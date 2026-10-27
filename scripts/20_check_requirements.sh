#!/usr/bin/env bash
# Bước 2: kiểm tra yêu cầu trước khi cài. Thoát mã 1 nếu có lỗi [FAIL].
# [WARN] chỉ là cảnh báo, không chặn việc cài đặt.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_config

FAILS=0
WARNS=0
pass() { log_ok "$*"; }
warn() { log_warn "$*"; WARNS=$((WARNS + 1)); }
fail() { log_fail "$*"; FAILS=$((FAILS + 1)); }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; echo "${s%"${s##*[![:space:]]}"}"; }

echo "${C_BOLD}Profile:${C_RESET} $PROFILE | ${C_BOLD}Model:${C_RESET} $MODEL_ID"
echo "${C_BOLD}Thư mục cài:${C_RESET} $INSTALL_DIR"

cuda_drv=""   # CUDA tối đa driver hỗ trợ (đọc ở mục GPU)
min_cc=""     # compute capability thấp nhất trong các GPU

# -----------------------------------------------------------------------------
log_step "Hệ điều hành"
if [[ -r /etc/os-release ]]; then
  os_id="$(. /etc/os-release && echo "${ID:-}")"
  os_ver="$(. /etc/os-release && echo "${VERSION_ID:-0}")"
  os_name="$(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")"
  if [[ "$os_id" == ubuntu ]]; then
    if version_ge "$os_ver" "22.04"; then pass "$os_name"; else warn "$os_name đã cũ, khuyến nghị >= 22.04"; fi
  else
    warn "$os_name — toolkit viết cho Ubuntu, có thể vẫn chạy được"
  fi
else
  warn "Không đọc được /etc/os-release"
fi

arch="$(uname -m)"
case "$arch" in
  x86_64)  pass "Kiến trúc CPU: $arch" ;;
  aarch64) warn "Kiến trúc CPU: $arch — vLLM wheel cho ARM có thể hạn chế" ;;
  *)       fail "Kiến trúc CPU không hỗ trợ: $arch" ;;
esac
pass "Kernel: $(uname -r)"

# -----------------------------------------------------------------------------
log_step "GPU NVIDIA / Driver / CUDA"
if ! command -v nvidia-smi >/dev/null 2>&1; then
  fail "Không có nvidia-smi → chưa cài driver NVIDIA"
  log_info "Blackwell (RTX PRO 6000) cần driver bản -open, ví dụ:"
  log_info "  sudo ubuntu-drivers install   hoặc   sudo apt install nvidia-driver-580-open"
  log_info "  rồi reboot"
  if lsmod 2>/dev/null | grep -q '^nouveau'; then
    fail "Driver nouveau đang chạy — cần thay bằng driver NVIDIA"
  fi
elif ! smi_out="$(nvidia-smi 2>&1)"; then
  fail "nvidia-smi báo lỗi (driver chưa load? cần reboot? Secure Boot chặn module?):"
  log_info "$(echo "$smi_out" | head -n 3)"
