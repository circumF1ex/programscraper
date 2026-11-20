<#
.SYNOPSIS
    Сбор сведений об установленных программах Windows 10/11 в XLSX-отчёт с несколькими листами.

.DESCRIPTION
    Читает разделы Uninstall реестра (HKLM x64/x86, HKCU и другие загруженные кусты
    пользователей), обновления KB (реестр + WMI/QFE), автозагрузку и winget.
    XLSX формируется средствами .NET (Open XML + ZIP), поэтому не нужны ни Microsoft
    Excel, ни сторонние PowerShell-модули (ImportExcel и т.п.).

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-InstalledPrograms.ps1
#>
param(
    [string]$OutputDir = (Join-Path -Path $PSScriptRoot -ChildPath 'Reports'),
    [switch]$SkipWinget,
    [switch]$SkipAutostart
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Вспомогательные функции
# ----------------------------------------------------------------------------
function ConvertTo-XmlText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    $text = $text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ' '
    $text = $text -replace '[\r\n\t]+', ' '
    $text = $text.Trim()
    $text = $text.Replace('&', '&amp;')
    $text = $text.Replace('<', '&lt;')
    $text = $text.Replace('>', '&gt;')
    $text = $text.Replace('"', '&quot;')
    $text = $text.Replace("'", '&apos;')
    return $text
}

function Get-ColumnLetter {
    param([int]$Index)

    $letter = ''
    while ($Index -gt 0) {
        $Index--
        $letter = [string][char](65 + ($Index % 26)) + $letter
        $Index = [int][Math]::Floor($Index / 26)
    }
    if (-not $letter) { $letter = 'A' }
    return $letter
}

function Get-ValidSheetName {
    param([string]$Name)

    $name = $Name -replace '[\\/\?\*\[\]:]', '_'
    if ($name.Length -gt 31) { $name = $name.Substring(0, 31) }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Sheet' }
    return $name
}

function New-Table {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Headers,
        [Parameter(Mandatory = $true)][object]$Rows,
        [string[]]$Widths
    )

    return [pscustomobject]@{
        Name    = $Name
        Headers = $Headers
        Rows    = $Rows
        Widths  = $Widths
    }
}

function New-RowList {
    return New-Object 'System.Collections.Generic.List[object]'
}

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

<#
    Выгрузка временно смонтированного куста с несколькими попытками.
    Возвращает объект Success/Message — решение, ругаться или нет, принимает
    вызывающая сторона (финальная проверка делается после записи отчёта).
#>
function Unmount-TemporaryHive {
    param([Parameter(Mandatory = $true)][string]$HiveName)

    $oldEap = $ErrorActionPreference
    $lastMessage = ''
    $success = $false

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()

        $ErrorActionPreference = 'Continue'
        try {
            $output = & reg.exe unload ("HKU\" + $HiveName) 2>&1
            $code = $LASTEXITCODE
            $lastMessage = (($output | ForEach-Object { $_.ToString() }) -join ' ').Trim()
            if ($code -eq 0) {
                $success = $true
                break
            }
        } catch {
            $lastMessage = $_.Exception.Message
        } finally {
            $ErrorActionPreference = $oldEap
        }
    }

    return [pscustomobject]@{
        Success = $success
        Message = $lastMessage
    }
}

<#
    Убирает кусты PSRep_*, оставшиеся смонтированными после предыдущего
    (возможно, прерванного) запуска. Иначе повторный reg load того же
    NTUSER.DAT завершится ошибкой из-за заблокированного файла.
#>
function Remove-StaleTemporaryHives {
    $stillMounted = New-Object 'System.Collections.Generic.List[string]'
    $staleNames = @()
    try {
        $staleNames = @([Microsoft.Win32.Registry]::Users.GetSubKeyNames() |
            Where-Object { $_ -match '^PSRep_[0-9a-f]{8,}$' })
    } catch {
        return $stillMounted.ToArray()
    }

    foreach ($hiveName in $staleNames) {
        $result = Unmount-TemporaryHive -HiveName $hiveName
        if (-not $result.Success -and (Test-Path -Path "Registry::HKEY_USERS\$hiveName")) {
            $stillMounted.Add($hiveName)
        }
    }

    return $stillMounted.ToArray()
}

<#
    Чтение смонтированного куста через .NET Registry API, а не через провайдер
    PowerShell. Провайдер кэширует открытые ключи и мешает `reg unload`.
    Все ключи закрываются явно до выгрузки куста.
