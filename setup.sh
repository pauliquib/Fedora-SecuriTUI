#!/usr/bin/env bash
# Nastavení aliasu m a volitelných symlinků do $HOME
# Spuštění: bash setup.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MENU_SH="${PROJECT_DIR}/menu.sh"
FISH_CFG="${HOME}/.config/fish/config.fish"
BASHRC="${HOME}/.bashrc"

[[ -x "$MENU_SH" ]] || { echo "Chyba: $MENU_SH neexistuje nebo není spustitelný."; exit 1; }

echo "==> Projekt: $PROJECT_DIR"

# --- Fish (výchozí shell) ---
mkdir -p "${HOME}/.config/fish"
if [[ -f "$FISH_CFG" ]]; then
  if grep -q 'alias m=' "$FISH_CFG" 2>/dev/null; then
    sed -i "s|alias m=.*|alias m=\"${MENU_SH}\"|" "$FISH_CFG"
    echo "Fish: alias m aktualizován"
  else
    # přidat do is-interactive bloku nebo na konec
    if grep -q 'if status is-interactive' "$FISH_CFG"; then
      sed -i "/if status is-interactive/a alias m=\"${MENU_SH}\"" "$FISH_CFG"
    else
      printf '\nif status is-interactive\nalias m="%s"\nend\n' "$MENU_SH" >> "$FISH_CFG"
    fi
    echo "Fish: alias m přidán"
  fi
else
  cat >"$FISH_CFG" <<EOF
if status is-interactive
alias m="${MENU_SH}"
end
EOF
  echo "Fish: vytvořen $FISH_CFG"
fi

# --- Bash ---
if [[ -f "$BASHRC" ]]; then
  if grep -q '^alias m=' "$BASHRC" 2>/dev/null; then
    sed -i "s|^alias m=.*|alias m=\"${MENU_SH}\"|" "$BASHRC"
    echo "Bash: alias m aktualizován"
  else
    printf '\nalias m="%s"\n' "$MENU_SH" >> "$BASHRC"
    echo "Bash: alias m přidán do .bashrc"
  fi
fi

# --- Volitelné symlinky v HOME (zpětná kompatibilita) ---
ln -sf "$MENU_SH" "${HOME}/menu.sh"
ln -sf "${PROJECT_DIR}/install-pentest-tools.sh" "${HOME}/install-pentest-tools.sh"
echo "Symlinky: ~/menu.sh -> $MENU_SH"

# --- dialogrc ---
mkdir -p "${HOME}/.config/menu"
cp "${PROJECT_DIR}/config/dialogrc" "${HOME}/.config/menu/dialogrc"
echo "Téma: ~/.config/menu/dialogrc"

echo
echo "Hotovo. Otevři nový terminál nebo:"
echo "  fish -c 'source ~/.config/fish/config.fish'"
echo "  bash -lc 'source ~/.bashrc'"
echo "Pak spusť: m"
