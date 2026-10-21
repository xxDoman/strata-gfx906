# Engines — every image of `xxdoman/strata-mi50`, with sums, what it fixes and what is not proven

One line of images, one page per engine. Each engine page carries the **same fixed header** — image tag,
image sum, engine binary sum, what it fixes, how that was proven, what is not proven — so two engines can
be compared without reading prose. This page is the index: it is what the front page of the repository
links to.

Two things to keep separate before you quote any tag:

- **`0.2.1` / `latest`** is the **published** image. It is what `docker pull` gives you, and it is the
  only engine here that a reader can reproduce.
- The **`0.1.44.1.b` … `.1.g`** line is built and smoke-tested **locally** (same engine binary, different
  configurator). None of those tags was pushed, so no registry digest exists for them and nobody outside
  this machine can pull them. They are documented here because they are real measurements and real
  fixes, not because they are downloadable.

| Image tag | Image sum (short) | Engine binary | What it fixes | On Docker Hub |
| --- | --- | --- | --- | --- |
| [`0.2.1`](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.2.1.md) · `latest` | `23ed0e3586c6` (`sha256:23ed0e3586c6ebb727fda…`) | `7a8e2beb…` (38 443 528 B) | clean v0.2.1 for gfx906; rocBLAS table wired + gfx906 table + FP16 prompt path; qwen35/36 restored | **yes** (2026-10-21) |
| [`0.1.43.1`](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.43.1.md) · `latest` | `6e9002179e55` (`sha256:6e9002179e55…`) | `c78456f3…` | upstream 0.1.43.1 hotfix + our rocBLAS table reader, AMD report header, per-card VRAM reserve floor | **yes** |
| [`0.1.44.1.b`](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.44.1.b.md) | `323ae9493819` | `9859791a…` | `Models Infos` panel, metadata repair on header copies, Start blocked for models that cannot load | no — local |
| [`0.1.44.1.c`](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.44.1.c.md) | `d16941ac6456` | `9859791a…` | pack build as a button (API + atomic `.tmp`→rename), model list out of the Configuration tab | no — local |
| [`0.1.44.1.d`](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.44.1.d.md) | `93a52b89ca6b` | `9859791a…` | metadata repair no longer sacrifices header keys — every model-file write behind a hard gate | no — local |
| [`0.1.44.1.e`](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.44.1.e.md) | `a4e0c060ff62` | `9859791a…` | the configurator only offers options the selected engine path accepts (`q36` vs packed) | no — local |
| [`0.1.44.1.f`](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.44.1.f.md) | `387bc23df8b0` | `9859791a…` | no dead controls: unsupported fields are not rendered, the "engine skips" list follows the model | no — local |
| [`0.1.44.1.g`](https://github.com/xxDoman/strata-gfx906/blob/master/docs/engines/0.1.44.1.g.md) | `d29828eefd6f` | `9859791a…` | path exclusions as a table, full EN/PL (checked at build time), panel view filter with persistent state | no — local |

Legend: *image sum* is the Docker **image ID** (config digest) of the build on this box, read from
`docker images --digests`; for the published tag it equals the registry digest returned by Docker Hub.
Every `0.1.44.1.x` image also carries an alias `:<tag>-test` that points at the same image ID.

## The engine binary, once

Both the `0.1.44.1.b`…`.g` builds ship **one and the same** engine binary — the engine was not rebuilt
anywhere in that line:

```
sha256  9859791aaa819eab78b414ddb01fc8875ac3f67ca58dfdc7491959cb06c5b7ca
size    29,704,144 B
version engine=0.1.44.1   (upstream tag v0.1.44.1 + 11 of our patches, gfx906 set GFX906-1..7 included)
```

So a difference between two `0.1.44.1.x` tags is **always** in the configurator (Python + HTML/JS), never
in the engine — which also means none of those differences can change a token/second number.

## Check a tag yourself, before trusting any page here

```bash
docker images --digests | grep strata-mi50          # tag -> image ID (and digest, if pulled)
curl -s https://hub.docker.com/v2/repositories/xxdoman/strata-mi50/tags | python3 -m json.tool
sha256sum /opt/strata/engine/strata                 # inside the container: the engine binary sum
```

Tag state is worth taking from the live Hub rather than from a note: this index is a record, the Hub is
the state. A tag that exists here and not on the Hub is a local build, and the reverse is also possible.

## Where the long form lives

- [Image history — what is in each released tag, and which fixes are ours](https://github.com/xxDoman/strata-gfx906/blob/master/docs/image-history.md)
- [Measurements — every number with its regime](https://github.com/xxDoman/strata-gfx906/blob/master/docs/measurements.md)
- [Community benchmark — a run of Strata's own suite on this pair](https://github.com/xxDoman/strata-gfx906/blob/master/docs/community-benchmark.md)
- [Where we stand — upstream's community results in one table](https://github.com/xxDoman/strata-gfx906/blob/master/docs/where-we-stand.md)
- Same pages on the wiki: [Engines](https://github.com/xxDoman/strata-gfx906/wiki/Engines) · [image-history](https://github.com/xxDoman/strata-gfx906/wiki/image-history) · [measurements](https://github.com/xxDoman/strata-gfx906/wiki/measurements) · [community-benchmark](https://github.com/xxDoman/strata-gfx906/wiki/community-benchmark) · [where-we-stand](https://github.com/xxDoman/strata-gfx906/wiki/where-we-stand)
- Upstream engine: <https://github.com/Niko1221/Strata> (MIT)
