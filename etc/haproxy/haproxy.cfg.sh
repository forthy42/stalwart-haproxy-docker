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
# Hilfsfunktionen
error() { echo -e "${RED}❌ ERROR: $1${NC}" >&2; exit 1; }
warn()  { echo -e "${YELLOW}⚠️  WARNING: $1${NC}" >&2; }
ok()    { echo -e "${GREEN}✅ $1${NC}" >&2; }

# function to sanitize/trim vars
trim_vars() {
    local vars=("$@")
    for var in "${vars[@]}"; do
        # trim variable
        local trimmed=$(echo "${!var}" | xargs)
        declare -g $var="$trimmed"
    done
}

TEMP_FILES=""

cleanup() {
    rv=$?
    for i in $TEMP_FILES
    do
	rm -f "$i" || warn "couldn't remove file $i"
    done
    exit $rv
}

# Check if input file exists
test -f "$INPUT_CSV" || error "$INPUT_CSV not found"

# temporare file for output
TEMP_FILE=$(mktemp)
ok "output temporarily to $TEMP_FILE"
TEMP_FILES="$TEMP_FILES $TEMP_FILE"
trap "cleanup" EXIT INT TERM HUP

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

EOF

FIELDS=fields
FIRSTRUN=.true.

echo "📋 Containing services:"
# parse table line (skip header)
while IFS=',' read -r $FIELDS; do
    if [ $FIRSTRUN ]
    then
	FIELDS=${fields//,/ }
	FIRSTRUN=""
	ok "Fields: $FIELDS"
    else
	trim_vars $FIELDS

	# only handle valid lines, name empty, starts with '#',
	# or no inc_port is invalid
	[[ "$name" =~ ^#|^$ || "$inc_port" == "" ]] && continue
	ok "Service $name"
	# generate frontend and backend, all in one single heredoc
	cat << EOF
frontend ${name}_in
    default_backend stalwart_${name}
$(if [ -n "${ipv4_bind}" ]; then
            if [ "${ipv4_bind}" = "*" ]; then
		echo "    bind :${inc_port}"
            else
		echo "    bind ${ipv4_bind}:${inc_port}"
            fi
	fi
	if [ -n "${ipv6_bind}" ]; then
            if [ "${ipv6_bind}" = "::" ]; then
		echo "    bind :::${inc_port}"
            else
		echo "    bind [${ipv6_bind}]:${inc_port}"
            fi
	fi)
$(test -n "${client_to}" && echo "    timeout client ${client_to}")

backend stalwart_${name}
    server stalwart stalwart-mail:${fwd_port} send-proxy-v2
$(test -n "${server_to}" && echo "    timeout server ${server_to}")

EOF
    fi
done < "$INPUT_CSV" >> "$TEMP_FILE"

# create output directory, if needed
test ! -z "$(dirname "$OUTPUT_CFG")" && mkdir -p "$(dirname "$OUTPUT_CFG")"

# copy generated config file
cp "$TEMP_FILE" "$OUTPUT_CFG" || error "Can't copy generated file to $OUTPUT_CFG"

ok "generated HAProxy-Config: $OUTPUT_CFG"
