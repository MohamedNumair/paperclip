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
    foreach ($procId in $listeners) {
      Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
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

function Get-PaperclipLogPaths {
  $logDir = Join-Path $HOME ".paperclip/instances/default/logs"
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null

  return @{
    StdOut = Join-Path $logDir "dev-stdout.log"
    StdErr = Join-Path $logDir "dev-stderr.log"
  }
}

function Start-PaperclipDetached {
  param(
    [string]$RootPath
  )

  $logPaths = Get-PaperclipLogPaths
  Remove-Item -Force $logPaths.StdOut -ErrorAction SilentlyContinue
  Remove-Item -Force $logPaths.StdErr -ErrorAction SilentlyContinue

  $process = Start-Process `
    -FilePath "cmd.exe" `
    -ArgumentList "/c", "pnpm dev" `
    -WorkingDirectory $RootPath `
    -RedirectStandardOutput $logPaths.StdOut `
    -RedirectStandardError $logPaths.StdErr `
    -PassThru

  return @{
    Process = $process
    LogPaths = $logPaths
  }
}

function Show-PaperclipLogs {
  param(
    [hashtable]$LogPaths
  )

  if (Test-Path $LogPaths.StdOut) {
    Write-Host "[paperclip] Last stdout lines:"
    Get-Content $LogPaths.StdOut -Tail 40 -ErrorAction SilentlyContinue
  }

  if (Test-Path $LogPaths.StdErr) {
    Write-Host "[paperclip] Last stderr lines:"
    Get-Content $LogPaths.StdErr -Tail 40 -ErrorAction SilentlyContinue
  }
}

Write-Host "[paperclip] Stopping running Paperclip-related processes..."
Stop-PaperclipProcesses

Write-Host "[paperclip] Resetting stale lock state..."
Reset-PaperclipDbLock

Write-Host "[paperclip] Starting pnpm dev..."
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $projectRoot

if (-not $SkipHealthCheck) {
  Write-Host "[paperclip] Startup will continue in this terminal."
  Write-Host "[paperclip] Check health at http://127.0.0.1:3100/api/health after the server banner appears."
}

pnpm dev
exit $LASTEXITCODE
