# Issue #15 findings

Investigation date: 2026-04-19
Investigator: Codex (dispatched)

## Summary

U1, U2, U4, and U5 are answered from local primary sources. U3 is answered for the current skill-based workflow only in the negative: `photo-temperature-cycle-resolve` exists as a `matched.json` post-processor, but I did not find an orchestrator that auto-invokes it in the 7-skill pipeline, so any future UI behavior is still a product decision rather than an inherited contract.

## U1. reference.json schema and cardinality

### What I found

`photo-reference-build` is the clearest primary source. Its converter builds one root JSON object with `source_dir` and `records`, where each record is per-photo, not per-group: `file_name`, `source`, `source_path`, `captured_at`, `top`, and `extracted` are emitted in [`~/.agents/skills/photo-reference-build/scripts/build_reference.py`](C:/Users/yuuji/.agents/skills/photo-reference-build/scripts/build_reference.py:148). The CLI accepts `--xlsx`, `--pdf`, or `--matched`, and writes `{"source_dir": "...", "records": [...]}` in the same script at [lines 196](C:/Users/yuuji/.agents/skills/photo-reference-build/scripts/build_reference.py:196) and [257](C:/Users/yuuji/.agents/skills/photo-reference-build/scripts/build_reference.py:257).

The same script shows cardinality. `--matched` passes through an existing `matched.json` array and tags each item with `source = "ground_truth"` at [lines 234-239](C:/Users/yuuji/.agents/skills/photo-reference-build/scripts/build_reference.py:234). `--xlsx` creates one record per Excel row at [lines 241-243](C:/Users/yuuji/.agents/skills/photo-reference-build/scripts/build_reference.py:241), and optional PDF captions merge into those same per-photo records at [lines 245-255](C:/Users/yuuji/.agents/skills/photo-reference-build/scripts/build_reference.py:245).

I also found an actual generated example under `~/photo-ai-memory/runs/[REDACTED]/reference.json`. Its top-level shape is an array of per-photo entries with fields like `fileName`, `filePath`, `group`, `photoCategory`, `workType`, `variety`, `subphase`, `remarks`, and `detectedText`, which matches the older `AnalysisResult` family rather than a separate case-level schema. The older mirrored `AnalysisResult` struct in [`~/apr2026-snapshot/photo-ai-rust/photo-ai-go/internal/ai/parser.go`](C:/Users/yuuji/apr2026-snapshot/photo-ai-rust/photo-ai-go/internal/ai/parser.go:20) confirms those per-photo fields.

For consumers, the only concrete reader I found in the new skill stack is `photo-subagent-dispatch`: each task payload embeds `reference_json` alongside `photos`, `scope`, `master_csv`, and `result_path` in [`~/.agents/skills/photo-subagent-dispatch/scripts/build_payloads.py`](C:/Users/yuuji/.agents/skills/photo-subagent-dispatch/scripts/build_payloads.py:95). `photo-ai-workflow` also describes `reference_result.json` as future input to `photo-scope-infer` and `photo-keyword-extract`, but labels that path as "将来" and "未実装" in [`~/.agents/skills/photo-ai-workflow/SKILL.md`](C:/Users/yuuji/.agents/skills/photo-ai-workflow/SKILL.md:106).

### Answer

`reference.json` is one file per run/case folder, with many per-photo records inside it. I did not find evidence that the current skill stack uses a distinct case-container schema with group-level entries; the implemented shape is "root object plus per-photo records", and the only concrete downstream consumer today is dispatch payload generation.

### Implications for photo-ai-lisp

`photo-ai-lisp` should not assume a group-level or workbook-wide `reference.json` contract. For REQUIREMENTS.md sections about scope sharing and XLSX containers, the safe contract is "one case/run file that carries per-photo ground-truth-like records".

## U2. Intermediate artifact placement

### What I found

