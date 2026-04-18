# 3bst Reference — Patterns to Steal

Source: https://github.com/3b/3bst — a working CL port of suckless `st`
(1876 lines). Cloned locally at `~/reference/3bst/`.

Use this as a cheat sheet while implementing Phase 5. Do not copy verbatim
— 3bst is GPL-ish and our scope is narrower. Lift *shapes* and *gotchas*.

---

## 1. Screen storage: vector-of-vectors, not 2D array

```lisp
;; st.lisp:313
(defun make-screen-array (rows columns)
  (make-array rows
              :element-type '(vector glyph *)
              :initial-contents
              (loop repeat rows
                    collect (coerce
                             (loop repeat columns
                                   collect (make-instance 'glyph))
                             '(vector glyph)))))
```

**Why it matters for us**: scrolling becomes `(rotatef (aref screen i)
(aref screen j))` — O(1) line swap. With a true 2D array
`(make-array (list rows cols))` you'd have to copy every cell on every
scroll.

**5e.5 `:lf` at bottom**: steal this. Before scroll-on-lf lands, our
`screen-buffer` is a 2D array and row rotation requires a copy loop.
If 5d/5e.5 land before we refactor, that's fine — but flag a TODO to
swap storage to vector-of-vectors before scrollback perf matters.

---

## 2. Dirty-bit-per-row

```lisp
;; st.lisp:380
(setf (slot-value term 'dirty)
      (make-array (rows term) :element-type 'bit))
```

Every mutation (`tputc`, `tclearregion`, `tscroll*`) flips the dirty bit
on affected rows. Renderer iterates dirty rows only.

**For 5g (screen->html)**: not needed for correctness but trivial to add
and turns O(rows×cols) render into O(dirty_rows×cols). Worth a
follow-up after 5g lands.

---

## 3. Tab stops as bit vector

```lisp
;; st.lisp:382
(setf (slot-value term 'tabs)
      (make-array (columns term) :element-type 'bit))
;; treset:
(loop for i from *tab-spaces* below (columns term) by *tab-spaces*
      do (setf (aref (tabs term) i) 1))
```

**5e.5 `:ht`**: instead of hardcoding "every 8", maintain a tab-stops
bit vector on the screen. Next-tab = `(position 1 tabs :start (1+ col))`.
This future-proofs CSI `H` (set tab stop) and CSI `g` (clear).

For 5e.5 minimum: hardcoded every-8 is fine. Leave a comment pointing
here.

---

## 4. Attribute bitmask vs booleans

```lisp
;; 3bst bindings.lisp — single integer, bits for bold/italic/underline/
;; blink/reverse/invisible/struck/wrap/wide/wdummy
(defconstant +attr-bold+      #b00000001)
(defconstant +attr-underline+ #b00010000)
(defconstant +attr-wrap+      #b1000000000)   ;; line-continuation marker
(defconstant +attr-wide+      #b10000000000)  ;; CJK double-width first half
```

Ops: `logior` to set, `logandc2` to clear, `logtest` to check.

**Our current `cell` struct has booleans** (`bold`, `underline`, `reverse`).
That's fine for 5e.4b. Bitmask is a polish-phase refactor — not
blocking.

**Do steal `+attr-wrap+`**: a per-cell flag saying "this line continues
onto the next row". Required for correct CJK / long-line behavior and
`(screen->text)` joining. We don't need it for Phase 5 minimum but if
text snapshots come out wrong on line boundaries, this is why.

---

## 5. `tclearregion` uses cursor's current bg/fg, NOT default

```lisp
;; st.lisp:634
(defun tclearregion (x1 y1 x2 y2 ...)
  ...
  (setf (fg g) (fg (attributes (cursor term)))
        (bg g) (bg (attributes (cursor term)))
        (mode g) 0
        (c g) #\space))
```

**GOTCHA for 5e.3 (erase-display / erase-line)**: the brief says "fill
target cells with default cell (reset attrs) at each position." That's
wrong for real terminals. Try `ESC[41m ESC[2J` — a conformant emulator
paints the screen red, not resets it. 3bst clears `mode` to 0 but
keeps the current cursor's fg/bg.

Recommended 5e.3 behavior: erase = space char, mode cleared, but
fg/bg inherit cursor's current attrs. Document the deviation if you
go strict-reset instead.

---

## 6. `move-glyphs` for insert/delete/scroll within a line

```lisp
;; st.lisp:232
(defun move-glyphs (line &key (start1 0) (start2 0) (end1 ...) (end2 ...))
  (if (<= start1 start2)
      (loop for i from start1 below end1 ...)       ;; forward
      (loop for i from (1- end1) downto start1 ...))) ;; reverse for overlap
```

