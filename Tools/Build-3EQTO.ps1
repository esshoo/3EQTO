[CmdletBinding()]
param(
    [switch]$Dispatch,
    [string]$OutputRoot = "",
    [ValidateRange(10, 300)][int]$QueueWaitSeconds = 90
)
$ErrorActionPreference = "Stop"
$repoName = "esshoo/3EQTO"
$workflow = "build-unsigned-ipa.yml"
$repoRoot = Split-Path -Parent $PSScriptRoot
foreach ($tool in @("git", "gh")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is missing. Install Git / GitHub CLI first." }
}
Push-Location $repoRoot
try {
    $dirty = @(& git status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) { throw "Commit your local changes before building. Nothing was dispatched." }
    $sha = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Cannot determine the local commit." }
    $remote = (& git remote get-url origin).Trim()
    if ($LASTEXITCODE -ne 0 -or $remote -notmatch 'github\.com[:/]esshoo/3EQTO(?:\.git)?$') {
        throw "Origin is not esshoo/3EQTO. Check git remote -v before building."
    }
    $remoteLine = & git ls-remote --exit-code origin refs/heads/main
    if ($LASTEXITCODE -ne 0) { throw "Cannot read remote main. Check your network/login." }
    $remoteSha = ($remoteLine -split '\s+')[0]
    if ($sha -ne $remoteSha) { throw "Local HEAD is not remote main. Commit and push your update first; nothing was dispatched." }
    & gh auth status --hostname github.com
    if ($LASTEXITCODE -ne 0) { throw "Run gh auth login before building." }
    $notBefore = (Get-Date).ToUniversalTime().AddSeconds(-5)
    if ($Dispatch) {
        & gh workflow run $workflow --repo $repoName --ref main
        if ($LASTEXITCODE -ne 0) { throw "GitHub workflow dispatch failed." }
    }
    $deadline = (Get-Date).AddSeconds($QueueWaitSeconds)
    $run = $null
    do {
        $raw = & gh run list --repo $repoName --workflow $workflow --branch main --commit $sha --limit 20 --json databaseId,createdAt,event,headSha,status
        if ($LASTEXITCODE -ne 0) { throw "Cannot list workflow runs." }
        $runs = @($raw | ConvertFrom-Json)
        if ($Dispatch) {
            $runs = @($runs | Where-Object { $_.event -eq 'workflow_dispatch' -and ([DateTime]$_.createdAt).ToUniversalTime() -ge $notBefore })
        }
        $run = $runs | Sort-Object createdAt -Descending | Select-Object -First 1
        if (-not $run) { Start-Sleep -Seconds 3 }
    } while (-not $run -and (Get-Date) -lt $deadline)
    if (-not $run) { throw "No matching run found for $sha. Retry with -Dispatch to start a manual build." }
    $runId = [string]$run.databaseId
    Write-Host "Following run $runId for commit $sha"
    & gh run watch $runId --repo $repoName --exit-status
    $watchExit = $LASTEXITCODE
    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        $OutputRoot = Join-Path (Split-Path -Parent $repoRoot) '3EQTO-Builds'
    }
    $destination = Join-Path $OutputRoot $runId
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    & gh run download $runId --repo $repoName --name '3EQTO-unsigned' --dir $destination
    $downloadExit = $LASTEXITCODE
    if ($watchExit -ne 0) {
        & gh run view $runId --repo $repoName --log-failed
        throw "Build did not succeed. Available diagnostics: $destination"
    }
    if ($downloadExit -ne 0) { throw "Build succeeded but artifact download failed. Run gh run download $runId --repo $repoName" }
    $metadataFile = Get-ChildItem -Path $destination -Recurse -Filter build-info.json | Select-Object -First 1
    if (-not $metadataFile) { throw "Build metadata is missing; do not use an unverified artifact." }
    $metadata = Get-Content -Raw -LiteralPath $metadataFile.FullName | ConvertFrom-Json
    if ($metadata.commit -ne $sha) { throw "Downloaded artifact does not belong to your local commit." }
    $ipa = Join-Path $metadataFile.DirectoryName $metadata.ipa
    if (-not (Test-Path -LiteralPath $ipa -PathType Leaf)) { throw "IPA is missing from the downloaded artifact." }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $ipa).Hash.ToLowerInvariant() -ne $metadata.sha256) { throw "IPA checksum mismatch." }
    Write-Host "Verified unsigned IPA: $ipa"
    Write-Host "Version $($metadata.version), build $($metadata.build). Re-sign before installing on iPhone."
} finally {
    Pop-Location
}
