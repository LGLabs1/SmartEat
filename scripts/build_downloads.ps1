param(
    [switch]$SkipWeb,
    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [switch]$SkipDeploy,
    [switch]$SkipRelease,
    [switch]$SkipVersionBump,
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
$script:AppVersion = $null
$script:DownloadUrls = $null
$apiBaseUrlDefine = '--dart-define=SMARTEAT_API_BASE_URL=https://smarteat-backend-n5ta.onrender.com/api'

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

function New-AppVersion {
    param(
        [int]$Major,
        [int]$Minor,
        [int]$Patch,
        [int]$Build
    )

    $display = "$Major.$Minor.$Patch"
    return @{
        Major   = $Major
        Minor   = $Minor
        Patch   = $Patch
        Build   = $Build
        Display = $display
        Full    = "$display+$Build"
        Tag     = "v$display"
    }
}

function Get-AppVersionInfo {
    $pubspecPath = Join-Path $frontend 'pubspec.yaml'
    $pubspec = Get-Content -LiteralPath $pubspecPath -Raw
    $match = [regex]::Match(
        $pubspec,
        '(?m)^version:\s*(?<major>[0-9]+)\.(?<minor>[0-9]+)\.(?<patch>[0-9]+)\+(?<build>[0-9]+)'
    )
    if (-not $match.Success) {
        throw "Could not read app version from $pubspecPath"
    }

    return @{
        Major = [int]$match.Groups['major'].Value
        Minor = [int]$match.Groups['minor'].Value
        Patch = [int]$match.Groups['patch'].Value
        Build = [int]$match.Groups['build'].Value
    }
}

function Set-AppVersion {
    param([hashtable]$Version)

    $pubspecPath = Join-Path $frontend 'pubspec.yaml'
    $pubspec = Get-Content -LiteralPath $pubspecPath -Raw
    $versionMatch = [regex]::Match(
        $pubspec,
        '(?m)^version:[ \t]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[ \t]*\r?$'
    )
    if (-not $versionMatch.Success) {
        throw "Could not read app version from $pubspecPath"
    }
    $eol = if ($versionMatch.Value.EndsWith("`r")) { "`r" } else { '' }
    $updatedPubspec = $pubspec.Replace(
        $versionMatch.Value,
        "version: $($Version.Full)$eol"
    )
    if ($updatedPubspec -ne $pubspec) {
        Set-Content -LiteralPath $pubspecPath -Value $updatedPubspec -NoNewline
    }

    $appVersionPath = Join-Path $frontend 'lib\config\app_version.dart'
    $appVersionContent = @"
class AppVersion {
  AppVersion._();

  static const String version = '$($Version.Display)';
  static const int buildNumber = $($Version.Build);
  static const String display = '$($Version.Display) ($($Version.Build))';
}
"@
    $existingContent = Get-Content -LiteralPath $appVersionPath -Raw
    if ($existingContent -ne $appVersionContent) {
        Set-Content -LiteralPath $appVersionPath -Value $appVersionContent -NoNewline
    }
}

function Set-DownloadUrls {
    param(
        [string]$Slug,
        [hashtable]$Version
    )

    $path = Join-Path $frontend 'lib\config\app_downloads.dart'
    $original = @(Get-Content -LiteralPath $path)
    $lines = @($original)
    $assetVersion = $Version.Display
    $baseUrl = "https://github.com/$Slug/releases/download/$($Version.Tag)"
    $androidUrl = "$baseUrl/smarteat-android-$assetVersion.apk"
    $windowsUrl = "$baseUrl/smarteat-windows-$assetVersion.zip"
    $script:DownloadUrls = @{
        AndroidApk = $androidUrl
        WindowsZip = $windowsUrl
    }

    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*static const String androidApk\s*=') {
            $lines[$index] = '  static const String androidApk ='
            if ($index + 1 -lt $lines.Count) {
                $lines[$index + 1] = "      '$androidUrl';"
                $index++
            }
        }
        elseif ($lines[$index] -match '^\s*static const String windowsZip\s*=') {
            $lines[$index] = '  static const String windowsZip ='
            if ($index + 1 -lt $lines.Count) {
                $lines[$index + 1] = "      '$windowsUrl';"
                $index++
            }
        }
    }

    if (($lines -join "`n") -ne ($original -join "`n")) {
        Set-Content -LiteralPath $path -Value $lines
    }
}