The skill docs describe a flat case-root layout, not an `out/` or hidden `.photo-ai/` directory. `photo-ai-workflow` explicitly shows `manifest.json`, `scope.json`, `photos.json`, `grouped.json`, `dispatch/task-NNN-groupX/`, `matched.json`, `report.xlsx`, and `photo_book.pdf` in a linear pipeline in [`~/.agents/skills/photo-ai-workflow/SKILL.md`](C:/Users/yuuji/.agents/skills/photo-ai-workflow/SKILL.md:28).

The actual scripts mostly match that flat layout. `photo-scan` writes a manifest JSON file described in [`~/.agents/skills/photo-scan/scripts/scan.py`](C:/Users/yuuji/.agents/skills/photo-scan/scripts/scan.py:1). `photo-group-assign` writes a JSON with `group` annotations; its default filename is `groups.json` if no `--out` is supplied, even though the workflow doc calls the step output `grouped.json`, as shown in [`~/.agents/skills/photo-group-assign/scripts/group_assign.py`](C:/Users/yuuji/.agents/skills/photo-group-assign/scripts/group_assign.py:16). `photo-match-master` writes `matched.json`-style output at [`~/.agents/skills/photo-match-master/scripts/match.py`](C:/Users/yuuji/.agents/skills/photo-match-master/scripts/match.py:182). `photo-temperature-cycle-resolve` defaults to `<matched stem>_cycle_resolved.json`, not `temperature-cycle.json`, in [`~/.agents/skills/photo-temperature-cycle-resolve/scripts/resolve_cycles.py`](C:/Users/yuuji/.agents/skills/photo-temperature-cycle-resolve/scripts/resolve_cycles.py:251). `photo-report-export` requires explicit output file paths for Excel/PDF in [`~/.agents/skills/photo-report-export/scripts/export.py`](C:/Users/yuuji/.agents/skills/photo-report-export/scripts/export.py:207).

Older `photo-ai-go` also writes flat-at-root by default. `result.json` is the canonical intermediate/final JSON name in [`~/photo-ai-go/internal/export/json.go`](C:/Users/yuuji/photo-ai-go/internal/export/json.go:12) and defaults to `<folder>/result.json` at [lines 55-57](C:/Users/yuuji/photo-ai-go/internal/export/json.go:55). `photo-tagger` uses `<folder>/photo-groups.json` in [`~/photo-ai-go/pkg/tagger/tagger.go`](C:/Users/yuuji/photo-ai-go/pkg/tagger/tagger.go:27) and [`~/photo-ai-go/pkg/tagger/fsops.go`](C:/Users/yuuji/photo-ai-go/pkg/tagger/fsops.go:12). The CLI also defaults pairing output to `<dir>/paired.json` in [`~/photo-ai-go/cmd/photo-ai-cli/main.go`](C:/Users/yuuji/photo-ai-go/cmd/photo-ai-cli/main.go:153).

For "how does the UI/operator find the latest run", I found two mechanisms. The Go server chooses `<folder>/result.json` when the request omits `Output` in [`~/photo-ai-go/cmd/photo-ai/serve.go`](C:/Users/yuuji/photo-ai-go/cmd/photo-ai/serve.go:1089). The older snapshot web UI persists the chosen result path in browser state via `localStorage.setItem('photoai_result_path', currentResultPath)` and restores it later in [`~/apr2026-snapshot/photo-ai-rust/web/index.html`](C:/Users/yuuji/apr2026-snapshot/photo-ai-rust/web/index.html:1651). I did not find an archive index or timestamped run registry.

### Answer

The dominant layout is flat at the case root, with dispatch subdirectories only for fan-out work. Canonical names that are actually implemented are `manifest.json`, `photo-groups.json` or caller-chosen `grouped.json`, `matched.json`, `result.json`, `paired.json`, and `<matched stem>_cycle_resolved.json`; I found no evidence of a standard `.photo-ai/`, `out/`, or timestamped archive layout.

### Implications for photo-ai-lisp

The UI should model "current artifact paths" rather than assume a managed run-history directory. If `photo-ai-lisp` needs archives, that would be a new design, not something inherited from the existing tools.

## U3. Temperature-cycle pipeline position

### What I found

