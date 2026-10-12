# Strata 0.1.43.1 + TABLICA rocBLAS gfx906 + floor rezerwy VRAM w launcherze — obraz PRODUKCYJNY.
# (AMD Instinct MI50 / MI60, Radeon VII — gfx906)
#
# Co innego niz xxdoman/strata-mi50:0.1.43-test:
#   1. Silnik: bin/strata-gfx906-0.1.43.1-roc981 = tag v0.1.43.1 + CZYTNIK tablicy rocBLAS z PR #981.
#      Patch = patches-upstream/pr981-1431.diff (przeniesiony na 0.1.43.1, git apply --check czysto).
#      Poprzedni plik pr981-clean.diff NIE byl tym, czym zbudowano 0.1.43 (hunk Gemm::f16_inplace i dwa
#      w setup.py nie wchodzily takze na 0.1.43), a drzewo z tamtego builda zniknelo - dlatego ten
#      obraz ma wlasny, weryfikowalny patch z bramka gfx906 w srodku.
#   2. Bramka gfx906 (bez tego czytnik jest kompilowany out, co juz raz nas ugryzlo): w bloku
#      if(STRATA_HIP_GFX906) jest find_package(rocblas CONFIG QUIET) + set(STRATA_ROCBLAS_AVAILABLE ...),
#      a if() wokol targetu rozszerzony na (STRATA_ENABLE_HIP OR STRATA_HIP_GFX906).
#   3. serve/, tools/, data/ odswiezone z drzewa 0.1.43.1 (serve/server.py +214/-46, frontend.py +28,
#      tools/strata_bench.py +86/-10, nowe tabelki hipblaslt gfx11xx/gfx12xx). Bez nowych importow
#      w serve/ (sprawdzone), wiec pip bez zmian.
#   4. Poprawka naglowka raportu community na AMD przeniesiona na nowy skrypt:
#      bench-patches/0001-gfx906-gpu-metadata-1431.patch. Dwa hunki: hunk 3 zalezal od przepisanego
#      collect_machine (teraz gpu_driver bierze used[0]["driver"] albo rocm_driver), a nazwy kart
#      wymagaly czwartej zmiany: upstream 0.1.43.1 (#1985/#2001) bierze nazwy Z SERWERA, gdy roznia sie
#      od lokalnych - a serwer raportuje "Radeon Instinct MI50 32GB + AMD Radeon" (sterownik nie zna
#      marketingowej nazwy 0x66a1). Teraz, gdy lista serwera zgadza sie 1:1 z wykrytymi kartami, zostaja
#      NASZE nazwy z PCI id. Sprawdzone na zywym silniku 0.1.43.1 (ten sam config):
#      przed: ['Radeon Instinct MI50 32GB', 'AMD Radeon'] -> po: ['AMD Instinct MI50 32GB', 'AMD Radeon VII 16GB'].
#   5. Launcher: LATER_FLOOR_MIB = 512 zamiast --vram-reserve-later-mib 0 na kartach splitu bez monitora
#      + tekst pomocy. To jest naprawa issue #1 (4x MI50 16GB: z 0 kazda pozniejsza karta byla
#      wypelniona do ~90 MiB i stage 2 padal na "the device arena (69 MiB) does not fit").
#   6. Info-tab podaje 0.1.43.1 + wiersz o zmianach hotfixu; decode na gfx906 dalej bez zmian.
#
# Zmierzone dla 0.1.42/0.1.43 (iq3, split [0,1], 225 W, 16k/32k, ta sama sciezka decode):
#   tablica   : prefill +9,1% @32k nad czystym 42 (+9,6% nad TAIL_SKIP=0)
#   TAIL_SKIP : split ~0%, sama MI50 ~+2% decode, sam Radeon VII ~+15% decode @32k
#
# Build (drzewo budujemy z tagu v0.1.43.1 + patches-upstream/pr981-1431.diff):
#   docker build -f Dockerfile -t xxdoman/strata-mi50:0.1.43.1 .
#   # kontrola sha jest wbudowana; nadpisanie, gdy binarke podmienimy swiadomie:
#   docker build -f Dockerfile --build-arg ENGINE_SHA=<sha256> -t ... .
#
# Publikowany jako xxdoman/strata-mi50:0.1.43.1 i :latest.

FROM rocm/dev-ubuntu-24.04:7.2.1

