# Image history — what is in each tag, and which parts are ours

The engine itself is [Strata](https://github.com/Niko1221/Strata) (MIT). This page is only about the
gfx906 packaging: which tags we built, what we had to patch for these cards, and what that patch is
worth in a measurement. Upstream's own engine changelog lives in their repository.

## Tags we built

```
0.1.39           0.1.40            0.1.41            0.1.42            0.1.43            0.1.43.1
  0.1.39-v3        0.1.40.4         0.1.41.v2         0.1.42-roc981     0.1.43-roc981     0.1.43.1-roc981
  0.1.39-854       0.1.40-i1187     0.1.41-roc981
                   0.1.40-pool
```

`-roc981` marks builds that carry our rocBLAS solution table (see below). `0.1.43.1-roc981` is the
engine in the **released** image: `xxdoman/strata-mi50:0.1.43.1` and `:latest` both point at it
(published 2026-10-12). `0.1.43` stays as the previous release; `0.1.43-test` is the pre-release build
of the same engine without the two fixes described under 0.1.43.1 below. Tag state is still worth
taking from the live Hub rather than from a note like this one:

```bash
curl -s https://hub.docker.com/v2/repositories/xxdoman/strata-mi50/tags?page_size=5 | python3 -m json.tool
```

## What we patch, and what it is worth

**rocBLAS solution table for gfx906 (`STRATA_ROCBLAS_TUNING`) — ours, deployed.**
Official ROCm images ship rocBLAS kernels only from gfx1010, so these cards get no GEMM code from
them; we pack the host's gfx906 rocBLAS in, and on top of that the engine asks a *solution table* for
the fastest kernel per GEMM shape instead of taking rocBLAS's own pick. The reader comes from the
idea in upstream [PR #981](https://github.com/Niko1221/Strata/pull/981), which is gated behind the
wave32 RDNA path — on a gfx906 build that macro never reaches `gemm.cu`, so the reader was compiled
out and the table sat unused. We added rocBLAS detection to the gfx906 block and widened the gate.
Measured A/B, same engine, MI50 @ 80 W, IQ3, by environment switch:

```
16k prompt   prefill 337.3 -> 369.4 tok/s      +9.5%    TTFT -9%
32k prompt   prefill 347.4 -> 384.8 tok/s     +10.8%    decode unchanged
```

The table only applies to the 16-bit prompt path, so the image sets `STRATA_HIP_PROMPT_F16=1` by
default: that changes the prompt's rounding (the engine says so itself — *not bit-identical to the
default*), decode is unaffected. Quote it as its own lever, never merged into one number with the
table.

**gfx906 build gates — ours, upstream.** Three `STRATA_USE_HIP` gates plus `STRATA_HIP_GFX906` in
`src/core/vmm.cpp`, `src/core/mtp.cpp`, `src/kernels/cuda/fused_gr.cu`; without them the 0.1.40 tree
does not compile on gfx906. Sent as [PR #1066](https://github.com/Niko1221/Strata/pull/1066) /
[#1083](https://github.com/Niko1221/Strata/pull/1083).

**dp4a (`v_dot4_i32_i8`) — in the engine, not ours.** It is already in upstream's hip-compat path
and it does work on gfx906. Our [PR #1084](https://github.com/Niko1221/Strata/pull/1084) turned out
to be a no-op — the binary with and without that line is identical byte for byte, because gfx906
does not compile that path. Measured A/B by build: decode **+12..17%**, prefill unchanged.

**Community benchmark header on AMD — ours, in this image.**
Upstream's new benchmark (`tools/strata_bench.py`) prints `GPU driver: not read` and a generic
`AMD Radeon Graphics` on AMD hardware, because of two bugs in the script itself (a discarded
`rocm_driver` read, and a card name taken from a driver that has no marketing name for the MI50).
Our image applies `bench-patches/0001-gfx906-gpu-metadata-1431.patch` on top of the upstream file —
report header only, nothing in the measurement path. The one-line driver fix is proposed upstream as
[#1974](https://github.com/Niko1221/Strata/pull/1974). If it lands, we drop our patch.

On 0.1.43.1 the patch also has to win the card names back: upstream rewrote `collect_machine`
(#1985/#2001) so that when the **server's** card names differ from the locally detected ones, the
server's win — and the server reports the ROCm driver's wording, which is `Radeon Instinct MI50 32GB +
AMD Radeon` here (no marketing name for `0x66a1`, and the Radeon VII's shortened). Our patch now keeps
the locally mapped names whenever the server's list lines up 1:1 with the detected cards, and takes the
server's only for a count mismatch or a vendor we did not detect. Checked against the running engine on
this box, same config: `['Radeon Instinct MI50 32GB', 'AMD Radeon']` before,
`['AMD Instinct MI50 32GB', 'AMD Radeon VII 16GB']` after, VRAM/driver/engine fields unchanged.

**Networked pool — separate build, not in this image.** A prototype for several PCs sharing one
model (roles: off / router / coordinator / worker, layers over TCP) lives in its own fork
(`fragtion/StrataPool`, idea:
[PR #482](https://github.com/Niko1221/Strata/pull/482)) and needs its own binary. The engine in this
image has no networked pool. Note that the engine's `--pool-tasks` flag is something else entirely:
a CPU task pool for MoE, not the network.

## Engine 0.1.43 on gfx906: nothing changed

A short note we keep because it saves a re-check: upstream's decode-speed pushes in 0.1.43 are gated
by architecture, and their own source says it plainly —

> the HIP defaults of the decode speed push (...) were measured on gfx1201 (Radeon AI PRO R9700) and
> apply on gfx1200 / gfx1201 only; every other AMD part (gfx11, gfx906, ...) keeps its earlier
> behaviour.

So on gfx906, 0.1.43 is 0.1.42 in the decode path. What 0.1.43 does change is the benchmark: it is
rewritten (new CLI, new report format, anonymised output) and the old script's auth wrapper is gone.
Our image carries **both** benchmarks — the old one stays so the results we already published remain
comparable, the new one runs alongside it in the configurator.

## Engine 0.1.43.1 on gfx906

The hotfix release (2026-10-12, 33 commits) is aimed at NVIDIA desktops, Windows, Intel and the server.
Three of its changes reach us:

- `STRATA_ADAPT_OVERLAP` is **opt-in again on every machine** (#2010): the Linux-NVIDIA decode collapse
  two users hit on 0.1.43 (#1964) is fixed twice over — the driver's host-callback thread is warmed up
  before the host core is pinned, and the per-layer signal no longer needs that thread. On HIP we were
  outside that regime anyway, and on this box the engine now prints `adaptive overlap: off: not on a
  layer split`.
- the prompt path is more forgiving: a loan larger than the auto chunk's no longer ends the engine
  (#2090, *lending the prompt path its slots failed*), and a request that finds the card nearly full now
  says so, naming the `--vram-reserve-mib` that would leave room (#2065).
- the PLE/n-gram start-up check no longer switches to mmap by itself on a slow disk (#2040: long prompts
  on a SATA SSD were about 7x slower).

Decode on gfx906 is unchanged — the 0.1.43 speed work is still gated to gfx1200/gfx1201 — so our
measured rows stand. Our patches, re-based onto 0.1.43.1: the rocBLAS table reader
(`patches-upstream/pr981-1431.diff`, 14 files, `git apply --check` clean on the tag) **with the gfx906
gate inside the patch this time**, and the community-report header above
(`bench-patches/0001-gfx906-gpu-metadata-1431.patch`). The old `pr981-clean.diff` was not what built
0.1.43 — two of its hunks (`Gemm::f16_inplace`, and two in `setup.py`) do not apply to the 0.1.43 tree
either, and the source tree from that build is gone, so 0.1.43.1 carries a patch that is verifiable from
the tag up.

**One fix of ours that is not an engine patch:** the configurator no longer writes
`--vram-reserve-later-mib 0` on the later cards of a headless split ([issue
#1](https://github.com/xxDoman/strata-gfx906/issues/1)). Every later card keeps a 512 MiB floor, because
the stage's own verification arena (69 MiB at `--spec 3`) and its serve-time buffers come on top of the
cache the engine sizes to `free - 96 MiB`. Cost on IQ3_S: ~530 cache slots per card, ~97% → ~95%
resident. On this box the flag stays at 1024 either way, because the display hangs off the later card.

Measured 2026-10-12 on this box, same config, same suite, 0.1.43.1 against the previous release (the
`--mmap-experts` arm, which is the config the image's own install uses):

```
16K prompt, fresh     543.9  ->  544.9 tok/s     level (ranges 543.2-546.1 vs 542.5-551.2)
chat decode            41.2  ->   41.7 tok/s     level (ranges overlap)
4K prompt, fresh      473.6  ->  460.7 tok/s     -2.7%, both ranges wide (375-477 vs 404-471)
agent session, decode  44.7  ->   43.4 tok/s     ranges overlap (33.7-53.2 vs 26.5-58.3)
```

Read it as: **the hotfix cost us nothing**; the number that carries the table (16K) is level to within
its own range. The table's *own* worth on 0.1.43.1 — a toggle-on/off A/B on this engine — came a few hours
later: **+19.7% at 4K and +24.2% at 16K prompt, first token 16-20% earlier, decode unmoved**, in the
`--mmap-experts` arm ([run 4](community-benchmark.md)). The +9.5% / +10.8% above is a different regime
(16k/32k, resident arena, ctx 65536, 0.1.42) and is not what 0.1.43.1 measures.

## Two ways to check a tag before trusting a note

```bash
docker images --digests | grep strata-mi50          # tag vs digest
curl -s https://hub.docker.com/v2/repositories/xxdoman/strata-mi50/tags   # what is on the Hub
```