function Assert-VersionFilesCommitted {
    $versionFiles = @(
        'frontend\pubspec.yaml',
        'frontend\lib\config\app_version.dart',
        'frontend\lib\config\app_downloads.dart'
    )
    $dirty = @(& git -C $repoRoot status --porcelain -- $versionFiles)
    if ($dirty.Count -gt 0) {
        throw "Version files have uncommitted changes; commit and push them before publishing:`n$($dirty -join "`n")"
    }
}

function Test-DownloadUrls {
    if (-not $script:DownloadUrls) {
        throw 'Download URLs were not generated.'
    }

    $urls = @()
    if (-not $SkipAndroid) { $urls += $script:DownloadUrls.AndroidApk }
    if (-not $SkipWindows) { $urls += $script:DownloadUrls.WindowsZip }
    if ($urls.Count -eq 0) { return }

    foreach ($url in $urls) {
        $verified = $false
        $lastError = $null
        for ($attempt = 1; $attempt -le 3 -and -not $verified; $attempt++) {
            try {
                $response = Invoke-WebRequest -Uri $url -Method Head `
                    -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 30
                if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 400) {
                    throw "HTTP $($response.StatusCode)"
                }
                $verified = $true
            }
            catch {
                $lastError = $_.Exception.Message
                if ($attempt -lt 3) { Start-Sleep -Seconds 3 }
            }
        }
        if (-not $verified) {
            throw "Download URL verification failed for $url : $lastError"
        }
        Write-Host "Verified download URL: $url"
    }
}

function Publish-GitHubRelease {
    param(
        [string]$Slug,
        [hashtable]$Version
    )

    $token = Get-GitHubToken
    $releaseTag = $Version.Tag
    $assetVersion = $Version.Display

    $headers = @{
        Authorization = "token $token"
        'User-Agent'  = 'SmartEat-Release'
    }
    $api = "https://api.github.com/repos/$Slug"

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
    if (-not $SkipAndroid -and (Test-Path -LiteralPath $apkPath)) {
        $assets += @{
            Name   = "smarteat-android-$assetVersion.apk"
            Source = 'smarteat-android.apk'
            Type   = 'application/vnd.android.package-archive'
        }
        $assets += @{
            Name   = 'smarteat-android.apk'
            Source = 'smarteat-android.apk'
            Type   = 'application/vnd.android.package-archive'
        }
    }
    if (-not $SkipWindows -and (Test-Path -LiteralPath $zipPath)) {
        $assets += @{
            Name   = "smarteat-windows-$assetVersion.zip"
            Source = 'smarteat-windows.zip'
            Type   = 'application/zip'
        }
        $assets += @{
            Name   = 'smarteat-windows.zip'
            Source = 'smarteat-windows.zip'
            Type   = 'application/zip'
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
        $upload = "https://uploads.github.com/repos/$Slug/releases/$($release.id)/assets?name=$($asset.Name)"
        Invoke-RestMethod -Uri $upload -Method Post -Headers $headers `
            -ContentType $asset.Type -InFile (Join-Path $downloads $asset.Source) `
            -TimeoutSec 900 | Out-Null
    }

    Test-DownloadUrls

    Write-Host "Release ready: https://github.com/$Slug/releases/tag/$releaseTag"
}

$repoSlug = Get-RepoSlug
$currentVersion = Get-AppVersionInfo

if ($Tag -and $Tag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "-Tag must look like v1.0.0 (got '$Tag')."
}

if ($SkipVersionBump) {
    $script:AppVersion = New-AppVersion `
        -Major $currentVersion.Major `
        -Minor $currentVersion.Minor `
        -Patch $currentVersion.Patch `
        -Build $currentVersion.Build
    Write-Host "Using version $($script:AppVersion.Full)"
}
else {
    $script:AppVersion = New-AppVersion `
        -Major $currentVersion.Major `
        -Minor $currentVersion.Minor `
        -Patch ($currentVersion.Patch + 1) `
        -Build ($currentVersion.Build + 1)
    Write-Host "Version bumped to $($script:AppVersion.Full)"
}

if ($Tag -and $Tag -ne $script:AppVersion.Tag) {
    throw "-Tag '$Tag' does not match the release version '$($script:AppVersion.Tag)'. Refusing to write version files."
}

Set-AppVersion $script:AppVersion
Set-DownloadUrls -Slug $repoSlug -Version $script:AppVersion

Push-Location $frontend
try {
    if (-not $SkipWeb) {
        Write-Host 'Building web...'
        Invoke-Native 'flutter build web' 'flutter' @(
            'build', 'web', '--release', '--base-href', '/', '--no-wasm-dry-run', '-O2', $apiBaseUrlDefine
        )
    }

    New-Item -ItemType Directory -Force -Path $downloads | Out-Null

    if (-not $SkipAndroid) {
        Write-Host 'Building Android APK...'
        Invoke-Native 'flutter build apk' 'flutter' @('build', 'apk', '--release', $apiBaseUrlDefine)
        Copy-Item `
            -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' `
            -Destination $apkPath `
            -Force
    }

    if (-not $SkipWindows) {
        Write-Host 'Building Windows app...'
        Invoke-Native 'flutter build windows' 'flutter' @('build', 'windows', '--release', $apiBaseUrlDefine)
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
        Assert-VersionFilesCommitted
        Publish-GitHubRelease -Slug $repoSlug -Version $script:AppVersion
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
