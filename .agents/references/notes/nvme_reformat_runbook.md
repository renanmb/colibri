# NVMe Drive (`nvme1n1p1`) Unmount & Reformat Runbook

This guide details the procedure for safely unmounting, reformatting, and remounting the secondary 4TB Samsung SSD 9100 PRO (`/dev/nvme1n1p1`) across both the host machine and the Devcontainer.

---

## 1. Important Considerations Before Reformatting

1. **UUID Invalidation:**
   - Formatting generates a **new filesystem UUID**.
   - If `/etc/fstab` on the host references the partition via `UUID=...`, it will fail to mount on subsequent reboots unless updated.
   - **Recommended Solution:** Use a volume label (`LABEL=colibri_models`). Referencing `LABEL=colibri_models` in `/etc/fstab` allows future reformats with the same label without requiring edits to `fstab`.
2. **Directory Recreation:**
   - The Devcontainer expects the directories `/mnt/models_fast/models` and `/mnt/models_fast/hf_cache` to exist on the mounted filesystem.
   - After formatting, these directories must be recreated with `777` permissions.
3. **Process Locking:**
   - Ensure no background servers (`coli serve`, `coli chat`) or terminals have their current working directory inside `/models` or `/mnt/models_fast`.

---

## 2. Step-by-Step Execution Guide

### Step 1: Verify No Active Processes
Check if any processes are holding locks on the mount points:

```bash
# In Devcontainer:
fuser -mv /models 2>/dev/null || echo "No active processes"

# On Host:
sudo fuser -mv /mnt/models_fast 2>/dev/null || echo "No active processes"
```

---

### Step 2: Unmount the Partition

Unmount from both environments to prevent cache/state desynchronization:

```bash
# 1. Inside Devcontainer (if mounted directly):
umount /models 2>/dev/null || true

# 2. On Host:
sudo umount /mnt/models_fast
```

Verify that the partition is completely unmounted:
```bash
lsblk /dev/nvme1n1p1
```

---

### Step 3: Reformat the Partition

#### Option A: High-Performance `ext4` (Recommended)
```bash
sudo mkfs.ext4 -F -m 1 -L colibri_models /dev/nvme1n1p1
```
- `-F`: Force formatting.
- `-m 1`: Reduces super-user reserved blocks to 1% (saving ~36 GB on a 4TB drive).
- `-L colibri_models`: Assigns the volume label `colibri_models`.

#### Option B: High-Throughput `xfs` (Alternative)
```bash
sudo mkfs.xfs -f -L colibri_models /dev/nvme1n1p1
```

---

### Step 4: Update Host `/etc/fstab`

Check the new UUID and label:
```bash
sudo blkid /dev/nvme1n1p1
```

Edit `/etc/fstab` on the host:
```bash
sudo nano /etc/fstab
```

Ensure the entry uses either the new UUID or the persistent label:

```text
# Using Volume Label (Recommended - impervious to future reformats):
LABEL=colibri_models /mnt/models_fast ext4 noatime,nodiratime,errors=remount-ro 0 2

# Or Using New UUID:
# UUID=<new-uuid-from-blkid> /mnt/models_fast ext4 noatime,nodiratime,errors=remount-ro 0 2
```

---

### Step 5: Remount and Recreate Directory Structure

Mount the partition on the host and establish container directory bindings:

```bash
# 1. Mount with streaming optimizations
sudo mount -o noatime,nodiratime /dev/nvme1n1p1 /mnt/models_fast

# 2. Recreate required subdirectories
sudo mkdir -p /mnt/models_fast/models /mnt/models_fast/hf_cache

# 3. Set permissive access permissions for container & host user
sudo chmod -R 777 /mnt/models_fast

# 4. Verify host symlink exists
sudo ln -sfn /mnt/models_fast /models
```

---

### Step 6: Verify Mount & Performance

```bash
# Check usable capacity
df -h /mnt/models_fast /models

# Inside Devcontainer:
df -h /models
```

Run a quick test with Colibrì's `iobench`:
```bash
python3 -c "with open('/models/test.bin', 'wb') as f: f.write(b'\0' * (1024 * 1024 * 1024))"
/workspaces/colibri/c/iobench /models/test.bin 19 32 8 1
rm -f /models/test.bin
```
