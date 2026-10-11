# Community benchmark — Strata's own suite on 2x gfx906

Upstream ships a suite (`tools/strata_bench.py`, 0.1.43+) that drives the real HTTP API and writes a
report you can paste into a GitHub issue or a pull request against `bench/results/`. This is a run
of it on this machine, plus the traps we hit while running it.

## The run

```
Date       2026-10-11
Image      xxdoman/strata-mi50 (Strata engine 0.1.43, project 0.1.43)
Harness    python tools/strata_bench.py --clients 1 --runs 3 --out /work/bench-results-community
Server     already running; model loading not timed
GPU        AMD Instinct MI50 32GB + AMD Radeon VII 16GB, 48 GiB VRAM total
CPU/RAM    12th Gen Intel Core i5-12400F (6 cores, 12 threads); 61.6 GiB
Model      Qwen3.8-Flash-Next-GSQ-RCO-IQ1_M   (pack coder-iq1_m)
Config     context 131072, KV q4_0, prefill 2048, MTP spec 4, rocBLAS solution table ON
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
