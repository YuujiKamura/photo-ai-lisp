# PhotoAISkills CLI contracts

Probed 2026-04-18. Run each command with `--help` to verify; this document
records the observed shape, not an invented one.

All scripts live under `~/.agents/skills/photo-*/scripts/`.  
`python` here means whichever Python 3 interpreter is on PATH (Windows: may
need `python3` or the full path).

---

## photo-scan

**Script:** `photo-scan/scripts/scan.py`  
**Purpose:** Walk a photo directory, collect metadata (file, date, dimensions).
Optionally run tesseract OCR.

```
python scan.py [--ocr] [--out OUT] root
```

| param | type | required | default | notes |
|---|---|---|---|---|
| `root` | positional | yes | — | photo directory |
| `--ocr` | flag | no | off | runs tesseract on each photo |
| `--out` | path | no | `-` (stdout) | output JSON array |

**Output channel:** JSON array → stdout or file  
**Exit codes:** 0 = success  
**stderr:** progress/count summary when writing to file

---

## photo-scope-infer

**Script:** `photo-scope-infer/scripts/contact_sheet.py`  
**Purpose:** Build a contact-sheet JPEG from manifest. The AI agent then reads
this image + manifest to write `scope.json` — the script only generates the
image.

```
python contact_sheet.py [--n N] [--cols COLS] [--cell CELL] [--out OUT] manifest
```

| param | type | required | default | notes |
|---|---|---|---|---|
| `manifest` | positional | yes | — | manifest.json from photo-scan |
| `--n` | int | no | 16 | number of photos to sample |
| `--cols` | int | no | 4 | columns in the contact sheet |
| `--cell` | int | no | 400 | cell width in pixels |
| `--out` | path | no | `contact.jpg` | output JPEG path |

**Output channel:** JPEG file (not JSON, not stdout)  
**Exit codes:** 0 = success  
**stderr:** size/count summary  
**Note:** scope.json is written by the LLM agent that reads `contact.jpg`; this
script does not produce JSON.

---

## photo-keyword-extract

**Script:** none — AI-only skill  
**Purpose:** Extract machine_type (object) and role (action) from photos,
using group context from `grouped.json`. Emits JSON per photo.

No Python script exists. The agent reads `grouped.json` produced by
`photo-group-assign`, looks at each photo in group context, and writes the
output JSON directly.

**Input:** `grouped.json` (photo-group-assign output)  
**Output:** JSON array written by the agent (no CLI invocation)

---

## photo-category-derive

**Script:** `photo-category-derive/scripts/derive_category.py`  
**Purpose:** Deterministically derive `photo_category` from `role`,
`detected_text`, and `description`.

```
python derive_category.py [--preset PRESET] [--extra EXTRA] [--out OUT] photos_json
```

| param | type | required | default | notes |
|---|---|---|---|---|
| `photos_json` | positional | yes | — | output of photo-keyword-extract |
| `--preset` | choice | no | `general` | `pavement`, `marking`, `general`, `none` |
| `--extra` | path | no | — | JSON file with additional `{keyword: category}` aliases |
| `--out` | path | no | `-` (stdout) | output JSON array |

**Output channel:** JSON array → stdout or file  
**Exit codes:** 0 = success  
**stderr:** count + conflict count when writing to file

---

## photo-group-assign

**Script:** `photo-group-assign/scripts/group_assign.py`  
**Purpose:** Assign `group` integer to each photo record using machine_id +
capture-time gap + attachment flag.

```
python group_assign.py [--gap GAP] [--out OUT] photos_json
```

| param | type | required | default | notes |
|---|---|---|---|---|
| `photos_json` | positional | yes | — | output of photo-keyword-extract |
| `--gap` | int (seconds) | no | 300 | gap between captures before splitting group |
| `--out` | path | no | `-` (stdout) | output JSON array (adds `group` field) |

**Output channel:** JSON array → stdout or file  
**Exit codes:** 0 = success  
**stderr:** record count + group count when writing to file

---

## photo-subagent-dispatch

**Script:** `photo-subagent-dispatch/scripts/build_payloads.py`  
**Purpose:** Split `grouped.json` into per-group (or per-chunk) task
directories for parallel agent execution.

```
python build_payloads.py \
  --grouped GROUPED --scope SCOPE --master MASTER --out-dir OUT_DIR \
  [--reference REFERENCE] [--mode {group,chunk}] [--chunk-size CHUNK_SIZE]
```

| param | type | required | default | notes |
|---|---|---|---|---|
| `--grouped` | path | yes | — | grouped.json from photo-group-assign |
| `--scope` | path | yes | — | scope.json from photo-scope-infer |
| `--master` | path | yes | — | master CSV |
| `--out-dir` | path | yes | — | directory to write task folders into |
| `--reference` | path | no | — | reference_result.json (optional prior) |
| `--mode` | choice | no | `group` | `group` or `chunk` |
| `--chunk-size` | int | no | 20 | photos per chunk (only with `--mode chunk`) |

**Output channel:** writes `<out-dir>/task-NNN-groupX/` folders + `INDEX.json`  
**Exit codes:** 0 = success  
**stderr:** task count summary

---

## photo-match-master

**Script:** `photo-match-master/scripts/match.py`  
**Purpose:** Deterministic keyword match against master CSV, optionally
filtered by scope.

```
python match.py [--top TOP] [--scope SCOPE] [--out OUT] photos_json master_csv
```

| param | type | required | default | notes |
|---|---|---|---|---|
| `photos_json` | positional | yes | — | output of photo-keyword-extract (or photo-group-assign) |
| `master_csv` | positional | yes | — | master CSV with 検索パターン column |
| `--top` | int | no | — | keep top-N candidates per photo |
| `--scope` | path | no | — | scope.json to narrow master rows |
| `--out` | path | no | `-` (stdout) | output JSON array |

