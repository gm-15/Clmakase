################################################################################
# OliveYoung 대기열 부하 테스트 스크립트
#
# 사용법:
#   Version A 테스트: .\load-test.ps1 -Version A
#   Version C 테스트: .\load-test.ps1 -Version C
#   동시 사용자 수 조정: .\load-test.ps1 -Version A -Users 200
#
# 테스트 순서:
#   1. Docker Compose로 해당 버전 실행
#   2. 헬스체크 대기
#   3. 대기열 진입 부하 테스트
#   4. 결과 집계 (평균 응답시간, 성공률, P95)
################################################################################

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("A", "C")]
    [string]$Version,

    [int]$Users = 100,
    [int]$ProductId = 1
)

$ErrorActionPreference = "Stop"

# 포트 설정
if ($Version -eq "A") {
    $Port = 8080
    $ComposeFile = "docker-compose-version-a.yml"
    $Label = "Version A (Circuit Breaker + Single Broker)"
} else {
    $Port = 8081
    $ComposeFile = "docker-compose-version-c.yml"
    $Label = "Version C (3-Broker Cluster + DLQ)"
}

$BaseUrl = "http://localhost:$Port"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " OliveYoung Load Test - $Label" -ForegroundColor Cyan
Write-Host " Users: $Users | Product: $ProductId" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 1. 헬스체크 ---
Write-Host "`n[1/3] Health Check..." -ForegroundColor Yellow
$maxRetries = 30
$retry = 0
$healthy = $false

while ($retry -lt $maxRetries -and -not $healthy) {
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/actuator/health" -TimeoutSec 3 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $healthy = $true
            Write-Host "  Backend is healthy!" -ForegroundColor Green
        }
    } catch {
        $retry++
        Write-Host "  Waiting for backend... ($retry/$maxRetries)" -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
}

if (-not $healthy) {
    Write-Host "  Backend not responding. Run docker-compose first:" -ForegroundColor Red
    Write-Host "  docker-compose -f $ComposeFile up -d --build" -ForegroundColor Red
    exit 1
}

# --- 2. 대기열 진입 부하 테스트 ---
Write-Host "`n[2/3] Load Test - $Users concurrent queue entries..." -ForegroundColor Yellow

$results = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
$body = "{`"productId`": $ProductId}"

$jobs = @()
$startTime = Get-Date

for ($i = 1; $i -le $Users; $i++) {
    $sessionId = "load-test-session-$i"

    $jobs += Start-Job -ScriptBlock {
        param($url, $sid, $reqBody)

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $resp = Invoke-WebRequest -Uri "$url/api/queue/enter" `
                -Method POST `
                -Headers @{
                    "Content-Type" = "application/json"
                    "X-Session-Id" = $sid
                } `
                -Body $reqBody `
                -TimeoutSec 30 `
                -ErrorAction Stop

            $sw.Stop()

            return [PSCustomObject]@{
                Status = $resp.StatusCode
                Time = $sw.ElapsedMilliseconds
                Success = $true
                Session = $sid
            }
        } catch {
            $sw.Stop()
            return [PSCustomObject]@{
                Status = 0
                Time = $sw.ElapsedMilliseconds
                Success = $false
                Session = $sid
                Error = $_.Exception.Message
            }
        }
    } -ArgumentList $BaseUrl, $sessionId, $body
}

Write-Host "  Waiting for $Users requests to complete..." -ForegroundColor Gray

# 결과 수집
$allResults = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

$totalTime = ((Get-Date) - $startTime).TotalSeconds

# --- 3. 결과 집계 ---
Write-Host "`n[3/3] Results" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan

$successCount = ($allResults | Where-Object { $_.Success -eq $true }).Count
$failCount = ($allResults | Where-Object { $_.Success -eq $false }).Count
$times = ($allResults | Where-Object { $_.Success -eq $true }).Time | Sort-Object

if ($times.Count -gt 0) {
    $avgTime = ($times | Measure-Object -Average).Average
    $minTime = $times[0]
    $maxTime = $times[-1]
    $p50Index = [math]::Floor($times.Count * 0.5)
    $p95Index = [math]::Floor($times.Count * 0.95)
    $p99Index = [math]::Floor($times.Count * 0.99)
    $p50 = $times[$p50Index]
    $p95 = $times[$p95Index]
    $p99 = $times[$p99Index]

    Write-Host "  Version:        $Label" -ForegroundColor White
    Write-Host "  Total Users:    $Users" -ForegroundColor White
    Write-Host "  Success:        $successCount ($([math]::Round($successCount/$Users*100, 1))%)" -ForegroundColor Green
    Write-Host "  Fail:           $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
    Write-Host "  Total Time:     $([math]::Round($totalTime, 2))s" -ForegroundColor White
    Write-Host "  Throughput:     $([math]::Round($Users/$totalTime, 1)) req/s" -ForegroundColor White
    Write-Host ""
    Write-Host "  Avg Latency:    $([math]::Round($avgTime, 0))ms" -ForegroundColor White
    Write-Host "  Min Latency:    ${minTime}ms" -ForegroundColor White
    Write-Host "  Max Latency:    ${maxTime}ms" -ForegroundColor White
    Write-Host "  P50 Latency:    ${p50}ms" -ForegroundColor White
    Write-Host "  P95 Latency:    ${p95}ms" -ForegroundColor Yellow
    Write-Host "  P99 Latency:    ${p99}ms" -ForegroundColor Yellow
} else {
    Write-Host "  All requests failed!" -ForegroundColor Red
    $allResults | Where-Object { $_.Success -eq $false } | Select-Object -First 3 | ForEach-Object {
        Write-Host "  Error: $($_.Error)" -ForegroundColor Red
    }
}

Write-Host "============================================" -ForegroundColor Cyan

# 실패한 요청 상세
if ($failCount -gt 0) {
    Write-Host "`n  Failed Requests (first 5):" -ForegroundColor Red
    $allResults | Where-Object { $_.Success -eq $false } | Select-Object -First 5 | ForEach-Object {
        Write-Host "    $($_.Session): $($_.Error)" -ForegroundColor Red
    }
}

# 결과를 CSV로 저장
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$csvFile = "load-test-result-version-$($Version.ToLower())-$timestamp.csv"
$allResults | Export-Csv -Path $csvFile -NoTypeInformation
Write-Host "`nResults saved to: $csvFile" -ForegroundColor Gray
