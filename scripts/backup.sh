#!/bin/bash
# backup.sh - Backup der Stalwart-Volumes

set -e

# Konfiguration
BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Fehlerbehandlungsfunktion
error() {
    echo -e "${RED}❌ FEHLER: $1${NC}" >&2
    exit 1
}

# Backup-Verzeichnis erstellen (mit Fehlerprüfung)
mkdir -p "$BACKUP_DIR" || error "Konnte Backup-Verzeichnis $BACKUP_DIR nicht erstellen"
echo "💾 Stalwart Backup - $TIMESTAMP"
echo "================================"
echo ""
echo -e "${GREEN}✅ Backup-Verzeichnis: $BACKUP_DIR${NC}"

# Prüfen ob Docker läuft
if ! docker info > /dev/null 2>&1; then
    error "Docker läuft nicht. Bitte Docker starten."
fi

# Prüfen ob die Volumes existieren
if ! docker volume inspect stalwart-etc > /dev/null 2>&1; then
    error "Volume 'stalwart-etc' existiert nicht. Führen Sie zuerst setup.sh aus."
fi

if ! docker volume inspect stalwart-data > /dev/null 2>&1; then
    error "Volume 'stalwart-data' existiert nicht. Führen Sie zuerst setup.sh aus."
fi

# Prüfen ob Container läuft
if docker ps --format '{{.Names}}' | grep -q "^stalwart$"; then
    echo -e "${YELLOW}⚠️  Stalwart-Container läuft. Backup wird live erstellt.${NC}"
    echo "   Für konsistentes Backup sollte Stalwart idealerweise gestoppt sein."
    echo ""
fi

# Backup: stalwart-etc Volume
echo "📦 Sichere Volume: stalwart-etc"
if ! docker run --rm \
    -v stalwart-etc:/source:ro \
    -v "$(pwd)/$BACKUP_DIR:/backup" \
    alpine \
    tar czf "/backup/stalwart-etc_$TIMESTAMP.tar.gz" -C /source .; then
    error "Backup von stalwart-etc fehlgeschlagen"
fi
echo -e "${GREEN}✅ stalwart-etc gesichert${NC}"

# Backup: stalwart-data Volume
echo "📦 Sichere Volume: stalwart-data"
if ! docker run --rm \
    -v stalwart-data:/source:ro \
    -v "$(pwd)/$BACKUP_DIR:/backup" \
    alpine \
    tar czf "/backup/stalwart-data_$TIMESTAMP.tar.gz" -C /source .; then
    error "Backup von stalwart-data fehlgeschlagen"
fi
echo -e "${GREEN}✅ stalwart-data gesichert${NC}"

# Konfigurationsdateien sichern (falls vorhanden)
echo "📦 Sichere Konfigurationsdateien"
if [ -d "./haproxy" ] || [ -f "./docker-compose.yml" ]; then
    if ! tar czf "$BACKUP_DIR/config_$TIMESTAMP.tar.gz" \
        ./docker-compose.yml \
        ./haproxy 2>/dev/null || true \
        ./hosts 2>/dev/null || true; then
        echo -e "${YELLOW}⚠️  Konfigurations-Backup teilweise fehlgeschlagen${NC}"
    else
        echo -e "${GREEN}✅ Konfigurationen gesichert${NC}"
    fi
fi

# Backup-Infos speichern
cat > "$BACKUP_DIR/backup_$TIMESTAMP.txt" << EOF
Backup Zeitpunkt: $TIMESTAMP
Volumes: stalwart-etc, stalwart-data
Enthaltene Konfigurationen: docker-compose.yml, haproxy/, hosts/
EOF

echo ""
echo -e "${GREEN}✅ Backup abgeschlossen!${NC}"
echo ""
echo "📁 Backup-Dateien:"
ls -lh "$BACKUP_DIR"/*"$TIMESTAMP"* 2>/dev/null || echo "   (keine Dateien gefunden)"
echo ""

# Alte Backups löschen
if [ "$RETENTION_DAYS" -gt 0 ]; then
    echo "🗑️  Lösche Backups älter als $RETENTION_DAYS Tage..."
    find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    find "$BACKUP_DIR" -name "backup_*.txt" -type f -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    echo -e "${GREEN}✅ Bereinigung abgeschlossen${NC}"
fi

echo ""
echo "💡 Wiederherstellung:"
echo "   docker run --rm -v stalwart-etc:/target -v $(pwd)/$BACKUP_DIR:/backup alpine tar xzf /backup/stalwart-etc_$TIMESTAMP.tar.gz -C /target"
echo "   docker run --rm -v stalwart-data:/target -v $(pwd)/$BACKUP_DIR:/backup alpine tar xzf /backup/stalwart-data_$TIMESTAMP.tar.gz -C /target"
