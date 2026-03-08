Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$jniLibsDir = Join-Path $repoRoot 'flutter_app\android\app\src\main\jniLibs'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("openclaw-proot-" + [System.Guid]::NewGuid().ToString('N'))
$repoBase = 'https://packages.termux.dev/apt/termux-main'
$packageIndexCache = @{}

New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

function Get-TermuxPackageFilename {
    param(
        [string]$PackageName,
        [string]$DebArch
    )

    if (-not $packageIndexCache.ContainsKey($DebArch)) {
        $packagesPath = Join-Path $tempRoot ("Packages-$DebArch.txt")
        $packagesUrl = "$repoBase/dists/stable/main/binary-$DebArch/Packages"
        & curl.exe -fsSL $packagesUrl -o $packagesPath
        $packageIndexCache[$DebArch] = $packagesPath
    }

    $packagesFile = $packageIndexCache[$DebArch]
    $match = Select-String -Path $packagesFile -Pattern "^Package: $([regex]::Escape($PackageName))$" -Context 0,12 | Select-Object -First 1
    if ($match) {
        foreach ($line in $match.Context.PostContext) {
            if ($line -match '^Filename:\s+(.+)$') {
                return $Matches[1].Trim()
            }
        }
    }

    throw "Package $PackageName not found for architecture $DebArch"
}

function Expand-DebPackage {
    param(
        [string]$DebPath,
        [string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Push-Location $Destination
    try {
        & ar.exe x $DebPath | Out-Null

        if (Test-Path 'data.tar.xz') {
            & xz.exe -d -k 'data.tar.xz' | Out-Null
            tar -xf 'data.tar' | Out-Null
        } elseif (Test-Path 'data.tar.gz') {
            tar -xf 'data.tar.gz' | Out-Null
        } elseif (Test-Path 'data.tar.zst') {
            tar -xf 'data.tar.zst' | Out-Null
        } else {
            throw "Unsupported deb payload format in $DebPath"
        }
    } finally {
        Pop-Location
    }
}

function Copy-FirstMatch {
    param(
        [string[]]$Patterns,
        [string]$DestinationPath,
        [switch]$AllowMissing
    )

    foreach ($pattern in $Patterns) {
        $item = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($item) {
            Copy-Item -LiteralPath $item.FullName -Destination $DestinationPath -Force
            return $true
        }
    }

    if (-not $AllowMissing) {
        throw "No file matched patterns: $($Patterns -join ', ')"
    }

    return $false
}

function Fetch-ForAbi {
    param(
        [string]$JniAbi,
        [string]$DebArch
    )

    Write-Host "[$JniAbi] Fetching binaries..."
    $outDir = Join-Path $jniLibsDir $JniAbi
    $extractBase = Join-Path $tempRoot $JniAbi
    $prootExtract = Join-Path $extractBase 'proot'
    $tallocExtract = Join-Path $extractBase 'libtalloc'

    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    $prootFilename = Get-TermuxPackageFilename -PackageName 'proot' -DebArch $DebArch
    $prootDeb = Join-Path $tempRoot ("proot-$DebArch.deb")
    & curl.exe -fsSL "$repoBase/$prootFilename" -o $prootDeb
    Expand-DebPackage -DebPath $prootDeb -Destination $prootExtract

    $tallocFilename = Get-TermuxPackageFilename -PackageName 'libtalloc' -DebArch $DebArch
    $tallocDeb = Join-Path $tempRoot ("libtalloc-$DebArch.deb")
    & curl.exe -fsSL "$repoBase/$tallocFilename" -o $tallocDeb
    Expand-DebPackage -DebPath $tallocDeb -Destination $tallocExtract

    Copy-FirstMatch -Patterns @(
        (Join-Path $prootExtract 'data\data\com.termux\files\usr\bin\proot'),
        (Join-Path $prootExtract '**\bin\proot')
    ) -DestinationPath (Join-Path $outDir 'libproot.so') | Out-Null

    Copy-FirstMatch -Patterns @(
        (Join-Path $prootExtract 'data\data\com.termux\files\usr\libexec\proot\loader'),
        (Join-Path $prootExtract '**\proot\loader')
    ) -DestinationPath (Join-Path $outDir 'libprootloader.so') | Out-Null

    Copy-FirstMatch -Patterns @(
        (Join-Path $prootExtract 'data\data\com.termux\files\usr\libexec\proot\loader32'),
        (Join-Path $prootExtract '**\proot\loader32')
    ) -DestinationPath (Join-Path $outDir 'libprootloader32.so') -AllowMissing | Out-Null

    Copy-FirstMatch -Patterns @(
        (Join-Path $tallocExtract 'data\data\com.termux\files\usr\lib\libtalloc.so.*'),
        (Join-Path $tallocExtract '**\libtalloc.so.*'),
        (Join-Path $tallocExtract '**\libtalloc.so')
    ) -DestinationPath (Join-Path $outDir 'libtalloc.so') | Out-Null

    Get-ChildItem $outDir -File | ForEach-Object {
        Write-Host "[$JniAbi] $($_.Name) ($([Math]::Round($_.Length / 1KB, 1)) KB)"
    }
}

try {
    Fetch-ForAbi -JniAbi 'arm64-v8a' -DebArch 'aarch64'
    Fetch-ForAbi -JniAbi 'armeabi-v7a' -DebArch 'arm'
    Fetch-ForAbi -JniAbi 'x86_64' -DebArch 'x86_64'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}