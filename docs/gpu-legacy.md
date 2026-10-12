# Legacy MediaTek GPU flow

The scripts in [`device/_legacy/`](../device/_legacy/README.md) preserve an older, unsupported setup based on a Vulkan ICD and direct Zink configuration. They are not part of bootstrap and must not be used as the current GPU setup.

Use the supported GLES-first path instead:

- `/data/linux/run-setup-gpu-hybris.sh`
- `/data/linux/gpu-check.sh`
- `/data/linux/gpu-desktop.sh`

The supported accelerated path is hardware-specific: MediaTek mt6878 with Mali-G615 MC2. Other devices should use the software desktop unless their GPU stack is independently ported and validated. See [GPU and desktop](gpu.md) and [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md).
