
  _______                     ________        __
 |       |.-----.-----.-----.|  |  |  |.----.|  |_
 |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|
 |_______||   __|_____|__|__||________||__|  |____|
          |__| W I R E L E S S   F R E E D O M
___________________________________________________

# **Converting TP-Link WR1043ND v1 into a Linux Host on OpenWrt with Advanced Wi-Fi Monitoring**
### https://youtu.be/ToZc7O0AeFA

## 1. Introduction

The goal of this work is to transform an old TP-Link TL-WR1043ND v1 router into a full-fledged Linux-like platform based on OpenWrt, and then deploy a Wi-Fi client monitoring system consisting of:
- prometheus-node-exporter-lua
- two custom exporters:
  - wifi.lua — radio interface status (quality, level, noise, bitrate)
  - wifi_stations.lua — client statistics (RSSI, inactive, tx/rx, throughput)
- Prometheus — metrics collection
- Grafana — visualization, including active client count
- Alertmanager — alerts for "low signal" and "client disappeared"

## 2. Flashing the Router with OpenWrt

Used stable official OpenWrt release:
https://downloads.openwrt.org/releases/22.03.5/targets/ath79/generic/

Firmware file:
openwrt-22.03.5-ath79-generic-tplink_tl-wr1043nd-v1-squashfs-factory.bin

### 2.1. Converting/Downloading Native Firmware Without Boot

If we want to return to factory firmware from OpenWrt, we can't use it as is, we need to download either ...stripped.bin, or manually trim (remove boot) from the existing firmware file. For example:
https://4pda.to/forum/dl/post/8068068/TL-WR1043ND-V1-stripped.zip

Or execute `dd if=wr1043nv1.bin of=fw.bin skip=257 bs=512` where wr1043nv1.bin is the original firmware file

### 2.2. Saving Backup Settings

Connect to the standard TP-Link web panel http://192.168.1.1, then System Tools -> Backup & Restore -> Backup

### 2.3. Selecting the ...factory.bin File

The stable version is the file that contains the words factory and squashfs in its name.

Ready-to-use image that will work immediately after flashing:
https://mirror-03.infra.openwrt.org/releases/22.03.5/targets/ath79/generic/openwrt-22.03.5-ath79-generic-tplink_tl-wr1043nd-v1-squashfs-factory.bin

Stable image without Wi-Fi module:
https://archive.openwrt.org/backfire/10.03.1/ar71xx/openwrt-ar71xx-tl-wr1043nd-v1-squashfs-factory.bin

And we begin the reflashing process, System Tools -> Firmware Upgrade -> File (pick up) -> Upgrade.

### 2.4. After Loading

router starts on OpenWrt:
SSH access: ssh root@192.168.1.1
Web access: http://192.168.1.1/cgi-bin/luci/

### 2.5. Initial Password and Network Setup

Connect to the router in any LAN port.
Open in browser: http://192.168.1.1
If you see a web interface different from TP-Link interface, the flashing was successful.

At first login:
login: root
password: (empty)
OpenWRT will immediately ask to set a new password → set it.

Configuring internet (WAN). Open menu Network -> Interfaces -> WAN -> Edit, select connection method, in my case PPPoE.
Protocol: PPPoE
Username: ISP login
Password: ISP password
Save & Apply
You can check link in Network -> Diagnostics -> Ping

Configuring wireless network (Wi-Fi). Open menu Network -> Wireless. Line: Generic MAC80211 802.11bgn (radio0) in Disabled state. Click Edit, ESSID – network name, Mode: Access Point, Network: lan, Wireless security: Encryption -> WPA2-PSK, Key: Wi-Fi password. Save. Enable. Save & Apply at top of page.

Configuring DHCP server. Network -> Interfaces -> LAN -> Edit. DHCP Server tab.
Start: 100 – range start (192.168.1.100)
Limit: 50 – range end (192.168.1.149)
Save & Apply

