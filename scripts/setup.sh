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
test docker info > /dev/null 2>&1 || error "Docker doesn't run. Please start docker and retry."
success "Docker runs"

# Check if docker compose is available
test docker compose version > /dev/null 2>&1 || error "Docker Compose not available. Please install"
success "Docker Compose available"

# Create volumes if available
echo ""
echo "📦 Create Docker Volumes..."
docker volume create stalwart-etc > /dev/null 2>&1 || true
docker volume create stalwart-data > /dev/null 2>&1 || true
success "Volumes created/already available"

# Check if config files are available
test -f "./etc/hosts" || error "hosts file not available"
test -f "./etc/haproxy/haproxy.cfg" || error "haproxy.cfg file not available"
test -f "./docker-compose.yml" ] || error "docker-compose.yml not found!"

# Container starten
echo ""
echo "🐳 Start Container..."
docker compose up -d

echo ""
success "Setup completed!"
echo ""
echo "📋 Next Steps:"
echo "   1. Go to Stalwart Admin-Interface: https://IHRE-DOMAIN:9443/admin"
echo "   2. Enable Proxy Trusted Networks (trusted-networks = 10.42.37.0/24)"
echo "   3. Configure Domains and users"
echo "   4. Set DNS entries (SPF, DKIM, DMARC) according to Stalwart's zone file"
echo "   5. Netcup: Delete filter rule for port 25"
echo ""
echo "💡 Pro Tip: If you see '550 5.1.2 Relay not allowed' connect with telnet to port 25"
echo "   RCPT TO: <account@primary-domain> to load aliases."
