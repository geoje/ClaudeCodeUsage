#!/bin/bash

TOKEN=$(cat ~/.claude-home/keychain-credentials.json | jq -r .claudeAiOauth.accessToken)

curl -s -D - -o /dev/null \
  -X POST 'https://api.anthropic.com/v1/messages' \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
  | grep -i "anthropic-ratelimit"
