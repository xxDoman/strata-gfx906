# Operations — running, configuring and feeding this image

Long form of what used to be on the repository's front page: setup, the configurator, the host layout,
the vision encoder, the network pool, the ports and the traps. The front page is now a card that links
here. **These sections were moved from `README.md` verbatim** (same wording, same numbers); only the
links were made absolute and the tag-specific facts were pointed at the engine pages —
[engine index](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/README.md).

The image described here is the published one: `xxdoman/strata-mi50:0.1.43.1` / `:latest`. The
`0.1.44.1.b` ... `.g` images built locally have their own pages in that index.

---

## What is in this image

- **Engine v0.1.43.1** (newest tag, `latest`) — a hotfix over 0.1.43;
  [docs/image-history.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/image-history.md) says what reaches gfx906 and what does not (the adaptive
  overlap back to opt-in, long prompts on Windows and SATA SSDs, two-card batch serving, AMD multi-slot
  memory faults, the server). The gfx906 **build** fixes are upstream (commit `a732a19`, verified on
  MI50 32 GB / gfx906 / ROCm-HIP) and dp4a (`v_dot4_i32_i8`) is in and works. **This tag carries two
  patches of ours and one configurator fix:** the **rocBLAS solution table** in the engine, the community
  benchmark's **report header on AMD** in the tools, and a per-card **VRAM reserve floor** on a split —
  all three below. On gfx906 the engine behaves as 0.1.42 in the decode path: upstream's 0.1.43 speed
  work is gated to gfx1200/gfx1201 and their own source says so (*"every other AMD part (gfx11, gfx906,
  ...) keeps its earlier behaviour"*). Configurator, Help tab, **both** benchmark tabs (the older
  `strata-bench.py` and the new community `strata_bench.py`) and per-card VRAM reserve in every current tag.
- **rocBLAS solution table for gfx906** — the prompt path asks a table for the fastest rocBLAS kernel
  per GEMM shape instead of taking rocBLAS's own pick (PR #981's own measurement on gfx1030: up to 6×
  slower for some shapes). Measured on this box: **prefill +9.1%** (IQ3_XXS, split MI50+Radeon VII,
  ctx 65536, 225 W, median of 3, 32k prompt). It is off unless the config turns it on — see below.
- **Two test toggles in the configurator** (Configuration tab): the **rocBLAS table** (off by default)
  and the **expert tail skip** (`STRATA_ROUTE_TAIL_SKIP`, on by default in upstream 0.1.42). Both are
  environment-only switches — the engine has no CLI flag for either — and the launcher writes both
  **explicitly in both directions** (`1`/`0`, path/empty), so unchecking really turns them off, even on
  an image that has the keys baked in its `ENV`. Both need an engine restart; the table also switches
  the prompt path to FP16, which changes prompt rounding slightly.
- **Expert profile is per artifact.** The Coder build of the model has 256 experts per layer
  (48×256), the plain one 512 (48×512); the wrong profile is a hard engine stop, not a slowdown. The
  configurator picks the profile from the pack name (`expert-profile-coder.bin` vs `expert-profile.bin`).
- **Benchmark tab** — runs Strata's own `strata-bench.py` from inside the image. A small wrapper
  adds the `Authorization` header (your API key is passed through the environment, never `argv`),
  and the engine-address field fills itself from the live config.
- **Network pool** (`serve/pool.py`, `serve/route.py`, the **Pool** tab) — split the model across
  several PCs over TCP, the way `llama.cpp` RPC does, but moving *layers* instead of computations.
  Each PC runs a full engine with its own layers, so cards of **different vendors never share a
  driver** — a Radeon and an MI50 on one machine, or a laptop over Wi-Fi. Roles are set in the
  **Pool** tab: `off` / `router` / `coordinator` / `worker`. Default role is `off`.

  ⚠ **Test phase.** The network pool ships **only in the `0.1.40.1-pool` tag** (a fork built on
  engine 0.1.40); it is **not** in `0.1.43.1` / `latest`, whose engine has no `--pool-listen`. The link
  layer is proven GPU-less (`strata-pool-link-test`), but a full two-machine run is still ahead — treat it
  as experimental, not production. Note: the engine flag `--pool-tasks` is unrelated (it is the
  **CPU** expert pool for MoE, not the network).
