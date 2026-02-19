################################################################################
# Version A vs C 비교 부하 테스트
#
# 사용법: .\load-test-compare.ps1 -Users 100
#
# 두 버전을 순차적으로 테스트하고 결과를 비교합니다.
# 주의: 두 Docker Compose가 모두 실행 중이어야 합니다.
#   docker-compose -f docker-compose-version-a.yml up -d --build
#   docker-compose -f docker-compose-version-c.yml up -d --build
################################################################################

param(
    [int]$Users = 100,
    [int]$ProductId = 1
)

function Run-LoadTest {
    param(
        [string]$BaseUrl,
        [string]$VersionName,
        [int]$UserCount,
        [int]$ProdId
    )

    $body = "{`"productId`": $ProdId}"
    $results = @()
    $jobs = @()
    $startTime = Get-Date

    for ($i = 1; $i -le $UserCount; $i++) {
        $sessionId = "compare-$VersionName-$i"
        $jobs += Start-Job -ScriptBlock {
            param($url, $sid, $reqBody)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $resp = Invoke-WebRequest -Uri "$url/api/queue/enter" `
                    -Method POST `
                    -Headers @{ "Content-Type" = "application/json"; "X-Session-Id" = $sid } `
                    -Body $reqBody -TimeoutSec 30 -ErrorAction Stop
                $sw.Stop()
                return [PSCustomObject]@{ Success=$true; Time=$sw.ElapsedMilliseconds }
            } catch {
                $sw.Stop()
                return [PSCustomObject]@{ Success=$false; Time=$sw.ElapsedMilliseconds }
            }
        } -ArgumentList $BaseUrl, $sessionId, $body
    }

    $results = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job
    $totalTime = ((Get-Date) - $startTime).TotalSeconds

    $successes = ($results | Where-Object { $_.Success }).Time | Sort-Object
    $successCount = $successes.Count
    $failCount = $UserCount - $successCount

    if ($successes.Count -gt 0) {
        return [PSCustomObject]@{
            Version = $VersionName
            Users = $UserCount
            Success = $successCount
            Fail = $failCount
            SuccessRate = [math]::Round($successCount/$UserCount*100, 1)
            TotalSec = [math]::Round($totalTime, 2)
            Throughput = [math]::Round($UserCount/$totalTime, 1)
            AvgMs = [math]::Round(($successes | Measure-Object -Average).Average, 0)
            P50Ms = $successes[[math]::Floor($successes.Count * 0.5)]
            P95Ms = $successes[[math]::Floor($successes.Count * 0.95)]
            P99Ms = $successes[[math]::Floor($successes.Count * 0.99)]
            MaxMs = $successes[-1]
        }
    }
    return $null
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  OliveYoung Load Test: Version A vs Version C" -ForegroundColor Cyan
Write-Host "  Concurrent Users: $Users" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# Version A 테스트
Write-Host "`n>>> Testing Version A (Circuit Breaker + Single Broker)..." -ForegroundColor Yellow
$resultA = Run-LoadTest -BaseUrl "http://localhost:8080" -VersionName "A" -UserCount $Users -ProdId $ProductId

# 5초 대기 (시스템 안정화)
Write-Host ">>> Cooling down 5s..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# Version C 테스트
Write-Host ">>> Testing Version C (3-Broker Cluster + DLQ)..." -ForegroundColor Yellow
$resultC = Run-LoadTest -BaseUrl "http://localhost:8081" -VersionName "C" -UserCount $Users -ProdId $ProductId

# 비교 결과 출력
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  COMPARISON RESULTS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$header = "{0,-18} {1,12} {2,12}" -f "Metric", "Version A", "Version C"
Write-Host $header -ForegroundColor White
Write-Host ("-" * 44) -ForegroundColor Gray

if ($resultA -and $resultC) {
    $rows = @(
        @("Success Rate", "$($resultA.SuccessRate)%", "$($resultC.SuccessRate)%"),
        @("Throughput", "$($resultA.Throughput) req/s", "$($resultC.Throughput) req/s"),
        @("Avg Latency", "$($resultA.AvgMs)ms", "$($resultC.AvgMs)ms"),
        @("P50 Latency", "$($resultA.P50Ms)ms", "$($resultC.P50Ms)ms"),
        @("P95 Latency", "$($resultA.P95Ms)ms", "$($resultC.P95Ms)ms"),
        @("P99 Latency", "$($resultA.P99Ms)ms", "$($resultC.P99Ms)ms"),
        @("Max Latency", "$($resultA.MaxMs)ms", "$($resultC.MaxMs)ms"),
        @("Failures", "$($resultA.Fail)", "$($resultC.Fail)")
    )

    foreach ($row in $rows) {
        $line = "{0,-18} {1,12} {2,12}" -f $row[0], $row[1], $row[2]
        Write-Host $line
    }

    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  ANALYSIS" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan

    # 속도 비교
    if ($resultA.AvgMs -lt $resultC.AvgMs) {
        $faster = "A"
        $diff = [math]::Round(($resultC.AvgMs - $resultA.AvgMs) / $resultC.AvgMs * 100, 1)
    } else {
        $faster = "C"
        $diff = [math]::Round(($resultA.AvgMs - $resultC.AvgMs) / $resultA.AvgMs * 100, 1)
    }
    Write-Host "  Speed: Version $faster is ${diff}% faster (avg latency)" -ForegroundColor Green

    # 안정성 비교
    if ($resultA.SuccessRate -ge $resultC.SuccessRate) {
        Write-Host "  Reliability: Version A ($($resultA.SuccessRate)%) >= Version C ($($resultC.SuccessRate)%)" -ForegroundColor White
    } else {
        Write-Host "  Reliability: Version C ($($resultC.SuccessRate)%) > Version A ($($resultA.SuccessRate)%)" -ForegroundColor White
    }

    # P95 비교
    if ($resultA.P95Ms -lt $resultC.P95Ms) {
        Write-Host "  P95 Tail: Version A ($($resultA.P95Ms)ms) < Version C ($($resultC.P95Ms)ms)" -ForegroundColor White
    } else {
        Write-Host "  P95 Tail: Version C ($($resultC.P95Ms)ms) <= Version A ($($resultA.P95Ms)ms)" -ForegroundColor White
    }
} else {
    if (-not $resultA) { Write-Host "  Version A: FAILED (check docker-compose-version-a.yml)" -ForegroundColor Red }
    if (-not $resultC) { Write-Host "  Version C: FAILED (check docker-compose-version-c.yml)" -ForegroundColor Red }
}

Write-Host "================================================================" -ForegroundColor Cyan
