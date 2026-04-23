#!/usr/bin/env python3
"""
Batch-submit multi-view 2D asset folders to Meshy Multi-Image to 3D.

Expected input layout:

    visual_concepts/Assets2D/L1/lotus-close/panel_00.png
    visual_concepts/Assets2D/L1/lotus-close/panel_01.png
    visual_concepts/Assets2D/L1/lotus-close/panel_02.png
    visual_concepts/Assets2D/L1/lotus-close/panel_03.png

Each folder containing images is treated as one object. Meshy currently accepts
1 to 4 images for multi-image-to-3d, so this script selects up to 4 views per
folder and submits them as Data URIs.

Usage:

    # Preview work without using credits.
    python scripts/meshy_batch.py plan --root visual_concepts/Assets2D

    # Submit all folders. Requires Meshy_TOKEN.
    Meshy_TOKEN=... python scripts/meshy_batch.py submit --root visual_concepts/Assets2D

    # Poll submitted tasks and download successful models.
    Meshy_TOKEN=... python scripts/meshy_batch.py poll --download
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any


API_BASE = "https://api.meshy.ai/openapi/v1"
DEFAULT_ROOT = Path("visual_concepts/Assets2D")
DEFAULT_OUT = Path("meshy_outputs")
SUPPORTED_EXTS = {".png", ".jpg", ".jpeg"}
TERMINAL_STATUSES = {"SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"}


@dataclass
class AssetJob:
    key: str
    folder: str
    image_paths: list[str]
    selected_image_paths: list[str]


def eprint(*parts: object) -> None:
    print(*parts, file=sys.stderr)


def slugify(value: str) -> str:
    value = value.strip().replace(os.sep, "__")
    value = re.sub(r"[^\w\u4e00-\u9fff,.-]+", "_", value, flags=re.UNICODE)
    value = value.strip("_")
    return value or "asset"


def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    tmp.replace(path)


def append_jsonl(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(data, ensure_ascii=False, sort_keys=True))
        f.write("\n")


def image_sort_key(path: Path) -> tuple[Any, ...]:
    nums = [int(n) for n in re.findall(r"\d+", path.stem)]
    return (*nums, path.name) if nums else (10**9, path.name)


def select_images(paths: list[Path], max_images: int, strategy: str) -> list[Path]:
    if len(paths) <= max_images:
        return paths
    if strategy == "first":
        return paths[:max_images]
    if strategy == "last":
        return paths[-max_images:]

    # even: preserve the first and last views, sample the middle evenly.
    if max_images == 1:
        return [paths[0]]
    selected: list[Path] = []
    last_index = len(paths) - 1
    for i in range(max_images):
        idx = round(i * last_index / (max_images - 1))
        selected.append(paths[idx])
    # Deduplicate while preserving order.
    deduped: list[Path] = []
    seen: set[Path] = set()
    for p in selected:
        if p not in seen:
            deduped.append(p)
            seen.add(p)
    return deduped[:max_images]


def discover_jobs(root: Path, max_images: int, strategy: str, include: str | None) -> list[AssetJob]:
    root = root.resolve()
    if not root.exists():
        raise SystemExit(f"Root does not exist: {root}")

    include_re = re.compile(include) if include else None
    jobs: list[AssetJob] = []

    for folder in sorted([p for p in root.rglob("*") if p.is_dir()]):
        images = sorted(
            [p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in SUPPORTED_EXTS],
            key=image_sort_key,
        )
        if not images:
            continue

        rel_folder = folder.relative_to(root).as_posix()
        if include_re and not include_re.search(rel_folder):
            continue

        selected = select_images(images, max_images=max_images, strategy=strategy)
        key = slugify(rel_folder)
        jobs.append(
            AssetJob(
                key=key,
                folder=rel_folder,
                image_paths=[p.relative_to(root).as_posix() for p in images],
                selected_image_paths=[p.relative_to(root).as_posix() for p in selected],
            )
        )

    return jobs


def image_to_data_uri(path: Path) -> str:
    mime = mimetypes.guess_type(path.name)[0]
    if mime not in {"image/png", "image/jpeg"}:
        if path.suffix.lower() == ".png":
            mime = "image/png"
        elif path.suffix.lower() in {".jpg", ".jpeg"}:
            mime = "image/jpeg"
        else:
            raise ValueError(f"Unsupported image type: {path}")
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{encoded}"


def meshy_request(
    method: str,
    path: str,
    token: str,
    payload: dict[str, Any] | None = None,
    timeout: int = 120,
) -> Any:
    url = f"{API_BASE}{path}"
    data = None
    headers = {"Authorization": f"Bearer {token}"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read()
            if not body:
                return None
            return json.loads(body.decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Meshy HTTP {exc.code} for {method} {path}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Meshy request failed for {method} {path}: {exc}") from exc


def download_url(url: str, dest: Path, timeout: int = 300) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "ssvep-meshy-batch/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        tmp = dest.with_suffix(dest.suffix + ".tmp")
        with tmp.open("wb") as f:
            while True:
                chunk = resp.read(1024 * 1024)
                if not chunk:
                    break
                f.write(chunk)
        tmp.replace(dest)


def build_payload(args: argparse.Namespace, image_urls: list[str]) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "image_urls": image_urls,
        "ai_model": args.ai_model,
        "should_texture": args.should_texture,
        "enable_pbr": args.enable_pbr,
        "target_formats": args.formats,
        "image_enhancement": args.image_enhancement,
        "remove_lighting": args.remove_lighting,
        "moderation": args.moderation,
    }

    if args.should_remesh:
        payload["should_remesh"] = True
        payload["topology"] = args.topology
        payload["target_polycount"] = args.target_polycount
        payload["save_pre_remeshed_model"] = args.save_pre_remeshed_model
    else:
        payload["should_remesh"] = False

    if args.texture_prompt:
        payload["texture_prompt"] = args.texture_prompt[:600]
    if args.symmetry_mode:
        payload["symmetry_mode"] = args.symmetry_mode
    if args.pose_mode:
        payload["pose_mode"] = args.pose_mode
    if args.auto_size:
        payload["auto_size"] = True
        payload["origin_at"] = args.origin_at

    return payload


def command_plan(args: argparse.Namespace) -> int:
    jobs = discover_jobs(args.root, args.max_images, args.select, args.include)
    print(f"Discovered {len(jobs)} asset folders under {args.root}")
    for job in jobs[: args.limit or None]:
        more = "" if len(job.image_paths) <= args.max_images else f" (selected {len(job.selected_image_paths)} of {len(job.image_paths)})"
        print(f"- {job.folder}: {len(job.image_paths)} images{more}")
        for rel in job.selected_image_paths:
            print(f"    {rel}")
    if args.limit and len(jobs) > args.limit:
        print(f"... {len(jobs) - args.limit} more jobs omitted by --limit")
    return 0


def command_submit(args: argparse.Namespace) -> int:
    token = os.environ.get("Meshy_TOKEN")
    if not token:
        raise SystemExit("Missing environment variable Meshy_TOKEN")

    root = args.root.resolve()
    out = args.out
    tasks_path = out / "tasks.json"
    events_path = out / "events.jsonl"
    tasks: dict[str, Any] = read_json(tasks_path, {})

    jobs = discover_jobs(args.root, args.max_images, args.select, args.include)
    if args.limit:
        jobs = jobs[: args.limit]

    print(f"Submitting {len(jobs)} jobs to Meshy")
    for index, job in enumerate(jobs, start=1):
        existing = tasks.get(job.key)
        if existing and existing.get("task_id") and not args.force:
            print(f"[{index}/{len(jobs)}] skip existing {job.folder}: {existing['task_id']}")
            continue

        selected_abs = [root / rel for rel in job.selected_image_paths]
        image_urls = [image_to_data_uri(path) for path in selected_abs]
        payload = build_payload(args, image_urls)

        print(f"[{index}/{len(jobs)}] submit {job.folder} ({len(image_urls)} images)")
        response = meshy_request("POST", "/multi-image-to-3d", token, payload=payload)
        task_id = response.get("result") if isinstance(response, dict) else None
        if not task_id:
            raise RuntimeError(f"Unexpected Meshy response for {job.folder}: {response}")

        record = {
            **asdict(job),
            "task_id": task_id,
            "endpoint": "multi-image-to-3d",
            "status": "SUBMITTED",
            "created_local_at": int(time.time() * 1000),
            "request_options": {
                "ai_model": args.ai_model,
                "should_texture": args.should_texture,
                "enable_pbr": args.enable_pbr,
                "formats": args.formats,
                "should_remesh": args.should_remesh,
                "topology": args.topology if args.should_remesh else None,
                "target_polycount": args.target_polycount if args.should_remesh else None,
            },
        }
        tasks[job.key] = record
        write_json(tasks_path, tasks)
        append_jsonl(events_path, {"event": "submitted", "key": job.key, "folder": job.folder, "task_id": task_id})

        if args.sleep > 0:
            time.sleep(args.sleep)

    print(f"Wrote {tasks_path}")
    return 0


def command_poll(args: argparse.Namespace) -> int:
    token = os.environ.get("Meshy_TOKEN")
    if not token:
        raise SystemExit("Missing environment variable Meshy_TOKEN")

    out = args.out
    tasks_path = out / "tasks.json"
    events_path = out / "events.jsonl"
    tasks: dict[str, Any] = read_json(tasks_path, {})
    if not tasks:
        raise SystemExit(f"No tasks found at {tasks_path}")

    deadline = time.time() + args.timeout if args.wait else time.time()

    while True:
        pending = 0
        changed = False
        for key, record in sorted(tasks.items()):
            task_id = record.get("task_id")
            if not task_id:
                continue
            current_status = record.get("status")
            if current_status in TERMINAL_STATUSES and not args.refresh:
                if args.download and current_status == "SUCCEEDED":
                    download_task_outputs(out, key, record)
                continue

            task = meshy_request("GET", f"/multi-image-to-3d/{urllib.parse.quote(task_id)}", token)
            status = task.get("status", "UNKNOWN")
            progress = task.get("progress")
            print(f"{record.get('folder', key)}: {status} {progress}%")

            record["status"] = status
            record["progress"] = progress
            record["last_response"] = task
            changed = True
            append_jsonl(events_path, {"event": "polled", "key": key, "task_id": task_id, "status": status, "progress": progress})

            if status not in TERMINAL_STATUSES:
                pending += 1
            elif args.download and status == "SUCCEEDED":
                download_task_outputs(out, key, record)

            if args.sleep > 0:
                time.sleep(args.sleep)

        if changed:
            write_json(tasks_path, tasks)

        if not args.wait or pending == 0 or time.time() >= deadline:
            if pending and args.wait:
                print(f"Stopped with {pending} task(s) still pending after timeout.")
            break

        print(f"Waiting {args.interval}s before next poll; {pending} task(s) pending.")
        time.sleep(args.interval)

    return 0


def download_task_outputs(out: Path, key: str, record: dict[str, Any]) -> None:
    response = record.get("last_response") or {}
    model_urls = response.get("model_urls") or {}
    thumbnail_url = response.get("thumbnail_url")
    texture_urls = response.get("texture_urls") or []

    dest_dir = out / "downloads" / key
    downloaded = record.setdefault("downloaded", {})

    for fmt, url in sorted(model_urls.items()):
        if not url or downloaded.get(fmt):
            continue
        suffix = "glb" if fmt == "pre_remeshed_glb" else fmt.strip().lower()
        dest = dest_dir / f"{fmt}.{suffix}"
        print(f"  download {fmt} -> {dest}")
        download_url(url, dest)
        downloaded[fmt] = str(dest)

    if thumbnail_url and not downloaded.get("thumbnail"):
        dest = dest_dir / "thumbnail.png"
        print(f"  download thumbnail -> {dest}")
        download_url(thumbnail_url, dest)
        downloaded["thumbnail"] = str(dest)

    for i, texture_set in enumerate(texture_urls):
        for name, url in sorted(texture_set.items()):
            key_name = f"texture_{i}_{name}"
            if not url or downloaded.get(key_name):
                continue
            dest = dest_dir / f"{key_name}.png"
            print(f"  download {key_name} -> {dest}")
            download_url(url, dest)
            downloaded[key_name] = str(dest)


def add_common_discovery_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT, help=f"Asset root. Default: {DEFAULT_ROOT}")
    parser.add_argument("--max-images", type=int, default=4, choices=range(1, 5), metavar="{1,2,3,4}")
    parser.add_argument("--select", choices=["even", "first", "last"], default="even", help="How to choose views if a folder has more than --max-images images.")
    parser.add_argument("--include", help="Regex filter matched against relative folder paths.")
    parser.add_argument("--limit", type=int, help="Limit number of jobs for testing.")


def add_meshy_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help=f"Output folder. Default: {DEFAULT_OUT}")
    parser.add_argument("--ai-model", default="latest", choices=["latest", "meshy-6", "meshy-5"])
    parser.add_argument("--formats", nargs="+", default=["glb", "usdz"], choices=["glb", "obj", "fbx", "stl", "usdz", "3mf"])
    parser.add_argument("--no-texture", dest="should_texture", action="store_false", default=True)
    parser.add_argument("--enable-pbr", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--image-enhancement", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--remove-lighting", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--moderation", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--should-remesh", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--save-pre-remeshed-model", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--topology", choices=["triangle", "quad"], default="quad")
    parser.add_argument("--target-polycount", type=int, default=50000)
    parser.add_argument("--symmetry-mode", choices=["off", "auto", "on"], default="auto")
    parser.add_argument("--pose-mode", choices=["", "a-pose", "t-pose"], default="")
    parser.add_argument("--auto-size", action="store_true")
    parser.add_argument("--origin-at", choices=["bottom", "center"], default="bottom")
    parser.add_argument("--texture-prompt", default="")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Batch Meshy Multi-Image to 3D for asset folders.")
    sub = parser.add_subparsers(dest="command", required=True)

    plan = sub.add_parser("plan", help="List asset folders and selected images; does not call Meshy.")
    add_common_discovery_args(plan)
    plan.set_defaults(func=command_plan)

    submit = sub.add_parser("submit", help="Submit discovered asset folders to Meshy.")
    add_common_discovery_args(submit)
    add_meshy_options(submit)
    submit.add_argument("--force", action="store_true", help="Submit again even if a task already exists for the asset key.")
    submit.add_argument("--sleep", type=float, default=1.0, help="Seconds to sleep between submissions.")
    submit.set_defaults(func=command_submit)

    poll = sub.add_parser("poll", help="Poll task status and optionally download outputs.")
    poll.add_argument("--out", type=Path, default=DEFAULT_OUT, help=f"Output folder. Default: {DEFAULT_OUT}")
    poll.add_argument("--download", action="store_true", help="Download model, thumbnail, and texture URLs for succeeded tasks.")
    poll.add_argument("--wait", action="store_true", help="Keep polling until tasks reach terminal states or timeout.")
    poll.add_argument("--interval", type=float, default=30.0, help="Polling interval when --wait is used.")
    poll.add_argument("--timeout", type=float, default=60 * 60, help="Max seconds to wait with --wait.")
    poll.add_argument("--refresh", action="store_true", help="Refresh terminal tasks too.")
    poll.add_argument("--sleep", type=float, default=0.2, help="Seconds to sleep between API calls.")
    poll.set_defaults(func=command_poll)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except KeyboardInterrupt:
        eprint("Interrupted.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
