# Community benchmark — Strata's own suite on 2x gfx906

Upstream ships a suite (`tools/strata_bench.py`, 0.1.43+) that drives the real HTTP API and writes a
report you can paste into a GitHub issue or a pull request against `bench/results/`. These are runs
of it on this machine, plus the traps we hit while running it.

> **Read this before comparing with anyone else's numbers.** This image is **not a stock install**,
> and the report cannot say so — its line *"Settings: the install's own configuration, unchanged"*
> describes the **config** (thinking off, temperature 0), not the image. What is ours in every number
> below: the engine binary is built from tag v0.1.43 **plus our gfx906 build gates** (three HIP gates;
> without them 0.1.40+ does not compile on gfx906) **and the rocBLAS solution-table reader**, our code
> change based on the idea in [#981](https://github.com/Niko1221/Strata/pull/981) (upstream gates that
> reader behind a path gfx906 never compiles). The image also turns the **solution table on by
> default** (`STRATA_ROCBLAS_TUNING`) along with the **FP16 prompt path** it needs
> (`STRATA_HIP_PROMPT_F16=1`) — the engine's own words are *"not bit-identical to the default"*.
> Decode is unaffected by the table: we measured it as a prefill lever (+9.5% / +10.8% on IQ3, same
> engine, A/B by environment). Quote these numbers as *"gfx906 image, table ON, FP16 prompt path"*,
> never as stock 0.1.43.

## Run 1 — IQ1_M coder (split, no low-RAM)

```
Date       2026-10-11
Image      xxdoman/strata-mi50 (Strata engine 0.1.43, project 0.1.43)
Harness    python tools/strata_bench.py --clients 1 --runs 3 --out /work/bench-results-community
Server     already running; model loading not timed
GPU        AMD Instinct MI50 32GB + AMD Radeon VII 16GB, 48 GiB VRAM total
CPU/RAM    12th Gen Intel Core i5-12400F (6 cores, 12 threads); 61.6 GiB
Model      Qwen3.8-Flash-Next-GSQ-RCO-IQ1_M   (pack coder-iq1_m)
Config     context 131072, KV q4_0, prefill 2048, MTP spec 4, rocBLAS solution table ON,
           --layer-split auto (both cards), no --mmap-experts
```

## Results (median, with the range over the runs)

```
short chat            decode 49.4 tok/s   (43.6-63.9)     first token 0.60 s (0.54-0.64)
4K prompt, fresh      prompt 604.2 tok/s  (596.0-604.5)  first token 6.68 s (6.68-6.77)
16K prompt, fresh     prompt 756.5 tok/s  (755.9-757.3)  first token 21.26 s (21.24-21.28)
agent session         decode 49.5 tok/s   (37.6-54.6)     first token 4.00 s (3.76-4.16)
1 concurrent client   34.1 tok/s total    latency p50 3.749 s / p95 3.816 s, 0 errors
```

Agent session detail (conversation cache, run 1) — the suite resends a growing conversation the way
agent clients do, so the cache either holds earlier turns or the engine reads them again:

```
turn   prompt tok   reused   read    prompt tok/s   first token s   decode tok/s
  0         609        0      609        283.7           2.176            41.9
  1        2262      623     1639        434.7           3.801            47.0
  2        3968     2326     1642        416.9           3.969            45.6
  3        5643     4001     1642        414.3           3.995            37.6
  4        7302     5660     1642        411.6           4.022            42.6
  5        8961     7319     1642        397.6           4.164            52.8
cache hit over the follow-up turns: 70.8%; earlier-turn tokens read again per session: 3
```

Read this with the regime in mind: `--runs 3` gives n=3 for the prompt tests and n=5 turns for the
agent session, and the decode spread in the agent session (37.6 to 54.6) shows how much a single run
can move. One run per test is not a result.

## Run 2 — IQ3_XXS, split, low-RAM off vs on (2026-10-11)

Same model, same config, **one switch apart**: only the expert-arena mode differs, so whatever moves
is attributable to that switch and nothing else.

| arm | expert arena | flag | status |
| --- | --- | --- | --- |
| **A** | experts load into pinned host RAM | *(none)* | measured, 3 runs — below |
| **B** | experts are read through the page cache | `--mmap-experts` | in progress when this was written |

