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

# Unbind usbfs driver locks on USB ports so CUPS libusb can open endpoints cleanly
for path in /sys/bus/usb/drivers/usbfs/1-*; do
    if [ -e "$path" ]; then
        dev_name="${path##*/}"
        echo "$dev_name" > /sys/bus/usb/drivers/usbfs/unbind 2>/dev/null || true
    fi
done

chmod -R 666 /dev/bus/usb/*/* 2>/dev/null || true

# Obtener todas las colas de impresión actuales
mapfile -t PRINTERS < <(lpstat -p 2>/dev/null | awk '{print $2}' || true)

if [ ${#PRINTERS[@]} -eq 0 ]; then
    exit 0
fi

for pname in "${PRINTERS[@]}"; do
    STATUS=$(lpstat -p "$pname" -l 2>/dev/null || echo "")
    
    # Si la cola está detenida, deshabilitada, esperando puerto o presenta errores
    if echo "$STATUS" | grep -qiE "stopped|disabled|Permission denied|exited with status|waiting for printer"; then
        log_msg "ALERTA: Cola '$pname' detectada en estado inactivo/pausado/espera. Intentando auto-recuperación..."
        
        # Verificar que los permisos del USB estén correctos
        chmod 666 /dev/usb/lp* 2>/dev/null || true
        chmod -R 666 /dev/bus/usb/*/* 2>/dev/null || true
        
        # Si un trabajo lleva atascado más de 30s en espera de puerto, cancelarlo para no bloquear impresiones futuras
        if echo "$STATUS" | grep -qiE "waiting for printer|esperando a que la impresora"; then
            log_msg "ALERTA: Limpiando trabajo bloqueado en cola '$pname'..."
            cancel -a "$pname" 2>/dev/null || true
        fi
        
        # Desbloquear, aceptar trabajos, activar y asignar política de reintento
        cupsaccept "$pname" 2>/dev/null || true
        cupsenable "$pname" 2>/dev/null || true
        lpadmin -p "$pname" -o printer-error-policy=retry-job -o usb-unidirectional-default=true -E 2>/dev/null || true
        
        log_msg "ÉXITO: Cola '$pname' reactivada."
    fi
done

# Verificar también que el servicio avahi-daemon esté activo
if ! systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    log_msg "ALERTA: avahi-daemon inactivo. Reiniciando servicio de descubrimiento mDNS..."
    systemctl restart avahi-daemon 2>/dev/null || true
fi
