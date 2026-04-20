# --- snor-oh Terminal Mirror (Fish) ---
# Add to fish config:  source /path/to/terminal-mirror.fish
#
# Presence is event-driven: POST /session-start on source, /session-end on
# fish_exit. snor-oh verifies PID liveness via kill(0) every 2s.

set -g _TM_URL "http://127.0.0.1:1234"
set -g _TM_SESSIONS_DIR "$HOME/.snor-oh/sessions"

function _tm_urlenc
    string replace -a ' ' '%20' -- $argv[1]
end

function _tm_is_claude
    set -l first_word (string split ' ' -- $argv[1])[1]
    test "$first_word" = "claude"; and return 0
    set -l resolved (type -p "$first_word" 2>/dev/null)
    string match -q '*claude*' -- "$resolved"; and return 0
    return 1
end

function _tm_classify
    set -l cmd "$argv[1]"
    if string match -rq '(^|\s|/)(start|dev|serve|watch|metro|docker-compose|docker compose|up)(\s|$)' -- "$cmd"
        echo "service"
    else
        echo "task"
    end
end

function _tm_session_start
    mkdir -p "$_TM_SESSIONS_DIR"
    set -l lstart (ps -o lstart= -p $fish_pid | string trim)
    set -l pwd_now (pwd)
    printf '{"pid":%d,"cwd":"%s","kind":"shell","started_at":"%s"}\n' \
        $fish_pid $pwd_now $lstart > "$_TM_SESSIONS_DIR/$fish_pid.json"
    curl -s --max-time 2 \
        "$_TM_URL/session-start?pid=$fish_pid&cwd="(_tm_urlenc $pwd_now)"&kind=shell&started_at="(_tm_urlenc $lstart) \
        >/dev/null 2>&1 &
    disown
end

function _tm_session_end --on-event fish_exit
    rm -f "$_TM_SESSIONS_DIR/$fish_pid.json" 2>/dev/null
    curl -s --max-time 1 "$_TM_URL/session-end?pid=$fish_pid" >/dev/null 2>&1
end

if not set -q _TM_REGISTERED
    set -g _TM_REGISTERED 1
    _tm_session_start
end

function _tm_preexec --on-event fish_preexec
    set -l cmd "$argv[1]"

    _tm_is_claude "$cmd"; and return

    set -l cmd_type (_tm_classify "$cmd")
    curl -s --max-time 1 "$_TM_URL/status?pid=$fish_pid&state=busy&type=$cmd_type&cwd="(pwd) >/dev/null 2>&1 &
    disown
end

function _tm_postexec --on-event fish_postexec
    curl -s --max-time 1 "$_TM_URL/status?pid=$fish_pid&state=idle&cwd="(pwd) >/dev/null 2>&1 &
    disown
end
