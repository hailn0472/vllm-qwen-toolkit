#!/usr/bin/env bash
# Bước 7: cài Docker Engine + Docker Compose v2 (gói của Ubuntu) để chạy LibreChat.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_config
source "$TOOLKIT_DIR/lib/librechat.sh"

log_step "Docker"

SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

if command -v docker >/dev/null 2>&1 && docker_ready; then
  log_ok "$(docker --version)"
  log_ok "$(docker_cmd compose version)"
else
  pkgs=()
  command -v docker >/dev/null 2>&1 || pkgs+=(docker.io)
  docker compose version >/dev/null 2>&1 || pkgs+=(docker-compose-v2)
  command -v apt-get >/dev/null 2>&1 || die "Không có apt-get. Hãy tự cài Docker: https://docs.docker.com/engine/install/"
  log_info "Cần cài: ${pkgs[*]}"
  confirm "Cài Docker bằng sudo apt-get?" \
    || die "Đã huỷ. Tự cài bằng: sudo apt-get install -y ${pkgs[*]}"
  $SUDO apt-get update
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  $SUDO systemctl enable --now docker
  docker_ready || die "Cài xong nhưng 'docker compose' vẫn không chạy được"
  log_ok "$(docker --version)"
fi

# Cho user chạy docker không cần sudo (có hiệu lực sau khi đăng nhập lại)
if [[ $EUID -ne 0 ]] && ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  $SUDO usermod -aG docker "$USER"
  log_warn "Đã thêm $USER vào nhóm docker — đăng xuất/đăng nhập lại để dùng docker không cần sudo."
  log_info "Trong lúc chờ, toolkit tự dùng sudo docker."
fi
