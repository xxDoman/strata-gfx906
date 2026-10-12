# Where we place in Strata's community results

Upstream keeps a community list in `docs/COMMUNITY_BENCHMARKS.md` and the folders behind it in
`bench/results/`. This page puts all of it on one screen **with the regime kept visible**, because those
numbers come from different models, quantisations, contexts, harness versions and engine releases — a
bare tok/s ranking would be a lie. Two caveats before any comparison:

- **Harness.** Entries marked `old` were measured with the pre-0.1.43 script (4K / 32K / 128K prompts,
  256-token outputs); `new` means the 0.1.43 community suite (chat, fresh 4K and 16K, agent session).
  Only the prompt rows at ~4K are close to comparable across the two.
- **Engine.** Anything on Linux CUDA 0.1.43 may carry the `STRATA_ADAPT_OVERLAP` regression
  ([#1964](https://github.com/Niko1221/Strata/issues/1964)) unless the entry says otherwise; upstream made
  that overlap opt-in again in 0.1.43.1 ([#2010](https://github.com/Niko1221/Strata/issues/2010)).

Our two rows are marked *(ours)* — they live in [PR #1978](https://github.com/Niko1221/Strata/pull/1978)
and are not merged upstream yet. Everything else is copied from the entries, numbers verbatim.

| date | hardware | VRAM | engine | model | ctx | harness | numbers, as written in that entry | folder |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-11 | **2x gfx906: MI50 32 GB + Radeon VII 16 GB — ours** | 48 GB | 0.1.43 | IQ1_M coder | 131,072 | new | chat decode **49.4** (n=3); 4K prompt **604.2**; 16K prompt **756.5**; agent decode 49.5; first token 0.60 / 6.68 / 21.26 s | [PR #1978](https://github.com/Niko1221/Strata/pull/1978) |
| 2026-10-11 | **same box — ours** | 48 GB | 0.1.43 | IQ3_XXS | 131,072 | new | chat decode **44.0** resident / 41.2 with `--mmap-experts`; 4K prompt 546.9 / 473.6; 16K 621.8 / 543.9 | [PR #1978](https://github.com/Niko1221/Strata/pull/1978) |
| 2026-10-12 | **same box — ours, next engine** | 48 GB | 0.1.43.1 | IQ3_XXS | 131,072 | new | same config (`--mmap-experts`): chat decode 41.7; 4K prompt 460.7; 16K prompt **544.9**; agent decode 43.4 — level with the row above (16K within 0.2%), hotfix measured as free | [run 3](community-benchmark.md) |
| 2026-09-30 | RTX 5090, Core Ultra 9 285K, 64 GB RAM | — | 0.1.29 | IQ2_XS | — | old | Median decode throughput was **179.4 tok/s at 4,096 prompt tokens, 175.7 tok/s at 32,768, and 165.0 tok/s at 128,000**. These are synthetic code-expla | [2026-09-30-community-rtx-5090](../bench/results/2026-09-30-community-rtx-5090/README.md) |
| 2026-10-03 | 2x AMD Instinct MI50 16 GB (gfx906), Xeon E5-2666 v3, 32 G | 16 GB | 0.1.38 | IQ1_M | — | old | The median decode throughput was **50.1 tok/s at 4,096 prompt tokens, 47.8 tok/s at 32,768 and 45.7 tok/s at 128,000**. Prompts were read at 321, 523  | [2026-10-03-community-2x-mi50](../bench/results/2026-10-03-community-2x-mi50/README.md) |
| 2026-10-04 | 2x Intel Arc Pro B60 24 GB, Ryzen 5 5600, 64 GB RAM | 24 GB | — | IQ1_M | — | old | by-hand `--tokens` run, 11-token prompt, 128 greedy tokens: **11.9 tok/s** (11.2 to 11.9 over five builds that differ only in experiments), coherent P | [2026-10-04-community-2x-arc-pro-b6](../bench/results/2026-10-04-community-2x-arc-pro-b60/README.md) |
| 2026-10-07 | 2x NVIDIA Quadro RTX 4000 8 GB, Xeon E5-2620 v3, 96 GB RAM | 8 GB | — | Swift-Qwen3.8 | — | ? | measured deep-context prompt ingestion (73k–74k tokens at 100–250 tok/s, 18–23 tok/s decode) and production pipeline comparison against a 12B model. | [2026-10-07-community-2x-rtx-4000](../bench/results/2026-10-07-community-2x-rtx-4000/README.md) |
| 2026-10-08 | 2x TITAN RTX 24 GB (sm_75, NVLink present but unused), Xeo | 24 GB | 0.1.40.3 | IQ3_S | — | old | Decode 70.9/77.3/71.1 tok/s, prompt 868.9/1548.9/1626.9 tok/s at those three lengths, 8,649 cached experts, needles 6/6 at 32k and 128k. | [2026-10-08-community-2x-titan-rtx-](../bench/results/2026-10-08-community-2x-titan-rtx-0.1.40.3/README.md) |
| 2026-10-08 | Tesla V100-SXM2-32GB (sm_70), Threadripper 2990WX without  | 32 GB | 0.1.41 | IQ4_XS | — | ? | **confirms the opt-in Volta decode kernels** (`STRATA_SM70_TABLE=1`) that [NVIDIA_V100.md](NVIDIA_V100.md) asks a V100 owner to check: decode **+9.8%  | [2026-10-08-community-v100-sm70-tab](../bench/results/2026-10-08-community-v100-sm70-table/README.md) |
| 2026-10-08 | one AMD Radeon AI PRO R9700 32 GB, two EPYC 9334 CPUs, 503 | 32 GB | — | IQ3_S | — | ? | The product-style IQ3_S configuration generated **87.6–101.9 tokens/s**, taking the median at each | [2026-10-08-community-r9700-linux](../bench/results/2026-10-08-community-r9700-linux/README.md) |
| 2026-10-08 | RTX 4070 12 GB, Core i5-12600KF, 32 GB DDR4 | 12 GB | — | IQ2_XS | — | ? | Measured **2026-10-08** by [Hcl192088](https://github.com/Hcl192088), on one consumer GPU with 12 GB installed VRAM and 32 GB DDR4 system RAM. The mos | [2026-10-08-community-rtx4070-iq2-x](../bench/results/2026-10-08-community-rtx4070-iq2-xs/README.md) |
| 2026-10-09 | Radeon 8060S / Ryzen AI Max+ 395 Strix Halo laptop (HP ZBo | — | 0.1.41 | IQ4_XS | — | old | 4–6 fresh-process runs at 8,192 / 32,768 / 131,072 prompt tokens: prompt 969 / 1,067 / 1,031 tok/s, decode 59.2 / 57.8 / 42.0 tok/s (medians). | [2026-10-09-community-strix-halo-la](../bench/results/2026-10-09-community-strix-halo-laptop-70w/README.md) |
| 2026-10-09 | RTX 3060 12 GB, Core i7-12700, 64 GB RAM | 12 GB | 0.1.41 | Q2_0 | — | ? | Prompt throughput in tok/s is freshly read tokens * 1,000 / engine prompt milliseconds. Decode throughput comes from the engine, not tokens divided by | [2026-10-09-community-rtx-3060-0141](../bench/results/2026-10-09-community-rtx-3060-0141/README.md) |
| 2026-10-09 | RTX 5060 Ti 16 GB + Xeon E5-2680 v4 (Windows 10) | 16 GB | 0.1.41 | IQ1_M | — | ? | (liczby tylko w tabelach) | [2026-10-09-community-rtx-5060-ti-e](../bench/results/2026-10-09-community-rtx-5060-ti-e5-2680-v4/README.md) |
| 2026-10-09 | RTX 5060 Ti 16 GB under WSL2, Ryzen 7 3700X, 128 GB RAM | 16 GB | 0.1.41 | IQ3_S | — | ? | single runs only (decode 48.2/47.7 tok/s, prompt 343/598 tok/s at 3.8K/19.2K), no needle test, no TTFT. | [2026-10-09-community-rtx-5060ti-ws](../bench/results/2026-10-09-community-rtx-5060ti-wsl2-iq3_s-0141/README.md) |
| 2026-10-09 | Radeon Pro VII 16 GB (gfx906), Xeon E5-2666 v3, 125.7 GiB  | 16 GB | 0.1.40.4 | IQ2_XS | — | ? | decode 24.2/24.0/23.7 tok/s, prompt 350/339/284 tok/s at 4K/32K/128K, two sweeps with telemetry. | [2026-10-09-community-radeon-pro-vi](../bench/results/2026-10-09-community-radeon-pro-vii-16gb/README.md) |
| 2026-10-10 | AMD Radeon RX 9070 16 GB (gfx1201), Ryzen 7 5800X3D, 64 GB | 16 GB | 0.1.41 | IQ3_XXS | — | old | Decode 58.7/57.9/57.9 tok/s, prompt 586/804/833 tok/s at those three lengths, needles 6/6 at 33.5k and 130k; | [2026-10-10-community-rx-9070](../bench/results/2026-10-10-community-rx-9070/README.md) |
| 2026-10-10 | AMD Radeon RX 9060 XT 16 GB (gfx1200), Ryzen 7 9800X3D, 64 | 16 GB | 0.1.40.3 | IQ2_XS | — | ? | prefill 593.3 / 879.4 tok/s at 8,019-token inputs (4,096 / 8,192 chunk); decode 52.7-57.9 tok/s; weighted engine decode 49.61 vs 42.52 for the two con | [2026-10-10-community-rx-9060-xt](../bench/results/2026-10-10-community-rx-9060-xt/README.md) |
| 2026-10-10 | 2x Tesla P40 24 GB, Xeon E5-2699 v3, 125 GB RAM | 24 GB | 0.1.41 | IQ3_S | — | ? | decode 35.0 tok/s, prompt 350/558 tok/s at 3.9K/21.9K, needles 6/6, conversation checkpoints. | [2026-10-10-community-2x-p40-iq3_s](../bench/results/2026-10-10-community-2x-p40-iq3_s/README.md) |

The two rankings of these same numbers — as bar charts — are on [rankings](rankings).

## What that placement actually is, in facts

- **Decode puts us mid-field**: above the two other gfx906 entries (2x MI50 16 GB: 50 tok/s, single
  Radeon Pro VII: 24 tok/s) and above 2x P40 (35), level with an RTX 5060 Ti under WSL2 (48) and with
  2x MI50 16 GB (50); below an RX 9070 (58.7), a Strix Halo (59), 2x TITAN RTX (71-77), an R9700
  (88-102) and an RTX 5090 (179).
- **Prompt is where this box is strong**: 547-756 tok/s against 284-523 tok/s on the other gfx906
  entries — the same family, older 16 GB cards, engines 0.1.38 and 0.1.40.4. Our two image levers
  (the rocBLAS solution table + the FP16 prompt path it needs) act on exactly this axis; ours is
  v0.1.43.1 with both on, and the rocBLAS table alone measured +9.5% / +10.8% prompt on IQ3 in an A/B
  on this box ([measurements](measurements.md)).
- **48 GB of gfx906 is unique here.** Every other entry is one card or two cards of 8-32 GB; the
  other gfx906 rows are 16 GB. Ours also carries the largest quantisations in the list
  (IQ1_M and IQ3_XXS of the Uncensored model, 41 GB per shard) at a 131,072-token context, resident.
- **Our rows are the only `new`-harness rows**, so they cannot be dropped straight into the old
  tables — which is exactly why both harnesses are still shipped in the image.

Sources: the entries themselves under `bench/results/`, upstream's summary list, and our own runs in
[community-benchmark.md](community-benchmark.md). Regenerate by hand when the list changes.
