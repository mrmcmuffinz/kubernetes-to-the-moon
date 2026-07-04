# Cloud-Init Reference

**Purpose:** Quick reference for inspecting cloud-init status, reading logs, and
re-running cloud-init on a running VM. Use this when a VM first boot fails, a
cloud-init module did not apply, or you want to re-provision a VM without reflashing.

---

## Status

```bash
# Summary: which stage completed, which failed, and overall result
cloud-init status

# Detailed: per-stage timing and error messages
cloud-init status --long
```

Stages in order: `cloud-init-local` → `cloud-init` (network) → `config` → `final`.
A failure in an early stage can prevent later stages from running.

---

## Logs

```bash
# Human-readable output from every module and script (best starting point)
sudo cat /var/log/cloud-init-output.log

# Structured log with timestamps and debug detail
sudo cat /var/log/cloud-init.log

# Tail the output log during a live run
sudo tail -f /var/log/cloud-init-output.log
```

`cloud-init-output.log` captures stdout and stderr from every module in order. It is
the most useful log for diagnosing why a package install, `runcmd`, or `write_files`
step failed.

---

## Inspect Applied Config

```bash
# Show the merged config cloud-init actually used (user-data + network-config + meta-data)
sudo cloud-init query --all

# Show only user-data
sudo cloud-init query userdata

# Show only network config
sudo cloud-init query network
```

---

## Re-Run Cloud-Init

Only needed if you want to re-apply configuration on an already-booted VM without
reflashing.

```bash
# Clean all cloud-init state and logs, then re-run each stage manually
sudo cloud-init clean --logs
sudo cloud-init init
sudo cloud-init modules --mode=config
sudo cloud-init modules --mode=final
```

```bash
# Clean state and trigger a full re-run on next reboot
sudo cloud-init clean
sudo reboot
```

```bash
# Clean state, wipe logs, and reboot in one command
sudo cloud-init clean --logs --reboot
```

`cloud-init clean` removes the run stamps in `/var/lib/cloud/`. Without those stamps,
cloud-init treats the next boot as a first boot and re-runs all stages. The seed ISO
must still be attached to the VM for cloud-init to read the user-data and network-config
again.

---

## Common Failure Patterns

| Symptom | Likely cause | Where to look |
|---------|-------------|---------------|
| VM boots but has no static IP | `network-config` not read in `cloud-init-local` | `cloud-init.log` for netplan errors |
| `runcmd` steps did not run | Earlier stage failed and blocked `final` | `cloud-init-output.log`, check `status --long` |
| SSH key not injected | `users` block malformed in user-data | `cloud-init-output.log` for YAML parse errors |
| Package install failed | No network at package install time | Confirm static IP was set before `config` stage |
| VM rebooted unexpectedly mid-run | `power_state` or `runcmd` reboot in user-data | Expected -- wait for second boot to complete |
