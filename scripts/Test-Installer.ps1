$ErrorActionPreference = 'Stop'
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Power BI Desktop'
$sentinel = '0123456789ABCDEF0123456789ABCDEF01234567'
New-Item $policy -Force | Out-Null
New-ItemProperty $policy -Name TrustedCertificateThumbprints -PropertyType MultiString -Value @($sentinel) -Force | Out-Null
$msi = (Resolve-Path Hardcharger-PowerBI-Setup-x64.msi).Path
function Run-Msi($Args) {
    $proc = Start-Process msiexec.exe -ArgumentList $Args -Wait -PassThru
    if ($proc.ExitCode -notin @(0,3010)) { throw "msiexec failed with $($proc.ExitCode)" }
}
Run-Msi "/i `"$msi`" /qn /norestart /l*v `"$PWD/install.log`""
$folder = "$env:ProgramFiles\Microsoft Power BI Desktop\bin\ADBC Drivers\Hardcharger"
$documents = [Environment]::GetFolderPath('MyDocuments')
foreach ($name in @('libadbc_driver_hardcharger.dll','LICENSE','THIRD_PARTY_NOTICES')) {
    if (!(Test-Path "$folder\$name")) { throw "Installed driver file missing: $name" }
}
foreach ($name in @('Power BI Desktop','Microsoft Power BI Desktop')) {
    $pqx = "$documents\$name\Custom Connectors\Hardcharger.pqx"
    if (!(Test-Path $pqx)) { throw "Installed connector missing: $pqx" }
    if ((Get-FileHash $pqx).Hash -ne (Get-FileHash Hardcharger.pqx).Hash) { throw 'Installed PQX differs from signed artifact' }
}
$trusted = (Get-ItemProperty $policy).TrustedCertificateThumbprints
if ($sentinel -notin $trusted -or $env:CERT_THUMBPRINT -notin $trusted) { throw 'Installer failed to append signer trust while preserving existing policy' }
# A repair must retain the exact same signed payload.
Run-Msi "/fa `"$msi`" /qn /norestart /l*v `"$PWD/repair.log`""
Run-Msi "/x `"$msi`" /qn /norestart /l*v `"$PWD/uninstall.log`""
if (Test-Path "$folder\libadbc_driver_hardcharger.dll") { throw 'Driver remains after uninstall' }
if ($sentinel -notin (Get-ItemProperty $policy).TrustedCertificateThumbprints) { throw 'Uninstall removed pre-existing policy entry' }
foreach ($name in @('Power BI Desktop','Microsoft Power BI Desktop')) {
    if (Test-Path "$documents\$name\Custom Connectors\Hardcharger.pqx") { throw 'Connector remains after uninstall' }
}
Write-Host 'Install, repair, trust policy preservation and uninstall passed.'