IP reservations (Static Leases). Can bind permanent IPs to specific devices. Network -> DHCP and DNS -> Static Leases -> Add:

Hostname: any device name (e.g., laptop, server, tv)
MAC Address: physical address (can copy from DHCP Leases list above)
IP Address: desired IP, e.g., 192.168.1.10
Lease time: if left empty – permanent
Save & Apply

Changing LAN address and subnet can be done in Network -> Interfaces -> LAN -> Edit -> IPv4 address
Save & Apply.

The same settings can be configured via SSH. Main config files:
/etc/config/network
/etc/config/dhcp
/etc/config/wireless

Using console (e.g., git bash, ps) ssh root@192.168.1.1 (Can add your key for passwordless access (~/.ssh))

For Wi-Fi configuration vi /etc/config/wireless
```uci
config wifi-device 'radio0'
        option type 'mac80211'
        option path 'platform/ahb/180c0000.wmac'
        option channel '1'
        option band '2g'
        option htmode 'HT20'
        option disabled '0' # <-!!!

config wifi-iface 'default_radio0'
        option device 'radio0'
        option network 'lan'
        option mode 'ap'
        option ssid 'Wireless Network Name'
        option encryption 'psk2'
        option key 'wireless Password'
```
Configuring LAN vi /etc/config/network
```uci
config interface 'lan'
        option type 'bridge'
        option ifname 'eth0.1'
        option proto 'static'
        option ipaddr '192.168.0.2'  # Router LAN address
        option netmask '255.255.255.0'
        option ip6assign '60'
```
save and exit (:wq)

vi /etc/config/dhcp change or add DHCP pool for LAN
```uci
config dhcp 'lan'
        option interface 'lan'
        option start '100'
        option limit '50'
        option leasetime '12h'
        option force '1'
```
equals 192.168.0.100 – 192.168.0.149

Example static reservations:
```uci
config host
        option name 'desktop'
        option mac 'AA:BB:CC:DD:EE:01'
        option ip '192.168.0.10'

config host
        option name 'rpi'
        option mac 'AA:BB:CC:DD:EE:02'
        option ip '192.168.0.11'
```
Can enable local DNS via dnsmasq, in /etc/config/dhcp these options should be enabled:
```uci
option dhcpv4 'server'
        option ra 'server'
        option domain 'lan' – if missing, add it.
        option dynamicdhcp '1' – if missing, add it
```
Now you can ping hosts by option name, e.g., ping desktop.lan.

Example dnsmasq configuration:
```uci
config dnsmasq
        option domainneeded '1'
        option localise_queries '1'
        option rebind_protection '1'
        option rebind_localhost '1'
        option local '/homelab.com/' – resolves names within this zone
        option domain 'homelab.com' – sets local domain (now can use homelab.com)
        option expandhosts '1' – takes hostname from DHCP reservations and adds to local domain
        option authoritative '1'
        option readethers '1'
        option leasefile '/tmp/dhcp.leases'
        option resolvfile '/tmp/resolv.conf.d/resolv.conf.auto'
        option localservice '1'
        option ednspacket_max '1232'
#        option logqueries '1' – enables DNS logging
```
Example WAN configuration:
```uci
config interface 'wan'
        option device 'eth0.2'
        option proto 'pppoe'
        option username 'isp login'
        option password 'isp password'
        option ipv6 'auto'
```
To apply configuration changes execute: /etc/init.d/dnsmasq restart (this restarts DHCP without losing SSH), then: /etc/init.d/network reload

Verification:
```bash
    ip addr show br-lan (check router IP)
    cat /tmp/dhcp.leases (check active leases)
    ps | grep dnsmasq (check if dnsmasq is running)
```
**Summary**

After flashing, the device essentially becomes a compact Linux host with BusyBox, opkg, UCI, and access to system services, with extended capabilities:

