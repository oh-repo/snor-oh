# --- snor-oh Terminal Mirror (Zsh) ---
# Source this in .zshrc:  source /path/to/terminal-mirror.zsh

export TAURI_MIRROR_PORT=1234
_TM_URL="http://127.0.0.1:${TAURI_MIRROR_PORT}"

# --- Detect if a command is Claude Code (works with aliases/functions) ---
_tm_is_claude() {
  local cmd="$1"
  local first_word="${cmd%% *}"
  # Direct match
  [[ "$first_word" == "claude" ]] && return 0
  # Resolve alias/function — e.g. "ccc" → "claude"
  local resolved=$(whence "$first_word" 2>/dev/null)
  [[ "$resolved" == *claude* ]] && return 0
  return 1
}

# --- Command categorization ---
# "service" = long-running dev server, flash blue then idle
# "task"    = normal command, stay busy until done
_tm_classify() {
  local cmd="$1"
  if [[ "$cmd" =~ (^|[[:space:]/])(start|dev|serve|watch|metro|docker-compose|docker\ compose|up|run\ dev|run\ start|run\ serve)([[:space:]]|$) ]]; then
    echo "service"
  else
    echo "task"
  fi
}

# --- Heartbeat (background, every 20s) ---
_tm_heartbeat() {
  while true; do
    curl -s --max-time 2 "${_TM_URL}/heartbeat?pid=$$&cwd=$(pwd)" > /dev/null 2>&1
    sleep 20
  done
}

# Start heartbeat only once per shell session
if [[ -z "$_TM_HEARTBEAT_PID" ]]; then
  _tm_heartbeat &!
  _TM_HEARTBEAT_PID=$!
  trap "kill $_TM_HEARTBEAT_PID 2>/dev/null" EXIT
fi

# --- Hooks ---
_tm_preexec() {
  # Claude Code has its own hooks — skip entirely
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
