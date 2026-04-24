# Xray Configure

NetProxy Use Xray-core As a proxy core, the configuration document is modularized.

## Configure Directory

```
/data/adb/modules/netproxy/config/xray/
├── confdir/               # Modular configuration (calculated)
│   ├── 00_log.json        # Log Configuration
│   ├── 01_inbounds.json   # Entry Configuration
│   ├── 02_dns.json        # DNS Configure
│   ├── 03_routing.json    # Route Configuration
│   ├── 04_policy.json     # Policy Configuration
│   ├── 05_api.json        # API Configure
│   └── 06_outbounds.json  # Outstation Configuration
└── outbounds/             # Node Configuration Directory
    ├── default.json       # Default Node
    └── sub_Subscriptions/        # Subscription Node Directory
        ├── _meta.json     # Can not open message
        └── Nodes.json
```

## Configure Load

Xray Load in file order on startup `confdir/` All of it. JSON File and merge.

---

## Core Configuration Description

### DNS Configure (02_dns.json)

```json
{
    "dns": {
        "hosts": {
            "dns.alidns.com": ["223.5.5.5", "223.6.6.6"],
            "cloudflare-dns.com": ["104.16.249.249", "104.16.248.249"]
        },
        "servers": [
            {
                "address": "https://dns.alidns.com/dns-query",
                "domains": ["geosite:cn"],
                "skipFallback": true
            },
            {
                "address": "https://cloudflare-dns.com/dns-query",
                "domains": ["geosite:google"],
                "skipFallback": true
            },
            "https://cloudflare-dns.com/dns-query"
        ]
    }
}
```

**Annotations**：
- `hosts`: Static DNS Map, avoid DNS Pollution
- `servers`: DNS Server list, split by domain name

### Entry Configuration (01_inbounds.json)

Definitions TProxy Listen port and DNS Enter.

### Route Configuration (03_routing.json)

By `routing_rules.json` Automatically generated, recommended WebUI Management.

---

## Custom Configuration

If you need to add a custom configuration:

1. Yes. `confdir/` Create new JSON Documentation
2. Use number prefix to control loading order (e. g. `07_custom.json`）
3. Restart Service Valid

::: warning Attention.
`01_inbounds.json` and `06_outbounds.json` is automatically managed by the module and does not recommend manual changes.
:::
