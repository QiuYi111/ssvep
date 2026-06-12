import cv2
import numpy as np
from pathlib import Path

def remove_checkerboard_surgical(img_path, out_path):
    img = cv2.imread(str(img_path))
    if img is None: return
    
    corners = [img[0,0], img[0,-1], img[-1,0], img[-1,-1], img[1,1], img[1,-2]]
    bg_colors = np.unique(corners, axis=0)
    
    mask = np.ones(img.shape[:2], dtype=bool)
    for color in bg_colors:
        # Cast to int to avoid uint8 overflow
        c_int = color.astype(int)
        lower = np.clip(c_int - 15, 0, 255).astype(np.uint8)
        upper = np.clip(c_int + 15, 0, 255).astype(np.uint8)
        bg_mask = cv2.inRange(img, lower, upper)
        mask = mask & (~bg_mask.astype(bool))
    
    mask_img = mask.astype(np.uint8) * 255
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3,3))
    mask_img = cv2.morphologyEx(mask_img, cv2.MORPH_CLOSE, kernel)
    
    rgba = cv2.cvtColor(img, cv2.COLOR_BGR2BGRA)
    rgba[:, :, 3] = mask_img
    
    coords = cv2.findNonZero(mask_img)
    if coords is not None:
        x, y, w, h = cv2.boundingRect(coords)
        p = 4
        y1, y2 = max(0, y-p), min(rgba.shape[0], y+h+p)
        x1, x2 = max(0, x-p), min(rgba.shape[1], x+w+p)
        rgba = rgba[y1:y2, x1:x2]
    
    cv2.imwrite(str(out_path), rgba)

def main():
    icon_dir = Path("/Users/qiujingyi.7/ssvep/web-prototype/public/icons")
    orig_dir = Path("/Users/qiujingyi.7/ssvep/visual_concepts/App_Visual/UI_Icons")
    mapping = {
        "L1.png": "l1.png", "L2.png": "l2.png", "L3.png": "l3.png",
        "L4.png": "l4.png", "L5.png": "l5.png", "L6.png": "l6.png",
        "Settings.png": "settings.png", "home.png": "home.png", "标定.png": "calibrate.png"
    }
    for orig_name, new_name in mapping.items():
        src = orig_dir / orig_name
        dst = icon_dir / new_name
        if src.exists():
            print(f"Processing {new_name}...")
            remove_checkerboard_surgical(src, dst)

if __name__ == "__main__":
    main()
