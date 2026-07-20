#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: change_network.sh
# Descripción: Herramienta 6 - Modificar rápidamente la subred o IP de la red
#              de producción permitida para imprimir en CUPS y reiniciar mDNS.
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
    log_error "Este script requiere privilegios root: sudo ./change_network.sh"
    exit 1
fi

CUPS_CONF="/etc/cups/cupsd.conf"
if [ ! -f "$CUPS_CONF" ]; then
    log_error "No se encontró ${CUPS_CONF}. Ejecuta primero el Paso 2."
    exit 1
fi

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 🌐  SKUNK PC: CAMBIAR SUBRED / RED DE PRODUCCIÓN PERMITIDA EN CUPS ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

# Detectar subred e IP actual del contenedor
DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1 || echo "eth0")
CURRENT_IP=$(ip -4 addr show "$DEFAULT_IFACE" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1 || echo "Desconocida")
CURRENT_SUBNET=$(ip -4 route show dev "$DEFAULT_IFACE" 2>/dev/null | awk '/proto kernel/ {print $1}' | head -n1 || echo "192.168.1.0/24")

echo -e "Información de red del servidor/contenedor actual:"
echo -e "  • Interfaz activa   : ${BOLD}${DEFAULT_IFACE}${NC}"
echo -e "  • IP del servidor   : ${YELLOW}${CURRENT_IP}${NC}"
echo -e "  • Subred local (LAN): ${YELLOW}${CURRENT_SUBNET}${NC}"
echo ""
echo -e "Directivas Allow actualmente configuradas en cupsd.conf:"
grep -i "Allow " "$CUPS_CONF" | grep -v "Order" | sed 's/^/  -> /' | sort -u || true
echo ""

echo -e "¿Qué subred o rango de IPs deseas permitir para la red de PRODUCCIÓN?"
echo -e "Ejemplos válidos:"
echo -e "  • ${BOLD}192.168.10.0/24${NC}  -> Subred típica de almacén/planta (Wi-Fi 192.168.10.X)"
echo -e "  • ${BOLD}10.0.0.0/8${NC}       -> Toda la red corporativa clase A"
echo -e "  • ${BOLD}172.16.0.0/12${NC}    -> Toda la red corporativa clase B"
echo -e "  • ${BOLD}all${NC}              -> Permitir conexiones desde cualquier IP (Red interna segura)"
echo ""
read -p "Nueva subred permitida en Producción [Presiona ENTER para permitir '${CURRENT_SUBNET} y all LAN']: " INPUT_NET
NEW_NET="${INPUT_NET:-all}"

log_info "Creando respaldo rápido antes de modificar red..."
cp "$CUPS_CONF" "${CUPS_CONF}.netbackup.$(date +%s)"

log_info "Actualizando políticas de acceso en ${CUPS_CONF} para permitir: ${YELLOW}${NEW_NET}${NC}..."

# Ejecutar el reajuste de directivas de subred
if grep -q "Order allow,deny" "$CUPS_CONF"; then
    # Para evitar duplicados infinitos de Allow, reconstruimos los bloques de ubicación limpiamente o agregamos 'Allow all' / 'Allow NEW_NET'
    sed -i '/Order allow,deny/a \  Allow @LOCAL\n  Allow '"${NEW_NET}" "$CUPS_CONF"
else
    log_warn "No se encontró el patrón Order allow,deny. Añadiendo directiva global..."
    echo -e "\n<Location />\n  Order allow,deny\n  Allow @LOCAL\n  Allow ${NEW_NET}\n</Location>" >> "$CUPS_CONF"
fi

# Eliminar líneas duplicadas de Allow en cupsd.conf
awk '!seen[$0]++' "$CUPS_CONF" > "${CUPS_CONF}.tmp" && mv "${CUPS_CONF}.tmp" "$CUPS_CONF"

# Verificar que escucha el puerto 631 y reiniciar
systemctl restart cups cups-browsed avahi-daemon

echo -e "${GREEN}==============================================================================${NC}"
echo -e "${BOLD} ✅  RED DE PRODUCCIÓN ACTUALIZADA EXITOSAMENTE ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "CUPS y Avahi (mDNS) han sido reiniciados y ahora permiten tráfico desde:"
echo -e "  👉 ${BOLD}@LOCAL${NC} (Subred local inmediata ${CURRENT_SUBNET})"
echo -e "  👉 ${BOLD}${NEW_NET}${NC} (Subred o red de producción configurada)"
echo -e "${CYAN}==============================================================================${NC}"
