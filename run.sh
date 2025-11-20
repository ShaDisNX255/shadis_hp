#!/usr/bin/env bash
# Minimal self-detaching server runner (no watcher)

set -u

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

SERVER="${SERVER:-$DIR/net_battle_server}"
PORT="${PORT:-3000}"

LOG="$DIR/logs.txt"
PIDFILE="$DIR/server.pid"

have_pid() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

# Optional line buffering (harmless if stdbuf missing)
stdbuf_wrap() {
  if command -v stdbuf >/dev/null 2>&1; then
    echo "stdbuf -oL -eL $*"
  else
    echo "$*"
  fi
}

start_server() {
  if [ -f "$PIDFILE" ] && have_pid "$(cat "$PIDFILE" 2>/dev/null)"; then
    echo "Server already running (pid $(cat "$PIDFILE"))."
    return 0
  fi

  # Overwrite logs each start (like 'tee' without -a). Remove this line to append instead.
  : > "$LOG"

  CMD=$(stdbuf_wrap "\"$SERVER\" -p \"$PORT\"")
  # Detach fully, write all output to logs.txt
  nohup bash -lc "$CMD >> \"$LOG\" 2>&1" >/dev/null 2>&1 &
  echo $! > "$PIDFILE"
  echo "Server started (pid $(cat "$PIDFILE"))."
  echo "Logs → $LOG"
}

stop_server() {
  if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" 2>/dev/null || true)"
    if have_pid "$PID"; then
      kill "$PID" 2>/dev/null || true
      for _ in 1 2 3; do have_pid "$PID" || break; sleep 0.3; done
      have_pid "$PID" && kill -9 "$PID" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
    echo "Server stopped."
  else
    echo "No PID file; server may not be running."
  fi
}

status_server() {
  if [ -f "$PIDFILE" ] && have_pid "$(cat "$PIDFILE" 2>/dev/null)"; then
    echo "Server: running (pid $(cat "$PIDFILE"))"
  else
    echo "Server: stopped"
  fi
}

case "${1:-}" in
  start|--daemon) start_server ;;
  stop)           stop_server ;;
  restart)        stop_server; start_server ;;
  status)         status_server ;;
  *)
    # Self-detach so you can just run ./run.sh and get your prompt back
    nohup bash "$0" start >/dev/null 2>&1 &
    echo "Starting server in background. Logs → $LOG"
    ;;
esac
