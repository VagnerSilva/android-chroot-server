# Changelog

Operational changes are recorded here by release/date, with impact and the implementation-plan reference. This is a maintenance record, not a duplicate of the commit log.

## Unreleased

### 2026-10-12 — Phase 6 documentation

- **Impact:** Documentation is split into setup, GPU/desktop, and troubleshooting guides, with English and Portuguese entry points; README pages link to the focused guides. See [`sdd/fase-6/01-documentacao.md`](sdd/fase-6/01-documentacao.md).
- **Impact:** Added script purpose, prerequisites, inputs, and outputs to the three shell files modified in the latest implementation change. See [`sdd/fase-6/03-headers-scripts.md`](sdd/fase-6/03-headers-scripts.md).
- **Compatibility:** Existing `/data/linux/*.sh` command paths and deployment flow are retained; no runtime behavior or command interface is intentionally changed.

### 2026-10-12 — Mesa 25 Zink vendor mapper fix

- **Impact:** The active boot flow binds Android `/vendor` read-only into the chroot so Mesa 25 Zink can load the MediaTek mapper by its absolute path. The Mesa 25 check now reports Zink failure details and does not count a failed invocation as a heap pass.
- **Validation:** On-device Mesa 25 check reported `RESULT ok=12 fail=0`; a 60-second Zink `glxgears` run rendered until its expected timeout while the XFCE session remained active. A restart with this fix was not tested.
- **Reference:** [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) and [`sdd/fase-5/05-validacao-final-pendencias.md`](sdd/fase-5/05-validacao-final-pendencias.md).

### 2026-10-12 — Mesa 26.2.4 evaluation closed without promotion

- **Impact:** Mesa 25.1.2 remains the production overlay. The isolated Mesa 26 candidate reported OpenGL 3.1, no improvement over baseline, and unsupported Zink features; GLX/sustained drawing were not validated. Do not remove the production block or force advertised capabilities from these results.
- **Compatibility:** No Mesa 26 candidate was installed into the production rootfs. Testing used an isolated image copy.
- **Reference:** [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) and [`sdd/fase-5/05-validacao-final-pendencias.md`](sdd/fase-5/05-validacao-final-pendencias.md).

### 2026-10-12 — Phase 5 operational validation

- **Impact:** Added/validated pre-deploy shell parsing, rootfs backup/restore safeguards, and bounded boot-log rotation. The integration of log rotation into the boot entrypoint remains deferred because the production container was active during validation.
- **Compatibility:** Backup refuses to overwrite an existing backup; restore requires an explicit operator confirmation. No production rootfs restore or Mesa 26 install was performed.
- **Reference:** [`sdd/fase-5/01-validar-shell.md`](sdd/fase-5/01-validar-shell.md), [`sdd/fase-5/02-backup-rootfs.md`](sdd/fase-5/02-backup-rootfs.md), [`sdd/fase-5/03-rotacionar-boot-log.md`](sdd/fase-5/03-rotacionar-boot-log.md), and [`sdd/fase-5/05-validacao-final-pendencias.md`](sdd/fase-5/05-validacao-final-pendencias.md).
