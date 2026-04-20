# --- snor-oh Terminal Mirror (Bash) ---
# Source this in .bashrc:  source /path/to/terminal-mirror.bash
#
# Presence is event-driven: POST /session-start on source, /session-end on
# EXIT. snor-oh verifies PID liveness via kill(0) every 2s.

export TAURI_MIRROR_PORT=1234
_TM_URL="http://127.0.0.1:${TAURI_MIRROR_PORT}"
_TM_SESSIONS_DIR="$HOME/.snor-oh/sessions"
_TM_CMD_RUNNING=0

_tm_urlenc() { printf '%s' "$1" | sed 's/ /%20/g'; }

_tm_is_claude() {
  local first_word="${1%% *}"
  [[ "$first_word" == "claude" ]] && return 0
  local resolved
  resolved=$(type -p "$first_word" 2>/dev/null)
  [[ "$resolved" == *claude* ]] && return 0
  return 1
}

_tm_classify() {
  local cmd="$1"
  if [[ "$cmd" =~ (^|[[:space:]/])(start|dev|serve|watch|metro|docker-compose|docker\ compose|up) ]]; then
    echo "service"
  else
    echo "task"
  fi
}

_tm_bg() { { "$@" & disown; } 2>/dev/null; }

_tm_session_start() {
  mkdir -p "$_TM_SESSIONS_DIR"
  local lstart pwd_now
  lstart=$(ps -o lstart= -p $$ | sed 's/^ *//;s/ *$//')
  pwd_now=$(pwd)
  printf '{"pid":%d,"cwd":"%s","kind":"shell","started_at":"%s"}\n' \
    "$$" "$pwd_now" "$lstart" > "$_TM_SESSIONS_DIR/$$.json"
  _tm_bg curl -s --max-time 2 \
    "${_TM_URL}/session-start?pid=$$&cwd=$(_tm_urlenc "$pwd_now")&kind=shell&started_at=$(_tm_urlenc "$lstart")" \
    > /dev/null 2>&1
}

_tm_session_end() {
  rm -f "$_TM_SESSIONS_DIR/$$.json" 2>/dev/null
  curl -s --max-time 1 "${_TM_URL}/session-end?pid=$$" > /dev/null 2>&1
}

if [[ -z "$_TM_REGISTERED" ]]; then
  _TM_REGISTERED=1
  _tm_session_start
  trap '_tm_session_end' EXIT
fi

_tm_preexec() {
  [[ "$_TM_CMD_RUNNING" == "1" ]] && return
  [[ "$BASH_COMMAND" == "_tm_precmd" ]] && return
  [[ "$BASH_COMMAND" == *"_tm_precmd"* ]] && return

  _TM_CMD_RUNNING=1
  local cmd="$BASH_COMMAND"

  _tm_is_claude "$cmd" && return

  local cmd_type
  cmd_type=$(_tm_classify "$cmd")
  _tm_bg curl -s --max-time 1 "${_TM_URL}/status?pid=$$&state=busy&type=${cmd_type}&cwd=$(pwd)" > /dev/null 2>&1
}
trap '_tm_preexec' DEBUG

_tm_precmd() {
  _TM_CMD_RUNNING=0
  _tm_bg curl -s --max-time 1 "${_TM_URL}/status?pid=$$&state=idle&cwd=$(pwd)" > /dev/null 2>&1
}
PROMPT_COMMAND="_tm_precmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
