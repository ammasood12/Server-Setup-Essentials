## Table of Contents
- [Server Setup Essentials](#Server-Setup-Essentials)
- [CF DDNS Manager](#CF-DDNS-Manager)
- [aaPanel Migration Tool](#aaPanel-Migration-Tool)

# Server Setup Essentials

An interactive Bash toolkit to quickly prepare a fresh Linux server (Debian/Ubuntu, CentOS with basic functionality), with:

- ✅ System Overview on the Dashboard
- ✅ Swap Management (auto/set/increase/decrease)
- ✅ Interactive Timezone Selection
- ✅ Multi-select Software Installer
- ✅ Network and Logs Optimization
- ✅ Benchmark Tools
- ✅ One-click Default Setup (swap + base tools + timezone)

Perfect for new VPS / nodes running things like sing-box, XrayR, V2bX, etc.

## RUN
```
bash <(wget -qO- "https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/server-setup-essentials.sh?$(date +%s)" | sed 's/\r$//')
```
```
bash <(curl -fsSL https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/server-setup-essentials.sh?$(date +%s) | sed 's/\r$//')
```
```
if ! command -v curl >/dev/null 2>&1; then apt update -y && apt install -y curl; fi && bash <(curl -fsSL https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/server-setup-essentials.sh?$(date +%s) | sed 's/\r$//')
```

---

# CF DDNS Manager

A simple tool to manage CF DNS for server with NAT based servers (auto changing ips):

- ✅ Add/Edit/Delete CF Records
- ✅ Auto Update server public ip to selected sub-domain
- ✅ Add cron job for auto updating

## RUN
```
bash <(wget -qO- "https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/cf-ddns-manager.sh?$(date +%s)" | sed 's/\r$//')

```
```
bash <(curl -fsSL https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/cf-ddns-manager.sh?$(date +%s) | sed 's/\r$//')
```
```
if ! command -v curl >/dev/null 2>&1; then apt update -y && apt install -y curl; fi && bash <(curl -fsSL https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/cf-ddns-manager.sh?$(date +%s) | sed 's/\r$//')
```

---

# aaPanel Migration Tool
# HIGHLY RISKY (USE ON YOUR RESPONSIBILITY)

A simple tool to migrate aaPanel:

Requirement: Clean OS with same version

### Backup Process
- ✅ Backup aaPanel+PHP+Nginx+Database
- ✅ Meta data for PHP extensions and other software (not all) installed on aaPanel
### Restore Process (on Clean serveer)
- ✅ Direct Download from old server and verify
- ✅ install aaPanel
- ✅ Restore PHP+Nginx+Database
- ✅ install PHP extensions based on available Meta Data

## RUN
```
bash <(wget -qO- "https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/aapanel_migrate.sh?$(date +%s)" | sed 's/\r$//')
```
```
bash <(curl -fsSL https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/aapanel_migrate.sh?$(date +%s) | sed 's/\r$//')
```
```
if ! command -v curl >/dev/null 2>&1; then apt update -y && apt install -y curl; fi && bash <(curl -fsSL https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/aapanel_migrate.sh?$(date +%s) | sed 's/\r$//')
```

---

