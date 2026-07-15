#!/bin/bash
set -euo pipefail

KEYCHAIN_SERVICE="Claude Code-credentials"
KEYCHAIN_ACCOUNT="gyeongho.yang"
HOME_DIR="/Users/$KEYCHAIN_ACCOUNT"

# Validate argument
[[ -z "${1:-}" || ! "$1" =~ ^[1-3]$ ]] && { echo "Usage: $0 {1|2|3}"; exit 1; }

# Backup current credentials to appropriate profile (pro → home, enterprise → work)
if secret=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null); then
  backup_target=$(echo "$secret" | jq -r '.claudeAiOauth.subscriptionType' 2>/dev/null | grep -q "pro" && echo "$HOME_DIR/.claude-home" || echo "$HOME_DIR/.claude-work")
  [[ -n "$backup_target" ]] && printf '%s' "$secret" | jq . > "$backup_target/keychain-credentials.json" && chmod 600 "$backup_target/keychain-credentials.json"
fi

# Switch to target profile
target=$([[ "$1" == "1" ]] && echo "$HOME_DIR/.claude-home" || echo "$HOME_DIR/.claude-work")
ln -sfn "$target" "$HOME_DIR/.claude"

# Setup settings file for selected profile
[[ "$1" == "2" ]] && echo '{}' > "$HOME_DIR/.claude-work/settings.json"
[[ "$1" == "3" ]] && cp "$HOME_DIR/.claude-work/settings.dh.json" "$HOME_DIR/.claude-work/settings.json"

# Restore credentials from target profile to keychain
[[ -f "$target/keychain-credentials.json" ]] && security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w "$(jq -c . "$target/keychain-credentials.json")"

# Print profile name
case "$1" in
  1) echo "Personal" ;;
  2) echo "Enterprise" ;;
  3) echo "LiteLLM" ;;
esac

# Restore latest backup or clean up old one
latest_backup=$(ls -1t "$HOME_DIR/.claude/backups"/.claude.json.backup.* 2>/dev/null | head -n1 || true)
[[ -n "$latest_backup" ]] && cp "$latest_backup" "$HOME_DIR/.claude.json" || rm -f "$HOME_DIR/.claude.json"