`photo-temperature-cycle-resolve` presents itself as a `matched.json` post-processor. Its own skill file says it operates "on top of `photo-match-master` output" and that it is in the same "matched.json 後処理" family as `photo-pair-resolve` in [`~/.agents/skills/photo-temperature-cycle-resolve/SKILL.md`](C:/Users/yuuji/.agents/skills/photo-temperature-cycle-resolve/SKILL.md:6) and [lines 85-93](C:/Users/yuuji/.agents/skills/photo-temperature-cycle-resolve/SKILL.md:85). The same document says the two post-processors have non-overlapping targets and "順序は任意" at [line 92](C:/Users/yuuji/.agents/skills/photo-temperature-cycle-resolve/SKILL.md:92).

The implementation matches that framing. The resolver script takes `matched.json` plus `master.csv`, and writes `matched_cycle_resolved.json` in [`~/.agents/skills/photo-temperature-cycle-resolve/scripts/resolve_cycles.py`](C:/Users/yuuji/.agents/skills/photo-temperature-cycle-resolve/scripts/resolve_cycles.py:1). Its CLI is standalone and default output is a sibling file, not an in-place hidden phase, at [`resolve_cycles.py:251`](C:/Users/yuuji/.agents/skills/photo-temperature-cycle-resolve/scripts/resolve_cycles.py:251).

The 7-skill orchestrator does not include this step in its main pipeline table. `photo-ai-workflow` stops at `photo-match-master` then `photo-report-export` in [`~/.agents/skills/photo-ai-workflow/SKILL.md`](C:/Users/yuuji/.agents/skills/photo-ai-workflow/SKILL.md:34). I did not find a workflow script or Go CLI entrypoint in the current skill-oriented tooling that auto-runs `photo-temperature-cycle-resolve` when scope indicates 温度管理.

There is an older, different lineage in snapshot Rust code: `photo-ai-rust/src/temperature.rs` contains built-in temperature repair functions. That shows temperature handling existed inside the older engine, but it does not prove the new skill named `photo-temperature-cycle-resolve` is auto-chained.

### Answer

For the current skill-based workflow, `photo-temperature-cycle-resolve` is post-hoc, not part of the documented mainline. I found no evidence that it is called unconditionally after `photo-match-master`, and no evidence that scope detection auto-triggers it; the safe reading is "optional/manual post-process for temperature cases".

### Implications for photo-ai-lisp

If `photo-ai-lisp` wants this behavior in the UI, it has to choose it explicitly: hidden auto-trigger, visible button, or separate command. The existing skill docs do not supply a preexisting UI contract.

## U4. Gemini→Claude quota fallback

### What I found

The current wrapper layer does handle Gemini auth mode, but not backend failover. `cli-ai-analyzer` strips `GEMINI_API_KEY`, `GOOGLE_API_KEY`, and `GOOGLE_GENAI_API_KEY` unless `CLI_AI_ANALYZER_USE_API_KEY=1`, so Gemini CLI falls back to OAuth / Code Assist quotas in [`~/cli-ai-analyzer/internal/gemini/cli.go`](C:/Users/yuuji/cli-ai-analyzer/internal/gemini/cli.go:53). The same file injects that environment into both Windows and Unix subprocesses at [lines 96-104](C:/Users/yuuji/cli-ai-analyzer/internal/gemini/cli.go:96) and [129-134](C:/Users/yuuji/cli-ai-analyzer/internal/gemini/cli.go:129).

The snapshot `cli-ai-analyzer` supports multiple backends, but the backend is chosen up front. `run_ai` dispatches by `request.backend` and `request.usage_mode` in [`~/apr2026-snapshot/cli-ai-analyzer/src/executor.rs`](C:/Users/yuuji/apr2026-snapshot/cli-ai-analyzer/src/executor.rs:158). Gemini, Claude, and Codex have separate execution branches at [lines 196-223](C:/Users/yuuji/apr2026-snapshot/cli-ai-analyzer/src/executor.rs:196). I did not find code that catches a Gemini quota failure and automatically reruns the same request on Claude.

