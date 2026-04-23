"""
split_panels.py — 前景分割 + 连通域分析，自动拆分素材拼贴图

用法:
    uv run python split_panels.py                          # 处理全部 Assets/2D/
    uv run python split_panels.py --dir Assets/2D/L1       # 只处理指定目录
    uv run python split_panels.py --keep topk --topk 4     # 只保留最大的 4 个 panel
    uv run python split_panels.py --dry-run                # 只输出 metadata，不保存图片
"""

import argparse
import json
import cv2
import numpy as np
from pathlib import Path
from datetime import datetime


def estimate_background(img: np.ndarray) -> np.ndarray:
    """从图像边缘像素估计背景颜色（中值）"""
    border = np.concatenate([
        img[0, :, :],
        img[-1, :, :],
        img[:, 0, :],
        img[:, -1, :],
    ], axis=0)
    return np.median(border, axis=0)


def build_foreground_mask(img: np.ndarray, threshold: int = 30) -> np.ndarray:
    """
    构建前景 mask。
    优先用 alpha 通道（如果有），否则用背景色差阈值。
    返回 uint8 mask（0/255）。
    """
    if img.ndim == 3 and img.shape[2] == 4:
        # RGBA — alpha 通道直接当 mask
        mask = (img[:, :, 3] > 8).astype(np.uint8) * 255
        return mask

    rgb = img[:, :, :3] if img.ndim == 3 else cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    bg = estimate_background(rgb)

    diff = np.linalg.norm(rgb.astype(np.float32) - bg.astype(np.float32), axis=2)
    mask = (diff > threshold).astype(np.uint8) * 255
    return mask


def clean_mask(mask: np.ndarray, kernel_size: int = 5) -> np.ndarray:
    """形态学开闭清理小噪点和空洞"""
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    return mask


def find_panels(
    image_path: str | Path,
    threshold: int = 30,
    min_area: int = 1500,
    pad: int = 12,
    keep_mode: str = "all",
    topk: int = 4,
    area_ratio: float = 0.12,
    kernel_size: int = 5,
) -> tuple[list[dict], np.ndarray | None]:
    """
    对一张图做前景分割 + 连通域分析。

    返回 (panels, rgb_image)。
    每个 panel 是一个 dict：
        bbox: (x1, y1, x2, y2)
        area: int
        centroid: (cx, cy)
        crop: numpy array (BGR)
    """
    img = cv2.imread(str(image_path), cv2.IMREAD_UNCHANGED)
    if img is None:
        raise ValueError(f"Cannot read image: {image_path}")

    # 统一拿到 BGR rgb
    if img.ndim == 3 and img.shape[2] == 4:
        rgb = img[:, :, :3]
    elif img.ndim == 3:
        rgb = img
    else:
        rgb = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)

    # 1) 前景 mask
    mask = build_foreground_mask(img, threshold=threshold)

    # 2) 形态学清理
    mask = clean_mask(mask, kernel_size=kernel_size)

    # 3) 连通域
    num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(
        mask, connectivity=8
    )

    H, W = rgb.shape[:2]
    panels = []
    for i in range(1, num_labels):  # 0 = 背景
        x, y, w, h, area = stats[i]
        cx, cy = centroids[i]

        if area < min_area:
            continue

        # 加 pad 裁剪
        x1 = max(0, x - pad)
        y1 = max(0, y - pad)
        x2 = min(W, x + w + pad)
        y2 = min(H, y + h + pad)

        panels.append({
            "bbox": [int(x1), int(y1), int(x2), int(y2)],
            "area": int(area),
            "centroid": [float(cx), float(cy)],
            "crop": rgb[y1:y2, x1:x2].copy(),
        })

    # 4) 按面积降序排，做筛选
    panels.sort(key=lambda p: p["area"], reverse=True)

    if keep_mode == "topk":
        panels = panels[:topk]
    elif keep_mode == "main_only":
        if panels:
            max_area = panels[0]["area"]
            panels = [p for p in panels if p["area"] >= max_area * area_ratio]

    # 5) 最终按 (y, x) 排序（从上到下，从左到右）
    panels.sort(key=lambda p: (p["bbox"][1], p["bbox"][0]))

    return panels, rgb


