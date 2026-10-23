$ErrorActionPreference = 'Stop'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'MSVC x64 build tools are required for the installer trust detector' }
$vcvars = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
New-Item -ItemType Directory -Force .deps | Out-Null
$batch = @"
@echo off
call "$vcvars" >nul
if errorlevel 1 exit /b 1
cl /nologo /LD /MT /O2 /W4 /WX /Fo:.deps/trust-policy.obj installer/trust-policy.cpp /link /OUT:installer/trust-policy.dll /IMPLIB:.deps/trust-policy.lib msi.lib advapi32.lib
"@
Set-Content .deps/build-trust-action.cmd $batch
cmd.exe /d /c .deps\build-trust-action.cmd
if ($LASTEXITCODE -ne 0) { throw 'Native installer trust detector compilation failed' }
