<a href="https://ibb.co/Zm7hLhD"><img src="https://i.ibb.co/0tvfDfb/image.png" alt="image" border="0"></a>
# Asuswrt-Merlin-AdGuardHome-Installer:
The Official Installer of AdGuardHome for Asuswrt-Merlin
# Requirements:
- ARM based ASUS routers that use Asuswrt-Merlin Firmware, and Entware Repository.
- JFFS support and enabled.
- REQUIRES ENTWARE(!) for package management, and a separate USB drive for storage -i.e. the same drive Entware is stored.
- Entware must be fully up-to-date as well `opkg update && opkg upgrade`.
- Minimum recommended to have a 2gb swap file. (up to 10gb can be made with AMTM).
- Minimum supported firmware version is 384.11.
- It is recommended to use a Router stronger than the RT-AC68U, even though the AdGuardHome can be used at a limited capacity on the RT-AC68U.
# Incompatibilities:
- No known issue, but may not be compatible with "some" doule-nat or dual-wan environments since AdGuardHome takes over DNSMASQ placement on port 53. DNSMASQ uses port 553 instead.
# Current features:
- [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome) Network-wide ads & trackers blocking DNS server, with multiple dns protocol encryption, and other features.
- Support ARM based routers
- Redirect all DNS queries on your network to AdGuardHome if user chooses to use Merlin DNS Filter Option
- Ability to update AdGuardHome without reinstalling/reconfiguring
- Improved Installer/Update/Backup Functions.
# AdGuardHome Supports Multiple Features:
<a href="https://ibb.co/ZhTX4N4"><img src="https://i.ibb.co/cNT3fxf/Features.jpg" alt="Features" border="0"></a>
- 94.140.14.140: plain DNS (over UDP).
- tls://dns-unfiltered.adguard.com: encrypted DNS-over-TLS.
- https://cloudflare-dns.com/dns-query: encrypted DNS-over-HTTPS.
- quic://dns-unfiltered.adguard.com:784: experimental DNS-over-QUIC support.
- tcp://1.1.1.1: plain DNS (over TCP).
- sdns://...: DNS Stamps for DNSCrypt or DNS-over-HTTPS resolvers.
- [/example.local/]1.1.1.1: DNS upstream for specific domains, see below.
<a href="https://ibb.co/txhZqvt"><img src="https://i.ibb.co/SdxQtM8/Upstream-DNS.jpg" alt="Upstream-DNS" border="0"></a>

This forum link will provide you with a link to more dns servers and instructional use:
http://www.snbforums.com/threads/release-asuswrt-merlin-adguardhome-installer-amaghi.76506/post-735471
also,
https://adguard-dns.io/kb/general/dns-providers/
# Setting Up Your Routers Reverse DNS:
<a href="https://imgbb.com/"><img src="https://i.ibb.co/QvJ5nNV/Lan.jpg" alt="Lan" border="0"></a>
- Under Lan DHCP page on Asuswrt-Merlin define a domain such as lan or some-domain like in the image above.
<a href="https://ibb.co/vDRpFQh"><img src="https://i.ibb.co/4J3zqY2/Reverse-DNS.jpg" alt="Reverse-DNS" border="0"></a>
- Define the appropriate rules inside the Private Reverse DNS Servers.
The AdGuardHome Installer already does this, but the information is more for user personal education. 
# Best AdGuardHome Setup Guide:
For the Best AdGuardHome Setup Guide please refer to their wiki:
https://github.com/AdguardTeam/AdGuardHome/wiki
# AdGuardHome Developement:
For issues pertaining with AdGuardHome itself, please refer to this link:
https://github.com/AdguardTeam/AdGuardHome/issues
# Changelog:
https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/commits/master
# Install/Update/Reconfig/Uninstall:
Run this command from ssh shell and following the prompt for AdGuardHome:
```
curl -L -s -O https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/installer && sh installer
```
# Terminal commands to for AdGuardHome are:
```
/opt/etc/init.d/S99AdGuardHome {start|stop|restart|check|kill|reload}
```
or (recommended commands)
```
service {start|stop|restart|kill|reload}_AdGuardHome
```
# How to check if it works:
Run this command in the ssh shell:
```
pidof AdGuardHome
```
will return a number.

or:
```
/opt/etc/init.d/S99AdGuardHome check
```
which will return
```
  Checking AdGuardHome...              alive.
```
# How to report issue:
I need following directories and files:
```
/opt/etc/AdGuardHome
/opt/sbin/AdGuardHome
/opt/etc/init.d/S99AdGuardHome
/opt/etc/init.d/rc.func.AdGuardHome
/jffs/addons/AdGuardHome.d
/jffs/scripts/init-start
/jffs/scripts/dnsmasq.postconf
/jffs/scripts/services-stop
/jffs/scripts/service-event-end
```
One can use this command to create a tar archive of these files:
```
echo .config > exclude-files; tar -cvf AdGuardHome.tar -X exclude-files /opt/etc/AdGuardHome /opt/sbin/AdGuardHome /opt/etc/init.d/S99AdGuardHome /opt/etc/init.d/rc.func.AdGuardHome /jffs/addons/AdGuardHome.d /jffs/scripts/init-start /jffs/scripts/dnsmasq.postconf /jffs/scripts/services-stop /jffs/scripts/service-event-end; rm exclude-files
```
in current directory and send me the archive for debug.
I also need following information:
- Which dns server you selected during AdGuardHome installation
- Which router you're using
- Firmware and its version
# How I made this:
- Use AdGuardHome binary packages from https://github.com/AdguardTeam/AdGuardHome
- I wrote the installer script with stuff inspired from entware-setup.sh from asuswrt-merlin
- You can look at all the stuff here https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer
# Donate:
This script will always be open source and free to use under [GPL-3.0 License](https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/LICENSE), but if you want to support future development you can do so by [Donating With PayPal](https://paypal.me/swotrb) or [Buy me a coffee](https://www.buymeacoffee.com/swotrb).
