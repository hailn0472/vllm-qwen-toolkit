# vLLM + Qwen + LibreChat Toolkit (Ubuntu)

Bộ script cài tự động **vLLM** (chạy model), model **Qwen** và **LibreChat** (giao diện web chat giống ChatGPT) trên Ubuntu.

```
Trình duyệt ──► LibreChat :3080 (Docker) ──► vLLM :8000 /v1 (venv, GPU) ──► Qwen
```

Toolkit kiểm tra yêu cầu hệ thống, cài uv + venv Python + vLLM, tải model, chạy thử, rồi cài Docker + LibreChat.

## 0. Bắt đầu nhanh (từ đầu)

```bash
cd vllm-qwen-toolkit
bash check.sh --profile qwen3.5-0.8b          # 1. kiểm tra máy (không cài gì)
bash install.sh --profile qwen3.5-0.8b        # 2. cài tất cả (hỏi sudo để cài gcc, Docker)
bash start.sh                                 # 3. bật vLLM + LibreChat
# 4. mở http://localhost:3080 → Sign up → chọn endpoint "vLLM" → chat
bash stop.sh                                  # dừng tất cả
```

Chọn profile theo VRAM của GPU (GPU 4 GB → `qwen3.5-0.8b`, server lớn → `qwen3.5-4b` / `qwen3.8-27b`).
Profile chọn lúc cài được ghi nhớ, các lệnh sau không cần `--profile` nữa.

| Profile | Model | Dung lượng | Dùng cho |
|---|---|---|---|
| `qwen3.5-0.8b` | `Qwen/Qwen3.5-0.8B` | ~1.8 GB | GPU nhỏ (4 GB): test toàn bộ quy trình |
| `qwen3-0.6b` | `Qwen/Qwen3-0.6B` | ~1.5 GB | Dự phòng GPU nhỏ nếu vLLM chưa chạy được Qwen3.5 |
| `qwen3.5-4b` *(mặc định)* | `Qwen/Qwen3.5-4B` | ~9 GB | Chạy thử toolkit cho nhanh |
| `qwen3-4b-instruct` | `Qwen/Qwen3-4B-Instruct-2507` | ~8 GB | Dự phòng nếu bản vLLM đang cài chưa hỗ trợ kiến trúc Qwen3.5 |
| `qwen3.8-27b` | `Qwen/Qwen3.8-27B` | ~55 GB | Model chính |

---

## 1. Chép từ USB sang server

```bash
# USB thường được mount ở /media/$USER/<TÊN_USB>
cp -r /media/$USER/<TÊN_USB>/vllm-qwen-toolkit ~/
cd ~/vllm-qwen-toolkit
```

> Luôn chạy bằng `bash <script>.sh`. USB định dạng FAT32/exFAT không giữ quyền thực thi, nên `./install.sh` có thể báo *Permission denied*.
> Có thể chạy thẳng từ USB vì venv và model được cài vào `INSTALL_DIR` (mặc định `~/vllm-qwen`), không ghi lên USB.

## 2. Chạy menu

```bash
bash menu.sh
```

```
==================================================================
  vLLM + Qwen Toolkit
==================================================================
  Profile     : qwen3.5-4b (Qwen/Qwen3.5-4B)
  Thư mục cài : ~/vllm-qwen
  uv          : ✓ 0.11.21  → ~/.local/bin/uv
  vLLM        : ✓ 0.25.1  → ~/vllm-qwen/venv
  Weights     : ✓ đã tải 8.7G  → ~/vllm-qwen/models/Qwen3.5-4B
  vLLM server : tắt
  LibreChat   : tắt
------------------------------------------------------------------
 CÀI ĐẶT
   1) Kiểm tra yêu cầu hệ thống
   2) Cài gói hệ thống (curl, gcc...)
   3) Cài / cập nhật uv
   4) Tạo venv + cài vLLM
   5) Tải model (chọn từ danh sách Qwen trên Hugging Face)
   6) Chạy smoke test
   7) Cài tự động toàn bộ (1 → 6 + 16)
 SỬ DỤNG
   8) Chạy thử offline (code mẫu Python)
   9) Bật API server (chạy nền)
  10) Dừng API server
  11) Xem log server
  12) Chat với model qua API server
 KHÁC
  13) Đổi model (profile)
  14) Xem cấu hình & GPU
  15) Gỡ cài đặt
 WEB UI (LIBRECHAT)
  16) Cài Docker + LibreChat
  17) Bật vLLM + LibreChat
  18) Dừng LibreChat
  19) Xem log LibreChat
   0) Thoát
```

