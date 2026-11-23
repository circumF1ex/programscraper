# BASELINE — состояние репозитория перед интеграцией

**Дата фиксации:** 23.11.2026  
**Ветка:** `dev`  
**Импорт исходников:** коммит `588236f` — `chore: import ClassroomSoftwareDeploy archive and integration spec`  
**Задание:** `TECH_SPEC_ProgramScraper_ClassroomDeploymentManager_RU.md` (в корне репозитория)  
**Репозиторий:** <https://github.com/circumF1ex/programscraper>

Этот документ фиксирует фактическое состояние исходных проектов до начала
интеграции. Он не заменяет ТЗ; при расхождении между кодом и ТЗ действует
правило остановки из раздела 0 ТЗ.

---

## 1. Что добавлено в репозиторий

| Источник | Состояние |
| --- | --- |
| ProgramScraper (исходный код) | Уже был в `main`, коммит `83a84e3`, не изменялся |
| `ClassroomSoftwareDeploy/` | Импортирован из архива `ClassroomSoftwareDeploy-OfflineUSB.zip`, 20 файлов |
| `TECH_SPEC_..._RU.md` | Добавлен в корень, 878 строк |

Импорт выполнен «как есть»: файлы не переименованы и не переписаны. Выполнена
только техническая нормализация, чтобы архив корректно работал и не засорял Git:

- `.ps1` и `.cmd` переведены в CRLF; BOM у `.ps1` сохранён (требование Windows
  PowerShell 5.1 для кириллицы);
- в `.gitattributes` добавлен шаблон `*.cmd text eol=crlf`;
- в `.gitignore` исключены реальные payload (`ClassroomSoftwareDeploy/Packages/*`,
  кроме `README.txt`), логи (`Logs/*`, кроме `.keep`) и генерируемый
  `Config/OFFLINE-DOWNLOAD-RESULTS.csv`.

## 2. Контрольные суммы исходных файлов (SHA-256)

Хэши соответствуют файлам в рабочем дереве после нормализации EOL.

| Файл | Размер, байт | SHA-256 |
| --- | ---: | --- |
| `.gitattributes` | 102 | `144a83060705ef7fdabf2a6a3caf13e8e2711e6689e4a87ec3d452cecb766d27` |
| `.gitignore` | 575 | `c08488ff61f751d858b4966c8eac3ef33827ebfd8beedf83b6468ebdce79f9c7` |
| `Get-InstalledPrograms.ps1` | 40649 | `a04fc84da31540ca7a75ee92cde3914c4644aa446ab90660849fec39d0420934` |
| `Run.bat` | 1421 | `38b3722bf8cfbbd9df7b94ba6ce4da461a42267997ce3586e68aebffc1f05a65` |
| `README.md` | 2953 | `7394ad128a1c7de48f34f62a8785bf861d2086711b39ddc2a4c1f36c35e5a9ff` |
| `ClassroomSoftwareDeploy/README.md` | 8694 | `943ad6adce2e3017aa3280b3a24c83697115261cbdc7b0f33cf4deb662908bbb` |
| `ClassroomSoftwareDeploy/Config/apps.json` | 16710 | `7759cd1c242cae585e75a441747da0f0dc2f61adba8fe112c74e5ca05629571a` |
| `ClassroomSoftwareDeploy/Config/software-catalog.csv` | 9132 | `e4fb794891ce49403a4214b1ceb0669afde2755581b887890aa656d8acb8e5a7` |
| `ClassroomSoftwareDeploy/Config/MANUAL-DOWNLOADS.csv` | 5333 | `fedd0743f5babd3e2b0419af71d9415fc81f41b1fcaa7f70db1ffa68c7b7de63` |
| `ClassroomSoftwareDeploy/Config/PREDEPLOY-CHECKLIST.txt` | 1233 | `39e0a48a328a5f21ebae1eecfdd5433402d51ef756d9dc93c2ca3b6431da7a40` |
| `ClassroomSoftwareDeploy/Config/computers.txt` | 114 | `747980dc80855b7f84f29a545d8c0781557545784524d415ded6d090a890bffd` |
| `ClassroomSoftwareDeploy/Config/requirements.txt` | 35 | `ed2ae4ac5fd8aca17b17759aa3e993802b7b8e520c950f7e7b4641993202eead` |
| `ClassroomSoftwareDeploy/Scripts/Install-Local.ps1` | 4721 | `060771811f6de27c897dfd03c83610c6288f964a2127c040c0102dfd8ecfbda5` |
| `ClassroomSoftwareDeploy/Scripts/Install-PythonLibraries.ps1` | 976 | `ad946c0386ec29e207ce05226513f16b612a3c5aaabea8f1f4c957005c2a83f2` |
| `ClassroomSoftwareDeploy/Scripts/Prepare-OfflineMedia.ps1` | 4880 | `b72a8212ae5a7a03d04a0970a7b8f1e18d84625c49939fb80d796cd0cd71f08b` |
| `ClassroomSoftwareDeploy/Scripts/Invoke-NetworkDeploy.ps1` | 2425 | `193eaf25d2bfea28cf810b422f1d47190368863baca749815c3a15c9b4602696` |
| `ClassroomSoftwareDeploy/INSTALL-FROM-USB.cmd` | 48 | `d45f2f362acedaa66eb454d34d7b29b59ba5e8d154292e9de9fcfe0089826866` |
| `ClassroomSoftwareDeploy/PREPARE-USB.cmd` | 57 | `4354dbce1aa020abd00ff106c901124b109ea6d7b2fd7626f179168b6a1426f8` |
| `ClassroomSoftwareDeploy/Scripts/Install-USB.cmd` | 456 | `bc4416ea56895f6ea60df60930ee54bf360044d1009b6c36453281134e72662b` |
| `ClassroomSoftwareDeploy/Scripts/Prepare-OfflineMedia.cmd` | 250 | `b5989b2a039692b649d6c446cfebbae07a7f0a87b301bf2fdb521d276a2bc13a` |

