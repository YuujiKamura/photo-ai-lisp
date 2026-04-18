# photo-ai-lisp

![test](https://github.com/YuujiKamura/photo-ai-lisp/actions/workflows/test.yml/badge.svg)

photo-ai-lisp is a Common Lisp construction photo manifest management app. It is a small public prototype aimed at managing photo-oriented manifest data with a simple Lisp-first stack rather than a conventional deploy-heavy web workflow.

The project explores a REPL-driven, hot-reloading development style: write into a running server from the REPL, skip a separate deploy step during development, and generate HTML through S-expressions. The goal is to make that style of personal web application development comfortable using modern Common Lisp tooling.

This repository also doubles as a practical Common Lisp learning project applied to a real (if tiny) web application rather than isolated exercises. The initial stack is SBCL, Hunchentoot, and cl-who, kept deliberately small so the runtime editing loop stays easy to understand.

## Local Development

Install SBCL and Quicklisp first. On Windows, `choco install sbcl` is the simplest native path; for a smoother Lisp workflow, WSL is also a reasonable option. On macOS, `brew install sbcl` works. Then download the Quicklisp installer: `curl -O https://beta.quicklisp.org/quicklisp.lisp`, start SBCL with `sbcl --load quicklisp.lisp`, then run `(quicklisp-quickstart:install)` and `(ql:add-to-init-file)`.

Make the project visible to Quicklisp by cloning or symlinking this repository into `~/quicklisp/local-projects/`. Then start SBCL and run `(ql:quickload :photo-ai-lisp)` followed by `(photo-ai-lisp:start)`. The app will be available at <http://localhost:8080>.

The intended development loop is live REPL editing: redefine functions from the REPL while the server is running, reload the browser, and immediately see the new behavior without a separate build or deploy step. SLIME, Sly, or Alive all fit this workflow well and make the edit-eval-refresh cycle much more comfortable.

## The REPL front page

`GET /` is not a CRUD table — it is an in-browser Lisp REPL bound to the running SBCL image. Type an expression, hit Enter, and the form is `read` + `eval`'d inside the `photo-ai-lisp` package with `*standard-output*` captured. The response is rendered back into a scrolling history:

    > (+ 1 2)
    3
    > (length (all-photos))
    1
    > (defun greet (n) (format nil "hi ~A" n))
    GREET
    > (greet "lisp")
    "hi lisp"

Definitions persist across requests because the eval happens in the same image the server runs in — redefine a handler or a helper and the next request picks it up. The old photo table still lives at `/photos`.

### Safety

- `/eval` refuses any request whose `remote-addr` is not `127.0.0.1` / `::1` and returns `403`.
- The page carries a conspicuous "Local dev only" banner. Do not expose this server on a public host — `/eval` runs arbitrary Lisp against your image.
- No auth, no sandbox, no quota. This is a single-developer live-edit environment, not a shared service.

### API

`POST /eval` with form body `expr=<lisp-form>` returns JSON:

- Success: `{"ok":true,"value":"<prin1-of-result>","stdout":"<captured-output>"}`
- Failure (read error, runtime condition, etc.): `{"ok":false,"error":"<principal-message>"}` with HTTP 200.

## Persistence

Photos are saved to `~/.photo-ai-lisp/photos.store` via `cl-store` on every mutation. The store is loaded automatically on start. Delete that file to reset the local state.

## Templating

The layout macro wraps every page with a shared header, nav, and footer. Redefine it at the REPL and reload the browser to see the change live without restarting. Example: `(defmacro layout (title &body body) ...)` any redefinition takes effect immediately across all handlers.

## Skill integration

Skills under `~/.agents/skills/` are invoked via `(run-skill "photo-scan" dir)`. The layer finds the `.py` script, runs it with python, captures stdout as JSON (`yason`), and signals `skill-error` on non-zero exit.

## Running a scan

Navigate to `/scan`, enter a directory path containing JPEG photos, and click Scan. The `photo-scan` skill (Python) walks the directory, extracts EXIF dates, and returns a JSON manifest. Results appear at `/manifest` as a browsable table.

## Full pipeline

Navigate to `/pipeline`, enter a photo directory, and click Run. Steps: `photo-scan` (EXIF manifest), `photo-scope-infer` (contact sheet JPEG), `photo-match-master` (master CSV matching), Rust export (PDF+Excel). Status polls `/pipeline/status` every 2s. Artifacts land in `<dir>/photo-ai-output/`.

## Testing

Load the test system and run:

    (ql:quickload :photo-ai-lisp/tests)
    (asdf:test-system :photo-ai-lisp)

Or call directly:

    (photo-ai-lisp/tests:run-tests)

Integration tests (real subprocess / skills) are tagged :integration and excluded from the default suite.

The code is released under the MIT License. Current status: WIP skeleton.