Lần đầu nên chạy lần lượt **1 → 2 → 3 → 4 → 5 → 6 → 16 → 17**, hoặc chọn **7** rồi **17**. Phần đầu menu luôn hiện trạng thái và **thư mục** của uv, vLLM (venv) và weights của model đang chọn. Mục **14** hiện đầy đủ các thư mục: uv cache, Python của uv, package vLLM, HF cache, log...

- **Mục 5**: chọn `1` để tải model của profile hiện tại, hoặc `2` để mở danh sách model Qwen lấy trực tiếp từ Hugging Face:

  ```
     #  Model                        Tham số    ~GB  Tải/30n  Ngày tạo    Vừa GPU Ghi chú
     5  Qwen/Qwen3.8-27B               27.8B   51.7     7.6M  2026-08-05     ✓    đa phương thức
     6  Qwen/Qwen3.5-4B                 4.7B    8.7     7.4M  2026-02-27     ✓    đa phương thức, ĐÃ TẢI
    13  Qwen/Qwen3.8-27B-FP8           27.8B   28.7     4.4M  2026-08-13     ✓    đa phương thức
    20  Qwen/Qwen3.8-Flash-Next         180B  335.3     3.2M  2026-08-24     ✗    đa phương thức
  Nhập SỐ để chọn | n/p: trang sau/trước | s <từ khoá>: lọc (vd: s 3.8 27b), s: bỏ lọc
  d/t/m: sắp xếp theo lượt tải/xu hướng/mới nhất | <org>/<repo>: nhập trực tiếp | q: quay lại
  ```

  - Danh sách chỉ giữ model sinh văn bản (kể cả đa phương thức). Embedding, TTS, ASR và các bản GGUF/MLX bị loại vì vLLM không chạy trực tiếp.
  - `~GB` được ước tính từ số tham số và kiểu dữ liệu. Cột `Vừa GPU` so dung lượng đó với VRAM thực tế của máy.
  - Có thể gõ thẳng tên repo của org khác, ví dụ `unsloth/Qwen3.8-27B-NVFP4`.
  - Chọn xong, toolkit tự tạo profile trong `~/vllm-qwen/profiles/`. `MAX_MODEL_LEN` được lấy theo `config.json` của model, tối đa 32768. Sau đó toolkit chuyển sang profile này và tải weights về `~/vllm-qwen/models/<tên>`. Repo của org khác Qwen sẽ lưu vào `models/<org>--<tên>` để tránh trùng tên.
- **Mục 8**: hỏi prompt, số token, thinking, rồi chạy `examples/offline_inference.py`.
- **Mục 9**: bật server chạy nền và chờ tới khi model load xong. Bấm Ctrl+C sẽ chỉ thôi chờ, server vẫn chạy. Log nằm ở `~/vllm-qwen/logs/server.log`.
- **Mục 12**: chat nhiều lượt với model. Trong khung chat có các lệnh `/think` (bật/tắt suy nghĩ), `/clear` (xoá lịch sử), `/exit` (thoát). Nếu server chưa bật, menu sẽ hỏi có bật luôn không.
- **Mục 13**: chuyển giữa các profile, gồm cả profile có sẵn và profile tự tạo ở mục 5. Danh sách cho biết model nào đã tải và dung lượng bao nhiêu. Toàn bộ menu sẽ theo profile vừa chọn.
- Nếu server nền đang chiếm VRAM, menu sẽ hỏi có dừng server không trước khi chạy test, smoke test hoặc cài lại.
- Bấm Ctrl+C trong một mục chỉ dừng lệnh đang chạy, không thoát menu. Log các bước cài được ghi vào `~/vllm-qwen/logs/menu-<ngày>.log`.

### Không dùng menu (chạy script)

```bash
bash check.sh        # chỉ kiểm tra, không cài gì
bash install.sh -y   # cài một lượt, không hỏi (hợp khi chạy qua SSH/automation)
```

Các bước cài đặt (tương ứng mục 1–6 của menu):

