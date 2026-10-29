$ErrorActionPreference = 'Stop'
$env:HARDCHARGER_ADMIN_PASSWORD = 'hardcharger_password'
New-Item -ItemType Directory -Force .deps/test-home,test-results | Out-Null
$init = (Resolve-Path tests/fixtures.sql).Path
$testHome = (Resolve-Path .deps/test-home).Path
$env:HOME = $testHome
$server = Start-Process $env:HARDCHARGER_SERVER -ArgumentList @('--host','127.0.0.1','--port','31337','--health-port','0','--database',':memory:','--admin-username','hardcharger_user','--print-queries','true','--init-sql-commands-file',"`"$init`"") -WorkingDirectory $testHome -PassThru -RedirectStandardOutput "$PWD/test-results/server.stdout.log" -RedirectStandardError "$PWD/test-results/server.stderr.log"
$oauthServer = Start-Process python -ArgumentList 'tests/oauth_server.py' -PassThru -RedirectStandardOutput "$PWD/test-results/oauth.stdout.log" -RedirectStandardError "$PWD/test-results/oauth.stderr.log"
try {
    $ready = $false
    for ($i=0; $i -lt 40; $i++) {
        if ($server.HasExited) { Get-Content test-results/server.*.log; throw 'Server exited before ready' }
        try { $probe = [Net.Sockets.TcpClient]::new(); $probe.Connect('127.0.0.1', 31337); $probe.Dispose(); $ready=$true; Write-Host "Hardcharger HTTP endpoint ready"; break } catch { Write-Host "Waiting for HTTP readiness: $($_.Exception.Message)"; Start-Sleep 1 }
    }
    if (!$ready) { Get-Content test-results/server.*.log; throw 'Hardcharger did not become ready' }
    $cred = @{
        AuthenticationKind = 'UsernamePassword'
        AuthenticationProperties = @{Username='hardcharger_user';Password=$env:HARDCHARGER_ADMIN_PASSWORD}
        PrivacySetting = 'None'; Permissions = @()
    } | ConvertTo-Json
    $cred | & $env:PQTEST set-credential -e Hardcharger.mez -q tests/Navigation.query.pq
    if ($LASTEXITCODE -ne 0) { throw 'PQTest set-credential failed' }
    $output = & $env:PQTEST run-test -e Hardcharger.mez -q tests -p --testFilter '!ConnectionOptions.query.pq' --testFilter '!OAuth.query.pq'
    $code = $LASTEXITCODE
    $output | Set-Content test-results/pqtest.json
    Write-Host ($output -join "`n")
    if ($code -ne 0) { throw "PQTest exited $code" }
    $results = @($output | ConvertFrom-Json)
    # The test hook is invoked outside Power BI's OAuth-handler context, so
    # explicitly grant anonymous Web credentials to the loopback OAuth fixtures
    # (a current server and one released before the protocol rename).
    $anonymous = @{AuthenticationKind='Anonymous'; AuthenticationProperties=@{}; PrivacySetting='None'; Permissions=@()} | ConvertTo-Json
    foreach ($fixture in @('http://127.0.0.1:31338', 'http://127.0.0.1:31339')) {
        $anonymous | & $env:PQTEST set-credential -e Hardcharger.Test.mez -dsk Web -dsp $fixture
        if ($LASTEXITCODE -ne 0) { throw "OAuth fixture credential setup failed for $fixture" }
    }
    foreach ($name in @('ConnectionOptions','OAuth')) {
        $unit = & $env:PQTEST run-test -e Hardcharger.Test.mez -q "tests/$name.query.pq" -p
        $unitCode = $LASTEXITCODE
        $unit | Set-Content "test-results/$name.json"
        Write-Host ($unit -join "`n")
        if ($unitCode -ne 0) { throw "$name PQTest exited $unitCode" }
        $results += @($unit | ConvertFrom-Json)
    }
    $expected = @(Get-ChildItem tests/*.query.pq).Count
    if ($results.Count -ne $expected -or $expected -lt 9) { throw "Expected $expected tests; got $($results.Count)" }
    $failed = @($results | Where-Object Status -ne 'Passed')
    $failureCount = $failed.Count
    # DirectQuery requires folding, not merely a correct client-side result.
    foreach ($query in @('Aggregation','ColumnSelection','Filtering','Sorting','TopN','DirectQueryJoin','TextFolding')) {
        $foldOutput = & $env:PQTEST run-test -e Hardcharger.mez -q "tests/$query.query.pq" -p --failOnFoldingFailure
        $foldCode = $LASTEXITCODE
        $foldOutput | Set-Content "test-results/folding-$query.json"
        $foldResults = @($foldOutput | ConvertFrom-Json)
        if ($foldCode -ne 0 -or $foldResults.Count -ne 1 -or $foldResults[0].Status -ne 'Passed') {
            Write-Host ($foldOutput -join "`n")
            Write-Host "DirectQuery folding failed: $query"
            $failureCount++
        }
    }
    # Separate end-to-end checks use the same released native ADBC DLL.
    python tests/test_driver.py
    if ($LASTEXITCODE -ne 0) { $failureCount++ }
    if ($failureCount -gt 0) { throw "$failureCount Power Query/folding/native test groups failed" }
    Write-Host "All $expected Power Query tests and native driver tests passed."
} finally {
    if (!$server.HasExited) { Stop-Process -Id $server.Id -Force }
    if (!$oauthServer.HasExited) { Stop-Process -Id $oauthServer.Id -Force }
}
