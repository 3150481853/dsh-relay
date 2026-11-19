# relay-watchdog.ps1 - keep the ds-harness-remote relay alive on Windows.
# Scheduled task: DSHRelayWatch (every 5 minutes, SYSTEM).
# Health: GET http://127.0.0.1:8080/health must return {"status":"ok"}.

$ErrorActionPreference = 'Continue'
$root  = 'C:\DSHRelay'
$url   = 'http://127.0.0.1:8080/health'
$log   = Join-Path $root 'logs\watchdog.log'
$state = Join-Path $root 'watchdog-state.json'
$task  = 'DSHRelay'

New-Item -ItemType Directory -Force -Path (Join-Path $root 'logs') | Out-Null

function Log([string]$m) {
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Add-Content -Path $log -Value $line -Encoding UTF8
    try {
        if ((Get-Item $log).Length -gt 1048576) { Move-Item $log ($log + '.1') -Force }
    } catch { }
}

function Test-Health {
    try {
        $r = Invoke-RestMethod -Uri $url -TimeoutSec 6 -ErrorAction Stop
        return ($r.status -eq 'ok')
    } catch { return $false }
}

function Set-Fails([int]$n) {
    "{""fails"":$n}" | Set-Content -Path $state -Encoding UTF8
}

function Notify([string]$text) {
    # Notify through the Molly relay (independent of port 8080).
    $tokenFile = 'C:\MollyServer\watch\token.txt'
    if (-not (Test-Path $tokenFile)) { return }
    try {
        $token = (Get-Content $tokenFile -Raw).Trim()
        $body = @{ from = 'relay-watchdog'; text = $text } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri 'https://jndnbd.asia/molly/messages' -Method Post -TimeoutSec 15 `
            -Headers @{ 'X-Molly-Token' = $token } -ContentType 'application/json; charset=utf-8' `
            -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
    } catch { }
}

$fails = 0
if (Test-Path $state) {
    try { $fails = [int]((Get-Content $state -Raw | ConvertFrom-Json).fails) } catch { $fails = 0 }
}

if (Test-Health) {
    if ($fails -ne 0) { Log "health ok again (was $fails consecutive failures)"; Notify "relay recovered on jndnbd.asia (was down $fails checks)" }
    Set-Fails 0
    exit 0
}

$fails++
Set-Fails $fails
Log "health FAILED (consecutive=$fails)"
if ($fails -lt 2) { exit 1 }

# Two consecutive failures: restart the relay.
Log "restarting relay"
Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*relay-server.mjs*' } | ForEach-Object {
    Log ("killing stale node pid=" + $_.ProcessId)
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1
& schtasks.exe /End /TN $task 2>$null | Out-Null
& schtasks.exe /Run /TN $task | Out-Null
Log "schtasks /Run $task issued"

for ($i = 0; $i -lt 12; $i++) {
    Start-Sleep -Seconds 5
    if (Test-Health) { Log 'recovered via scheduled task'; Set-Fails 0; Notify 'relay restarted by watchdog on jndnbd.asia'; exit 0 }
}

# Fallback: start it directly.
Log 'still down after task run; starting directly'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', (Join-Path $root 'start-relay.ps1')) -WindowStyle Hidden
Start-Sleep -Seconds 10
if (Test-Health) { Log 'recovered via direct start'; Set-Fails 0; Notify 'relay restarted directly by watchdog on jndnbd.asia'; exit 0 }

Log 'STILL DOWN - needs human'
Notify 'relay is DOWN on jndnbd.asia and the watchdog could not restart it'
exit 2
