#!/bin/bash
# Claude Code notification script
# Sends notification after CLAUDE_ALARM_DELAY seconds of inactivity (default: 30s)
# Includes task context: user request, Claude response, questions, and todo status
#
# === COMPATIBILITY WARNING ===
# This script relies on parse-transcript.sh to parse Claude Code's internal transcript format.
# The transcript structure is not a public API and may change between versions.
# If notifications stop working after a Claude Code update, the jq queries may need adjustment.
#
# Last tested with: Claude Code v2.1.11 (2025-01-18)

# === HELPER FUNCTIONS ===

truncate_text() {
  local text="$1"
  local line_count
  line_count=$(echo "$text" | wc -l)

  if [ "$line_count" -le 10 ]; then
    echo "$text"
  else
    local first last
    first=$(echo "$text" | head -n 5)
    last=$(echo "$text" | tail -n 5)
    echo "$first"
    echo ""
    echo "...(truncated)..."
    echo ""
    echo "$last"
  fi
}

escape_json() {
  local text="$1"
  text="${text//\\/\\\\}"
  text="${text//\"/\\\"}"
  text="${text//$'\n'/\\n}"
  text="${text//$'\t'/\\t}"
  echo "$text"
}

# Slack Web API POST helper (requires jq, curl)
slack_api_post() {
  local endpoint="$1"
  local payload="$2"
  curl -sS -X POST "https://slack.com/api/${endpoint}" \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "$payload"
}

get_dm_channel_id() {
  # Cache DM channel ID to avoid calling conversations.open every time
  local cache_file="$HOME/.claude/attention-hook.slack_dm_channel_id"
  if [ -f "$cache_file" ]; then
    local cached
    cached=$(cat "$cache_file" 2>/dev/null | tr -d '\n' | tr -d '\r')
    if [ -n "$cached" ]; then
      echo "$cached"
      return 0
    fi
  fi

  local resp ok ch
  resp=$(slack_api_post "conversations.open" "{\"users\":\"${SLACK_USER_ID}\"}")
  ok=$(echo "$resp" | jq -r '.ok // false')
  if [ "$ok" != "true" ]; then
    return 1
  fi

  ch=$(echo "$resp" | jq -r '.channel.id // empty')
  if [ -z "$ch" ]; then
    return 1
  fi

  mkdir -p "$HOME/.claude" >/dev/null 2>&1
  echo -n "$ch" > "$cache_file" 2>/dev/null || true
  echo "$ch"
}

send_dm() {
  local channel_id="$1"
  local text="$2"
  slack_api_post "chat.postMessage" "{\"channel\":\"${channel_id}\",\"text\":\"${text}\"}" >/dev/null 2>&1
}

# === MAIN LOGIC ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # === CONFIGURATION ===
  ENV_FILE="$HOME/.claude/.env"
  if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
  fi

  # Bot API envs (DM)
  SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-}"
  SLACK_USER_ID="${SLACK_USER_ID:-}"

  # If not configured, do nothing (fail quietly to avoid breaking hook pipeline)
  if [ -z "$SLACK_BOT_TOKEN" ] || [ -z "$SLACK_USER_ID" ]; then
    exit 0
  fi

  # === READ HOOK INPUT ===
  INPUT=$(cat)
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

  # === BUILD NOTIFICATION ===
  HOSTNAME=$(hostname)
  TITLE="Claude Code @ $HOSTNAME"

  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    PARSE_SCRIPT="$SCRIPT_DIR/parse-transcript.sh"

    if [ -x "$PARSE_SCRIPT" ]; then
      eval "$("$PARSE_SCRIPT" "$TRANSCRIPT_PATH")"
      LAST_HUMAN_TEXT="$PARSED_HUMAN_TEXT"
      LAST_ASSISTANT_TEXT="$PARSED_ASSISTANT_TEXT"
      ASK_QUESTION="$PARSED_ASK_QUESTION"
      TODO_STATUS="$PARSED_TODO_STATUS"
    else
      LAST_HUMAN_TEXT=""
      LAST_ASSISTANT_TEXT=""
      ASK_QUESTION=""
      TODO_STATUS=""
    fi

    MESSAGE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"$'\n'

    if [ -n "$LAST_HUMAN_TEXT" ]; then
      TRUNCATED_REQUEST=$(truncate_text "$LAST_HUMAN_TEXT")
      MESSAGE+=$'\n'":memo: Request:"$'\n'"$TRUNCATED_REQUEST"$'\n'
    fi

    if [ -n "$LAST_ASSISTANT_TEXT" ]; then
      TRUNCATED_RESPONSE=$(truncate_text "$LAST_ASSISTANT_TEXT")
      MESSAGE+=$'\n'":robot_face: Response:"$'\n'"$TRUNCATED_RESPONSE"$'\n'
    fi

    if [ -n "$ASK_QUESTION" ]; then
      TRUNCATED_QUESTION=$(truncate_text "$ASK_QUESTION")
      MESSAGE+=$'\n'":question: Waiting for answer:"$'\n'"$TRUNCATED_QUESTION"$'\n'
    fi

    if [ -n "$TODO_STATUS" ]; then
      MESSAGE+=$'\n'"$TODO_STATUS"
    fi
  else
    MESSAGE="Claude is waiting for your input"
  fi

  # === SEND NOTIFICATIONS (Slack DM via Bot API) ===
  # Compose final Slack text (bold title + message)
  FINAL_TEXT="*$(escape_json "$TITLE")*\\n$(escape_json "$MESSAGE")"

  CHANNEL_ID=$(get_dm_channel_id)
  if [ -n "$CHANNEL_ID" ]; then
    send_dm "$CHANNEL_ID" "$FINAL_TEXT"
  fi

  exit 0
fi
