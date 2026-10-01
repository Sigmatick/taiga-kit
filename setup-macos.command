#!/usr/bin/env bash
# Полная установка для macOS: плагин + программа + вход + подключение проекта.
# Файл .command запускается двойным щелчком из Finder.
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
export PATH="$BIN:$PATH"

bold() { printf '\n\033[1m%s\033[0m\n' "$1"; }
warn() { printf '\033[33m%s\033[0m\n' "$1"; }
fail() { printf '\033[31mостанов: %s\033[0m\n' "$1"; printf '\nНажмите Enter, чтобы закрыть.\n'; read -r _; exit 1; }
ask()  { read -r -p "$1 [y/N] " a; [[ "$a" =~ ^([yY]|[дД]а?)$ ]]; }

clear
cat <<'TXT'
┌──────────────────────────────────────────────┐
│  Taiga в Claude Code — установка             │
└──────────────────────────────────────────────┘

Пять шагов. Прерваться можно в любой момент: Ctrl+C.
TXT

# ── 1. что уже есть ─────────────────────────────────────────────────────────
bold "Шаг 1 из 5. Проверка окружения"
command -v python3 >/dev/null || fail "нет python3. Выполните в Терминале: xcode-select --install"
echo "  python3: $(python3 --version)"
command -v claude  >/dev/null || fail "нет Claude Code. Поставьте его и запустите этот файл снова."
echo "  claude:  $(claude --version 2>/dev/null | head -1)"
command -v git     >/dev/null || fail "нет git. Выполните: xcode-select --install"
echo "  git:     есть"

# ── 2. плагин ───────────────────────────────────────────────────────────────
bold "Шаг 2 из 5. Плагин Claude Code"
if claude plugin list 2>/dev/null | grep -q "taiga-kit"; then
  echo "  уже установлен"
else
  echo "  подключаю каталог и ставлю плагин…"
  claude plugin marketplace add Sigmatick/taiga-kit >/dev/null 2>&1 \
    || claude plugin marketplace add "$SRC" >/dev/null 2>&1 \
    || warn "  каталог подключить не удалось — плагин поставьте вручную"
  claude plugin install taiga-kit@taiga-kit >/dev/null 2>&1 \
    && echo "  плагин установлен" \
    || warn "  плагин не установился — см. README"
fi

# ── 3. программа ────────────────────────────────────────────────────────────
bold "Шаг 3 из 5. Программа taiga"
mkdir -p "$BIN"
cp "$SRC/bin/taiga" "$BIN/taiga" && chmod +x "$BIN/taiga"
echo "  установлена: $BIN/taiga"
if ! grep -qs '\.local/bin' "$HOME/.zshrc" 2>/dev/null; then
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
  echo "  путь дописан в ~/.zshrc (подействует в новых окнах Терминала)"
fi

# ── 4. вход ─────────────────────────────────────────────────────────────────
bold "Шаг 4 из 5. Вход в Taiga"
if "$BIN/taiga" status >/dev/null 2>&1; then
  "$BIN/taiga" status | sed 's/^/  /'
  ask "  войти заново под другой учётной записью?" && "$BIN/taiga" login
else
  cat <<'TXT'
  Сейчас спросим адрес, логин и пароль.
  Пароль при вводе НЕ отображается — ни звёздочек, ни курсора.
  Это нормально: печатайте вслепую и нажмите Enter.
TXT
  "$BIN/taiga" login || fail "вход не выполнен"
fi

# ── 5. проект ───────────────────────────────────────────────────────────────
bold "Шаг 5 из 5. Подключение проекта"
"$BIN/taiga" projects || fail "список проектов не получен"
echo
echo "  Слаг — это левый столбец. В адресе браузера он же:"
echo "  https://<инстанс>/project/СЛАГ/kanban"
echo
read -r -p "  слаг проекта (пусто — пропустить): " SLUG
if [ -n "$SLUG" ]; then
  DEF="$HOME/Documents/$SLUG"
  read -r -p "  папка проекта [$DEF]: " DIR
  DIR="${DIR:-$DEF}"
  DIR="${DIR/#\~/$HOME}"
  mkdir -p "$DIR" || fail "не удалось создать $DIR"
  ( cd "$DIR" && "$BIN/taiga" init "$SLUG" ) || fail "подключение не удалось"
  echo
  ( cd "$DIR" && "$BIN/taiga" ls --open 2>/dev/null | head -6 )
  bold "Готово"
  cat <<TXT
  Откройте Claude Code с папкой:
     $DIR
  и напишите: что в бэклоге

  Ещё проект: перейти в его папку и выполнить  taiga init <слаг>
TXT
else
  bold "Готово"
  echo "  Проект подключите позже: перейти в его папку и  taiga init <слаг>"
fi

printf '\nНажмите Enter, чтобы закрыть окно.\n'
read -r _
