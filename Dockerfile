# Strata 0.1.40 dla MI50 / gfx906 — obraz v4 (0.1.40.v2)
#
# Bazuje na obrazie 0.1.39.v3 (konfigurator + rezerwa VRAM per karta), ale z silnikiem 0.1.40.
# 0.1.40 zawiera juz upstreamem to, co w 0.1.39 patchowalismy osobno:
#   #808 (cudaFuncSetAttribute jako funkcja) i #854 (helper GPU nie w udziale PCIe).
# NIE kompiluje sie jednak na gfx906 wprost — sa 3 bledy (bramki STRATA_USE_HIP nie lapia
# STRATA_HIP_GFX906). Naprawione w zrodle (patch patches/0.1.40-gfx906-fixes.diff):
#   src/kernels/cuda/fused_gr.cu  return; -> return false;
#   src/core/mtp.cpp              + && !defined(STRATA_HIP_GFX906)
#   src/core/vmm.cpp              + && !defined(STRATA_HIP_GFX906)
# Dodatkowo dp4a dla gfx906 (intrinsics.hpp): v_dot4_i32_i8 zamiast petli 4 iteracji (+2-4% decode).
# Zgloszone upstream jako PR #1066 (build fix) i #1067 (dp4a).
#
# Baza: rocm/dev-ubuntu-24.04:7.2.1. Biblioteki + kernele gfx906 (golden, 156 gfx906 + 54 fallback)
# kopiowane z HOSTA — oficjalny obraz nie ma kerneli gfx906.
#
# Build (z katalogu strata-docker/):
#   ./prepare-rocm.sh
#   docker build -f Dockerfile.v40 -t xxdoman/strata-mi50:0.1.40.v2 .

FROM rocm/dev-ubuntu-24.04:7.2.1

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    LANG=C.UTF-8 \
    HSA_OVERRIDE_GFX_VERSION=9.0.6 \
    ROCR_VISIBLE_DEVICES=0 \
    LD_LIBRARY_PATH=/opt/rocm/lib

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip ca-certificates curl libatomic1 libgomp1 libnuma1 \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages \
        jinja2==3.1.6 pillow==12.3.0 psutil==7.2.2 pyyaml==6.0.3 regex==2026.9.10 numpy \
        requests tqdm

COPY rocm-libs/*.so* /opt/rocm/lib/
COPY rocm-libs/rocblas-library/ /opt/rocm/lib/rocblas/library/
RUN ldconfig && ls /opt/rocm/lib/librocblas.so.5 >/dev/null && \
    ls /opt/rocm/lib/rocblas/library/*gfx906* | wc -l | grep -q '^1*[0-9]'

WORKDIR /opt/strata
COPY src-serve-40/        /opt/strata/serve/
COPY src-tools/strata_tokenizer.py /opt/strata/strata_tokenizer.py
# 0.1.40 + 3 build fixy (gfx906) + dp4a gfx906
COPY bin/strata-gfx906-0.1.40 /opt/strata/engine/strata
COPY bin/strata-vision-0.1.39 /opt/strata/engine/strata-vision
COPY strata-launcher.py   /opt/strata/strata-launcher.py
COPY strata_setup.py      /opt/strata/strata_setup.py
COPY default-config.json  /opt/strata/default-config.json
COPY docker-entrypoint.sh /opt/strata/docker-entrypoint.sh

COPY tools40/                 /opt/strata/tools/
COPY third_party-gguf-py/   /opt/strata/third_party/llama.cpp/gguf-py/
COPY data40/                  /opt/strata/data/
RUN chmod +x /opt/strata/engine/strata /opt/strata/engine/strata-vision \
             /opt/strata/strata-launcher.py /opt/strata/docker-entrypoint.sh

VOLUME ["/models", "/data", "/work"]
EXPOSE 8084 8090
ENTRYPOINT ["/opt/strata/docker-entrypoint.sh"]
