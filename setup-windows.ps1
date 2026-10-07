# Полная установка для Windows: плагин + программа + вход + подключение проекта.
#
# Запуск: щёлкнуть правой кнопкой по файлу → «Выполнить с помощью PowerShell».
# Если Windows откажется из-за политики выполнения, открыть PowerShell и выполнить:
#     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#     .\setup-windows.ps1

# Работает и в Windows PowerShell 5.1 (из коробки), и в PowerShell 7.
$ErrorActionPreference = 'Stop'
chcp 65001 > $null                      # вывод по-русски в UTF-8
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$bin = Join-Path $env:USERPROFILE '.local\bin'
$env:PATH = "$bin;$env:PATH"

function Bold($t) { Write-Host "`n$t" -ForegroundColor White -BackgroundColor DarkBlue }
function Warn($t) { Write-Host $t -ForegroundColor Yellow }
function Fail($t) { Write-Host "останов: $t" -ForegroundColor Red; Read-Host "`nEnter — закрыть"; exit 1 }
function Ask($t)  { $a = Read-Host "$t [y/N]"; return $a -match '^(y|Y|д|Д)' }

Clear-Host
Write-Host @'
+----------------------------------------------+
|  Taiga в Claude Code — установка             |
+----------------------------------------------+

Пять шагов. Прерваться можно в любой момент: Ctrl+C.
'@

# ── 1. окружение ────────────────────────────────────────────────────────────
Bold 'Шаг 1 из 5. Проверка окружения'
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { Fail 'нет Python. Поставьте с python.org и ОБЯЗАТЕЛЬНО отметьте "Add Python to PATH"' }
Write-Host "  python:  $(& $py.Source --version)"
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Fail 'нет Claude Code. Поставьте его и запустите файл снова.' }
Write-Host "  claude:  $((claude --version) -split "`n" | Select-Object -First 1)"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Warn '  git не найден — связь задач с коммитами работать не будет' }

# ── роль ──
Bold 'Кто вы?'
Write-Host @'
  1) Менеджер — вести задачи: смотреть, создавать, двигать по доске,
     раскладывать техническое задание в эпики и истории.

  2) Разработчик — то же плюс дозорный: раз в час проверяет трекер,
     кладёт заготовки разбора в папки проектов и уведомляет.
'@
$role = ''
while (-not $role) {
    $a = Read-Host '  1 или 2'
    if ($a -eq '1') { $role = 'pm' } elseif ($a -eq '2') { $role = 'dev' } else { Warn '  введите 1 или 2' }
}
Write-Host "  выбрано: $(if ($role -eq 'dev') {'разработчик'} else {'менеджер'})"

# ── 2. плагин ───────────────────────────────────────────────────────────────
Bold 'Шаг 2 из 5. Плагин Claude Code'
if ((claude plugin list 2>$null) -match 'taiga-kit') {
    Write-Host '  уже установлен'
} else {
    Write-Host '  подключаю каталог и ставлю плагин…'
    try   { claude plugin marketplace add Sigmatick/taiga-kit 2>$null | Out-Null }
    catch { try { claude plugin marketplace add $src 2>$null | Out-Null } catch { Warn '  каталог подключить не удалось' } }
    try   { claude plugin install taiga-kit@taiga-kit 2>$null | Out-Null; Write-Host '  плагин установлен' }
    catch { Warn '  плагин не установился — см. README' }
}

# ── 3. программа ────────────────────────────────────────────────────────────
Bold 'Шаг 3 из 5. Программа taiga'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
Copy-Item (Join-Path $src 'bin\taiga') (Join-Path $bin 'taiga.py') -Force

# Windows не понимает #!/usr/bin/env python3 — нужна обёртка .cmd
@"
@echo off
chcp 65001 >nul
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
"$($py.Source)" "%~dp0taiga.py" %*
"@ | Set-Content -Path (Join-Path $bin 'taiga.cmd') -Encoding ASCII

Write-Host "  установлена: $bin\taiga.cmd"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$bin*") {
    [Environment]::SetEnvironmentVariable('Path', "$bin;$userPath", 'User')
    Write-Host '  путь дописан в PATH (подействует в новых окнах консоли)'
}

# ── 4. вход ─────────────────────────────────────────────────────────────────
Bold 'Шаг 4 из 5. Вход в Taiga'
$ok = $false
try { & "$bin\taiga.cmd" status 2>$null | ForEach-Object { Write-Host "  $_" }; $ok = $LASTEXITCODE -eq 0 } catch { $ok = $false }
if ($ok) {
    if (Ask '  войти заново под другой учётной записью?') { & "$bin\taiga.cmd" login }
} else {
    Write-Host @'
  Сейчас спросим адрес, логин и пароль.
  Пароль при вводе НЕ отображается — ни звёздочек, ни курсора.
  Это нормально: печатайте вслепую и нажмите Enter.
'@
    & "$bin\taiga.cmd" login
    if ($LASTEXITCODE -ne 0) { Fail 'вход не выполнен' }
}

# ── 5. проект ───────────────────────────────────────────────────────────────
Bold 'Шаг 5 из 5. Подключение проекта'
& "$bin\taiga.cmd" projects
if ($LASTEXITCODE -ne 0) { Fail 'список проектов не получен' }

Write-Host ''
Write-Host '  Слаг — это левый столбец. В адресе браузера он же:'
Write-Host '  https://<инстанс>/project/СЛАГ/kanban'
Write-Host ''
$slug = Read-Host '  слаг проекта (пусто — пропустить)'

if ($slug) {
    $def = Join-Path $env:USERPROFILE "Documents\$slug"
    $dir = Read-Host "  папка проекта [$def]"
    if (-not $dir) { $dir = $def }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Push-Location $dir
    & "$bin\taiga.cmd" init $slug
    if ($LASTEXITCODE -ne 0) { Pop-Location; Fail 'подключение не удалось' }
    Write-Host ''
    & "$bin\taiga.cmd" ls --open | Select-Object -First 6
    Pop-Location
    Bold 'Готово'
    Write-Host "  Откройте Claude Code с папкой:`n     $dir`n  и напишите: что в бэклоге"
    Write-Host '  Ещё проект: перейти в его папку и выполнить  taiga init <слаг>'
} else {
    Bold 'Готово'
    Write-Host '  Проект подключите позже: перейти в его папку и  taiga init <слаг>'
}

# ── для разработчика: реестр и дозорный ──
if ($role -eq 'dev') {
    Bold 'Дополнительно для разработчика'
    Write-Host '  наполняю реестр проектов…'
    & "$bin\taiga.cmd" registry --scan
    Write-Host ''
    Write-Host @'
  Дозорный раз в час (9–19 по будням) проверяет трекер и кладёт
  заготовки разбора в <проект>\.claude\триаж\. Код не меняет,
  в трекер не пишет.
'@
    if (Ask '  поставить дозорного на расписание?') {
        & "$bin\taiga.cmd" watch --install
        Write-Host ''
        Write-Host '  первая проверка за сутки:'
        & "$bin\taiga.cmd" watch --days 1
    } else {
        Write-Host '  пропущено. Поставить позже:  taiga watch --install'
    }
}

Read-Host "`nEnter — закрыть"