def process_one(
    image_path: Path,
    out_dir: Path,
    dry_run: bool = False,
    threshold: int = 30,
    min_area: int = 1500,
    pad: int = 12,
    keep_mode: str = "all",
    topk: int = 4,
    area_ratio: float = 0.12,
) -> dict:
    """处理单张图片，返回 metadata dict。"""
    panels, rgb = find_panels(
        image_path,
        threshold=threshold,
        min_area=min_area,
        pad=pad,
        keep_mode=keep_mode,
        topk=topk,
        area_ratio=area_ratio,
    )

    stem = image_path.stem
    saved_paths = []

    if not dry_run:
        panel_dir = out_dir / stem
        panel_dir.mkdir(parents=True, exist_ok=True)
        for idx, panel in enumerate(panels):
            out_path = panel_dir / f"panel_{idx:02d}.png"
            cv2.imwrite(str(out_path), panel["crop"])
            saved_paths.append(str(out_path))
            del panel["crop"]

    meta = {
        "source": str(image_path),
        "folder": image_path.parent.name,
        "num_panels": len(panels),
        "panels": panels,
        "saved_paths": saved_paths,
    }
    return meta


def process_batch(
    root_dir: str | Path,
    out_root: str | Path,
    dry_run: bool = False,
    threshold: int = 30,
    min_area: int = 1500,
    pad: int = 12,
    keep_mode: str = "all",
    topk: int = 4,
    area_ratio: float = 0.12,
) -> list[dict]:
    """批量处理目录下所有 PNG/JPG 图片。"""
    root_dir = Path(root_dir)
    out_root = Path(out_root)
    all_meta = []
    images = sorted(root_dir.rglob("*.png")) + sorted(root_dir.rglob("*.jpg"))
    # deduplicate (case-insensitive FS)
    seen = set()
    unique = []
    for img in images:
        key = str(img.resolve())
        if key not in seen:
            seen.add(key)
            unique.append(img)
    images = unique

    print(f"Found {len(images)} images in {root_dir}")
    for i, img_path in enumerate(images, 1):
        rel = img_path.relative_to(root_dir)
        out_dir = out_root / rel.parent

        print(f"[{i:2d}/{len(images)}] {rel} ... ", end="", flush=True)
        try:
            meta = process_one(
                img_path, out_dir,
                dry_run=dry_run,
                threshold=threshold,
                min_area=min_area,
                pad=pad,
                keep_mode=keep_mode,
                topk=topk,
                area_ratio=area_ratio,
            )
            n = meta["num_panels"]
            print(f"✅ {n} panel{'s' if n != 1 else ''}")
            all_meta.append(meta)
        except Exception as e:
            print(f"❌ {e}")
            all_meta.append({
                "source": str(img_path),
                "error": str(e),
            })

    # 写总 metadata
    if not dry_run:
        meta_path = out_root / "metadata.json"
        meta_path.parent.mkdir(parents=True, exist_ok=True)
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump({
                "generated_at": datetime.now().isoformat(),
                "params": {
                    "threshold": threshold,
                    "min_area": min_area,
                    "pad": pad,
                    "keep_mode": keep_mode,
                    "topk": topk,
                    "area_ratio": area_ratio,
                },
                "images": all_meta,
            }, f, indent=2, ensure_ascii=False)
        print(f"\nMetadata saved to {meta_path}")

    # 打印汇总
    total_panels = sum(m.get("num_panels", 0) for m in all_meta)
    errors = sum(1 for m in all_meta if "error" in m)
    print(f"\n{'='*50}")
    print(f"Total: {len(images)} images → {total_panels} panels  ({errors} errors)")

    return all_meta


def main():
    parser = argparse.ArgumentParser(description="素材拼贴图前景分割工具")
    parser.add_argument("--dir", default="Assets/2D", help="输入目录（默认 Assets/2D）")
    parser.add_argument("--out", default="Assets/2D_split", help="输出目录（默认 Assets/2D_split）")
    parser.add_argument("--threshold", type=int, default=30, help="背景色差阈值（默认 30）")
    parser.add_argument("--min-area", type=int, default=1500, help="最小连通域面积（默认 1500）")
    parser.add_argument("--pad", type=int, default=12, help="裁剪 padding（默认 12）")
    parser.add_argument("--keep", choices=["all", "topk", "main_only"], default="all",
                        help="保留模式（默认 all）")
    parser.add_argument("--topk", type=int, default=4, help="topk 模式保留数量")
    parser.add_argument("--area-ratio", type=float, default=0.12, help="main_only 面积比例阈值")
    parser.add_argument("--dry-run", action="store_true", help="只分析不保存图片")
    args = parser.parse_args()

    process_batch(
        root_dir=args.dir,
        out_root=args.out,
        dry_run=args.dry_run,
        threshold=args.threshold,
        min_area=args.min_area,
        pad=args.pad,
        keep_mode=args.keep,
        topk=args.topk,
        area_ratio=args.area_ratio,
    )


if __name__ == "__main__":
    main()
