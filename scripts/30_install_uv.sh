#!/usr/bin/env bash
# Bước 3: cài hoặc cập nhật uv (https://docs.astral.sh/uv/).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_config

log_step "uv"

install_uv() {
  log_info "Cài uv bằng installer chính thức (vào ~/.local/bin)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  hash -r
}

if command -v uv >/dev/null 2>&1; then
  uv_ver="$(uv --version | awk '{print $2}')"
  if version_ge "$uv_ver" "$MIN_UV_VERSION"; then
    log_ok "uv $uv_ver đã sẵn sàng"
    exit 0
  fi
  log_info "uv $uv_ver cũ, đang cập nhật..."
  # self update chỉ chạy được nếu uv cài bằng installer chính thức; nếu không thì cài bản mới
  uv self update || install_uv
else
  install_uv
fi

command -v uv >/dev/null 2>&1 || die "Cài uv thất bại"
uv_ver="$(uv --version | awk '{print $2}')"
version_ge "$uv_ver" "$MIN_UV_VERSION" \
  || die "uv $uv_ver vẫn < $MIN_UV_VERSION (uv cũ khác trong PATH: $(command -v uv)?)"
log_ok "uv $uv_ver ($(command -v uv))"
