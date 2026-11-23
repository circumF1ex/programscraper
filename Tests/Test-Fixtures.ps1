[CmdletBinding()]
param(
    [string]$Root = ''
)

# Проверка тестовых fixtures: структура, обязательные поля, отсутствие
# реальных путей/ПО. Скрипт не скачивает файлы и не требует прав администратора.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$fixturesRoot = Join-Path $Root 'Tests\Fixtures'
if (-not (Test-Path -LiteralPath $fixturesRoot -PathType Container)) {
    throw "Не найдена папка fixtures: $fixturesRoot"
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

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Test-SafeRelativePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '^[A-Za-z]:') { return $false }
    if ($Path -match '^\\\\') { return $false }
    if ($Path -match '^/') { return $false }

    $segments = $Path -split '[\\/]'
    if ($segments -contains '..') { return $false }

    return $true
}

# ---------------------------------------------------------------------------
# Inventory fixtures
# ---------------------------------------------------------------------------
$inventoryDir = Join-Path $fixturesRoot 'Inventory'
$inventoryFiles = @(
    Get-ChildItem -LiteralPath $inventoryDir -File -Filter '*.json' -ErrorAction Stop |
        Sort-Object -Property Name
)

Test-Check -Name 'Inventory: минимум 2 отчёта' -Condition ($inventoryFiles.Count -ge 2) -Detail ("найдено: {0}" -f $inventoryFiles.Count)

$allApplications = New-Object 'System.Collections.Generic.List[object]'

foreach ($file in $inventoryFiles) {
    $data = Read-JsonFile -Path $file.FullName
    Test-Check -Name ("{0}: schemaVersion = 1.0" -f $file.Name) -Condition ([string]$data.schemaVersion -eq '1.0')

    $scanId = [guid]::Empty
    Test-Check -Name ("{0}: scanId — GUID" -f $file.Name) -Condition ([guid]::TryParse([string]$data.scanId, [ref]$scanId))

    Test-Check -Name ("{0}: computer.name заполнен" -f $file.Name) -Condition (-not [string]::IsNullOrWhiteSpace([string]$data.computer.name))
    Test-Check -Name ("{0}: scan.tool заполнен" -f $file.Name) -Condition (-not [string]::IsNullOrWhiteSpace([string]$data.scan.tool))
    Test-Check -Name ("{0}: scan.sources — массив" -f $file.Name) -Condition ($data.scan.sources -is [System.Array])
    Test-Check -Name ("{0}: warnings — массив" -f $file.Name) -Condition ($null -ne $data.warnings)

    $applications = @($data.applications)
    Test-Check -Name ("{0}: applications не пуст" -f $file.Name) -Condition ($applications.Count -gt 0)

    $appProblems = New-Object 'System.Collections.Generic.List[string]'
    foreach ($app in $applications) {
        $allApplications.Add($app)

        if ([string]::IsNullOrWhiteSpace([string]$app.displayName)) { $appProblems.Add('displayName') }
        if ([string]::IsNullOrWhiteSpace([string]$app.publisher)) { $appProblems.Add('publisher') }
        if ([string]::IsNullOrWhiteSpace([string]$app.displayVersion)) { $appProblems.Add('displayVersion') }
        if ([string]::IsNullOrWhiteSpace([string]$app.categoryHint)) { $appProblems.Add('categoryHint') }
        if ([string]$app.architecture -notin @('x64', 'x86', 'Any')) { $appProblems.Add('architecture') }
        if ([string]$app.scope -notin @('Machine', 'User', 'Any')) { $appProblems.Add('scope') }

        if ([string]$app.installLocation -match '(?i)^[A-Z]:\\Users\\') {
            $appProblems.Add('installLocation содержит реальный профиль пользователя')
        }
    }

    Test-Check -Name ("{0}: поля applications" -f $file.Name) -Condition ($appProblems.Count -eq 0) -Detail (($appProblems | Select-Object -Unique) -join ', ')
}

$byName = @($allApplications | Group-Object -Property displayName)

$sameNameDifferentPublisher = @(
    $byName | Where-Object {
        @($_.Group | Select-Object -ExpandProperty publisher -Unique).Count -gt 1
    }
)
Test-Check -Name 'Fixtures: одно имя — разные издатели' -Condition ($sameNameDifferentPublisher.Count -gt 0)

$sameNameDifferentVersion = @(
    $byName | Where-Object {
        @($_.Group | Select-Object -ExpandProperty displayVersion -Unique).Count -gt 1
    }
)
Test-Check -Name 'Fixtures: одно имя — разные версии' -Condition ($sameNameDifferentVersion.Count -gt 0)

$categoryHints = @($allApplications | Select-Object -ExpandProperty categoryHint -Unique)
foreach ($requiredHint in @('Application', 'Runtime', 'WindowsComponent', 'Driver', 'Update')) {
    Test-Check -Name ("Fixtures: есть категория {0}" -f $requiredHint) -Condition ($categoryHints -contains $requiredHint)
}

Test-Check -Name 'Fixtures: есть запись scope = User' -Condition (@($allApplications | Where-Object { [string]$_.scope -eq 'User' }).Count -gt 0)

