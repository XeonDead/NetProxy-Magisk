# Module Configuration

## Configure File Location

The module profile is located in `/data/adb/modules/netproxy/config/` Under the table of contents:

```
config/
├── module.conf          # Module master configuration
├── tproxy.conf          # TProxy Transparent proxy configuration
├── routing_rules.json   # Route Configuration
└── xray/                # Xray Configure Directory
    ├── confdir/         # Xray Modular Configuration
    └── outbounds/       # Node Configuration
```

---

## module.conf

Module master profile to control basic behavior.

```bash
# NetProxy Module Settings

# Autostart service. (1=Enable, 0=Disable)
AUTO_START=1

# Out of station mode (rule=Rules diverting, global=Global Agent, direct=Global Straight Company)
OUTBOUND_MODE=rule

# OnePlus Android 16 Rehabilitation (1=Enable, 0=Disable)
ONEPLUS_A16_FIX=0

# Current Profile Path
CURRENT_CONFIG="/data/adb/modules/netproxy/config/xray/outbounds/default.json"
```

| Configure Item | Annotations | Optional value |
|--------|------|--------|
| `AUTO_START` | Turn yourself on. | `1` / `0` |
| `OUTBOUND_MODE` | Out of station mode | `rule` / `global` / `direct` |
| `ONEPLUS_A16_FIX` | One. A16 Rehabilitation | `1` / `0` |
| `CURRENT_CONFIG` | Current Node Configuration Path | File Path |

---

## tproxy.conf

TProxy Transparent proxy detailed configuration.

### Proxy Core Configuration

```bash
# Proxy Process Run Users and Groups
CORE_USER_GROUP="root:net_admin"

# Transparent proxy listening port
PROXY_TCP_PORT="12345"
PROXY_UDP_PORT="12345"

# Proxy Mode: 0=Autodetect, 1=ForceTPROXY, 2=ForceREDIRECT
PROXY_MODE=0
```

### DNS Configure

```bash
# DNS Hijacking methods (0: Disable, 1: tproxy, 2: redirect)
DNS_HIJACK_ENABLE=1

# DNS Listen Port
DNS_PORT="1053"
```

### Network Interface

```bash
# Mobile Data Interface
MOBILE_INTERFACE="rmnet_data+"

# WiFi Interface
WIFI_INTERFACE="wlan0"

# Hotspot Interface
HOTSPOT_INTERFACE="wlan2"

# USB Shared interface
USB_INTERFACE="rndis+"
```

### Proxy Switch

```bash
PROXY_MOBILE=1    # Proxy Move Data
PROXY_WIFI=1      # Proxy WiFi
PROXY_HOTSPOT=0   # Proxy Hotspot
PROXY_USB=0       # Proxy USB Share
PROXY_TCP=1       # Proxy TCP
PROXY_UDP=1       # Proxy UDP
PROXY_IPV6=0      # Proxy IPv6
```

### Subappliance Proxy

```bash
# Enable sub-application agent (0: Disable, 1: Enable)
APP_PROXY_ENABLE=1

# Proxy Apply List (Space Separator)
PROXY_APPS_LIST=""

# Skip the application list (Space Separator)
BYPASS_APPS_LIST=""

# Subapplication Mode
APP_PROXY_MODE="blacklist"  # blacklist or whitelist
```

### China IP Around

```bash
BYPASS_CN_IP=0
CN_IP_FILE=""
CN_IPV6_FILE=""
CN_IP_URL="https://raw.githubusercontent.com/Hackl0us/GeoIP2-CN/release/CN-ip-cidr.txt"
```

---

## Modify Configuration

### Pass. WebUI

Most configurations can be used WebUI Yes. **Settings** page change.
