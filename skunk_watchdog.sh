#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: skunk_watchdog.sh
# Descripción: Demonio Watchdog para monitorear colas en estado 'stopped' o
#              con errores de papel/USB y rehabilitarlas automáticamente en 30s.
# ==============================================================================

set -u

LOG_FILE="/var/log/skunk-watchdog.log"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Obtener todas las colas de impresión actuales
mapfile -t PRINTERS < <(lpstat -p 2>/dev/null | awk '{print $2}' || true)

if [ ${#PRINTERS[@]} -eq 0 ]; then
    exit 0
fi

for pname in "${PRINTERS[@]}"; do
    STATUS=$(lpstat -p "$pname" -l 2>/dev/null || echo "")
    
    # Si la cola está detenida, deshabilitada o presenta error de filtro/permiso
    if echo "$STATUS" | grep -qiE "stopped|disabled|Permission denied|exited with status|waiting for printer"; then
        log_msg "ALERTA: Cola '$pname' detectada en estado inactivo/pausado. Intentando auto-recuperación..."
        
        # Verificar que los permisos del USB estén correctos (por si se desconectó y reconectó)
        chmod 666 /dev/usb/lp* 2>/dev/null || true
        chmod -R 666 /dev/bus/usb/*/* 2>/dev/null || true
        
        # Desbloquear, aceptar trabajos, activar y asignar política de reintento
        cupsaccept "$pname" 2>/dev/null || true
        cupsenable "$pname" 2>/dev/null || true
        lpadmin -p "$pname" -o printer-error-policy=retry-job -E 2>/dev/null || true
        
        log_msg "ÉXITO: Cola '$pname' reactivada (cupsaccept & cupsenable ejecutados)."
    fi
done

# Verificar también que el servicio avahi-daemon esté activo (a veces en LXC si cae se debe levantar)
if ! systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    log_msg "ALERTA: avahi-daemon inactivo. Reiniciando servicio de descubrimiento mDNS..."
    systemctl restart avahi-daemon 2>/dev/null || true
fi