- **VLAN support and fine interface tuning** — can segment the network without additional equipment
- **Flexible WAN/LAN configuration**: static IP, PPPoE, DHCP, failover, multi-WAN, WAN as LAN (See bonus section)
- **Firewall and NAT** fully configurable through iptables/nftables, plus QoS
- **IPv6**: full support with DHCPv6, SLAAC, tunnel configuration
- **All radio modules and SSIDs** under full control: power adjustment, channels, standards (a/b/g/n/ac), HT/VHT
- **Monitoring connected clients**: can view MAC, RSSI, bitrate, inactive time
- **SSID separation** for guest networks with different VLAN or firewall rules
- **Installation of additional packages** through opkg
- **For example**:
  - Prometheus Node Exporter for monitoring
  - VPN services: OpenVPN, WireGuard
  - Adblock / Pi-hole like services
  - Samba, NFS, FTP for file server
- **SSH/console access** with full BusyBox utilities
- **Cron / scheduled tasks** for automation
- **Lua or shell scripts** for custom monitoring and metrics (as we did with Wi-Fi metrics)
- **Configuration saving** through UCI and backup recovery capability
- **Full data collection capability**: CPU load, memory, network, Wi-Fi clients, temperature (if sensors available)
- **Integration with Prometheus** through Node Exporter or custom scripts
- **Events and logging** through syslog, can integrate with external systems
- **Available wireless interface modes**: Access Point, Client, Ad-Hoc, 802.11s, Pseudo Ad-Hoc (ahdemo), Monitor, Access Point (WDS), Client (WDS)

## 3. Monitoring System on OpenWrt

### 3.1. Installing Prometheus Node Exporter (Lua)

Packages:
```bash
    opkg update
    opkg install prometheus-node-exporter-lua
    opkg install prometheus-node-exporter-lua-openwrt
    opkg install prometheus-node-exporter-lua-wifi
    opkg install prometheus-node-exporter-lua-wifi_stations
```
After installation, standard collectors are located in /usr/lib/lua/prometheus-collectors/. We modify wifi_stations.lua (section 4.1.)

## 4. Custom Lua Wi-Fi Collectors

Both scripts use:
- ubus — for getting network.wireless structures
- iwinfo — for signal level, noise, clients, bitrate
- metric format fully compatible with Prometheus

### 4.1. wifi.lua — interface parameters

- (file in /usr/lib/lua/prometheus-collectors/wifi.lua)
- signal quality
- bitrate
- noise
- signal level
- ssid, bssid, mode, channel, frequency

Full code:
```lua
    local ubus = require "ubus"
    local iwinfo = require "iwinfo"

local function scrape()
    local metric_wifi_network_quality = metric("wifi_network_quality", "gauge")
    local metric_wifi_network_bitrate = metric("wifi_network_bitrate", "gauge")
    local metric_wifi_network_noise = metric("wifi_network_noise_dbm", "gauge")
    local metric_wifi_network_signal = metric("wifi_network_signal_dbm", "gauge")

    local u = ubus.connect()
    local status = u:call("network.wireless", "status", {})

    for dev, dev_table in pairs(status) do
        for _, intf in ipairs(dev_table['interfaces']) do
            local ifname = intf['ifname']
            if ifname ~= nil then
                local iw = iwinfo[iwinfo.type(ifname)]
                local labels = {
                    channel = iw.channel(ifname),
                    ssid = iw.ssid(ifname),
                    bssid = string.lower(iw.bssid(ifname)),
                    mode = iw.mode(ifname),
                    ifname = ifname,
                    country = iw.country(ifname),
                    frequency = iw.frequency(ifname),
                    device = dev,
                }

                local qc = iw.quality(ifname) or 0
                local qm = iw.quality_max(ifname) or 0
                local quality = 0
                if qc > 0 and qm > 0 then
                    quality = math.floor((100 / qm) * qc)
                end

                metric_wifi_network_quality(labels, quality)
                metric_wifi_network_noise(labels, iw.noise(ifname) or 0)
                metric_wifi_network_bitrate(labels, iw.bitrate(ifname) or 0)
                metric_wifi_network_signal(labels, iw.signal(ifname) or -255)
            end
        end
    end
end

return { scrape = scrape }
```
### 4.2. wifi_stations.lua — client parameters

