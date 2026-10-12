# Artix + dinit no Android (KernelSU)

Chroot Artix real numa imagem ext4, gerido por scripts KernelSU. Sem proot. O container pode iniciar no boot; o desktop XFCE usa Termux:X11 sob demanda.

A aceleração GPU hybris/Zink só é suportada em MediaTek mt6878 com Mali-G615 MC2. Nos outros dispositivos, use o desktop por software, salvo se o stack da GPU tiver sido portado independentemente.

## Requisitos

- Dispositivo Android com KernelSU, ADB e o módulo `ksu-module` instalado (reinicie após a instalação).
- App Android Termux:X11 (`com.termux.x11`); Termux sozinho não fornece o desktop.
- Arquivo `armtix-dinit-20260921.tar.xz` no home do Termux ou `/data/local/tmp`; o setup tenta baixá-lo se faltar.

## Início rápido

No PC, envie os scripts:

```powershell
cd host
.\deploy.ps1
```

No Android, prepare e configure:

```sh
adb shell
su
sh /data/local/tmp/rootfs/host/prepare.sh
/data/linux/bootstrap.sh
```

Sem TTY, informe as credenciais: `CREATE_USER=1 ARTIX_USER=<user> ARTIX_PASS='senha' /data/linux/bootstrap.sh`. O bootstrap configura serviços centrais e XFCE, mas não GPU hybris. Consulte [Instalação](docs/setup.pt.md) para passos avançados, backup/restauração e comandos diários.

## Guias

- [Instalação e operação diária](docs/setup.pt.md)
- [GPU e desktop](docs/gpu.pt.md)
- [Solução de problemas](docs/troubleshooting.pt.md)
- [Fluxo GPU MediaTek legado](docs/gpu-legacy.pt.md)
- [English: setup and daily operation](docs/setup.md)
- [English: GPU and desktop](docs/gpu.md)
- [English: troubleshooting](docs/troubleshooting.md)
- [English: legacy GPU flow](docs/gpu-legacy.md)

## Comandos principais

| Tarefa | Comando |
|---|---|
| Iniciar / parar / estado | `/data/linux/linux-start.sh` / `linux-stop.sh` / `linux-status.sh` |
| Entrar como root / user | `/data/linux/linux-shell.sh` / `linux-shell.sh <user>` |
| Iniciar desktop | `/data/linux/gpu-desktop.sh` |
| Parar desktop | `/data/linux/gpu-desktop.sh stop` |
| Backup do rootfs | `/data/linux/linux-backup.sh` |

Execute os comandos no host Android como root, salvo indicação em contrário. O container inicia no boot; XFCE e Termux:X11 não. A GPU acelerada é específica do hardware. Mesa 25.1.2 continua a versão de produção; consulte [problemas conhecidos](KNOWN_ISSUES.md) antes de alterar o bloqueio da Mesa 26.

## Referências do projeto

- [Problemas conhecidos e evidências](KNOWN_ISSUES.md)
- [Changelog](CHANGELOG.md)
- [Plano de implementação](sdd/plan.md)
