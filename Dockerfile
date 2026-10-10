# Strata 0.1.42 + TABLICA rocBLAS gfx906 + przelaczniki w konfiguratorze — obraz PRODUKCYJNY.
# (AMD Instinct MI50 / MI60, Radeon VII — gfx906)
#
# Publikowany jako xxdoman/strata-mi50:0.1.42 i :latest.
#
# Co jest w srodku (i czym rozni sie od 0.1.41):
#   1. Silnik: bin/strata-gfx906-0.1.42-roc981 = tag v0.1.42 + CZYTNIK tablicy rocBLAS z PR #981
#      (autor Vop3p). Ten PR jest ZAMKNIETY i nie zostal zmergowany; czytnik jest w nim ogrodzony
#      STRATA_ENABLE_HIP, ktorego gfx906 nie uzywa — dlatego dolozylismy poprawe bramki dla gfx906.
#   2. Tablica: rocm-tune/gfx906-rocblas-5.2.0.dabb6df2b9.txt -> /opt/strata/tools/hip/
#      (narzedzie tools/hip/tune_rocblas z PR #981). W ENV NIE MA STRATA_ROCBLAS_TUNING ani
#      STRATA_HIP_PROMPT_F16 — o wlaczeniu decyduje PRZELACZNIK w konfiguratorze, a launcher pisze
#      OBA klucze JAWNIE w kazdym stanie ("1"/"0" i sciezka/""), wiec ptaszek wygrywa takze z ENV
#      wypalonym w obrazie. Obraz "as-shipped" = bez tabeli.
#   3. Info-tab podaje 0.1.42; launcher ma dwa przelaczniki: tablica rocBLAS i TAIL_SKIP.
#
# Zmierzone na tej maszynie (iq3, split [0,1], 225 W = SMI default, 16k/32k, ta sama binarka):
#   tablica   (0.1.42): prefill +9,1% @32k nad czystym 42 (+9,6% nad TAIL_SKIP=0)
#   TAIL_SKIP (0.1.42): split ~0% (cache trzyma cala mase routingu), sama MI50 ~+2% decode,
#                       sam Radeon VII ~+15% decode @32k; prefill zawsze plaski
#
# Ten plik to PRZEPIS. Katalogi zrodlowe (src-serve-142/, tools142/, data142/, rocm-libs/,
# rocm-tune/, bin/) zostaja lokalnie w strata-docker/ i nie sa czescia tego repo: binarke buduje
# sie ze zrodel Strata, a biblioteki i kernele gfx906 zbiera z hosta (patrz README).
#
# Build (z katalogu strata-docker/):
#   docker build -f Dockerfile -t xxdoman/strata-mi50:0.1.42 .
#
FROM rocm/dev-ubuntu-24.04:7.2.1

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    LANG=C.UTF-8 \
    HSA_OVERRIDE_GFX_VERSION=9.0.6 \
    ROCR_VISIBLE_DEVICES=0 \
    LD_LIBRARY_PATH=/opt/rocm/lib

LABEL org.opencontainers.image.title="xxdoman/strata-mi50" \
      org.opencontainers.image.description="Strata engine v0.1.42 for AMD gfx906 (MI50/MI60/Radeon VII): gfx906 rocBLAS solution table (PR #981 reader) and the expert-tail skip as configurator toggles, with a web configurator and the official benchmark" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.url="https://hub.docker.com/r/xxdoman/strata-mi50" \
      org.opencontainers.image.source="https://github.com/xxDoman/strata-gfx906" \
      org.opencontainers.image.vendor="xxDoman"

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
COPY src-serve-142/serve/  /opt/strata/serve/
COPY src-tools-142/strata_tokenizer.py /opt/strata/strata_tokenizer.py
# Silnik: 0.1.42 + czytnik tablicy rocBLAS z #981 (bramka poprawiona dla gfx906).
COPY bin/strata-gfx906-0.1.42-roc981 /opt/strata/engine/strata
COPY bin/strata-vision-0.1.39 /opt/strata/engine/strata-vision
COPY strata-launcher.py   /opt/strata/strata-launcher.py
COPY LICENSE              /opt/strata/LICENSE
COPY strata_setup.py      /opt/strata/strata_setup.py
COPY default-config.json  /opt/strata/default-config.json
COPY docker-entrypoint.sh /opt/strata/docker-entrypoint.sh