Quota detection is string-based. `GeminiStats::from_error()` marks failures when stderr contains "rate", "quota", or "429", and optionally extracts retry seconds in [`~/apr2026-snapshot/cli-ai-analyzer/src/executor.rs`](C:/Users/yuuji/apr2026-snapshot/cli-ai-analyzer/src/executor.rs:1276). The older Go Gemini REST client in [`~/photo-ai-go/internal/ai/client.go`](C:/Users/yuuji/photo-ai-go/internal/ai/client.go:18) retries Gemini-on-Gemini for 429/5xx, but also does not escalate to Claude.

The human memory files match the code. `feedback_no_api_key_default.md` and `reference_cli_ai_analyzer_auth.md` point to OAuth-default behavior, and `feedback_photo_pipeline_use_gemini_default.md` says Gemini CLI is the default AI path while Claude/Opus should not be used for direct observe loops. None of those memory files describe an implemented automatic Gemini→Claude handoff.

### Answer

Retry ownership is in the wrapper/client layer, but backend fallback is not automated. Quota is detected mainly from stderr text patterns and rate-limit messages; the current behavior is "use OAuth by default, retry within Gemini when supported, otherwise fail and require the caller to choose another backend manually".

### Implications for photo-ai-lisp

`photo-ai-lisp` should not assume there is an inherited automatic Gemini→Claude safety net. If the product needs backend failover, that logic has to be designed explicitly in Lisp-side orchestration.

## U5. ~/apr2026-snapshot/ provenance and PII

### What I found

The snapshot readme states that `~/apr2026-snapshot/` reproduces the state around 2026-04-14 for a specific ground-truth run, and points to a concrete ground-truth JSON file and 2026-03-31 capture date in [`~/apr2026-snapshot/README-snapshot.md`](C:/Users/yuuji/apr2026-snapshot/README-snapshot.md:1). The top-level contents are `photo-ai-rust/`, `photo-tagger/`, `cli-ai-analyzer/`, and `README-snapshot.md`; this is a code snapshot with artifacts, not a minimal fixture pack.

Inside the snapshot, I found `photo-ai-rust/result.json` and other result artifacts, but I did not find a committed `reference.json` in snapshot root. That means the snapshot is closer to "raw repos plus result JSONs" than "already normalized reference-builder output".

PII risk is real, not hypothetical. The snapshot readme itself includes real location/designator text in the GT path in [`README-snapshot.md:19`](C:/Users/yuuji/apr2026-snapshot/README-snapshot.md:19). The memory note [`~/.claude/projects/C--Users-yuuji/memory/feedback_pii_in_public_repos.md`](C:/Users/yuuji/.claude/projects/C--Users-yuuji/memory/feedback_pii_in_public_repos.md:7) explicitly warns that public repos must not contain real project names, company names, place names, person names, or work-zone designators, and calls out snapshot-related leakage as a real incident.

### Answer

`~/apr2026-snapshot/` is a reproduction snapshot for one real April 2026 GT case, not a sanitized fixture package. It contains real-world identifiers and should be treated as PII-bearing source material; it is not safe to copy into `photo-ai-lisp` as-is.

### PII assessment

Yes, the snapshot contains PII or project-identifying metadata. The first safe CI fixture would have to be a sanitized synthetic subset: a tiny case with renamed files, redacted paths, redacted OCR text, neutralized remarks/stations, and no real client/site/work-zone names.

## Cross-cutting notes

The existing ecosystem uses two nearby but different families of JSON. The skills-side `reference.json` work is "ground-truth-like per-photo records plus optional root metadata", while the older `AnalysisResult` / `result.json` line is the operational analysis output used by Go/Rust exporters and web UI state.

The skill docs are not perfectly aligned on filenames. `photo-ai-workflow` says `grouped.json`, but the standalone group-assign script defaults to `groups.json`; `photo-report-export` also does not enforce the exact `report.xlsx` / `photo_book.pdf` names shown in the docs.

## What still blocks REQUIREMENTS.md §5

The remaining open point is UI/product policy, not source discovery: whether temperature-cycle resolution should be exposed as an explicit action or silently auto-run for temperature-scoped cases. I did not find an inherited workflow contract that settles that decision for `photo-ai-lisp`.
