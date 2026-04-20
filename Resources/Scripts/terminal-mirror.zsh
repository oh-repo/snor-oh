# --- snor-oh Terminal Mirror (Zsh) ---
# Source this in .zshrc:  source /path/to/terminal-mirror.zsh
#
# Presence is event-driven: POST /session-start once on source,
# /session-end from the EXIT trap. snor-oh verifies PID liveness via
# kill(0) every 2 s, so force-quit terminals still get cleaned up.

export TAURI_MIRROR_PORT=1425
_TM_URL="http://127.0.0.1:${TAURI_MIRROR_PORT}"
_TM_SESSIONS_DIR="$HOME/.snor-oh/sessions"

_tm_urlenc() { printf '%s' "$1" | sed 's/ /%20/g'; }

_tm_is_claude() {
  local cmd="$1"
  local first_word="${cmd%% *}"
  [[ "$first_word" == "claude" ]] && return 0
  local resolved=$(whence "$first_word" 2>/dev/null)
  [[ "$resolved" == *claude* ]] && return 0
  return 1
}

_tm_classify() {
  local cmd="$1"
  if [[ "$cmd" =~ (^|[[:space:]/])(start|dev|serve|watch|metro|docker-compose|docker\ compose|up|run\ dev|run\ start|run\ serve)([[:space:]]|$) ]]; then
    echo "service"
  else
    echo "task"
  fi
}

_tm_session_start() {
  mkdir -p "$_TM_SESSIONS_DIR"
  local lstart=$(ps -o lstart= -p $$ | sed 's/^ *//;s/ *$//')
  local pwd_now=$(pwd)
  printf '{"pid":%d,"cwd":"%s","kind":"shell","started_at":"%s"}\n' \
    "$$" "$pwd_now" "$lstart" > "$_TM_SESSIONS_DIR/$$.json"
  curl -s --max-time 2 \
    "${_TM_URL}/session-start?pid=$$&cwd=$(_tm_urlenc "$pwd_now")&kind=shell&started_at=$(_tm_urlenc "$lstart")" \
    > /dev/null 2>&1 &!
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
  _tm_is_claude "$1" && return
  local cmd_type=$(_tm_classify "$1")
  curl -s --max-time 1 "${_TM_URL}/status?pid=$$&state=busy&type=${cmd_type}&cwd=$(pwd)" > /dev/null 2>&1 &!
}

_tm_precmd() {
  curl -s --max-time 1 "${_TM_URL}/status?pid=$$&state=idle&cwd=$(pwd)" > /dev/null 2>&1 &!
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _tm_preexec
add-zsh-hook precmd  _tm_precmd
