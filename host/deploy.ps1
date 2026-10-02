# Deploy Artix/KernelSU chroot scripts via adb
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Root "device\linux-start.sh"))) {
  $Root = $PSScriptRoot
}

$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb) {
  Write-Error "adb nao encontrado no PATH (instale platform-tools)"
}

foreach ($req in @(
  "device\setup-gpu-hybris.sh",
  "device\run-setup-gpu-hybris.sh",
  "device\bootstrap.sh",
  "host\prepare.sh"
)) {
  $p = Join-Path $Root $req
  if (-not (Test-Path $p)) {
    Write-Error "ficheiro obrigatorio ausente: $p"
  }
}

Write-Host ">> dispositivo:"
& adb devices

# garantir LF nos .sh antes do push (evita 'unexpected do' no Android)
Get-ChildItem -Path $Root -Recurse -Filter *.sh | ForEach-Object {
  $t = [IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n" -replace "`r", "`n"
  $enc = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($_.FullName, $t, $enc)
}

$remote = "/data/local/tmp/rootfs"
Write-Host ">> limpar $remote (evita adb push aninhado host/host)"
& adb shell "rm -rf $remote"
& adb shell "mkdir -p $remote"

Write-Host ">> push $Root -> $remote"
# remote limpo: adb cria device/ host/ sem aninhar
& adb push (Join-Path $Root "device") "${remote}/device"
& adb push (Join-Path $Root "host") "${remote}/host"
& adb push (Join-Path $Root "ksu-module") "${remote}/ksu-module"
if (Test-Path (Join-Path $Root "deps")) {
  & adb push (Join-Path $Root "deps") "${remote}/deps"
}
if (Test-Path (Join-Path $Root "README.md")) {
  & adb push (Join-Path $Root "README.md") "${remote}/README.md"
}

# sanity: prepare + bootstrap + hybris no sitio certo
& adb shell "test -f $remote/host/prepare.sh && grep -q NUNCA $remote/host/prepare.sh && test -f $remote/device/bootstrap.sh && test -f $remote/device/setup-gpu-hybris.sh && test -f $remote/device/run-setup-gpu-hybris.sh && echo '>> deploy OK' || echo '!! deploy incompleto'"

Write-Host ""
Write-Host "No aparelho:"
Write-Host "  adb shell"
Write-Host "  su"
Write-Host "  sh /data/local/tmp/rootfs/host/prepare.sh"
Write-Host "  /data/linux/bootstrap.sh"
Write-Host ""
Write-Host "Modulo sepolicy: copie ksu-module para o Manager KernelSU e instale + reboot."
Write-Host "Pre-requisito desktop: app Termux:X11 (com.termux.x11)."
