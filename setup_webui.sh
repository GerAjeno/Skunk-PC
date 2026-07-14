#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: setup_webui.sh
# Descripción: Herramienta 14 - Instala dependencias Flask e inicializa el
#              portal Web UI de gestión de Skunk PC en el puerto 8080.
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
    log_error "Este script requiere privilegios root: sudo ./setup_webui.sh"
    exit 1
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBUI_SCRIPT="${BASE_DIR}/skunk_webui.py"

if [ ! -f "$WEBUI_SCRIPT" ]; then
    log_error "No se encontró ${WEBUI_SCRIPT}."
    exit 1
fi

chmod +x "$WEBUI_SCRIPT"

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 🌐  SKUNK PC: INSTALANDO INTERFAZ WEB DE GESTIÓN (PUERTO 8080) ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

log_info "Verificando e instalando dependencias Python 3 Flask..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq python3 python3-flask python3-psutil 2>/dev/null || {
    log_warn "Fallo en apt-get quiet, ejecutando instalación estándar..."
    apt-get install -y python3 python3-flask
}

log_info "Creando servicio systemd /etc/systemd/system/skunk-webui.service..."
cat << EOF > /etc/systemd/system/skunk-webui.service
[Unit]
Description=Skunk PC - Enterprise Web UI Dashboard (Flask Port 8080)
After=network.target cups.service avahi-daemon.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${WEBUI_SCRIPT}
WorkingDirectory=${BASE_DIR}
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

log_info "Recargando systemd e iniciando skunk-webui.service en puerto 8080..."
systemctl daemon-reload
systemctl enable --now skunk-webui.service

# Obtener IP local para mostrar la URL
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "IP_SERVIDOR")

echo -e "${GREEN}==============================================================================${NC}"
echo -e "${BOLD} 🚀  INTERFAZ WEB DE GESTIÓN ACTIVADA EXITOSAMENTE ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "Desde cualquier teléfono Android, tablet o PC en la planta, ingresa al navegador:"
echo -e "  👉 ${BOLD}${CYAN}http://${LOCAL_IP}:8080${NC}"
echo -e "Desde allí podrás autodetectar impresoras, añadir colas de red, ejecutar pruebas"
echo -e "en EPL2/ZPL, desatascar colas y descargar respaldos visualmente sin usar SSH."
echo -e "${CYAN}==============================================================================${NC}"
