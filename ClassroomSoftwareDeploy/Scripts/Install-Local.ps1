[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-ProjectRoot -StartPath $PSScriptRoot
}
$Root = [System.IO.Path]::GetFullPath($Root)

$LogDir = Resolve-ProjectPath -Root $Root -RelativePath 'Logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir ("install-{0}-{1}.log" -f $env:COMPUTERNAME,(Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $Log -Append | Out-Null
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Запустите деплоер от имени администратора.' }

    $manifestPath = Resolve-ProjectPath -Root $Root -RelativePath 'Config\apps.json'
    if (-not (Test-Path $manifestPath)) { throw "Не найден манифест: $manifestPath" }
    $apps = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
    $installed = 0; $skipped = 0; $failed = 0

    foreach ($app in ($apps | Sort-Object Order)) {
        if (-not $app.Enabled) { continue }
        Write-Host "`n==== $($app.Name) [$($app.Id)] ====" -ForegroundColor Cyan
        if ($app.Type -eq 'PythonLibraries') {
            Write-Host 'Python-библиотеки устанавливаются отдельным локальным wheelhouse. См. README.' -ForegroundColor Yellow
            $skipped++; continue
        }
        if ($app.Type -eq 'Manual') { Write-Warning 'Этот пункт помечен как Manual и не устанавливается автоматически.'; $skipped++; continue }

        $appDir = Resolve-ProjectPath -Root $Root -RelativePath ('Packages\' + [string]$app.Id)
        $installerName = [string]$app.Installer
        if ([string]::IsNullOrWhiteSpace($installerName)) {
            $candidates = @(Get-ChildItem -Path $appDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(exe|msi)$' })
            if ($candidates.Count -eq 1) { $installerName = $candidates[0].Name }
        }
        $installer = if (-not [string]::IsNullOrWhiteSpace($installerName)) { Join-Path $appDir $installerName } else { $null }
        if (-not $installer -or -not (Test-Path $installer)) {
            Write-Warning "Локальный установщик не найден в $appDir. НИЧЕГО из интернета не скачивается. Пропуск."
            $skipped++; continue
        }

        $expectedHash = [string]$app.Sha256
        if (-not [string]::IsNullOrWhiteSpace($expectedHash)) {
            $actualHash = (Get-FileHash -Path $installer -Algorithm SHA256).Hash
            if ($actualHash -ne $expectedHash) { Write-Warning 'SHA-256 не совпадает. Установщик пропущен.'; $failed++; continue }
        }
        if ($WhatIf) { Write-Host "[ПРОВЕРКА] локальный запуск: $installer $($app.Arguments -join ' ')"; continue }

        try {
            if ($app.Type -eq 'MSI' -or ([IO.Path]::GetExtension($installer) -ieq '.msi')) {
                $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i',('"'+$installer+'"'),'/qn','/norestart') -Wait -PassThru
            }
            elseif ($app.Type -eq 'EXE') {
                if (-not $app.Arguments -or $app.Arguments.Count -eq 0) {
                    Write-Warning 'Для EXE не заданы проверенные тихие параметры. Пропуск, чтобы не запускать мастер установки наугад.'
                    $skipped++; continue
                }
                $p = Start-Process -FilePath $installer -ArgumentList $app.Arguments -Wait -PassThru
            }
            elseif ($app.Type -eq 'PowerShell') {
                $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $app.Arguments -Wait -PassThru
            }
            else { Write-Warning "Неподдерживаемый Type '$($app.Type)'."; $skipped++; continue }

            if ($p.ExitCode -in @(0,3010,1641)) { Write-Host "Успешно. ExitCode=$($p.ExitCode)" -ForegroundColor Green; $installed++ }
            else { Write-Warning "Код установщика: $($p.ExitCode)"; $failed++ }
        }
        catch { Write-Warning "Ошибка установки $($app.Name): $_"; $failed++ }
    }
    Write-Host "`nИтог: установлено=$installed; пропущено=$skipped; ошибок=$failed" -ForegroundColor Green
    Write-Host "Журнал: $Log"
    if ($failed -gt 0) { exit 2 }
}
catch { Write-Error $_; exit 1 }
finally { Stop-Transcript | Out-Null }
