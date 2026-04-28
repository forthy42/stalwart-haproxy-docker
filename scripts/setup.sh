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
error() {
    echo -e "${RED}❌ ERROR: $*${NC}" >&2
    exit 1
}
success() {
echo -e "${GREEN}✅ $*${NC}"
}
warn() {
echo -e "${YELLOW}⚠️ $*${NC}"
}

# Check if docker runs
docker info > /dev/null 2>&1 || error "Docker doesn't run. Please start docker and retry."
success "Docker runs"

# Check if docker compose is available
docker compose version > /dev/null 2>&1 || error "Docker Compose not available. Please install"
success "Docker Compose available"

# Create volumes if available
echo ""
echo "📦 Create Docker Volumes..."
docker volume create stalwart-etc > /dev/null 2>&1 || true
docker volume create stalwart-data > /dev/null 2>&1 || true
success "Volumes created/already available"

# Check if lighttpd file is available
echo ""
echo "🐳 Setup lighttpd reverse proxy..."
test -f "./lighttpd/9-mail.conf" || error "lighttpd config not available"
systemctl status lighttpd.service > /dev/null 2>&1 || warn "lighttpd not running"
cp ./lighttpd/9-mail.conf /etc/lighttpd/conf-available || warn "copy failed"
lighty-enable-mod mail || warn "failed to enable mail module"
systemctl restart lighttpd.service || warn "lighttpd failed to restart"

# Check if config files are available
test -f "./etc/hosts" || error "hosts file not available"
test -f "./etc/haproxy/haproxy.cfg" || error "haproxy.cfg file not available"
test -f "./docker-compose.yml" || error "docker-compose.yml not found!"

echo ""
echo "🐳 Start Container for bootstrap..."
echo "   1. Go to Stalwart Admin-Interface: http://mail.<YOUR-DOMAIN>:9080/admin"
echo "   2. Take the admin password shown here"
echo "   3. Go through the initial setup, until you see a new admin password"
echo "   4. Stop the container with ^C here"
docker run --name stalwart -it \
       -v stalwart-etc:/etc/stalwart \
       -v stalwart-data:/var/lib/stalwart \
       -p 9080:8080 -p 9443:443 stalwartlabs/stalwart:latest || success "setup done"

docker rm stalwart || warn "Can't remove temporary container"

echo ""
echo "🐳 Start Container for network configuration..."
echo "   1. Go to Stalwart Admin-Interface: https://mail.<YOUR-DOMAIN>:9443/login"
echo "   2. Take the noted admin password"
echo "   2. Network -> General -> Proxy Trusted Networks 10.0.0.0/8 172.16.0.0/12 fd00::/8"
docker run --name stalwart -it \
       -v stalwart-etc:/etc/stalwart \
       -v stalwart-data:/var/lib/stalwart \
       -p 9080:8080 -p 9443:443 stalwartlabs/stalwart:latest || success "config done"
docker rm stalwart || warn "Can't remove temporary container"

# Container starten
echo ""
echo "🐳 Start Container..."
docker compose up -d

echo ""
success "Setup completed!"
echo ""
echo "📋 Next Steps:"
echo "   1. Configure Domains and users"
echo "   2. Set DNS entries (SPF, DKIM, DMARC) according to Stalwart's zone file"
echo "   3. Netcup: Delete filter rule for port 25"
echo ""
echo "💡 Pro Tip: If you see '550 5.1.2 Relay not allowed' connect with telnet to port 25"
echo "   RCPT TO: <account@primary-domain> to load aliases."
