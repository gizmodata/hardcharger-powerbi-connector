param([ValidateSet('Sdk','Driver','Server')][string]$Component)
$ErrorActionPreference = 'Stop'
$lock = Get-Content "$PSScriptRoot/../dependencies.json" -Raw | ConvertFrom-Json
function Assert-Hash($Path, $Expected) {
    $actual = (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected) { throw "SHA256 mismatch for $Path ($actual)" }
}
New-Item -ItemType Directory -Force .deps | Out-Null
switch ($Component) {
    'Sdk' {
        $dep = $lock.powerQuerySdk
        Invoke-WebRequest $dep.url -OutFile .deps/sdktools.zip
        Assert-Hash .deps/sdktools.zip $dep.sha256
        Expand-Archive .deps/sdktools.zip .deps/sdktools -Force
        foreach ($tool in @('PQTest','MakePQX')) {
            $exe = (Get-ChildItem .deps/sdktools -Filter "$tool.exe" -Recurse | Select-Object -First 1).FullName
            if (!$exe) { throw "$tool.exe missing in SDK $($dep.version)" }
            if ($env:GITHUB_ENV) { "$($tool.ToUpperInvariant())=$exe" >> $env:GITHUB_ENV }
            Write-Host "$tool = $exe"
        }
    }
    'Driver' {
        $dep = $lock.hardchargerAdbc
        gh release download "v$($dep.version)" --repo $dep.repo --pattern $dep.asset --dir .deps --clobber
        if ($LASTEXITCODE -ne 0) { throw 'Driver download failed' }
        Assert-Hash ".deps/$($dep.asset)" $dep.sha256
        New-Item -ItemType Directory -Force .deps/driver-unpacked,installer/bin | Out-Null
        tar -xzf ".deps/$($dep.asset)" -C .deps/driver-unpacked
        if ($LASTEXITCODE -ne 0) { throw 'Driver extraction failed' }
        foreach ($name in @('libadbc_driver_hardcharger.dll','LICENSE','THIRD_PARTY_NOTICES')) {
            $file = Get-ChildItem .deps/driver-unpacked -Filter $name -Recurse | Select-Object -First 1
            if (!$file) { throw "$name missing in driver release" }
            Copy-Item $file.FullName installer/bin/
        }
        if ($env:PQTEST) {
            $sdkDrivers = Join-Path (Split-Path $env:PQTEST) 'Mashup/ADBC Drivers/Hardcharger'
            New-Item -ItemType Directory -Force $sdkDrivers | Out-Null
            Copy-Item installer/bin/libadbc_driver_hardcharger.dll $sdkDrivers/
        }
        $driverDir = (Resolve-Path installer/bin).Path
        if ($env:GITHUB_PATH) { $driverDir >> $env:GITHUB_PATH }
        $env:PATH = "$driverDir;$env:PATH"
    }
    'Server' {
        $dep = $lock.hardchargerServer
        gh release download "v$($dep.version)" --repo $dep.repo --pattern $dep.asset --dir .deps --clobber
        if ($LASTEXITCODE -ne 0) { throw 'Server download failed' }
        Assert-Hash ".deps/$($dep.asset)" $dep.sha256
        Expand-Archive ".deps/$($dep.asset)" .deps/server -Force
        $exe = (Get-ChildItem .deps/server -Filter hardcharger-server.exe -Recurse | Select-Object -First 1).FullName
        if (!$exe) { throw 'hardcharger-server.exe missing in release' }
        if ($env:GITHUB_ENV) { "HARDCHARGER_SERVER=$exe" >> $env:GITHUB_ENV }
    }
}
