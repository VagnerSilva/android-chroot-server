# GPU e desktop

O desktop corre dentro do chroot Artix através do Termux:X11 no display `:0`; não usa TigerVNC. O renderer XFCE padrão é software (softpipe). O stack acelerado hybris/Zink só é suportado em MediaTek mt6878 com Mali-G615 MC2 (por exemplo, Moto G86); outros SoCs exigem portabilidade. Veja o [fluxo GPU legado](gpu-legacy.pt.md) para scripts preservados, mas sem suporte.

## Termux:X11 e XFCE

Instale a app Android `com.termux.x11` pelo F-Droid ou pelos nightly do GitHub Termux:X11. O Termux base (`com.termux`) não chega. No Android 14+, o companion `loader.apk` fica em `/data/linux/termux-x11/`; `prepare.sh` e `x11-start.sh` podem instalá-lo. Alternativamente, no Termux use `pkg i x11-repo && pkg i termux-x11-nightly`.

Com utilizador configurado e container ligado:

```sh
ARTIX_USER=<user> /data/linux/run-setup-xfce.sh
/data/linux/x11-start.sh
/data/linux/x11-stop.sh
```

O primeiro comando pode ser repetido para reaplicar as preferências XFCE sem apagar o rootfs. A configuração X11 é `/etc/artix-x11.conf` (`X11_USER`, `X11_DISPLAY`, `XFCE_USE_ZINK`). O serviço dinit XFCE espera que X0 já exista.

O helper `gpu-desktop.sh` cobre o uso diário:

```sh
/data/linux/gpu-desktop.sh          # configura se necessário e inicia o desktop
/data/linux/gpu-desktop.sh status   # markers e configuração
/data/linux/gpu-desktop.sh stop     # para X11/XFCE
/data/linux/gpu-desktop.sh cpu      # desktop por software
```

O desktop não inicia automaticamente no boot. O autostart do container é separado; ligue o desktop quando necessário.

## Setup Mali suportado

O setup é GLES-first e usa bibliotecas Android/Bionic num runtime isolado. Não é um setup Mali/Panfrost genérico. Não crie `/dev/dri/renderD128`; este dispositivo expõe o nó Mali KBase `/dev/mali0`, enquanto `mediatek-drm` fornece o nó de display separado `/dev/dri/card0`.

Os arquivos runtime offline em `deps/` são instalados em `/data/linux/deps/` pelo deploy e copiados para o chroot pelos scripts de setup. Mesa e libhybris são pré-compilados; não os compile no dispositivo. `android-vulkan-bridge.tar.gz` é legado e não é usado no fluxo suportado.

Com o container ligado, configure a GPU e verifique o gate GLES inicial:

```sh
/data/linux/run-setup-gpu-hybris.sh
/data/linux/gpu-check.sh
```

O helper do desktop executa o setup quando faltam markers. Para testes diretos:

```sh
gpu-egl-run /tmp/mali-egl-test
DISPLAY=:0 gpu-egl-run <teste-x11>
DISPLAY=:0 gpu-vulkan-run vkcube
```

Deixe `vulkaninfo` para o fim ao diagnosticar o driver. O gate `STRICT=1` considera o marker GLES como GPU funcional; Vulkan e Zink são capacidades opcionais posteriores.

## Markers e seleção do renderer

| Marker | Significado |
|---|---|
| `/etc/artix-gpu-gles.ok` | Mali GLES/EGL funcional |
| `/etc/artix-gpu-hybris.ok` | Setup GLES, Vulkan e WSI concluído |
| `/etc/artix-gpu-zink.ok` | Zink sobre Vulkan Mali validado |
| `/etc/artix-mesa25.ok` | Overlay Mesa 25.1.2 em `/opt/android-mali` |
| `/etc/artix-libhybris.ok` | Overlay libhybris em `/opt/libhybris` |
| `/etc/artix-sysvk.ok` | Overlay sysvk instalado |

| Uso | Entrada |
|---|---|
| XFCE padrão | Renderização software softpipe |
| XFCE acelerado (com marker/config Zink) | `XFCE_USE_ZINK=1`, depois `zink-run startxfce4` |
| App GLES | `gpu-egl-run` |
| App Vulkan | `gpu-vulkan-run` após setup hybris |
| App OpenGL/Zink | `zink-run` ou `gpu-run` |

`gpu-desktop.sh` seleciona e configura o caminho suportado. Não use `XFCE_USE_ZINK=1` sem `/etc/artix-gpu-zink.ok`; o modo `cpu` do helper volta à renderização por software.

## Diagnóstico e limites conhecidos

Se o SELinux do Android bloquear acesso à GPU, veja `dmesg | grep -iE 'avc|mali|gpu'`. Em alguns dispositivos Android 16, `app_process` do Termux:X11 pode falhar com `NoClassDefFoundError`; atualize app e loader pelos nightly e consulte `logcat | grep termux-x11`.

A situação canônica das versões GPU, medições e critérios de promoção está em [`GPU_KNOWLEDGE_BASE.md`](../GPU_KNOWLEDGE_BASE.md). Consulte [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md) para o histórico detalhado das avaliações. Não force versão GL nem invente capacidades Vulkan.

Para renderer Mali ausente, ELF inválido, tela preta ou falha de X11, consulte [Solução de problemas](troubleshooting.pt.md).
