# Agent Workspace (`.agents`)

This repository stores agent skills, architectural references, technical plans, and long-term session memory for the Antigravity agent working on the **Colibrì** local LLM deployment.

---

## Directory Structure

```text
.agents/
├── README.md               # Repository overview and conventions
├── skills/                 # Antigravity agent skills (on-demand runbooks & procedures)
│   └── colibri-glm/
│       └── SKILL.md        # Skill for managing and optimizing GLM on Colibrì
├── references/             # Project references, deployment plans, and architectural notes
│   ├── plans/              # Actionable implementation plans and roadmaps
│   │   └── glm53_deployment_plan.md
│   └── notes/              # Deep-dive technical notes and host environment specs
│       ├── hardware_architecture.md
│       ├── glm53_colibri_preparation_summary.md
│       └── nvme_reformat_runbook.md
└── memory/                 # Session memory and cross-session knowledge persistence
    ├── GLOBAL_MEMORY.md    # High-level persistent facts, environment bindings, and invariants
    └── sessions/           # Dated session logs and progress checkpoints
        └── 2026-10-09-setup.md
```

---

## Guidelines for Agents
1. **Context Awareness:** Always remember that this environment runs inside a Docker Devcontainer on an Ubuntu host with two Samsung 9100 PRO 4TB NVMe drives and dual NVIDIA GPUs (RTX PRO 6000 Blackwell + RTX 5090).
2. **Memory Updates:** At the end of major milestones, update `memory/GLOBAL_MEMORY.md` and log the session record in `memory/sessions/`.
3. **Reference Documents:** When modifying architecture or hardware placement, keep `references/` documents up to date.
