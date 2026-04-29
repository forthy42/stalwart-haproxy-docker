# Makefile for haproxy.cfg

.PHONY: generate-config clean validate

# Variablen
HAPROXY = etc/haproxy
CSV_FILE = $(HAPROXY)/services.csv
HAPROXY_CFG = $(HAPROXY)/haproxy.cfg
HAPROXY_SH = $(HAPROXY)/haproxy.cfg.sh
HOSTS = etc/hosts

# Konfiguration generieren
all: validate

$(HAPROXY_CFG): $(CSV_FILE) $(HAPROXY_SH)
	@echo "🔧 Generiere HAProxy-Konfiguration..."
	@./$(HAPROXY_SH) $(CSV_FILE) $(HAPROXY_CFG)

# HAProxy-Config validieren (erfordert laufenden Docker)
validate: $(HAPROXY_CFG)
	@echo "🔍 Validiere HAProxy-Konfiguration..."
	@docker run --rm -v ./$(HAPROXY_CFG):/usr/local/etc/haproxy/haproxy.cfg haproxy:alpine -v ./$(HOSTS):/etc/hosts haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Aufräumen
clean:
	@rm -f $(HAPROXY_CFG)
	@echo "🗑️  Entfernt: $(HAPROXY_CFG)"

# Hilfe
help:
	@echo "Verfügbare Kommandos:"
	@echo "  make generate-config  - Generiert haproxy.cfg aus services.csv"
	@echo "  make validate         - Generiert und validiert die Konfiguration"
	@echo "  make clean           - Löscht die generierte haproxy.cfg"
