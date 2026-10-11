# Rankings — one number per bar

The same community results as the table on [where-we-stand](where-we-stand), but as two bar charts, so
the spread is visible at a glance. **Each bar is the first figure that entry states** (its shortest
prompt, usually 4K or 8K) — not an average, and not a like-for-like benchmark. Entries that state no
single comparable number are left out; the full picture, with every regime column, is in the table on
[where-we-stand](where-we-stand).

<!-- charts -->

## Decode, side by side

```
  5090 + IQ2_XS                        179.4 / 175.7 / 165.0   (4K / 32K / 128K, old suite)
  R9700 32 GB + IQ3_S                  87.6 - 101.9            (product-style run)
  2x TITAN RTX 24 GB + IQ3_S           70.9 / 77.3 / 71.1      (262,144-token context)
  Strix Halo + IQ4_XS                  59.2 / 57.8 / ...
  RX 9070 16 GB + IQ3_XXS              58.7 / 57.9 / 57.9
  RX 9060 XT 16 GB + IQ2_XS            52.7 - 57.9             (8,019-token inputs)
  2x MI50 16 GB (gfx906) + IQ1_M       50.1 / 47.8 / 45.7      (v0.1.38 + #637-#640)
  ours, IQ1_M coder, 48 GB             49.4 chat / 49.5 agent  (new suite)
  RTX 5060 Ti WSL2 + IQ3_S             48.2 / 47.7
  ours, IQ3_XXS, 48 GB                 44.0 chat / 41.7 agent  (new suite)
  2x P40 24 GB + IQ3_S                 35.0
  Radeon Pro VII 16 GB (gfx906)        24.2 / 24.0 / 23.7
  2x Quadro RTX 4000 8 GB              18 - 23                 (73-74k-token prompts)
  2x Arc Pro B60 24 GB + IQ1_M         11.9                    (11-token prompt, by-hand run)
```

## Prompt (prefill), side by side

```
  2x TITAN RTX 24 GB + IQ3_S           868.9 / 1548.9 / 1626.9
  Strix Halo + IQ4_XS                  969 / 1,067 / 1,031
  RX 9070 16 GB + IQ3_XXS              586 / 804 / 833
  ours, IQ1_M coder, 48 GB             604.2 (4K) / 756.5 (16K)
  RX 9060 XT 16 GB + IQ2_XS            593.3 / 879.4           (8,019-token inputs, 4,096 / 8,192 chunk)
  ours, IQ3_XXS, 48 GB                 546.9 (4K) / 621.8 (16K)
  2x P40 24 GB + IQ3_S                 350 / 558
  2x MI50 16 GB (gfx906) + IQ1_M       321 / 523 / 517
  Radeon Pro VII 16 GB (gfx906)        350 / 339 / 284
  RTX 5060 Ti WSL2 + IQ3_S             343 / 598
```

Two caveats that apply to both charts: rows measured with the **old** script took decode on long
prompts while our rows come from the 0.1.43 **community suite**, and anything on **Linux CUDA
0.1.43** may be carrying the `STRATA_ADAPT_OVERLAP` regression
([#1964](https://github.com/Niko1221/Strata/issues/1964)) unless the entry says otherwise.
