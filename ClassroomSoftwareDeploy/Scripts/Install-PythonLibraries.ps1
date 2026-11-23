[CmdletBinding()]
param(
    [string]$PythonCommand = "py -3.12",
    [string]$WheelDir = '',
    [string]$Requirements = ''
)
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot 'Common.ps1')
$Root = Get-ProjectRoot -StartPath $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($WheelDir)) {
    $WheelDir = Resolve-ProjectPath -Root $Root -RelativePath 'Packages\Python-Wheels'
}
if ([string]::IsNullOrWhiteSpace($Requirements)) {
    $Requirements = Resolve-ProjectPath -Root $Root -RelativePath 'Config\requirements.txt'
}

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
