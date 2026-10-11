# Agent Rules & Constraints

## 1. Git and Version Control Restrictions (STRICT POLICY)

> [!CAUTION]
> **FORBIDDEN: GIT COMMIT AND GIT PUSH**
> The agent is strictly forbidden from creating git commits and pushing to GitHub or any remote repository.

* **No Git Commits (`git commit`):**
  The agent must NEVER run `git commit` under any circumstances. The agent must never stage and commit changes automatically.
* **No Git Pushes (`git push`):**
  The agent must NEVER run `git push` or interact with remote repositories to publish changes.
* **User Authority:**
  All git commits and pushes must be reviewed and executed manually by the human user. The agent's role is restricted to making local file edits, running diagnostics, builds, tests, or scripts as requested, and reporting modified files to the user.
* **No Subagent or Script Delegation:**
  The agent must not delegate git commit or push commands to subagents, background jobs, or automation scripts.
