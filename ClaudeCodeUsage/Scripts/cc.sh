#!/bin/bash
set -euo pipefail

KEYCHAIN_SERVICE="Claude Code-credentials"
KEYCHAIN_ACCOUNT="gyeongho.yang"
HOME_DIR="/Users/$KEYCHAIN_ACCOUNT"

save_current_creds() {
  local dest="$1/keychain-credentials.json"
  local secret
  if secret=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null); then
    printf '%s' "$secret" > "$dest"
    chmod 600 "$dest"
  fi
}

restore_creds() {
  local src="$1/keychain-credentials.json"
  if [[ -f "$src" ]]; then
    security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w "$(cat "$src")"
  fi
}

case "${1:-}" in
  1)
    new_target="$HOME_DIR/.claude-home"
    ;;
  2|3)
    new_target="$HOME_DIR/.claude-work"
    ;;
  *)
    echo "Usage: $0 {1|2|3}"
    exit 1
    ;;
esac

current_target=$(readlink "$HOME_DIR/.claude" 2>/dev/null || true)
if [[ -n "$current_target" && "$current_target" == "$new_target" ]]; then
  save_current_creds "$current_target"
fi

case "${1:-}" in
  1)
    ln -sfn "$HOME_DIR/.claude-home" "$HOME_DIR/.claude"
    restore_creds "$HOME_DIR/.claude-home"
    echo "Personal"
    ;;
  2)
    ln -sfn "$HOME_DIR/.claude-work" "$HOME_DIR/.claude"
    echo '{}' > "$HOME_DIR/.claude-work/settings.json"
    restore_creds "$HOME_DIR/.claude-work"
    echo "Enterprise"
    ;;
  3)
    ln -sfn "$HOME_DIR/.claude-work" "$HOME_DIR/.claude"
    cp "$HOME_DIR/.claude-work/settings.dh.json" "$HOME_DIR/.claude-work/settings.json"
    echo "LiteLLM"
    ;;
esac

latest_backup=$(ls -1t "$HOME_DIR/.claude/backups"/.claude.json.backup.* 2>/dev/null | head -n1 || true)
if [[ -n "$latest_backup" ]]; then
  cp "$latest_backup" "$HOME_DIR/.claude.json"
else
  rm -f "$HOME_DIR/.claude.json"
fi
