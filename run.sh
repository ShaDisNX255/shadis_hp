#!/usr/bin/env bash
# Minimal self-detaching server runner (correct PID handling + group kill)

set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

SERVER="${SERVER:-$DIR/net_battle_server}"
PORT="${PORT:-3000}"

LOG="$DIR/logs.txt"
PIDFILE="$DIR/server.pid"

have_pid() { local p="${1:-}"; [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null; }

start_server() {
  if [[ -f "$PIDFILE" ]] && have_pid "$(cat "$PIDFILE" 2>/dev/null || true)"; then
    echo "Server already running (pid $(cat "$PIDFILE"))."
    return 0
  fi

  # Overwrite logs each start (remove this line if you prefer to append)
  : > "$LOG"

  # Build the command: use stdbuf if present to keep line-flushed logs
  if command -v stdbuf >/dev/null 2>&1; then
    CMD=(stdbuf -oL -eL "$SERVER" -p "$PORT")
  else
    CMD=("$SERVER" -p "$PORT")
  fi

  # Detach fully, record the *server's* PID.
  # If 'setsid' exists, put it in its own session so we can kill the whole group later.
  if command -v setsid >/dev/null 2>&1; then
    nohup setsid "${CMD[@]}" 2>&1 | sed -u 's/\x1b\[[0-9;]*m//g' >> "$LOG" &
  else
    nohup "${CMD[@]}" 2>&1 | sed -u 's/\x1b\[[0-9;]*m//g' >> "$LOG" &
  fi
  echo $! > "$PIDFILE"

  echo "Server started (pid $(cat "$PIDFILE"))."
  echo "Logs → $LOG"
}

stop_server() {
  if [[ ! -f "$PIDFILE" ]]; then
    echo "No PID file; server may not be running."
    return 0
  fi

  local pid
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if ! have_pid "$pid"; then
    echo "PID $pid not running; cleaning up pidfile."
    rm -f "$PIDFILE"
    return 0
  fi

  # Try to terminate the entire process group first (covers any children),
  # then the main pid as a fallback. Negative PID = process group.
  kill -TERM -"${pid}" 2>/dev/null || true
  kill -TERM  "${pid}" 2>/dev/null || true

  for _ in {1..10}; do
    have_pid "$pid" || break
    sleep 0.3
  done

  if have_pid "$pid"; then
    echo "Force killing server (pid $pid)..."
    kill -KILL -"${pid}" 2>/dev/null || true
    kill -KILL  "${pid}" 2>/dev/null || true
    for _ in {1..10}; do
      have_pid "$pid" || break
      sleep 0.2
    done
  fi

  rm -f "$PIDFILE"
  echo "Server stopped."
}

status_server() {
  if [[ -f "$PIDFILE" ]]; then
    local pid; pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if have_pid "$pid"; then
      echo "Server: running (pid $pid)"
    else
      echo "Server: stopped (stale pidfile: $pid)"
    fi
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
