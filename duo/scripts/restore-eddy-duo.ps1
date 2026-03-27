param(
    [string]$PiHost = "pi@192.168.1.200",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\Voron24MrA.ppk",
    [string]$VoronConfigRepoPath = "C:\Users\ronal\Documents\voron-config-repo",
    [switch]$SkipSetup,
    [switch]$SkipHardening,
    [switch]$SkipReboot
)

$ErrorActionPreference = "Stop"

$plink = "C:\Program Files\PuTTY\plink.exe"
$pscp  = "C:\Program Files\PuTTY\pscp.exe"
$eddyRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$localScriptGlob = Join-Path $eddyRepoRoot "duo\scripts\*"

function Test-PathOrThrow {
    param([string]$PathToCheck, [string]$Label)
    if (-not (Test-Path $PathToCheck)) {
        throw "$Label not found: $PathToCheck"
    }
}

function Invoke-External {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [string]$Label
    )

    Write-Host "`n==> $Label"
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

Test-PathOrThrow -PathToCheck $plink -Label "plink"
Test-PathOrThrow -PathToCheck $pscp -Label "pscp"
Test-PathOrThrow -PathToCheck $KeyPath -Label "SSH key"
Test-PathOrThrow -PathToCheck $VoronConfigRepoPath -Label "Voron config repo"

Invoke-External -Exe $plink -Arguments @(
    "-i", $KeyPath, "-batch", $PiHost,
    "mkdir -p ~/eddy-duo/scripts ~/eddy-duo/firmware-builds ~/eddy-duo/diagnostics ~/printer_data/config; if [ -f ~/printer_data/config/printer.cfg ]; then cp ~/printer_data/config/printer.cfg /tmp/printer.cfg.pre-restore; fi"
) -Label "Prepare remote directories"

Invoke-External -Exe $pscp -Arguments @(
    "-i", $KeyPath, "-batch", $localScriptGlob,
    "${PiHost}:/home/pi/eddy-duo/scripts/"
) -Label "Upload Eddy Duo scripts"

Invoke-External -Exe $pscp -Arguments @(
    "-i", $KeyPath, "-batch", (Join-Path $VoronConfigRepoPath "*.cfg"),
    "${PiHost}:/home/pi/printer_data/config/"
) -Label "Upload Voron config files"

Invoke-External -Exe $plink -Arguments @(
    "-i", $KeyPath, "-batch", $PiHost,
    "chmod +x ~/eddy-duo/scripts/*.sh; rm -f ~/printer_data/config/_remote_printer.cfg; if [ -f /tmp/printer.cfg.pre-restore ] && grep -q '^#\\*# <---------------------- SAVE_CONFIG ---------------------->' /tmp/printer.cfg.pre-restore; then awk '/^#\\*# <---------------------- SAVE_CONFIG ---------------------->/{exit} {print}' ~/printer_data/config/printer.cfg > /tmp/printer.cfg.base; awk 'f{print} /^#\\*# <---------------------- SAVE_CONFIG ---------------------->/{f=1; print}' /tmp/printer.cfg.pre-restore > /tmp/printer.cfg.saveblock; cat /tmp/printer.cfg.base /tmp/printer.cfg.saveblock > ~/printer_data/config/printer.cfg; fi"
) -Label "Set script permissions and clean extra config"

if (-not $SkipSetup) {
    Invoke-External -Exe $plink -Arguments @(
        "-i", $KeyPath, "-batch", $PiHost,
        "bash ~/eddy-duo/scripts/setup-eddy-dev.sh"
    ) -Label "Run setup-eddy-dev.sh"
}

if (-not $SkipHardening) {
    Invoke-External -Exe $plink -Arguments @(
        "-i", $KeyPath, "-batch", $PiHost,
        "bash ~/eddy-duo/scripts/harden-eddy-usb.sh"
    ) -Label "Run harden-eddy-usb.sh"
}

if (-not $SkipReboot) {
    Invoke-External -Exe $plink -Arguments @(
        "-i", $KeyPath, "-batch", $PiHost,
        "sudo reboot"
    ) -Label "Reboot Pi"

    Start-Sleep -Seconds 20

    $active = $false
    for ($i = 0; $i -lt 12; $i++) {
        & $plink -i $KeyPath -batch $PiHost "systemctl is-active klipper" | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $active = $true
            break
        }
        Start-Sleep -Seconds 5
    }

    if (-not $active) {
        throw "Klipper did not report active after reboot wait window."
    }

    Invoke-External -Exe $plink -Arguments @(
        "-i", $KeyPath, "-batch", $PiHost,
        "cat /proc/cmdline; echo ---; systemctl is-active klipper"
    ) -Label "Verify cmdline hardening and Klipper service"

    $remotePrinterRecoverCmd = @'
info=$(/usr/bin/curl -s http://127.0.0.1:7125/printer/info)
echo "$info"
if echo "$info" | grep -q '"state":"shutdown"'; then
  /usr/bin/curl -s -X POST "http://127.0.0.1:7125/printer/gcode/script?script=FIRMWARE_RESTART"
  sleep 3
  /usr/bin/curl -s http://127.0.0.1:7125/printer/info
fi
'@

    Invoke-External -Exe $plink -Arguments @(
        "-i", $KeyPath, "-batch", $PiHost,
        $remotePrinterRecoverCmd
    ) -Label "Verify printer state and auto-recover shutdown"
}

Write-Host "`nRestore complete."
