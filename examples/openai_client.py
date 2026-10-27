#!/usr/bin/env python3
"""
Ví dụ gọi vLLM server (OpenAI-compatible API) bằng thư viện `openai`.

Bước 1 (terminal 1):  bash serve.sh          (hoặc menu.sh → mục 9)
Bước 2 (terminal 2):  bash chat.sh --prompt "Thủ đô của Việt Nam là gì?"
                      bash chat.sh --interactive     # chat nhiều lượt, giữ lịch sử

Server tương thích OpenAI nên mọi client OpenAI (LangChain, LlamaIndex, curl...) đều dùng được:
    curl http://127.0.0.1:8000/v1/chat/completions -H "Content-Type: application/json" \
      -d '{"model": "qwen3.5-4b", "messages": [{"role": "user", "content": "Xin chào"}]}'
"""

import argparse
import os
import sys
import time


def env_bool(name: str, default: bool = False) -> bool:
    return os.environ.get(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Gọi thử vLLM OpenAI-compatible server")
    p.add_argument("--base-url", default=f"http://127.0.0.1:{os.environ.get('PORT', '8000')}/v1")
    p.add_argument("--api-key", default=os.environ.get("API_KEY") or "EMPTY")
    p.add_argument("--model", default=os.environ.get("SERVED_MODEL_NAME"),
                   help="Tên model trên server (mặc định: model đầu tiên server trả về)")
    p.add_argument("--prompt", default="Giải thích ngắn gọn sự khác nhau giữa CPU và GPU.")
    p.add_argument("--system", default="Bạn là trợ lý AI hữu ích. Luôn trả lời bằng tiếng Việt.")
    p.add_argument("--max-tokens", type=int, default=1024)
    p.add_argument("--thinking", action=argparse.BooleanOptionalAction,
                   default=env_bool("ENABLE_THINKING"))
    p.add_argument("--no-stream", action="store_true", help="Nhận kết quả một lần thay vì stream")
    p.add_argument("-i", "--interactive", action="store_true", help="Chat nhiều lượt trong terminal")
    return p.parse_args()


def build_request(model: str, messages: list, max_tokens: int, thinking: bool) -> dict:
    # Tham số sampling khuyến nghị của Qwen cho từng chế độ
    return dict(
        model=model,
        messages=messages,
        max_tokens=max_tokens,
        temperature=0.6 if thinking else 0.7,
        top_p=0.95 if thinking else 0.8,
        # Tham số riêng của vLLM, gửi qua extra_body
        extra_body={"top_k": 20, "chat_template_kwargs": {"enable_thinking": thinking}},
    )


def get_reasoning(obj) -> str | None:
    # Tên trường reasoning khác nhau giữa các bản vLLM
    return getattr(obj, "reasoning_content", None) or getattr(obj, "reasoning", None)


def ask_model(client, request: dict, stream: bool) -> str:
    """Gửi request, in câu trả lời ra màn hình, trả về nội dung trả lời (không gồm phần suy nghĩ)."""
    start = time.perf_counter()
    answer = []
    usage = None

    if not stream:
        resp = client.chat.completions.create(**request)
        msg = resp.choices[0].message
        reasoning = get_reasoning(msg)
        if reasoning:
            print(f"[Suy nghĩ]\n{reasoning.strip()}\n\n[Trả lời]")
        print(msg.content)
        answer.append(msg.content or "")
        usage = resp.usage
    else:
        section = None
        stream_resp = client.chat.completions.create(
            **request, stream=True, stream_options={"include_usage": True}
        )
        for chunk in stream_resp:
            if chunk.usage:
                usage = chunk.usage
            if not chunk.choices:
                continue
            delta = chunk.choices[0].delta
            reasoning = get_reasoning(delta)
            if reasoning:
                if section != "reasoning":
                    print("[Suy nghĩ]")
                    section = "reasoning"
                print(reasoning, end="", flush=True)
            if delta.content:
                if section == "reasoning":
                    print("\n\n[Trả lời]")
                section = "answer"
                print(delta.content, end="", flush=True)
                answer.append(delta.content)
        print()

    elapsed = time.perf_counter() - start
    if usage:
        print(f"--- {usage.prompt_tokens} token vào | {usage.completion_tokens} token ra | "
              f"{elapsed:.2f}s | {usage.completion_tokens / elapsed:.1f} token/s")
    return "".join(answer)


def interactive(client, model: str, args: argparse.Namespace) -> None:
    print("Chế độ chat. Lệnh: /think bật/tắt suy nghĩ | /clear xoá lịch sử | /exit thoát\n")
    history = [{"role": "system", "content": args.system}]
    thinking = args.thinking
    while True:
        try:
            user = input("Bạn: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if not user:
            continue
        if user in ("/exit", "/quit", "/q"):
            return
        if user == "/clear":
            history = history[:1]
            print("(đã xoá lịch sử)\n")
            continue
        if user == "/think":
            thinking = not thinking
            print(f"(thinking: {'bật' if thinking else 'tắt'})\n")
            continue

        history.append({"role": "user", "content": user})
        print("AI: ", end="", flush=True)
        try:
            answer = ask_model(client, build_request(model, history, args.max_tokens, thinking),
                               stream=not args.no_stream)
        except KeyboardInterrupt:
            print("\n(đã ngắt)\n")
            history.pop()
            continue
        history.append({"role": "assistant", "content": answer})
        print()


def main() -> int:
    args = parse_args()
    from openai import OpenAI

    client = OpenAI(base_url=args.base_url, api_key=args.api_key)
    try:
        models = [m.id for m in client.models.list().data]
    except Exception as exc:  # noqa: BLE001
        print(f"Không kết nối được server {args.base_url}: {exc}\nHãy chạy trước: bash serve.sh")
        return 1
    model = args.model if args.model in models else models[0]
    print(f"Server: {args.base_url} | model: {model} | thinking: {args.thinking}\n")

    if args.interactive:
        interactive(client, model, args)
        return 0

    messages = [
        {"role": "system", "content": args.system},
        {"role": "user", "content": args.prompt},
    ]
    ask_model(client, build_request(model, messages, args.max_tokens, args.thinking),
              stream=not args.no_stream)
    return 0


if __name__ == "__main__":
    sys.exit(main())
