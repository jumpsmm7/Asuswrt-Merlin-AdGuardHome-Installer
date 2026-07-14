# Service Management

## Recommended service commands

Use Asuswrt-Merlin service events:

```sh
service start_AdGuardHome
service stop_AdGuardHome
service restart_AdGuardHome
service reload_AdGuardHome
service kill_AdGuardHome
```

`service` is a router-stock binary at `/sbin/service`.

## Entware init script

After Entware is mounted, the init script can be called directly:

```sh
/opt/etc/init.d/S99AdGuardHome start
/opt/etc/init.d/S99AdGuardHome stop
/opt/etc/init.d/S99AdGuardHome restart
/opt/etc/init.d/S99AdGuardHome check
/opt/etc/init.d/S99AdGuardHome reload
/opt/etc/init.d/S99AdGuardHome kill
```

Restarting AdGuardHome can interrupt DNS service. Avoid unnecessary restarts during active network use.