- **Help tab** in the configurator — the engine's full flag reference, captured from the binary at
  image build time, so it updates itself with every release.

### The gfx906 build fixes

The gfx906 gates (`src/core/vmm.cpp`, `src/core/mtp.cpp`, `src/kernels/cuda/fused_gr.cu`) and the
`cudaEventBlockingSync` mapping landed upstream — first in **0.1.40.2**, completed in **0.1.41**
(commit `a732a19`), so from 0.1.41 the tree **builds** for gfx906 with no patches. dp4a for gfx906
(`v_dot4_i32_i8`) is also upstream (in `strata_hip.h`) and **works**: measured A/B decode
**+12..17%**, prefill unchanged. PR #1083 (build fix) and #1084 (dp4a) were ours; #1084 turned out
to be a **no-op** on gfx906 (the `intrinsics.hpp` path is not compiled there — the binary is
byte-identical with and without it).

### The rocBLAS solution table — our engine patch

That "no patches" above is about **building**. One **feature** still needs a patch, and no upstream
release has it:

- **PR #981** (Vop3p) **proposed** a reader for a per-shape rocBLAS **solution table** for the prompt's
  16-bit GEMMs (its own title scope: gfx103x, RDNA3). **That PR is closed and was never merged**, so
  **none of this exists in the upstream engine** — no 0.1.43, no `main`. The code exists only as that
  PR's diff, and this image applies it as a patch. On top of that the reader is gated on
  `STRATA_ENABLE_HIP` — the **wave32 RDNA** backend — while this build sets `STRATA_HIP_GFX906`, so
  `cmake/hip_backend.cmake` never runs, `STRATA_ROCBLAS_AVAILABLE` never reaches `gemm.cu`, and even a
  patched tree could compile the reader out. The table would then sit in the image unused, with no error
  and no log line: a silent no-op, which is worse than a build break.
- What this image adds: the **PR's diff**, rocBLAS **detection inside the gfx906 block**, a **widened
  gate** (`STRATA_ENABLE_HIP OR STRATA_HIP_GFX906`) and a **table for this card**. The engine then logs
  `prefill gemm: rocBLAS tuning enabled (103 rows, 78 with a solution, gfx906, rocBLAS 5.2.0.dabb6df2b9)`.
- The table itself was produced with the tuning tool from PR #981's diff (`tools/hip/tune_rocblas`,
  not in upstream main either) on this card, and ships at
  `/opt/strata/tools/hip/gfx906-rocblas-5.2.0.dabb6df2b9.txt`. The file name must match the
  rocBLAS version in the image; a mismatch logs `architecture mismatch` and falls back to rocBLAS's
  own choice.
- **Credit, precisely:** the mechanism, the reader and the tuning tool are **Vop3p's**, from PR #981,
  which upstream has **not** merged. Ours are the gfx906 gate fix and the table for this card — nothing
  here is upstream's work.
- **Why the table is per-image and not upstream:** a solution table is **per card** — gfx906 solutions
  mean nothing on an RDNA3 card and vice versa. Upstream's design already takes the table from a **path
  in the config** (`STRATA_ROCBLAS_TUNING`), so the artifact belongs with whoever owns the card, not in
  the engine. This image ships the one table for **this** card and no other.

### The community benchmark's report header on AMD — our tools patch

