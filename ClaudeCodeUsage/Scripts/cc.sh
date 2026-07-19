#!/bin/bash
set -euo pipefail

KEYCHAIN_SERVICE="Claude Code-credentials"
KEYCHAIN_ACCOUNT="gyeongho.yang"
HOME_DIR="/Users/$KEYCHAIN_ACCOUNT"

# Validate argument
[[ -z "${1:-}" || ! "$1" =~ ^[1-2]$ ]] && { echo "Usage: $0 {1|2}"; exit 1; }

# Clean up temporary claude json files
rm -f "$HOME_DIR"/.claude.json.tmp.* "$HOME_DIR"/.claude.json.lock* 2>/dev/null || true

# Backup current credentials and .claude.json to appropriate profile
if secret=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null); then
  backup_target=$(echo "$secret" | jq -r '.claudeAiOauth.subscriptionType' 2>/dev/null | grep -q "pro" && echo "$HOME_DIR/.claude-home" || echo "$HOME_DIR/.claude-work")
  [[ -n "$backup_target" ]] && printf '%s' "$secret" | jq . > "$backup_target/keychain-credentials.json" && chmod 600 "$backup_target/keychain-credentials.json"
  [[ -n "$backup_target" && -f "$HOME_DIR/.claude.json" ]] && cp "$HOME_DIR/.claude.json" "$backup_target/.claude.json" && chmod 600 "$backup_target/.claude.json"
fi

# Switch to target profile
target=$([[ "$1" == "1" ]] && echo "$HOME_DIR/.claude-home" || echo "$HOME_DIR/.claude-work")
ln -sfn "$target" "$HOME_DIR/.claude"

# Restore credentials from target profile to keychain
[[ -f "$target/keychain-credentials.json" ]] && security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w "$(jq -c . "$target/keychain-credentials.json")"

# Restore .claude.json from target profile or remove if not exists
[[ -f "$target/.claude.json" ]] && cp "$target/.claude.json" "$HOME_DIR/.claude.json" || rm -f "$HOME_DIR/.claude.json"

# Print profile name
case "$1" in
  1) echo "Home" ;;
  2) echo "Work" ;;
esac
