[CmdletBinding()]
param(
    [string]$Root = ''
)

# Статическая проверка синтаксиса всех .ps1 без выполнения скриптов.
# Требования: Windows PowerShell 5.1, без интернета и без прав администратора.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$Root = [System.IO.Path]::GetFullPath($Root)
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Корень проекта не найден: $Root"
}

$files = @(
    Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1' -ErrorAction Stop |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        Sort-Object -Property FullName
)

if ($files.Count -eq 0) {
    Write-Host 'Не найдено ни одного .ps1 — проверьте параметр -Root.' -ForegroundColor Yellow
    exit 1
}

$errorCount = 0
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        foreach ($parseError in $parseErrors) {
            $errorCount++
            Write-Host (
                'FAIL {0}:{1}:{2} {3}' -f
                $file.FullName,
                $parseError.Extent.StartLineNumber,
                $parseError.Extent.StartColumnNumber,
                $parseError.Message
            ) -ForegroundColor Red
        }
    }
}

if ($errorCount -gt 0) {
    Write-Host ("Синтаксис: ошибок {0} в {1} файл(ах)." -f $errorCount, $files.Count) -ForegroundColor Red
    exit 1
}

Write-Host ("Синтаксис: OK, проверено файлов: {0}." -f $files.Count) -ForegroundColor Green
exit 0
