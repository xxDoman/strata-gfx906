# Strata 0.1.39 dla MI50 / gfx906 — obraz "odpal i dziala"
#
# Baza: rocm/dev-ubuntu-24.04:7.2.1 — DOKLADNIE ta sama wersja ROCm, na ktorej zbudowano
# binarke gfx906. Nowe ROCm (10.x) NIE MA kerneli gfx906 (rocBLAS startuje od gfx1010).
# Nawet 7.2.1 z officiala ich nie ma — pakujemy sprawdzone biblioteki z HOSTA (ten sam
# wzorzec co ollama-mi50: obraz = binarka + biblioteki, ktore znaja karte).
#
# Rozmiar: ~6 GB (baza 3,9 + libki 1,2 + kernele rocBLAS 0,68).
#
# Build (z katalogu strata-docker/):
#   ./prepare-rocm.sh          # kopiuje libki + kernele gfx906 z /opt/rocm-7.2.1
#   docker build -f Dockerfile.mi50 -t strata-mi50:0.1.35 .

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

# Zaleznosci runtime serwera (z requirements.txt) — bez tego serve/ sie nie laduje.
RUN pip3 install --no-cache-dir --break-system-packages \
        jinja2==3.1.6 pillow==12.3.0 psutil==7.2.2 pyyaml==6.0.3 regex==2026.9.10 numpy \
        requests tqdm

# Biblioteki gfx906 z hosta (7.2.1) — nadpisuja obrazowe, ktore nie maja gfx906.
COPY rocm-libs/*.so* /opt/rocm/lib/
# Kernele rocBLAS dla gfx906 (bez nich prefill/GEMM nie ma kodu dla karty).
COPY rocm-libs/rocblas-library/ /opt/rocm/lib/rocblas/library/
# Odswiez soname (podmienione pliki maja te same nazwy wersji co baza 7.2.1).
RUN ldconfig && ls /opt/rocm/lib/librocblas.so.5 >/dev/null && \
    ls /opt/rocm/lib/rocblas/library/*gfx906* | wc -l | grep -q '^1*[0-9]'

WORKDIR /opt/strata
COPY src-serve-39/        /opt/strata/serve/
COPY src-tools/strata_tokenizer.py /opt/strata/strata_tokenizer.py
COPY bin/strata-gfx906-0.1.39 /opt/strata/engine/strata
COPY bin/strata-vision-0.1.39 /opt/strata/engine/strata-vision
# Konfigurator + launcher (web UI :8090); entrypoint startuje go jako PID 1.
COPY strata-launcher.py   /opt/strata/strata-launcher.py
COPY strata_setup.py      /opt/strata/strata_setup.py
# Bazowy config (standalone): launcher kopiuje go na /work, jesli tam nie ma.
COPY default-config.json  /opt/strata/default-config.json
COPY docker-entrypoint.sh /opt/strata/docker-entrypoint.sh

# --- Setup tools: download the GGUF from HuggingFace + build packs/tokenizer/MTP in-container ---
# The image ships ONLY the data tools (not setup.py: on Linux it would fetch its own CUDA engine
# and clash with the gfx906 one). These build the model data from a GGUF the wizard downloads.
COPY tools39/                 /opt/strata/tools/
COPY third_party-gguf-py/   /opt/strata/third_party/llama.cpp/gguf-py/
COPY data/                  /opt/strata/data/
RUN chmod +x /opt/strata/engine/strata /opt/strata/engine/strata-vision \
             /opt/strata/strata-launcher.py /opt/strata/docker-entrypoint.sh

VOLUME ["/models", "/data", "/work"]
EXPOSE 8084 8090
ENTRYPOINT ["/opt/strata/docker-entrypoint.sh"]
