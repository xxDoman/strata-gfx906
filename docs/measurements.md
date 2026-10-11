# Measurements — every number we took, and the traps we walked into

**English abstract.** This is the running record of measuring the Strata engine, and separately
llama.cpp on the same pair, on **2x AMD gfx906: Instinct MI50 32 GB + Radeon VII 16 GB**, ROCm 7.2.1,
61.6 GiB RAM. Every number carries the regime it was measured in — power cap, quantisation, context,
mode (helper / layer split / single), image — and the two engine families are never mixed, because a
number without its regime is not a result. The traps we hit are written in place, next to the
measurement that exposed them, and sections are added rather than rewritten: that part is the
project's memory.

*Poniżej oryginalny dokument roboczy (po polsku) — historia projektu, rozbudowywana, nic nie jest
usuwane. Nowe sekcje dopisujemy na koniec, z data i nazwanym regime.*

---

# OPIS SILNIKA — MATERIAŁY: wszystkie pomiary z punktem odniesienia

Zasada: **każda liczba musi mieć podane (a) co porównano, (b) na czym, (c) względem czego.**
Bez tego nie wchodzi do opisu („+25%" bez odniesienia nic nie mówi).

Zebrane 2026-10-10. Źródła w `~/hermes_dane/` (root, `strata-docker/`, `strata-mi50/`, `bench-141/`, `rocm-tune/`, `flash-lab/`).
Pliki z surowymi logami zostają — patrz sekcja „Gdzie są surowe dane" na końcu.

---

## 0. NAJWAŻNIEJSZE: to są DWIE różne rodziny wyników — nie mieszać

| rodzina | silnik | bazowy decode | gdzie |
|---|---|---|---|
| **STRATA** (obraz `xxdoman/strata-mi50`) | silnik Strata, gfx906 | dziesiątki t/s (np. iq2 ~40, iq3 ~35) | `strata-docker/`, `strata-mi50/` |
| **llama.cpp / fork GenerelSchwerz** (qwen4exp) | llama.cpp + MoE expert cache | **18,99 t/s** (RPC MI50+4070, 44 GB VRAM) | `flash-lab/`, `IQ2-*`, `expert-cache-*`, `mtp-*` |

Każda liczba niżej jest opatrzona, z której rodziny jest. Mieszanie ich daje bezsens.

---

## 0b. KARTY — twarde dane z tej maszyny (2026-10-10)

### MI50 32 GB — **VRAM 32 GB**
```
lspci      03:00.0  1002:66a1  "Vega 20 [Radeon Pro VII/Radeon Instinct MI50 32GB]" (rev 01)
gfx        gfx906, 60 CU / 60 SM @ ~1,73 GHz, HBM2 ~1 TB/s
PCIe       endpoint trafia na Gen4 (LnkSta 16 GT/s x16), ALE mostek nad kartą (01:00.0) stoi na
           8 GT/s (Gen3) -> EFEKTYWNIE PCIe 3.0 x16. (Fakt techniczny, NIE wąskie gardło —
           patrz „MIT OBALONY" niżej.)
VRAM       34 342 961 152 B = 32 GB  (/sys/class/drm/card1)
rocm-smi   GPU[0]   GUID 16893
rola       karta GŁÓWNA (master). Od niej zależy prefill (MI50-master 361 tok/s vs Radeon-master 139, 2,6x)
moc        cap 80 W (cichy tryb, świadomy kompromis) / max 225 W; UPP TdcLimitGfx 150 A, Soc 50 A
```
W logu silnika: `layer split auto: CUDA0 60 SMs at 1.73 GHz`.

### Radeon VII — **VRAM 16 GB**
```
lspci      09:00.0  1002:66af  "Vega 20 [Radeon VII]" (rev c1)
gfx        gfx906, 60 CU / 60 SM @ ~1,80 GHz, HBM2 ~1 TB/s
PCIe       endpoint Gen3 x16 (LnkSta 8 GT/s x16), ale mostek nad kartą (07:00.0) stoi na x4
           -> EFEKTYWNIE PCIe 3.0 x4. (Fakt techniczny, NIE wąskie gardło — patrz „MIT OBALONY".)
VRAM       17 163 091 968 B = 16 GB  (/sys/class/drm/card2)
rocm-smi   GPU[1]   GUID 17665
rola       karta WYŚWIETLAJĄCA (jedyna z wyjściem wideo). Jako helper GPU do ekspertów NIE daje nic —
           powód: host-mediated round-trip zjada oszczędność (dostał 5689 ekspertów / 7,65 GiB),
           a nie szerokość linku (PCIe i tak nie jest wysycone).
moc        cap 250 W
```
W logu silnika: `layer split auto: CUDA1 60 SMs at 1.80 GHz`.

**Łańcuch mostków (twarde dane, `sudo lspci -vv`):**
```
MI50:    [root] -> 01:00.0  16GT/s x16 CAP, LnkSta 8GT/s  x16  ("downgraded" — sam mostek, nie karta)
              -> 02:00.0  LnkSta 16GT/s x16
              -> 03:00.0  MI50,     LnkSta 16GT/s x16
Radeon:  [root] -> 07:00.0  8GT/s x16 CAP, LnkSta 8GT/s  x4   ("downgraded" — sam mostek, nie karta)
              -> 08:00.0  LnkSta 8GT/s  x16
              -> 09:00.0  Radeon VII, LnkSta 8GT/s x16
```
### MIT OBALONY: PCIe NIE jest wąskim gardłem

Szerokość linku to fakt techniczny, ale **nie tłumaczy wydajności**. Zmierzone wykorzystanie PCIe
pod obciążeniem: **13,2% i 48,4%** (logi silnika) — maks ~50%, nigdy wysycone. Z tego:

- link x4 na Radeonie **nie jest** powodem, że jako helper nie dawał nic — powodem jest
  host-mediated round-trip, nie przepustowość,
- MI50 na efektywnym Gen3 x16 **nie jest ograniczony linkiem**,
- prawdziwe wąskie gardła: prefill bez tensor cores (185 vs 689 tok/s vs RTX) i trafienia w HBM2
  na decode. Nie PCIe.
- 13,6 vs 3,6 GB/s to różnica przepustowości host->device, ale skoro nigdy nie schodzimy powyżej
  ~50%, ta różnica **nie przekłada się na tok/s**.
- **Mocniejszy dowód, z samego Radeona VII (16 GB):** przy 83,7% trafień cache przez PCIe dociągnięto
  **0,1% routowanych ekspertów (58 z 63 840)**. Eksperty siedzą w HBM2 albo liczy je CPU — PCIe
  praktycznie nie bierze udziału. Szerokość linku to nie temat.

**Do opisu:** MI50 to wersja 32 GB tej samej architektury (gfx906) — ten sam układ co Radeon VII,
ale **2× VRAM**, czyli 2× więcej ekspertów trafia z HBM2 bez żadnego ruchu. Wąskim gardłem jest
pojemność HBM2 i trafienia cache, nie link. Liczby z sekcji 1–3 są zmierzone na MI50 (32 GB);
wyniki dla samego Radeona VII (16 GB) — sekcja 7.

---

## 1. TABLICA rocBLAS gfx906 (nowa robota, 2026-10-10)

Zmienna: **tabela rocBLAS** (`STRATA_ROCBLAS_TUNING`), off vs on. Silnik: 0.1.41 + czytnik #981
(`bin/strata-gfx906-0.1.41-roc981`). Miara z logu silnika, przeplot off/on/off/on.

### 1a. Config bench, split [0,1], ctx 65536, kv q4_0, model IQ3_XXS — **@ 80 W**
| co | off | on | delta | odniesienie |
|---|---|---|---|---|
| prefill 16k | 337,3 | 369,4 tok/s | **+9,5%** | off = to samo bez tabeli (F16=1) |
| prefill 32k | 347,4 | 384,8 tok/s | **+10,8%** | jw.; TTFT -8,7% / -9,7% |
| decode | 29,9 | 29,4 tok/s | ~0 | tabela dotyka tylko gęstych GEMM promptu |

Plik: `strata-docker/bench-141/RAPORT-roc981.md`, `wyniki-roc981.csv`, `results/{off1,on1,off2,on2}.roc981.log`.

### 1b. Obraz testowy, config DOMYŚLNY (1 karta MI50, ctx 32768, kv int8) — **@ 225 W** (bez limitu SMI)
| co | off | on | delta |
|---|---|---|---|
| prefill 32k | 434,1 | 449,8 tok/s | **+3,6%** (ramiona rozdzielone) |
| prefill 16k | 430,6 | 443,6 tok/s | +3,0% (niepewne — jeden przebieg rozjechany) |

Plik: `wyniki-roc981-img.csv`, `results/*.roc981-img.log`. **Ten test nie ma odpowiednika wcześniejszego
— zapisany jako osobny punkt, nieporównywalny 1:1.**

### 1c. PEŁNA MATRYCA jak przy sterownikach — split [0,1], ctx 65536 — **@ 225 W**
| kwant | dl | off | on | delta |
|---|---|---|---|---|
| iq2 | 16k / 32k / 60k | 564,1 / 580,5 / 567,4 | 631,2 / 652,1 / 634,2 | **+11,9% / +12,3% / +11,8%** |
| iq3 | 16k / 32k / 60k | 482,6 / 500,9 / 481,9 | 502,4 / 543,3 / 533,6 | +4,1% / +8,5% / +10,7% |
| q4km | 16k / 32k / 60k | 201,6 / 230,7 / 226,5 | 208,2 / 243,2 / 242,8 | +3,3% / +5,4% / +7,2% |

Wzorzec: zysk tabeli **rośnie z długością promptu** (iq3 +4→+11%, q4km +3→+7%), a **maleje z kwantem**
(iq2 największy, ~+12%). Decode bez zmian w każdym punkcie.

Plik: `wyniki-roc981-split.csv`, `results/{iq2,iq3}-{off,on}.roc981-split.log`, log `run_roc981_ab.log`.

### 1d. Dźwignia FP16 (`STRATA_HIP_PROMPT_F16=1`) — wyliczona z 1c
Porównanie z **wcześniejszymi przebiegami na tym samym configu** (sterowniki, sekcja 2 — tam F16 było WYŁĄCZONE):

| kwant | poprzednie (bez F16, 7.2.1) | off (F16=1) | → sam F16 | on (F16+tabela) | → razem vs poprzednie |
|---|---|---|---|---|---|
| iq2 | 495,7 / 507,0 / 497,1 | 564,1 / 580,5 / 567,4 | **+13,8% / +14,5% / +14,1%** | 631,2 / 652,1 / 634,2 | **+27,3% / +28,6% / +27,6%** |
| iq3 | 407,5 / 442,7 / 432,7 | 482,6 / 500,9 / 481,9 | +18,4% / +13,1% / +11,4% | 502,4 / 543,3 / 533,6 | +23,3% / +22,7% / +23,3% |

⚠ **Uwaga do opisu:** ramię „off" w 1c ma F16=1, więc NIE równa się poprzednim przebiegom.
Dwie dźwignie: F16 ~+14%, tabela na niej ~+12%; razem ~+28% wobec starego 7.2.1.

### Mechanizm (z logu, potwierdzone)
```
prefill gemm: rocBLAS tuning enabled (103 rows, 78 with a solution, gfx906, rocBLAS 5.2.0.dabb6df2b9)
```
Zawsze z ENV obrazu lub `-e STRATA_ROCBLAS_TUNING=/tuning`. Nazwa pliku tabeli = wersja runtime (brak mismatch).
W ramieniu iq2-on wybrano 1475 rozwiązań, 2 odmowy (status 6), 1417 „no row" → default.
Per-kształtowe linie (`rocBLAS solution ...`) widać tylko przy `STRATA_ROCBLAS_VERBOSE=1`.

### Dlaczego to w ogóle działa (bloker, który naprawiliśmy)
PR #981 jest ogrodzony `STRATA_ENABLE_HIP` (wave32 RDNA); na gfx906 idziemy `STRATA_HIP_GFX906=ON`,
przy którym `STRATA_ENABLE_HIP` zostaje OFF → `cmake/hip_backend.cmake` się nie włącza → makro
`STRATA_ROCBLAS_AVAILABLE` nie trafia do `gemm.cu` → **czytnik kompilowany out** (zbudowane bez zmian
nie miało ani jednego symbolu). Nasza poprawka: 2 miejsca w `CMakeLists.txt` (detekcja w bloku gfx906
+ bramka `... OR STRATA_HIP_GFX906`). Diff + opis: `patches/0.1.41-roc981-full.diff`, `patches/0.1.41-roc981-README.md`.

---

## 2. STEROWNIKI (ROCm): 7.2.1 golden vs 7.14 vs 10.1 (2026-10-10)

Silnik 0.1.41 (bez tabeli, **bez F16**), split [0,1], ctx 64k, 16k/32k/60k, **@ 225/250 W**. Miara z logu.

| kwant dl | 7.2.1 | 7.14 | 10.1 |
|---|---|---|---|
| iq2 16k | 495,7 | 481,0 | 483,8 |
| iq2 32k | 507,0 | 499,0 | 500,8 |
| iq2 60k | 497,1 | 490,0 | 491,1 |
| iq3 16k | 407,5 | 414,7 | 394,3 |
| iq3 32k | 442,7 | 445,9 | 435,5 |
| iq3 60k | 432,7 | 432,8 | 424,7 |
| q4km 16k | 211,6 | 198,9 | 184,4 |
| q4km 32k | 245,8 | 243,7 | 230,5 |
| q4km 60k | 236,6 | 224,6 | 223,3 |

Wniosek: nowsze libki dają **decode ~+5%**, prefill **-1% (7.14) / -3% (10.1)**. 7.2.1 golden jest konkurencyjny.
Plik: `strata-docker/bench-141/RAPORT-STEROWNIKI.md`, `wyniki-3way.csv`.
**To jest punkt odniesienia dla sekcji 1d.**

---

## 3. OBRAZY Strata 0.1.39 → 0.1.41 (2026-10-04…10-09)

| porównanie | warunki | wynik | odniesienie | plik |
|---|---|---|---|---|
| nasz obraz vs czysty master 0.1.41 | split, 16k/32k/60k, iq2/iq3/q4km, 225/250 W | zgodność ~1% na wszystkich punktach | A=nasz obraz, B=master (`python -m serve.server`) | `bench-141/RAPORT-0.1.41.md` |
| 0.1.39 vs 0.1.40 (bez dp4a) | MI50 master, IQ3_XXS, ta sama sesja | prefill 358-359 vs 358 (= **-22% się NIE potwierdza**), decode 39,2 vs 40,9 | ramię A = 0.1.39, B = 0.1.40 | `strata-docker/STAN-NA-JUTRO.md`, `PR-KOMENTARZ-EN.md` |
| 0.1.39 vs 0.1.38+patch | IQ2_XS, 4k+256, spec3 | decode 42,5 vs 32,4 (**+30%**), prefill 293 vs 294 | 0.1.38 z naszym patchem | `65279611…` (brain), `strata-docker/STAN-0.1.41.md` |
| 0.1.40.4a vs wcześniej | zakładka Benchmark | prefill -0,1%, **decode +22,7%** | poprzedni obraz | `strata-docker/STAN-0.1.40.4a.md` |

## 4. gfx906 — co dawało zysk (skumulowane, do opisu „dlaczego szybciej")

| element | efekt | odniesienie | plik |
|---|---|---|---|
| **MMQ** włączone na gfx906 | **prefill +1,41×** | ta sama binarka z MMQ wyłączonym flagą | `strata-mi50/TODO-zrobic.md`, `TODO-ollama-llama.md` |
| **dp4a** (v_dot4_i32_i8) | **decode +12…17%** (pomiar A/B: 20,4 → 23,7 tok/s) | build bez dp4a | `strata-mi50/TODO-zrobic.md`, `dockerhub-strata-mi50-description.md` |
| **expert cache (Strata)** — krzywa na MI50 | cache 13109 (26,57 GiB, hit 95,6%, decode 21,5) vs 1500 (3,04 GiB, 51,2%, 17,7) → **cache daje 3,8 tok/s (21%) za 8× VRAM** | kolejne rozmiary cache, ten sam prompt | `strata-mi50/README.md` sekcja 4d, `krzywa-cache.txt` |
| brakujące eksperty NIE idą przez PCIe | major_faults=0 przy każdym rozmiarze, CPU SRE 52% stałe | jw. | `da92bfe8…` (brain) |
| **Radeon VII jako helper** | **nic nie daje** (prefill ten sam, decode niższy 39,3 vs 40,9) | sama MI50 | `90aaa8d7…` (brain), `RAPORT-0.1.41.md` |
| skan repo pod blokady gfx906 | **brak nowych blokad**; jedyne realne małe: `native_qsa_score.cu` (tf32 vs F32 dot) | lista `#if __HIPCC__` | `1497bc57…` (brain) |
| MTP na Strata/llama (qwen4exp) | MTP spowalnia decode **27%** gdy eksperty w RAM (llama.cpp) | bez MTP | PR #29887 (llama.cpp, video) |

## 5. MOC, TERMOSTYKA, UPP (kontekst dla każdej liczby „tok/s")

| parametr | wartość | uwaga | plik |
|---|---|---|---|
| power1_cap MI50 | **80 W** (tryb cichy) / max 225 W | świadomy kompromis Dominika; koszt ~10-15% vs UPP 300 A | `strata-mi50/TODO-zrobic.md`, `mi50/MI50-DEFAULT-vs-TRYBY.md` |
| UPP TdcLimitGfx / Soc | 150 A / 50 A | jw. | `mi50/MI50-DEFAULT-vs-TRYBY.md` |
| junction, cel | max 90 °C (bez limitów dochodziło 110 °C) | po modyfikowanym chłodzeniu | `strata-mi50/TODO-zrobic.md` |
| pomiar 225 W, tabela | med 157–179 W, max 219–258 W, junction ~61 °C | sekcja 1b/1c | `results/*.power.txt` |

**Reguła:** każda liczba prefill/decode z sekcji 1–3 musi mieć dopisane, przy jakiej mocy i UPP była zmierzona.

## 6. Poza Stratą — llama.cpp / fork / MTP / Ollama (rodzina druga, baseline 18,99)

| element | wynik | odniesienie | plik |
|---|---|---|---|
| mainline RPC (MI50+4070), IQ4_XS | 18,99 t/s decode | — (baseline) | `flash-next-PELNY-STAN.md` |
| fork GenerelSchwerz + cache | 20,28 t/s (**+1,3 t/s, 7%**) | mainline 18,99 | `fork-generelschwerz-wyniki-STAN.md` |
| MTP (PR #28243) + Q4_XS | 23,13-23,15 t/s (**+22%**) | base 18,99 | `mtp-rpc-wynik.md`, `STAN-KONCOWY.md` |
| IQ2_XXS + cache 360 | 20,23 t/s (**+21% nad rekordem 17,98**) | poprzedni rekord | `IQ2-cache-MI50-WYNIKI.md` |
| IQ4_XS + cache 224 | 19,15 t/s (4-bit) vs iq2cache352 19,89 | ten sam prompt | `IQ4_XS-cache-MI50-WYNIKI.md` |
| grouped decode HIP | -4% decode, -69% prompt | stara ścieżka | `grouped-decode-HIP-WYNIKI.md` |
| Ollama Flash-Next (1× MI50) | 14,00 t/s (warm) vs 11,69 (cold) = **+19,8%** | ta sama sesja | `ollama-flashnext-WYNIKI.md` |
| RPC MI50+4070 vs sama MI50 | 17,89 vs 15,77 (**+13%**) | sama MI50 | `flash-lab-WYNIKI.md` |
| satelita CPU (RPC po RAM) | **negatywny** | — | `satelita-cpu-test-STAN.md` |

---

## 7. SAM RADEON VII (16 GB) — ten sam test, ta sama metoda

Jedna karta (ROCR_VISIBLE_DEVICES=1), ctx 65536, 225 W. iq2 z pełnymi 3 długościami, iq3 na 16k/32k
(60k pominięte — przy ~148 tok/s to ~6 min na punkt). Uwaga: n=1 na punkt.

### 7a. Tabela rocBLAS off → on (prefill tok/s)
| kwant | dl | off | on | delta |
|---|---|---|---|---|
| iq2 | 16k / 32k / 60k | 244,3 / 246,8 / 247,3 | 248,2 / 249,1 / 246,6 | **+1,6% / +0,9% / -0,3%** |
| iq3 | 16k / 32k | 147,8 / 150,6 | 143,4 / 143,4 | **-3,0% / -4,8%** |

Na 16 GB tabela **nie daje nic** (iq2 w granicach szumu, iq3 lekko ujemny). Decode bez zmian.

### 7b. ori (czysty 0.1.41) vs nasz build — na Radeonie
| kwant | dl | ori | nasz (tabela+F16) | delta |
|---|---|---|---|---|
| iq2 | 16k / 32k | 244,9 / 246,8 | 248,2 / 249,1 | +1,3% / +0,9% |
| iq3 | 16k / 32k | 144,4 / 148,4 | 143,4 / 143,4 | -0,7% / -3,4% |

**Nasz build ≈ ori na 16 GB.** Nic nie psuje, ale i nic nie daje.

### 7c. Dlaczego — i to jest sedno całego obrazu
Na Radeonie eksperty w VRAM: **4975 z 24576 profili = ~20%** (16 GB). Resztę (~80%) liczy host.
Karta stoi na barierze: `GPU use 100%` przy **64 W z 250 W**, junction 92 °C — kręci się, nie liczy.
Pula CPU silnika: 6 wątków z 12 dostępnych (i5-12400F). Silnik sam pisze: przez PCIe dociągnięto
**0,1% routowanych ekspertów**.

Stąd porównanie, które wszystko tłumaczy:

| | VRAM | iq2 32k off → on | iq3 32k off → on |
|---|---|---|---|
| **split** (MI50 32 GB master) | 32 GB | 580,5 → 652,1 (**+12,3%**) | 500,9 → 543,3 (**+8,5%**) |
| **sam Radeon VII** | 16 GB | 246,8 → 249,1 (+0,9%) | 150,6 → 143,4 (-4,8%) |

**Zysk z tabeli rośnie z VRAM** — bo tabela poprawia gęste GEMM-y *promptu*, a te pomagają tylko
wtedy, gdy GPU nie czeka już na host. Na 16 GB karta czeka, więc nie ma czego przyspieszać.

**Do opisu:** to samo urywa mit „x4/szerokość linku". Wąskim gardłem 16 GB jest HBM2 (ile ekspertów
trafia) i robota hosta, nie link i nie GPU.

---

## 8. PLE (tablica Engram) — półki pamięci. iq2, split [0,1], 225 W

Silnik ma przełącznik `--ple-io direct|mmap|ram`:
`direct` = **DOMYŚLNE** (niebuforowany odczyt z SSD, tabela nigdy nie wchodzi do RAM ani cache),
`mmap` = page cache, `ram` = cała tabela mlockowana w RAM na starcie.

| tryb | prefill 16k / 32k | RAM |
|---|---|---|
| **direct** (domyślne) | 494,4 / 507,1 | OK — RSS ~35 GB, min MemAvailable 21,2 GB |
| **mmap** | 493,2 / 507,0 | OK — jw. |
| **ram** | — | **NIE WCHODZI** — RSS 0→28→54→**57 GB** w 15 s, MemAvailable **1187 MiB** z 61 GB → bezpiecznik ubił |
| **no-ple** | — | niewykonalne z `--native` (silnik: „the PLE key is native too") |

Wnioski:
- **direct = mmap = czysty 0.1.41** (495,7 / 507,0 z pomiaru sterowników). Półka SSD vs page cache
  **nie zmienia nic** — bo ruch tablicy to ~100-200 KB/token (≤8 MB/s przy ~40 tok/s), a domyślny
  `--ple-row-cache` (1M wierszy × 90 B ≈ 94 MB) łapie większość odczytów. Dysk nigdy nie staje się gardłem.
- **`--ple-io ram` nie mieści się** na tej maszynie (61 GB) — nawet dla iq2. Silnik loguje
  `PLE table locked in RAM (--ple-io ram) in 0.9 s`, ale potem RSS winduje do 57 GB.
- Kontrast z filmem (Kai, „End of VRAM-Bottlenecked LLMs"): tam RAM vs NVMe to klif 142,6 → 77,5 tok/s.
  U nas SSD vs cache to zero różnicy, a RAM w ogóle się nie mieści.

Pliki: `wyniki-ple.csv`, `results/{direct,mmap,ram}.ple-monitor.txt`, `configs/D-iq2-ple-*.json`, `run_ple.sh`.
**Pułapka własna:** stała nazwa kontenera (`strata-ple`) + dwa równoległe ramiona = kasowanie sobie kontenerów.
Bezpiecznik RAM działa — ubił ramię PRZED OOM-killerem jądra.

---

## 9. Silnik 0.1.42 na gfx906 — co się zmieniło i ile daje. iq3, split [0,1], 225 W

Wydany 2026-10-10 (16:10 UTC), **235 commitów / 300 plików** od 0.1.41.

**Nagłówek release (13-16% szybszy decode, do 30% na jednej karcie) jest CUDA-owy** — oba nowe
domyślne ustawienia (`STRATA_ROUTE_TAIL_SKIP=7` z PR #1668 oraz mierzony udział PCIe) są wprost
wyłączone na AMD. Ale to nie znaczy, że nic z tego nie mamy (patrz niżej).

**Bramka TAIL_SKIP działa na naszą korzyść.** W `src/program/generate.cpp` domyślna wartość jest pod
`#if !defined(STRATA_USE_HIP)`. Nasz build gfx906 definiuje TYLKO `STRATA_HIP_GFX906` (a `STRATA_USE_HIP`
należy do ścieżki wave32 RDNA), więc gałąź CUDA jest **prawdziwa** i domyślne 7 włącza się samo —
silnik loguje wprost `STRATA_ROUTE_TAIL_SKIP=7 is ON (default)`. Wartość czyta `getenv` w
`tail_skip_rank()`, więc przełącznik to zmienna środowiskowa (`=0` wyłącza).

**Tabela rocBLAS działa na 0.1.42 tak samo jak na 0.1.41** (mediana z 3 przebiegów, prefill @32k):

| ramię (iq3, split) | 16k | 32k |
|---|---|---|
| czysty 42 (`TAIL_SKIP=7` domyślne) | 473,0 | 502,6 |
| czysty 42 (`TAIL_SKIP=0`) | 488,5 | 500,2 |
| **42 + tablica** | **532,1** | **548,2** |

→ tablica **+9,1%** nad czystym 42 i **+9,6%** nad `TAIL_SKIP=0`. Wobec 0.1.41+tablica (ten sam cap 225 W,
ta sama matryca): **+5,9% @16k i +0,9% @32k** — czyli na 32k jesteśmy RÓWNO, a zysk siedzi w tablicy,
nie w samym 0.1.42. Czytnik wybrał **62 rozwiązania** — tyle samo co na 0.1.41, czyli podstawia kernele realnie.

**Profil TAIL_SKIP zależy od karty — zysk rośnie z odsetkiem chybień** (prefill ZAWSZE płaski, to
mechanizm dekodowania):

| układ | decode @32k `=7` vs `=0` | zysk |
|---|---|---|
| split [0,1] | 502,6 vs 500,2 (prefill) | ~0% — cache trzyma całą masę routingu |
| **IQ1_M, split [0,1], ctx 131072, hit 99,9-100%** | **48,6 vs 47,9-48,7** @32k; **51,0 vs 50,2-51,8** @4k | **~0%** — wszystkie 12 288 ekspertów w VRAM, nie ma czego pomijać |
| sama MI50 (cache 12874 slotów, hit 86,3%) | 36,4 vs 35,5 | ~+2,5% (granica szumu) |
| sam Radeon VII (16 GB) | 23,8 vs 20,6 | **+15,5%** (16k: 17,8 vs 15,5) |

**Nowe w 0.1.42 warte odnotowania:** sonda `PLE direct read probe: 72256 rows/s (fine)` — silnik sam
mierzy odczyt tablicy PLE na starcie i przechodzi na `mmap`, gdy `direct` wypada wolno (u nas zostaje na
`direct`, co potwierdza nasz wcześniejszy wynik direct ≈ mmap); memory guard w kontenerach (#1601) czyta
realny RAM (min z `MemAvailable` i limitu cgroup) — istotne, bo nasze ramię `--ple-io ram` zjadło pamięć;
`--aux-cpus` sadza wątki silnika na zapasowych CPU.

**Nasza praca nadal nie jest w upstreamie:** PR #981 (czytnik tablicy) jest `closed, merged: None`,
a w 0.1.42 bramka wygląda identycznie — `find_package(rocblas)` siedzi wyłącznie w
`cmake/hip_backend.cmake`, którego blok gfx906 nie włącza. Patch dla 0.1.42: `patches/0.1.42-roc981-full.diff`
(14 plików, 96 672 B — wcześniejszy pomijał `rocblas_tuning.hpp`, bo `git diff` nie łapie plików spoza indeksu).

---

## 10. Baseline JeanP00la — punkt odniesienia dla naszego IQ1

Źródło: repo Strata, `bench/results/2026-10-03-community-2x-mi50` (autor JeanP00l — ten sam, który zrobił
port gfx906, issue #641). Użył **tego samego `benchmark.py`, który my wozimy jako `strata-bench.py`**,
więc liczby są porównywalne bezpośrednio, bez przeliczania formuł.

**Sprzęt:** 2× MI50 **16 GB** gfx906, 85 W na kartę, PCIe 3.0 x16, peer przez root complex,
Xeon E5-2666 v3 (10c/20t, **bez AVX-512**), 32 GB DDR4, Ubuntu 24.04, HIP 7.14 z `mixa3607/rocm-gfx906`.
Silnik 0.1.38 + jego PR-y #637-#640.

**Model:** `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF`, **IQ1_M**:
```
shard 1  e11083ba855e7666b48ea3f2db6a9c3a20c18751a012cc24f948de91b7087fad
shard 2  316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113
```
pack `pack-coder`, profil `data/expert-profile-coder.bin`.

**Konfig:** `--max-context 131072 --kv int8 --kv-resident 32768 --prefill 4096 --spec 4 --spec-min-p 0.5
--vram-reserve-mib 600 --pcie-frac 0`, `layer_split 27`, `STRATA_ARENA_MMAP=1`; 6912 + 5376 =
**wszystkie 12 288 eksperty w VRAM, hit 100%**.

**Silnik zmierzony:** `strata 0.1.38` + PR-y #637-#640 (JeanP00l, 2x MI50 16 GB, 85 W/karta) —
**nie nasz obraz**; wstawiona tu jako punkt odniesienia, patrz sekcja 10.

| prompt tok | prefill tok/s | decode tok/s | TTFT |
|---|---|---|---|
| 4 096 | 320,9 [309,9-324,7] | 50,1 [49,3-54,0] | 12,81 s |
| 32 768 | 522,8 [522,6-523,4] | 47,8 [47,6-48,5] | 62,81 s |
| 128 000 | 516,8 [516,5-516,9] | 45,7 [44,8-51,5] | 248,09 s |

Mediana [min-max] z 3 przebiegów, 256 tokenów na żądanie, **0 reused** w każdym. VRAM peak
15,42 / 14,70 GiB; `MemAvailable` min 25,1 z 31,2 GiB. Needle bench 6/6.

**Jak to czytać (żeby nie wziąć tego za anomalię):** prefill 522,8 przy 32k i 170 W total wygląda szybko,
ale to reżim — **IQ1_M plus pełna rezydencja ekspertów**, czyli zero chybień w ścieżce prefillu.
Nasze 385 tok/s przy 80 W było na iq3 z częściowym cache'em. CPU różnicy nie tłumaczy — oba bez AVX-512.

---

## 11. Cap mocy to SUFIT, nie budżet — i przecieka. Pomiar na IQ1_M @ 85 W (2026-10-10)

Ustawione `rocm-smi -d 0/1 --setpoweroverdrive 85` na obu kartach, potwierdzone w hwmon
(`power1_cap` = 85 W na card1 i card2). Pobór mierzony co 2 s z `power1_input` (NIE `power1_average`
— to drugie na tych kartach nie istnieje i zwraca 0 W, co dało fałszywy odczyt „0 W przez cały bieg").

| karta | mediana | średnia | max | próbki NAD capem | szczyt |
|---|---|---|---|---|---|
| MI50 (cap 85 W) | **84,0 W** | 74,9 W | **127 W** | 27/70 = **39%** | 1,49× cap |
| Radeon VII (cap 85 W) | 56,0 W | 57,6 W | **132 W** | 18/70 = **26%** | 1,55× cap |
| spoczynek | 24 W | | | | |

Temperatury w obciążeniu: MI50 max 66 C, Radeon max 47 C — **nie termika**, to firmware.
44 z 70 próbek mają jedną kartę < 30 W → karty pracują **na przemian** (przelot pipeline'u między
stopniami splitu); Radeon jest niedociśnięty (mediana 56 W przy MI50 84 W).

**Wniosek:** `--setpoweroverdrive` ustawia wartość, która obowiązuje jako mediana, ale karty
przeskakują ją w szczytach do ~1,5×. Dlatego porównywanie „my mieliśmy 225/250 W, on 85/85" jak
budżetów jest BŁĘDNE — po obu stronach to nominal, nie realny pobór. Porównuj mocy tylko wtedy, gdy
obie strony ZMIERZYŁY pobór; sam cap tego nie zastępuje.

Efekt na wydajności (IQ1_M, split [0,1], spec 4, min-p 0,9): przy 85 W wobec 225/250 W
prefill **-31% @4k / -33% @32k**, decode **-14% @4k / -10% @32k** — czyli moc rusza OBA pola,
decode też (wcześniej błędnie twierdziłem, że decode jest odporny na waty).

---

## Gdzie są surowe dane (trzymać!)

```
strata-docker/                          obrazy, Dockerfile.*, STAN-*, RAPORT-*
strata-docker/bench-141/               wyniki-*.csv, run_*.sh, measure*.py, results/*.log, run_*.log
strata-docker/bench-141/results/       surowe logi silnika per ramię
strata-docker/rocm-tune/               tabela rocBLAS + tuner + logi
strata-docker/patches/                 diff 0.1.41+#981+bramka, opis wkladu
strata-docker/patches-upstream/        PR-y upstream jako diffy (783/907/934/981/1535/1661/1718/1732/1743)
strata-docker/bin/                     wszystkie binarki silnika (per wersja)
strata-mi50/                           WYNIKI-02-10, krzywa-cache.txt, logi, manifest.json
flash-lab/ · IQ*-cache-MI50-WYNIKI.md   rodzina llama.cpp (baseline 18,99)
dockerhub-strata-mi50-description.md   AKTUALNY opis na Hubie — tu trafi opis silnika
```

**Uwaga:** część drzewa z patchem siedzi tylko w `~/.hermes/cache/scratch/strata-981` (scratch czyści się
po 24 h) — zabezpieczone w `patches/0.1.41-roc981-full.diff` + `patches/0.1.41-roc981-README.md`.


---

## 2026-10-10 — Radeon jako HELPER vs SPLIT na 0.1.42 (IQ3_XXS Uncensored, ctx 131072)

Test uzytkownika z konfiguratora, ten sam obraz 0.1.42 (oba przelaczniki ON: tablica + TAIL_SKIP=7,
`STRATA_HIP_PROMPT_F16=1`, `STRATA_ROCBLAS_TUNING=/opt/strata/tools/hip`, `ROCR_VISIBLE_DEVICES=0,1`).
Model: `orca-iq3_xxs` (Qwen3.8-Flash-Next-Uncensored-IQ3_XXS), profil `expert-profile.bin`.

**UWAGA METODOLOGICZNA: to NIE jest czysty A/B.** Ramiona roznia sie nie tylko helperem.
To para z 20:00-20:10 na **IQ3_XXS**. Para z 20:25/20:28 jest na **IQ2_XS** i to ona jest czysta —
patrz sekcja nizej.

| | helper (20:00:21) | split (20:06:22) |
|---|---|---|
| uklad | `--expert-cache-device1 6077 --remote-expert-opt` | `--layer-split auto` |
| kv | **int8** | **q4_0** |
| eksperci | **`--mmap-experts`** | nie |

Wyniki (mediana z przebiegow, `benchmark.log` kontenera; n=3 @4k, n=2 @16k dla helpera, n=1 dla splitu):

**Silnik zmierzony:** `strata 0.1.42` (+ tablica rocBLAS ON + `TAIL_SKIP=7`), IQ3_XXS Uncensored,
ctx 131072 — mediana z przebiegow z `benchmark.log` kontenera.

| prompt | ramie | prefill tok/s | decode tok/s | TTFT s | hit | pcie_share | file_mb |
|---|---|---|---|---|---|---|---|
| 4096 | helper | 267,5 / 297,2 / 362,1 / 335,0 | 32,5 / 44,9 / 44,7 / 35,8 | 15,31 / 13,78 / 11,31 / 12,23 | 97,7-99,0% | **12,6-21,2%** | **1349-3155** |
| 4096 | split | 333,4 | 39,5 | 12,29 | 98,1% | 0,20% | 0 |
| 16384 | helper | 372,0 / 335,1 | 49,6 / 34,6 | 44,05 / 48,89 | 99,1-99,6% | 18,3-19,4% | 705-1306 |
| 16384 | split | 307,0 | 45,1 | 53,36 | 99,2% | 0,10% | 0 |

**Odczyt:** prefill i decode mieszcza sie w szumie — rozrzut WEWNATRZ ramienia helper (decode 32,5 -> 49,6
na 4k) jest wiekszy niz roznica miedzy ramionami. Split jest stabilny (decode 43-45 @16k), helper skacze.
Rozstrzygajaca roznica jest fizyczna, nie w tok/s: helper prowadzi per-ekspert ruch przez PCIe i zrzuca
chibienia na dysk.

**Mechanizm z logu silnika ramienia helper:**
```
PCIe probe: 13.6 GB/s host->device -> pcie_frac 0.37 (default 0.55)
expert cache auto: 25.82 GiB free -> 12213 slots        (MI50, 24.75 GiB VRAM)
pre-filled 12213 of 12213 slots from the profile in 9.1 s
CUDA1: 6077 additional experts, 12.32 GiB; results return through pinned host rows
mapping the experts from the model files (about 45 GB, --mmap-experts) - not loaded into RAM
routing-aware prefetch on (the next layer's router, file tier)
```
Czyli Radeon NIE jest martwym balastem: trzyma 6077 ekspertow (12,32 GiB) i realnie liczy — ale kazdy
token idzie do niego przez PCIe (13,6 GB/s) i wraca **pinned host rows**, a chibienia ponad oba cache
lecą z dysku (`file_mb` do 3155 MB na zimnym przebiegu; 3155 -> 1924 -> 1349 w trzech przebiegach, czyli
page cache sie rozgrzewa). W splicie PCIe stoi na 0,1-0,2% i dysk nie jest czytany w ogole.

**WNIOSEK:** helper nie daje zysku nad splitem — daje ten sam albo gorszy wynik przy 20x wiekszym ruchu
PCIe i czytaniu z dysku. Zbieznosc KIERUNKU z wczesniejszym pomiarem, ale na INNYM kwancie — IQ2_XS,
ctx 32000, spec 2 (helper 358/39,3 vs split 498/40,1). **To nie jest punkt odniesienia dla IQ3_XXS**:
inny kwant, inne ctx, inny spec. Liczby z tamtego biegu wolno cytowac tylko jako „helper nie pomaga
takze tam", nigdy jako porownanie wielkosci z tym biegiem.
**Do rozstrzygniecia:** czy to koszt helpera, czy koszt `--mmap-experts` + int8 — potrzebny czysty A/B,
w ktorym zmienia sie WYLACZNIE flaga helpera (ten sam kv, ten sam mmap).


---

## 2026-10-10 (pozniej) — CZYSTY A/B: Radeon helper vs SPLIT na IQ2_XS

Para z 20:25 (split) i 20:28 (helper). **Ta jest czysta**: identyczny model, kv, ctx i spec — rozni je
wylacznie uklad. IQ2_XS GSQ-RCO, ctx 131072, kv q4_0, spec 4, obraz 0.1.42, oba przelaczniki ON.

**Silnik zmierzony:** `strata 0.1.42` (+ tablica rocBLAS ON), IQ2_XS GSQ-RCO, ctx 131072,
kv q4_0, spec 4, oba przelaczniki ON — ta sama wersja w obu ramionach.

| prompt | split (`--layer-split auto`) | helper (`--expert-cache-device1 10158 --remote-expert-opt`) | roznica helpera |
|---|---|---|---|
| 4096 | 479,2 prefill / 49,0 decode / TTFT 8,55 s | 422,0 / 48,4 / 9,74 s | **prefill -11,9%**, TTFT +13,9%, decode -1,2% |
| 16384 | 568,7 / 50,3 / 28,81 s | 416,2 / 48,4 / 39,41 s | **prefill -26,8%**, TTFT +36,8%, decode -3,8% |

**Mechanizm (helper):** MI50 cache 18 074 slotow (26,48 GiB), Radeon **5 651 dodatkowych ekspertow
(7,60 GiB)**, `PCIe probe: 13.6 GB/s -> pcie_frac 0.37`. W biegu: hit 100%, `pcie_share` 4,7-5,2% (wiec
Radeon realnie liczy, ale tylko ~5% ruchu ekspertow). Koszt per-request z logu silnika:

```
4096:   659 wpisow / 179 startow warstw / 8,7 MiB zwrocone (87,2 MiB z pelnymi wierszami); host 14 ms staging + 35 ms czekania
16384: 6682 wpisow / 2547 startow warstw / 63,9 MiB zwrocone (639,1 MiB z pelnymi wierszami); host 44 ms staging + 449 ms czekania
```

**WNIOSEK (to jest odpowiedz na pytanie o helpera):** w splicie **obie karty licza**. W helperze Radeon
tylko trzyma te ~5% ruchu ekspertow, ktory musi przejsc przez PCIe i wrocic pinned host rows — a jego
rdzenie stoja. Dlatego helper przegrywa prefill o 12-27% i TTFT o 14-37%, przy decode rownym w szumie.
Im wiekszy model, tym wiecej Radeon musi wysylac i tym gorzej (IQ3_XXS: pcie_share 18-21%).

**Zasada:** zysk z drugiej karty bierze sie z jej LICZENIA (split), nie z jej pamieci (helper).
Pamiec przez PCIe to koszt, nie zysk.

### PUŁAPKA: helper ZABIJA start, gdy wszystkie eksperty są rezydentne (IQ1_M coder, 2026-10-11)

Silnik kończy się wtedy **bez śladu w kernelu** — bez coredumpu, bez błędu amdgpu — a ostatnia
linia logu silnika to `CUDA1 experts: no unclaimed experts remain`. To nie ostrzeżenie, a wyrok:
`src/core/remote_experts.cpp` przy pustej selekcji robi `close(); return false`, a launcher
raportuje `EngineDied: the engine exited before it was ready` i powtarza próbę kilka razy.

Powód: karta 0 zajmuje **wszystkie** pozycje profilu (`pre-filled 12288 of 12288 slots`), bo cały
zbiór ekspertów modelu (IQ1_M coder: 12 288 ekspertów = 23,42 GiB) mieści się w jej cache
(MI50 32 GB ma 25,71 GiB wolne). Dla karty 1 nie zostaje nic do wzięcia.

Sprawdź to JEDNYM porównaniem dwóch linii logu, zanim włączysz helper:

```
strata generate: loaded <X> GiB at ... GiB/s       <- arena = CAŁY zbiór ekspertów modelu
strata generate: expert cache <N> slots, <X> GiB   <- X równe powyższemu: karta 0 wzięła wszystko
```

Równe = ta konfiguracja nie ma prawa wstać. **Dla IQ1_M ustaw rolę karty 1 na `skip (don't use)`
albo tryb `Single card`** — helper ma sens tylko dla modeli większych niż cache karty głównej
(IQ2_XS/IQ3_XXS: tak, tam zostawało dla Radeona 5 651 ekspertów). Nasze wcześniejsze biegi na
IQ1_M szły **splitem [0,1]**, nie helperem — dlatego wyglądało, że „wcześniej działało".
