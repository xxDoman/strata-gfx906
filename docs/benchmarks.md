# Benchmarks — the measured tables

Moved here from the repository's front page, **verbatim** (same machine, same runs, same caveats). The
image quoted in the rows is the published `0.1.43.x` line; the engine's own sums and the local
`0.1.44.1.x` builds are on [the engine index](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/README.md).

---

## Benchmarks

Machine: LianLi, Linux 7.0.0-38, 61 GB RAM, ROCm 7.2.1 with the host gfx906 rocBLAS.
MI50 (32 GB, gfx906) + Radeon VII (16 GB, gfx906), same box. Model: Qwen3.8-Flash-Next.
Medians of 3-4 runs. Both cards at their **default socket caps** — MI50 225 W, Radeon VII 250 W (this
box also has the UPP limit `TdcLimitGfx` at 150 on the MI50; see Notes & limitations before comparing).

| # | master | second card | role of second | quant | ctx | kv | low-RAM | mmap | prompt tok | prefill tok/s | TTFT s | decode tok/s | hit % | PCIe % | build |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | MI50 (0) | Radeon VII (1) | helper | IQ3_XXS | 32000 | int8 | off | off | 11552 | 365.5 | 31.6 | 39.6 | 99.6 | 13.2 | 0.1.40.v2 |
| 2 | MI50 (0) | Radeon VII (1) | helper | IQ3_XXS | 32000 | int8 | off | off | 11552 | 380.0 | 30.4 | 38.7 | 99.6 | 13.2 | 0.1.39.v3 |
| 3 | Radeon VII (1) | MI50 (0) | helper | IQ3_XXS | 32000 | int8 | off | off | 11552 | 140.5 | 82.4 | 36.8 | — | — | 0.1.39.v3 |
| 4 | Radeon VII (1) | MI50 (0) | helper | IQ4_XS | 32000 | int8 | on | on | 775 | — | 16.9 | 30.1 | 91.6 | 48.4 | 0.1.39.v2 |
| 5 | Radeon VII (1) | MI50 (0) | helper | IQ4_XS | 32000 | int8 | on | on | 93 | — | 4.0 | 33.9 | 92.2 | 71.8 | 0.1.39.v2 |
| 6 | MI50 (0) | — | — | IQ3_XXS | 32768 | int8 | off | off | 11552 | 237.9 | 3.9 | 32.4 | — | — | 0.1.35+MMQ+dp4a |
| 8 | MI50 (0) | Radeon VII (1) | split | IQ3_XXS | 65536 | q4_0 | off | off | 16384 | 532.1 | 26.7 | 35.1 | — | — | 0.1.42 + table |
| 9 | MI50 (0) | Radeon VII (1) | split | IQ3_XXS | 65536 | q4_0 | off | off | 28496 | 548.2 | 51.7 | 36.8 | — | — | 0.1.42 + table |

Rows 8-9 are what the configurator's toggle buys on this box: same engine, same config, the rocBLAS
table on at `--spec 3`, **MI50 at its default 225 W socket cap**. Against **the same build without the
table** the prefill at 32k was 500.2 tok/s, i.e. **+9.6%**. Against the **previous engine** (0.1.41 with
the same table, same cap, same config): **+5.9% at 16k and +0.9% at 32k** — level at 32k, so the gain
measured here is the **table**, not the version bump. The tail-skip toggle changed nothing here (VRAM
hit was ~100%: with every expert resident there is nothing to skip) — it is worth testing on a
**single 16 GB card**, where the hit rate drops.

Pool, both cards, TCP over loopback — coordinator Radeon VII (1), worker MI50 (0):

| split | layers coordinator | layers worker | arena MiB | slots | experts on GPU | decode tok/s | tokens / time | windows |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 24 | 0-23 | 24-47 | 17237 | 12288 | 21358 | 42.0 | 91 / 3.1 s | 77 |

Pool flags: `--pool-split 24 --pool-wire f32`, quant IQ2_XS, ctx 8192, spec 2, `--vram-reserve-mib 1024`.
The RTX 4070 row that used to sit here is **not** measured on this box and has been dropped; all rows
above are **this box** (the ids are kept from the full record).
