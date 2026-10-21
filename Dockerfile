# Strata 0.2.1 (engine 0.1.46) for AMD gfx906 — the image published as
# `xxdoman/strata-mi50:0.2.1` and `:latest` (digest sha256:23ed0e3586c6…). PRODUCTION.
#
# This Dockerfile layers on the PREVIOUS published image (`xxdoman/strata-mi50:0.1.45`), which carries
# ROCm 7.2.1 with the host's gfx906 libraries and rocBLAS kernels packed in: it replaces the engine
# binary, the release's serve/tools/data/strata_control, our launcher and the rocBLAS table.
# Build (from the repository root, with the binary in bin/ and the 0.2.1 sources in src-serve-021/,
# strata_control021/, tools021/, data021/ and CMakeLists-021.txt — see docs/engines/0.2.1.md):
#   docker build -f Dockerfile -t xxdoman/strata-mi50:0.2.1 .
# Release gate before pushing: ./bramka-wydania.sh --tag xxdoman/strata-mi50:0.2.1
#
# Strata 0.2.1 — WYDANIE (engine 0.1.46) na gfx906. NASZA wersja: silnik + tablica rocBLAS + serwer/konfigurator z wydania.
#
# Nazewnictwo (zasada Dominika): tag = wersja wydania ze strony, nie wersja silnika w środku.
#   0.2.1 (wydanie) = engine 0.1.46 (upstream nazywa assety strata-engine-0.1.46-*, w tagu v0.2.1 stoi
#   project(strata VERSION 0.1.46)). Stąd tag obrazu 0.2.1, mimo że w środku silnik melduje 0.1.46.
#
# CO JEST NASZE:
#   * silnik 0.1.46 z v0.2.1 zbudowany czysto dla gfx906 (bin/strata-gfx906-0.1.46-tab, sha256 7b2fa372...)
#     + wpięty czytnik tablicy rocBLAS (patches/0.1.46-gfx906-rocblas-table.diff, dwa hunki CMake;
#       reader STRATA_ROCBLAS_TUNING jest w upstreamie, brakowało tylko wpięcia — bez tego kompiluje się do zera)
#   * tabela rocBLAS gfx906 z 10.10 (5.2.0.dabb6df2b9, zgodna z libką ROCm 7.2.1) pod /opt/strata/rocblas-tuning.txt
#   * STRATA_HIP_PROMPT_F16=1 — ścieżka FP16-in/out promptu, na której tablica jest mierzona
#     (pomiar @80 W, Qwen3.8-Flash-Next IQ2_XXS: czysty 246-253 PP -> F16 275-276 -> F16+tablica 308-310; TG bez zmian)
#   * konfigurator: NASZ strata-launcher.py z bazy (zakładki, Pool, Bench, rejestr błędów) — bez zmian
#
# CO JEST Z WYDANIA 0.2.1 (świeże, nie z 0.1.45): serve/ (nowe moduły launch_identity, lifeline, loader_diag,
# owner_guard, ready), tools/, data/ — skopiowane z drzewa tagu v0.2.1. Nasze dodatki w tools
# (embd_sidecar.py) zostają z bazy, bo COPY nakłada katalog na istniejący.
#
# QWEN3.6 (qwen35moe) JEST W TYM OBRAZIE: binarka ma przywrocony silnik q36 na gfx906
# (families: qwen4exp qwen35moe). Upstream 0.2.1 wycial go z builda gfx906 (issue #3172), wiec
# wzgledem czystego upstreamu dochodza: q36_engine.cu z linii 0.1.45 z E1-E3 (bufory atencji
# z geometrii, zapas 128 int dla ident/rinv, upload_f32 przyjmuje Q4_K/Q6_K), X(12)=Q4_K
# w STRATA_D_FMTS (E4) i shimy cublasSgemm/GemmStridedBatchedEx w platform/hip_compat (E5c).
# Szczegoly i pomiary: PROJEKT/PORT-0.2.1.md.
#
# Build (z katalogu strata-docker/):  docker build -f Dockerfile.021 -t xxdoman/strata-mi50:0.2.1 .
FROM xxdoman/strata-mi50:0.1.45

ENV STRATA_HIP_PROMPT_F16=1 \
    STRATA_ROCBLAS_TUNING=/opt/strata/rocblas-tuning.txt

LABEL org.opencontainers.image.title="xxdoman/strata-mi50 0.2.1 (engine 0.1.46 + rocBLAS table, gfx906)" \
      org.opencontainers.image.version="0.2.1" \
      org.opencontainers.image.description="Strata 0.2.1 for AMD gfx906: engine 0.1.46 built clean from tag v0.2.1 (90767252) with the rocBLAS solution-table reader wired for gfx906, the gfx906 table tuned on MI50, and STRATA_HIP_PROMPT_F16=1, the path the table is measured on. Prompt speed on Qwen3.8-Flash-Next IQ2_XXS at 80 W: 246-253 tok/s clean, 275-276 with the FP16 prompt path, 308-310 with the table on top; decode unchanged. Carries the serve/, tools/ and data/ of the 0.2.1 release together with our launcher/configurator. qwen35/36 is not in this build, as in the upstream gfx906 build." \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.url="https://hub.docker.com/r/xxdoman/strata-mi50" \
      org.opencontainers.image.source="https://github.com/xxDoman/strata-gfx906" \
      org.opencontainers.image.vendor="xxDoman"

COPY bin/strata-gfx906-0.1.46-q35 /opt/strata/engine/strata
COPY rocm-tune/gfx906-rocblas-5.2.0.dabb6df2b9.txt /opt/strata/rocblas-tuning.txt
COPY OPIS-WYDANIA.md /opt/strata/OPIS-WYDANIA.md
COPY CMakeLists-021.txt /opt/strata/CMakeLists.txt
COPY strata-launcher.py /opt/strata/strata-launcher.py
COPY src-serve-021/ /opt/strata/serve/
COPY strata_control021/ /opt/strata/strata_control/
COPY tools021/     /opt/strata/tools/
COPY data021/      /opt/strata/data/

RUN chmod 755 /opt/strata/engine/strata /opt/strata/rocblas-tuning.txt \
 && /opt/strata/engine/strata --version \
 && /opt/strata/engine/strata --families \
 && printf 'engine=0.1.46\n' > /opt/strata/data/engine-version.txt \
 && printf 'release=0.2.1\nengine=0.1.46\n' > /opt/strata/RELEASE \
 && cd /opt/strata && python3 -c "import serve.server; print('serve/ z 0.2.1: import OK')"
