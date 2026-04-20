# Usage Log Format Spec (Tier 3 / T3.b)

Frozen spec for `~/.photo-ai-lisp/usage.log`. Referenced by T2.f. Verb set is CLOSED — adding a verb is a spec violation.

## 1. File Location and Rotation

- Path: `~/.photo-ai-lisp/usage.log`, append-only
- No rotation during dogfood week (< 10 MB total)
- Protocol-violation events go to `~/.photo-ai-lisp/usage-errors.log`

## 2. Line Format

One event per line, tab-separated, four fields:

```
<iso8601-ts>\t<verb>\t<session>\t<bytes>
```

| field | notes |
|-------|-------|
| `iso8601-ts` | ISO 8601 UTC, `Z` suffix, ms precision. Example: `2026-04-21T10:30:45.123Z` |
| `verb` | Member of closed set (section 3). Anything else MUST write to `usage-errors.log` with reason. |
| `session` | deckpilot session name (e.g., `ghostty-12345`). Use `-` for BOOT/SHUTDOWN. |
| `bytes` | Unsigned int UTF-8 byte count per semantics table. Never negative. |

Format is deliberately TSV (not JSON lines) for greppability.

## 3. Closed Verb Set (frozen)

| verb | emitted when | bytes semantics |
|------|--------------|-----------------|
| `INPUT` | CP client sends INPUT via hub | UTF-8 bytes of `msg` **after** base64 decode |
| `SHOW` | CP client requests SHOW via hub | UTF-8 bytes of response `data` string length |
| `STATE` | CP client requests STATE via hub | UTF-8 bytes of response body (serialized JSON) |
| `LIST` | CP client requests LIST via hub | UTF-8 bytes of response body (serialized JSON) |
| `BOOT` | hub starts and opens `usage.log` | `0` |
| `SHUTDOWN` | hub closes cleanly | `0` |

INPUT/SHOW/STATE/LIST come from deckpilot issue #27. BOOT/SHUTDOWN are specific to this log.

## 4. Examples

```
2026-04-21T10:00:00.000Z	BOOT	-	0
2026-04-21T10:01:15.423Z	INPUT	ghostty-12345	21
2026-04-21T10:01:17.891Z	SHOW	ghostty-12345	2048
2026-04-21T18:30:00.000Z	SHUTDOWN	-	0
```

## 5. Counting Rules for KEEP / ARCHIVE Verdict

- **Total INPUTs during dogfood week** = unique `INPUT` lines with `bytes > 0`
- `BOOT` and `SHUTDOWN` do NOT count toward usage
- `SHOW` / `STATE` / `LIST` are queries — keep a separate counter, do NOT conflate with `INPUT` for the verdict
- Verdict is driven by `INPUT` count only; queries are context, not usage
