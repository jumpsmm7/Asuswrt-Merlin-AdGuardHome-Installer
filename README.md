<a href="https://ibb.co/CMDBVRS"><img src="https://i.ibb.co/wwjyp52/Ad-Guard-Home.jpg" alt="Ad-Guard-Home" border="0"></a>
# Asuswrt-Merlin-AdGuardHome-Installer
The Official Installer of AdGuardHome for Asuswrt-Merlin
# Requirements:
- ARM based ASUS routers that use Asuswrt-Merlin Firmware
- JFFS support and enabled
# Incompatibilities:
- No known issue
# Current features:
- [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome) Network-wide ads & trackers blocking DNS server, with multiple dns protocol encryption, and other features.
- Support ARM based routers
- Redirect all DNS queries on your network to AdGuardHome if user chooses to use Merlin DNS Filter Option
- Ability to update AdGuardHome without reinstalling/reconfiguring
- Improved Installer/Update/Backup Functions.
# AdGuardHome Supports Multiple Features
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

# Setting Up Your Routers Reverse DNS
<a href="https://imgbb.com/"><img src="https://i.ibb.co/QvJ5nNV/Lan.jpg" alt="Lan" border="0"></a>
- Under Lan DHCP page on Asuswrt-Merlin define a domain such as lan or some-domain like in the image above.
<a href="https://ibb.co/vDRpFQh"><img src="https://i.ibb.co/4J3zqY2/Reverse-DNS.jpg" alt="Reverse-DNS" border="0"></a>
- Define the appropriate rules inside the Private Reverse DNS Servers.
# Changelog:
https://github.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/commits/master
# Install/Update/Reconfig/Uninstall:
Run this command from ssh shell and following the prompt for AdGuardHome:
```
curl -L -s -k -O https://raw.githubusercontent.com/jumpsmm7/Asuswrt-Merlin-AdGuardHome-Installer/master/installer && sh installer
```
# Terminal commands to for AdGuardHome are
```
/opt/etc/init.d/S99AdGuardHome {stop|start|restart|kill|check}
```
or
```
service {stop|start|restart|kill}_AdGuardHome
```
# How to check if it works
Run this command in the ssh shell:
```
pidof AdGuardHome
```
will return a number.
# How to report issue:
I need following directory:
```
/opt/etc/AdGuardHome
/jffs/scripts/dnsmasq.postconf
```
One can use this command to create a tar archive of these files:
```
echo .config > exclude-files; tar -cvf AdGuardHome.tar -X exclude-files /opt/etc/AdGuardHome /jffs/scripts/dnsmasq.postconf; rm exclude-files
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
