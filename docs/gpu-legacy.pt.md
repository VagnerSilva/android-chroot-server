# Fluxo GPU MediaTek legado

Os scripts em [`device/_legacy/`](../device/_legacy/README.md) preservam um setup antigo e sem suporte, baseado em Vulkan ICD e configuração Zink direta. Não fazem parte do bootstrap e não devem ser usados como setup GPU atual.

Use o fluxo suportado GLES-first:

- `/data/linux/run-setup-gpu-hybris.sh`
- `/data/linux/gpu-check.sh`
- `/data/linux/gpu-desktop.sh`

A aceleração suportada é específica: MediaTek mt6878 com Mali-G615 MC2. Noutros dispositivos, use o desktop por software, salvo se o stack da GPU tiver sido portado e validado independentemente. Consulte [GPU e desktop](gpu.pt.md) e [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md).
