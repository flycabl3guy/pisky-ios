# One-shot: align the repo (public + workflow on default branch), build on GitHub's free Macs,
# and fetch the result. Run it, walk away (~10-20 min). Ends with an .ipa path OR build-errors.txt.
# Usage:  powershell -ExecutionPolicy Bypass -File C:\Users\flyca\pisky-ios\build-and-fetch.ps1
# (ASCII-only on purpose: Windows PowerShell 5.1 mis-parses non-ASCII characters in scripts.)

$gh = "C:\Program Files\GitHub CLI\gh.exe"
Set-Location "C:\Users\flyca\pisky-ios"

Write-Host "1/6  Ensuring the repo is public (free macOS CI)..." -ForegroundColor Cyan
& $gh repo edit --visibility public --accept-visibility-change-consequences 2>$null

Write-Host "2/6  Putting the latest code + workflow on branch 'main'..." -ForegroundColor Cyan
git push origin HEAD:main -f

Write-Host "3/6  Making 'main' the default branch (so the workflow is found)..." -ForegroundColor Cyan
& $gh repo edit --default-branch main 2>$null

Write-Host "4/6  Triggering the iOS build on main..." -ForegroundColor Cyan
& $gh workflow run ios.yml --ref main
Start-Sleep -Seconds 10

Write-Host "5/6  Watching the run (go do something else)..." -ForegroundColor Cyan
$runId = (& $gh run list --workflow=ios.yml --limit 1 --json databaseId --jq ".[0].databaseId").Trim()
if (-not $runId) {
    Write-Host "No run found. Open the repo Actions tab to check." -ForegroundColor Red
    exit 1
}
$runUrl = (& $gh run view $runId --json url --jq ".url").Trim()
Write-Host ("     run #" + $runId + "  " + $runUrl) -ForegroundColor DarkGray
& $gh run watch $runId --exit-status --interval 20
$ok = $?

Write-Host ""
if ($ok) {
    Write-Host "6/6  BUILD SUCCEEDED. Downloading the app..." -ForegroundColor Green
    Remove-Item ".\ipa-out" -Recurse -Force -ErrorAction SilentlyContinue
    & $gh run download $runId --name PiSky-unsigned-ipa --dir ".\ipa-out"
    $ipa = Get-ChildItem ".\ipa-out" -Recurse -Filter *.ipa | Select-Object -First 1 -ExpandProperty FullName
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host (" YOUR APP:  " + $ipa) -ForegroundColor Green
    Write-Host " Open Sideloadly, drag that .ipa in, sign in with your Apple" -ForegroundColor Green
    Write-Host " ID, hit Start. Enable Developer Mode on the iPhone first:" -ForegroundColor Green
    Write-Host " Settings > Privacy and Security > Developer Mode." -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
} else {
    Write-Host "6/6  BUILD FAILED. Saving everything we need to fix it..." -ForegroundColor Yellow
    "PiSky iOS build failure" | Out-File -Encoding utf8 ".\build-errors.txt"
    ("run: " + $runUrl) | Out-File -Append -Encoding utf8 ".\build-errors.txt"
    "================================" | Out-File -Append -Encoding utf8 ".\build-errors.txt"
    & $gh run view $runId --log-failed 2>$null | Out-File -Append -Encoding utf8 ".\build-errors.txt"
    if ((Get-Item ".\build-errors.txt").Length -lt 200) {
        & $gh run view $runId --log 2>$null | Out-File -Append -Encoding utf8 ".\build-errors.txt"
    }
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " Errors saved to:  C:\Users\flyca\pisky-ios\build-errors.txt" -ForegroundColor Yellow
    Write-Host (" Or just send me the run link: " + $runUrl) -ForegroundColor Yellow
    Write-Host " I fix it, you re-run this same script." -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
}
