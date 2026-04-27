# Stalwart Mailserver mit HAProxy und Docker

Eine vollständige, produktionsreife Docker-Konfiguration für Stalwart Mailserver hinter HAProxy mit PROXY-Protokoll-Unterstützung. Löst die Probleme mit echten Client-IPs, Docker-NAT und dynamischen IP-Adressen.

## 🎯 Das Problem

- Stalwart im Docker-Container hinter einem Reverse Proxy
- Docker-NAT verschleiert die echten Client-IPs (SPF wird zu `softfail` mit `172.x.x.x`)
- `network_mode: host` für HAProxy nötig (echte Client-IPs), aber dann fehlt der Docker-DNS
- Dynamische Docker-IPs (`172.17.x.x`, `172.18.x.x`, ...) wandern bei jedem Restart
- Stalwart benötigt `trusted-networks` mit stabilen IP-Bereichen

## ✅ Die Lösung

- **HAProxy** als TCP-Proxy mit PROXY-Protokoll v2 für SMTP, Submission, IMAP, POP3
- **Fester IP-Bereich** via Docker IPAM (z.B. `10.10.0.0/24`) – keine wandernden IPs mehr
- **/etc/hosts Mount** im HAProxy-Container für stabile Namensauflösung (umgeht Docker-DNS im Host-Modus)
- **Trusted Networks** in Stalwart auf den festen IP-Bereich konfiguriert

## 📁 Repository-Struktur

```
.
├── docker-compose.yml
├── haproxy/
│   └── haproxy.cfg
├── hosts/
│   └── hosts
└── README.md
```

## 🔧 Konfigurationen

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
    network_mode: host                    # Für echte Client-IPs
    cap_add:
      - NET_BIND_SERVICE                  # Für Ports <1024
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
      - ./hosts/hosts:/etc/hosts:ro
    # Kein networks-Eintrag (host-Modus) - Ports werden direkt gemappt

  stalwart:
    image: stalwartlabs/stalwart:latest
    restart: unless-stopped
    container_name: stalwart
    networks:
      mailnet:
        ipv4_address: 10.10.0.2           # Feste IP
    volumes:
      - stalwart-etc:/etc/stalwart
      - stalwart-data:/var/lib/stalwart
    # Keine ports: - Stalwart ist nur intern erreichbar

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
    timeout connect 5s
    timeout client  60s
    timeout server  60s

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

backend stalwart_smtp
    server stalwart stalwart:10025 send-proxy-v2

backend stalwart_submission
    server stalwart stalwart:10587 send-proxy-v2

backend stalwart_submissions
    server stalwart stalwart:10465 send-proxy-v2

backend stalwart_imap
    server stalwart stalwart:10143 send-proxy-v2

backend stalwart_pop3
    server stalwart stalwart:10110 send-proxy-v2
```

### hosts/hosts

```
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
10.10.0.2       stalwart
```

### Stalwart-Konfiguration (config.toml oder Admin-UI)

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

## 🚀 Installation

```bash
# Volumes erstellen
docker volume create stalwart-etc
docker volume create stalwart-data

# Repository klonen
git clone https://github.com/yourname/stalwart-haproxy-docker
cd stalwart-haproxy-docker

# Container starten
docker compose up -d

# Stalwart Admin-Interface: https://your-domain:9443/admin
# (Port 9443 muss entsprechend in der Compose ergänzt werden, falls gewünscht)
```

## ⚠️ Bekannte Probleme und Lösungen

### 1. HAProxy: Permission denied für Port 25

**Fehler:** `cannot bind socket (Permission denied) for [0.0.0.0:25]`

**Lösung:** Die Capability `NET_BIND_SERVICE` im Compose-File ergänzen (bereits enthalten).

### 2. Stalwart: 550 5.1.2 Relay not allowed

**Problem:** Tritt auf, wenn man nicht den primären Domainnamen verwendet, sondern ein Alias. Die Aliase werden erst geladen, wenn der primäre Name genutzt wird.

**Lösung:** Einmalig manuell mit telnet verbinden:

```bash
telnet your-server.com 25
EHLO test.de
MAIL FROM: <test@test.de>
RCPT TO: <primary-domain-name>
QUIT
```

Danach funktionieren alle Aliase – sie werden durch die primäre Domain-Abfrage geladen.

### 3. SPF softfail mit 172.x.x.x

**Problem:** Docker-NAT verschleiert die echte Client-IP

**Lösung:** PROXY-Protokoll wie oben konfiguriert – dann sieht Stalwart die echte IP.

### 4. Dynamische Docker-IPs wandern

**Problem:** `172.17.x.x`, `172.18.x.x` usw. ändern sich bei Restarts

**Lösung:** Fester IP-Bereich über Docker IPAM (siehe Compose-File).

### 5. HAProxy findet Stalwart nicht (Host-Modus)

**Problem:** Im Host-Modus funktioniert der Docker-DNS (`127.0.0.11`) nicht

**Lösung:** `/etc/hosts` mounten (siehe oben).

## 🔒 Sicherheitshinweise

- Interne Ports von Stalwart (10025, 10587, etc.) sind **nicht** exponiert
- Nur HAProxy kommuniziert mit Stalwart über das isolierte Netzwerk
- PROXY-Protokoll verhindert IP-Spoofing durch `trusted-networks`
- Keine direkten eingehenden Verbindungen zu Stalwart möglich

## 📋 Voraussetzungen

- Docker & Docker Compose
- Domain mit korrekten DNS-Einträgen (SPF, DKIM, DMARC)
- **Netcup-spezifisch:** Port 25 in der Server-Firewall freigeben (seit Dezember 2025 standardmäßig blockiert)
- Alternative DNS-Provider: Cloudflare (als Resolver), deSEC (als Hosting)

## 🔄 Alternative DNS-Provider

- **Cloudflare:** Schnelle DNS-Propagation, guter Resolver (`1.1.1.1`)
- **deSEC:** Native Stalwart-Integration (ab v0.16)
- **Netcup:** Manuelle DNS-Einträge oder API via Community-Tools

## 🐛 Fehlersuche

### Logs anzeigen
```bash
docker compose logs haproxy
docker compose logs stalwart
```

### PROXY-Protokoll testen
```bash
docker logs stalwart | grep -i "remoteIp"
# Sollte echte Client-IP zeigen, nicht 172.x.x.x
```

### SMTP direkt testen
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

## 📚 Inspiration und Danksagung

Dieses Setup basiert auf den Erfahrungen aus der Stalwart-Community, insbesondere den Diskussionen zu:
- PROXY-Protokoll mit Docker und HAProxy
- Netcup-spezifischen Eigenheiten (Port 25, DNS-API)
- Dynamischen IP-Problemen in Docker-Netzwerken

## 📄 Lizenz

MIT