# ---------------------------------------------------------------------------
# Package manifest fixtures
# ---------------------------------------------------------------------------
$packagesDir = Join-Path $fixturesRoot 'Packages'
$manifestFiles = @(
    Get-ChildItem -LiteralPath $packagesDir -File -Filter '*.manifest.json' -ErrorAction Stop |
        Sort-Object -Property Name
)
Test-Check -Name 'Packages: найден fixture манифеста' -Condition ($manifestFiles.Count -ge 1)

foreach ($file in $manifestFiles) {
    $manifest = Read-JsonFile -Path $file.FullName
    Test-Check -Name ("{0}: schemaVersion = 1.0" -f $file.Name) -Condition ([string]$manifest.schemaVersion -eq '1.0')
    Test-Check -Name ("{0}: packageId заполнен" -f $file.Name) -Condition (-not [string]::IsNullOrWhiteSpace([string]$manifest.packageId))
    Test-Check -Name ("{0}: applications не пуст" -f $file.Name) -Condition (@($manifest.applications).Count -gt 0)
    Test-Check -Name ("{0}: payloadFiles не пуст" -f $file.Name) -Condition (@($manifest.payloadFiles).Count -gt 0)
    Test-Check -Name ("{0}: installRecipe присутствует" -f $file.Name) -Condition ($null -ne $manifest.installRecipe)

    $pathProblems = New-Object 'System.Collections.Generic.List[string]'
    $shaProblems = New-Object 'System.Collections.Generic.List[string]'

    foreach ($item in @($manifest.applications) + @($manifest.payloadFiles)) {
        if (-not (Test-SafeRelativePath -Path ([string]$item.relativePath))) {
            $pathProblems.Add([string]$item.relativePath)
        }
        if ([string]$item.sha256 -notmatch '^[a-f0-9]{64}$') {
            $shaProblems.Add([string]$item.sha256)
        }
    }

    Test-Check -Name ("{0}: относительные пути безопасны" -f $file.Name) -Condition ($pathProblems.Count -eq 0) -Detail (($pathProblems | Select-Object -Unique) -join ', ')
    Test-Check -Name ("{0}: SHA-256 в нижнем регистре (64 hex)" -f $file.Name) -Condition ($shaProblems.Count -eq 0) -Detail (($shaProblems | Select-Object -Unique) -join ', ')
}

# Старый формат apps.json: массив записей, совместимый с текущим деплоером.
$legacyPath = Join-Path $packagesDir 'legacy-apps.sample.json'
Test-Check -Name 'Packages: legacy-apps.sample.json существует' -Condition (Test-Path -LiteralPath $legacyPath -PathType Leaf)
if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
    $legacyApps = @(Read-JsonFile -Path $legacyPath)
    Test-Check -Name 'Packages: legacy fixtures не пуст' -Condition ($legacyApps.Count -gt 0)

    $legacyProblems = New-Object 'System.Collections.Generic.List[string]'
    foreach ($app in $legacyApps) {
        if ([string]::IsNullOrWhiteSpace([string]$app.Id)) { $legacyProblems.Add('Id') }
        if ([string]::IsNullOrWhiteSpace([string]$app.Name)) { $legacyProblems.Add('Name') }
        if ([string]$app.Type -notin @('MSI', 'EXE', 'PowerShell', 'Manual', 'PythonLibraries')) { $legacyProblems.Add('Type') }
    }
    Test-Check -Name 'Packages: legacy fixtures поля Id/Name/Type' -Condition ($legacyProblems.Count -eq 0) -Detail (($legacyProblems | Select-Object -Unique) -join ', ')
}

# ---------------------------------------------------------------------------
# Catalog CSV fixture
# ---------------------------------------------------------------------------
$catalogPath = Join-Path $fixturesRoot 'Catalog\software-catalog.sample.csv'
Test-Check -Name 'Catalog: CSV fixture существует' -Condition (Test-Path -LiteralPath $catalogPath -PathType Leaf)
if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
    $catalogRows = @(Import-Csv -LiteralPath $catalogPath -Delimiter ';' -Encoding UTF8)
    Test-Check -Name 'Catalog: CSV читается, есть строки' -Condition ($catalogRows.Count -gt 0)

    $expectedHeaders = @('ID', 'Программа', 'Тип', 'Включено по умолчанию', 'Источник', 'Особенности')
    $actualHeaders = @($catalogRows[0].PSObject.Properties.Name)
    $headerDiff = @($expectedHeaders | Where-Object { $actualHeaders -notcontains $_ })
    Test-Check -Name 'Catalog: обязательные колонки' -Condition ($headerDiff.Count -eq 0) -Detail ($headerDiff -join ', ')

    $catalogProblems = @($catalogRows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.ID) })
    Test-Check -Name 'Catalog: у всех строк заполнен ID' -Condition ($catalogProblems.Count -eq 0)
}

# ---------------------------------------------------------------------------
# Итог
# ---------------------------------------------------------------------------
if ($script:failures -gt 0) {
    Write-Host ("Fixtures: FAIL, проверок {0}, ошибок {1}." -f $script:checks, $script:failures) -ForegroundColor Red
    exit 1
}

Write-Host ("Fixtures: OK, проверок {0}, inventory-записей {1}." -f $script:checks, $allApplications.Count) -ForegroundColor Green
exit 0
