1. Probe: 5/5 PASS — sha256 of every JPEG matches byte-for-byte under `xl/media/` of the saved XLSX (originals 69,597 B, xlsx 27,242 B, synth fixture).
2. Tool: **openpyxl (Python subprocess)** — photo-ai-skills is already Python+openpyxl; adding a second XLSX engine before measured pain is premature.
3. Size: embed originals up to **200 photos / 500 MB**, then flip to thumbnails-in-sheet + `originals/` sibling dir.
4. Resolves #15 **U1** (Reference sheet), **U2** (intermediates live inside XLSX), **U5** (snapshot = case.xlsx with Reference pre-filled).
5. Open: CI probe-regression gate, sanitized fixture commit, writer-side file lock + atomic-rename, real-case 60s acceptance run.
