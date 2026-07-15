#!/bin/bash

cd /Users/gyeongho.yang || exit 1
export TERM="${TERM:-xterm-256color}"

RAW=$(expect -c '
  log_user 0
  set timeout 8
  spawn /Users/gyeongho.yang/.local/bin/claude /usage --ax-screen-reader

  expect "Current session"
  expect -re {([0-9]+)% [0-9]+% used}
  set sessionPct $expect_out(1,string)

  expect -re {Resets ([^\r\n]+)\r?\n}
  set sessionReset $expect_out(1,string)

  expect "Current week (all models)"
  expect -re {([0-9]+)% [0-9]+% used}
  set weeklyPct $expect_out(1,string)

  expect -re {Resets ([^\r\n]+)\r?\n}
  set weeklyReset $expect_out(1,string)

  set pid [exp_pid]
  catch {exec kill -9 $pid}
  catch {close}
  catch {wait}

  puts "SESSION_PCT=$sessionPct"
  puts "SESSION_RESET=$sessionReset"
  puts "WEEKLY_PCT=$weeklyPct"
  puts "WEEKLY_RESET=$weeklyReset"
')

# Normalizes "9am" / "12:30am" -> "09:00AM" / "12:30AM" for `date -f` parsing.
normalize_time() {
  local t="$1"
  local ap
  ap=$(echo "${t: -2}" | tr 'a-z' 'A-Z')
  local hm="${t%??}"
  local h m
  if [[ "$hm" == *":"* ]]; then
    h="${hm%%:*}"; m="${hm##*:}"
  else
    h="$hm"; m="00"
  fi
  printf "%02d:%02d%s" "$((10#$h))" "$((10#$m))" "$ap"
}

# Converts a "Resets ..." string into a unix epoch.
# Session-style:  "12:30am (Europe/Berlin)"          -> next occurrence of that time
# Weekly-style:   "Jul 21 at 10am (Europe/Berlin)"    -> that date/time this year
reset_to_epoch() {
  local raw="$1"
  local zone
  zone=$(echo "$raw" | sed -nE 's/.*\(([^)]+)\).*/\1/p')
  [[ -z "$zone" ]] && zone="UTC"
  local now epoch
  now=$(date +%s)

  if [[ "$raw" == *" at "* ]]; then
    local mon day time_norm
    mon=$(echo "$raw" | sed -nE 's/^([A-Za-z]{3}) ([0-9]{1,2}) at.*/\1/p')
    day=$(echo "$raw" | sed -nE 's/^([A-Za-z]{3}) ([0-9]{1,2}) at.*/\2/p')
    time_norm=$(normalize_time "$(echo "$raw" | sed -nE 's/.*at ([0-9]{1,2}(:[0-9]{2})?[ap]m).*/\1/p')")
    local year
    year=$(TZ="$zone" date +%Y)
    epoch=$(TZ="$zone" date -j -f "%Y %b %d %I:%M%p" "$year $mon $day $time_norm" +%s 2>/dev/null)
    [[ -n "$epoch" && "$epoch" -lt "$now" ]] && epoch=$(TZ="$zone" date -j -v+1y -f "%Y %b %d %I:%M%p" "$year $mon $day $time_norm" +%s 2>/dev/null)
  else
    local time_norm today
    time_norm=$(normalize_time "$(echo "$raw" | sed -nE 's/^([0-9]{1,2}(:[0-9]{2})?[ap]m).*/\1/p')")
    today=$(TZ="$zone" date +%Y-%m-%d)
    epoch=$(TZ="$zone" date -j -f "%Y-%m-%d %I:%M%p" "$today $time_norm" +%s 2>/dev/null)
    [[ -n "$epoch" && "$epoch" -lt "$now" ]] && epoch=$((epoch + 86400))
  fi

  echo "${epoch:-0}"
}

SESSION_PCT=$(echo "$RAW" | sed -nE 's/^SESSION_PCT=(.*)/\1/p')
SESSION_RESET_RAW=$(echo "$RAW" | sed -nE 's/^SESSION_RESET=(.*)/\1/p')
WEEKLY_PCT=$(echo "$RAW" | sed -nE 's/^WEEKLY_PCT=(.*)/\1/p')
WEEKLY_RESET_RAW=$(echo "$RAW" | sed -nE 's/^WEEKLY_RESET=(.*)/\1/p')

[[ -z "$SESSION_PCT" || -z "$WEEKLY_PCT" ]] && exit 1

echo "SESSION_PERCENT=$SESSION_PCT"
echo "SESSION_RESET_EPOCH=$(reset_to_epoch "$SESSION_RESET_RAW")"
echo "WEEKLY_PERCENT=$WEEKLY_PCT"
echo "WEEKLY_RESET_EPOCH=$(reset_to_epoch "$WEEKLY_RESET_RAW")"
