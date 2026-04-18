# case-container format: single-XLSX with embedded originals

Refs #13, #15.

## Hypothesis

Build one `.xlsx` per case that holds masters + manifests + matched results +
originals JPEGs losslessly embedded. JSON scatter is brittle; Excel is
portable and natively readable by construction admin users.

## Verification result

Empirically verified with `demo/xlsx-lossless-probe.py` + captured output
`demo/xlsx-lossless-probe.txt`.

- Source: 5 synthesized JPEGs (Pillow, quality=88, 640x480). Synthesis was
  chosen over real `~/apr2026-snapshot/` or `~/Downloads/` content to keep
  the committed `xlsx-lossless-probe.txt` PII-free. The script retains the
  real-directory fallback chain for local runs by the operator.
- Result: **5/5 PASS**. Every original's sha256 is present byte-for-byte
  under `xl/media/imageN.jpeg` inside the saved workbook.
- Sizes: originals total **69,597 B**, workbook **27,242 B** (overhead
  **-60.86 %**). The XLSX is smaller than the sum of originals because the
  outer ZIP deflates the XML metadata while leaving the already-compressed
  JPEGs untouched — i.e. openpyxl stores the JPEG bytes as-is, consistent
  with the lossless claim. Real production photos will push overhead back
  toward `~0 %` (originals dominate).
- `openpyxl.drawing.image.Image(path)` + `ws.add_image(img, anchor)` does
  **not** re-encode. The probe is reproducible; re-run changes only the
  temp-dir path.

## Sheet layout

One workbook per case. Suggested sheets (names stable, order fixed):

| Sheet           | Kind    | Content                                                                                            |
|-----------------|---------|----------------------------------------------------------------------------------------------------|
| `_Meta`         | kv      | case id, 工事名, date range, pipeline version, writer pid, schema_version, last_run_at (ISO-8601). |
| `Master_Work`   | table   | work-category master (工種 rows). Columns: `id, label_ja, parent_id, aliases`.                     |
| `Master_Role`   | table   | role master (役割 rows, e.g. 到着温度・敷均し温度). Columns: `id, label_ja, work_id, sort_order`.  |
| `Manifest`      | table   | scanned photos: `photo_id, path_rel, sha256, mtime_iso, exif_ts, machine_id, role_hint`.           |
| `Matched`       | table   | pipeline output: `photo_id, work_id, role_id, group_id, confidence, tiebreaker, matched_at`.       |
| `Reference`     | table   | GT from 正解写真帳: `photo_id, work_id, role_id, group_id, gt_notes`. Resolves #15 U1.            |
| `Photos`        | images  | one row per photo + embedded image anchor. Columns: `photo_id, basename, sha256, bytes, anchor`.   |

`photo_id` is the join key across all sheets. `Photos` is authoritative for
the embedded bytes; `Manifest` is the indexable view.

## Protocol

**Single writer, readers-many.**

