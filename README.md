## Table of Contents
- [Server Setup Essentials](#Server-Setup-Essentials)
- [CF DDNS Manager](#CF-DDNS-Manager)

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
bash <(wget -qO- https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/refs/heads/main/server-setup-essentials.sh | sed 's/\r$//')
```
```
bash <(curl -fsSL https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/server-setup-essentials.sh | sed 's/\r$//')
```
```
if ! command -v curl >/dev/null 2>&1; then apt update -y && apt install -y curl; fi && bash <(curl -fsSL https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/server-setup-essentials.sh | sed 's/\r$//')
```

---

# CF DDNS Manager

A simple tool to manage CF DNS for server with NAT based servers (auto changing ips):

- ✅ Add/Edit/Delete CF Records
- ✅ Auto Update server public ip to selected sub-domain
- ✅ Add cron job for auto updating

## RUN
```
bash <(wget -qO- https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/refs/heads/main/cf-ddns-manager.sh | sed 's/\r$//')
```
```
bash <(curl -fsSL https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/cf-ddns-manager.sh | sed 's/\r$//')
```
```
if ! command -v curl >/dev/null 2>&1; then apt update -y && apt install -y curl; fi && bash <(curl -fsSL https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/cf-ddns-manager.sh | sed 's/\r$//')
```

---


