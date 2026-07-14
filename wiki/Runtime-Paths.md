# Runtime Paths

The following paths are used after Entware is installed and AdGuardHome is installed or partially staged.

| Path | Purpose |
| --- | --- |
| `/opt/etc/AdGuardHome` | AdGuardHome configuration, data, installer `.config`, and IPSET user files. |
| `/opt/sbin/AdGuardHome` | AdGuardHome binary symlink managed by the installer. |
| `/opt/etc/init.d/S99AdGuardHome` | Entware init script. |
| `/opt/etc/init.d/rc.func.AdGuardHome` | Shared service functions. |
| `/opt/etc/backup_AdGuardHome.tar.gz` | Default backup archive location. |
| `/jffs/addons/AdGuardHome.d` | Asuswrt-Merlin hook integration. |
| `/jffs/scripts/dnsmasq.postconf` | dnsmasq post-configuration hook. |
| `/jffs/scripts/firewall-start` | Firewall-start hook. |
| `/jffs/scripts/service-event-end` | Service event hook. |

Do not use `/opt/...` examples before Entware is mounted.