- **Writer**: Lisp server, always. Skills (`photo-scan`, `photo-match-master`,
  etc.) that need to mutate the case emit JSON/edn to the Lisp writer over
  the existing CP byte pipe (#13); the Lisp writer is the only process that
  opens the `.xlsx` for write.
- **Concurrent write is banned.** Two agents mutating the same case XLSX
  is a bug class; guard with:
  - file-level advisory lock (`.case.xlsx.lock` sentinel, pid + timestamp)
    acquired before load, released after atomic rename.
  - atomic save: write to `case.xlsx.tmp`, fsync, `os.replace` to `case.xlsx`.
    Partial writes never reach readers.
- **Readers**: UI, skills, `gh`/`gemini`/`claude` panes, all open read-only.
  Readers tolerate a stale view and re-read on WebSocket `case-changed`
  push from the Lisp server.
- Maps to REQUIREMENTS.md §3 "last pipeline result pointer" — the pointer
  becomes `{case.xlsx path, schema_version, last_run_at}`.

## Size budget

Assumption: construction site photos ≈ 2–3 MB JPEG each. 500 photos ≈
1.0–1.5 GB. openpyxl loads the whole workbook into memory on write, which
makes 500+ photos painful even before Excel's own 1,048,576-row ceiling
becomes a concern.

Strategy (tiered):

1. **Default** — up to **200 photos / case**: embed originals in the
   `Photos` sheet. Expected workbook size ≤ 600 MB.
2. **Thumbs + sidecar** — at **>200 photos or >500 MB projected**: the
   `Photos` sheet embeds 512 px-long-edge thumbnails only; originals move
   to a sibling directory `<case>/originals/` and `Photos.sha256` becomes
   the authoritative link. The XLSX still round-trips losslessly for the
   thumbnails; originals are archived as raw files next to it.
3. **Hard cap** — switch to thumb-only when case XLSX **> 500 MB**. 500 MB
   is chosen because (a) Excel 2016+ opens it but starts stuttering on
   typical admin laptops (8 GB RAM), (b) openpyxl write RSS is roughly
   2× workbook size, and (c) git LFS default chunk crossings above 500 MB
   make even LFS painful. Number is coarse; revisit once a real 下無田-scale
   case is measured.

## Tool choice

Pick: **openpyxl (Python subprocess)** for v0.1. Revisit at tier-2 cutover.

| Tool                | Embed lossless | Speed  | Native toolchain fit                                 | Verdict                                                     |
|---------------------|----------------|--------|------------------------------------------------------|-------------------------------------------------------------|
| openpyxl (Python)   | yes (proved)   | slow   | photo-ai-skills already Python-first (`~/.agents/`)  | **chosen** — zero new deps                                  |
| excelize (Go)       | yes            | fast   | `photo-ai-go` exists in toolchain, Go installed      | strong tier-2 candidate when tier-1 hits perf ceiling       |
| rust_xlsxwriter     | yes            | fast   | Rust pieces (`photo-ai-rust`, `cli-ai-analyzer`)     | defer — more surface area than excelize for same win        |

Justification: the skill ecosystem (`photo-scan`, `photo-match-master`,
`photo-report-export`, etc.) is already Python+openpyxl. Introducing a
second XLSX engine for the case container before we have measured pain
is premature. If tier-2 (thumb-only + large cases) shows openpyxl write
time > 30 s, switch the writer to excelize — the case-XLSX schema is
engine-agnostic because it's just named sheets + anchored images.

## Git / versioning

XLSX is a binary ZIP and not usefully diffable.

Pick: **(a) do not commit `case.xlsx` to the repo.** Cases live outside
the repo, archived per-operator (local disk, then backup). The repo
commits only:

- probe scripts + schema docs (this issue),
- a **sanitized fixture** (1 synthetic case.xlsx with 3–5 synth JPEGs)
  under `tests/fixtures/case-sample.xlsx` for CI, generated by the probe.

Option (b) "commit binary, accept no diffs" fails on size alone at tier-1.
Option (c) "decompose to XML" defeats the portability win — the whole
point is that operators can open the file natively.

## What this resolves in #15

- **U1** (`reference.json` schema & cardinality): resolved as **a
  `Reference` sheet inside the case XLSX**, one row per `photo_id`, with
  `work_id / role_id / group_id / gt_notes`. Cardinality: one `Reference`
  sheet per case, not per run. Writers: `photo-reference-build`. Readers:
  `photo-match-master` (supervised signal), UI diff panel.
- **U2** (intermediate artifact placement): resolved as **inside the
  XLSX**. `matched.json`/`scope.json`/`groups.json` become the `Matched`
  sheet + a `groups` column + a `_Meta.scope` row. Per-run history is kept
  via `_Meta.last_run_at` and `Matched.matched_at`; older runs are
  appended to a `Matched_Archive` sheet when retention matters.
- **U5** (`~/apr2026-snapshot/` shape): resolved as **a `case.xlsx` with
  `Reference` pre-filled**. The snapshot becomes a single file + an
  `originals/` sibling, instead of scattered Excel+PDF. PII handling: the
  snapshot stays private; a synthesized `tests/fixtures/case-sample.xlsx`
  ships in CI.

## What this does NOT resolve

- **U3** — temperature-cycle resolution (main-line vs post-hoc). Orthogonal;
  this issue is storage, not pipeline ordering.
- **U4** — Gemini → Claude quota fallback. Orthogonal; this is scope-broker
  policy, lives in the Lisp writer's retry layer regardless of container.

## Acceptance criteria

1. `demo/xlsx-lossless-probe.py` exits 0, reports N/N PASS, sha256 round-trip
   matches on every embedded JPEG. **Met.**
2. A real-sized case (≥50 photos, 2–3 MB each) round-trips (scan → match →
   export → re-open) in ≤ 60 s on the operator's laptop. **Pending** —
   requires a real fixture post-U5.
3. Probe script wired into CI as a regression gate against openpyxl
   upgrades re-encoding images. **Pending** — follow-up issue.
4. Sanitized `tests/fixtures/case-sample.xlsx` checked in. **Pending** —
   follow-up issue (requires CI decision).
5. Lisp writer opens a `.case.xlsx.lock` sentinel before every write and
   releases on atomic rename. **Pending** — follow-up implementation
   issue once this proposal is accepted.
