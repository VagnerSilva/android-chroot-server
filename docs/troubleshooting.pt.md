# Solução de problemas

Execute comandos do dispositivo no host Android como root, salvo indicação em contrário. Para limites de renderer e falhas específicas da GPU, consulte [GPU e desktop](gpu.pt.md).

| Sintoma | Causa provável | Ação |
|---|---|---|
| `unexpected do` ou script `not found` | Fim de linha CRLF do Windows | `deploy.ps1` força LF. A limpeza no dispositivo está abaixo; nunca use `sed 's/\\r//'` no BusyBox Android, pois pode apagar a letra `r`. |
| `unshare` falha, dinit `[FAILED] boot`, erros udev/modules/fsck | Early boot de máquina real indisponível dentro do chroot Android | Execute `linux-stop.sh`, atualize scripts com `prepare.sh`, rode `fix-dinit-chroot.sh`, depois inicie e consulte o estado. O fix substitui serviços early boot incompatíveis. |
| Falta `libgcc_s.so.1` ou `libstdc++.so.6` | Runtime GCC incompleto após transação pacman | Execute `su -c /data/linux/repair-libgcc.sh` e repita o setup necessário. |
| `unshare(...): Invalid argument` | Kernel sem suporte a PID namespace | Esperado em alguns kernels; o start usa fallback mount-only. O status pode indicar falha de namespace PID com container ativo. |
| `nsenter: can't open .../ns/pid` | Scripts antigos no dispositivo | Execute `prepare.sh` novamente; o caminho atual suporta namespace apenas de mount. |
| Mount da imagem sem RW ou loop com `Invalid argument` | Módulo SELinux/reboot, imagem em armazenamento incompatível ou flags de mount | Instale `ksu-module` e reinicie; mantenha a imagem em `/data/linux`; consulte status e `dmesg | grep -iE 'avc|ext4|loop'`. |
| Pacman trava em 100% / Landlock | Incompatibilidade do sandbox com kernel Android | Execute `fix-pacman-sandbox.sh` no host Android com container ligado. Desativa sandbox no chroot e instala hook de reaplicação. |
| Pacman retorna 404, TLS ou mirrors mortos | Lista de mirrors errada/desatualizada | Execute `fix-pacman-mirrors.sh` e depois `sudo pacman -Syy` dentro do chroot. |
| `SigLevel = Neve` | Limpeza CRLF antiga corrompeu `Never` | Corrija para `SigLevel = Never` e rode `fix-pacman-mirrors.sh`; evite a expressão `sed` insegura do BusyBox descrita acima. |
| Pacote `direnv` não encontrado | Pacote ausente no ARMtix | Habilite Arch Linux ARM com `enable-archlinuxarm.sh`; instale pacotes ARM, nunca Arch x86. |
| Senha SSH/login recusada ou sudo negado | Credenciais/grupo do utilizador | Use `artix-user.sh passwd <user> 'senha'` ou `artix-user.sh sudo <user>` e volte a entrar. SSH usa a porta 2222. |
| `cd root` sem permissão | Utilizador normal tentou entrar em `/root` | Esperado; use `cd ~` para `/home/<user>`. |
| dbus/elogind/logind falha com cgroup | Cgroup Android não permite `run-in-cgroup` | Repita `run-setup.sh` ou `fix-dbus-chroot.sh`; consulte `dinitctl status dbus elogind logind` e `/run/dbus/system_bus_socket`. |
| Teste dinit de user: cgroup, boot ausente ou estado vazio | Argumentos/serviço de teste incorretos | Use `--user --container --cgroup-path /sys/fs/cgroup`, defina serviço `boot` e evite `>` em `command =`; chame um script. |
| XFCE/Termux:X11 não inicia | App/loader ausente, X0 inexistente ou configuração de sessão | Confirme `pm path com.termux.x11`, abra a app, execute `x11-start.sh`, consulte `dinitctl status xfce-x11 dbus`, `/var/log/dinit/xfce-x11.log` e `/etc/artix-x11.conf`. |
| Container parece morto ou pidfile obsoleto | Start/stop anterior não terminou | Execute `linux-stop.sh`, depois `linux-start.sh`; consulte `/data/linux/boot.log`. |

Para remover CRLF no dispositivo, preservando os bytes restantes e substituindo cada arquivo:

```sh
CR=$(printf '\r')
for f in /data/linux/*.sh; do tr -d "$CR" < "$f" > "$f.n" && mv "$f.n" "$f"; done
```

Para socket X11 ausente, tela preta ou `Cannot open display :0`, consulte o [guia GPU e desktop](gpu.pt.md). Para evidências Mesa 26 e decisão de produção, veja [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md).
