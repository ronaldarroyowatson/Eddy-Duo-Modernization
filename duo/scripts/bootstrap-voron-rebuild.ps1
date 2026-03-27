param(
    [string]$WorkspaceRoot = "C:\Users\ronal\Documents",
    [string]$VoronRepoUrl = "https://github.com/ronaldarroyowatson/voron-config-repo.git",
    [string]$EddyRepoUrl = "https://github.com/ronaldarroyowatson/Eddy-Duo-Modernization.git",
    [string]$PiHost = "pi@192.168.1.200",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\Voron24MrA.ppk",
    [switch]$SkipSetup,
    [switch]$SkipHardening,
    [switch]$SkipReboot
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
    param([string[]]$Args, [string]$Label)
    Write-Host "`n==> $Label"
    & git @Args
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

function Ensure-Repo {
    param(
        [string]$RepoPath,
        [string]$RepoUrl,
        [string]$Label
    )

    if (Test-Path $RepoPath) {
        Invoke-Git -Args @("-C", $RepoPath, "fetch", "--all", "--prune") -Label "$Label fetch"
        Invoke-Git -Args @("-C", $RepoPath, "pull", "--ff-only") -Label "$Label pull"
    } else {
        Invoke-Git -Args @("clone", $RepoUrl, $RepoPath) -Label "$Label clone"
    }
}

if (-not (Test-Path $WorkspaceRoot)) {
    throw "Workspace root not found: $WorkspaceRoot"
}

$voronRepoPath = Join-Path $WorkspaceRoot "voron-config-repo"
$eddyRepoPath = Join-Path $WorkspaceRoot "Eddy-Duo-Modernization"
$restoreScript = Join-Path $eddyRepoPath "duo\scripts\restore-eddy-duo.ps1"

Ensure-Repo -RepoPath $voronRepoPath -RepoUrl $VoronRepoUrl -Label "Voron repo"
Ensure-Repo -RepoPath $eddyRepoPath -RepoUrl $EddyRepoUrl -Label "Eddy Duo repo"

if (-not (Test-Path $restoreScript)) {
    throw "Restore script not found: $restoreScript"
}

$restoreArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $restoreScript,
    "-PiHost", $PiHost,
    "-KeyPath", $KeyPath,
    "-VoronConfigRepoPath", $voronRepoPath
)

if ($SkipSetup) { $restoreArgs += "-SkipSetup" }
if ($SkipHardening) { $restoreArgs += "-SkipHardening" }
if ($SkipReboot) { $restoreArgs += "-SkipReboot" }

Write-Host "`n==> Running full restore"
& powershell @restoreArgs
if ($LASTEXITCODE -ne 0) {
    throw "Restore failed with exit code $LASTEXITCODE"
}

Write-Host "`nBootstrap rebuild complete."
