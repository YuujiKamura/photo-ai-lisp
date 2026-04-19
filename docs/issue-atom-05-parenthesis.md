# Issue: atom-05 parenthesis matching blocker

## Status
Rolled back due to parenthesis matching complexity.

## Context
- **Atom**: codex-business-ui-05 (case-view-handler)
- **Dispatch**: `.dispatch/codex-business-ui-05-case-view-handler.md`
- **Branch**: `track-c/ghostty-web-front`
- **Task**: Implement `case-view-handler` with embedded iframe + case metadata pane

## Problem
Attempted implementation hit parenthesis nesting complexity:
- `case-view-handler` body contains a nested `let* + format` structure with inline HTML strings
- The format call has multiple `(or ...)` expressions for optional metadata
- Counting closing parentheses became error-prone across the nested scope
- Compilation error: "unmatched close parenthesis" and "end of file" errors

## Root Cause
The reference sketch in the dispatch provides a working template, but manual transcription with proper indentation/escaping across:
- Multiline HTML strings (embedded CSS)
- Nested `or` expressions 
- Variable bindings in `let*`
...proved challenging for bracket balancing in a text editor.

## Recommendation
Next executor should:
1. Copy the reference sketch from dispatch verbatim (lines 62-106)
2. Verify with a Lisp syntax highlighter or REPL before testing
3. Consider pre-compiling the HTML template as a separate function to reduce nesting depth

## Working Elements (pre-rollback)
- `%case-basename` helper function was correctly implemented
- Test expectations understood and match the dispatch spec
- No changes needed to test files or other modules

## Next Steps
1. Assign to different executor (Opus preferred for nested structure handling)
2. Use dispatch reference sketch exactly, no reimplementation
3. Run tests immediately after paste to catch syntax errors early