(file in /usr/lib/lua/prometheus-collectors/wifi_stations.lua)
- RSSI
- inactive (ms)
- expected throughput
- tx/rx bitrate
- tx/rx pkts, bytes
- client count → new → wifi_stations{name="wlan0"}

Full code:
```lua
  local ubus = require "ubus"
  local iwinfo = require "iwinfo"

local function safe_label(val)
  if not val then return "" end
  val = tostring(val)
  val = val:gsub("\\", "\\\\")
  val = val:gsub("\"", "\\\"")
  return val
end

local function scrape()
  local metric_wifi_stations = metric("wifi_stations", "gauge")
  local metric_wifi_station_signal = metric("wifi_station_signal_dbm","gauge")
  local metric_wifi_station_inactive = metric('wifi_station_inactive_milliseconds', 'gauge')
  local metric_wifi_station_exp_thr = metric('wifi_station_expected_throughput_kilobits_per_second', 'gauge')
  local metric_wifi_station_tx_bitrate = metric('wifi_station_transmit_kilobits_per_second', 'gauge')
  local metric_wifi_station_rx_bitrate = metric('wifi_station_receive_kilobits_per_second', 'gauge')
  local metric_wifi_station_tx_packets = metric("wifi_station_transmit_packets_total","counter")
  local metric_wifi_station_rx_packets = metric("wifi_station_receive_packets_total","counter")
  local metric_wifi_station_tx_bytes = metric('wifi_station_transmit_bytes_total', 'counter')
  local metric_wifi_station_rx_bytes = metric('wifi_station_receive_bytes_total', 'counter')

  local u = ubus.connect()
  local status = u:call("network.wireless", "status", {})
  for dev, dev_table in pairs(status) do
    for _, intf in ipairs(dev_table['interfaces']) do
      local ifname = intf['ifname']
      if ifname then
        local iw = iwinfo[iwinfo.type(ifname)]
        local assoclist = iw.assoclist(ifname)
        local count = 0

        for mac, station in pairs(assoclist) do
          local labels = {
            ifname = safe_label(ifname),
            mac    = safe_label(mac)
          }

          if station.signal and station.signal ~= 0 then
            metric_wifi_station_signal(labels, station.signal)
          end
          if station.inactive then
            metric_wifi_station_inactive(labels, station.inactive)
          end
          if station.expected_throughput and station.expected_throughput ~= 0 then
            metric_wifi_station_exp_thr(labels, station.expected_throughput)
          end
          if station.tx_rate and station.tx_rate ~= 0 then
            metric_wifi_station_tx_bitrate(labels, station.tx_rate)
          end
          if station.rx_rate and station.rx_rate ~= 0 then
            metric_wifi_station_rx_bitrate(labels, station.rx_rate)
          end
          metric_wifi_station_tx_packets(labels, station.tx_packets)
          metric_wifi_station_rx_packets(labels, station.rx_packets)
          if station.tx_bytes then
            metric_wifi_station_tx_bytes(labels, station.tx_bytes)
          end
          if station.rx_bytes then
            metric_wifi_station_rx_bytes(labels, station.rx_bytes)
          end

          count = count + 1
        end
        metric_wifi_stations({ifname = safe_label(ifname)}, count)
      end
    end
  end
end

return { scrape = scrape }
```

