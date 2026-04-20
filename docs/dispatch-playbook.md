# Dispatch Playbook (Runbook)

Guidelines for Hub Agents (Opus/Sonnet) to dispatch tasks to Hub-Mode Agents (Sonnet/Gemini/Codex) and for Manager Agents to babysit them.

## 1. Hub Agent: Dispatching Tasks
- **Select Template**: Use `~/photo-ai-lisp/.dispatch/templates/brief-*.md`.
- **Define Goal**: Ensure the brief has a clear "Definition of Done" (DoD).
- **Branch Policy**: Specify if the agent should create a new branch or work on an existing one.
- **Push Policy**: Strictly enforce `push prohibited` for automated tasks.
- **Launch**:
  ```powershell
  deckpilot launch <agent> "@.dispatch/brief-name.md" --cwd <path>
  ```

## 2. Manager Agent: Babysitting Tasks
- **Monitor**: Use `deckpilot show <session> --tail 40` every 20-60 seconds.
- **Handle Prompts**:
    - Gemini: Send `2` for session-wide allow.
    - Claude: Send `1` for folder trust.
    - OMC: Confirm "bypass permissions on".
- **Detect Stalls**:
    - Long "Thinking": If 5m+, check status via `deckpilot show`.
    - "Shell awaiting input": Check if a debugger (SBCL/Go) is trapped. Use `taskkill` if necessary.
- **Unblock**: Use `deckpilot send <session> "Still thinking?"` or specific commands to nudge the agent.
- **Verify**: Confirm the agent reached `DISPATCH-DONE` before reporting `MANAGER-ROLE-DONE`.

## 3. Common Troubleshooting Patterns
- **SBCL Debugger Trap**: Happens on unhandled errors. Kill the `sbcl` process and let the agent retry or report the failure.
- **Auto-approvals Regression**: If detection fails, use explicit `--agent <name>` flag.
- **Vite/Web Server**: If an agent starts a server that blocks the input, ensure it runs in the background or use `deckpilot send` to terminate the foreground process.

## 4. Reporting Hierarchy
1. Hub Brief (Task Definition)
2. Implementation/Investigation (Agent Work)
3. Babysit Report (Management Log)
4. Split/Integration Report (Hub Synthesis)
