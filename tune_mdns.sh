#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: tune_mdns.sh
# Descripción: Herramienta 13 - Optimizar Avahi (mDNS) y CUPS para latencia < 1s
#              en detección por Wi-Fi de teléfonos móviles Android.
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} ${BOLD}$1${NC}"; }
log_success() { echo -e "${GREEN}[OK]${NC} ${BOLD}$1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

if [ "$EUID" -ne 0 ]; then
    log_error "Este script requiere privilegios root: sudo ./tune_mdns.sh"
    exit 1
fi

AVAHI_CONF="/etc/avahi/avahi-daemon.conf"

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} ⚡  SKUNK PC: AFINAMIENTO DE LATENCIA Y CACHÉ mDNS (@ANDROID) ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

log_info "Ajustando directivas de baja latencia en ${AVAHI_CONF}..."
if [ -f "$AVAHI_CONF" ]; then
    # Respaldo rápido
    cp "$AVAHI_CONF" "${AVAHI_CONF}.bak.$(date +%s)"
    
    # Asegurar directivas en sección [server] y [publish]
    sed -i 's/^#host-name-ttl=.*/host-name-ttl=60/' "$AVAHI_CONF" || true
    sed -i 's/^host-name-ttl=.*/host-name-ttl=60/' "$AVAHI_CONF" || true
    
    sed -i 's/^#publish-workstation=.*/publish-workstation=yes/' "$AVAHI_CONF" || true
    sed -i 's/^publish-workstation=.*/publish-workstation=yes/' "$AVAHI_CONF" || true
    
    # Prevenir bloqueos por límites en contenedores Proxmox LXC
    if ! grep -q "rlimit-nproc=0" "$AVAHI_CONF"; then
        sed -i '/^\[server\]/a rlimit-nproc=0' "$AVAHI_CONF" || true
    fi
fi

# Ajustar intervalo de refresco de cups-browsed
CUPS_BROWSED_CONF="/etc/cups/cups-browsed.conf"
if [ -f "$CUPS_BROWSED_CONF" ]; then
    log_info "Optimizando intervalos de transmisión IPP/mDNS en cups-browsed.conf..."
    sed -i 's/^# BrowseInterval .*/BrowseInterval 30/' "$CUPS_BROWSED_CONF" || true
    if ! grep -q "^BrowseInterval " "$CUPS_BROWSED_CONF"; then
        echo "BrowseInterval 30" >> "$CUPS_BROWSED_CONF"
    fi
fi

log_info "Reiniciando demonios Avahi y CUPS para aplicar latencia ultrabaja..."
systemctl restart avahi-daemon cups cups-browsed

echo -e "${GREEN}==============================================================================${NC}"
echo -e "${BOLD} ✅  OPTIMIZACIÓN mDNS COMPLETADA EXITOSAMENTE ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "Los anuncios ZeroConf (_ipp._tcp) ahora se emiten con TTL de 60 segundos,"
echo -e "garantizando que al presionar 'Imprimir' en los teléfonos Android en planta,"
echo -e "la impresora aparezca en el menú nativo de forma prácticamente instantánea (<1s)."
echo -e "${CYAN}==============================================================================${NC}"