Upstream's community script (`tools/strata_bench.py`, new in 0.1.43) publishes `GPU driver: not read` and
a generic `AMD Radeon Graphics` on AMD hardware, and both causes are in that script: the `gpu_driver`
field picks `gpus[0]["driver"]`, which on the ROCm path is `None`, so the `rocm_driver` read a few lines
above it is discarded; and the card name comes straight from `rocm-smi`, where the amdgpu driver carries
no marketing name for the MI50 (`0x66a1`). This image applies `bench-patches/0001-gfx906-gpu-metadata.patch`
on top of the upstream file — **report header only, nothing in the measurement path** — so a report made
here reads `AMD Instinct MI50 32GB + AMD Radeon VII 16GB`, `GPU driver: 7.0.0-38-generic`, and names its
results folder `2x-instinct-mi50-32gb-...` instead of `2x-unknown-...`. The one-line driver fix is
proposed upstream as [#1974](https://github.com/Niko1221/Strata/pull/1974); if it lands, this patch goes
away. The upstream file in this repo stays byte for byte theirs, so the patch is easy to audit and to
drop.

### About the 0.1.40.1 naming

Upstream's 0.1.40.1 hotfix does **not** bump the version in `CMakeLists.txt` — the engine still
reports `0.1.40`. That is why older images keep the engine tag and add a suffix instead of moving
the engine version.

## Two ways to get the model data

### Option 1 — the built-in wizard (easiest, in `0.1.43` / `latest`, `0.1.41`, `0.1.40.1-pool` and `0.1.38-setup`)

No host steps, no scripts. Open **http://<host>:8090**, use section **0. Setup**: pick a family and a
size (or **Custom HuggingFace repo…** and paste any `user/repo`), say whether you want images, click
**Download and prepare** — the container downloads the GGUF and builds the pack, the tokenizer and the
MTP draft layer inside itself — then pick the model and **Save and load**.

Sources the wizard offers: `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF` (GSQ-RCO),
`ukisai/Swift-1.5-Qwen3.8-Flash-Next-GSQ-RCO-GGUF`, `ISTA-DASLab/...-Coder-GGUF`,
`orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF`, `unsloth/Qwen3.8-Flash-Next-GGUF` (experimental) —
or any repo id you paste.

`--compat-bf16` is applied automatically for the fine-tunes that need it (Uncensored, Unsloth).
The Q2_0 AVX-512 repack is used only when the CPU actually has AVX-512 (everything else uses the
plain `iq_pack`, which only needs AVX2) — same rule as upstream setup.

Progress and the live tool log are in the page, and it is **resumable** — restart it and the downloads
continue. It needs `/models` and `/data` mounted **writable**, and pulls a one-time ~70 GB (up to ~350 GB
for a full BF16 size).

> The wizard does **not** run upstream `setup.py`: on Linux that would fetch its own prebuilt CUDA engine
> and clash with the gfx906 engine here. It runs only the data tools (`iq_pack.py`,
> `strata_tokenizer.py`, `mtp_fetch.py`, …), which build the same `Strata-data` layout.

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
    devices: [/dev/kfd:/dev/kfd, /dev/dri:/dev/dri]
    device_cgroup_rules: ['c 226:* rmw']
    ports: ["8085:8085", "8090:8090"]        # engine (API + chat) / configurator
    ulimits: {memlock: -1}
    security_opt: [seccomp=unconfined]
    environment:
      - HSA_OVERRIDE_GFX_VERSION=9.0.6
      - LD_LIBRARY_PATH=/opt/rocm/lib
      - CONFIG=/work/strata-config.json
      # - ROCR_VISIBLE_DEVICES=0               # multi-GPU: which card (index from rocm-smi)
    volumes:
      - /path/to/gguf:/models                # models + mmproj (RW for the wizard; :ro after)
      - /path/to/Strata-data:/data           # packs/ + mtp/ + expert-profile.bin (RW for the wizard)
      - /path/to/Strata-data/configs:/work   # RW — the configurator writes the config here
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

## How it works

`strata-launcher.py` is PID 1: it runs the **configurator (:8090)** and manages the **engine (:8085)**
(OpenAI/Anthropic-compatible API + built-in chat) as a child process.

- The config lives on a **volume** (`/work/strata-config.json`), written by the configurator, and
  **survives image updates**. Config present -> the model loads on start (autostart); no config -> only
  the configurator starts.
- Model, context, key, expert cache, VRAM reserve, MTP drafts (`--spec`) and the engine port are all
  changed on **:8090** — no docker restart, no image rebuild.

---

## Configuration

### Configurator UI (:8090)

1. **Model** — pick a detected GGUF (its name is paired with a matching *pack*).
2. **Image (mmproj)** — optional; a matching `mmproj-*.gguf` enables vision.
3. **AMD card** — the GPU (`rocm-smi`) or "All cards".
4. **Settings** — context (default **65536**), API key (**1234**), expert cache (`auto` or a number),
   VRAM reserve, engine port, **MTP drafts** (`--spec`, default 3) and **spec min-p** (0.9). On the MI50,
   `--spec 3` is measurably faster than 2. The two **test toggles** (rocBLAS table, expert tail skip)
   sit in this panel.
5. **Save and load** — writes the config and starts the engine.

While the engine runs, **Engine state** shows a clickable server link (`http://<host>:<port>/`) built from
the browser host and the config port, so the built-in chat/API opens from another PC on the LAN too.
The UI is **English by default** with an **EN / PL** toggle (remembered in `localStorage`).

### Environment variables

`MODELS_DIR` (`/models`), `DATA_DIR` (`/data`), `CONFIG` (`/work/strata-config.json`, must be RW),
`WEB_PORT` (`8090`), `ENGINE_PORT` (`8085`) — all changeable. `HSA_OVERRIDE_GFX_VERSION=9.0.6` is
**required** for MI50/gfx906; `STRATA_MODE=local` keeps the launcher managing the engine as a child;
`ROCR_VISIBLE_DEVICES` selects the card for multi-GPU (index from `rocm-smi`).

### Config file (`/work/strata-config.json`)

Written by the configurator — you normally never edit it by hand. Key fields: `args` (the engine flags:
`--pack`, `--native`, `--ple-gguf`, `--expert-cache`, `--mtp`, `--max-context`, `--kv`, `--spec`,
`--vram-reserve-mib`), `vision` (`"gpu": false` = the encoder on CPU), `env` (the toggles above),
`api_key`, `port`, `model_name`, `tokenizer`, `lib_dirs`.

---

## Where the model files come from

This image ships **only** the engine (prebuilt gfx906 binary + ROCm 7.2.1), the configurator and — in
`0.1.43`/`latest` and `0.1.38-setup` — the **data tools**. The model and the data it consumes are **not**
in the image and are **not** taken from anyone's personal folder:

- **Model GGUF and `mmproj/`** — HuggingFace, from the repo you pick (the list above / the wizard).
- **`packs/<size>/`** (`dense.bin`, `native_experts.txt`, `index.txt`) and its **tokenizer** — generated
  from that GGUF by `tools/iq_pack.py` (`strata_pack.py` for Q2_0 with AVX-512).
- **`mtp/rt/`** (the draft layer) — `tools/mtp_fetch.py` downloads only the ~5 GB of **MTP tensors from
  the original Qwen checkpoint**, then `mtp_pack.py` + `mtp_rt.py` build it.
- **`expert-profile.bin`**, **`draft_vocab.bin`** — shipped in the Strata repo itself (`data/`).

You produce those files **one of two ways**:

- **Option 1 (easiest):** the built-in wizard in this image (`0.1.43`/`latest` or `0.1.38-setup`) does it — see above.
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

## Vision (images)

The `strata-vision` encoder in this image is a **CPU build** — it works inside the ROCm image (no CUDA).
Put a matching `mmproj-*.gguf` under `/models/mmproj/`, then in the configurator pick the model and under
**2. Image (mmproj)** choose the `+ images: …` entry and **Save and load**; the status shows `images: on`
and the chat's *Attach* button accepts pictures. The encoder runs on CPU by design (`"gpu": false`) — on
gfx906 the GPU vision path is not available, and CPU encoding is fast enough for still images.

> **The encoder is deliberately an AVX2 build** (`GGML_AVX512=OFF`), on every machine: its head size (72) is not a multiple of the AVX-512 vector width (16), so an AVX-512 build drops ggml's CPU flash attention to a per-row kernel — **~3.3× slower** and 26% off in the embeddings. **Do not rebuild it as "native/AVX-512".**

---

## Pool (several PCs, one model) — test phase

> ⚠ **Experimental.** The network pool is **only in the `0.1.40.1-pool` tag** (fork on engine
> 0.1.40). The `0.1.43` / `latest` engine has no `--pool-listen`. The link layer is proven GPU-less
> (`strata-pool-link-test`), but a full run across two machines is still ahead. Not for production.

The **Pool** tab splits the model across machines over TCP. Each PC runs a full engine with its own
layers, so cards of different vendors never share a driver. Roles: `off` / `router` (whole model on
each PC, the router hands out requests) / `coordinator` (keeps the head and the first layers) /
`worker` (lends its GPU). Start the worker first — it listens, the coordinator dials in. Roles and
the shared secret are set in the tab and survive a restart. Two gfx906 cards in one machine work
too: pick the card per process.

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

- **Why host libraries:** official ROCm images (10.x and 7.2.1) have **no gfx906 kernels** (rocBLAS starts at gfx1010). The image packs the host's gfx906 libraries and the full 210-file `rocblas/library/` (156 gfx906 kernels + 54 generic fallbacks — without the fallbacks a long prompt SIGSEGVs).
- **gfx906-specific:** the engine binary and kernels target gfx906. For gfx11/gfx12 you need a binary built for that arch and its kernels.
- The container needs `--security-opt seccomp=unconfined` (ROCm/kfd).
- **Memory:** the expert arena lives in RAM. Never run the host engine and the container at once on a
  small-RAM box — the OOM killer can take the system down.
- **A power cap is a ceiling, not a budget** — and it leaks. With `rocm-smi --setpoweroverdrive 85`
  verified in `power1_cap`, the cards still overshoot in peaks: on this box the MI50 ran at a median
  84 W but peaked at **127 W** (39% of samples above the cap) and the Radeon VII at a median 56 W,
  peaking at **132 W** (26% above) — about **1.5× the cap**, at 66 °C / 47 °C, so it is firmware, not
  thermals. Never compare two machines' "W" settings as if they were equal budgets; compare **measured
  draw**.
- **SMI and UPP are two different limits — and only one of them is shown by `rocm-smi`.** This box runs
  the SMI socket cap at its **default** (MI50 225 W, Radeon VII 250 W, and 85 W where the table above
  says so), but the **UPP** limit `TdcLimitGfx` is set to **150** on the MI50 (the Radeon VII: 330).
  `rocm-smi` displays the socket cap only, and `--resetpoweroverdrive` does **not** restore the UPP
  value. So our numbers at "225 W" are not a stock card's numbers. Read both limits before comparing:
  `sudo upp -p /sys/class/drm/cardN/device/pp_table dump | grep -iE 'TdcLimit|SocketPowerLimit'`.
  If your card is stock you will likely be **faster than this table** — now you know why, and it is not
  a different engine.
- **Read the draw from `power1_input`, not `power1_average`.** On gfx906 the latter does not exist and
  returns `0 W`, which reads convincingly as "the card sat idle for the whole run".
- Docker adds no GPU overhead here — same binary, same ROCm, same card.

## Benchmarks (moved to their own page)

The measured tables that used to sit on the front page — this box's community-suite rows, the rocBLAS
table's own worth, the pool row, and the power/driver caveats — are on [benchmarks](https://github.com/xxDoman/strata-gfx906/blob/master/docs/benchmarks.md).
The running record of every number, each with its regime, stays in
[measurements](https://github.com/xxDoman/strata-gfx906/blob/master/docs/measurements.md).

## License

The packaging (Dockerfiles, `docker-compose.yml`, the configurator glue and the docs) is **MIT** — see
`LICENSE` in the repository. It redistributes the **Strata engine**, also **MIT**,
`Copyright (c) 2026 Niko1221 and the Strata contributors` (<https://github.com/Niko1221/Strata>); MIT
requires the original copyright notice to travel with the binary, and it is kept verbatim in `LICENSE`.
The base ROCm images and the model weights (downloaded separately, not in this image) keep their own
licenses.