#>
function Get-RegistryUninstallItemsFromHive {
    param([Parameter(Mandatory = $true)][string]$HiveName)

    $items = New-Object 'System.Collections.Generic.List[object]'
    $basePath = $HiveName + '\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $baseKey = $null

    try {
        $baseKey = [Microsoft.Win32.Registry]::Users.OpenSubKey($basePath)
        if ($null -eq $baseKey) { return $items.ToArray() }

        foreach ($subName in $baseKey.GetSubKeyNames()) {
            $subKey = $null
            try {
                $subKey = $baseKey.OpenSubKey($subName)
                if ($null -eq $subKey) { continue }

                $values = @{}
                foreach ($valueName in $subKey.GetValueNames()) {
                    $values[$valueName] = $subKey.GetValue($valueName)
                }

                $items.Add([pscustomobject]@{
                    DisplayName          = $values['DisplayName']
                    Publisher            = $values['Publisher']
                    DisplayVersion       = $values['DisplayVersion']
                    InstallDate          = $values['InstallDate']
                    EstimatedSize        = $values['EstimatedSize']
                    UninstallString      = $values['UninstallString']
                    QuietUninstallString = $values['QuietUninstallString']
                    InstallLocation      = $values['InstallLocation']
                    InstallSource        = $values['InstallSource']
                    SystemComponent      = $values['SystemComponent']
                    ReleaseType          = $values['ReleaseType']
                    PSPath               = "Registry::HKEY_USERS\$HiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$subName"
                })
            } catch {
                # Недоступный подраздел — пропускаем
            } finally {
                if ($null -ne $subKey) {
                    $subKey.Close()
                    $subKey.Dispose()
                }
            }
        }
    } catch {
        # Куст недоступен для чтения
    } finally {
        if ($null -ne $baseKey) {
            $baseKey.Close()
            $baseKey.Dispose()
        }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }

    return $items.ToArray()
}

<#
    Формирует источники для чтения uninstall-ключей всех пользователей.
    Если куст уже загружен (пользователь вошёл в систему) — читаем напрямую
    из HKEY_USERS\<SID>. Иначе монтируем NTUSER.DAT через `reg load`.
    Все смонтированные кусты возвращаются в LoadedHives для обязательной
    разгрузки вызывающей стороной.