else
  driver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d ' ')"
  if version_ge "$driver" "$MIN_DRIVER_VERSION"; then
    pass "Driver NVIDIA: $driver (>= $MIN_DRIVER_VERSION)"
  else
    fail "Driver NVIDIA $driver < $MIN_DRIVER_VERSION — Blackwell cần driver mới hơn"
  fi

  # Driver cũ in "CUDA Version: 12.8", driver mới in "CUDA UMD Version: 13.4"
  cuda_drv="$(echo "$smi_out" | grep -oE 'CUDA (UMD )?Version: *[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+$' | head -n1)"
  if [[ -z "$cuda_drv" ]]; then
    warn "Không đọc được CUDA Version từ nvidia-smi"
  elif version_ge "$cuda_drv" "$MIN_DRIVER_CUDA_VERSION"; then
    pass "CUDA (driver hỗ trợ tối đa): $cuda_drv (>= $MIN_DRIVER_CUDA_VERSION)"
  else
    fail "Driver chỉ hỗ trợ CUDA $cuda_drv < $MIN_DRIVER_CUDA_VERSION — cần nâng cấp driver"
  fi

  # Có driver cũ không hỗ trợ trường compute_cap -> fallback
  gpu_query="$(nvidia-smi --query-gpu=index,name,memory.total,memory.used,compute_cap \
                --format=csv,noheader,nounits 2>/dev/null)" \
    || gpu_query="$(nvidia-smi --query-gpu=index,name,memory.total,memory.used \
                --format=csv,noheader,nounits)"

  max_vram_gb=0
  while IFS=, read -r idx name mem_total mem_used cc; do
    idx="$(trim "$idx")"; name="$(trim "$name")"
    mem_total="$(trim "$mem_total")"; mem_used="$(trim "$mem_used")"; cc="$(trim "${cc:-?}")"
    total_gb=$((mem_total / 1024))
    used_gb=$((mem_used / 1024))
    (( total_gb > max_vram_gb )) && max_vram_gb=$total_gb
    pass "GPU $idx: $name | VRAM ${total_gb} GB (đang dùng ${used_gb} GB) | compute capability $cc"
    if [[ "$cc" =~ ^[0-9]+\.[0-9]+$ ]] && { [[ -z "$min_cc" ]] || ! version_ge "$cc" "$min_cc"; }; then
      min_cc="$cc"
    fi

    if [[ "$cc" =~ ^[0-9]+\.[0-9]+$ ]] && version_ge "$cc" "12.0"; then
      log_info "→ Blackwell (sm_${cc/./}): cần PyTorch build CUDA >= 12.8 (uv --torch-backend=auto sẽ tự chọn)"
    fi
    # vLLM chỉ khởi động nếu VRAM trống >= GPU_MEMORY_UTILIZATION * tổng VRAM
    max_used=$(awk -v t="$mem_total" -v u="$GPU_MEMORY_UTILIZATION" 'BEGIN{print int(t*(1-u))}')
    if (( mem_used > max_used )); then
      warn "GPU $idx đang bị chiếm ${used_gb} GB — vLLM với gpu_memory_utilization=$GPU_MEMORY_UTILIZATION có thể không khởi động được"
      log_info "Xem process: nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv"
    fi
  done <<< "$gpu_query"

  if (( max_vram_gb >= MIN_VRAM_GB )); then
    pass "VRAM đủ cho $MODEL_ID (cần >= ${MIN_VRAM_GB} GB)"
  else
    fail "VRAM ${max_vram_gb} GB < ${MIN_VRAM_GB} GB cần cho $MODEL_ID"
  fi
fi

nvcc_bin="$(command -v nvcc 2>/dev/null || true)"
[[ -z "$nvcc_bin" && -x /usr/local/cuda/bin/nvcc ]] && nvcc_bin=/usr/local/cuda/bin/nvcc
if [[ -n "$nvcc_bin" ]]; then
  pass "CUDA Toolkit (nvcc): $("$nvcc_bin" --version | grep -oE 'release [0-9.]+' | cut -d' ' -f2) — không bắt buộc"
else
  log_info "Không có CUDA Toolkit (nvcc) — KHÔNG bắt buộc, wheel vLLM/PyTorch đã kèm CUDA runtime"
fi

# -----------------------------------------------------------------------------
log_step "Python"
sys_py="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || true)"
log_info "Python hệ thống: ${sys_py:-không có} (không dùng — uv sẽ cài Python riêng)"
if version_ge "$PYTHON_VERSION" "$SUPPORTED_PYTHON_MIN" && version_ge "$SUPPORTED_PYTHON_MAX" "$PYTHON_VERSION"; then
  pass "Python cho venv: $PYTHON_VERSION (vLLM hỗ trợ $SUPPORTED_PYTHON_MIN – $SUPPORTED_PYTHON_MAX)"
else
  fail "PYTHON_VERSION=$PYTHON_VERSION ngoài khoảng vLLM hỗ trợ ($SUPPORTED_PYTHON_MIN – $SUPPORTED_PYTHON_MAX)"
fi

