# Strata gfx906 — MI50 / MI60 / Radeon VII

**Docker image that runs the [Strata](https://github.com/Niko1221/Strata) engine (Qwen3.8-Flash-Next) on AMD Instinct MI50 / MI60 and Radeon VII (gfx906, wave64) — with a built-in web configurator and a one-click setup wizard.**

One image = **engine + server + configurator + setup wizard**. Pick a model in the browser, click once, and you get an OpenAI/Anthropic-compatible API and a chat UI — no host steps, no manual pack building.

- Image: [`xxdoman/strata-mi50`](https://hub.docker.com/r/xxdoman/strata-mi50) (tags `latest`, `0.1.39`)
- Engine build: Strata **v0.1.39**, gfx906 backend (`-DSTRATA_HIP_GFX906=ON`), ROCm 7.2.1
- Why this image exists: upstream Strata ships prebuilt engines for NVIDIA and RDNA only — **gfx906 has no ready-made engine**, so this image provides one (built from source with the gfx906 path) plus the gfx906 ROCm libraries and rocBLAS kernels.

---

## Requirements

| | |
|---|---|
| GPU | AMD Instinct MI50 / MI60 or Radeon VII — **gfx906**, wave64 |
| Host | `/dev/kfd` + `/dev/dri`, user in the `video` and `render` groups |
| RAM | ~32-64 GB (the engine holds a large expert arena in RAM) |
| Disk | ~70 GB for the model data (see *Getting a model*) |

---

## Quick start

### docker compose

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
      - ~/strata/gguf:/models                  # GGUF shards + mmproj (RW for the setup wizard)
      - ~/strata/Strata-data:/data             # packs/ + mtp/ + expert-profile.bin (RW for the wizard)
      - ~/strata/Strata-data/configs:/work     # RW — the configurator writes the config here
```

```bash
docker compose up -d
```

> **Paths.** Data goes in **your own home** (`~/strata/`) — no `sudo`, no shared folder. On a normal
> host `docker compose` expands `~` for you.
>
> **In Portainer it does not.** Portainer passes volumes through verbatim, so `~/strata/gguf` becomes the
> literal path `/strata/gguf` (or `/test` if you wrote `~test`) — a root folder, not your home. **In
> Portainer always use absolute paths:** `/home/<your-user>/strata/gguf` (find yours with `echo $HOME`).

### docker run

```bash
docker run -d --name strata --restart unless-stopped \
  --shm-size 16g \
  --device /dev/kfd --device /dev/dri --device-cgroup-rule 'c 226:* rmw' \
  -p 8085:8085 -p 8090:8090 \
  --ulimit memlock=-1 --security-opt seccomp=unconfined \
  -e HSA_OVERRIDE_GFX_VERSION=9.0.6 -e LD_LIBRARY_PATH=/opt/rocm/lib \
  -v "$HOME/strata/gguf:/models" \
  -v "$HOME/strata/Strata-data:/data" \
  -v "$HOME/strata/Strata-data/configs:/work" \
  xxdoman/strata-mi50:latest
```

Open **http://\<host\>:8090** — the configurator.

---

## The web configurator (port 8090)

Everything is done in the browser. Sections:

**0. Setup (get a model)** — for a fresh install. Pick a **model family** and a **size** (every quant shows its source repo and size), or **Custom HuggingFace repo…** and paste any `user/repo`; the wizard lists its `.gguf` groups. Click **Download and prepare**: the container downloads the GGUF from HuggingFace, then builds the pack, the tokenizer and the MTP draft layer — all inside the container. Progress and the live tool log stream in the page. It is **resumable** (restart and it continues).

Families with their source repos:

| Family | HuggingFace repo |
|---|---|
| Qwen3.8-Flash-Next (GSQ-RCO) | `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF` |
| Swift 1.5 | `ukisai/Swift-1.5-Qwen3.8-Flash-Next-GSQ-RCO-GGUF` |
| Coder | `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF` |
| Uncensored | `orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF` |
| Unsloth (experimental) | `unsloth/Qwen3.8-Flash-Next-GGUF` |
| **Custom** | any `user/repo` you paste |

**1. Model** — pick one of the detected models (a model is only usable when a matching *pack* exists; the wizard builds it).

**2. Image (mmproj)** — optional. Pick a matching `mmproj-*.gguf` to enable **image input** (text-only vs. +images). The encoder runs on **CPU** (correct for gfx906).

**3. AMD card** — the GPU (`rocm-smi`) or "All cards".

**4. Settings** — context (default **65536**), API key (default **1234**), expert cache (`auto` or a number), VRAM reserve (MiB), engine port, **MTP drafts** (`--spec`, default 3) and **spec min-p** (`--spec-min-p`, 0.9).

**Save and load** writes the config and starts the engine.

The UI is **English by default**; **EN / PL** toggle top-right (remembered per browser).

---

## Autostart: restarting the container brings the model back

The config lives on a **volume** (`/work/strata-config.json`), so it **survives restarts and image updates**.

- **Config present → the model loads automatically** when the container starts (autostart). Just `docker restart strata` (or a host reboot) and the last model comes back by itself.
- **No config → only the configurator starts**; the engine waits until you pick a model and click **Save and load**.

You normally never edit the config by hand — the configurator writes it.

---

## Chatting with the model

Once the model is loaded, the **Engine state** section shows a clickable link to the engine
`http://<your-host>:<engine-port>/`. Open it for the **built-in chat** (accepts images when vision is on).

The engine speaks the OpenAI and Anthropic APIs. Use the API key in the header — **the default key is `1234`**:

```bash
# OpenAI
curl http://<host>:8085/v1/chat/completions \
  -H "Authorization: Bearer 1234" -H "Content-Type: application/json" \
  -d '{"model":"Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS",
       "messages":[{"role":"user","content":"hello"}]}'

# Anthropic
curl http://<host>:8085/v1/messages \
  -H "x-api-key: 1234" -H "anthropic-version: 2023-06-01" -H "Content-Type: application/json" \
  -d '{"model":"Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS","max_tokens":128,
       "messages":[{"role":"user","content":"hello"}]}'
```

### API key

- **Default: `1234`** (built into the container, used by the built-in chat and every API call).
- **Where to change it:** the configurator (:8090) → **4. Settings → API key** → type a new key →
  **Save and load**. The engine restarts with the new key; the config on the volume keeps it, so it also
  survives a container restart.
- Any client (OpenAI SDK, Anthropic SDK, Codex, `curl`, another app) must send the **same** key.
- The built-in chat uses the key from the config automatically — nothing to set there.

> **Before exposing the ports to a network** (not just `localhost`), set a long random key. With a
> trivial key like `1234` anyone on the LAN can use your model. There is no other access control.

---

## Changing the model or settings

1. Open the configurator (**:8090**).
2. Change the model / context / key / cache / MTP drafts and click **Save and load**.
3. The engine is stopped and restarted with the new config.

If you want to stop the engine without changing anything, use **Stop engine** on the page; **Save and load** starts it again. A container restart after that brings the same (new) model back automatically.

---

## Vision (images)

The image encoder (`strata-vision`) is a **CPU build** — it works inside the ROCm image (no CUDA). To use it:

1. Put a matching `mmproj-*.gguf` under `/models/mmproj/` (the setup wizard downloads it if you tick "images").
2. In the configurator, pick the model, then under **2. Image (mmproj)** choose the mmproj entry.
3. **Save and load.** The status shows `images: on`; the chat accepts pictures, and the API takes image content.

CPU encoding is fast enough for still images (a 2-second answer for one photo on an MI50).

---

## Measured performance (MI50 32 GB)

Strata 0.1.39, IQ2_XS, 4K prompt, 256-token decode, `--spec 3`, expert cache auto:

| build | prefill | decode |
|---|---|---|
| **0.1.39 (this image)** | 293 tok/s | **42.5 tok/s** |
| 0.1.38 + local gfx906 patches | 294 tok/s | 32.4 tok/s |

In-container (Q2_0): 351 tok/s prefill, 36.8 tok/s decode, ~94% expert-cache hit, MTP 4/4 drafts accepted. Correctness `17*23 → 391`. Numbers drift a few % between sessions — measure interleaved for comparisons.

---

## Notes / limitations

- **gfx906-only.** The engine binary and kernels target gfx906; other archs need their own build.
- The container needs `--security-opt seccomp=unconfined` (ROCm/kfd requirement).
- **One engine at a time.** The engine holds a large expert arena in RAM — don't run two on a small-RAM box.
- **Build note (for contributors):** the binary is built *inside* the ROCm 7.2.1 image (glibc 2.39). A binary built on a newer host glibc will not load. `cudaFuncSetAttribute` had to be a template function, not a macro — fixed upstream in [PR #808](https://github.com/Niko1221/Strata/pull/808).

---

## Troubleshooting

**`docker pull` fails with `408 Request Timeout` / `429` / `502`**
The image is fine (2.23 GB compressed; the registry digest is correct). These are **network/registry timeouts on large layers**. Docker resumes already-downloaded layers, so just repeat:
```bash
docker pull xxdoman/strata-mi50:latest      # run it 2-3 times — each attempt resumes
# or pull by digest (skips the tag lookup):
docker pull xxdoman/strata-mi50@sha256:6e65ddf1a5b284f356678728c936fa14e650405bec6dfb19984c794e8a7dad1a
```
In **Portainer**, the pull window has its own timeout and tends to hit 408 on big layers — pull from the **CLI** first, then Deploy in Portainer (the image is already local).

**Data landed in `/test` (or `/strata`) instead of my home** — you wrote `~...` in a **Portainer** stack. Portainer does not expand `~`. Use the absolute path `/home/<your-user>/strata/...`, then redeploy.

**Container starts, page shows only the configurator, no model** — normal with no config on the volume. Pick a model in section **1** and **Save and load** (build the data first in **0. Setup** if the list is empty).

**Restart does not bring the model back** — the config must be on the mounted `/work` volume (env `CONFIG=/work/strata-config.json`). If you changed volume paths, the old config is elsewhere.

**`HTTP 000` / connection refused on :8085 right after start** — the engine takes ~1-2 minutes to load the model. The configurator shows the live engine log; wait for `ready`.

**Engine exits with `GLIBC_2.43 not found`** — you are running an engine built on a newer host glibc. Use the published image as-is (built on ROCm 7.2.1, glibc 2.39); do not rebuild the binary on a newer host.

---

## Portainer stack

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
      - "8085:8085"
      - "8090:8090"
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
    volumes:
      - /home/<your-user>/strata/gguf:/models
      - /home/<your-user>/strata/Strata-data:/data
      - /home/<your-user>/strata/Strata-data/configs:/work
```

> In Portainer, `~` is **not** expanded — use the absolute path (for you it is `/home/doman/strata/...`).

Strata on GitHub: https://github.com/Niko1221/Strata