#>
function Get-UserProgramSources {
    $result = [pscustomobject]@{
        Sources     = New-Object 'System.Collections.Generic.List[object]'
        LoadedHives = New-Object 'System.Collections.Generic.List[string]'
    }

    $isAdmin = Test-IsAdministrator
    if (-not $isAdmin) {
        Write-Warning 'Нет прав администратора: будут прочитаны только загруженные кусты пользователей.'
    }

    $profileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $profiles = @()
    try {
        $profiles = Get-ChildItem -Path $profileListPath -ErrorAction Stop
    } catch {
        Write-Warning 'Не удалось прочитать список профилей пользователей.'
    }

    foreach ($profileKey in $profiles) {
        $sid = $profileKey.PSChildName
        if ($sid -match '_Classes$') { continue }
        if ($sid -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { continue }

        $imagePath = ''
        try {
            $imagePath = [string](Get-ItemProperty -Path $profileKey.PSPath -Name ProfileImagePath -ErrorAction Stop).ProfileImagePath
        } catch {
            continue
        }
        if (-not $imagePath) { continue }
        $imagePath = [System.Environment]::ExpandEnvironmentVariables($imagePath)

        $display = $sid
        try {
            $sidObject = New-Object System.Security.Principal.SecurityIdentifier($sid)
            $display = $sidObject.Translate([System.Security.Principal.NTAccount]).Value
        } catch {
            $display = Split-Path -Path $imagePath -Leaf
        }

        $loadedPath = "Registry::HKEY_USERS\$sid"
        if (Test-Path -Path $loadedPath) {
            $result.Sources.Add([pscustomobject]@{
                Path = $loadedPath + '\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
                Arch = 'Any'; Scope = 'User'; UserName = $display
            })
            continue
        }

        if (-not $isAdmin) { continue }

        $datPath = Join-Path -Path $imagePath -ChildPath 'NTUSER.DAT'
        if (-not (Test-Path -Path $datPath)) { continue }

        $hiveName = 'PSRep_' + [guid]::NewGuid().ToString('N').Substring(0, 10)
        $loadOutput = & reg.exe load ("HKU\" + $hiveName) $datPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("Не удалось загрузить куст пользователя {0}: {1}" -f $display, ($loadOutput -join ' '))
            continue
        }

        $result.LoadedHives.Add($hiveName)
        $result.Sources.Add([pscustomobject]@{
            Path      = "Registry::HKEY_USERS\$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            Arch      = 'Any'; Scope = 'User'; UserName = $display
            UseDotNet = $true; HiveName = $hiveName
        })
    }

    return $result
}

# ----------------------------------------------------------------------------
# Сбор данных из реестра и WMI
# ----------------------------------------------------------------------------
function Get-ProgramTables {
    $programHeaders = @(
        'Название', 'Издатель', 'Версия', 'Дата установки', 'Размер, КБ',
        'Область', 'Архитектура', 'Путь установки', 'Команда удаления',
        'Тихая команда удаления', 'Источник установки', 'Раздел реестра', 'Пользователь'
    )
    $programWidths = @(46, 28, 16, 14, 12, 12, 13, 42, 55, 55, 40, 62, 18)

    $updateHeaders = @(
        'Название / KB', 'Идентификатор', 'Описание', 'Дата установки',
        'Установил', 'Источник', 'Раздел реестра'
    )
    $updateWidths = @(34, 18, 55, 16, 24, 16, 62)

    $buckets = @{
        user     = New-RowList
        system64 = New-RowList
        system86 = New-RowList
        windows  = New-RowList
    }
    $updateRows = New-RowList

    $sources = New-Object 'System.Collections.Generic.List[object]'
    $sources.Add([pscustomobject]@{
        Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        Arch = 'x64'; Scope = 'Computer'; UserName = ''
    })
    $sources.Add([pscustomobject]@{
        Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        Arch = 'x86'; Scope = 'Computer'; UserName = ''
    })

    # Все пользователи: загруженные кусты + монтирование NTUSER.DAT
    $userSources = Get-UserProgramSources
    # Если старые кусты не удалось выгрузить — читаем программы и из них,
    # чтобы не потерять данные пользователей.
    foreach ($hiveName in @($script:StaleHives)) {
        if (-not (Test-Path -Path "Registry::HKEY_USERS\$hiveName")) { continue }
        $userSources.Sources.Add([pscustomobject]@{
            Path      = "Registry::HKEY_USERS\$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            Arch      = 'Any'; Scope = 'User'; UserName = 'профиль (куст прошлого запуска)'
            UseDotNet = $true; HiveName = $hiveName
        })
        if (-not $userSources.LoadedHives.Contains($hiveName)) {
            $userSources.LoadedHives.Add($hiveName)
        }
    }

    $script:TemporaryHives = @($userSources.LoadedHives)
    foreach ($userSource in $userSources.Sources) {
        $sources.Add($userSource)
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]'

    foreach ($source in $sources) {
        $items = $null
        if ($source.UseDotNet) {
            # Временно смонтированный куст читаем без провайдера реестра,
            # иначе reg unload не сможет его выгрузить.
            $items = Get-RegistryUninstallItemsFromHive -HiveName $source.HiveName
        } else {
            try {
                $items = Get-ItemProperty -Path $source.Path -ErrorAction Stop
            } catch {
                continue
            }
        }

        foreach ($item in @($items)) {
            if ($null -eq $item -or -not $item.DisplayName) { continue }

            # У Get-ItemProperty свойство Name пустое, поэтому уникальным
            # identификатором служит PSPath (полный путь к разделу реестра).
            $key = [string]$item.PSPath
            if (-not $key) {
                $key = [string]$source.Path + '|' + [string]$item.PSChildName
            }
            if (-not $seen.Add($key)) { continue }

            $registryKey = $key -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''

            $name = [string]$item.DisplayName
            $publisher = [string]$item.Publisher
            $releaseType = [string]$item.ReleaseType
            $isComponent = ($item.SystemComponent -eq 1)
            $isUpdate = ($name -match '(?i)^KB\d+') -or
                        ($releaseType -eq 'Update') -or
                        ($name -match '(?i)^(Update for|Hotfix for)')
            $isMicrosoft = ($publisher -match '(?i)Microsoft')
            $isWindowsish = ($name -match '(?i)Windows|\.NET|Visual C\+\+|DirectX|MSXML|Internet Explorer|Microsoft Edge|WebView|PowerShell|Redistributable|Runtime|Microsoft Update')

            if ($isUpdate) {
                $kbId = ''
                if ($name -match '(?i)(KB\d+)') { $kbId = $Matches[1] }
                $updateRows.Add([string[]]@(
                    $name, $kbId, '', [string]$item.InstallDate, '', 'Реестр', $registryKey
                ))
                continue
            }

            if ($isMicrosoft -and ($isWindowsish -or $isComponent)) {
                $bucket = 'windows'
            } elseif ($source.Scope -eq 'User') {
                $bucket = 'user'
            } elseif ($source.Arch -eq 'x86') {
                $bucket = 'system86'
            } else {
                $bucket = 'system64'
            }

            $buckets[$bucket].Add([string[]]@(
                $name,
                [string]$item.Publisher,
                [string]$item.DisplayVersion,
                [string]$item.InstallDate,
                [string]$item.EstimatedSize,
                [string]$source.Scope,
                [string]$source.Arch,
                [string]$item.InstallLocation,
                [string]$item.UninstallString,
                [string]$item.QuietUninstallString,
                [string]$item.InstallSource,
                $registryKey,
                [string]$source.UserName
            ))
        }
    }

    # Разгружаем все временно смонтированные кусты; финальная проверка — в конце скрипта
    foreach ($hiveName in $userSources.LoadedHives) {
        [void](Unmount-TemporaryHive -HiveName $hiveName)
    }

    # Обновления из WMI (Win32_QuickFixEngineering)
    $qfeAdded = $false
    try {
        $qfeItems = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction Stop
        foreach ($q in $qfeItems) {
            $installedOn = if ($q.InstalledOn) { [string]$q.InstalledOn } else { '' }
            $updateRows.Add([string[]]@(
                [string]$q.HotFixID,
                [string]$q.HotFixID,
                [string]$q.Description,
                $installedOn,
                [string]$q.InstalledBy,
                'WMI / QFE',
                ''
            ))
            $qfeAdded = $true
        }
    } catch {
        # Fallback на устаревший командлет
        try {
            foreach ($q in (Get-HotFix -ErrorAction Stop)) {
                $installedOn = if ($q.InstalledOn) { [string]$q.InstalledOn } else { '' }
                $updateRows.Add([string[]]@(
                    [string]$q.HotFixID,
                    [string]$q.HotFixID,
                    [string]$q.Description,
                    $installedOn,
                    '',
                    'Get-HotFix',
                    ''
                ))
                $qfeAdded = $true
            }
        } catch {
            # Информация о обновлениях недоступна
        }
    }
    if (-not $qfeAdded) {
        $updateRows.Add([string[]]@('Сведения об обновлениях недоступны', '', '', '', '', '', ''))
    }

    return @(
        (New-Table -Name 'Программы пользователя' -Headers $programHeaders -Rows $buckets.user -Widths $programWidths)
        (New-Table -Name 'Программы системы x64' -Headers $programHeaders -Rows $buckets.system64 -Widths $programWidths)
        (New-Table -Name 'Программы системы x86' -Headers $programHeaders -Rows $buckets.system86 -Widths $programWidths)
        (New-Table -Name 'Windows и компоненты' -Headers $programHeaders -Rows $buckets.windows -Widths $programWidths)
        (New-Table -Name 'Обновления KB' -Headers $updateHeaders -Rows $updateRows -Widths $updateWidths)
    )
}

function Get-AutostartTable {
    $headers = @('Название', 'Команда / путь', 'Тип', 'Расположение', 'Пользователь')
    $widths = @(36, 72, 22, 62, 20)
    $rows = New-RowList

    $runKeys = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; UserName = '' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; UserName = '' }
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; UserName = '' }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; UserName = $env:USERNAME }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; UserName = $env:USERNAME }
    )

    $skipProps = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')

    foreach ($runKey in $runKeys) {
        $props = $null
        try {
            $props = Get-ItemProperty -Path $runKey.Path -ErrorAction Stop
        } catch {
            continue
        }
        foreach ($prop in $props.PSObject.Properties) {
            if ($prop.Name -in $skipProps) { continue }
            $rows.Add([string[]]@(
                [string]$prop.Name,
                [string]$prop.Value,
                'Реестр (Run)',
                [string]$runKey.Path,
                [string]$runKey.UserName
            ))
        }
    }

    $folders = @(
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'); UserName = $env:USERNAME }
        @{ Path = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'); UserName = 'All users' }
    )

    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { $shell = $null }

    foreach ($folder in $folders) {
        if (-not (Test-Path -Path $folder.Path)) { continue }
        foreach ($file in (Get-ChildItem -Path $folder.Path -File -ErrorAction SilentlyContinue)) {
            $target = $file.FullName
            if ($file.Extension -ieq '.lnk' -and $null -ne $shell) {
                try { $target = $shell.CreateShortcut($file.FullName).TargetPath } catch { }
            }
            $rows.Add([string[]]@(
                [string]$file.Name,
                [string]$target,
                'Папка автозагрузки',
                [string]$folder.Path,
                [string]$folder.UserName
            ))
        }
    }

    return New-Table -Name 'Автозагрузка' -Headers $headers -Rows $rows -Widths $widths
}

