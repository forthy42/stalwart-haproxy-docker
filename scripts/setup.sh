#!/bin/bash

#!/bin/bash
# setup.sh - Initial Setup for Stalwart with HAProxy

set -e

echo "🚀 Stalwart Mailserver with HAProxy - Setup"
echo "==========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error handling function
error() { echo -e "${RED}❌ ERROR: $1${NC}" >&2; exit 1; }
warn()  { echo -e "${YELLOW}⚠️  WARNING: $1${NC}" >&2; }
ok()    { echo -e "${GREEN}✅ $1${NC}" >&2; }

# Check if docker runs
docker info > /dev/null 2>&1 || error "Docker doesn't run. Please start docker and retry."
ok "Docker runs"

# Check if docker compose is available
docker compose version > /dev/null 2>&1 || error "Docker Compose not available. Please install"
ok "Docker Compose available"

# Create volumes if available
echo ""
echo "📦 Create Docker Volumes..."
docker volume create stalwart-etc > /dev/null 2>&1 || true
docker volume create stalwart-data > /dev/null 2>&1 || true
ok "Volumes created/already available"

# Check if lighttpd file is available
echo ""
echo "🐳 Setup lighttpd reverse proxy..."
test -f "./lighttpd/9-mail.conf" || error "lighttpd config not available"
systemctl status lighttpd.service > /dev/null 2>&1 || error "lighttpd not running"
cp ./lighttpd/9-mail.conf /etc/lighttpd/conf-available || error "copy failed"
lighty-enable-mod mail || error "failed to enable mail module"
systemctl restart lighttpd.service || error "lighttpd failed to restart"

# Check if config files are available
test -f "./etc/hosts" || error "hosts file not available"
test -f "./etc/haproxy/haproxy.cfg" || error "haproxy.cfg file not available"
test -f "./docker-compose.yml" || error "docker-compose.yml not found!"

echo ""
echo "🐳 Start Container for bootstrap..."
echo "   1. Go to Stalwart Admin-Interface: http://mail.<YOUR-DOMAIN>/admin"
echo "   2. Take the admin password shown here"
echo "   3. Go through the initial setup, until you see a new admin password"
echo "   4. Stop the container with ^C here"
docker run --name stalwart -it \
       -v stalwart-etc:/etc/stalwart \
       -v stalwart-data:/var/lib/stalwart \
       -p 9080:8080 stalwartlabs/stalwart:latest || ok "setup done"

docker rm stalwart || warn "Can't remove temporary container"

echo ""
echo "🐳 Start Container for network configuration..."
echo "   1. Go to Stalwart Admin-Interface: https://mail.<YOUR-DOMAIN>/login"
echo "   2. Take the noted admin password"
echo "   2. Network -> General -> Proxy Trusted Networks 10.0.0.0/8 172.16.0.0/12 fd00::/8"
docker run --name stalwart -it \
       -v stalwart-etc:/etc/stalwart \
       -v stalwart-data:/var/lib/stalwart \
       -p 9080:8080 stalwartlabs/stalwart:latest || ok "config done"
docker rm stalwart || warn "Can't remove temporary container"

# Container starten
echo ""
echo "🐳 Start Container with proxy..."
docker compose up -d

echo ""
ok "Setup completed!"
echo ""
echo "📋 Next Steps:"
echo "   1. Configure Domains and users"
echo "   2. Set DNS entries (SPF, DKIM, DMARC) according to Stalwart's zone file"
echo "   3. Netcup: Delete filter rule for port 25"
echo ""
echo "💡 Pro Tip: If you see '550 5.1.2 Relay not allowed'"
echo "   connect with telnet mail.<YOUR-DOMAIN> 25"
echo "       EHLO example.com"
echo "       MAIL FROM: <account@example.com>"
echo "       RCPT TO: <account@primary-domain>"
echo "       QUIT"
echo "   to load aliases."
