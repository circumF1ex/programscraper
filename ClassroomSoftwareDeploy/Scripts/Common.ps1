# Общие функции определения корня комплекта и безопасных относительных путей.
# Подключается через dot-source: . (Join-Path $PSScriptRoot 'Common.ps1')

function Get-ProjectRoot {
    <#
        .SYNOPSIS
            Возвращает абсолютный путь к корню комплекта.

        .DESCRIPTION
            Ищет вверх от StartPath папку, содержащую одновременно Config и
            Scripts. Это делает скрипты независимыми от текущего каталога,
            буквы диска, пробелов и кириллицы в пути.
    #>
    [CmdletBinding()]
    param(
        [string]$StartPath = ''
    )

    if ([string]::IsNullOrWhiteSpace($StartPath)) {
        $StartPath = (Get-Location).ProviderPath
    }

    $current = [System.IO.Path]::GetFullPath($StartPath)
    if (Test-Path -LiteralPath $current -PathType Leaf) {
        $current = [System.IO.Path]::GetDirectoryName($current)
    }

    while (-not [string]::IsNullOrEmpty($current)) {
        $hasConfig = Test-Path -LiteralPath (Join-Path $current 'Config') -PathType Container
        $hasScripts = Test-Path -LiteralPath (Join-Path $current 'Scripts') -PathType Container
        if ($hasConfig -and $hasScripts) {
            return [System.IO.Path]::GetFullPath($current)
        }

        $parent = [System.IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) {
            break
        }
        $current = $parent
    }

    throw "Не удалось определить корень комплекта (нужны папки Config и Scripts): $StartPath"
}

function Resolve-ProjectPath {
    <#
        .SYNOPSIS
            Соединяет корень комплекта с относительным путём и запрещает выход за корень.

        .DESCRIPTION
            Принимает только относительные пути. Абсолютные пути, UNC и
            сегменты '..' отклоняются. Возвращает абсолютный путь.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw 'Относительный путь не задан.'
    }
    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Ожидается относительный путь, получен абсолютный: $RelativePath"
    }

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
    if ([string]::IsNullOrEmpty($rootFull)) {
        throw "Некорректный корень комплекта: $Root"
    }

    $combined = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootFull, $RelativePath))
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar

    if (-not $combined.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Путь выходит за корень комплекта: $RelativePath"
    }

    return $combined
}
