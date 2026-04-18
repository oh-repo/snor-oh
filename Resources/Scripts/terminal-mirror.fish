# --- snor-oh Terminal Mirror (Fish) ---
# Add to fish config:  source /path/to/terminal-mirror.fish

set -g _TM_URL "http://127.0.0.1:1234"

# --- Detect if a command is Claude Code ---
function _tm_is_claude
    set -l first_word (string split ' ' -- $argv[1])[1]
    test "$first_word" = "claude"; and return 0
    set -l resolved (type -p "$first_word" 2>/dev/null)
    string match -q '*claude*' -- "$resolved"; and return 0
    return 1
end

# --- Command categorization ---
function _tm_classify
    set -l cmd "$argv[1]"
    if string match -rq '(^|\s|/)(start|dev|serve|watch|metro|docker-compose|docker compose|up)(\s|$)' -- "$cmd"
        echo "service"
    else
        echo "task"
    end
end

# --- Heartbeat (background, every 20s) ---
function _tm_heartbeat
    while true
        curl -s --max-time 2 "$_TM_URL/heartbeat?pid=$fish_pid&cwd="(pwd) >/dev/null 2>&1
        sleep 20
    end
end

# Start heartbeat only once per shell session
if not set -q _TM_HEARTBEAT_STARTED
    set -g _TM_HEARTBEAT_STARTED 1
    _tm_heartbeat &
    disown
end

# --- Hooks ---
function _tm_preexec --on-event fish_preexec
    set -l cmd "$argv[1]"

    # Claude Code has its own hooks — skip entirely
    _tm_is_claude "$cmd"; and return

    set -l cmd_type (_tm_classify "$cmd")
    curl -s --max-time 1 "$_TM_URL/status?pid=$fish_pid&state=busy&type=$cmd_type&cwd="(pwd) >/dev/null 2>&1 &
    disown
end

function _tm_postexec --on-event fish_postexec
    curl -s --max-time 1 "$_TM_URL/status?pid=$fish_pid&state=idle&cwd="(pwd) >/dev/null 2>&1 &
    disown
end
