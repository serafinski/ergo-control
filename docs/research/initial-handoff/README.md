# Initial research handoff (archive)

This folder preserves the original pre-implementation handoff and hashes of the vendor evidence used during research. It is historical context; protocol recovery and the working app are documented in [the investigation](../INVESTIGATION.md) and [current setup guide](../../APP.md).

`HANDOFF.md` records the earlier scope, constraints, observations, and static findings. Its suggested next steps describe that earlier stage, not the current project status. `MANIFEST.json` contains reference SHA-256 hashes and sizes for 105 evidence files. The actual installer, extracted code, native libraries, and driver bundles are not distributed in this repository.

For local verification, place the privately obtained evidence under `analysis/private/handoff/evidence/`, or give `tools/collect_evidence.py` an alternate evidence path. Vendor artifacts are static research material; the application does not execute or link them.
