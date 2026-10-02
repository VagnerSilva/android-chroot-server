@echo off
REM Empacota ksu-module em zip instalavel pelo KernelSU Manager
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path 'module.prop','sepolicy.rule','META-INF' -DestinationPath '..\artix_chroot_loop.zip' -Force"
echo Criado: ..\artix_chroot_loop.zip