Shared regime for both arms: model **Qwen3.8-Flash-Next-Uncensored-IQ3_XXS** (pack `orca-iq3_xxs`,
profile `expert-profile.bin`), context 131072, KV q4_0, prefill 2048, MTP spec 4, min-p 0.9,
`--vram-reserve-mib 1024 --vram-reserve-later-mib 1024`, `--layer-split auto`, engine 0.1.43.
No `--resident-*` flags. The engine names the two modes itself, and that sentence is the whole
difference being measured: arm A logs `expert arena: cudaHostRegister PORTABLE ok`, arm B logs
`expert arena read through the file cache (buffered)`.

### Arm A — no `--mmap-experts` (experts resident in host RAM)

```
short chat            decode 44.0 tok/s   (41.9-62.1)     first token 0.59 s (0.54-0.75)
4K prompt, fresh      prompt 546.9 tok/s  (546.5-549.5)  first token 7.38 s (7.35-7.39)
16K prompt, fresh     prompt 621.8 tok/s  (619.7-622.0)  first token 25.87 s (25.86-25.96)
agent session         decode 41.7 tok/s   (34.9-62.0)     first token 4.18 s (3.86-10.85)
1 concurrent client   31.7 tok/s total    latency p50 4.035 s / p95 9.077 s, 0 errors
```

Agent session, arm A (conversation cache — cache hit 71.0%, 4 earlier-turn tokens read again per
session, first turn with nothing cached 2.57 s):

```
turn   prompt tok   reused   read    prompt tok/s   first token s   decode tok/s
  0         609        0      609        244.8           2.572            36.2
  1        2264      624     1640        425.6           3.892            41.5
  2        3970     2327     1643        395.9           4.192            42.8
  3        5676     4033     1643        399.6           4.152            43.1
  4        7382     5739     1643        396.8           4.184            41.6
  5        9067     7425     1642        396.4           4.184            41.7
```

Two "hit" numbers are in play here and they are **not** the same thing: the 71.0% above is the
*conversation* cache (how much of a resent prompt the engine could reuse), while the engine reports
its own *expert* cache separately (`decode expert cache hit rate: 99.7%` on a test request in the
same session). Never swap them.

### Arm B — with `--mmap-experts` (experts read through the page cache)

```
short chat            decode 41.2 tok/s   (34.8-53.0)     first token 0.69 s (0.58-0.76)
4K prompt, fresh      prompt 473.6 tok/s  (375.1-477.0)  first token 8.52 s (8.46-10.75)
16K prompt, fresh     prompt 543.9 tok/s  (543.2-546.1)  first token 29.56 s (29.45-29.60)
agent session         decode 44.7 tok/s   (33.7-53.2)     first token 4.76 s (4.51-4.95)
1 concurrent client   32.5 tok/s total    latency p50 3.932 s / p95 4.239 s, 0 errors
```

### The difference — medians, arm B against arm A

```
4K prompt tok/s      546.9  ->  473.6      -13.4%     range on B is wide: 375.1-477.0
16K prompt tok/s     621.8  ->  543.9      -12.5%
4K first token        7.38  ->   8.52      +15.4%
16K first token      25.87  ->  29.56      +14.3%
chat decode           44.0  ->   41.2       -6.4%     ranges overlap (41.9-62.1 vs 34.8-53.0)
agent decode          41.7  ->   44.7       +7.2%     ranges overlap (34.9-62.0 vs 33.7-53.2)
1 client, total       31.7  ->   32.5       +2.5%     A's range had a 13.3 outlier
agent cache hit      71.0%  ->  70.7%       same
```

Read it as: **on a model that fits in RAM, `--mmap-experts` costs the prompt path ~12-13% and the
first token ~14-15%**, while decode is not attributable — the ranges overlap, so that is noise, not
a result. Two things in the raw data are worth watching rather than concluding from: arm B's 4K
range (375.1) shows one run paying for a cold page cache, and in one arm-B session 73 earlier-turn
tokens were read again against 4 in arm A (the conversation cache missing more). Both are consistent
with the arena going through the page cache; neither is proven at n=3.

**Not measured here, and worth someone's evening:** the case low-RAM exists for — a model whose
expert arena is *larger* than RAM, where the resident mode cannot run at all.

## Run 3 — 0.1.43.1, the same `--mmap-experts` config (2026-10-12)

The released engine is **0.1.43.1** now — a hotfix over 0.1.43, and [what it changes](image-history.md)
is written up on the image-history page. The config here is the install's own, i.e. **arm B above on the
next engine**: IQ3_XXS, ctx 131072, KV q4_0, prefill 2048, MTP spec 4, min-p 0.9,
`--vram-reserve-mib 1024 --vram-reserve-later-mib 1024`, `--layer-split auto`, `--mmap-experts`.

