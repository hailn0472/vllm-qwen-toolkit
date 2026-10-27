#!/usr/bin/env bash
# Hàm dùng chung cho LibreChat (Docker). Chỉ source sau khi đã source lib/common.sh và gọi load_config.

LIBRECHAT_URL="http://localhost:$LIBRECHAT_PORT"

# Lệnh docker: dùng trực tiếp nếu user đã vào nhóm docker, không thì qua sudo
# (vừa cài xong Docker phải đăng nhập lại mới có quyền nhóm docker).
docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

docker_ready() { command -v docker >/dev/null 2>&1 && docker_cmd compose version >/dev/null 2>&1; }

librechat_installed() { [[ -f "$LIBRECHAT_DIR/docker-compose.yml" && -f "$LIBRECHAT_DIR/.env" ]]; }

lc_compose() { docker_cmd compose --project-directory "$LIBRECHAT_DIR" -f "$LIBRECHAT_DIR/docker-compose.yml" "$@"; }

librechat_ready() {
  [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$LIBRECHAT_URL" 2>/dev/null)" == 200 ]]
}

# Ghi lại librechat.yaml theo profile đang dùng (tên model, cổng, API key của vLLM)
render_librechat_yaml() {
  local api_key="${API_KEY:-EMPTY}" thinking=false
  [[ "$ENABLE_THINKING" == true ]] && thinking=true
  sed -e "s|@VLLM_BASE_URL@|http://host.docker.internal:$PORT/v1|" \
      -e "s|@VLLM_API_KEY@|$api_key|" \
      -e "s|@MODEL@|$SERVED_MODEL_NAME|g" \
      -e "s|@ENABLE_THINKING@|$thinking|" \
      "$TOOLKIT_DIR/librechat/librechat.yaml.tmpl" > "$LIBRECHAT_DIR/librechat.yaml"
  chmod 600 "$LIBRECHAT_DIR/librechat.yaml"
}

# Bật LibreChat, chờ web lên (tối đa ~3 phút)
start_librechat() {
  librechat_installed || { log_fail "Chưa cài LibreChat — chạy: bash install.sh hoặc scripts/80_setup_librechat.sh"; return 1; }
  render_librechat_yaml
  lc_compose up -d || return 1
  local i
  log_info "Chờ LibreChat khởi động..."
  for i in $(seq 1 90); do
    librechat_ready && { log_ok "LibreChat sẵn sàng: $LIBRECHAT_URL"; return 0; }
    sleep 2
  done
  log_warn "LibreChat chưa trả lời sau 3 phút. Xem log: bash librechat.sh logs"
  return 1
}

stop_librechat() {
  librechat_installed && command -v docker >/dev/null 2>&1 || { log_info "LibreChat chưa cài"; return 0; }
  lc_compose down && log_ok "Đã dừng LibreChat"
}
