# Strata gfx906 - MI50 / MI60 / Radeon VII

Docker image: [`xxdoman/strata-mi50`](https://hub.docker.com/r/xxdoman/strata-mi50)

**Strata engine (Qwen3.8-Flash-Next) for AMD Instinct MI50 / gfx906 — self-contained Docker image with a built-in web configurator.**

One image = engine + server + **browser configurator (:8090)**. Pick a model, set the context, load the API key — done. No model is baked into the image; models, packs and MTP live on the host and are mounted.

ROCm 7.2.1 base with the host's **gfx906 libraries and rocBLAS kernels** packed in, so prefill/GEMM actually has code for the card (official ROCm images ship rocBLAS starting at gfx1010 — no gfx906).

License: Strata is **MIT** — repackaging and redistribution are allowed (keep the copyright notice).

---

## What is in this image

- **Engine v0.1.40** with the gfx906 build fixes (below).
- **Server hotfixes from upstream v0.1.40.1** — tool calls inside code fences, a request meeting a
  restart in progress, `--batch` whose engine died during its prompt read, and the four-part version
  tag. Pure Python; no engine changes.
- **Network pool** (`serve/pool.py`, `serve/route.py`, the **Pool** tab) — split the model across
  several PCs over TCP, the way `llama.cpp` RPC does, but moving *layers* instead of computations.
  Each PC runs a full engine with its own layers, so cards of **different vendors never share a
  driver** — a Radeon and an MI50 on one machine, or a laptop over Wi-Fi. Roles are set in the
  **Pool** tab: `off` / `router` / `coordinator` / `worker`. Default role is `off`.
- **Help tab** in the configurator — the engine's full flag reference, captured from the binary at
  image build time, so it updates itself with every release.

### The gfx906 build fixes

The upstream 0.1.40 tree does not compile for gfx906 at all: three `STRATA_USE_HIP` gates miss
`STRATA_HIP_GFX906`. Fixed in this image (`src/core/vmm.cpp`, `src/core/mtp.cpp`,
`src/kernels/cuda/fused_gr.cu`), plus a signed-dot4 (`v_dot4_i32_i8`) path for `__dp4a` on gfx906.
Proposed upstream as PR #1083 (build fix) and #1084 (dp4a).

### About the 0.1.40.1 naming

Upstream's 0.1.40.1 hotfix does **not** bump the version in `CMakeLists.txt` — the engine still
reports `0.1.40`. That is why this image keeps the engine tag and adds a suffix instead of moving
the engine version.

---

## Tags

- `latest` / `0.1.40.1` / `0.1.40.1-pool` — the current image (all three names point at the same
  digest). Engine **v0.1.40** + upstream **v0.1.40.1** server hotfixes + **network pool** +
  **Help** tab + per-card VRAM reserve.
- `0.1.40` — the previous image: engine v0.1.40, server v0.1.40, **no pool**, no Help tab.
- `0.1.39` — engine **v0.1.39** (the release before that).
- `0.1.38-setup` — engine **v0.1.38** + the **in-browser setup wizard** (download + build the model
  data without touching the host).

All tags include the configurator UI in **English** with an **EN/PL** toggle; the vision encoder is a
**CPU** build (correct for gfx906).

## Two ways to get the model data

### Option 1 — the built-in wizard (easiest, in `latest` / `0.1.40.1-pool` and `0.1.38-setup`)

No host steps, no scripts. Open **http://<host>:8090** and use section **0. Setup**:

1. pick a **model family** and a **size** (every quant shows its source repo and size),
   or choose **Custom HuggingFace repo…** and paste any `user/repo` — the wizard lists its
   `.gguf` sizes (grouped from the shards, with sizes) and builds the one you pick,
2. choose whether you want images (vision),
3. click **Download and prepare** — the container downloads the GGUF from HuggingFace, then builds
   the pack (dense.bin, index.txt), the tokenizer, and the MTP draft layer — all inside the container,
4. when it says *done*, pick the model below and **Save and load**.

Families with their source repos:

| Family | Repo |
|---|---|
| Qwen3.8-Flash-Next (GSQ-RCO) | `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF` |
| Swift 1.5 | `ukisai/Swift-1.5-Qwen3.8-Flash-Next-GSQ-RCO-GGUF` |
| Coder | `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF` |
| Uncensored | `orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF` |
| Unsloth (experimental) | `unsloth/Qwen3.8-Flash-Next-GGUF` |
| **Custom** | any repo id you paste |

`--compat-bf16` is applied automatically for the fine-tunes that need it (Uncensored, Unsloth).
The Q2_0 AVX-512 repack is used only when the CPU actually has AVX-512 (everything else uses the
plain `iq_pack`, which only needs AVX2) — same rule as upstream setup.

Progress and the live tool log are shown in the page. It is resumable: if it stops, restart it and the
downloads continue where they left off. Requires the data + models volumes mounted **writable** (the
wizard writes into them). A one-time ~70 GB download (up to ~350 GB for a full BF16 size).

> The wizard does **not** run upstream `setup.py` — on Linux that would download its own prebuilt CUDA
> engine and clash with the gfx906 engine in this image. It only runs the data tools (`iq_pack.py`,
> `strata_tokenizer.py`, `mtp_fetch.py`, ...), which build the same `Strata-data` layout.

### Option 2 — prepare on the host

Run upstream Strata's own setup once, on the host, outside this container, then mount the result:

    ./setup.sh --family qwen --model IQ2_XS --vision yes \
               --data-dir /srv/strata-data --no-start --yes

## Quick start

### docker compose (recommended)

```yaml
services:
  strata:
    image: xxdoman/strata-mi50:latest
    container_name: strata
    restart: unless-stopped
    shm_size: 16g
    devices:
      - /dev/kfd:/dev/kfd
      - /dev/dri:/dev/dri
    device_cgroup_rules:
      - 'c 226:* rmw'
    ports:
      - "8085:8085"     # engine (API + built-in chat)
      - "8090:8090"     # configurator (web)
    ulimits:
      memlock: -1
    security_opt:
      - seccomp=unconfined
    environment:
      - HSA_OVERRIDE_GFX_VERSION=9.0.6
      - LD_LIBRARY_PATH=/opt/rocm/lib
      - CONFIG=/work/strata-config.json
      - WEB_PORT=8090
      - ENGINE_PORT=8085
      # - ROCR_VISIBLE_DEVICES=0     # multi-GPU: which AMD card (index from rocm-smi)
    volumes:
      - /path/to/gguf:/models                  # models + mmproj (RW for the setup wizard; :ro after)
      - /path/to/Strata-data:/data             # packs/ + mtp/ + expert-profile.bin (RW for the wizard)
      - /path/to/Strata-data/configs:/work     # RW — configurator writes the config here
```

```bash
docker compose up -d && docker compose logs -f
```

### docker run

```bash
docker run -d --name strata --restart unless-stopped \
  --shm-size 16g \
  --device /dev/kfd --device /dev/dri --device-cgroup-rule 'c 226:* rmw' \
  -p 8085:8085 -p 8090:8090 \
  --ulimit memlock=-1 --security-opt seccomp=unconfined \
  -e HSA_OVERRIDE_GFX_VERSION=9.0.6 -e LD_LIBRARY_PATH=/opt/rocm/lib \
  -v /path/to/gguf:/models \
  -v /path/to/Strata-data:/data \
  -v /path/to/Strata-data/configs:/work \
  xxdoman/strata-mi50:latest
```

Open **http://<host>:8090** (configurator) and **http://<host>:8085** (engine chat / API).

> **Portainer.** Portainer passes volume paths through verbatim - `~` is **not** expanded, so
> `~/strata/gguf` becomes the literal `/strata/gguf` (a root folder). In Portainer always use absolute
> paths: `/home/<your-user>/strata/gguf` (find yours with `echo $HOME`).

---

## How it works

The image runs the **configurator (:8090)** and the **engine (:8085)** together. `strata-launcher.py` is PID 1 and manages the engine as a child process.

    http://<host>:8090   ->  CONFIGURATOR: pick model / card / context / key -> "Save and load"
    http://<host>:8085   ->  ENGINE (OpenAI- and Anthropic-compatible API + built-in chat)

- The config lives on a **volume** (`/work/strata-config.json`), written by the configurator. It **survives image updates**.
- **Config present -> the model loads automatically** on container start (autostart).
  **No config -> only the configurator starts**; the engine starts after you choose in the UI.
- Change model, context, key, expert cache, VRAM reserve, MTP drafts (`--spec`) or the engine port on **:8090** — no docker restart, no image rebuild.

---

## Configuration

### Configurator UI (:8090)

1. **Model** — pick one of the detected GGUF models (name is paired with a matching *pack*).
2. **Image (mmproj)** — optional. Pick a matching `mmproj-*.gguf` to enable vision (text-only vs. +images).
3. **AMD card** — pick the GPU (`rocm-smi`) or "All cards".
4. **Settings** — context (default **65536**), API key (default **1234**), expert cache (`auto` or an explicit number),
   VRAM reserve (MiB), engine port, **MTP drafts** (`--spec`, default 3) and **spec min-p** (`--spec-min-p`, 0.9).
   The `--spec` / `--spec-min-p` fields let you tune the MTP draft layer without editing the config
   (on the MI50, `--spec 3` is measurably faster than 2).
5. **Save and load** — writes the config and starts the engine.

When the engine is running, the **Engine state** section shows a clickable **server link**
`http://<your-host>:<engine-port>/` (host taken from the browser, port from the config), so you can open the
built-in chat/API UI directly — including from another PC on the LAN.

The UI is **English by default**; toggle **EN / PL** in the top-right corner (remembered in `localStorage`).

### API key

- **Default: `1234`** (built into the container, used by the built-in chat and every API call).
- **Where to change it:** the configurator (:8090) -> **4. Settings -> API key** -> type a new key ->
  **Save and load**. The engine restarts with the new key; the config on the volume keeps it, so it also
  survives a container restart.
- Any client (OpenAI SDK, Anthropic SDK, Codex, `curl`, another app) must send the **same** key.
  The built-in chat uses the key from the config automatically - nothing to set there.

> **Before exposing the ports to a network** (not just `localhost`), set a long random key. With a
> trivial key like `1234` anyone on the LAN can use your model. There is no other access control.

### Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `MODELS_DIR` | `/models` | models + mmproj (mount here) |
| `DATA_DIR` | `/data` | packs / mtp / expert-profile |
| `CONFIG` | `/work/strata-config.json` | written by the configurator, must be RW |
| `WEB_PORT` | `8090` | configurator port |
| `ENGINE_PORT` | `8085` | engine port |
| `STRATA_MODE` | `local` | launcher mode (`local` = manage engine as a child process) |
| `HSA_OVERRIDE_GFX_VERSION` | `9.0.6` | required for MI50 (gfx906) |
| `ROCR_VISIBLE_DEVICES` | *(unset)* | multi-GPU: which card (index from `rocm-smi`) |

### Config file (`/work/strata-config.json`)

Written by the configurator; you normally never edit it by hand. Key fields:

- `args` — engine flags: `--pack`, `--native` (model shard), `--ple-gguf`, `--expert-cache`, `--mtp`, `--max-context`, `--kv int8`, `--spec 3 --spec-min-p 0.9`, `--vision`, `--vram-reserve-mib`.
- `vision` — `{ "exe", "mmproj", "model", "gpu": false, "max_tokens", "threads" }`. **`"gpu": false` = vision encoder on CPU** (correct for gfx906 — see below).
- `api_key`, `port`, `model_name`, `tokenizer`, `lib_dirs`.

---

## Where the model files come from

This image ships **only** the engine (prebuilt gfx906 binary + ROCm 7.2.1), the configurator, and —
in the `0.1.40` / `latest` / `0.1.38-setup` tags — the **data tools**. The model and the data it consumes are **not** in the
image and are **not** taken from anyone's personal folder. Each piece comes from a known source:

| Piece | Where it comes from |
|---|---|
| **Model GGUF** | **HuggingFace:** `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF` (the original), `ukisai/Swift-1.5-Qwen3.8-Flash-Next-GSQ-RCO-GGUF`, `ISTA-DASLab/...-Coder-GGUF`, `orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF`, `unsloth/Qwen3.8-Flash-Next-GGUF` |
| **`mmproj/`** (images) | the same repo as the model (`mmproj-*.gguf`) |
| **`packs/<size>/`** — `dense.bin`, `native_experts.txt`, `index.txt` | **generated from the GGUF** by `tools/iq_pack.py` (or `strata_pack.py` for Q2_0 with AVX-512) |
| **`packs/<size>/tokenizer/`** | **extracted from the GGUF metadata** (`iq_pack` writes it; `strata_tokenizer.py` is the fallback) |
| **`mtp/rt/`** (draft layer) | `tools/mtp_fetch.py` downloads only the ~5 GB of **MTP tensors from the original Qwen checkpoint**, then `mtp_pack.py` + `mtp_rt.py` build it |
| **`expert-profile.bin`**, **`draft_vocab.bin`** | **shipped in the Strata repo** itself (`data/`) |

You produce those files **one of two ways**:

- **Option 1 (easiest):** the built-in wizard in this image (`0.1.40`/`latest` or `0.1.38-setup`) does it — see above.
- **Option 2:** run upstream Strata's own setup **on the host** (Linux `./setup.sh`, Windows `START-HERE.bat`,
  or `docs/AI_SETUP.md`), then mount the resulting `Strata-data`:

      ./setup.sh --family qwen --model IQ2_XS --vision yes \
                 --data-dir /srv/strata-data --no-start --yes

