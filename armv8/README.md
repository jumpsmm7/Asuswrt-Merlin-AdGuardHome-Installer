# ARMv8 AdGuardHome archives

The `Cache AdGuardHome static archives` workflow writes local static AdGuardHome archive copies here for ARMv8 routers. The installer maps this folder to AdGuardHome's `linux_arm64` archive.

Expected generated archive files:

- `AdGuardHome_stable_linux_arm64.tar.gz`
- `AdGuardHome_beta_linux_arm64.tar.gz`
- `AdGuardHome_edge_linux_arm64.tar.gz`

Expected generated metadata files:

- `VERSION.txt` records the version associated with each archive.
- `checksum.txt` records MD5 and SHA-256 checksums for each archive.
