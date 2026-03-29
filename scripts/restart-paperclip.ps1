param(
  [switch]$ResetDb,
  [switch]$SkipHealthCheck
)

$ErrorActionPreference = "Stop"

function Stop-PaperclipProcesses {
  $ports = 3100, 13100, 54329
  foreach ($port in $ports) {
    $listeners = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
      Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($pid in $listeners) {
      Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
    }
  }

  Get-CimInstance Win32_Process -Filter "Name='postgres.exe'" |
    Where-Object {
      $_.CommandLine -match "@embedded-postgres" -or
      $_.CommandLine -match "\\.paperclip\\instances\\default\\db"
    } |
    ForEach-Object {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Reset-PaperclipDbLock {
  $dbDir = Join-Path $HOME ".paperclip/instances/default/db"
  $pidFile = Join-Path $dbDir "postmaster.pid"

  if (Test-Path $pidFile) {
    Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
  }

  if ($ResetDb) {
    if (Test-Path $dbDir) {
      Write-Host "[paperclip] Resetting embedded database directory: $dbDir"
      Remove-Item -Recurse -Force $dbDir
    }
  }
}

function Wait-PaperclipHealth {
  $url = "http://127.0.0.1:3100/api/health"
  $maxAttempts = 30

  for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
      $response = Invoke-WebRequest -UseBasicParsing $url -TimeoutSec 2
      if ($response.StatusCode -eq 200) {
        Write-Host "[paperclip] Health check OK: $url"
        Write-Host $response.Content
        return
      }
    } catch {
      Start-Sleep -Milliseconds 1000
    }
  }

  throw "Paperclip health check failed after waiting for startup."
}

Write-Host "[paperclip] Stopping running Paperclip-related processes..."
Stop-PaperclipProcesses

Write-Host "[paperclip] Resetting stale lock state..."
Reset-PaperclipDbLock

Write-Host "[paperclip] Starting pnpm dev..."
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $projectRoot

if ($SkipHealthCheck) {
  pnpm dev
  exit $LASTEXITCODE
}

$job = Start-Job -ScriptBlock {
  param($root)
  Set-Location $root
  pnpm dev
} -ArgumentList $projectRoot.Path

try {
  Wait-PaperclipHealth
  Write-Host "[paperclip] Server started successfully. Attaching logs. Press Ctrl+C to stop."
  Receive-Job -Job $job -Wait -AutoRemoveJob
} catch {
  Stop-Job -Job $job -Force -ErrorAction SilentlyContinue
  Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
  throw
}
