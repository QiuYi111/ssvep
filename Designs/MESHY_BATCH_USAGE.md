# Meshy Batch Conversion Usage

This project uses `scripts/meshy_batch.py` to submit `visual_concepts/Assets2D` folders to Meshy Multi-Image to 3D.

Each folder is treated as one object. If a folder has more than four images, the script selects four evenly spaced views because Meshy Multi-Image to 3D accepts up to four input images.

## 1. Preview the Batch

This does not call Meshy or consume credits.

```bash
python3 scripts/meshy_batch.py plan --root visual_concepts/Assets2D
```

Preview a small subset:

```bash
python3 scripts/meshy_batch.py plan --root visual_concepts/Assets2D --limit 8
```

Filter by folder path:

```bash
python3 scripts/meshy_batch.py plan --root visual_concepts/Assets2D --include 'L1/lotus-close'
```

## 2. Submit Jobs

Set the API token through the environment variable `Meshy_TOKEN`.

```bash
Meshy_TOKEN='YOUR_TOKEN' python3 scripts/meshy_batch.py submit --root visual_concepts/Assets2D
```

Recommended first test:

```bash
Meshy_TOKEN='YOUR_TOKEN' python3 scripts/meshy_batch.py submit \
  --root visual_concepts/Assets2D \
  --include 'L1/lotus-close' \
  --limit 1
```

Useful options:

```bash
--formats glb usdz
--ai-model latest
--target-polycount 50000
--topology quad
--select even
--sleep 1.0
```

## 3. Poll and Download

Check task status:

```bash
Meshy_TOKEN='YOUR_TOKEN' python3 scripts/meshy_batch.py poll
```

Wait until tasks finish and download generated assets:

```bash
Meshy_TOKEN='YOUR_TOKEN' python3 scripts/meshy_batch.py poll --wait --download
```

## Outputs

The script writes:

- `meshy_outputs/tasks.json`: task registry and latest Meshy responses.
- `meshy_outputs/events.jsonl`: append-only submission/poll log.
- `meshy_outputs/downloads/<asset_key>/`: downloaded models, thumbnails, and textures.

## Notes for Delegated Agents

- Do not submit the full batch before validating one or two assets visually.
- Prefer `glb` for web preview and `usdz` for Apple-native pipelines.
- If the generated model is too heavy, rerun selected assets with a lower `--target-polycount`.
- If the object is a flat effect layer, do not force it into 3D. Keep it as animated 2D or shader-driven visual.