### 4.3. prometheus-node-exporter-lua — port and listening interface parameters
(file /etc/config/prometheus-node-exporter-lua)
```uci
config prometheus-node-exporter-lua 'main'
    option listen_interface 'lan'      # instead of 'loopback'
    option listen_port '9100'
```
Or from command line execute the following:
```bash
    uci set prometheus-node-exporter-lua.main.listen_interface='lan'
    uci set prometheus-node-exporter-lua.main.listen_port='9100'
    uci commit prometheus-node-exporter-lua
    /etc/init.d/prometheus-node-exporter-lua restart
```
### 4.4. Example firewall configuration (generally not needed)
```bash
    uci add firewall rule
    uci set firewall.@rule[-1].name='Prometheus Node Exporter'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest_port='9100'
    uci set firewall.@rule[-1].proto='tcp udp'
    uci set firewall.@rule[-1].target='ACCEPT'
    uci commit firewall
    /etc/init.d/firewall restart
```
## 5. Verifying Metrics Operation

Verification:
```bash
    curl http://192.168.0.2:9100/metrics
```
Make sure these are present:
```promql
wifi_network_quality{...}
wifi_station_signal_dbm{mac="..."}
wifi_stations{ifname="wlan0"} 3
```
## 6. Prometheus Configuration
```yaml
job:
scrape_configs:
  - job_name: 'openwrt'
    static_configs:
      - targets: ['192.168.0.2:9100']
```
## 7. Grafana Dashboard

