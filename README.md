# Stalwart Mailserver with HAProxy and Docker

A complete, production-ready Docker configuration for Stalwart Mailserver behind HAProxy with PROXY protocol support. Solves the problems with real client IPs, Docker NAT, and dynamic IP addresses.

## 🎯 The Problem

- Stalwart in a Docker container behind a reverse proxy
- Docker NAT hides real client IPs (SPF shows `softfail` with `172.x.x.x`, fail2ban inside the container will block that single address)
- `network_mode: host` needed for HAProxy (real client IPs), but then Docker DNS is unavailable
- Dynamic Docker IPs (`172.17.x.x`, `172.18.x.x`, ...) can change on every restart
- Stalwart needs `trusted-networks` with stable IP ranges

## ✅ The Solution

- **HAProxy** as TCP proxy with PROXY protocol v2 for SMTP, Submission, IMAP, POP3
- **Fixed IP range** via Docker IPAM (e.g., `10.10.0.0/24`) – no more wandering IPs
- **/etc/hosts mount** in HAProxy container for stable name resolution (bypasses Docker DNS in host mode)
- **Trusted Networks** in Stalwart configured to the fixed IP range

## 📁 Repository Structure

```
.
├── docker-compose.yml
├── haproxy/
│   └── haproxy.cfg
├── hosts/
│   └── hosts
├── scripts/
│   ├── setup.sh
│   └── backup.sh
└── README.md
```

## 🔧 Configuration Files

### docker-compose.yml

```yaml
networks:
  mailnet:
    driver: bridge
    ipam:
      config:
        - subnet: 10.10.0.0/24
          gateway: 10.10.0.1

services:
  haproxy:
    image: haproxy:alpine
    restart: unless-stopped
    network_mode: host                    # For real client IPs
    cap_add:
      - NET_BIND_SERVICE                  # For ports <1024
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
      - ./hosts/hosts:/etc/hosts:ro
    # No networks entry (host mode) - ports are mapped directly

  stalwart:
    image: stalwartlabs/stalwart:latest
    restart: unless-stopped
    container_name: stalwart
    networks:
      mailnet:
        ipv4_address: 10.10.0.2           # Fixed IP
    volumes:
      - stalwart-etc:/etc/stalwart
      - stalwart-data:/var/lib/stalwart
    # No ports - Stalwart is only reachable internally

volumes:
  stalwart-etc:
    external: true
  stalwart-data:
    external: true
```

### haproxy/haproxy.cfg

```haproxy
global
    daemon
    maxconn 4096

defaults
    mode tcp
    # Default timeouts for most services
    timeout connect 5s
    timeout client  30s
    timeout server  30s

# ---------------------------------------------------------------------
# Frontends
# ---------------------------------------------------------------------

frontend smtp_in
    bind :25
    default_backend stalwart_smtp

frontend submission_in
    bind :587
    default_backend stalwart_submission

frontend smtps_in
    bind :465
    default_backend stalwart_submissions

frontend imaps_in
    bind :993
    default_backend stalwart_imap

frontend pop3s_in
    bind :995
    default_backend stalwart_pop3

# ---------------------------------------------------------------------
# Backends with service-specific timeouts
# ---------------------------------------------------------------------

# SMTP (Port 25) - longer timeout for manual testing
backend stalwart_smtp
    timeout client  300s   # 5 minutes for manual telnet sessions
    timeout server  300s
    server stalwart stalwart:10025 send-proxy-v2

# Submission (Port 587) - normal timeout
backend stalwart_submission
    timeout client  60s
    timeout server  60s
    server stalwart stalwart:10587 send-proxy-v2

# SMTPS (Port 465) - normal timeout
backend stalwart_submissions
    timeout client  60s
    timeout server  60s
    server stalwart stalwart:10465 send-proxy-v2

# IMAP (Port 993) - very long timeout for IDLE support
backend stalwart_imap
    timeout client  3600s   # 1 hour for IMAP IDLE
    timeout server  3600s
    server stalwart stalwart:10143 send-proxy-v2

# POP3 (Port 995) - normal timeout
backend stalwart_pop3
    timeout client  60s
    timeout server  60s
    server stalwart stalwart:10110 send-proxy-v2
```

### hosts/hosts

```
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
10.10.0.2       stalwart
```

### Stalwart Configuration (config.toml or Admin UI)

```toml
[server.listener.smtp]
bind = ["0.0.0.0:10025"]

[server.listener.smtp.proxy]
override = true
trusted-networks.0 = "10.10.0.0/24"
protocol = "PROXY"

[server.listener.submission]
bind = ["0.0.0.0:10587"]

[server.listener.submission.proxy]
override = true
trusted-networks.0 = "10.10.0.0/24"
protocol = "PROXY"

[server.listener.submissions]
bind = ["0.0.0.0:10465"]

[server.listener.submissions.proxy]
override = true
trusted-networks.0 = "10.10.0.0/24"
protocol = "PROXY"

[server.listener.imap]
bind = ["0.0.0.0:10143"]

[server.listener.imap.proxy]
override = true
trusted-networks.0 = "10.10.0.0/24"
protocol = "PROXY"

[server.listener.pop3]
bind = ["0.0.0.0:10110"]

[server.listener.pop3.proxy]
override = true
trusted-networks.0 = "10.10.0.0/24"
protocol = "PROXY"
```