COPY tools142/                 /opt/strata/tools/
COPY tools142/strata-bench.py  /opt/strata/tools/strata-bench.py
COPY tools142/bench-auth-wrap.py /opt/strata/tools/bench-auth-wrap.py
# Tablica rocBLAS dla gfx906 — silnik szuka jej przez STRATA_ROCBLAS_TUNING (/opt/strata/tools/hip),
# plik <arch>-rocblas-<wersja>.txt musi pasowac nazwa do wersji rocBLAS w tym obrazie.
COPY rocm-tune/gfx906-rocblas-5.2.0.dabb6df2b9.txt /opt/strata/tools/hip/gfx906-rocblas-5.2.0.dabb6df2b9.txt
COPY third_party-gguf-py/   /opt/strata/third_party/llama.cpp/gguf-py/
COPY data142/                  /opt/strata/data/
RUN chmod +x /opt/strata/engine/strata /opt/strata/engine/strata-vision \
             /opt/strata/strata-launcher.py /opt/strata/docker-entrypoint.sh

# Twarda kontrola: wbita binarka to DOKLADNIE ta zbudowana z 0.1.42 + nasz patch.
# Bez tego .dockerignore moze ja po cichu wykluczyc i obraz dostanie stara/brakujaca binarke.
RUN test "$(sha256sum /opt/strata/engine/strata | cut -d' ' -f1)" = \
         "5f1592d48ab89e876aa87dd9d8d6a9533ef13760909d491cb25c73082cebc3b8" \
 && echo "engine sha256 OK (0.1.42 + tablica)"

# Kontrola: czytnik tablicy ORAZ przelacznik TAIL_SKIP sa w binarce, a tablica jest w obrazie.
RUN strings -n 8 /opt/strata/engine/strata | grep -q 'STRATA_ROCBLAS_TUNING_V1' \
 && strings -n 8 /opt/strata/engine/strata | grep -q 'STRATA_ROUTE_TAIL_SKIP' \
 && test -s /opt/strata/tools/hip/gfx906-rocblas-5.2.0.dabb6df2b9.txt \
 && echo "tablica rocBLAS: czytnik OK, TAIL_SKIP OK, tablica $(wc -l < /opt/strata/tools/hip/gfx906-rocblas-5.2.0.dabb6df2b9.txt) linii" \
 && head -3 /opt/strata/tools/hip/gfx906-rocblas-5.2.0.dabb6df2b9.txt

# Test importow serwera — lapie braki na etapie BUILDA, nie na produkcji.
RUN cd /opt/strata && python3 -c "\
import sys; sys.path.insert(0, '/opt/strata');\
import serve.server, serve.frontend;\
print('serve imports OK: server, frontend')"

RUN test "$(wc -c < /opt/strata/tools/strata-bench.py)" -gt 5000 \
 && python3 -m py_compile /opt/strata/tools/strata-bench.py \
 && cd /opt/strata && python3 -c "\
import sys; sys.path[:0] = ['/opt/strata', '/opt/strata/tools'];\
import regex; from strata_tokenizer import Tokenizer; from serve.frontend import ChatTemplate, openai_to_messages;\
print('benchmark imports OK: regex, Tokenizer, ChatTemplate')" \
 && python3 -m py_compile /opt/strata/tools/bench-auth-wrap.py \
 && echo "strata-bench.py: $(wc -lc < /opt/strata/tools/strata-bench.py) (linie slowa)"

# Launcher (konfigurator) tez musi sie kompilowac — ma przelaczniki tablicy i TAIL_SKIP.
RUN python3 -m py_compile /opt/strata/strata-launcher.py \
 && grep -q 'l_tailskip' /opt/strata/strata-launcher.py \
 && grep -q 'STRATA_ROUTE_TAIL_SKIP' /opt/strata/strata-launcher.py \
 && echo "launcher py_compile OK + przelaczniki obecne"

# Help silnika dla zakladki Help — generowany PRZY BUDOWIE z wbita binarka (STDERR -> 2>&1).
RUN /opt/strata/engine/strata --help > /opt/strata/data/engine-help.txt 2>&1 \
 && test "$(wc -c < /opt/strata/data/engine-help.txt)" -gt 5000 \
 && echo "engine-help.txt: $(wc -lc < /opt/strata/data/engine-help.txt) (linie slowa)"

# Wersja silnika. UWAGA: silnik NIE MA --version (drukuje "unknown argument"), a `strings | sort -uV`
# wygrywa ggml (0.24.0). Bierzemy pole z logu, ktore jest dokladnie nasza wersja.
RUN strings -n 4 /opt/strata/engine/strata | grep -oE 'engine=0[.][0-9]+[.][0-9]+' | head -1 | tee /opt/strata/data/engine-version.txt \
 && grep -q 'engine=0.1.42' /opt/strata/data/engine-version.txt

VOLUME ["/models", "/data", "/work"]
EXPOSE 8084 8090
ENTRYPOINT ["/opt/strata/docker-entrypoint.sh"]
