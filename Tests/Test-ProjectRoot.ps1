[CmdletBinding()]
param(
    [string]$Root = ''
)

# Проверка Get-ProjectRoot/Resolve-ProjectPath без запуска установки.
# Создаёт временную структуру с пробелами и кириллицей в пути.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$script:checks = 0
$script:failures = 0

function Test-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Condition,
        [string]$Detail = ''
    )

    $script:checks++
    if ($Condition) {
        Write-Host ("PASS  {0}" -f $Name) -ForegroundColor Green
    } else {
        $script:failures++
        if ([string]::IsNullOrWhiteSpace($Detail)) {
            Write-Host ("FAIL  {0}" -f $Name) -ForegroundColor Red
        } else {
            Write-Host ("FAIL  {0} — {1}" -f $Name, $Detail) -ForegroundColor Red
        }
    }
}

$commonPath = Join-Path $Root 'ClassroomSoftwareDeploy\Scripts\Common.ps1'
Test-Check -Name 'Common.ps1 существует' -Condition (Test-Path -LiteralPath $commonPath -PathType Leaf)
if (-not (Test-Path -LiteralPath $commonPath -PathType Leaf)) {
    Write-Host 'Common.ps1 не найден, дальнейшие проверки невозможны.' -ForegroundColor Red
    exit 1
}

. $commonPath

$deployRoot = Join-Path $Root 'ClassroomSoftwareDeploy'
$expectedRoot = [System.IO.Path]::GetFullPath($deployRoot)

Test-Check -Name 'Get-ProjectRoot из Scripts' -Condition (
    (Get-ProjectRoot -StartPath (Join-Path $deployRoot 'Scripts')) -eq $expectedRoot
)

Test-Check -Name 'Get-ProjectRoot из файла в Scripts' -Condition (
    (Get-ProjectRoot -StartPath (Join-Path $deployRoot 'Scripts\Common.ps1')) -eq $expectedRoot
)

$tempBase = Join-Path $env:TEMP ('cdm root test ' + [guid]::NewGuid().ToString('N').Substring(0, 8) + ' Кириллица')
$tempRoot = Join-Path $tempBase 'Package With Spaces'
try {
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'Config') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'Scripts') -Force | Out-Null

    Test-Check -Name 'Get-ProjectRoot: путь с пробелами и кириллицей' -Condition (
        (Get-ProjectRoot -StartPath (Join-Path $tempRoot 'Scripts')) -eq [System.IO.Path]::GetFullPath($tempRoot)
    )

    $resolved = Resolve-ProjectPath -Root $tempRoot -RelativePath 'Config\apps.json'
    Test-Check -Name 'Resolve-ProjectPath: относительный путь' -Condition (
        $resolved -eq [System.IO.Path]::GetFullPath((Join-Path $tempRoot 'Config\apps.json'))
    )

    $traversalRejected = $false
    try { [void](Resolve-ProjectPath -Root $tempRoot -RelativePath '..\outside.txt') } catch { $traversalRejected = $true }
    Test-Check -Name 'Resolve-ProjectPath: отклоняет ..' -Condition $traversalRejected

    $absoluteRejected = $false
    try { [void](Resolve-ProjectPath -Root $tempRoot -RelativePath 'C:\Windows\win.ini') } catch { $absoluteRejected = $true }
    Test-Check -Name 'Resolve-ProjectPath: отклоняет абсолютный путь' -Condition $absoluteRejected

    $emptyRejected = $false
    try { [void](Resolve-ProjectPath -Root $tempRoot -RelativePath '') } catch { $emptyRejected = $true }
    Test-Check -Name 'Resolve-ProjectPath: отклоняет пустой путь' -Condition $emptyRejected
}
finally {
    if (Test-Path -LiteralPath $tempBase) {
        Remove-Item -LiteralPath $tempBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($script:failures -gt 0) {
    Write-Host ("ProjectRoot: FAIL, проверок {0}, ошибок {1}." -f $script:checks, $script:failures) -ForegroundColor Red
    exit 1
}

Write-Host ("ProjectRoot: OK, проверок {0}." -f $script:checks) -ForegroundColor Green
exit 0
