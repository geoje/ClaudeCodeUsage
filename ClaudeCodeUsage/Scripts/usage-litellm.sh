#!/bin/bash

CF_TOKEN=$(cat "$HOME/.claude-work/litellm-token" 2>/dev/null)

curl -s 'https://dp-litellm.deliveryhero.net/dh-self-service/api/v1/self' \
  -b "CF_Authorization=$CF_TOKEN" \
  | jq -r .spend \
  | awk '{print int($1)}'
