#!/bin/bash
# haproxy.cfg.sh - Generates haproxy.cfg from CSV table

set -e

INPUT_CSV="${1:-services.csv}"
OUTPUT_CFG="${2:-haproxy/haproxy.cfg}"

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

# Prüfen ob Eingabedatei existiert
test -f "$INPUT_CSV" || error "$INPUT_CSV not found"

# temporare file for output
TEMP_FILE=$(mktemp)

# Header of haproxy.cfg (static part)
cat > "$TEMP_FILE" << 'EOF'
# HAProxy configuration for Stalwart
# Generated from services.csv - Make changes there!

global
    daemon
    maxconn 4096
    user haproxy
    group haproxy

defaults
    mode tcp
    timeout connect 5s

# ---------------------------------------------------------------------
# FRONTENDS (Client side timeouts)
# ---------------------------------------------------------------------

EOF

# parse table line (skip header)
tail -n +2 "$INPUT_CSV" | while IFS=',' read -r name inc_port fwd_port client_to server_to ipv4_bind ipv6_bind protocol; do
    # remove whitespace and quotes
    name=$(echo "$name" | xargs)
    inc_port=$(echo "$inc_port" | xargs)
    fwd_port=$(echo "$fwd_port" | xargs)
    client_to=$(echo "$client_to" | xargs)
    server_to=$(echo "$server_to" | xargs)
    ipv4_bind=$(echo "$ipv4_bind" | xargs)
    ipv6_bind=$(echo "$ipv6_bind" | xargs)
    protocol=$(echo "$protocol" | xargs)
    
    # only handle valid lines
    if [ -z "$name" ] || [ -z "$inc_port" ]; then
        continue
    fi
    
    # generate frontend
    cat >> "$TEMP_FILE" << EOF
frontend ${name}_in
EOF
    
    # IPv4 bind (if not empty)
    if [ -n "$ipv4_bind" ]; then
        if [ "$ipv4_bind" = "*" ]; then
            echo "    bind :${inc_port}" >> "$TEMP_FILE"
        else
            echo "    bind ${ipv4_bind}:${inc_port}" >> "$TEMP_FILE"
        fi
    fi
    
    # IPv6 bind (if not empty)
    if [ -n "$ipv6_bind" ]; then
        if [ "$ipv6_bind" = "::" ]; then
            echo "    bind :::${inc_port}" >> "$TEMP_FILE"
        else
            echo "    bind [${ipv6_bind}]:${inc_port}" >> "$TEMP_FILE"
        fi
    fi
    
    cat >> "$TEMP_FILE" << EOF
    timeout client ${client_to}
    default_backend stalwart_${name}

EOF
done

# Backend-Sektion Header
cat >> "$TEMP_FILE" << 'EOF'
# ---------------------------------------------------------------------
# BACKENDS (server side timeout)
# ---------------------------------------------------------------------

EOF

# generate backends (go again through the table)
tail -n +2 "$INPUT_CSV" | while IFS=',' read -r name inc_port fwd_port client_to server_to ipv4_bind ipv6_bind protocol; do
    name=$(echo "$name" | xargs)
    fwd_port=$(echo "$fwd_port" | xargs)
    server_to=$(echo "$server_to" | xargs)
    
    if [ -z "$name" ] || [ -z "$fwd_port" ]; then
        continue
    fi
    
    cat >> "$TEMP_FILE" << EOF
backend stalwart_${name}
    timeout server ${server_to}
    server stalwart stalwart-mail:${fwd_port} send-proxy-v2
EOF
    
    echo "" >> "$TEMP_FILE"
done

# create output directory, if needed
test ! -z "$(dirname "$OUTPUT_CFG")" && mkdir -p "$(dirname "$OUTPUT_CFG")"

# copy generated config file
cp "$TEMP_FILE" "$OUTPUT_CFG" || error "Can't copy generated file to $OUTPUT_CFG"
rm "$TEMP_FILE" || warn "Can't remove $TEMP_FILE"

success "generated HAProxy-Config: $OUTPUT_CFG"
echo "📋 Containing services:"
tail -n +2 "$INPUT_CSV" | cut -d',' -f1 | grep -v '^$' | sed 's/^/   - /'