function Get-WingetTable {
    $headers = @('Название', 'Идентификатор', 'Установленная версия', 'Доступно', 'Источник')
    $widths = @(46, 34, 20, 20, 16)
    $rows = New-RowList

    if (-not (Get-Command -Name winget -ErrorAction SilentlyContinue)) {
        $rows.Add([string[]]@('winget не установлен на этом компьютере', '', '', '', ''))
        return New-Table -Name 'winget' -Headers $headers -Rows $rows -Widths $widths
    }

    try {
        $output = & winget list --accept-source-agreements --disable-interactivity 2>&1
        $lines = @($output | ForEach-Object { [string]$_ })
    } catch {
        $lines = @()
    }

    $headerSeen = $false
    foreach ($rawLine in $lines) {
        $line = $rawLine -replace '\x1B\[[0-9;]*[A-Za-z]', ''
        if ($line -match '^\s*[-]{3,}' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        if (-not $headerSeen) {
            if ($line -match '(?i)(Name|Имя|Название)\s+(Id|Идентификатор)') {
                $headerSeen = $true
            }
            continue
        }
        $parts = @($line -split '\s{2,}' | Where-Object { $_.Trim() -ne '' })
        if ($parts.Count -lt 3) { continue }
        $rows.Add([string[]]@(
            [string]$parts[0],
            [string]$parts[1],
            [string]$parts[2],
            $(if ($parts.Count -gt 3) { [string]$parts[3] } else { '' }),
            $(if ($parts.Count -gt 4) { [string]$parts[4] } else { '' })
        ))
    }

    if ($rows.Count -eq 0) {
        $rows.Add([string[]]@('Не удалось получить список winget', '', '', '', ''))
    }

    return New-Table -Name 'winget' -Headers $headers -Rows $rows -Widths $widths
}

function Get-DriverTable {
    $headers = @(
        'Название', 'Производитель', 'Версия', 'Дата выпуска', 'Класс',
        'Устройство', 'INF-файл', 'Подписан', 'Расположение'
    )
    $widths = @(42, 26, 18, 15, 26, 42, 32, 12, 50)
    $rows = New-RowList

    try {
        $drivers = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop |
            Where-Object { $_.DeviceName -and $_.DriverProviderName } |
            Sort-Object -Property DeviceName

        foreach ($driver in $drivers) {
            $driverDate = ''
            if ($driver.DriverDate) {
                try {
                    $driverDate = ([datetime]$driver.DriverDate).ToString('dd.MM.yyyy')
                } catch {
                    $driverDate = [string]$driver.DriverDate
                }
            }

            $rows.Add([string[]]@(
                [string]$driver.DeviceName,
                [string]$driver.DriverProviderName,
                [string]$driver.DriverVersion,
                $driverDate,
                [string]$driver.ClassName,
                [string]$driver.FriendlyName,
                [string]$driver.InfName,
                $(if ($driver.IsSigned) { 'Да' } else { 'Нет' }),
                [string]$driver.LocationInformation
            ))
        }
    } catch {
        $rows.Add([string[]]@('Не удалось получить список драйверов', '', '', '', '', '', '', '', ''))
    }

    return New-Table -Name 'Драйверы' -Headers $headers -Rows $rows -Widths $widths
}

# ----------------------------------------------------------------------------
# Генератор XLSX (Open XML без внешних библиотек)
# ----------------------------------------------------------------------------
function New-WorksheetXml {
    param([Parameter(Mandatory = $true)][object]$Table)

    $ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$sb.Append('<worksheet xmlns="' + $ns + '">')
    [void]$sb.Append('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')

    if ($Table.Widths -and $Table.Widths.Count -gt 0) {
        [void]$sb.Append('<cols>')
        for ($i = 0; $i -lt $Table.Widths.Count; $i++) {
            $letter = Get-ColumnLetter ($i + 1)
            [void]$sb.Append('<col min="' + $letter + '" max="' + $letter + '" width="' + $Table.Widths[$i] + '" customWidth="1"/>')
        }
        [void]$sb.Append('</cols>')
    }

    [void]$sb.Append('<sheetData>')

    # Шапка
    [void]$sb.Append('<row r="1" ht="20" customHeight="1">')
    for ($i = 0; $i -lt $Table.Headers.Count; $i++) {
        $ref = (Get-ColumnLetter ($i + 1)) + '1'
        [void]$sb.Append('<c r="' + $ref + '" s="1" t="inlineStr"><is><t xml:space="preserve">' + (ConvertTo-XmlText $Table.Headers[$i]) + '</t></is></c>')
    }
    [void]$sb.Append('</row>')

    # Строки данных
    $rowNumber = 2
    foreach ($row in $Table.Rows) {
        [void]$sb.Append('<row r="' + $rowNumber + '">')
        for ($i = 0; $i -lt $Table.Headers.Count; $i++) {
            $value = if ($i -lt $row.Count) { $row[$i] } else { '' }
            $ref = (Get-ColumnLetter ($i + 1)) + $rowNumber
            [void]$sb.Append('<c r="' + $ref + '" t="inlineStr"><is><t xml:space="preserve">' + (ConvertTo-XmlText $value) + '</t></is></c>')
        }
        [void]$sb.Append('</row>')
        $rowNumber++
    }

    [void]$sb.Append('</sheetData>')

    if ($Table.Rows.Count -gt 0) {
        $lastCol = Get-ColumnLetter $Table.Headers.Count
        $lastRow = $Table.Rows.Count + 1
        [void]$sb.Append('<autoFilter ref="A1:' + $lastCol + $lastRow + '"/>')
    }

    [void]$sb.Append('</worksheet>')
    return $sb.ToString()
}

function Export-Xlsx {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Sheets
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $nsMain = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
    $nsRelDoc = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    $nsPkgRel = 'http://schemas.openxmlformats.org/package/2006/relationships'
    $nsCt = 'http://schemas.openxmlformats.org/package/2006/content-types'

    function Write-ZipEntry {
        param(
            [System.IO.Compression.ZipArchive]$Zip,
            [string]$EntryName,
            [string]$Content
        )
        $entry = $Zip.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
        $stream = $entry.Open()
        $bytes = $utf8.GetBytes($Content)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Dispose()
    }

    # Имена листов: валидные и уникальные
    $usedNames = @{}
    $sheetDefs = New-Object 'System.Collections.Generic.List[object]'
    foreach ($sheet in $Sheets) {
        $baseName = Get-ValidSheetName $sheet.Name
        $name = $baseName
        $suffix = 2
        while ($usedNames.ContainsKey($name.ToLowerInvariant())) {
            $tail = ' (' + $suffix + ')'
            $cut = [Math]::Max(0, 31 - $tail.Length)
            $name = $baseName.Substring(0, [Math]::Min($baseName.Length, $cut)) + $tail
            $suffix++
        }
        $usedNames[$name.ToLowerInvariant()] = $true
        $sheetDefs.Add([pscustomobject]@{
            Name = $name
            Xml  = (New-WorksheetXml -Table $sheet)
        })
    }

    $directory = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [System.IO.Directory]::Exists($directory)) {
        [void][System.IO.Directory]::CreateDirectory($directory)
    }
    if ([System.IO.File]::Exists($Path)) {
        [System.IO.File]::Delete($Path)
    }

    $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        # [Content_Types].xml
        $ct = New-Object System.Text.StringBuilder
        [void]$ct.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        [void]$ct.Append('<Types xmlns="' + $nsCt + '">')
        [void]$ct.Append('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
        [void]$ct.Append('<Default Extension="xml" ContentType="application/xml"/>')
        [void]$ct.Append('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
        for ($i = 0; $i -lt $sheetDefs.Count; $i++) {
            [void]$ct.Append('<Override PartName="/xl/worksheets/sheet' + ($i + 1) + '.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>')
        }
        [void]$ct.Append('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
        [void]$ct.Append('<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>')
        [void]$ct.Append('<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>')
        [void]$ct.Append('</Types>')
        Write-ZipEntry $zip '[Content_Types].xml' $ct.ToString()

        # Корневые связи
        $rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<Relationships xmlns="' + $nsPkgRel + '">' +
            '<Relationship Id="rId1" Type="' + $nsRelDoc + '/officeDocument" Target="xl/workbook.xml"/>' +
            '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>' +
            '<Relationship Id="rId3" Type="' + $nsRelDoc + '/extended-properties" Target="docProps/app.xml"/>' +
            '</Relationships>'
        Write-ZipEntry $zip '_rels/.rels' $rootRels

        # workbook.xml
        $wb = New-Object System.Text.StringBuilder
        [void]$wb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        [void]$wb.Append('<workbook xmlns="' + $nsMain + '" xmlns:r="' + $nsRelDoc + '"><sheets>')
        for ($i = 0; $i -lt $sheetDefs.Count; $i++) {
            [void]$wb.Append('<sheet name="' + (ConvertTo-XmlText $sheetDefs[$i].Name) + '" sheetId="' + ($i + 1) + '" r:id="rId' + ($i + 1) + '"/>')
        }
        [void]$wb.Append('</sheets></workbook>')
        Write-ZipEntry $zip 'xl/workbook.xml' $wb.ToString()

        # xl/_rels/workbook.xml.rels
        $wbRels = New-Object System.Text.StringBuilder
        [void]$wbRels.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        [void]$wbRels.Append('<Relationships xmlns="' + $nsPkgRel + '">')
        for ($i = 0; $i -lt $sheetDefs.Count; $i++) {
            [void]$wbRels.Append('<Relationship Id="rId' + ($i + 1) + '" Type="' + $nsRelDoc + '/worksheet" Target="worksheets/sheet' + ($i + 1) + '.xml"/>')
        }
        $stylesRid = 'rId' + ($sheetDefs.Count + 1)
        [void]$wbRels.Append('<Relationship Id="' + $stylesRid + '" Type="' + $nsRelDoc + '/styles" Target="styles.xml"/>')
        [void]$wbRels.Append('</Relationships>')
        Write-ZipEntry $zip 'xl/_rels/workbook.xml.rels' $wbRels.ToString()

        # styles.xml
        $styles = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF2F5496"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="1">
    <border><left/><right/><top/><bottom/><diagonal/></border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
  </cellXfs>
  <cellStyles count="1">
    <cellStyle name="Normal" xfId="0" builtinId="0"/>
  </cellStyles>
</styleSheet>
'@
        Write-ZipEntry $zip 'xl/styles.xml' $styles

        # Свойства документа
        $now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $core = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<cp:coreProperties ' +
            'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" ' +
            'xmlns:dc="http://purl.org/dc/elements/1.1/" ' +
            'xmlns:dcterms="http://purl.org/dc/terms/" ' +
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
            '<dc:creator>ProgramScraper</dc:creator>' +
            '<cp:lastModifiedBy>ProgramScraper</cp:lastModifiedBy>' +
            '<dcterms:created xsi:type="dcterms:W3CDTF">' + $now + '</dcterms:created>' +
            '<dcterms:modified xsi:type="dcterms:W3CDTF">' + $now + '</dcterms:modified>' +
            '</cp:coreProperties>'
        Write-ZipEntry $zip 'docProps/core.xml' $core

        $app = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">' +
            '<Application>ProgramScraper</Application>' +
            '</Properties>'
        Write-ZipEntry $zip 'docProps/app.xml' $app

        # Листы
        for ($i = 0; $i -lt $sheetDefs.Count; $i++) {
            Write-ZipEntry $zip ('xl/worksheets/sheet' + ($i + 1) + '.xml') $sheetDefs[$i].Xml
        }
    } finally {
        $zip.Dispose()
    }
}

# ----------------------------------------------------------------------------
# Основная логика
# ----------------------------------------------------------------------------
Write-Host 'Сбор сведений об установленных программах...' -ForegroundColor Cyan

$script:StaleHives = @(Remove-StaleTemporaryHives)

$programTables = Get-ProgramTables

$autostartTable = $null
if (-not $SkipAutostart) {
    $autostartTable = Get-AutostartTable
}

$wingetTable = $null
if (-not $SkipWinget) {
    $wingetTable = Get-WingetTable
}

$driverTable = Get-DriverTable

# Сводка
$os = $null
$computer = $null
try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch { }
try { $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop } catch { }

$summaryHeaders = @('Параметр', 'Значение')
$summaryWidths = @(38, 92)
$summaryRows = New-RowList
$summaryRows.Add([string[]]@('Компьютер', [string]$env:COMPUTERNAME))
$summaryRows.Add([string[]]@('Пользователь', [string]"$env:USERDOMAIN\$env:USERNAME"))
$summaryRows.Add([string[]]@('Операционная система', $(if ($os) { [string]$os.Caption } else { 'не определена' })))
$summaryRows.Add([string[]]@('Версия / сборка', $(if ($os) { [string]$os.Version + ' / ' + [string]$os.BuildNumber } else { '' })))
$summaryRows.Add([string[]]@('Разрядность ОС', $(if ($os) { [string]$os.OSArchitecture } else { '' })))
$summaryRows.Add([string[]]@('Производитель / модель', $(if ($computer) { [string]$computer.Manufacturer + ' / ' + [string]$computer.Model } else { '' })))
$summaryRows.Add([string[]]@('Дата и время сбора', [DateTime]::Now.ToString('dd.MM.yyyy HH:mm:ss')))
$summaryRows.Add([string[]]@('Права администратора', $(if (Test-IsAdministrator) { 'Да' } else { 'Нет' })))
$summaryRows.Add([string[]]@('Источники данных', 'Реестр Uninstall (HKLM x64/x86, HKEY_USERS + NTUSER.DAT всех профилей), WMI/QFE, Win32_PnPSignedDriver' + $(if (-not $SkipAutostart) { ', автозагрузка' } else { '' }) + $(if (-not $SkipWinget) { ', winget' } else { '' })))
foreach ($table in $programTables) {
    $summaryRows.Add([string[]]@('Строк: ' + $table.Name, [string]$table.Rows.Count))
}
if ($null -ne $autostartTable) {
    $summaryRows.Add([string[]]@('Строк: ' + $autostartTable.Name, [string]$autostartTable.Rows.Count))
}
if ($null -ne $wingetTable) {
    $summaryRows.Add([string[]]@('Строк: ' + $wingetTable.Name, [string]$wingetTable.Rows.Count))
}
if ($null -ne $driverTable) {
    $summaryRows.Add([string[]]@('Строк: ' + $driverTable.Name, [string]$driverTable.Rows.Count))
}
$summaryRows.Add([string[]]@('Примечание', 'Отчёт создан без использования Microsoft Excel и сторонних модулей.'))

$summaryTable = New-Table -Name 'Сводка' -Headers $summaryHeaders -Rows $summaryRows -Widths $summaryWidths

$allSheets = @($summaryTable) + @($programTables)
if ($null -ne $autostartTable) { $allSheets += $autostartTable }
if ($null -ne $wingetTable) { $allSheets += $wingetTable }
if ($null -ne $driverTable) { $allSheets += $driverTable }

$stamp = [DateTime]::Now.ToString('yyyy-MM-dd_HH-mm-ss')
$safeComputer = ($env:COMPUTERNAME -replace '[^\w\-]', '_')
$fileName = 'Programs_' + $safeComputer + '_' + $stamp + '.xlsx'
$outputPath = Join-Path -Path $OutputDir -ChildPath $fileName

Export-Xlsx -Path $outputPath -Sheets $allSheets

# Финальная попытка выгрузить кусты, которые не отпустились с первой попытки
foreach ($hiveName in @($script:TemporaryHives)) {
    if (-not (Test-Path -Path "Registry::HKEY_USERS\$hiveName")) { continue }
    $unmount = Unmount-TemporaryHive -HiveName $hiveName
    if (Test-Path -Path "Registry::HKEY_USERS\$hiveName") {
        Write-Warning ("Не удалось выгрузить куст HKU\{0}: {1}" -f $hiveName, $unmount.Message)
    }
}

Write-Host ''
Write-Host 'Отчёт готов:' -ForegroundColor Green
Write-Host $outputPath -ForegroundColor Yellow
Write-Host ''
