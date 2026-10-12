# Devcontainer Environment Boundaries & Constraints

## Strict Rule: Devcontainer Execution Boundary & Hardware Non-Intervention

> [!WARNING]
> The agent operates strictly inside a containerized Docker Devcontainer environment (`/workspaces/colibri`).
> Physical host hardware operations and host firmware actions CANNOT and WILL NOT work from inside this container.

### Prohibitions & Boundaries
1. **No Physical Hardware Execution:**
   The agent must never attempt or assume automated execution of physical hardware reconfiguration.
   Actions such as:
   - Motherboard rear I/O peripheral cable swapping / USB port relocations
   - PCIe slot card relocation or reseating
   - M.2 NVMe physical drive swaps
   - Physical DisplayPort / HDMI cable re-routing
   - BIOS/UEFI firmware setup, flashing, or PCIe lane bifurcation adjustments
   are strictly host-level physical operations reserved exclusively for the human operator on the physical workstation.
2. **Hardware Runbooks as Manual Human References:**
   Documents detailing physical motherboard layouts and PCIe topologies (e.g. [`.agents/references/plans/motherboard_usb_and_pcie_topology_plan.md`](../references/plans/motherboard_usb_and_pcie_topology_plan.md)) must be treated as manual reference documentation for the human operator, not as executable agent tasks.
3. **Portable Documentation Links:**
   Documentation files (`.md`) within the repository must use portable relative links (e.g. `[label](./relative/path.md)`) rather than absolute `file:///workspaces/colibri/...` URIs, which break outside the container environment and in VS Code markdown previews.