## ⏱️ Timeout Configuration Explained

The HAProxy configuration uses service-specific timeouts to accommodate different use cases:

| Service | Port | Timeout | Reason |
|---------|------|---------|--------|
| **SMTP** | 25 | 300s | Manual telnet testing, large email transfers |
| **Submission** | 587 | 60s | Normal email submission |
| **SMTPS** | 465 | 60s | Normal email submission (legacy) |
| **IMAP** | 993 | 3600s | **IMAP IDLE** – keeps connection open for push notifications |
| **POP3** | 995 | 60s | Short connections, fetch and disconnect |

### Why Different Timeouts?

- **IMAP IDLE** allows email clients (Thunderbird, iPhone Mail, Outlook) to receive push notifications without constantly polling. A longer timeout (1 hour or even 24 hours) keeps the connection alive.
- **SMTP on port 25** needs a longer timeout for manual debugging with telnet. Writing a test email manually can take several minutes.
- **POP3 and Submission** are designed for short, transaction-based connections – they don't benefit from long timeouts.

### Adjusting IMAP Timeout for 24/7 IDLE

If you want even longer IMAP IDLE support (e.g., for mobile devices that keep connections open overnight):

```haproxy
backend stalwart_imap
    timeout client  86400s   # 24 hours
    timeout server  86400s
    server stalwart stalwart:10143 send-proxy-v2
```

## 🚀 Installation

```bash
# Create volumes
docker volume create stalwart-etc
docker volume create stalwart-data

# Clone repository
git clone https://github.com/yourname/stalwart-haproxy-docker
cd stalwart-haproxy-docker

# Make scripts executable
chmod +x scripts/*.sh

# Run setup
./scripts/setup.sh

# Or start manually
docker compose up -d

# Stalwart Admin Interface: https://your-domain:9443/admin
# (Add port 9443 to docker-compose.yml if needed)
```

## ⚠️ Known Issues and Solutions

### 1. HAProxy: Permission denied for port 25

**Error:** `cannot bind socket (Permission denied) for [0.0.0.0:25]`

**Solution:** The capability `NET_BIND_SERVICE` is already included in the compose file.

### 2. Stalwart: 550 5.1.2 Relay not allowed

**Problem:** Occurs when using an alias domain instead of the primary domain name. Aliases are only loaded after the primary name is used.

**Solution:** Connect once manually via telnet:

```bash
telnet your-server.com 25
EHLO test.de
MAIL FROM: <test@test.de>
RCPT TO: <primary-domain-name>
QUIT
```

After this, all aliases work – they are loaded by the primary domain query.

### 3. SPF softfail with 172.x.x.x

**Problem:** Docker NAT hides real client IPs

**Solution:** PROXY protocol as configured above – Stalwart will see the real IP.

### 4. Dynamic Docker IPs keep changing

**Problem:** `172.17.x.x`, `172.18.x.x`, etc. change on every restart

**Solution:** Fixed IP range via Docker IPAM (see compose file).

### 5. HAProxy cannot find Stalwart (host mode)

**Problem:** In host mode, Docker DNS (`127.0.0.11`) doesn't work

**Solution:** Mount `/etc/hosts` (see above).

## 🔒 Security Notes

- Internal Stalwart ports (`10025`, `10587`, etc.) are **not** exposed
- Only HAProxy communicates with Stalwart via the isolated network
- PROXY protocol prevents IP spoofing through `trusted-networks`
- No direct incoming connections to Stalwart possible

## 📋 Prerequisites

- Docker & Docker Compose
- Domain with correct DNS records (SPF, DKIM, DMARC)
- **Netcup-specific:** Allow port 25 in server firewall (blocked by default since December 2025)
- Alternative DNS providers: Cloudflare (as resolver), deSEC (as hosting)

## 🔄 Alternative DNS Providers

- **Cloudflare:** Fast DNS propagation, good resolver (`1.1.1.1`)
- **deSEC:** Native Stalwart integration (since v0.16)
- **Netcup:** Manual DNS entries or API via community tools

## 🐛 Troubleshooting

### View logs
```bash
docker compose logs haproxy
docker compose logs stalwart
```

### Test PROXY protocol
```bash
docker logs stalwart | grep -i "remoteIp"
# Should show real client IP, not 172.x.x.x
```

### Test SMTP directly
```bash
telnet your-server.com 25
EHLO test.com
MAIL FROM: <test@test.com>
RCPT TO: <real-user@your-domain.com>
DATA
Subject: Test

Test message
.
QUIT
```

## 📚 Inspiration and Credits

This setup is based on community experience from:
- PROXY protocol with Docker and HAProxy
- Netcup specifics (port 25, DNS API)
- Dynamic IP issues in Docker networks
- Deepseek wrote the README

## 📄 License

MIT

---

The scripts `scripts/setup.sh` and `scripts/backup.sh` are included in the repository. Make them executable with `chmod +x scripts/*.sh` before running.