`ClassroomSoftwareDeploy/Logs/.keep` — пустой файл (SHA-256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`).

## 3. Точки входа и параметры

### ProgramScraper

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-InstalledPrograms.ps1
```

Параметры: `-OutputDir <path>` (по умолчанию `Reports`), `-SkipWinget`,
`-SkipAutostart`. `Run.bat` запрашивает UAC и открывает последний отчёт.
Отчёт — `Reports/Programs_<PC>_<yyyy-MM-dd_HH-mm-ss>.xlsx`.

### ClassroomSoftwareDeploy

| Точка входа | Назначение |
| --- | --- |
| `PREPARE-USB.cmd` → `Scripts/Prepare-OfflineMedia.ps1` | Подготовка на ПК с интернетом |
| `INSTALL-FROM-USB.cmd` → `Scripts/Install-USB.cmd` → `Scripts/Install-Local.ps1` | Установка на целевом ПК |
| `Scripts/Install-PythonLibraries.ps1` | Установка Python-библиотек из локального wheelhouse |
| `Scripts/Invoke-NetworkDeploy.ps1` | Копирование по локальной сети (Robocopy) и запуск через PsExec |

Параметры `Prepare-OfflineMedia.ps1`: `-Root`, `-OpenManualPages`,
`-DownloadPythonWheels`. Параметры `Install-Local.ps1`: `-Root`, `-WhatIf`.
Параметры `Invoke-NetworkDeploy.ps1`: `-ComputerList`, `-PsExec`, `-RemoteRoot`.

## 4. Фактическое состояние данных

- `Config/apps.json` — 41 запись. Это одновременно каталог, метаданные
  загрузки и рецепт установки (ограничение из ТЗ §2.3).
- `Config/software-catalog.csv` — 50 строк, разделитель `;`, UTF-8 с BOM.
- `Config/MANUAL-DOWNLOADS.csv` — 26 строк; это **сгенерированный** файл
  (`Prepare-OfflineMedia.ps1`), зафиксирован как снимок состояния.
- `Config/OFFLINE-DOWNLOAD-RESULTS.csv` отсутствует.
- `Packages/` содержит только `README.txt`; реальных установщиков нет.
- `Tools/PsExec64.exe` отсутствует, папки `Tools/` нет.
- `Config/computers.txt` содержит только комментарии.

## 5. Известные проблемы, зафиксированные до интеграции

Проблемы ниже не исправлялись в импортирующем коммите. Их исправление
планируется отдельными маленькими коммитами.

### ProgramScraper

1. **Невалидный элемент `<col>` в XLSX** — `Get-InstalledPrograms.ps1:649`.
   В `min`/`max` записывается буква столбца (`min="A"`), хотя по ECMA-376
   требуется числовой индекс. Excel может пометить файл как повреждённый
   или проигнорировать ширины столбцов. Проверено распаковкой последнего
   отчёта из `Reports/`.
2. **Дубли строк KB** — реестровые обновления (`:391-397`) и
   `Win32_QuickFixEngineering` (`:434-469`) попадают на один лист без
   дедупликации.
3. **Перезапись отчёта может упасть** — `:741-743` без проверки удаляет
   существующий файл; если он открыт в Excel, сбор завершается ошибкой.
4. **Хрупкий разбор `winget list`** — `:572-580`, разбиение по 2+ пробелам,
   без JSON-вывода.
5. **У офлайн-профилей читается только `...\Uninstall`** — `:161`, без
   `WOW6432Node`, в отличие от HKLM-источников.
6. **Autostart текущего пользователя зависит от контекста UAC** — при
   повышении под другой учётной записью `HKCU:`/`%APPDATA%` относятся к
   администратору, а не к исходному пользователю.

### ClassroomSoftwareDeploy

1. **`Prepare-OfflineMedia.ps1` не разделяет выбор и установку**: скачивает
   всё, где задан `DownloadUrl`, независимо от `Enabled` (ТЗ §2.3 п.1).
2. **`Install-Local.ps1:51` игнорирует `Arguments` для MSI**: всегда
   используется `/qn /norestart`, поэтому пользовательские MSI properties
   молча не применяются.
3. **`software-catalog.csv` уже расходится с `apps.json`**: у `GoogleChrome`
   и `Blender` тип `EXE` против `MSI`; колонка «Включено по умолчанию» =
   `Нет` для всех строк, хотя 6 записей имеют `Enabled: true`; в CSV есть
   11 веб-сервисов (Pixlr, Convertio, CodePen, Wokwi и др.), которые ТЗ §3.2
   не относит к устанавливаемым desktop-приложениям.
4. **Нет документации и файла PsExec**: `Invoke-NetworkDeploy.ps1`
   требует `Tools\PsExec64.exe`, но ни README, ни чек-лист об этом не
   упоминают (ТЗ §2.3 п.14).
5. **Источник `PaintNETAnimationPlugin`** — `https://top-academy.site/...`,
   не официальный сайт; запись `Manual`/`Enabled: false`, но противоречит
   ТЗ §6.3. Требует решения пользователя.
6. **`Prepare-OfflineMedia.ps1:24`** создаёт папку `Packages/<Id>` даже для
   `Manual`-записей без URL.
7. **Проверка уже существующего файла** ограничена ненулевым размером и
   опциональным SHA-256; тип файла и подпись не проверяются (ТЗ §2.3 п.12-13).
8. **Сетевой сценарий** последовательный, без DeploymentId, throttle,
   retry и сбора результатов (ТЗ §2.3 п.9).

## 6. Что проверено и что нет

Проверено статически:

- прочитаны все импортированные файлы, конфигурации и ТЗ;
- SHA-256 исходников зафиксированы выше;
- проверено наличие BOM/кодировки и EOL;
- проверено, что в `Packages/` нет payload, а `Reports/` остаётся вне Git.

**NOT RUN:** запуск `Get-InstalledPrograms.ps1`, `PREPARE-USB.cmd`,
`INSTALL-FROM-USB.cmd`, `Invoke-NetworkDeploy.ps1`; скачивание ПО; установка;
изменение реестра; удалённые команды. Эти действия требуют отдельного
разрешения (ТЗ §0 п.7, §12.4).

## 7. Следующие шаги по ТЗ

Этап 0, коммиты 01–04:

- 01 — этот документ (`docs: add integration baseline`);
- 02 — статическая проверка синтаксиса всех `.ps1`;
- 03 — тестовые fixtures инвентаризации и манифестов;
- 04 — единая функция определения корня проекта.

После этапа 0 — отчёт пользователю и пауза перед этапом 1.
