# Common problems

## Installation issues

### Q: Module not effective after installation

**A:** Ensure that:
1. Finished restart
2. Yes. Magisk/KernelSU Module page confirmation module enabled
3. Check module log:`/data/adb/modules/netproxy/logs/`

### Q: WebUI Unable to open

**A:** Possible causes:
1. Module not installed correctly, repainted
2. WebUI File Missing, Check `/data/adb/modules/netproxy/webroot/` Contents

---

## Use

### Q: Proxy startup failed

**A:** Common causes:
1. **Node added**: Add proxy node first
2. **Configure Error**: Check if node configuration is correct
3. **Port Conflict**: Other VPN or proxy application mouth

View details error:
```bash
cat /data/adb/modules/netproxy/logs/xray.log
```

### Q: Partial application cannot be connected

**A:** Possible causes:
1. Check to apply sub-agent settings and whether the blacklist application is wrong
2. Check the routing rules.

### Q: DNS Parsing failed

**A:** Try:
1. Ensure DNS Configure correctly
2. Inspection DNS Server availability
3. Clear System DNS Cache

---

## Performance issues

### Q: Network speed slow

**A:** Recommendations:
1. Switch to Lower Delay Node
2. Use WebUI Section for delayed testing Points

---

## Other issues

### Q: How to View Logs

**A:** Log in `/data/adb/modules/netproxy/logs/` Contents
- `service.log` - Service Stop Log
- `xray.log` - Xray Core Log
- `subscription.log` - Subscription to Update Log

### Q: How to fully unmount

**A:** 
1. Stop proxy services
2. Yes. Magisk/KernelSU Remove Module
3. Restart Device
4. (Optional) Delete residual data:`rm -rf /data/adb/modules/netproxy`
