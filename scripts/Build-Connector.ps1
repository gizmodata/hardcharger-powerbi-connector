$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory staging -Force | Out-Null
Remove-Item staging/* -Force
Copy-Item Hardcharger.pq,Diagnostics.pqm,SqlGenerator.pqm,SqlGeneratorCommon.pqm,HardchargerAdbcConfig.pqm,PreRenameCompat.pqm,TypeInfo.pqm,resources.resx,LICENSE,THIRD_PARTY_NOTICES.md staging/
Copy-Item icons/*.png staging/
Compress-Archive staging/* Hardcharger.zip -Force
Move-Item Hardcharger.zip Hardcharger.mez -Force
if ($env:MAKEPQX) {
    & $env:MAKEPQX pack -mz Hardcharger.mez -t Hardcharger.pqx
    if ($LASTEXITCODE -ne 0) { throw 'MakePQX failed' }
}

# Test-only seam: never included in the production MEZ/PQX or installer.
Add-Content staging/Hardcharger.pq @'
shared Hardcharger.TestHelpers = () => [BuildUri = BuildUri, MapCredentialProperties = MapCredentialProperties, OAuthBaseUrl = OAuthBaseUrl, StartLogin = StartLogin, FinishLogin = FinishLogin];
'@
Compress-Archive staging/* Hardcharger.Test.zip -Force
Move-Item Hardcharger.Test.zip Hardcharger.Test.mez -Force
