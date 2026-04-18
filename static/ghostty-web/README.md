# ghostty-web bundle

Pinned copy of [ghostty-web](https://npmjs.com/package/ghostty-web) v0.3.0
(MIT, by coder/ghostty-web). Vendored so the Lisp server can serve a
self-contained page at /shell without reaching out to a CDN at runtime.

Upstream:

- https://github.com/coder/ghostty-web
- https://npmjs.com/package/ghostty-web

Files:

- `ghostty-web.js`        — ES module entrypoint (imported as `/static/ghostty-web/ghostty-web.js`)
- `ghostty-web.umd.cjs`   — UMD build (unused here, kept for parity)
- `ghostty-vt.wasm`       — WASM parser; `init()` loads this from the same directory
- `__vite-browser-external-2447137e.js` — vite shim referenced by the ES module
- `index.d.ts`            — TypeScript declarations (for reference)

To upgrade: `cp ~/ghostty-web/dist/* ~/ghostty-web/ghostty-vt.wasm static/ghostty-web/`
after bumping the ghostty-web npm package upstream.
