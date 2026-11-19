# DSHRelay 启动脚本：读同目录 .env，前台跑中继（由计划任务拉起，崩溃由任务重启）
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $root '.env'
if (Test-Path $envFile) {
    Get-Content $envFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $i = $line.IndexOf('=')
            $k = $line.Substring(0, $i).Trim()
            $v = $line.Substring($i + 1).Trim().Trim('"')
            [Environment]::SetEnvironmentVariable($k, $v, 'Process')
        }
    }
}
if (-not $env:DSH_SERVER_DATA_FILE) { $env:DSH_SERVER_DATA_FILE = Join-Path $root 'data\store.json' }
$logDir = Join-Path $root 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$node = 'C:\Program Files\nodejs\node.exe'
if (-not (Test-Path $node)) {
    $cmd = Get-Command node.exe -ErrorAction Stop
    $node = $cmd.Source
}
& $node (Join-Path $root 'relay-server.mjs') *>> (Join-Path $logDir 'relay.log')