**Output channel:** JSON array → stdout or file  
**Exit codes:** 0 = success  
**stderr:** total + matched count when writing to file

---

## photo-pair-resolve

**Script:** `photo-pair-resolve/scripts/resolve_pairs.py`  
**Purpose:** Resolve composite-blackboard pairs in `matched.json`, ordering
photos within each group.

```
python resolve_pairs.py [--out OUT] [--sort-by {file_name,captured_at}] matched_json master_csv
```

| param | type | required | default | notes |
|---|---|---|---|---|
| `matched_json` | positional | yes | — | output of photo-match-master |
| `master_csv` | positional | yes | — | master CSV |
| `--out` | path | no | `<matched>_pair_resolved.json` | output path |
| `--sort-by` | choice | no | `file_name` | `file_name` or `captured_at` |

**Output channel:** JSON file (default derived from input filename)  
**Exit codes:** 0 = success

---

## photo-temperature-cycle-resolve

**Script:** `photo-temperature-cycle-resolve/scripts/resolve_cycles.py`  
**Purpose:** Resolve temperature measurement cycles (arrival / spreading /
compaction / release stages) in `matched.json`.

```
python resolve_cycles.py \
  [--block-size N] [--stages STAGES] [--release-stage STAGE] \
  [--temp-ranges RANGES] [--out OUT] \
  matched_json master_csv
```

| param | type | required | default | notes |
|---|---|---|---|---|
| `matched_json` | positional | yes | — | output of photo-match-master |
| `master_csv` | positional | yes | — | master CSV |
| `--block-size` | int | no | 9 | photos per temperature block |
| `--stages` | str | no | `到着温度,敷均し温度,初期締固前温度` | comma-separated stage names |
| `--release-stage` | str | no | `開放温度` | release/opening stage name |
| `--temp-ranges` | str | no | `到着温度:150-180,...` | colon-separated name:min-max pairs |
| `--out` | path | no | `<matched>_cycle_resolved.json` | output path |

**Output channel:** JSON file (default derived from input filename)  
**Exit codes:** 0 = success

---

## photo-reference-build

**Scripts:** `photo-reference-build/scripts/build_reference.py` and
`photo-reference-build/scripts/diff_reference.py`

### build_reference.py

Build a `reference_result.json` from an existing photo book (xlsx, pdf, or
matched.json) to serve as ground truth.

```
python build_reference.py \
  [--xlsx XLSX] [--pdf PDF] [--matched MATCHED] \
  [--master MASTER] [--source-dir DIR] [--allow-missing-source-dir] \
  --out OUT
```

| param | type | required | default | notes |
|---|---|---|---|---|
| `--out` | path | **yes** | — | output reference_result.json |
| `--xlsx` / `--pdf` / `--matched` | path | at least one | — | input source (book or matched.json) |
| `--master` | path | no | — | master CSV for validation |
| `--source-dir` | path | no | — | original photo folder to pair with book |
| `--allow-missing-source-dir` | flag | no | off | suppress warning when --source-dir omitted |

**Output channel:** JSON file at `--out`  
**Exit codes:** 0 = success, 1 = no input source provided  
**Note:** `--help` crashes on Windows cp932 console (em-dash in help text
triggers `UnicodeEncodeError`); use `grep add_argument` to inspect args.

### diff_reference.py

Diff a reference_result.json against a matched.json.

```
python diff_reference.py [--fields FIELDS] [--out OUT] reference matched
```

| param | type | required | default | notes |
|---|---|---|---|---|
| `reference` | positional | yes | — | reference_result.json |
| `matched` | positional | yes | — | matched.json to compare |
| `--fields` | str | no | — | comma-separated hierarchy columns to compare |
| `--out` | path | no | — | if set, write JSON report; otherwise stdout |

**Output channel:** JSON → stdout or file  
**Exit codes:** 0 = success

---

## photo-report-export

**Script:** `photo-report-export/scripts/export.py`  
**Purpose:** Export `matched.json` to xlsx and/or PDF photo book.

```
python export.py [--xlsx XLSX] [--pdf PDF] [--title TITLE] matched_json
```

| param | type | required | default | notes |
|---|---|---|---|---|
| `matched_json` | positional | yes | — | output of photo-match-master (or pair-resolve) |
| `--xlsx` | path | no | — | output xlsx path |
| `--pdf` | path | no | — | output PDF path |
| `--title` | str | no | `""` | 工事名 title string for the report |

**Output channel:** .xlsx and/or .pdf files (specify at least one)  
**Exit codes:** 0 = success  
**Note:** `--help` shows mojibake on Windows cp932 console; title arg is fine
when passed at runtime.

---

## photo-ai-workflow

**Script:** none — orchestration SKILL.md only  
**Purpose:** Describes the 7-step pipeline that chains the above skills.
No Python script; this is a guide for the orchestrating agent.

---

## Skills without scripts (AI-only)

| skill | reason |
|---|---|
| `photo-keyword-extract` | Agent reads photos and grouped.json directly |
| `photo-ai-workflow` | Pipeline orchestration guide — no executable |

---

## Common patterns

- `--out -` or omitting `--out`: most JSON-emitting scripts default to stdout.
- `--out PATH`: write to file; script prints summary to stderr.
- contact_sheet.py is the exception: default `--out contact.jpg` writes a JPEG, never stdout JSON.
- build_reference.py and diff_reference.py are in `photo-reference-build/scripts/`, two files in one skill.
- photo-pair-resolve and photo-temperature-cycle-resolve derive their default output filename from the input: `<input-stem>_pair_resolved.json` / `_cycle_resolved.json`.
