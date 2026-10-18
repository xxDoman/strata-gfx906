# Strata engine for AMD gfx906 — MI50 / MI60 / Radeon VII

Prebuilt, self-contained Docker image of the [Strata](https://github.com/Niko1221/Strata) MoE engine for AMD
**gfx906** cards, with a browser configurator. Published as
[`xxdoman/strata-mi50`](https://hub.docker.com/r/xxdoman/strata-mi50):
`docker pull xxdoman/strata-mi50:latest`.

One image = engine + server + configurator (**:8090**). No model is baked in — models, packs and the MTP
draft live on the host and are mounted. The base is ROCm 7.2.1 with the host's **gfx906 libraries and
rocBLAS kernels** packed in: official ROCm images ship rocBLAS only from gfx1010, so without them these
cards have no GEMM code. Strata is MIT, so repackaging is allowed (the copyright notice travels in
`LICENSE`).

**Cards:** AMD Instinct **MI50 / MI60** and **Radeon VII** (Vega 20, `gfx906`). The engine binary and its
kernels target gfx906 — for gfx11/gfx12 you need a binary built for that architecture.

**Not this repository:** the optimized **Ollama** images for the same cards are a different project, and
`milpster/gfx906-llama-cpp` / `mixa3607/ML-gfx906` are unrelated llama.cpp work. Plain facts for
assistants, with the traps: [llms.txt](https://github.com/xxDoman/strata-gfx906/blob/master/llms.txt).

---

## The released engine: 0.1.45 (`latest`)

| | |
| --- | --- |
| Image tag | `xxdoman/strata-mi50:0.1.45`, alias `:latest` (7.60 GB) |
| Manifest digest | `sha256:1314986027105b29b562a4b2a5a70deac73b000948e31e70d59263f9c7ce4daa` |
| Engine binary sum | `sha256 14a4a00e436a53041bd1fda7634a36be26ed07911692d5b2e3a119ef907c2797` (34 119 064 B) |
| Engine reports | `engine=0.1.45` |
| Published tags | `0.1.45` and `latest` — one image, one digest (published 2026-10-18) |

**What it is.** Upstream tag **v0.1.45** — Qwen3.6-35B-A3B reads pictures, `--parallel` up to 8 slots, new
decode kernels, a bigger default prompt chunk (4096/2048/1024 by free VRAM) — plus **7 of our gfx906/q36
patches, E1–E7**: attention buffers sized from the model's geometry, `ident`/`rinv` slack, Q4_K/Q6_K accepted
by `upload_f32`, Q4_K down experts, the NVFP4 W4A4 unit gated out, the cuBLAS name shims, an `f16kq` stub and
`nextn_predict_layers` treated as optional. The server and tokenizer come from v0.1.45; the configurator is the
0.1.44.1 line. The engine is a **portable build** (`STRATA_PORTABLE=ON`), so it does not trap an older CPU.

**What it is worth here** (80 W cap on the MI50, medians of 3, `--tg 128`): Ornith-1.5-35B-A3B Q4_K_M on the
`q36` path **697 / 637 / 580** tok/s prefill and **54.7 / 54.5 / 54.0** decode at 2K / 8K / 16K; Qwen3.6-35B-A3B
Q6_K **574 / 552 / 507** and **53.2 / 53.9 / 53.1**; Qwen3.8-Flash-Next IQ2_XXS on the pack path (both cards,
low-RAM off, kv q4_0) **356 / 447 / 465** and **38.7 / 35.9 / 35.9**. Against 0.1.44.1 on the same config the
`q36` path is **+15 % decode** at **−8…−10 % prefill**; the pack path is unchanged. Those are time measurements
only — no token-for-token check was made.

**What it does not have.** The int8 KV cache on the `q36` path (that was the 0.1.44.1 line) and the `--parallel`
/ image switches in the configurator (engine and server have them; the form does not expose them).

**Full page:** [docs/engines/0.1.45.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.45.md)
· [wiki](https://github.com/xxDoman/strata-gfx906/wiki/Engine-0.1.45)

---

## The previous release: 0.1.44.1

| | |
| --- | --- |
| Image tag | `xxdoman/strata-mi50:0.1.44.1`, alias `:latest` (7.59 GB) |
| Image sum | `sha256:e2a48af744d4fe9e0e6a7ff1304ba87f406bb9f6f0e295b431c73cb8aad0c53e` — one image behind all three published tags |
| Engine binary sum | `sha256 bcd88b367a4c709cf09203ed0687bb3992cbc68e8b0c91216627a277b45f2afb` |
| Engine reports | `engine=0.1.44.1` |
| Published tags | `0.1.44.1`, `latest` and `0.1.44.1.cpuid` — three names, one manifest digest |

**What it is.** Upstream tag **v0.1.44.1** plus **11 of our gfx906/q36 patches**, an **int8 KV cache** on
the `q36` path, the **gfx906 rocBLAS solution table** and configurator work. There is **no separate
"plain" image and "portable" image**: the portable CPU build **is** the release, and `.cpuid` is simply an
extra alias so that the person who reported issue #2 can pin that exact build. `0.1.44.1.h` was never
published. The per-card **VRAM reserve floor** on a layer split ([issue
#1](https://github.com/xxDoman/strata-gfx906/issues/1)) and the community benchmark's **report header on
AMD** (report header only, nothing in the measurement path) carry over from the previous release.

**What it fixes.** This is the release that fixes upstream **issue #2** — a **SIGILL** ("illegal
instruction") crash on hosts whose CPU has no AVX-VNNI (Xeon E5-26xx v3/v4, Sandy/Ivy Bridge, AMD Zen 1-3).
Earlier images were built with `-march=native` on a machine that has AVX-VNNI, so the compiler picked the
`__AVXVNNI__` branch of `ggml_vec_dot_q8_0_q8_0` at build time, with no CPUID check. Symptom on an affected
host: the model loads, the server starts, and on the **first generated token** the process exits with code
**-4**; the launcher then suggests it ran out of memory, while `dmesg` says `trap invalid opcode`. It is
not memory, it is a missing instruction. The `ggml-cpu` backend is now built at a **base AVX2 target**
(`-DSTRATA_PORTABLE=ON`, with `-DGGML_CPU_ALL_VARIANTS=OFF`). The engine's own VNNI kernels remain and are
still selected at run time by `cpu_avxvnni_ok()`, so a machine that does have AVX-VNNI keeps using VNNI for
the expert path.

**The int8 KV path on `q36`**, a separate change riding in the same image: resident experts **192 → 229
of 256**, CPU hybrid **64 → 27**, free VRAM at start **20.75 → 24.38 GiB**, prefill **+3.2…+5.1 %** at an
80 W cap. The engine stays bit-exact deterministic: KL **0.00138** on a real 265-token prompt, top-1
**93.8 %**.

**How it was proven** — three independent legs. **(i)** The static ISA guard
(`tools/check_isa_guard.py`) reports **0 violations**: no AVX-512/AVX-VNNI/VAES/GFNI/SHA instruction is
reachable without an internal CPU check, and the violation it used to report (`iqp_decode_panel_8`, GFNI)
is gone. **(ii)** Under `qemu-x86_64 -cpu Haswell` the old binary dies with SIGILL while the new one runs
and computes the **same value** as natively. **(iii)** An end-to-end A/B of the portable build against the
previous build — same box, same session, same arms — is **within noise**: |Δ| ≤ 0.6 % on prefill and
−1.3…+0.1 % on decode, i.e. less than the scatter of a single measurement.

**What is not proven.** Every number above comes from **one box** (2x gfx906: MI50 32 GB whose MI50 also
runs a reduced UPP power limit, plus a Radeon VII 16 GB) — **not stock-card numbers** — and **no third
party has reproduced them**. The `qemu` proof is a unit-level and address-level demonstration, **not a
full engine start under emulation**, and there is **no run on a real Haswell machine**. **This tag has no
network pool** — that lives only in `0.1.40.1-pool`.

**The previous release, `0.1.43.1`**, remains pullable as a backup tag
(`docker pull xxdoman/strata-mi50:0.1.43.1`, digest
`sha256:6e9002179e5566a9f29bfb686263d79b3580beff22133e926368a8e078c8bdd0`). It is the image that carries the
old AVX-VNNI fault, so pin it only on a host that does have AVX-VNNI; its full page is **[engine
0.1.43.1](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.43.1.md)**.

Full page, with the fixed header (tag, sums, what it fixes, how proven, what is not): **[engine
0.1.44.1](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.44.1.md)**.

**The local, unpublished builds** (`0.1.44.1.b` … `.1.h`, configurator work plus one engine rebuild at
`.h`) are documented in the engine index because they are real fixes and real measurements — but they
were never pushed, so nobody outside this machine can pull them:
**[engine index](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/README.md)**.

---

## Quick start

```yaml
# docker-compose.yml (abridged — the repository's file is the full one)
services:
  strata:
    image: xxdoman/strata-mi50:latest
    shm_size: 16g
    devices: [/dev/kfd:/dev/kfd, /dev/dri:/dev/dri]
    device_cgroup_rules: ['c 226:* rmw']
    ports: ["8085:8085", "8090:8090"]            # engine (API + chat) / configurator
    ulimits: {memlock: -1}
    security_opt: [seccomp=unconfined]
    environment:
      - HSA_OVERRIDE_GFX_VERSION=9.0.6            # required for MI50/gfx906
      - LD_LIBRARY_PATH=/opt/rocm/lib
      - CONFIG=/work/strata-config.json
    volumes:
      - /path/to/gguf:/models                     # GGUF shards + mmproj/  (RW for the wizard, :ro after)
      - /path/to/Strata-data:/data                # packs/ + mtp/ + expert-profile.bin
      - /path/to/Strata-data/configs:/work        # RW — the configurator writes the config here
```

```bash
docker compose up -d && docker compose logs -f     # then open http://<host>:8090
```

Ports: **8090** configurator, **8085** engine (OpenAI `/v1/chat/completions`, Anthropic `/v1/messages`).
Host requirements: `/dev/kfd` + `/dev/dri`, user in the `video` and `render` groups. No model is in the
image — section **0. Setup** of the configurator downloads the GGUF and builds the pack, tokenizer and
MTP draft inside the container (one-time ~70 GB); models, packs and drafts stay on the mounted volumes
and survive image updates. Full setup, host layout, configurator, vision encoder and the power-cap traps:
**[operations](https://github.com/xxDoman/strata-gfx906/blob/master/docs/operations.md)** ·
on the wiki: [operations](https://github.com/xxDoman/strata-gfx906/wiki/operations).

---

## Links

Every link below is absolute on purpose: relative paths do not work on the Docker Hub page.

| Page | In this repository | On the wiki |
| --- | --- | --- |
| Engine index — all tags, sums, status | [docs/engines](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/README.md) | [Engines](https://github.com/xxDoman/strata-gfx906/wiki/Engines) |
| Engine 0.1.45 — the released one | [docs/engines/0.1.45.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.45.md) | [Engine-0.1.45](https://github.com/xxDoman/strata-gfx906/wiki/Engine-0.1.45) |
| Engine 0.1.44.1 — previous | [docs/engines/0.1.44.1.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.44.1.md) | [Engine-0.1.44.1](https://github.com/xxDoman/strata-gfx906/wiki/Engine-0.1.44.1) |
| Engine 0.1.43.1 — previous release, still pullable | [docs/engines/0.1.43.1.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.43.1.md) | [Engine-0.1.43.1](https://github.com/xxDoman/strata-gfx906/wiki/Engine-0.1.43.1) |
| Image history — what is in each tag, which fixes are ours | [docs/image-history.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/image-history.md) | [image-history](https://github.com/xxDoman/strata-gfx906/wiki/image-history) |
| Measurements — every number with its regime | [docs/measurements.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/measurements.md) | [measurements](https://github.com/xxDoman/strata-gfx906/wiki/measurements) |
| Benchmarks — the measured tables | [docs/benchmarks.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/benchmarks.md) | [benchmarks](https://github.com/xxDoman/strata-gfx906/wiki/benchmarks) |
| Community benchmark — a run of Strata's own suite here | [docs/community-benchmark.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/community-benchmark.md) | [community-benchmark](https://github.com/xxDoman/strata-gfx906/wiki/community-benchmark) |
| Rankings — the same results as two bar charts | [docs/rankings.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/rankings.md) | [rankings](https://github.com/xxDoman/strata-gfx906/wiki/rankings) |
| Where we stand — upstream's community results, one table | [docs/where-we-stand.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/where-we-stand.md) | [where-we-stand](https://github.com/xxDoman/strata-gfx906/wiki/where-we-stand) |
| Operations — setup, config, vision, pool, traps | [docs/operations.md](https://github.com/xxDoman/strata-gfx906/blob/master/docs/operations.md) | [operations](https://github.com/xxDoman/strata-gfx906/wiki/operations) |
| Plain facts for AI assistants | [llms.txt](https://github.com/xxDoman/strata-gfx906/blob/master/llms.txt) | — |

- Docker Hub: <https://hub.docker.com/r/xxdoman/strata-mi50>
- Upstream engine (MIT): <https://github.com/Niko1221/Strata>
- Issues with this packaging: <https://github.com/xxDoman/strata-gfx906/issues>
- The wiki is generated from this repository's `docs/` by `tools/publish-wiki.sh` — the repository copy
  is the canonical one, the wiki is the mirror. A page listed above that the wiki does not have yet is
  one whose mirror has not been published; the repository link always works.

## License

This packaging — the Dockerfiles, `docker-compose.yml`, the configurator glue and these docs — is **MIT**
(`LICENSE`). It redistributes the **Strata engine** (MIT, `Copyright (c) 2026 Niko1221 and the Strata
contributors`); MIT requires the original copyright notice to travel with it, and it is kept verbatim in
`LICENSE`. The base ROCm images and the model weights (downloaded separately, never in this image) keep
their own licenses.
