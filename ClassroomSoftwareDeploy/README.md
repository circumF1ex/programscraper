# ClassroomSoftwareDeploy — автономная установка Windows с USB

## Главное: как это работает

**Интернет нужен только на подготовительном компьютере.** На целевых компьютерах интернет не требуется.

1. На компьютере с интернетом подключите USB-диск, распакуйте сюда папку `ClassroomSoftwareDeploy` (или подготовьте папку прямо на USB).
2. Запустите `PREPARE-USB.cmd`. Скрипт скачает файлы, для которых в `Config\apps.json` заданы прямые официальные URL, в `Packages\<ID>\`.
3. Откройте `Config\MANUAL-DOWNLOADS.csv`: там перечислены остальные программы, официальные страницы скачивания и точные папки, куда сохранить файлы.
4. Когда подготовка завершена, безопасно извлеките USB-диск.
5. На компьютере без интернета подключите USB и запустите `INSTALL-FROM-USB.cmd` от имени администратора.
6. Деплоер читает только локальные файлы из `Packages`. Он **не устанавливает Chocolatey, не обращается к Chocolatey Community и не скачивает ничего из интернета**.

## Что скачивается автоматически в этой версии

- Google Chrome Enterprise x64 (MSI)
- Mozilla Firefox x64
- 7-Zip x64
- Visual Studio Code System Installer x64
- Python 3.14.10 x64
- Blender 5.3.0 x64 (MSI)
- Audacity x64 MSI 4.0.2
- GIMP Windows installer 3.2.8
- DBeaver Community x64 (файл скачивается, автоустановка выключена до проверки тихих ключей)

Актуальные хэши Audacity и GIMP проверяются во время подготовки. Ссылки на остальные пакеты указаны в манифесте. Если прямого автономного URL нет, файл нужно скачать вручную с официальной страницы и положить в указанную папку.

**Это не означает, что весь исходный список уже загружен:** в исходном архиве были преимущественно ссылки на страницы загрузки, а не прямые URL к файлам. Кроме того, часть продуктов требует аккаунт, лицензию, отдельные модули или индивидуальный offline layout.

## Структура файлов

- `Packages\<ID>\` — реальные локальные установщики.
- `Config\apps.json` — манифест с именем файла, типом, аргументами и флагом `Enabled`.
- `Scripts\Prepare-OfflineMedia.ps1` — скачивание на компьютере с интернетом.
- `Scripts\Install-Local.ps1` — установка только из локальных файлов.
- `Scripts\Install-PythonLibraries.ps1` — установка библиотек Python из wheelhouse.
- `Scripts\Invoke-NetworkDeploy.ps1` — копирование подготовленного комплекта по локальной сети; целевым ПК интернет не нужен, но нужна LAN.
- `Logs\` — журналы.

## Как добавить вручную скачанный установщик

Например, для программы с ID `ArduinoIDE`:

1. Откройте официальный сайт из `Config\apps.json`.
2. Скачайте Windows x64 offline installer.
3. Положите его в `Packages\ArduinoIDE\`.
4. В `Config\apps.json` заполните `Installer` точным именем файла, `Type` (`EXE` или `MSI`), `Arguments` с подтверждёнными производителем тихими ключами и выставьте `Enabled: true`.
5. Сначала проверьте на одном тестовом ПК.

У EXE деплоер намеренно не угадывает параметры тихой установки. Если `Arguments` пустой, он пропускает этот файл и пишет предупреждение. У MSI использует `/qn /norestart`.

## Python-библиотеки

На компьютере с интернетом установите совместимую версию Python и выполните:

```powershell
py -m pip download --only-binary=:all: -d .\Packages\Python-Wheels -r .\Config\requirements.txt
```

На целевом ПК, где Python уже установлен:

```powershell
.\Scripts\Install-PythonLibraries.ps1 -PythonCommand "py -3.12"
```

Версия Python, архитектура Windows и колёса должны быть совместимы с целевыми ПК.

## Программы, требующие отдельной подготовки

- **Visual Studio**: на компьютере с интернетом создайте полный offline layout с нужными workloads (C++, .NET, ASP.NET и т. п.) через Visual Studio Installer; скопируйте весь layout на USB. Один bootstrapper недостаточен.
- **Adobe Creative Cloud / Photoshop / Lightroom / Illustrator / InDesign / Premiere / After Effects**: подготовьте managed package через Adobe Admin Console. Нужны соответствующие лицензии.
- **Autodesk AutoCAD / 3ds Max / Maya**: используйте offline deployment/custom install из Autodesk Account; действуют лицензионные требования.
- **Docker Desktop**: нужен офлайн-пакет и заранее подготовленная поддержка WSL 2/виртуализации; отдельные функции после установки могут требовать сеть.
- **Unity / Unreal Engine**: редакторы, модули и платформенные компоненты загружаются отдельно; нужно подготовить весь комплект, а не только launcher.
- **V-Ray / Corona / ZBrush / SketchUp / Minecraft Education**: использовать официальные инсталляторы и лицензии; не копировать неизвестные патчи.
- **MagicaVoxel / Godot и другие portable ZIP**: их нужно распаковывать/копировать по отдельным правилам; текущий install script не ставит ZIP автоматически.

## Chocolatey — важное ограничение

Обычный `choco install` из Chocolatey Community **не является автономным развёртыванием**: community-пакеты часто скачивают реальные EXE/MSI с сайтов разработчиков во время установки. Команда `choco download` относится к лицензированным редакциям, а автоматический Package Internalizer — к Chocolatey for Business/MSP. Поэтому в этом USB-комплекте целевые ПК устанавливают именно локальные EXE/MSI из `Packages`, а не получают их из Chocolatey.

Официальная документация Chocolatey:
- https://docs.chocolatey.org/en-us/choco/commands/download/
- https://docs.chocolatey.org/en-us/features/package-internalizer/

## Проверка и безопасность

- После `PREPARE-USB.cmd` проверьте `Config\OFFLINE-DOWNLOAD-RESULTS.csv` и `Config\MANUAL-DOWNLOADS.csv`.
- Проверьте цифровые подписи установщиков и лицензии.
- Сделайте пробную установку на одном ПК без интернета.
- Для полного комплекта на 20–30 ПК объём USB может быть десятки или сотни гигабайт; используйте быстрый внешний SSD, а не маленькую флешку.
- Не запускайте массовую установку, пока не проверены параметры EXE и все зависимости.
