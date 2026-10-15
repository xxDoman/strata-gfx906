# Strata on AMD gfx906 — image, measurements and everything we hit on the way

Prebuilt, self-contained Docker image of the [Strata](https://github.com/Niko1221/Strata) MoE engine
for **AMD Instinct MI50 / MI60 / Radeon VII** (gfx906), with a browser configurator, plus the full
record of how it was built, what it measures and what went wrong.

Pull it: `docker pull xxdoman/strata-mi50:latest` · Hub page: <https://hub.docker.com/r/xxdoman/strata-mi50>

---

## Quick start

```bash
docker pull xxdoman/strata-mi50:latest

docker run -d --name strata \
  --device=/dev/kfd --device=/dev/dri --group-add video \
  -v /path/to/gguf:/models:ro -v /path/to/Strata-data:/data -v /path/to/work:/work \
  -p 8085:8085 -p 8090:8090 xxdoman/strata-mi50:latest

# then open http://<host>:8090
```

The released engine is **0.1.43.1** (`latest`): [its own page](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.43.1.md) has the tag, the image sum, the engine binary sum, what it fixes and what was never proven. The locally built `0.1.44.1.b` … `.1.g` images (same engine binary, configurator work) are indexed there too — [engine index](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/README.md).

Models, conversion packs and the MTP draft stay on the host and are mounted — nothing is baked into
the image. ROCm 7.2.1 with the gfx906 libraries and rocBLAS kernels packed in (official ROCm images
ship rocBLAS only from gfx1010, so without them these cards have no GEMM code).

## Docs

| Page | What is in it |
| --- | --- |
| [measurements.md](https://github.com/xxDoman/strata-gfx906/wiki/measurements) | Every measurement we took — both families (Strata and llama.cpp on the same pair), with the regime of each number, plus the traps we walked into |
| [community-benchmark.md](https://github.com/xxDoman/strata-gfx906/wiki/community-benchmark) | A run of Strata's own community suite on this hardware, the exact numbers, and how to repeat it |
| [image-history.md](https://github.com/xxDoman/strata-gfx906/wiki/image-history) | What each image version changed, which fixes are ours, what is upstream |
| [rankings.md](https://github.com/xxDoman/strata-gfx906/wiki/rankings) | The same results as two bar charts — decode and prefill |
| [where-we-stand.md](https://github.com/xxDoman/strata-gfx906/wiki/where-we-stand) | All community results in one table, regime visible, and where this box places |
| [Engines — every tag with its image sum, engine binary sum and status](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/README.md) | One page per engine of this image line: what it fixes, how that was proven, what is not proven (also on the wiki: [Engines](https://github.com/xxDoman/strata-gfx906/wiki/Engines)) |

## Numbers at a glance

Community suite (`tools/strata_bench.py`, 3 runs per test) on **2x gfx906: MI50 32 GB + Radeon VII 16 GB**,
Qwen3.8-Flash-Next-GSQ-RCO **IQ1_M**, context 131072, KV q4_0, MTP spec 4:

```
short chat            decode 49.4 tok/s (43.6-63.9), first token 0.60 s
4K prompt, fresh      prompt 604.2 tok/s (596.0-604.5), first token 6.68 s
16K prompt, fresh     prompt 756.5 tok/s (755.9-757.3), first token 21.26 s
agent session         cache hit 70.8%, 3 re-read tokens/session, first token 4.00 s
1 concurrent client   34.1 tok/s total, latency p50 3.749 s
```

Full run, per-turn detail and how to reproduce: [community-benchmark.md](https://github.com/xxDoman/strata-gfx906/wiki/community-benchmark).

## Two families of results — do not mix them

This project measures two different engines on the same machine. Numbers from one family are not
comparable with the other: different engine, different cache behaviour, different quantisation of
the KV cache. Keep them apart, always with the regime attached.

```
Family A  Strata (this image)        MoE engine, expert cache in VRAM
Family B  llama.cpp / fork / Ollama  dense-style runtime, MTP drafts, tensor vs layer split
```

Both are collected in [measurements.md](https://github.com/xxDoman/strata-gfx906/wiki/measurements), each under its own heading.

## What went wrong, and stays written down

Sections are added, never deleted — the traps below cost real evenings, and they repeat:

- **The helper card kills the start when the whole expert set fits on the main card.** The engine
  exits with `CUDA1 experts: no unclaimed experts remain` and no trace in the kernel. Symptom,
  cause and the two log lines to compare before you enable it: [measurements.md](https://github.com/xxDoman/strata-gfx906/wiki/measurements).
- **The config file is written when you press Start**, so a container that autostarts loads the
  *previous* model and dies with `missing model shard`.
- **Strata's community report reads nothing on AMD** — upstream bug in their own benchmark
  (driver and card names); our image carries a two-line fix, proposed upstream as
  [#1974](https://github.com/Niko1221/Strata/pull/1974).

## Links

- Docker Hub: <https://hub.docker.com/r/xxdoman/strata-mi50>
- Upstream engine: <https://github.com/Niko1221/Strata> (MIT)
- Strata's community benchmark results: `bench/results/` upstream, `docs/COMMUNITY_BENCHMARKS.md`