if [[ -x "$VENV_DIR/bin/python" ]]; then
  venv_py="$("$VENV_DIR/bin/python" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || echo "?")"
  if [[ "$venv_py" == "$PYTHON_VERSION"* ]]; then
    pass "venv đã có: $VENV_DIR (Python $venv_py)"
  else
    warn "venv hiện có dùng Python $venv_py khác $PYTHON_VERSION — sẽ được tạo lại"
  fi
  vllm_ver="$("$VENV_DIR/bin/python" -c 'import importlib.metadata as m; print(m.version("vllm"))' 2>/dev/null || true)"
  [[ -n "$vllm_ver" ]] && log_info "vLLM đã cài trong venv: $vllm_ver"

  # PyTorch build CUDA X cần driver hỗ trợ CUDA >= X, và phải có kernel (sm_XY) cho GPU này.
  # Lệch -> lỗi lúc chạy "no kernel image" / "driver too old". Sửa bằng cách cài lại venv nên chỉ WARN
  # (FAIL sẽ chặn install.sh trước bước cài lại venv).
  torch_info="$("$VENV_DIR/bin/python" -c 'import torch; print(torch.version.cuda or "", " ".join(torch.cuda.get_arch_list()))' 2>/dev/null || true)"
  torch_cuda="${torch_info%% *}"
  torch_archs=" ${torch_info#* } "
  if [[ -z "$torch_info" ]]; then
    log_info "Chưa có PyTorch trong venv — bỏ qua kiểm tra CUDA của PyTorch"
  elif [[ -z "$torch_cuda" ]]; then
    warn "PyTorch trong venv là bản CPU (không có CUDA) — cài lại: bash install.sh --recreate-venv"
  else
    if [[ -z "$cuda_drv" ]]; then
      log_info "PyTorch build CUDA $torch_cuda (không đọc được CUDA của driver để so sánh)"
    elif version_ge "$cuda_drv" "$torch_cuda"; then
      pass "PyTorch build CUDA $torch_cuda — driver hỗ trợ tới $cuda_drv"
    else
      warn "PyTorch build CUDA $torch_cuda > CUDA driver hỗ trợ ($cuda_drv) — nâng driver, hoặc cài torch hợp driver:"
      log_info "TORCH_BACKEND=cu${cuda_drv/./} bash install.sh --recreate-venv   (vd cu128, cu129, cu130)"
    fi
    if [[ -n "$min_cc" ]]; then
      sm="sm_${min_cc/./}"
      if [[ "$torch_archs" == *" $sm "* ]]; then
        pass "PyTorch có kernel cho GPU ($sm)"
      else
        warn "PyTorch không có kernel $sm cho GPU (có:$torch_archs) — sẽ lỗi 'no kernel image'"
        log_info "Cài lại với backend khác: TORCH_BACKEND=cu128 bash install.sh --recreate-venv (hoặc cu130)"
      fi
    fi
  fi
fi

# -----------------------------------------------------------------------------
log_step "uv"
if command -v uv >/dev/null 2>&1; then
  uv_ver="$(uv --version | awk '{print $2}')"
  if version_ge "$uv_ver" "$MIN_UV_VERSION"; then
    pass "uv $uv_ver (>= $MIN_UV_VERSION)"
  else
    warn "uv $uv_ver < $MIN_UV_VERSION — sẽ tự cập nhật"
  fi
else
  warn "Chưa có uv — sẽ tự cài vào ~/.local/bin"
fi

# -----------------------------------------------------------------------------
log_step "Trình biên dịch C (Triton cần lúc chạy)"
if command -v gcc >/dev/null 2>&1; then
  pass "gcc $(gcc -dumpfullversion 2>/dev/null || gcc -dumpversion)"
else
  fail "Thiếu gcc — cài: sudo apt-get install -y build-essential"
fi

# -----------------------------------------------------------------------------
log_step "Ổ đĩa & RAM"
target="$INSTALL_DIR"
while [[ ! -e "$target" ]]; do target="$(dirname "$target")"; done
fstype="$(findmnt -n -o FSTYPE --target "$target" 2>/dev/null || df -PT "$target" | awk 'NR==2{print $2}')"
case "$fstype" in
  vfat|exfat|msdos|ntfs|ntfs3|fuseblk)
    fail "INSTALL_DIR ($INSTALL_DIR) nằm trên $fstype (USB?) — không dùng được cho venv"
    log_info "Đặt INSTALL_DIR trên ổ ext4/xfs, ví dụ: INSTALL_DIR=\$HOME/vllm-qwen bash install.sh" ;;
  *) pass "Filesystem tại $target: $fstype" ;;
esac

avail_gb="$(df -Pk "$target" | awk 'NR==2{print int($4/1024/1024)}')"
need_gb=0
[[ -x "$VENV_DIR/bin/vllm" ]] || need_gb=$((need_gb + VENV_DISK_GB))
model_downloaded || need_gb=$((need_gb + MIN_DISK_GB))
if (( avail_gb >= need_gb )); then
  pass "Ổ đĩa trống: ${avail_gb} GB (cần ~${need_gb} GB)"
else
  fail "Ổ đĩa trống ${avail_gb} GB < ~${need_gb} GB cần (venv + model)"
fi

