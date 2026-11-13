param(
    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [switch]$SkipDeploy,
    [switch]$SkipRelease,
    [string]$Tag
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$frontend = Join-Path $repoRoot 'frontend'
# Keep installers out of the Firebase Hosting public folder: Spark-plan
# Hosting refuses to serve executable files. GitHub Releases serves them.
$downloads = Join-Path $frontend 'build\downloads'
$apkPath = Join-Path $downloads 'smarteat-android.apk'
$zipPath = Join-Path $downloads 'smarteat-windows.zip'

# Native tools (flutter, firebase) write progress and warnings to stderr.
# Windows PowerShell 5.1 turns that into a terminating error while
# $ErrorActionPreference is 'Stop', so merge the streams and check the exit
# code ourselves instead.
function Invoke-Native {
    param(
        [string]$Label,
        [string]$Command,
        [string[]]$Arguments
    )

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Command @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }

    if ($code -ne 0) {
        throw "$Label failed with exit code $code"
    }
}

function Get-GitHubToken {
    if ($env:GH_TOKEN) { return $env:GH_TOKEN }
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }

    $cred = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
    $line = $cred | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
    if ($line) { return ($line -replace '^password=', '') }

    throw 'No GitHub token found. Set GH_TOKEN or sign in with git first.'
}

function Get-RepoSlug {
    $url = (& git -C $repoRoot remote get-url origin).Trim()
    if ($url -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') {
        return "$($Matches.owner)/$($Matches.repo)"
    }
    throw "Could not parse a GitHub repository from origin: $url"
}

function Publish-GitHubRelease {
    $token = Get-GitHubToken
    $slug = Get-RepoSlug
    $releaseTag = $Tag
    if (-not $releaseTag) {
        $pubspec = Get-Content (Join-Path $frontend 'pubspec.yaml') -Raw
        $match = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
        $version = if ($match.Success) { $match.Groups[1].Value } else { '1.0.0' }
        $releaseTag = "v$version"
    }

    $headers = @{
        Authorization = "token $token"
        'User-Agent'  = 'SmartEat-Release'
    }
    $api = "https://api.github.com/repos/$slug"

    $release = $null
    try {
        $release = Invoke-RestMethod -Uri "$api/releases/tags/$releaseTag" `
            -Headers $headers -TimeoutSec 30
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -ne 404) { throw }
    }

    if (-not $release) {
        Write-Host "Creating GitHub release $releaseTag..."
        $body = @{
            tag_name         = $releaseTag
            target_commitish = 'main'
            name             = "SmartEat $releaseTag"
            body             = 'Installable SmartEat builds for Android and Windows.'
            draft            = $false
            prerelease       = $false
        } | ConvertTo-Json
        $release = Invoke-RestMethod -Uri "$api/releases" -Method Post `
            -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 30
    }

    $assets = @()
    if (Test-Path -LiteralPath $apkPath) {
        $assets += @{
            Name = 'smarteat-android.apk'
            Type = 'application/vnd.android.package-archive'
        }
    }
    if (Test-Path -LiteralPath $zipPath) {
        $assets += @{
            Name = 'smarteat-windows.zip'
            Type = 'application/zip'
        }
    }

    foreach ($asset in $assets) {
        $existing = $release.assets |
            Where-Object { $_.name -eq $asset.Name } |
            Select-Object -First 1
        if ($existing) {
            Write-Host "Removing existing asset $($asset.Name)..."
            Invoke-RestMethod -Uri "$api/releases/assets/$($existing.id)" `
                -Method Delete -Headers $headers -TimeoutSec 30 | Out-Null
        }

        Write-Host "Uploading $($asset.Name)..."
        $upload = "https://uploads.github.com/repos/$slug/releases/$($release.id)/assets?name=$($asset.Name)"
        Invoke-RestMethod -Uri $upload -Method Post -Headers $headers `
            -ContentType $asset.Type -InFile (Join-Path $downloads $asset.Name) `
            -TimeoutSec 900 | Out-Null
    }

    Write-Host "Release ready: https://github.com/$slug/releases/tag/$releaseTag"
}

Push-Location $frontend
try {
    Write-Host 'Building web...'
    Invoke-Native 'flutter build web' 'flutter' @('build', 'web', '--release')

    New-Item -ItemType Directory -Force -Path $downloads | Out-Null

    if (-not $SkipAndroid) {
        Write-Host 'Building Android APK...'
        Invoke-Native 'flutter build apk' 'flutter' @('build', 'apk', '--release')
        Copy-Item `
            -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' `
            -Destination $apkPath `
            -Force
    }

    if (-not $SkipWindows) {
        Write-Host 'Building Windows app...'
        Invoke-Native 'flutter build windows' 'flutter' @('build', 'windows', '--release')
        $winRelease = 'build\windows\x64\runner\Release'
        if (-not (Test-Path -LiteralPath $winRelease)) {
            throw "Windows release folder not found: $winRelease"
        }
        if (Test-Path -LiteralPath $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force
        }
        Compress-Archive -Path (Join-Path $winRelease '*') -DestinationPath $zipPath
    }

    Write-Host "Installers staged in $downloads"

    if (-not $SkipRelease) {
        Publish-GitHubRelease
    }

    if (-not $SkipDeploy) {
        Push-Location $repoRoot
        try {
            Write-Host 'Deploying hosting...'
            Invoke-Native 'firebase deploy' 'firebase' @(
                'deploy', '--only', 'hosting',
                '--project', 'smart-eat-2eaf7', '--non-interactive'
            )
        }
        finally {
            Pop-Location
        }
    }
}
finally {
    Pop-Location
}
