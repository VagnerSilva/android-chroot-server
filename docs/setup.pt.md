# Instalação e operação diária

Este guia cobre o envio dos scripts, a criação do rootfs Artix e a operação do container. GPU e Termux:X11 estão em [GPU e desktop](gpu.pt.md); problemas comuns estão em [Solução de problemas](troubleshooting.pt.md).

## Requisitos

- Dispositivo Android com KernelSU e acesso ADB.
- `ksu-module` instalado pelo KernelSU Manager e dispositivo reiniciado (política SELinux para loop devices).
- Termux:X11 (`com.termux.x11`) para o desktop. O Termux sozinho não fornece o servidor X.
- Arquivo `armtix-dinit-20260921.tar.xz` no home do Termux ou em `/data/local/tmp`; se faltar, o setup tenta baixá-lo.
- O caminho acelerado suportado exige MediaTek mt6878 com Mali-G615 MC2. Outros dispositivos podem usar o desktop por software.

## Envio e bootstrap

No PC, a partir do repositório:

```powershell
cd host
.\deploy.ps1
```

No dispositivo:

```sh
adb shell
su
sh /data/local/tmp/rootfs/host/prepare.sh
```

Instale `ksu-module` no KernelSU Manager e reinicie. Depois, prepare o ambiente:

```sh
su
/data/linux/bootstrap.sh
```

O bootstrap para o container para iniciar em estado limpo, instala o rootfs se necessário, inicia dinit, configura sshd, dbus/elogind e XFCE, e instala o autostart do container. Não configura GPU hybris. Em TTY pergunta se quer criar utilizador (padrão: sim); sem TTY, informe as credenciais:

```sh
CREATE_USER=1 ARTIX_USER=<user> ARTIX_PASS='senha' /data/linux/bootstrap.sh
```

Se o home desse utilizador já existir, execute `/data/linux/bootstrap.sh` novamente sem as variáveis de criação. Para um rootfs inconsistente não há recuperação de bibliotecas no local; o wipe é destrutivo para `/data/linux` e exige confirmação explícita:

```sh
YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh
```

A procura do arquivo segue esta ordem: argumento ou `ARMTIX_TAR`, home do Termux, `/data/local/tmp` e, por fim, download do ARMtix. Se a extração `.xz` falhar no Termux, instale `xz-utils` e use `xz -dk` no arquivo.

## Setup avançado

Os passos individuais ficam disponíveis quando o bootstrap não for adequado:

```sh
/data/linux/install-rootfs.sh
/data/linux/linux-start.sh
/data/linux/run-setup.sh
SETUP_FULL=1 SKIP_GPU=1 /data/linux/run-setup.sh
/data/linux/x11-start.sh
STRICT=1 REQUIRE_X11=1 REQUIRE_GPU=0 /data/linux/linux-status.sh
```

Sem `SETUP_FULL=1`, `run-setup.sh` configura os serviços centrais. `SETUP_FULL=1 SKIP_GPU=1` também instala XFCE sem GPU; sem `SKIP_GPU`, solicita a configuração da GPU. Em TTY o setup pode perguntar pelo utilizador. O modo completo sem interação exige `ARTIX_USER` e `ARTIX_PASS`. Se sshd falhar, o setup para nessa etapa.

## Arranque no boot

`prepare.sh` e `bootstrap.sh` instalam `/data/adb/service.d/99-linux.sh`. Ele inicia o container depois do boot; XFCE e Termux:X11 continuam sob demanda. Reinstale ou atualize o serviço com:

```sh
/data/linux/install-autostart.sh
```

Para não instalar autostart ao preparar os scripts:

```sh
SKIP_AUTOSTART=1 sh /data/local/tmp/rootfs/host/prepare.sh
```

## Comandos diários

| Tarefa | Comando |
|---|---|
| Iniciar / parar / estado | `/data/linux/linux-start.sh`, `/data/linux/linux-stop.sh`, `/data/linux/linux-status.sh` |
| Verificação estrita | `STRICT=1 REQUIRE_X11=1 /data/linux/linux-status.sh` |
| Shell root / shell de user | `/data/linux/linux-shell.sh` / `/data/linux/linux-shell.sh <user>` |
| Criar, alterar senha, dar sudo ou remover user | `/data/linux/artix-user.sh create <user> 'senha'`; `passwd <user> 'nova'`; `sudo <user>`; `remove <user>` |
| Backup do rootfs | `/data/linux/linux-backup.sh` (container parado; não substitui backup existente) |
| Iniciar/parar desktop | `/data/linux/gpu-desktop.sh` / `/data/linux/gpu-desktop.sh stop` |
| Log de boot | `cat /data/linux/boot.log` |
| SSH | `ssh -p 2222 <user>@<ip-do-dispositivo>` |

Execute estes comandos no host Android como root, salvo indicação em contrário. `linux-shell.sh <user>` entra no home do utilizador sem pedir senha. O home root é `/root`; utilizadores normais ficam em `/home/<user>`.

## Pacman e dinit

Com o container ligado, corrija os mirrors ARMtix ou o sandbox do pacman incompatível com Android a partir do host:

```sh
/data/linux/fix-pacman-mirrors.sh
/data/linux/fix-pacman-sandbox.sh
```

A correção do sandbox desativa Landlock no chroot e instala um hook para reaplicar a opção após upgrades do pacman. Para pacotes ausentes no ARMtix, `enable-archlinuxarm.sh` habilita o repositório Arch Linux ARM; não use pacotes Arch x86.

Instale um serviço dinit de sistema e consulte o estado:

```sh
/data/linux/install-dinit-services.sh dinit-test
dinitctl status dinit-test
```

Não use `>` em `command =` de serviços dinit; chame um script. O socket de controle do dinit de sistema já existe em `/run/dinitctl`. O teste isolado de rede do utilizador é `~/test-dinit-network.sh` e exige serviço `boot` e `--user --container --cgroup-path /sys/fs/cgroup`.

## Backup e restauração

O backup padrão é `/data/linux/rootfs.img.bak`. Pare o container primeiro. O comando verifica se a imagem está desmontada, espaço livre e integridade da cópia; nunca substitui backup existente.

Para restaurar explicitamente, preserve a imagem atual em separado e confirme antes de substituir:

```sh
/data/linux/linux-stop.sh
/data/linux/linux-backup.sh /data/linux/rootfs.img.pre-restore
printf 'Digite RESTORE para substituir rootfs.img: '
read -r answer
[ "$answer" = RESTORE ] || exit 1
test ! -e /data/linux/rootfs.img.restore.tmp || exit 1
cp -p /data/linux/rootfs.img.bak /data/linux/rootfs.img.restore.tmp
cmp -s /data/linux/rootfs.img.bak /data/linux/rootfs.img.restore.tmp || exit 1
mv /data/linux/rootfs.img.restore.tmp /data/linux/rootfs.img
```

Para avaliar Mesa 26, use apenas o fluxo de cópia isolada em [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md); não instale a candidata no rootfs de produção.
