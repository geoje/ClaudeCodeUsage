#!/bin/bash

cd /Users/gyeongho.yang || exit 1
export TERM="${TERM:-xterm-256color}"

USAGE=$(expect -c '
  log_user 0
  set timeout 4
  spawn /Users/gyeongho.yang/.local/bin/claude /usage --ax-screen-reader
  expect {
    "used" {
      puts $expect_out(buffer)
    }
  }
  expect eof
')

echo "$USAGE" \
  | perl -pe 's/\e\[[0-9;?]*[a-zA-Z]//g; s/\e\].*?(\a|\e\\)//g; s/\e.//g' \
  | tail -1 \
  | awk '{print $2}'