> **Why this image at all?** Upstream Strata ships prebuilt engines for NVIDIA RTX 20-50 and certain AMD
> RDNA cards — **gfx906 (MI50) is not among them**. This image provides a **prebuilt gfx906 engine** with the
> gfx906 ROCm libraries. The model data is produced by the wizard (or the host setup); the engine runs here.

### Required host layout

    /path/to/gguf                 -> /models    (GGUF shards + mmproj/*.gguf)
    /path/to/Strata-data          -> /data      (packs/ + mtp/ + expert-profile.bin)
    /path/to/Strata-data/configs  -> /work      (RW! configurator writes strata-config.json + engine log)

- **`/work` must be writable** — the configurator writes the config and the engine writes its log there.
- **For the setup wizard** `/models` and `/data` must also be **writable** (the wizard downloads and builds into
  them). If you prepare the data on the host (Option 2), you may mount them **`:ro`** — the engine only reads them.

Host requirements (MI50): `/dev/kfd` + `/dev/dri`, user in the `video` and `render` groups.

---

## Vision (images)

The `strata-vision` encoder in this image is a **CPU build** — it works inside the ROCm image (no CUDA). To use it:

1. Put a matching `mmproj-*.gguf` under `/models/mmproj/`.
2. In the configurator, pick the model, then under **2. Image (mmproj)** choose the mmproj entry (`+ images: ...`).
3. **Save and load.** The engine status shows `images: on`; the chat's *Attach* button accepts pictures.

The encoder runs on CPU by design (`"gpu": false`); on gfx906 the GPU vision path isn't available, and CPU encoding is fast enough for still images.

> **The encoder is deliberately an AVX2 build** (`GGML_AVX512=OFF`), and it is the right choice even on machines that *do* have AVX-512 — not just where they don't. This encoder's head size (72) is not a multiple of the AVX-512 vector width (16), so on an AVX-512 build ggml's CPU flash attention falls back from the fast tiled kernel to a per-row one: ~3.3× slower (43.5 s vs 13.3 s for a 1024×1024 image) and 26% off in the embeddings (cosine 0.965). An AVX2 build keeps the tiled kernel (72 % 8 == 0). Upstream is making gfx906-independent CPU encoders turn flash attention off on AVX-512 for the same reason ([PR #1086](https://github.com/Niko1221/Strata/pull/1086)). **Do not rebuild this encoder as "native/AVX-512"** — it would be both slower and less accurate.

---

## Pool (several PCs, one model)

The **Pool** tab splits the model across machines over TCP. Each PC runs a full engine with its own
layers, so cards of different vendors never share a driver. Roles: `off` / `router` (whole model on
each PC, the router hands out requests) / `coordinator` (keeps the head and the first layers) /
`worker` (lends its GPU). Start the worker first — it listens, the coordinator dials in. Roles and
the shared secret are set in the tab and survive a restart. Two gfx906 cards in one machine work
too: pick the card per process.

---

## Ports

    8090  CONFIGURATOR (web) — model / context / key / cache / Help / Pool
    8085  ENGINE (API) — OpenAI: /v1/chat/completions, Anthropic: /v1/messages

    7701  a pool WORKER's listening port (only when its role is set to worker)

Example:

```bash
curl http://<host>:8085/v1/chat/completions \
  -H "Authorization: Bearer 1234" -H "Content-Type: application/json" \
  -d '{"model":"Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS",
       "messages":[{"role":"user","content":"hello"}]}'
```

---

## Notes & limitations

- **Why host libraries, not the base image:** official ROCm images (10.x and 7.2.1) have **no gfx906 kernels** (rocBLAS starts at gfx1010). The image packs the host's gfx906 libraries and the full 210-file `rocblas/library/` (156 gfx906 kernels + 54 generic fallbacks — without the fallbacks a long prompt SIGSEGVs).
- **gfx906-specific:** the engine binary and kernels target gfx906. For gfx11/gfx12 you need a binary built for that arch and its kernels.
- The container needs `--security-opt seccomp=unconfined` (ROCm/kfd requirement).
- **Memory:** the engine holds a large expert arena in RAM. Don't run the host engine and the container at the same time on a small-RAM box — the OOM killer may take down the whole system. Run one engine at a time.
- Docker is neither faster nor slower than the host here: same binary, same ROCm, same card, no GPU passthrough overhead (bind mounts, no cgroup CPU limit).

---

## Benchmarks

Machine: LianLi, Linux 7.0.0-38, 61 GB RAM, ROCm 7.2.1 with the host gfx906 rocBLAS.
MI50 (32 GB, gfx906) + Radeon VII (16 GB, gfx906), same box. Model: Qwen3.8-Flash-Next.
Medians of 4 runs.

| # | master | second card | role of second | quant | ctx | kv | low-RAM | mmap | prompt tok | prefill tok/s | TTFT s | decode tok/s | hit % | PCIe % | build |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | MI50 (0) | Radeon VII (1) | helper | IQ3_XXS | 32000 | int8 | off | off | 11552 | 365.5 | 31.6 | 39.6 | 99.6 | 13.2 | 0.1.40.v2 |
| 2 | MI50 (0) | Radeon VII (1) | helper | IQ3_XXS | 32000 | int8 | off | off | 11552 | 380.0 | 30.4 | 38.7 | 99.6 | 13.2 | 0.1.39.v3 |
| 3 | Radeon VII (1) | MI50 (0) | helper | IQ3_XXS | 32000 | int8 | off | off | 11552 | 140.5 | 82.4 | 36.8 | — | — | 0.1.39.v3 |
| 4 | Radeon VII (1) | MI50 (0) | helper | IQ4_XS | 32000 | int8 | on | on | 775 | — | 16.9 | 30.1 | 91.6 | 48.4 | 0.1.39.v2 |
| 5 | Radeon VII (1) | MI50 (0) | helper | IQ4_XS | 32000 | int8 | on | on | 93 | — | 4.0 | 33.9 | 92.2 | 71.8 | 0.1.39.v2 |
| 6 | MI50 (0) | — | — | IQ3_XXS | 32768 | int8 | off | off | 11552 | 237.9 | 3.9 | 32.4 | — | — | 0.1.35+MMQ+dp4a |
| 7 | RTX 4070 | — | — | IQ3_XXS | 32768 | int8 | off | off | 11552 | 665.7 | 1.2 | 45.1 | — | — | 0.1.35 |

Pool, both cards, TCP over loopback — coordinator Radeon VII (1), worker MI50 (0):

| split | layers coordinator | layers worker | arena MiB | slots | experts on GPU | decode tok/s | tokens / time | windows |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 24 | 0-23 | 24-47 | 17237 | 12288 | 21358 | 42.0 | 91 / 3.1 s | 77 |

Pool flags: `--pool-split 24 --pool-wire f32`, quant IQ2_XS, ctx 8192, spec 2, `--vram-reserve-mib 1024`.
The RTX 4070 rows are the same model on a different card, for reference.

## Tags / engine

- Engine **v0.1.40** (gfx906 build: 3 compile fixes for the gfx906 path + `v_dot4_i32_i8` for `__dp4a`),
  `--spec 3` speculative decoding, MTP, `--kv int8`.
- Server hotfixes from upstream **v0.1.40.1** and the **network pool** (`serve/pool.py`,
  `serve/route.py`, Pool tab) — layer split across PCs, `--pool-listen` / `--pool-peers`.
- Measured on MI50 32 GB (this image, MI50 master + Radeon VII helper, IQ3_XXS, 11552-token prompt):
  ~380 tok/s prefill, ~39-40 tok/s decode. The gfx906 `dp4a` path adds ~2-4% decode over the portable loop.
- **VRAM reserve is per card.** The configurator detects which card drives the display
  (`/sys/class/drm/*/status == connected`) and keeps the reserve there — that card keeps
  `--vram-reserve-mib` free (so the desktop and image rendering stay alive); cards with no monitor are
  filled to the edge (`--vram-reserve-later-mib 0` for a split). Helper cards have no reserve flag, so
  when the helper drives the display the configurator computes an explicit slot count instead of `auto`.

Strata on GitHub: https://github.com/Niko1221/Strata
