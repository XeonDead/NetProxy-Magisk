<p align="center">
  <img src="image/logo.png" alt="NetProxy Logo" width="120" />
</p>

<h1 align="center">NetProxy</h1>

<p align="center">
  <strong>Android System Level Xray Transparent proxy module</strong><br>
  Support TPROXY、UDP、IPv6, sub-appliance agent, subscription management
</p>

<p align="center">
  <a href="https://github.com/Fanju6/NetProxy-Magisk/releases">
    <img src="https://img.shields.io/github/v/release/Fanju6/NetProxy-Magisk?style=flat-square&label=Release&color=blue" alt="Latest Release" />
  </a>
  <a href="https://github.com/Fanju6/NetProxy-Magisk/releases">
    <img src="https://img.shields.io/github/downloads/Fanju6/NetProxy-Magisk/total?style=flat-square&color=green" alt="Downloads" />
  </a>
  <img src="https://img.shields.io/badge/Xray-Core-blueviolet?style=flat-square" alt="Xray Core" />
</p>

<p align="center">
  Chinese | <a href="README.md">English</a>
</p>

---

## Functional characteristics

| Functions | Description |
|------|------|
| **APPManagement** | Miuix Modern interface to support Monet colouring |
| **Transparent Agent** | Support TPROXY / REDIRECT Two models.TCP + UDP Take over. |
| **Subappliance Proxy** | Blacklist / White list mode, precise control of proxy range |
| **Route Settings** | Custom domain name,IPRoute rules, port etc. |
| **DNS Settings** | Custom DNS Servers and static Hosts Map |
| **Subscription Management** | Add, update and automatically resolve nodes online |
| **Hotspot Sharing** | Supporting Agent WiFi Hotspots and USB Shared traffic |
| **Hot Toggle Configuration** | Switch Nodes without restart |

---

## Interface Preview

<div align="center">
  <img src="image/Screenshot.jpg" width="60%" alt="Interface Preview" />
</div>

---

## Install

1. From [Releases](https://github.com/Fanju6/NetProxy-Magisk/releases) Download Update ZIP
2. Yes. **Magisk / KernelSU / APatch** Middlebrush Module
3. Restart Device
4. Open module manager WebUI Configure

---

## Contents structure

```
/data/adb/modules/netproxy/
├── bin/                      # Xray Binary File
├── config/
│   ├── xray/
│   │   ├── confdir/          # Xray Core Configuration
│   │   │   ├── routing/      # Route Subtract Configuration
│   │   │   │   ├── internal/ # Internal System Configuration
│   │   │   │   ├── direct.json
│   │   │   │   ├── global.json
│   │   │   │   ├── rule.json
│   │   │   │   └── routing_rules.json
│   │   │   ├── 00_log.json
│   │   │   ├── 01_api.json
│   │   │   ├── 02_dns.json
│   │   │   ├── 03_inbounds.json
│   │   │   ├── 04_outbounds.json
│   │   │   └── 05_policy.json
│   │   └── outbounds/        # Outstation Group Directory
│   │       ├── default/      # Default Node Grouping
│   │       └── sub_xxx/      # Subscribe Group Directory
│   ├── tproxy/
│   │   └── tproxy.conf       # Transparent proxy configuration
│   └── module.conf           # Module settings (start-up, etc.)
├── logs/                     # Run Log
├── scripts/                  # Script Start, Stop, Subscription etc.
├── webroot/                  # WebUI Static resources
└── service.sh                # Module Launch Entry
```

---

## Quick Start

### Mode I: Node Link Import (recommended)

Yes. APPNode Page Click **Import from Clipboard**, directly import node links:

```
vless://... or vmess://... or trojan://... Wait.
```

### Mode II: Subscription Import

Yes. APPNode Page Click **Add Subscription**, enter the subscribe name and address, and automatically resolve all nodes.

### Mode 3: Manual Configuration

 Yes. `outbounds/default` Directory Create JSON , for example:

```json
{
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": { ... }
    }
  ]
}
```



## Exchange Cluster

<p align="center">
  <a href="https://t.me/NetProxy_Magisk">
    <img src="https://img.shields.io/badge/Telegram-Join Group-blue?style=for-the-badge&logo=telegram" alt="Telegram Group" />
  </a>
</p>

---

## Contribution

Welcome to the project!

- Submit Issue Feedback BUG
- Functional recommendations
- Submit Pull Request
- Star Support project!

---

## Acknowledgements

The project was developed with the following excellent open-source projects:

| Item | Annotations |
|------|------|
| [Xray-core](https://github.com/XTLS/Xray-core) | Core proxy engine, support VLESS、XTLS、REALITY Wait for an advanced agreement. |
| [v2rayNG](https://github.com/2dust/v2rayNG) | Node Link Parsing Logic Reference |
| [AndroidTProxyShell](https://github.com/CHIZI-0618/AndroidTProxyShell) | Android TProxy Transparent proxy for reference |
| [KsuWebUIStandalone](https://github.com/KOWX712/KsuWebUIStandalone) | WebUI Independent Operational Programme Reference |
| [Proxylink](https://github.com/Fanju6/Proxylink) | Proxy Link Resolutionr to subscribe to resolution and configure generation |

---

## Licence

[GPL-3.0 License](LICENSE)


## Star

[![Star History Chart](https://api.star-history.com/svg?repos=Fanju6/NetProxy-Magisk&type=date&legend=top-left)](https://www.star-history.com/#Fanju6/NetProxy-Magisk&type=date&legend=top-left)
