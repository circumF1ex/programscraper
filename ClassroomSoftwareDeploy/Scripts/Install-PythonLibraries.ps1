[CmdletBinding()]
param(
    [string]$PythonCommand = "py -3.12",
    [string]$WheelDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "Packages\Python-Wheels"),
    [string]$Requirements = (Join-Path (Split-Path -Parent $PSScriptRoot) "Config\requirements.txt")
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $WheelDir)) { throw "Не найдена папка wheelhouse: $WheelDir" }
if (-not (Test-Path $Requirements)) { throw "Не найден requirements.txt: $Requirements" }

# Используйте только предварительно скачанные совместимые .whl.
$parts = $PythonCommand -split " "
$exe = $parts[0]
$prefixArgs = @()
if ($parts.Count -gt 1) { $prefixArgs = $parts[1..($parts.Count-1)] }
$args = $prefixArgs + @("-m","pip","install","--no-index","--find-links",$WheelDir,"-r",$Requirements)
& $exe @args
if ($LASTEXITCODE -ne 0) { throw "pip завершился с кодом $LASTEXITCODE" }
