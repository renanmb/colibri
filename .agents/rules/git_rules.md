# Git Operations Constraint

## Strict Rule: Git Commit and Push Are Forbidden

> [!CAUTION]
> The agent is strictly prohibited from running `git commit` and `git push`.

### Prohibitions
1. **Never Commit:** Do not run `git commit`, `git commit -a`, `git commit -m`, or any variation thereof.
2. **Never Push:** Do not run `git push`, `git push origin`, or any push to remote branches or GitHub.
3. **Never Bypass:** Do not invoke scripts, hooks, or subagents designed to commit or push.

### Required Workflow
- Perform only requested file edits, local tests, benchmarks, or command executions.
- Keep changes in the working directory.
- List all modified or created files in your response to the user so the user can inspect, stage, commit, and push them at their discretion.
