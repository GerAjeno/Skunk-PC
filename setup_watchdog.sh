#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: setup_watchdog.sh
# Descripción: Instala y activa el demonio y temporizador Systemd para ejecutar
#              skunk_watchdog.sh en segundo plano cada 30 segundos.
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
    log_error "Este script requiere privilegios root: sudo ./setup_watchdog.sh"
    exit 1
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHDOG_SCRIPT="${BASE_DIR}/skunk_watchdog.sh"

if [ ! -f "$WATCHDOG_SCRIPT" ]; then
    log_error "No se encontró ${WATCHDOG_SCRIPT}."
    exit 1
fi

chmod +x "$WATCHDOG_SCRIPT"

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 🛡️  SKUNK PC: INSTALANDO DEMONIO WATCHDOG DE AUTO-RECUPERACIÓN ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

log_info "Creando archivo de servicio /etc/systemd/system/skunk-watchdog.service..."
cat << EOF > /etc/systemd/system/skunk-watchdog.service
[Unit]
Description=Skunk PC - Auto-Healing Watchdog for CUPS Printers and Avahi
After=cups.service avahi-daemon.service

[Service]
Type=oneshot
ExecStart=${WATCHDOG_SCRIPT}
User=root

[Install]
WantedBy=multi-user.target
EOF

log_info "Creando temporizador /etc/systemd/system/skunk-watchdog.timer (30s)..."
cat << 'EOF' > /etc/systemd/system/skunk-watchdog.timer
[Unit]
Description=Run Skunk PC Watchdog every 30 seconds

[Timer]
OnBootSec=15sec
OnUnitActiveSec=30sec
AccuracySec=1sec

[Install]
WantedBy=timers.target
EOF

log_info "Recargando systemd daemon e inicializando temporizador..."
systemctl daemon-reload
systemctl enable --now skunk-watchdog.timer || true
systemctl start skunk-watchdog.service || true

echo -e "${GREEN}==============================================================================${NC}"
echo -e "${BOLD} ✅  WATCHDOG DE AUTO-RECUPERACIÓN ACTIVADO EXITOSAMENTE ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "El sistema revisará automáticamente cada 30 segundos el estado de tus colas"
echo -e "y desatascará cualquier impresora detenida por papel o desconexión temporal."
echo -e "Puedes consultar el log en vivo con: ${YELLOW}tail -f /var/log/skunk-watchdog.log${NC}"
echo -e "${CYAN}==============================================================================${NC}"