ARG ENGINE_SHA=c78456f3f9674174dd7411f76aef074390192bd21f13bdc283d2d70f6f1a3e41

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    LANG=C.UTF-8 \
    HSA_OVERRIDE_GFX_VERSION=9.0.6 \
    ROCR_VISIBLE_DEVICES=0 \
    LD_LIBRARY_PATH=/opt/rocm/lib

LABEL org.opencontainers.image.title="xxdoman/strata-mi50" \
      org.opencontainers.image.description="Strata engine v0.1.43.1 for AMD gfx906 (MI50/MI60/Radeon VII): gfx906 rocBLAS solution table (PR #981 reader), per-card VRAM reserve floor on a split, and the expert-tail skip as configurator toggles, with a web configurator and the official benchmark" \
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
COPY src-serve-1431/serve/  /opt/strata/serve/
COPY src-tools-1431/strata_tokenizer.py /opt/strata/strata_tokenizer.py
# Silnik: 0.1.43.1 + czytnik tablicy rocBLAS z #981.
COPY bin/strata-gfx906-0.1.43.1-roc981 /opt/strata/engine/strata
COPY bin/strata-vision-0.1.39 /opt/strata/engine/strata-vision
COPY strata-launcher.py   /opt/strata/strata-launcher.py
# CMakeLists.txt jest tu TYLKO dla naglowka raportu community: tools/strata_bench.py czyta
# ROOT/CMakeLists.txt po "project(strata VERSION x.y.z)" i bez niego publikuje "project ?".
# Wersja 0.1.43.1 jest prawdziwa. Wiersz "commit" zostanie "not a git checkout" — obraz nie jest
# checkoutem, wiec to prawda, a nie usterka; nie wozimy .git (20 MB), bo nasz silnik to tag + patch.
COPY cmake1431/CMakeLists.txt /opt/strata/CMakeLists.txt
COPY LICENSE              /opt/strata/LICENSE
COPY strata_setup.py      /opt/strata/strata_setup.py
COPY default-config.json  /opt/strata/default-config.json
COPY docker-entrypoint.sh /opt/strata/docker-entrypoint.sh

COPY tools1431/                 /opt/strata/tools/
COPY tools1431/strata-bench.py  /opt/strata/tools/strata-bench.py
COPY tools1431/bench-auth-wrap.py /opt/strata/tools/bench-auth-wrap.py
# POPRAWKA LOKALNA dla nowego skryptu community (nie upstream): na kartach AMD raport zawsze
# publikowal "GPU driver: not read" i generyczna nazwe "AMD Radeon Graphics" zamiast MI50.
# Przyczyna jest w samym skrypcie: (1) gpu_driver nie schodzil na odczytany rocm_driver, gdy
# sterownik per karta jest None; (2) nazwa karty szla wprost z rocm-smi, ktore nie zna marketingowej
# nazwy MI50 (0x66a1). Patch zmienia WYLACZNIE naglowek raportu (zero kodu pomiarowego). Plik w repo
# (tools1431/) zostaje 1:1 z upstreamem, wiec zdjecie poprawki = usuniecie tych dwoch linii.
# 0.1.43.1 przepisal collect_machine (#1985/#2001 - tylko karty uzywane przez silnik), dlatego hunk 3
# jest przeniesiony w 0001-gfx906-gpu-metadata-1431.patch.
COPY bench-patches/ /tmp/bench-patches/
RUN cd /opt/strata && patch -p1 --dry-run < /tmp/bench-patches/0001-gfx906-gpu-metadata-1431.patch \
 && patch -p1 < /tmp/bench-patches/0001-gfx906-gpu-metadata-1431.patch \
 && rm -rf /tmp/bench-patches
# UWAGA (0.1.43+): upstream PRZEPISAL benchmark na tools/strata_bench.py (inne CLI: --config/--url/
# --runs/--out/--compare) i USUNAL bench-auth-wrap.py. Nasza zakladka Benchmark w launcherze wola
# stare nazwy (tools/strata-bench.py + bench-auth-wrap.py) i bez wrappera odmawia startu, wiec
# obraz niesie OBA stare skrypty verbatim obok nowych (skopiowane z cyklu 0.1.42). Jesli kiedys
# przesiadziemy zakladke na nowy skrypt — te dwie linie i pliki z tools1431/ do usuniecia.
# Tablica rocBLAS dla gfx906 — silnik szuka jej przez STRATA_ROCBLAS_TUNING (/opt/strata/tools/hip),
# plik <arch>-rocblas-<wersja>.txt musi pasowac nazwa do wersji rocBLAS w tym obrazie.
COPY rocm-tune/gfx906-rocblas-5.2.0.dabb6df2b9.txt /opt/strata/tools/hip/gfx906-rocblas-5.2.0.dabb6df2b9.txt
COPY third_party-gguf-py/   /opt/strata/third_party/llama.cpp/gguf-py/
COPY data1431/                  /opt/strata/data/
RUN chmod +x /opt/strata/engine/strata /opt/strata/engine/strata-vision \
             /opt/strata/strata-launcher.py /opt/strata/docker-entrypoint.sh

