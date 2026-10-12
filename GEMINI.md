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

## 2. Devcontainer Environment Awareness & Physical Hardware Restrictions

> [!WARNING]
> **CONTAINER BOUNDARY: DEVCONTAINER ENVIRONMENT**
> The agent operates strictly inside a containerized Docker Devcontainer environment (`/workspaces/colibri`). The agent cannot interact with or modify physical hardware outside the container.

* **No Physical Hardware Execution:**
  Procedures requiring physical intervention—such as motherboard rear I/O peripheral re-cabling, USB port relocation, PCIe/M.2 slot reseating, physical display cable routing, and BIOS/UEFI firmware reconfiguration (as documented in physical runbooks such as [`.agents/references/plans/motherboard_usb_and_pcie_topology_plan.md`](.agents/references/plans/motherboard_usb_and_pcie_topology_plan.md))—**cannot and will not work** from inside this container. These are strictly manual reference guides for the human operator on the physical host machine.
* **No Host-Level BIOS or Power Operations:**
  The agent must never attempt to execute physical reboot, BIOS flashing, or host-only hardware modifications.
* **Portable Relative Documentation Links:**
  When referencing repository files within documentation (`.md` files), the agent must NEVER use absolute container URIs like `file:///workspaces/colibri/...`. All documentation references must use standard relative Markdown links (e.g., `[label](./relative/path.md)`) so they resolve properly across all environments (VS Code Devcontainer, GitHub, host markdown viewers).