| Bước | Script | Việc làm |
|---|---|---|
| 1 | `scripts/10_system_deps.sh` | Kiểm tra `curl`, `gcc`, `make`; thiếu thì hỏi để `sudo apt-get install` |
| 2 | `scripts/20_check_requirements.sh` | Kiểm tra OS, driver NVIDIA, CUDA, VRAM, compute capability, Python, uv, ổ đĩa, RAM, mạng, model trên HF, cổng |
| 3 | `scripts/30_install_uv.sh` | Cài uv, hoặc cập nhật nếu cũ hơn `MIN_UV_VERSION` |
| 4 | `scripts/40_setup_venv.sh` | `uv venv` với Python 3.12 managed, rồi `uv pip install vllm --torch-backend=auto` |
| 5 | `scripts/50_download_model.sh` | Tải model về `~/vllm-qwen/models/<tên>` (tự tải tiếp nếu bị ngắt) |
| 6 | `scripts/60_smoke_test.sh` | Kiểm tra GPU trong PyTorch, rồi sinh thử văn bản bằng vLLM |
| 7 | `scripts/70_install_docker.sh` | Cài `docker.io` + `docker-compose-v2` (gói Ubuntu), thêm user vào nhóm `docker` |
| 8 | `scripts/80_setup_librechat.sh` | Tạo `~/vllm-qwen/librechat/` (compose, `.env` + khoá bí mật, `librechat.yaml`), tải image |

Bước nào lỗi thì script dừng ở bước đó. Chạy lại `install.sh` sẽ bỏ qua những phần đã xong. Log lưu tại `~/vllm-qwen/logs/`.

### Các mục được kiểm tra

- **[FAIL]** (chặn cài đặt): không có driver hoặc driver < 570, CUDA mà driver hỗ trợ < 12.8, VRAM không đủ cho profile, thiếu gcc, ổ đĩa không đủ, `INSTALL_DIR` nằm trên FAT/exFAT/NTFS, không vào được PyPI, model không có trên Hugging Face hoặc bị gated mà chưa có token.
- **[WARN]** (chỉ cảnh báo): chưa có uv hoặc uv cũ (toolkit sẽ tự cài), RAM < 32 GB, GPU đang bị process khác chiếm VRAM, cổng 8000/3080 đang bận, OS không phải Ubuntu, chưa có Docker.
- **Tương thích model** (theo profile đang chọn, đọc `config.json` của model từ thư mục đã tải hoặc từ Hugging Face):
  - PyTorch trong venv: bản CUDA của torch phải ≤ CUDA mà driver hỗ trợ, và torch phải có kernel `sm_XY` cho GPU. Lệch → **[WARN]** kèm lệnh cài lại (`TORCH_BACKEND=cuXXX bash install.sh --recreate-venv`).
  - vLLM trong venv có hỗ trợ kiến trúc model (`architectures` trong `config.json`) không. Chưa → **[WARN]**, cập nhật vLLM bằng `--recreate-venv`.
  - Compute capability theo kiểu lượng tử hoá: BF16 cần ≥ 8.0, FP8 ≥ 8.9, FP4 ≥ 10.0 → thiếu thì **[WARN]**. Profile đặt `MIN_COMPUTE_CAP` → thiếu thì **[FAIL]**.
  - Hai mục đầu chỉ WARN vì cách sửa là cài lại venv — FAIL sẽ chặn chính `install.sh` trước bước đó. Chưa có venv thì hai mục này được bỏ qua: cài xong chạy lại `bash check.sh`.
- Driver/CUDA tối thiểu (`MIN_DRIVER_VERSION`, `MIN_DRIVER_CUDA_VERSION` trong `config.env`) phụ thuộc GPU, không phụ thuộc model. Muốn biết server có chạy được model khác không: chạy trên server `bash check.sh --profile <tên>`.
- **Thông tin**: Python hệ thống, CUDA Toolkit `nvcc`. Cả hai **không bắt buộc**: uv tự tải Python riêng, còn wheel vLLM/PyTorch đã có sẵn CUDA runtime.

## 3. Chạy thử model bằng script (tương đương mục 8, 9, 12)

```bash
# Inference offline (không cần server): examples/offline_inference.py
bash test.sh
bash test.sh --prompt "Viết hàm Python sắp xếp nổi bọt" --max-tokens 1024
bash test.sh --thinking                       # bật chế độ suy nghĩ của Qwen

# API server tương thích OpenAI: terminal 1
bash serve.sh
# terminal 2: examples/openai_client.py (có stream)
bash chat.sh --prompt "Thủ đô của Việt Nam là gì?"
bash chat.sh --interactive                    # chat nhiều lượt
```

Server chạy tại `http://<ip-server>:8000/v1`, nên mọi client OpenAI đều gọi được:

