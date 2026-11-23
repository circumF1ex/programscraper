[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$OpenManualPages,
    [switch]$DownloadPythonWheels
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

. (Join-Path $PSScriptRoot 'Common.ps1')
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-ProjectRoot -StartPath $PSScriptRoot
}
$Root = [System.IO.Path]::GetFullPath($Root)

$manifestPath = Resolve-ProjectPath -Root $Root -RelativePath 'Config\apps.json'
if (-not (Test-Path $manifestPath)) { throw "Не найден манифест: $manifestPath" }
$apps = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
$manual = New-Object System.Collections.Generic.List[object]
$results = New-Object System.Collections.Generic.List[object]

Write-Host 'ПОДГОТОВКА USB-НОСИТЕЛЯ: скачивание выполняется только на этом компьютере с интернетом.' -ForegroundColor Cyan
Write-Host "Папка комплекта: $Root`n"

foreach ($app in ($apps | Sort-Object Order)) {
    if ($app.Id -eq 'PythonLibraries') { continue }
    $url = [string]$app.DownloadUrl
    $installerName = [string]$app.Installer
    $appDir = Resolve-ProjectPath -Root $Root -RelativePath ('Packages\' + [string]$app.Id)
    New-Item -ItemType Directory -Force -Path $appDir | Out-Null

    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($installerName)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$app.Source) -and ([string]$app.Source -match '^https?://')) {
            $manual.Add([pscustomobject]@{
                Id=$app.Id; Name=$app.Name; OfficialPage=$app.Source
                SaveTo=(Join-Path ("Packages\" + [string]$app.Id) '<installer file>')
                Notes=$app.Notes
            })
        }
        continue
    }

    $destination = Join-Path $appDir $installerName
    try {
        if ((Test-Path $destination) -and ((Get-Item $destination).Length -gt 0)) {
            Write-Host "[УЖЕ ЕСТЬ] $($app.Name): $destination" -ForegroundColor DarkYellow
        } else {
            Write-Host "[СКАЧИВАЮ] $($app.Name)" -ForegroundColor Cyan
            Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing -MaximumRedirection 10
        }

        $file = Get-Item $destination
        if ($file.Length -lt 1024) { throw "Файл слишком маленький ($($file.Length) байт); возможно, скачана HTML-страница вместо установщика." }
        $hash = (Get-FileHash -Path $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace([string]$app.Sha256) -and $hash -ne ([string]$app.Sha256).ToLowerInvariant()) {
            throw "SHA-256 не совпадает. Ожидался $($app.Sha256), получен $hash. Файл оставлен, но использовать его нельзя."
        }
        $results.Add([pscustomobject]@{Id=$app.Id;Name=$app.Name;File=("Packages\"+$app.Id+"\"+$installerName);SizeMB=[math]::Round($file.Length/1MB,2);SHA256=$hash;Status='Downloaded/Verified'})
        Write-Host "[ГОТОВО] $($app.Name) — $([math]::Round($file.Length/1MB,2)) MB" -ForegroundColor Green
    }
    catch {
        $results.Add([pscustomobject]@{Id=$app.Id;Name=$app.Name;File=("Packages\"+$app.Id+"\"+$installerName);SizeMB='';SHA256='';Status=('ERROR: '+$_.Exception.Message)})
        Write-Warning "Не удалось скачать $($app.Name): $_"
    }
}

$manualCsv = Resolve-ProjectPath -Root $Root -RelativePath 'Config\MANUAL-DOWNLOADS.csv'
$manual | Export-Csv -Path $manualCsv -NoTypeInformation -Encoding UTF8
$resultsCsv = Resolve-ProjectPath -Root $Root -RelativePath 'Config\OFFLINE-DOWNLOAD-RESULTS.csv'
$results | Export-Csv -Path $resultsCsv -NoTypeInformation -Encoding UTF8

if ($DownloadPythonWheels) {
    $wheelDir = Resolve-ProjectPath -Root $Root -RelativePath 'Packages\Python-Wheels'
    New-Item -ItemType Directory -Force -Path $wheelDir | Out-Null
    $requirements = Resolve-ProjectPath -Root $Root -RelativePath 'Config\requirements.txt'
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if (-not $py) { Write-Warning 'Python Launcher (py.exe) не найден. Колёса Python не скачаны.' }
    else {
        & $py.Source -m pip download --only-binary=:all: -d $wheelDir -r $requirements
        if ($LASTEXITCODE -ne 0) { Write-Warning "pip download завершился с кодом $LASTEXITCODE. Проверьте версию Python и requirements.txt." }
    }
}

Write-Host "`nПодготовка завершена." -ForegroundColor Green
Write-Host "Список скачанных файлов: $resultsCsv"
Write-Host "Что скачать вручную: $manualCsv"
Write-Host 'Скопируйте ВЕСЬ каталог ClassroomSoftwareDeploy на внешний носитель.'

if ($OpenManualPages) {
    foreach ($row in $manual) { if ($row.OfficialPage -match '^https?://') { Start-Process $row.OfficialPage } }
}
