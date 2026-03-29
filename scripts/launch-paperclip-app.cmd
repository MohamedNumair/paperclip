@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."
set "CHROME_PROXY=C:\Program Files\Google\Chrome\Application\chrome_proxy.exe"
set "CHROME_ARGS=--profile-directory=Default --app-id=bkelfgdegfoncnmgammcbofifnpecdke"

start "Paperclip Dev" powershell.exe -NoExit -ExecutionPolicy Bypass -Command "Set-Location '%SCRIPT_DIR%'; .\restart-paperclip.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$healthUrl = 'http://127.0.0.1:3100/api/health';" ^
  "$maxAttempts = 120;" ^
  "for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {" ^
  "  try {" ^
  "    $response = Invoke-WebRequest -UseBasicParsing $healthUrl -TimeoutSec 2;" ^
  "    if ($response.StatusCode -eq 200) {" ^
  "      Start-Process '%CHROME_PROXY%' -ArgumentList '%CHROME_ARGS%';" ^
  "      exit 0;" ^
  "    }" ^
  "  } catch {}" ^
  "  Start-Sleep -Seconds 1;" ^
  "}" ^
  "Write-Error 'Paperclip did not become healthy in time; Chrome app was not opened.'"

endlocal