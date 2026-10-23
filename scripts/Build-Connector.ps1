$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory staging -Force | Out-Null
Remove-Item staging/* -Force
Copy-Item Hardcharger.pq,Diagnostics.pqm,SqlGenerator.pqm,SqlGeneratorCommon.pqm,HardchargerAdbcConfig.pqm,TypeInfo.pqm,resources.resx staging/
Copy-Item icons/*.png staging/
Compress-Archive staging/* Hardcharger.zip -Force
Move-Item Hardcharger.zip Hardcharger.mez -Force
if ($env:MAKEPQX) {
    & $env:MAKEPQX pack -mz Hardcharger.mez -t Hardcharger.pqx
    if ($LASTEXITCODE -ne 0) { throw 'MakePQX failed' }
}
