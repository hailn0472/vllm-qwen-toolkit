#!/usr/bin/env bash
# Bật/tắt vLLM server chạy nền (dùng chung cho menu.sh, start.sh, stop.sh).
# Chỉ source sau khi đã source lib/common.sh và gọi load_config.

SERVER_PID_FILE="$INSTALL_DIR/server.pid"
SERVER_LOG="$LOG_DIR/server.log"

local_host() { [[ "$HOST" == 0.0.0.0 ]] && echo 127.0.0.1 || echo "$HOST"; }

server_pid() {
  local pid
  [[ -f "$SERVER_PID_FILE" ]] || return 1
  pid="$(<"$SERVER_PID_FILE")"
  kill -0 "$pid" 2>/dev/null || { rm -f "$SERVER_PID_FILE"; return 1; }
  echo "$pid"
}

server_ready() {
  [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://$(local_host):$PORT/health" 2>/dev/null)" == 200 ]]
}

# Chờ server load xong model. Ctrl+C chỉ thôi chờ, server vẫn chạy nền.
wait_server_ready() {
  local pid="$1" waited=0 stop=0 last old_trap
  old_trap="$(trap -p INT)"
  log_info "Đang load model... (Ctrl+C để thôi chờ, server vẫn chạy nền)"
  trap 'stop=1' INT
  while (( stop == 0 )); do
    if ! kill -0 "$pid" 2>/dev/null; then
      eval "${old_trap:-trap - INT}"
      echo
      log_fail "Server đã dừng trong lúc khởi động. 30 dòng log cuối ($SERVER_LOG):"
      tail -n 30 "$SERVER_LOG"
      rm -f "$SERVER_PID_FILE"
      return 1
    fi
    if server_ready; then
      eval "${old_trap:-trap - INT}"
      echo
      log_ok "Server sẵn sàng sau ${waited}s — http://$(local_host):$PORT/v1 (model: $SERVED_MODEL_NAME)"
      return 0
    fi
    last="$(tail -n 1 "$SERVER_LOG" 2>/dev/null | cut -c1-90)"
    printf '\r\033[K       %4ds | %s' "$waited" "$last"
    sleep 2
    waited=$((waited + 2))
  done
  eval "${old_trap:-trap - INT}"
  echo
  log_info "Thôi chờ. Xem tiến trình: tail -f $SERVER_LOG"
  return 1
}

# start_server_bg [tham số thêm cho vllm serve...]
start_server_bg() {
  if server_pid >/dev/null || server_ready; then
    log_ok "vLLM server đã chạy sẵn ở cổng $PORT"
    return 0
  fi
  mkdir -p "$LOG_DIR"
  # setsid: tách server khỏi terminal hiện tại, có process group riêng để dừng gọn
  setsid bash "$TOOLKIT_DIR/serve.sh" "$@" > "$SERVER_LOG" 2>&1 < /dev/null &
  echo $! > "$SERVER_PID_FILE"
  log_ok "Đã bật vLLM server nền (PID $!). Log: $SERVER_LOG"
  wait_server_ready "$!"
}

stop_server() {
  local pid i
  if ! pid="$(server_pid)"; then
    if server_ready; then
      log_warn "vLLM server đang chạy nhưng không do toolkit bật nền — dừng nó ở terminal đã chạy serve.sh"
    else
      log_info "vLLM server không chạy"
    fi
    return 0
  fi
  log_info "Đang dừng vLLM server (PID $pid)..."
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
  for i in {1..30}; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    log_warn "Server không tự dừng, buộc dừng (SIGKILL)"
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
  fi
  rm -f "$SERVER_PID_FILE"
  log_ok "Đã dừng vLLM server"
}
