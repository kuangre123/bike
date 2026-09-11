#!/usr/bin/env python3
"""Call MiniMax video generation through the TokenDance gateway protocol."""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request


def request_json(url, token, payload=None, timeout=60):
    body = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(url, data=body, method="POST" if payload is not None else "GET")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {detail}") from exc


def main():
    parser = argparse.ArgumentParser(description="Generate a MiniMax video via TokenDance")
    parser.add_argument("prompt", help="视频描述")
    parser.add_argument("--image", help="首帧图片 URL（按协议可选）")
    parser.add_argument("--model", default=os.getenv("MINIMAX_MODEL", "minimax-h3"))
    parser.add_argument("--base-url", default=os.getenv("TOKENDANCE_BASE_URL", "https://tokendance.space"))
    parser.add_argument("--create-path", default=os.getenv("TOKENDANCE_VIDEO_CREATE_PATH", "/gateway/minimax/v2/video_generation"))
    parser.add_argument("--status-path", default=os.getenv("TOKENDANCE_VIDEO_STATUS_PATH", "/gateway/minimax/v2/query/video_generation/{id}"))
    parser.add_argument("--resolution", default=os.getenv("MINIMAX_RESOLUTION", "2K"))
    parser.add_argument("--ratio", default=os.getenv("MINIMAX_RATIO", "16:9"), help="文生视频宽高比")
    parser.add_argument("--token", default=os.getenv("TOKENDANCE_API_KEY"))
    parser.add_argument("--duration", type=int, help="视频时长（秒）")
    parser.add_argument("--poll-interval", type=float, default=3)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if not args.token:
        parser.error("请设置 TOKENDANCE_API_KEY 或传入 --token")

    payload = {
        "model": args.model,
        "resolution": args.resolution,
        "duration": args.duration or 6,
        "content": [{"type": "text", "text": args.prompt}],
    }
    if args.image:
        payload["content"].append({
            "type": "image_url",
            "image_url": {"url": args.image},
            "role": "first_frame",
        })
    else:
        payload["ratio"] = args.ratio

    base = args.base_url.rstrip("/")
    created = request_json(f"{base}/{args.create_path.lstrip('/')}", args.token, payload)
    task = created.get("task") if isinstance(created.get("task"), dict) else created
    task_id = task.get("task_id") or task.get("id") or created.get("task_id") or created.get("id")
    if not task_id:
        print(json.dumps(created, ensure_ascii=False, indent=2))
        return 0

    deadline = time.time() + args.timeout
    while time.time() < deadline:
        status_path = args.status_path.format(id=task_id, task_id=task_id)
        status = request_json(f"{base}/{status_path.lstrip('/')}", args.token)
        task = status.get("task") if isinstance(status.get("task"), dict) else status
        state = str(task.get("status", task.get("state", ""))).lower()
        if state in {"succeeded", "success", "completed", "done"}:
            content = task.get("content")
            result = content.get("url") if isinstance(content, dict) else None
            result = result or task.get("video_url") or task.get("url")
            print(result or json.dumps(status, ensure_ascii=False, indent=2))
            return 0
        if state in {"failed", "error", "cancelled", "canceled"}:
            raise RuntimeError(json.dumps(status, ensure_ascii=False))
        time.sleep(args.poll_interval)
    raise TimeoutError(f"任务 {task_id} 在 {args.timeout}s 内未完成")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, TimeoutError) as exc:
        print(f"错误: {exc}", file=sys.stderr)
        raise SystemExit(1)