```
short chat            decode 41.7 tok/s  (33.4-56.8)     first token 0.73 s (0.56-0.81)
4K prompt, fresh      prompt 460.7 tok/s (404.2-470.6)   first token 8.76 s (8.57-9.98)
16K prompt, fresh     prompt 544.9 tok/s (542.5-551.2)   first token 29.51 s (29.17-29.64)
agent session         decode 43.4 tok/s  (26.5-58.3)     first token 4.81 s (4.52-4.94)
1 concurrent client   31.9 tok/s total    latency p50 4.016 s / p95 4.252 s, 0 errors
agent cache hit       71.0% (70.7-71.0)
```

### The difference — 0.1.43.1 against 0.1.43, both arm B

```
16K prompt tok/s     543.9  ->  544.9      +0.2%     tight ranges: 543.2-546.1 vs 542.5-551.2
chat decode           41.2  ->   41.7      +1.2%     ranges overlap
4K prompt tok/s      473.6  ->  460.7      -2.7%     both ranges wide (375-477 vs 404-471)
agent decode          44.7  ->   43.4      -2.9%     ranges overlap (33.7-53.2 vs 26.5-58.3)
1 client, total       32.5  ->   31.9      -1.8%
agent cache hit      70.7%  ->  71.0%      same
```

The hotfix costs nothing measurable here: the one row with a tight range — 16K, the row the rocBLAS
table acts on — is level to 0.2%, and every other difference sits inside its own range. Both runs carried
the same two switches (table on: `STRATA_ROCBLAS_TUNING` + `STRATA_HIP_PROMPT_F16=1`; tail skip on:
`STRATA_ROUTE_TAIL_SKIP=7`), and this run's engine log confirms both on both cards —
`prefill gemm: rocBLAS tuning enabled (103 rows, 78 with a solution, gfx906, rocBLAS 5.2.0.dabb6df2b9)`
twice, then `STRATA_ROUTE_TAIL_SKIP=7 is ON`.

**Not measured, and the next run worth doing:** the table's own worth on 0.1.43.1 — this suite with the
table toggle **off**. The +9.5% / +10.8% on the image-history page is a 16k/32k A/B at 80 W on
0.1.42/0.1.43, not this suite and not this engine.

## Run 4 — the table's own worth on 0.1.43.1 (2026-10-12)

Same engine, same config, same suite, **one switch apart**: the rocBLAS table (`STRATA_ROCBLAS_TUNING`
plus the FP16 prompt path it needs) on against off. Both arms with `--mmap-experts`, ctx 131072, KV q4_0,
prefill 2048, MTP spec 4, min-p 0.9, `--layer-split auto`. The off arm is the engine restarted with the
toggle cleared (the launcher writes both keys explicitly), so the two arms are two engine sessions.

```
                     table ON             table OFF            delta
4K prompt, fresh     460.7 (404.2-470.6)   384.9 (374.3-389.0)  +19.7%
16K prompt, fresh    544.9 (542.5-551.2)   438.6 (437.5-438.7)  +24.2%
first token, 4K       8.76 s               10.48 s             -16.4%
first token, 16K     29.51 s               36.66 s             -19.5%
chat decode           41.7 (33.4-56.8)      40.7 (3.8-56.5)      level
agent session decode  43.4 (26.5-58.3)      50.7 (39.4-58.1)     ranges overlap
1 client, total       31.9 tok/s           32.0 tok/s           level
```

The table is a **prompt-path** lever and here a large one: +20% at 4K, +24% at 16K, first token 16-20%
earlier, while decode does not move (the agent row's 50.7 sits inside 39.4-58.1 and its 43.4 inside
26.5-58.3 — overlapping, not a result). Bigger than the +9.5% / +10.8% on the image-history page, and the
two do not conflict: that one was 16k/32k with a **resident** arena, ctx 65536, on 0.1.42; this one is
`--mmap-experts`, ctx 131072, on 0.1.43.1.

**The confound, stated.** The two arms are two engine sessions and the off arm had just restarted, so it
also paid for a cold page cache in its first requests — visible in exactly one place, the short-chat row
(`decode 3.8-56.5`, first token up to 10.6 s, against 33.4-56.8 and 0.55-0.81 s on the warm engine). The 4K
and 16K rows come after nine chat requests and their ranges are tight (16K: 437.5-438.7 against
542.5-551.2), which is why the prompt numbers are read as the table and not as cold cache. Repeating this:
run **each arm twice** and compare the second run of each.