Key graph: client count (http://192.168.0.2:9100/metrics)

PromQL:
```promql
Client signal: wifi_station_signal_dbm
Signal for specific MAC: wifi_station_signal_dbm{mac="aa:bb:cc:dd:ee:ff"}
Noise level: wifi_station_noise_dbm
TX/RX traffic packets by MAC: 
  rate(wifi_station_transmit_packets_total[5m])
  rate(wifi_station_receive_packets_total[5m])
PHY speed (expected throughput): wifi_station_expected_throughput_kilobits_per_second
Inactive clients (ms): wifi_station_inactive_milliseconds
Bitrate (tx/rx):
  wifi_station_transmit_kilobits_per_second
  wifi_station_receive_kilobits_per_second
Number of subscribers:
  total number of connected clients:
  count(wifi_station_signal_dbm)
number of clients per interface: count by (iface)(wifi_station_signal_dbm)
list of MAC addresses currently online:label_join(wifi_station_signal_dbm, "mac", "", "mac")
```

Example panel
- Columns:
  - MAC
  - RSSI
  - inactive
  - expected throughput
  - tx/rx bitrate
  - tx/rx packets
- Repeat by ifname (if multiple SSIDs)

## 8. Alertmanager — Ready Rules

### 8.1. Client Disconnected
```yaml
groups:
- name: wifi-alerts
  rules:
  - alert: WifiClientInactive
    expr: wifi_station_inactive_milliseconds > 30000
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "Client inactive > 30s"
      description: "MAC: {{ $labels.mac }} on {{ $labels.ifname }}"
```
### 8.2. Low Signal
```yaml
  - alert: WifiLowSignal
    expr: wifi_station_signal_dbm < -80
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Low WiFi signal"
      description: "MAC: {{ $labels.mac }} RSSI {{ $value }}"
```
### 8.3. Too Many Clients (Overload)
```yaml
  - alert: WifiTooManyClients
    expr: wifi_stations > 12
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Too many WiFi clients"
      description: "Interface {{ $labels.ifname }} has {{ $value }} clients"
```
## 9. Result

As a result, the old TP-Link WR1043ND v1 has been transformed into:

- **Lightweight Linux host** on OpenWrt 22.03.5
- **Custom Wi-Fi monitoring** at professional controller level
- **Providing comprehensive monitoring**:
  - Interface status
  - Client statistics  
  - Throughput metrics
  - Signal quality
  - Transmission speed
  - Subscriber count
- **Full integration** with:
  - Prometheus
  - Grafana
  - Alertmanager

The result is a full-fledged Wi-Fi status monitoring system, comparable to UniFi or MikroTik CAPsMAN, but on a budget router.

## 10. Bonus

Use the WAN-Port as a LAN-Port
remove the following lines, to remove the wan specific configuration (vlan and interface)
V1.x /etc/config/network
```uci
config interface 'wan'
        option ifname 'eth0.2'
        option proto 'dhcp'
```
and
```uci
config switch_vlan
        option device 'switch0'
        option vlan '2'
        option ports '0 5t'
```
and add the port 0 to the existing Vlan
```uci
config switch_vlan
        option device 'switch0'
        option vlan '1'
# add port 0 to the line below
        option ports '0 1 2 3 4 5t'
```
## 11. Rollback

To return to factory firmware from OpenWrt requires a binary with trimmed boot, these are...stripped.bin files. You can also perform this procedure yourself:
```bash 
dd if=wr1043nv1.bin of=fw.bin skip=257 bs=512
```
, where wr1043nv1.bin is the original firmware file.
https://4pda.to/forum/dl/post/8068068/TL-WR1043ND-V1-stripped.zip

Before starting the procedure, reset the router to factory settings. Through web interface this is:
System -> Backup/Flash Firmware -> Reset to defaults (red button Perform reset).
Or via CLI (better use stripped without dd, otherwise 99% can be bricked):
```bash
ssh root@192.168.0.2
firstboot -y && reboot
exit
dd if=wr1043nv1.bin of=fw.bin skip=257 bs=512
scp fw.bin root@192.168.1.1:/tmp/. #Use flag -O (uppercase o) in error case ash: /usr/libexec/sftp-server: not found 
ssh root@192.168.1.1 (this is the default address after reset)
cd /tmp
mtd -r write fw.bin firmware
```
If router is bricked – disassemle the router, find four pin connector (RX, TX, GND, VCC) on the main board, connect thru UART-USB adaptor (bitrate 115200) using Putty, turn on the router and strat typing tpl tpl tpl until CLI appears. Set the NIC as 192.168.0.5/24 gw 192.168.0.1 on PC, run TFTPd and start broadcasting the binaries. Server IP 192.168.0.5. The commands to run on the terminal:
```bash
erase 0xbf020000 +7c0000
tftpboot 0x81000000 .bin
cp.b 0x81000000 0xbf020000 0x7c0000
bootm 0xbf020000
```
More detailed at https://dcbeelinekz.1bb.ru/viewtopic.php?id=124



## 12. Useful Commands for OpenWrt
```bash
uci set wireless.@wifi-iface[0].mode='client'
uci commit wireless
wifi reload.

uci show wireless
uci set wireless.radioN.disabled='0'
uci set wireless.radioN.country='XX'
uci commit wireless
wifi reload

iwinfo
iwinfo wlan0 assoclist
iw dev wlan0 station dump
wifi up
ua -e 'local iw=require("iwinfo"); for k,v in pairs(iw.nl80211) do print(k,v) end'
iwinfo wlan0 scan
ubus call network.wireless status

logread -e lua
logread -e Prometheus
/etc/init.d/prometheus-node-exporter-lua restart
netstat -lnp | grep 9100
curl http://192.168.0.2:9100/metrics | grep wifi
```
Flashing (back to TP-Link)
```bash
firstboot -y && reboot
dd if=wr1043nv1.bin of=wr1043nv1out.bin skip=257 bs=512
scp fw.bin root@192.168.1.1:/tmp/.
mtd -r write fw.bin firmware
```
Useful Links
https://openwrt.org/toh/tp-link/tl-wr1043nd
https://archive.openwrt.org/backfire/10.03.1/ar71xx/
https://mirror-03.infra.openwrt.org/releases/22.03.5/targets/ath79/generic/
https://4pda.to/forum/index.php?showtopic=558575&st=920
https://openwrt.org/ru/toh/tp-link/tl-wr1043nd#back_to_original_firmware
https://dd-wrt.com/support/router-database/

LuCI Plugins and Tools
```bash
opkg install luci-app-statistics collectd-mod-interface collectd-mod-cpu collectd-mod-memory
```
This will allow monitoring traffic, CPU, memory, etc. directly in the web interface.


## 13. Final text - REPO USAGE

Within this repo you can find all scripts, configs and ready monitoring tools related to this project. 

The project structure:

 grafana-deploy]# tree
