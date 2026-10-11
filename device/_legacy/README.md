# Legacy MediaTek GPU

Os scripts nesta pasta representam um fluxo antigo e não suportado para o bootstrap atual.

- `setup-gpu-mediatek.sh` — antiga abordagem Vulkan ICD + Zink direct.
- `run-setup-gpu-mediatek.sh` — wrapper antigo para executar o setup no chroot.

Use em vez disso:

- `/data/linux/run-setup-gpu-hybris.sh`
- `/data/linux/gpu-check.sh`
- `/data/linux/linux-status.sh`

Este diretório existe apenas para preservar histórico e referência e não deve ser usado no fluxo principal.