ram_gb="$(awk '/^MemTotal/{print int($2/1024/1024)}' /proc/meminfo)"
if (( ram_gb >= MIN_RAM_GB )); then
  pass "RAM: ${ram_gb} GB"
else
  warn "RAM ${ram_gb} GB < ${MIN_RAM_GB} GB khuyến nghị — load model có thể chậm/thiếu"
fi

# -----------------------------------------------------------------------------
log_step "Kết nối mạng"
if ! command -v curl >/dev/null 2>&1; then
  fail "Thiếu curl — không kiểm tra được mạng"
else
  if curl -sS -o /dev/null --max-time 15 https://pypi.org/simple/vllm/; then
    pass "Kết nối PyPI"
  elif [[ -x "$VENV_DIR/bin/vllm" ]]; then
    warn "Không kết nối được PyPI (vLLM đã cài sẵn nên vẫn có thể tiếp tục)"
  else
    fail "Không kết nối được PyPI — cần Internet để cài vLLM"
  fi

  if model_downloaded; then
    pass "Model đã có sẵn tại $MODEL_DIR — bỏ qua kiểm tra Hugging Face"
  elif [[ "${SKIP_MODEL:-0}" == 1 ]]; then
    log_info "Bỏ qua kiểm tra Hugging Face (--skip-model)"
  else
    hf_url="${HF_ENDPOINT:-https://huggingface.co}"
    auth=()
    [[ -n "$HF_TOKEN" ]] && auth=(-H "Authorization: Bearer $HF_TOKEN")
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "${auth[@]}" "$hf_url/api/models/$MODEL_ID" 2>/dev/null)"
    case "$code" in
      200)     pass "Hugging Face: tìm thấy $MODEL_ID" ;;
      401|403) fail "Hugging Face trả $code cho $MODEL_ID — model gated/private hoặc sai tên. Kiểm tra tên & đặt HF_TOKEN" ;;
      404)     fail "Hugging Face: không tồn tại $MODEL_ID" ;;
      000|"")  fail "Không kết nối được $hf_url (thử HF_ENDPOINT mirror?)" ;;
      *)       warn "Hugging Face trả mã HTTP $code cho $MODEL_ID" ;;
    esac
  fi
fi

# -----------------------------------------------------------------------------
log_step "Tương thích model ($MODEL_ID)"
# Đọc config.json: từ thư mục model nếu đã tải, không thì lấy từ Hugging Face
cfg_file=""
if [[ -f "$MODEL_DIR/config.json" ]]; then
  cfg_file="$MODEL_DIR/config.json"
elif [[ "${SKIP_MODEL:-0}" != 1 ]] && command -v curl >/dev/null 2>&1; then
  cfg_file="$(mktemp)"
  trap 'rm -f "$cfg_file"' EXIT
  auth=()
  [[ -n "$HF_TOKEN" ]] && auth=(-H "Authorization: Bearer $HF_TOKEN")
  curl -sSfL --max-time 15 "${auth[@]}" -o "$cfg_file" \
    "${HF_ENDPOINT:-https://huggingface.co}/$MODEL_ID/resolve/main/config.json" 2>/dev/null || cfg_file=""
fi

py_bin="python3"
[[ -x "$VENV_DIR/bin/python" ]] && py_bin="$VENV_DIR/bin/python"

# In 2 dòng: các kiến trúc trong "architectures", và kiểu lượng tử hoá (fp8, fp4, awq, gptq...)
read_model_config='
import json, sys
cfg = json.load(open(sys.argv[1]))
q = cfg.get("quantization_config") or cfg.get("text_config", {}).get("quantization_config") or {}
method = str(q.get("quant_method", "")).lower()
if "fp4" in json.dumps(q).lower():   # NVFP4/MXFP4 có thể nằm trong compressed-tensors hoặc modelopt
    method = "fp4"
print(" ".join(cfg.get("architectures") or []))
print(method)
'
model_archs=""; quant=""
if [[ -n "$cfg_file" ]] && cfg_out="$("$py_bin" -c "$read_model_config" "$cfg_file" 2>/dev/null)"; then
  model_archs="$(sed -n 1p <<< "$cfg_out")"
  quant="$(sed -n 2p <<< "$cfg_out")"
  log_info "Kiến trúc: ${model_archs:-?} | lượng tử hoá: ${quant:-không (BF16/FP16)}"
else
  log_info "Không đọc được config.json của model — bỏ qua kiểm tra tương thích"
fi

