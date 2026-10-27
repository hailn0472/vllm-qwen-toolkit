#!/usr/bin/env bash
# Bước 1: kiểm tra và cài gói hệ thống cần thiết qua apt.
#   curl  : tải uv, kiểm tra mạng
#   gcc   : Triton (dùng bởi vLLM) biên dịch kernel lúc chạy, bắt buộc có C compiler
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_config

log_step "Gói hệ thống"

declare -A CMD_TO_PKG=( [curl]=curl [gcc]=build-essential [g++]=build-essential [make]=build-essential )
missing=()
for cmd in curl gcc g++ make; do
  if command -v "$cmd" >/dev/null 2>&1; then
    log_ok "$cmd: $(command -v "$cmd")"
  else
    log_warn "Thiếu lệnh: $cmd"
    missing+=("${CMD_TO_PKG[$cmd]}")
  fi
done
if [[ ! -f /etc/ssl/certs/ca-certificates.crt ]]; then
  log_warn "Thiếu chứng chỉ CA"
  missing+=(ca-certificates)
fi

if [[ ${#missing[@]} -eq 0 ]]; then
  log_ok "Đủ gói hệ thống"
  exit 0
fi

mapfile -t missing < <(printf '%s\n' "${missing[@]}" | sort -u)
command -v apt-get >/dev/null 2>&1 || die "Không có apt-get. Hãy tự cài: ${missing[*]}"

log_info "Cần cài: ${missing[*]}"
confirm "Cài các gói trên bằng sudo apt-get?" \
  || die "Đã huỷ. Tự cài bằng: sudo apt-get install -y ${missing[*]}"

SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"
$SUDO apt-get update
$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
log_ok "Đã cài: ${missing[*]}"
