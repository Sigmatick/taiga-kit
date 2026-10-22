# Полная установка для Windows: плагин + программа + вход + подключение проекта.
#
# Запуск: щёлкнуть правой кнопкой по файлу → «Выполнить с помощью PowerShell».
# Если Windows откажется из-за политики выполнения, открыть PowerShell и выполнить:
#     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#     .\setup-windows.ps1

# Работает и в Windows PowerShell 5.1 (из коробки), и в PowerShell 7.
$ErrorActionPreference = 'Stop'

# Без этого окно закрывается мгновенно при любой ошибке, и человек
# не успевает прочитать, что случилось. Ловушка ставится ПЕРВОЙ.
trap {
    Write-Host ""
    Write-Host "ОШИБКА: $_" -ForegroundColor Red
    Write-Host "Строка: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
    Read-Host "`nEnter — закрыть"
    exit 1
}

# Смена кодировки консоли на части систем бросает исключение. Ради
# вывода по-русски окно ронять нельзя: не вышло — работаем как есть.
try {
    chcp 65001 > $null
    $OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8
} catch { }
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

$src = Split-Path -Parent $MyInvocation.MyCommand.Path

# Режим языка определяет, что нам вообще позволено. Читать его можно всегда.
$script:Restricted = $false
try { $script:Restricted = ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') } catch { }
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
# Человек, которому нужен ещё один проект, чаще всего идёт распаковывать
# архив заново. Говорим об этом до того, как он пройдёт пять шагов зря.
if (Test-Path (Join-Path $bin 'taiga.cmd')) {
    $already = $false
    try { & (Join-Path $bin 'taiga.cmd') status 2>$null | Out-Null; $already = ($LASTEXITCODE -eq 0) } catch { }
    if ($already) {
        Warn 'Кит на этом компьютере УЖЕ УСТАНОВЛЕН и вход выполнен.'
        Write-Host @'

  Если вам нужно просто подключить ещё один проект — переустановка не нужна.
  Закройте это окно, откройте Claude Code с папкой проекта и напишите:

     подключи эту папку к проекту <слаг>

  Продолжайте установку, только если хотите сменить учётную запись
  или починить что-то сломавшееся.
'@
        if (-not (Ask '  всё равно продолжить установку?')) {
            Write-Host '  вышли, ничего не меняли.'; Read-Host "`nEnter — закрыть"; exit 0
        }
    }
}

Bold 'Шаг 1 из 5. Проверка окружения'
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { Fail 'нет Python. Поставьте с python.org и ОБЯЗАТЕЛЬНО отметьте "Add Python to PATH"' }
Write-Host "  python:  $(& $py.Source --version)"
# Десктопное приложение на Windows не кладёт claude в PATH — у людей
# установщик падал, хотя Claude Code стоял. Ищем сами, а не найдя,
# НЕ прерываемся: программа и вход нужны и без плагина.
$script:Claude = $null
$c = Get-Command claude -ErrorAction SilentlyContinue
if ($c) { $script:Claude = $c.Source }
else {
    foreach ($p in @(
        "$env:USERPROFILE\.local\bin\claude.exe",
        "$env:USERPROFILE\.local\bin\claude.cmd",
        "$env:APPDATA\npm\claude.cmd",
        "$env:LOCALAPPDATA\Programs\claude\claude.exe",
        "$env:LOCALAPPDATA\Programs\Claude\claude.exe",
        "$env:ProgramFiles\Claude\claude.exe")) {
        if (Test-Path $p) { $script:Claude = $p; break }
    }
}
if ($script:Claude) {
    $v = & $script:Claude --version 2>$null | Select-Object -First 1
    Write-Host "  claude:  $v"
} else {
    Warn '  claude в PATH не найден.'
    Write-Host '  Десктопное приложение Claude само в PATH не прописывается.'
    Write-Host '  Плагин я поставить не смогу — остальное установлю.'
    Write-Host '  Поставить командную строку: npm i -g @anthropic-ai/claude-code'
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Warn '  git не найден — связь задач с коммитами работать не будет' }
if ($script:Restricted) {
    Warn "  PowerShell в режиме $($ExecutionContext.SessionState.LanguageMode) — часть шагов пропущу"
    Write-Host '  Это политика вашей организации, не поломка. Установка пройдёт.'
}

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
if (-not $script:Claude) {
    Warn '  пропускаю: claude не найден. Поставьте его и запустите установщик снова.'
} elseif ((& $script:Claude plugin list 2>$null) -match 'taiga-kit') {
    # Пропускать нельзя: программа обновится, а навык останется старым —
    # кэш плагина привязан к версии и сам не перечитывается.
    Write-Host '  уже стоит — обновляю'
    try { & $script:Claude plugin marketplace update taiga-kit 2>$null | Out-Null }
    catch { try { & $script:Claude plugin marketplace update 2>$null | Out-Null } catch {} }
    try   { & $script:Claude plugin update taiga-kit@taiga-kit 2>$null | Out-Null
            Write-Host '  плагин обновлён' }
    catch { Warn '  обновить не удалось — см. README, раздел про обновление' }
    Write-Host '  ПЕРЕЗАПУСТИТЕ Claude Code: без этого останется старый навык.'
} else {
    Write-Host '  подключаю каталог и ставлю плагин…'
    try   { & $script:Claude plugin marketplace add Sigmatick/taiga-kit 2>$null | Out-Null }
    catch { try { & $script:Claude plugin marketplace add $src 2>$null | Out-Null } catch { Warn '  каталог подключить не удалось' } }
    try   { & $script:Claude plugin install taiga-kit@taiga-kit 2>$null | Out-Null; Write-Host '  плагин установлен' }
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

# В ограниченном языковом режиме (политика WDAC/AppLocker) доступ к типам
# .NET запрещён, и правка PATH упала бы с невнятной ошибкой. Это не повод
# прерывать установку: внутри Claude Code программа всё равно находится
# по пути плагина, PATH нужен только для вызова из терминала вручную.
if ($script:Restricted) {
    Warn '  PATH не меняю: PowerShell в ограниченном режиме'
    Write-Host '  На работу в Claude Code это не влияет.'
    Write-Host "  Нужен вызов 'taiga' из терминала — добавьте в PATH вручную:"
    Write-Host "     $bin"
} else {
    try {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath -notlike "*$bin*") {
            [Environment]::SetEnvironmentVariable('Path', "$bin;$userPath", 'User')
            Write-Host '  путь дописан в PATH (подействует в новых окнах консоли)'
        }
    } catch {
        Warn "  PATH дописать не удалось: $_"
        Write-Host "  Добавьте вручную, если нужен вызов из терминала:  $bin"
    }
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
Write-Host '  Слаг — одно слово сразу после /project/, до следующей косой черты.'
Write-Host '  Всё, что дальше, — страница, а не часть слага:'
Write-Host '     .../project/domcom/kanban            -> domcom'
Write-Host '     .../project/egsv/us/159              -> egsv'
Write-Host '     .../project/digital-police/task/294  -> digital-police'
Write-Host '  Дефис входит в слаг. Слаг не равен названию: проект могли переименовать.'
Write-Host ''
# Проектов обычно несколько, и у каждого СВОЯ папка с кодом: привязка
# лежит в ней, а не в общем списке. Поэтому не строка слагов, а цикл.
Write-Host '  Подключать можно сколько угодно: после каждого спрошу, нужен ли ещё.'
Write-Host ''
$doneN = 0; $lastDir = ''
while ($true) {
    $slug = Read-Host '  слаг проекта (пусто — закончить)'
    if (-not $slug) { break }
    $def = Join-Path $env:USERPROFILE "Documents\$slug"
    $dir = Read-Host "  папка проекта [$def]"
    if (-not $dir) { $dir = $def }
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    catch { Warn "  не удалось создать $dir — пропускаю"; continue }
    Push-Location $dir
    & "$bin\taiga.cmd" init $slug
    if ($LASTEXITCODE -eq 0) {
        $doneN++; $lastDir = $dir
        & "$bin\taiga.cmd" ls --open | Select-Object -First 4
    } else {
        Warn "  «$slug» подключить не удалось — проверьте слаг и права"
    }
    Pop-Location
    Write-Host ''
}

if ($doneN -gt 0) {
    Bold "Готово: подключено проектов — $doneN"
    Write-Host "  Откройте Claude Code с папкой проекта, например:`n     $lastDir`n  и напишите: что в бэклоге"
    Write-Host ''
    Write-Host '  ЭТО УСТАНАВЛИВАЕТСЯ ОДИН РАЗ НА КОМПЬЮТЕР.' -ForegroundColor Yellow
    Write-Host '  Для следующего проекта распаковывать архив заново НЕ НУЖНО:'
    Write-Host '  откройте Claude Code с его папкой и напишите в чате'
    Write-Host '     подключи эту папку к проекту <слаг>'
} else {
    Bold 'Готово'
    Write-Host '  Проекты подключите позже: откройте Claude Code с папкой проекта'
    Write-Host '  и напишите:  подключи эту папку к проекту <слаг>'
    Write-Host '  Переустанавливать кит для этого НЕ НУЖНО.' -ForegroundColor Yellow
}

# ── ежедневный отчёт ──
Bold 'Ежедневный отчёт'
Write-Host @'
  Кто что создал, взял и закрыл за предыдущий рабочий день — по всем проектам.
  Складывается в ~\.taiga-kit\отчёты\ отдельным файлом на день.
'@
if (Ask '  ставить на расписание (будни 09:00)?') {
    & "$bin\taiga.cmd" report --install
} else {
    Write-Host '  пропущено. Поставить позже:  taiga report --install'
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

# -- Telegram: только подсказка, рассылку включает администратор --
Bold 'Уведомления в Telegram'
Write-Host @'
  Бот: @MegacamPulseControl_bot

  Найдите его в Telegram, нажмите Start и скажите администратору —
  он свяжет ваш чат с учётной записью Taiga.

  Бот не имеет права писать первым: пока вы сами ему не напишете,
  рассылки не будет. Ваш Start и есть согласие её получать.

  Расписание рассылки ставится централизованно, на одной машине.
  Здесь ничего включать не надо.
'@

Read-Host "`nEnter — закрыть"
