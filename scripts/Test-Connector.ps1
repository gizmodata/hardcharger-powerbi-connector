$ErrorActionPreference = 'Stop'
$env:HARDCHARGER_ADMIN_PASSWORD = 'hardcharger_password'
New-Item -ItemType Directory -Force .deps/test-home,test-results | Out-Null
$init = (Resolve-Path tests/fixtures.sql).Path
$testHome = (Resolve-Path .deps/test-home).Path
$env:HOME = $testHome
$server = Start-Process $env:HARDCHARGER_SERVER -ArgumentList @('--host','127.0.0.1','--port','31337','--health-port','0','--database',':memory:','--admin-username','hardcharger_user','--print-queries','true','--init-sql-commands-file',"`"$init`"") -WorkingDirectory $testHome -PassThru -RedirectStandardOutput "$PWD/test-results/server.stdout.log" -RedirectStandardError "$PWD/test-results/server.stderr.log"
try {
    $ready = $false
    for ($i=0; $i -lt 40; $i++) {
        if ($server.HasExited) { Get-Content test-results/server.*.log; throw 'Server exited before ready' }
        try { Invoke-WebRequest http://localhost:31337/warp -TimeoutSec 2 | Out-Null; $ready=$true; break } catch { Start-Sleep 1 }
    }
    if (!$ready) { throw 'Hardcharger did not become ready' }
    $cred = @{
        AuthenticationKind = 'UsernamePassword'
        AuthenticationProperties = @{Username='hardcharger_user';Password=$env:HARDCHARGER_ADMIN_PASSWORD}
        PrivacySetting = 'None'; Permissions = @()
    } | ConvertTo-Json
    $cred | & $env:PQTEST set-credential -e Hardcharger.mez -q tests/Navigation.query.pq
    if ($LASTEXITCODE -ne 0) { throw 'PQTest set-credential failed' }
    $output = & $env:PQTEST run-test -e Hardcharger.mez -q tests -p -hm tests/oauth-http-mock.txt
    $code = $LASTEXITCODE
    $output | Set-Content test-results/pqtest.json
    Write-Host ($output -join "`n")
    if ($code -ne 0) { throw "PQTest exited $code" }
    $results = @($output | ConvertFrom-Json)
    $expected = @(Get-ChildItem tests/*.query.pq).Count
    if ($results.Count -ne $expected -or $expected -lt 9) { throw "Expected $expected tests; got $($results.Count)" }
    $failed = @($results | Where-Object Status -ne 'Passed')
    if ($failed.Count -gt 0) { throw "$($failed.Count) Power Query tests failed" }
    # DirectQuery requires folding, not merely a correct client-side result.
    foreach ($query in @('Aggregation','ColumnSelection','Filtering','Sorting','TopN','Join','TextFolding')) {
        $foldOutput = & $env:PQTEST run-test -e Hardcharger.mez -q "tests/$query.query.pq" -p --failOnFoldingFailure
        $foldCode = $LASTEXITCODE
        $foldOutput | Set-Content "test-results/folding-$query.json"
        $foldResults = @($foldOutput | ConvertFrom-Json)
        if ($foldCode -ne 0 -or $foldResults.Count -ne 1 -or $foldResults[0].Status -ne 'Passed') {
            Write-Host ($foldOutput -join "`n")
            throw "DirectQuery folding failed: $query"
        }
    }
    # Separate end-to-end checks use the same released native ADBC DLL.
    python tests/test_driver.py
    if ($LASTEXITCODE -ne 0) { throw 'Native driver tests failed' }
    Write-Host "All $expected Power Query tests and native driver tests passed."
} finally {
    if (!$server.HasExited) { Stop-Process -Id $server.Id -Force }
}