```bash
curl http://127.0.0.1:8000/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"qwen3.5-4b","messages":[{"role":"user","content":"Xin chào"}]}'
```

Muốn dùng venv trực tiếp trong code của bạn:

```bash
source ~/vllm-qwen/venv/bin/activate
python examples/offline_inference.py --model ~/vllm-qwen/models/Qwen3.5-4B
```

## 3b. LibreChat (web UI)

```bash
bash start.sh                 # bật vLLM nền (chờ load model) rồi bật LibreChat
bash librechat.sh status      # trạng thái container
bash librechat.sh logs        # log LibreChat
bash librechat.sh restart     # khởi động lại (sinh lại librechat.yaml theo profile hiện tại)
bash librechat.sh update      # cập nhật cấu hình / image mới (sau khi sửa LIBRECHAT_IMAGE)
bash stop.sh                  # dừng LibreChat + vLLM (lịch sử chat vẫn giữ)
```

- Gồm 3 container: `librechat-api` (web), `librechat-mongodb` (lưu tài khoản, lịch sử chat), `librechat-meilisearch` (tìm kiếm hội thoại).
  Dữ liệu nằm trong `~/vllm-qwen/librechat/` (khoá bí mật trong `secrets.env` — đừng xoá, mất là hỏng dữ liệu đã mã hoá).
- LibreChat gọi vLLM qua `http://host.docker.internal:$PORT/v1`. Danh sách model lấy tự động từ vLLM, nên đổi profile chỉ cần `bash stop.sh && bash start.sh`.
- Tài khoản đăng ký đầu tiên là admin. Đăng ký xong có thể khoá đăng ký: `LIBRECHAT_ALLOW_REGISTRATION=false` trong `config.local.env`, rồi `bash librechat.sh update`.
- Truy cập từ máy khác: `http://<ip-máy>:3080`. Chỉ cho máy này: `LIBRECHAT_BIND=127.0.0.1`.
- Thinking của Qwen bật/tắt theo `ENABLE_THINKING` của profile (gửi `chat_template_kwargs.enable_thinking`).

## 4. Chuyển sang Qwen3.8-27B

Trong menu: chọn **13** → `qwen3.8-27b`, rồi **5** (tải model, ~55 GB) → **6** (smoke test) → **9** (bật server). venv và vLLM dùng lại được, không cần cài lại.

Hoặc dùng script:

```bash
bash install.sh --profile qwen3.8-27b    # dùng lại venv đã có, chỉ tải thêm model (~55 GB)
bash serve.sh                            # từ giờ mặc định dùng profile vừa cài
bash serve.sh --profile qwen3.5-4b       # muốn quay lại model 4B
```

Với 27B BF16 trên một card 96 GB: weights chiếm khoảng 55 GB, phần còn lại dành cho KV cache. `MAX_MODEL_LEN` mặc định là 32768. Có thể tăng dần (model hỗ trợ tới 262144), ví dụ `MAX_MODEL_LEN=131072 bash serve.sh`. Nếu vLLM báo không đủ bộ nhớ KV cache thì giảm giá trị này xuống.

## 5. Tuỳ chỉnh

Mọi giá trị trong `config.env` và `profiles/*.env` đều ghi đè được bằng biến môi trường, hoặc ghi vào file `config.local.env` (tạo mới, cùng thư mục với `config.env`):

```bash
# config.local.env
INSTALL_DIR=/data/vllm-qwen      # ổ data lớn
HF_TOKEN=hf_xxx                  # nếu model gated
VLLM_VERSION=0.25.1              # ghim phiên bản vLLM
API_KEY=my-secret                # bắt client gửi key
PORT=9000
```

Muốn thêm model khác: chép một file trong `profiles/`, sửa `MODEL_ID`, `SERVED_MODEL_NAME`, `MIN_VRAM_GB`, `MIN_DISK_GB`, rồi chạy `bash install.sh --profile <tên-file>`.

Biến tuỳ chọn trong profile:

| Biến | Ý nghĩa |
|---|---|
| `MIN_COMPUTE_CAP` | Compute capability tối thiểu bắt buộc (vd `8.9` cho FP8, `12.0` cho NVFP4 trên Blackwell) — thiếu thì check báo FAIL |
| `ENFORCE_EAGER=true` | Tắt CUDA graph: tiết kiệm VRAM, khởi động nhanh hơn |
| `LANGUAGE_MODEL_ONLY=true` | Model đa phương thức chỉ dùng text, không nạp vision encoder |
| `MAX_NUM_SEQS`, `MAX_NUM_BATCHED_TOKENS` | Giới hạn request song song / token mỗi bước — giảm khi thiếu VRAM |

