# Blocklist Analysis

The installer can run an unused blocklist analyzer to identify filter lists with zero query-log rule hits during the analyzed window.

## Run from the installer menu

Use menu option **9** when available.

## Run from the command line

```sh
sh installer blocklists
sh installer unusedblocklists
```

## Dependency note

The analyzer uses Python. On routers, Python is not available in the stock PATH. If this feature is needed, install the Entware package after Entware is mounted:

```sh
opkg install python3
```

Keep this dependency separate from stock-router bootstrap steps.
