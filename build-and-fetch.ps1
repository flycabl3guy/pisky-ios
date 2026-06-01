# Build PiSky on whatever GitHub account is CURRENTLY logged into gh, on a PUBLIC repo.
# Public repo => free macOS CI. Use a clean account to dodge the billing hold on the old one.
# Run it, walk away (~10-20 min). Ends with an .ipa path OR build-errors.txt.
# Usage:  powershell -ExecutionPolicy Bypass -File C:\Users\flyca\pisky-ios\build-and-fetch.ps1
# (ASCII-only on purpose: Windows PowerShell 5.1 mis-parses non-ASCII characters.)

$gh = "C:\Program Files\GitHub CLI\gh.exe"
Set-Location "C:\Users\flyca\pisky-ios"

$me = (& $gh api user --jq ".login" 2>$null)
if ($me) { $me = $me.Trim() }
if (-not $me) {
    Write-Host "Not logged in. Run this, then re-run me:" -ForegroundColor Red
    Write-Host "   & 'C:\Program Files\GitHub CLI\gh.exe' auth login" -ForegroundColor Red
    exit 1
}
Write-Host ("GitHub account in use: " + $me) -ForegroundColor Cyan
if ($me -eq "ewatts104-bit") {
    Write-Host "That account has the macOS billing hold. Switch to your other account first:" -ForegroundColor Yellow
    Write-Host "   & 'C:\Program Files\GitHub CLI\gh.exe' auth login     (log into the other account)" -ForegroundColor Yellow
    Write-Host "   (or if it is already added:  & '...\gh.exe' auth switch )" -ForegroundColor Yellow
    Write-Host "then re-run this script." -ForegroundColor Yellow
    exit 1
}

Write-Host "1/6  Naming the default branch 'main'..." -ForegroundColor Cyan
git branch -M main

Write-Host ("2/6  Creating / using PUBLIC repo " + $me + "/pisky-ios ...") -ForegroundColor Cyan
git remote remove origin 2>$null
$exists = (& $gh repo view "$me/pisky-ios" --json name 2>$null)
if ($exists) {
    & $gh repo edit "$me/pisky-ios" --visibility public 2>$null
    git remote add origin ("https://github.com/" + $me + "/pisky-ios.git")
    git push -u origin main -f
} else {
    & $gh repo create pisky-ios --public --source . --remote origin --push
}

Write-Host "3/6  Setting default branch to main..." -ForegroundColor Cyan
& $gh repo edit "$me/pisky-ios" --default-branch main 2>$null

Write-Host "4/6  Triggering the iOS build..." -ForegroundColor Cyan
& $gh workflow run ios.yml --ref main
Start-Sleep -Seconds 10

Write-Host "5/6  Watching the run (go do something else)..." -ForegroundColor Cyan
$runId = (& $gh run list --repo "$me/pisky-ios" --workflow=ios.yml --limit 1 --json databaseId --jq ".[0].databaseId").Trim()
if (-not $runId) { Write-Host "No run found. Open the repo Actions tab." -ForegroundColor Red; exit 1 }
$runUrl = (& $gh run view $runId --repo "$me/pisky-ios" --json url --jq ".url").Trim()
Write-Host ("     run #" + $runId + "  " + $runUrl) -ForegroundColor DarkGray
& $gh run watch $runId --repo "$me/pisky-ios" --exit-status --interval 20
$ok = $?

Write-Host ""
if ($ok) {
    Write-Host "6/6  BUILD SUCCEEDED. Downloading the app..." -ForegroundColor Green
    Remove-Item ".\ipa-out" -Recurse -Force -ErrorAction SilentlyContinue
    & $gh run download $runId --repo "$me/pisky-ios" --name PiSky-unsigned-ipa --dir ".\ipa-out"
    $ipa = Get-ChildItem ".\ipa-out" -Recurse -Filter *.ipa | Select-Object -First 1 -ExpandProperty FullName
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host (" YOUR APP:  " + $ipa) -ForegroundColor Green
    Write-Host " Open Sideloadly, drag that .ipa in, sign in with your Apple" -ForegroundColor Green
    Write-Host " ID, hit Start. Enable Developer Mode on the iPhone first:" -ForegroundColor Green
    Write-Host " Settings > Privacy and Security > Developer Mode." -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
} else {
    Write-Host "6/6  BUILD FAILED. Saving the compiler errors..." -ForegroundColor Yellow
    "PiSky iOS build failure" | Out-File -Encoding utf8 ".\build-errors.txt"
    ("run: " + $runUrl) | Out-File -Append -Encoding utf8 ".\build-errors.txt"
    "================================" | Out-File -Append -Encoding utf8 ".\build-errors.txt"
    & $gh run view $runId --repo "$me/pisky-ios" --log-failed 2>$null | Out-File -Append -Encoding utf8 ".\build-errors.txt"
    if ((Get-Item ".\build-errors.txt").Length -lt 200) {
        & $gh run view $runId --repo "$me/pisky-ios" --log 2>$null | Out-File -Append -Encoding utf8 ".\build-errors.txt"
    }
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " Errors saved to:  C:\Users\flyca\pisky-ios\build-errors.txt" -ForegroundColor Yellow
    Write-Host (" Or send me the run link: " + $runUrl) -ForegroundColor Yellow
    Write-Host " I fix, you re-run this script." -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
}