# Twarda kontrola: wbita binarka to DOKLADNIE ta zbudowana z 0.1.43.1 + nasz patch.
# Bez tego .dockerignore moze ja po cichu wykluczyc i obraz dostanie stara/brakujaca binarke.
RUN test "$(sha256sum /opt/strata/engine/strata | cut -d' ' -f1)" = "$ENGINE_SHA" \
 && echo "engine sha256 OK (0.1.43.1 + tablica)"

# Kontrola: czytnik tablicy ORAZ przelacznik TAIL_SKIP sa w binarce, a tablica jest w obrazie.
RUN strings -n 8 /opt/strata/engine/strata | grep -q 'STRATA_ROCBLAS_TUNING_V1' \
 && strings -n 8 /opt/strata/engine/strata | grep -q 'STRATA_ROUTE_TAIL_SKIP' \
 && test -s /opt/strata/tools/hip/gfx906-rocblas-5.2.0.dabb6df2b9.txt \
 && echo "tablica rocBLAS: czytnik OK, TAIL_SKIP OK, tablica $(wc -l < /opt/strata/tools/hip/gfx906-rocblas-5.2.0.dabb6df2b9.txt) linii" \
 && head -3 /opt/strata/tools/hip/gfx906-rocblas-5.2.0.dabb6df2b9.txt

# MMQ musi byc prawdziwym kodem, nie stubem (5 B = pusty; ~0x238 = realny).
RUN test "$(nm -S --size-sort -C /opt/strata/engine/strata | grep 'mmq::Context::run' | awk '{print $2}' | head -1)" = "0000000000000238" \
 && echo "MMQ: realny kod (0x238), nie stub"

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
 && python3 -m py_compile /opt/strata/tools/strata_bench.py \
 && echo "strata-bench.py: $(wc -lc < /opt/strata/tools/strata-bench.py) (linie slowa)"

# Launcher (konfigurator) tez musi sie kompilowac — ma przelaczniki tablicy, TAIL_SKIP i floor rezerwy.
RUN python3 -m py_compile /opt/strata/strata-launcher.py \
 && grep -q 'l_tailskip' /opt/strata/strata-launcher.py \
 && grep -q 'STRATA_ROUTE_TAIL_SKIP' /opt/strata/strata-launcher.py \
 && grep -q 'LATER_FLOOR_MIB = 512' /opt/strata/strata-launcher.py \
 && grep -q 'engine build.*0.1.43.1' /opt/strata/strata-launcher.py \
 && echo "launcher py_compile OK + przelaczniki + floor rezerwy + wersja 0.1.43.1"

# Help silnika dla zakladki Help — generowany PRZY BUDOWIE z wbita binarka (STDERR -> 2>&1).
RUN /opt/strata/engine/strata --help > /opt/strata/data/engine-help.txt 2>&1 \
 && test "$(wc -c < /opt/strata/data/engine-help.txt)" -gt 5000 \
 && echo "engine-help.txt: $(wc -lc < /opt/strata/data/engine-help.txt) (linie slowa)"

# Wersja silnika. UWAGA: silnik NIE MA --version (drukuje "unknown argument"), a `strings | sort -uV`
# wygrywa ggml (0.24.0). Bierzemy pole z logu, ktore jest dokladnie nasza wersja.
RUN strings -n 4 /opt/strata/engine/strata | grep -oE 'engine=0[.][0-9]+[.][0-9]+[.][0-9]*' | head -1 | tee /opt/strata/data/engine-version.txt \
 && grep -q 'engine=0.1.43.1' /opt/strata/data/engine-version.txt

VOLUME ["/models", "/data", "/work"]
EXPOSE 8084 8090
ENTRYPOINT ["/opt/strata/docker-entrypoint.sh"]
