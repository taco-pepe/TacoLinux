# Vendored sources

Upstream source trees for everything in `rootfs/usr/local/bin`, kept here so
the binaries always ship with their corresponding source (GPL compliance) and
the image can be rebuilt offline once these are present.

- One directory per tool (see `../scripts/cli-tools/apps.tsv` for versions,
  URLs and recipes).
- Every `.git` directory is stripped after extraction.
- `SHA256SUMS` records the SHA-256 of each upstream archive and a digest of
  each extracted tree.
- Debian pool / GNU / GitHub mirrors are used because `nano-editor.org` and
  `codeberg.org` are unreachable from some networks (including Iran).

Rebuild:

```sh
./scripts/fetch-cli-sources.sh   # only fetches what is missing
./scripts/build-cli-tools.sh     # static musl build -> rootfs/usr/local/bin
./scripts/test-cli-tools.sh      # verifies static linkage + that it runs
```

Licences are upstream's. Nothing here is modified except the removal of VCS
metadata; build-time patches are not applied, so the tree is pristine.
