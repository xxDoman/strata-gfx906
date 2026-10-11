# Image history — what is in each tag, and which parts are ours

The engine itself is [Strata](https://github.com/Niko1221/Strata) (MIT). This page is only about the
gfx906 packaging: which tags we built, what we had to patch for these cards, and what that patch is
worth in a measurement. Upstream's own engine changelog lives in their repository.

## Tags we built

```
0.1.39           0.1.40            0.1.41            0.1.42            0.1.43
  0.1.39-v3        0.1.40.4         0.1.41.v2         0.1.42-roc981     0.1.43-roc981
  0.1.39-854       0.1.40-i1187     0.1.41-roc981
                   0.1.40-pool
```

`-roc981` marks builds that carry our rocBLAS solution table (see below). `0.1.43-roc981` is the
engine in the current test image; what is on the Docker Hub tag `latest` is stated on the Hub page
itself, and the README repeats it — check the live tag rather than a note like this one.

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
Our image applies `bench-patches/0001-gfx906-gpu-metadata.patch` on top of the upstream file —
report header only, nothing in the measurement path. The one-line driver fix is proposed upstream as
[#1974](https://github.com/Niko1221/Strata/pull/1974). If it lands, we drop our patch.

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

## Two ways to check a tag before trusting a note

```bash
docker images --digests | grep strata-mi50          # tag vs digest
curl -s https://hub.docker.com/v2/repositories/xxdoman/strata-mi50/tags   # what is on the Hub
```
