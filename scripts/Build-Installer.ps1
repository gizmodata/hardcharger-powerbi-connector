param([string]$Version = '1.0.0', [Parameter(Mandatory)][string]$CertThumbprint)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must be X.Y.Z' }
if ($CertThumbprint -notmatch '^[0-9A-Fa-f]{40}$') { throw 'Expected SHA1 certificate thumbprint' }
$deps = Get-Content "$PSScriptRoot/../dependencies.json" -Raw | ConvertFrom-Json
dotnet tool install --global wix --version $deps.wix
if ($LASTEXITCODE -ne 0) { throw 'WiX installation failed' }
wix extension add "WixToolset.UI.wixext/$($deps.wix)"
if ($LASTEXITCODE -ne 0) { throw 'WiX UI extension installation failed' }
New-Item -ItemType Directory -Force installer/connector | Out-Null
Copy-Item Hardcharger.pqx installer/connector/
$license = Get-Content LICENSE -Raw
$escaped = $license.Replace('\','\\').Replace('{','\{').Replace('}','\}') -replace "`r?`n", '\par '
Set-Content installer/license.rtf ('{\rtf1\ansi\deff0 {\fonttbl {\f0 Consolas;}}\f0\fs18 ' + $escaped + '}')
wix build installer/HardchargerBundle.wxs -arch x64 -d ProductVersion=$Version -d CertThumbprint=$CertThumbprint -b BinDir=installer/bin -b ConnectorDir=installer/connector -b installer -b . -o Hardcharger-PowerBI-Setup-x64.msi -ext WixToolset.UI.wixext
if ($LASTEXITCODE -ne 0) { throw 'MSI build failed' }