.
├── alert.rules.yml
├── docker-compose.yml
├── grafana
│   ├── datasources.yaml
│   ├── example-dashboard.json
│   ├── OpenWrt_Full_Node_Exporter.json
│   ├── OpenWrt_Wi-Fi_Dashboard.json
│   └── Router_OpenWrt_unified.json
├── loki-config.yaml
├── monitoring_down.sh
├── monitoring_up.sh
├── prometheus.yml
├── promtail-config.yaml
├── README.md
├── README.rus
├── template.tmpl
└── TPLINK
    ├── Native
    │   ├── TL-WR1043ND_v1_from_OpenWRT
    │   │   ├── tplink_WR1043ND.bin
    │   │   └── wr1043nv1_ru_3_13_11_up_boot(121102).bin
    │   ├── TL-WR1043ND-V1-stripped
    │   │   ├── md5sum.txt
    │   │   ├── TL-WR1043ND-V1-FW0.0.3-stripped.bin
    │   │   └── WR1043ND-tp-recovery.bin
    │   ├── tl-wr1043nd_v1-webrevert.bin
    │   ├── wr1043nv1_en_3_13_13_up_boot(130325).bin
    │   ├── wr1043nv1_en_3_13_13_up_boot(130428).bin
    │   └── wr1043nv1_en_3_13_15_up_boot(140319).bin
    └── OpenWrt
        ├── FW
        │   ├── openwrt-22.03.5-ath79-generic-tplink_tl-wr1043nd-v1-squashfs-factory.bin
        │   └── openwrt-ar71xx-tl-wr1043nd-v1-squashfs-factory.bin
        └── prometheus_scripts
            ├── collect_wifi.lua
            ├── wifi_stations_w.lua
            └── wifi_w.lua
 

To launch a ready Grafana-Prometheus-Alertmanager set, this very repo can be used for testing or using widely.
To do so and stop all deleting the secrets just run the scripts below:
```bash
   ./monitoring_up.sh
   ./monitoring_down.sh
```



## 14. Wi-Fi Interface Key Metrics (wifi_network_*)

| Metric | What it shows | How to use |
|--------|---------------|------------|
| `wifi_network_quality` | Signal quality (0–100%) | Graph AP signal quality. Can set threshold <50% — weak signal. |
| `wifi_network_signal_dbm` | RSSI signal in dBm | Strong signal around -50…-60 dBm. -80 and below — weak signal. |
| `wifi_network_noise_dbm` | Noise level in dBm | Lower noise is better (< -90 dBm). High noise degrades quality. |
| `wifi_network_bitrate` | Current transmission speed (kbit/s) | Check AP throughput, drops under overload. |

## Client Metrics (wifi_station_*)

| Metric | What it shows | How to use |
|--------|---------------|------------|
| `wifi_station_signal_dbm` | Client RSSI in dBm | Check signal quality for each client. |
| `wifi_station_inactive_milliseconds` | Time without activity | If growing — client inactive or connection lost. |
| `wifi_station_expected_throughput_kilobits_per_second` | Expected transmission speed | Can compare with actual `transmit/receive` speed. |
| `wifi_station_transmit_kilobits_per_second` | AP→client transmission speed | Monitor Wi-Fi load. |
| `wifi_station_receive_kilobits_per_second` | Client→AP transmission speed | Same but in reverse direction. |
| `wifi_station_transmit/receive_packets_total` | Packet count | For load analysis and packet loss issues. |
| `wifi_stations` | Total number of connected clients | Can set alert if AP "loses" clients. |
