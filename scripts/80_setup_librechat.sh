#!/usr/bin/env bash
# Bước 8: chuẩn bị LibreChat trong $LIBRECHAT_DIR: docker-compose.yml, .env (khoá bí mật sinh 1 lần),
# librechat.yaml (trỏ tới vLLM theo profile), rồi tải sẵn image Docker.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_config
source "$TOOLKIT_DIR/lib/librechat.sh"

log_step "LibreChat → $LIBRECHAT_DIR"
docker_ready || die "Chưa có Docker — chạy trước: bash scripts/70_install_docker.sh"

# Tạo sẵn thư mục bind-mount với quyền của user (để Docker không tạo chúng bằng root)
mkdir -p "$LIBRECHAT_DIR"/{images,uploads,logs,data,data-node,meili_data_v1.35.1}
cp "$TOOLKIT_DIR/librechat/docker-compose.yml" "$LIBRECHAT_DIR/docker-compose.yml"

# Khoá bí mật chỉ sinh lần đầu: đổi CREDS_KEY/JWT về sau sẽ làm hỏng dữ liệu/phiên đăng nhập đã có
SECRETS="$LIBRECHAT_DIR/secrets.env"
if [[ ! -f "$SECRETS" ]]; then
  ( umask 077
    cat > "$SECRETS" <<EOF
CREDS_KEY=$(openssl rand -hex 32)
CREDS_IV=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)
MEILI_MASTER_KEY=$(openssl rand -hex 16)
EOF
  )
  log_ok "Đã sinh khoá bí mật: $SECRETS"
else
  log_ok "Dùng lại khoá bí mật có sẵn: $SECRETS"
fi

# .env được ghi lại mỗi lần chạy theo config.env (cổng, tiêu đề, cho phép đăng ký...)
( umask 077
  cat > "$LIBRECHAT_DIR/.env" <<EOF
# File sinh tự động bởi scripts/80_setup_librechat.sh — sửa config.env / config.local.env thay vì sửa ở đây
LIBRECHAT_IMAGE=$LIBRECHAT_IMAGE
LIBRECHAT_BIND=$LIBRECHAT_BIND
UID=$(id -u)
GID=$(id -g)
HOST=0.0.0.0
PORT=$LIBRECHAT_PORT
DOMAIN_CLIENT=$LIBRECHAT_URL
DOMAIN_SERVER=$LIBRECHAT_URL
NO_INDEX=true
APP_TITLE=$LIBRECHAT_TITLE

# Chỉ hiện endpoint custom (vLLM), ẩn OpenAI/Anthropic/Google...
ENDPOINTS=custom

SEARCH=true
MEILI_NO_ANALYTICS=true

ALLOW_EMAIL_LOGIN=true
ALLOW_REGISTRATION=$LIBRECHAT_ALLOW_REGISTRATION
ALLOW_SOCIAL_LOGIN=false
ALLOW_SOCIAL_REGISTRATION=false
ALLOW_UNVERIFIED_EMAIL_LOGIN=true
SESSION_EXPIRY=1000 * 60 * 60 * 24
REFRESH_TOKEN_EXPIRY=(1000 * 60 * 60 * 24) * 7

$(<"$SECRETS")
EOF
)
log_ok "Đã ghi $LIBRECHAT_DIR/.env"

render_librechat_yaml
log_ok "Đã ghi $LIBRECHAT_DIR/librechat.yaml (model: $SERVED_MODEL_NAME, vLLM cổng $PORT)"

log_step "Tải image Docker (lần đầu ~1–2 GB)"
lc_compose pull
log_ok "LibreChat sẵn sàng để bật: bash start.sh"