# vLLM trong venv có hỗ trợ kiến trúc này không (WARN: sửa bằng cách cập nhật vLLM)
check_archs='
import sys
from vllm.model_executor.models import ModelRegistry
supported = set(ModelRegistry.get_supported_archs())
print(" ".join(a for a in sys.argv[1:] if a not in supported))
'
if [[ -n "$model_archs" ]]; then
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    log_info "Chưa có vLLM — sẽ kiểm tra hỗ trợ kiến trúc sau khi cài (chạy lại: bash check.sh)"
  elif unsupported="$("$VENV_DIR/bin/python" -c "$check_archs" $model_archs 2>/dev/null)"; then
    if [[ -z "$unsupported" ]]; then
      pass "vLLM ${vllm_ver:-} hỗ trợ kiến trúc $model_archs"
    else
      warn "vLLM ${vllm_ver:-} chưa hỗ trợ kiến trúc: $unsupported"
      log_info "Cập nhật vLLM: bash install.sh --recreate-venv  (hoặc thử thêm --model-impl transformers khi serve)"
    fi
  else
    warn "Không import được vLLM trong venv để kiểm tra kiến trúc — venv hỏng? Thử: bash install.sh --recreate-venv"
  fi
fi

# Compute capability: MIN_COMPUTE_CAP trong profile = yêu cầu cứng (FAIL);
# theo kiểu lượng tử hoá đọc từ config.json = khuyến nghị (WARN, vLLM thường có đường chạy thay thế chậm hơn).
if [[ -n "$min_cc" ]]; then
  if [[ -n "${MIN_COMPUTE_CAP:-}" ]]; then
    if version_ge "$min_cc" "$MIN_COMPUTE_CAP"; then
      pass "Compute capability $min_cc >= $MIN_COMPUTE_CAP (profile yêu cầu)"
    else
      fail "Compute capability $min_cc < $MIN_COMPUTE_CAP mà profile $PROFILE yêu cầu"
    fi
  fi
  case "$quant" in
    fp8) need_cc="8.9";  quant_name="FP8" ;;
    fp4) need_cc="10.0"; quant_name="FP4 (NVFP4/MXFP4)" ;;
    *)   need_cc="8.0";  quant_name="${quant:+${quant^^} + }BF16" ;;
  esac
  if version_ge "$min_cc" "$need_cc"; then
    pass "GPU (cc $min_cc) chạy gốc được $quant_name (cần >= $need_cc)"
  elif [[ "$need_cc" == 8.0 ]]; then
    warn "GPU cc $min_cc < 8.0 không có BF16 — vLLM sẽ chạy FP16 (thêm --dtype half nếu lỗi)"
  else
    warn "GPU cc $min_cc < $need_cc: $quant_name không chạy gốc — vLLM dùng kernel thay thế (Marlin) chậm hơn, hoặc báo lỗi. Nên chọn bản BF16/AWQ"
  fi
fi

# -----------------------------------------------------------------------------
log_step "Cổng server"
if command -v ss >/dev/null 2>&1; then
  if ss -ltnH "sport = :$PORT" 2>/dev/null | grep -q .; then
    warn "Cổng $PORT (vLLM) đang được dùng — đổi bằng PORT=xxxx khi chạy serve.sh"
  else
    pass "Cổng $PORT (vLLM) còn trống"
  fi
  if ss -ltnH "sport = :$LIBRECHAT_PORT" 2>/dev/null | grep -q .; then
    warn "Cổng $LIBRECHAT_PORT (LibreChat) đang được dùng — có thể LibreChat đã chạy, hoặc đổi LIBRECHAT_PORT"
  else
    pass "Cổng $LIBRECHAT_PORT (LibreChat) còn trống"
  fi
fi

# -----------------------------------------------------------------------------
log_step "Docker (cho LibreChat)"
if command -v docker >/dev/null 2>&1; then
  pass "$(docker --version)"
  docker compose version >/dev/null 2>&1 && pass "$(docker compose version)" \
    || warn "Thiếu Docker Compose v2 — toolkit sẽ cài gói docker-compose-v2"
else
  warn "Chưa có Docker — toolkit sẽ cài (gói docker.io + docker-compose-v2)"
fi

# -----------------------------------------------------------------------------
log_step "Kết quả kiểm tra"
if (( FAILS > 0 )); then
  log_fail "$FAILS lỗi, $WARNS cảnh báo — hãy sửa các mục [FAIL] trước khi cài"
  exit 1
fi
log_ok "Không có lỗi ($WARNS cảnh báo)"