**The resident arm is not measurable on this box while a desktop runs.** Tried on 0.1.43.1 with no
`--mmap-experts`: ~50 GiB of host arena pinned (`cudaHostRegister PORTABLE ok`, `MAP_HUGETLB` unavailable,
THP on 4k pages) on a 61.6 GiB machine, RAM went to 58/61 with 7 GiB in swap, the PCIe H2D probe fell from
5.5 to 3.6 GB/s, and the prompt path stalled in ten-second steps with the GPU at 24 W. The suite still
finished, but two of its three 16K runs and one 4K run carry that stall (16K: 127.3 / 545.3 / 617.5 tok/s).
The uncontaminated runs land where 0.1.43's resident arm landed — 4K 548.4 against 546.9 recorded, 16K
617.5 against 621.8 — which is the one thing that run says. For a real resident measurement: an idle box,
and `vm.nr_hugepages` sized to the arena.

### A trap we are *not* in, and why it is worth knowing: `STRATA_ADAPT_OVERLAP`

Upstream issue [#1964](https://github.com/Niko1221/Strata/issues/1964): on **Linux CUDA**, 0.1.43 turns
`STRATA_ADAPT_OVERLAP` on by default — the adaptive tier's copies land while the next decode window
already runs. Two users reproduced a **2-3x decode collapse** with it: RTX 4070 Ti **96.5 -> 37.9 tok/s**,
RTX 4090 **19-37 -> 102-116 tok/s** once it was turned off — prefills, first tokens and cache hit rates
all unchanged, so it looks like a code regression until you find the switch. `STRATA_ADAPT_OVERLAP=0`
restores the older numbers. The engine's own source names the regime it belongs to: the *single-GPU,
plain-RAM-arena decode loop* only, with the published wins on PCIe-bound small-VRAM cards
(A4000 +5.5-8.3%, P100 +4.4%).

On **HIP it is opt-in** (`STRATA_ADAPT_OVERLAP=1`) and the source says *"not measured yet"* — so every
number on this page was taken with it **off**. That is confirmed in the engine log, not just in the
source: the banner line it prints when the overlap is active (`strata serve: adaptive overlap ...`)
appears **zero** times across our runs. Our gfx906 numbers are therefore unaffected by #1964.

Two consequences worth keeping in mind. A gfx906 user on a **single** card with a plain RAM arena is
the one regime where switching it on could be worth measuring — nobody has. And any **CUDA** entry in
the community list measured on Linux 0.1.43 may be carrying this regression unless the entry says
otherwise, which matters when comparing our rows with theirs.

## What the suite actually does

Five steps, `Runs per size` repeats each one: chat (3 short questions, 100 new tokens), a fresh 4K
prompt, a fresh 16K prompt, an agent session (5-6 turns with four tools), and concurrency (only with
`clients > 0`). A ~32K prompt is opt-in. Prompts carry a unique tag so the conversation cache cannot
help the fresh-prompt tests; one warm-up chat and a 1K prompt are discarded first.

## How to reproduce

```bash
# the engine must already be running (the script uses --url, it does not start its own unless asked)
docker exec strata python3 /opt/strata/tools/strata_bench.py \
  --url http://127.0.0.1:8085 --runs 3 --out /work/bench-results-community
# or from the configurator: Benchmark tab -> Community benchmark (NEW script)
```

Upstream asks for those results as a pull request that adds the folder to `bench/results/` — see
their `docs/COMMUNITY_BENCHMARKS.md`, which already lists a 2x MI50 gfx906 report.

## Two traps in the report itself (both fixed in our image)

**1. On AMD the header used to read `GPU driver: not read` and `AMD Radeon Graphics` instead of the
card.** Nothing was missing in the image — the script threw the data away: `gpu_driver` picked
`gpus[0]["driver"]`, which on the ROCm path is `None`, while the `rocm_driver` read a few lines above
was discarded; and the card name came straight from `rocm-smi`, where the amdgpu driver has no
marketing name for the MI50 (`0x66a1`). Our image applies `bench-patches/0001-gfx906-gpu-metadata.patch`
on top of the upstream file (measured effect: `AMD Instinct MI50 32GB` + `AMD Radeon VII 16GB`,
driver `7.0.0-38-generic`, and a results folder named `2x-instinct-mi50-32gb-...` instead of
`2x-unknown-...`). The one-line driver fix is proposed upstream as
[#1974](https://github.com/Niko1221/Strata/pull/1974); nothing about this image is mentioned there.

**2. The folder name is built from the GPU name**, so with the generic name the folder came out as
`2x-unknown`. Cosmetic, but it is the label you submit.
