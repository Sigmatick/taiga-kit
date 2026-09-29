#!/usr/bin/env bash
# Установка CLI для работы ВНЕ Claude Code (терминал, скрипты, cron).
# Внутри Claude Code плагин ставится через /plugin и этот скрипт не нужен.
set -u
BIN="$HOME/.local/bin"; SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ask() { read -r -p "$1 [y/N] " a; [[ "$a" =~ ^([yY]|[дД]а?)$ ]]; }

say "taiga-kit — установка CLI"
command -v python3 >/dev/null || { echo "нет python3: xcode-select --install"; exit 1; }
mkdir -p "$BIN"; cp "$SRC/bin/taiga" "$BIN/taiga"; chmod +x "$BIN/taiga"
echo "установлено: $BIN/taiga"

if ! command -v taiga >/dev/null 2>&1; then
  RC="$HOME/.zshrc"
  say "Каталог $BIN не в PATH"
  if ask "дописать строку в $RC?"; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC"
    echo "дописано — откройте новый терминал"
  fi
  export PATH="$BIN:$PATH"
fi

say "Шаг 1. Вход"
if "$BIN/taiga" status >/dev/null 2>&1; then "$BIN/taiga" status
else
  echo "Токена нет. Спросим адрес, логин и пароль; пароль не отображается."
  "$BIN/taiga" login || { echo "вход не выполнен"; exit 1; }
fi

say "Шаг 2. Проверка"
"$BIN/taiga" projects || exit 1

say "Готово"
echo "Подключить проект: перейти в его папку и  taiga init <слаг>"