## 6. Xử lý sự cố

| Triệu chứng | Cách xử lý |
|---|---|
| `$'\r': command not found` | File bị đổi sang CRLF khi chép qua Windows. Chạy: `find . -name '*.sh' -o -name '*.env' \| xargs sed -i 's/\r$//'` |
| Không có `nvidia-smi` | Cài driver bản **open** (Blackwell bắt buộc): `sudo ubuntu-drivers install` hoặc `sudo apt install nvidia-driver-580-open`, rồi reboot |
| `no kernel image is available for execution on the device` | Bản torch không có kernel sm_120. Chạy lại: `TORCH_BACKEND=cu128 bash install.sh --recreate-venv` (hoặc `cu130`) |
| vLLM chưa hỗ trợ kiến trúc model (`... not supported`) | Cài lại bản vLLM mới nhất bằng `bash install.sh --recreate-venv`, hoặc thử profile `qwen3-4b-instruct` |
| Treo máy hoặc lỗi khi *capturing CUDA graphs* | Thêm `--enforce-eager`: `bash serve.sh --enforce-eager`, `bash test.sh --enforce-eager`. Có báo cáo RTX PRO 6000 ổn định hơn khi khoá xung: `sudo nvidia-smi -lgc 0,2400` |
| `CUDA out of memory` / không đủ KV cache | Giảm `MAX_MODEL_LEN`, hoặc kiểm tra process khác đang chiếm GPU (`nvidia-smi`) |
| Hugging Face 401/403 | Model gated: chấp nhận license trên trang model rồi đặt `HF_TOKEN` |
| Tải model chậm hoặc bị chặn | Dùng mirror: `HF_ENDPOINT=https://hf-mirror.com bash install.sh` |
| GPU nhỏ (4–8 GB): `No available memory for the cache blocks` | Dùng profile `qwen3.5-0.8b`. Với model đa phương thức, đặt `LANGUAGE_MODEL_ONLY=true` trong profile (vision encoder ngốn ~1.5 GB lúc khởi động); giảm thêm `MAX_NUM_BATCHED_TOKENS`, `MAX_MODEL_LEN` |
| `permission denied ... docker.sock` | Vừa thêm vào nhóm docker: đăng xuất/đăng nhập lại (toolkit tạm dùng `sudo docker`) |
| LibreChat báo lỗi khi chat / không có model | vLLM chưa chạy hoặc đang load: `curl localhost:8000/v1/models`. Có bật UFW thì mở cổng cho Docker: `sudo ufw allow from 172.16.0.0/12 to any port 8000` |

Gỡ cài đặt: `bash uninstall.sh` chỉ xoá venv. `bash uninstall.sh --all` dừng mọi thứ, xoá cả model, log, LibreChat và lịch sử chat (Docker và image vẫn giữ).

## Cấu trúc

```
vllm-qwen-toolkit/
├── menu.sh             # menu tương tác (dùng cái này)
├── install.sh          # cài đặt toàn bộ không cần menu
├── check.sh            # chỉ kiểm tra yêu cầu
├── test.sh             # chạy examples/offline_inference.py
├── serve.sh            # bật OpenAI-compatible server
├── chat.sh             # chạy examples/openai_client.py
├── start.sh / stop.sh  # bật / dừng vLLM + LibreChat
├── librechat.sh        # quản lý riêng LibreChat (up/down/logs/status/update)
├── uninstall.sh
├── config.env          # cấu hình chung
├── profiles/           # mỗi model một file .env (profile tự tạo nằm ở ~/vllm-qwen/profiles)
├── lib/common.sh       # hàm dùng chung
├── lib/hf_models.py    # danh sách model Qwen trên Hugging Face (menu mục 5)
├── lib/server.sh       # bật/tắt vLLM chạy nền
├── lib/librechat.sh    # hàm Docker/LibreChat
├── librechat/          # mẫu docker-compose.yml + librechat.yaml.tmpl
├── scripts/            # từng bước cài đặt (10 → 80)
└── examples/
    ├── env_info.py           # kiểm tra torch/CUDA/GPU
    ├── offline_inference.py  # vLLM LLM.chat() với model local
    └── openai_client.py      # gọi server bằng thư viện openai (stream, chat nhiều lượt)
```
