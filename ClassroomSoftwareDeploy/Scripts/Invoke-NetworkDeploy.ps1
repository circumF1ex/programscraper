[CmdletBinding()]
param(
    [string]$ComputerList = '',
    [string]$PsExec = '',
    [string]$RemoteRoot = "C$\ProgramData\ClassroomSoftwareDeploy"
)

$ErrorActionPreference = "Continue"

. (Join-Path $PSScriptRoot 'Common.ps1')
$Root = Get-ProjectRoot -StartPath $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ComputerList)) {
    $ComputerList = Resolve-ProjectPath -Root $Root -RelativePath 'Config\computers.txt'
}
if ([string]::IsNullOrWhiteSpace($PsExec)) {
    $PsExec = Resolve-ProjectPath -Root $Root -RelativePath 'Tools\PsExec64.exe'
}

if (-not (Test-Path $PsExec)) {
    throw "Не найден PsExec64.exe: $PsExec. Скачайте PsExec из Microsoft Sysinternals и положите в Tools."
}
if (-not (Test-Path $ComputerList)) { throw "Не найден список компьютеров: $ComputerList" }

$computers = Get-Content $ComputerList | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } | Select-Object -Unique

if (-not $computers) { throw "Список компьютеров пуст." }

Write-Host "Будет выполнено развёртывание на $($computers.Count) ПК."
$confirm = Read-Host "Продолжить? Введите YES"
if ($confirm -cne "YES") { Write-Host "Отменено."; exit 0 }

foreach ($pc in $computers) {
    Write-Host "`n===== $pc =====" -ForegroundColor Cyan
    $dest = "\\$pc\$RemoteRoot"
    try {
        # Создаём папку через административную шару и копируем комплект.
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        & robocopy.exe $Root $dest /E /Z /R:2 /W:3 /NFL /NDL /NP
        $rc = $LASTEXITCODE
        if ($rc -ge 8) { throw "Robocopy завершился с кодом $rc" }

        $remotePath = "C:\ProgramData\ClassroomSoftwareDeploy\Scripts\Install-Local.ps1"
        & $PsExec "\\$pc" -accepteula -nobanner -s powershell.exe -NoProfile -ExecutionPolicy Bypass -File $remotePath
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "PsExec/установка на $pc вернула код $LASTEXITCODE. Проверьте удалённый журнал."
        } else {
            Write-Host "Команда завершена на $pc." -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Ошибка на $pc : $_"
    }
}
Write-Host "`nРазвёртывание завершено. Подробные журналы находятся на ПК: C:\ProgramData\ClassroomSoftwareDeploy\Logs"