Copies cell *contents* (not references) with overlap-safe direction.
Relevant if/when we add CSI `P` (delete chars) or `@` (insert blank).

Not Phase 5. But if 5e.5 + scrollback hits "insert line" territory,
this is the shape.

---

## 7. SGR parameter walking

```lisp
;; st.lisp:711
(defun tsetattr (attributes ...)
  (loop for i = 0 then (1+ i)
        while (< i (length attributes))
        do (flet ((on  (&rest a) (setf (mode attr) (apply #'logior ...)))
                  (off (&rest a) (setf (mode attr) (logandc2 ...))))
             (case (aref attributes i)
               (0  (off +attr-bold+ +attr-faint+ ...) ...)
               (1  (on  +attr-bold+))
               (22 (off +attr-bold+ +attr-faint+))
               (38 (multiple-value-bind (index next-i)
                       (tdefcolor attributes i)
                     (setf (fg attr) index
                           i next-i)))
               ...))))
```

**Comparison with our 5e.4a**: we already use a plist (`(:bold t)`,
`(:fg 5)`) and handle `38 5 N`. Our parser is cleaner than theirs
for shallow cases. 3bst is worth reading for:

- `22` = bold-OFF + faint-OFF (turns off both). We handle only bold.
  Faint isn't in our cell struct — fine, note it as a gap.
- `38 2 R G B` = truecolor RGB. Our parser doesn't handle mode `2`.
  Add `(:fg (:rgb R G B))` emission if we want truecolor later.
- `tdefcolor` returns `(values index next-i)` — the advance-index
  idiom for variable-length sub-sequences. If we ever inline 38/48
  parsing into a non-plist walker, steal this shape.

---

## 8. `tnewline` = scroll when at bottom

```lisp
;; st.lisp:529
(defun tnewline (first-column ...)
  (let ((y (y (cursor term))))
    (if (= y (bottom term))
        (tscrollup (top term) 1 ...)   ;; scroll, stay at same y
        (incf y))
    (tmoveto (if first-column 0 (x (cursor term))) y ...)))
```

**For 5e.5 `:lf`**: this is the canonical shape. At bottom → scroll up
by 1 within the scroll region `[top..bottom]`. Pushing the top line
into scrollback is *separate* — 3bst doesn't even have scrollback in
core. Our 5d is the scrollback layer; 5e.5 should just call the
scroll-region primitive 37928 exposes.

Don't conflate "scroll-on-lf" with "push to scrollback". The first
is CSI/ECMA; the second is a UX feature we add on top.

---

## 9. Single entry point

```lisp
;; st.lisp:419
(defun handle-input (characters &key (term *term*))
  (let ((*term* term))
    (map 'nil #'tputc characters)))
```

Clean. One function, dynamic-bound `*term*` so `tputc` and all its
callees don't need to thread the term object. We've chosen explicit
`screen` passing (which is better for testability) but the pattern
confirms the shape of `(apply-events screen events)` → `(apply-event
screen event)` fan-out.

---

## 10. `csi-escape` / `str-escape` classes

```lisp
;; st.lisp:283
(defclass csi-escape ()
  ((buffer :accessor buffer :initform (make-array 8 :adjustable t
                                                  :fill-pointer 0
                                                  :element-type 'character))
   (priv :accessor priv :initform nil)          ;; ? prefix flag
   (arguments :accessor arguments ...)
   (mode :accessor mode :initform 0)))          ;; final byte
```

**Our `ansi-parser`** already has equivalent `params` / `current-param`
/ `collected-bytes`. The detail to steal is the `priv` slot: DEC
private modes (`ESC[?25h` show cursor, `ESC[?1049h` alt screen) are
common in real apps. We currently emit `:unknown` for these. If we
wire that up, parser should record `priv` = T when the first param
byte is `?`.

Not blocking Phase 5. Note it for Phase 6/7 when real shells feed
us private sequences.

---

## Summary — what to apply during Phase 5

| Task | Apply | How |
|------|-------|-----|
| 5e.3 erase | **yes** | Use cursor's bg/fg, not default cell. |
| 5e.4b apply SGR | partial | Our plist output → cursor attrs already. Note `22` = bold+faint. |
| 5e.5 `:lf` | shape | Scroll-region primitive, separate from scrollback. |
| 5e.5 `:ht` | defer | Hardcoded every-8 for now; tab-stop bitvec later. |
| 5g html | defer | Add dirty-row optimization in polish phase. |

## Later (post-Phase-5)

- Bitmask attrs, `+attr-wrap+`, `+attr-wide+` for CJK / line continuation.
- DEC private modes via `priv` flag.
- Truecolor `38 2 R G B`.
- Vector-of-vectors screen storage (for O(1) scroll).
- Dirty-bit-per-row (for incremental render).

All optional. Ship Phase 5 first.
