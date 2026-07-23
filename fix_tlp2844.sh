#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: fix_tlp2844.sh
# Descripción: Diagnóstico y reparación profunda de hardware y permisos para
#              Zebra TLP2844 (0a5f:000a) en Proxmox LXC. Pruebas directas EPL/ZPL.
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
    log_error "Este script requiere privilegios root: sudo ./fix_tlp2844.sh"
    exit 1
fi

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 🔧  SKUNK PC: DIAGNÓSTICO PROFUNDO Y PRUEBA HARDWARE TLP2844 ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

# 1. Verificar nodo de dispositivo USB (/dev/usb/lp0 o /dev/bus/usb/...)
log_info "Verificando nodos físicos de dispositivo en el sistema de archivos del contenedor..."
USB_LP=$(ls -1 /dev/usb/lp* 2>/dev/null | head -n1 || echo "")

if [ -z "$USB_LP" ]; then
    log_warn "No se detectó /dev/usb/lp0. Buscando en /dev/bus/usb/..."
    lsusb | grep -iE "0a5f|Zebra" || {
        log_error "La impresora Zebra no aparece en lsusb. ¿Se reinició el contenedor tras editar el .conf de Proxmox?"
        exit 1
    }
    log_info "Intentando cargar el módulo del kernel usbprinter / usblp en Proxmox..."
    modprobe usblp 2>/dev/null || true
    USB_LP=$(ls -1 /dev/usb/lp* 2>/dev/null | head -n1 || echo "")
fi

if [ -n "$USB_LP" ]; then
    log_success "Puerto paralelo USB físico detectado: ${YELLOW}${USB_LP}${NC}"
    ls -l "$USB_LP"
else
    log_warn "No existe /dev/usb/lp0 (es normal si CUPS usa libusb directo desde /dev/bus/usb/)."
fi
echo ""

# 2. Arreglar permisos de usuarios CUPS y LP en el kernel
log_info "Asegurando permisos globales para el usuario 'cups' en dispositivos USB..."
getent group lp >/dev/null && usermod -aG lp cups 2>/dev/null || true
getent group plugdev >/dev/null && usermod -aG plugdev cups 2>/dev/null || true
chmod 666 /dev/usb/lp* 2>/dev/null || true
chmod -R 666 /dev/bus/usb/*/* 2>/dev/null || true
log_success "Permisos de lectura/escritura asignados a CUPS sobre el bus USB."
echo ""

# 3. Pruebas Directas por Cable (Sin pasar por CUPS)
# La clásica TLP2844 opera de forma nativa con el lenguaje EPL2 (y a veces ignora ZPL si no tiene firmware dual).
echo -e "${BOLD}=== PRUEBAS DE COMUNICACIÓN DIRECTA HARDWARE ===${NC}"
echo -e "Enviaremos datos en crudo por el cable USB para ver qué lenguaje habla tu TLP2844."

if [ -n "$USB_LP" ]; then
    echo -e "\n${BOLD}[Test A: Comando Nativo EPL2 directo a ${USB_LP}]${NC}"
    log_info "Enviando orden de impresión EPL2 (N\nq609\nQ914,24\nA...P1\n)..."
    # N = Clear buffer, q = Width, Q = Length/Gap, A = ASCII Text, P1 = Print 1 label
    echo -e "\nN\nq609\nQ914,24\nA50,50,0,4,1,1,N,\"TEST DIRECTO EPL2 OK\"\nP1\n" > "$USB_LP" 2>/dev/null && \
    log_success "Datos EPL2 enviados por ${USB_LP}." || log_warn "No se pudo escribir en ${USB_LP} directo."
    
    echo -e "¿Imprimió la etiqueta o reaccionó la impresora con el Test A (EPL2)?"
    read -p "[s/N]: " RESP_EPL
    if [[ "$RESP_EPL" =~ ^[sS]$ ]]; then
        log_success "¡EXCELENTE! Tu impresora TLP2844 opera con lenguaje nativo EPL2."
        LANG_DETECTED="EPL2"
    else
        echo -e "\n${BOLD}[Test B: Comando Nativo ZPL II directo a ${USB_LP}]${NC}"
        log_info "Enviando orden de impresión ZPL II (^XA^FO...^XZ)..."
        echo -e "^XA^FO50,50^A0N,50,50^FDTEST DIRECTO ZPL OK^FS^XZ" > "$USB_LP" 2>/dev/null && \
        log_success "Datos ZPL enviados por ${USB_LP}." || log_warn "No se pudo escribir ZPL."
        
        echo -e "¿Imprimió la etiqueta o reaccionó la impresora con el Test B (ZPL)?"
        read -p "[s/N]: " RESP_ZPL
        if [[ "$RESP_ZPL" =~ ^[sS]$ ]]; then
            log_success "¡EXCELENTE! Tu impresora opera con lenguaje ZPL II."
            LANG_DETECTED="ZPL"
        else
            log_warn "La impresora no reaccionó con echo directo al nodo /dev/usb/lp0."
            LANG_DETECTED="CUPS_USB"
        fi
    fi
else
    log_info "Omitiendo prueba con echo directo porque no hay nodo /dev/usb/lp0. Probando vía colas CUPS..."
    LANG_DETECTED="CUPS_USB"
fi
echo ""

# 4. Verificación y Desatasco de Colas en CUPS
echo -e "${BOLD}=== REVISIÓN DE ESTADO DE COLAS CUPS ===${NC}"
mapfile -t PRINTERS < <(LC_ALL=C lpstat -p 2>/dev/null | awk '{print $2}' || true)

if [ ${#PRINTERS[@]} -gt 0 ]; then
    for pname in "${PRINTERS[@]}"; do
        log_info "Auditando cola de impresión: ${BOLD}${pname}${NC}"
        STATUS_FULL=$(lpstat -p "$pname" -l 2>/dev/null || echo "")
        echo "$STATUS_FULL"
        
        # Si la cola está detenida por error de permisos o filtro
        if echo "$STATUS_FULL" | grep -qiE "stopped|disabled|Permission denied|exited with status"; then
            log_warn "La cola ${pname} presentaba un bloqueo o pausa de seguridad."
            log_info "Reactivando, limpiando errores y aplicando política de reintento..."
            cupsaccept "$pname" || true
            cupsenable "$pname" || true
            lpadmin -p "$pname" -o printer-error-policy=retry-job -E || true
            log_success "Cola ${pname} desbloqueada y lista."
        fi
    done
else
    log_error "No hay colas de impresión configuradas. Ejecuta el Paso 3 para crear la impresora."
    exit 1
fi
echo ""

# 5. Envío de prueba por CUPS según el lenguaje detectado
TARGET_PRINTER="${PRINTERS[0]}"
echo -e "¿Deseas enviar un trabajo de diagnóstico final a la cola CUPS '${BOLD}${TARGET_PRINTER}${NC}'?"
echo -e "  [1] Enviar formato EPL2 (Recomendado para TLP2844 clásica)"
echo -e "  [2] Enviar formato ZPL II (Para modelos TLP2844/GC420t con firmware ZPL)"
echo -e "  [3] Enviar ambos formatos en secuencia"
echo -e "  [0] Salir"
echo ""
read -p "Opción [1-3]: " FINAL_OPT

case "${FINAL_OPT:-0}" in
    1)
        log_info "Enviando etiqueta de prueba EPL2 por la cola CUPS '${TARGET_PRINTER}'..."
        echo -e "\nN\nq609\nQ914,24\nA50,50,0,4,1,1,N,\"CUPS EPL2 OK - SKUNK PC\"\nP1\n" | lp -d "$TARGET_PRINTER" -o raw
        log_success "Trabajo EPL2 puesto en cola. Verifica: lpstat -o"
        ;;
    2)
        log_info "Enviando etiqueta de prueba ZPL por la cola CUPS '${TARGET_PRINTER}'..."
        echo -e "^XA^FO50,50^A0N,50,50^FDCUPS ZPL OK - SKUNK PC^FS^XZ" | lp -d "$TARGET_PRINTER" -o raw
        log_success "Trabajo ZPL puesto en cola. Verifica: lpstat -o"
        ;;
    3)
        log_info "Enviando primero EPL2 y luego ZPL..."
        echo -e "\nN\nq609\nQ914,24\nA50,50,0,4,1,1,N,\"TEST EPL2 CUPS OK\"\nP1\n" | lp -d "$TARGET_PRINTER" -o raw
        sleep 2
        echo -e "^XA^FO50,50^A0N,50,50^FDTEST ZPL CUPS OK^FS^XZ" | lp -d "$TARGET_PRINTER" -o raw
        log_success "Ambos trabajos enviados en modo raw."
        ;;
    0)
        exit 0
        ;;
esac

echo -e "\n${GREEN}==============================================================================${NC}"
echo -e "${BOLD} ✅  DIAGNÓSTICO FINALIZADO ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "Si el trabajo permanece en cola o da error, verifica el log en tiempo real con:"
echo -e "${YELLOW}sudo tail -f /var/log/cups/error_log${NC}"
echo -e "${CYAN}==============================================================================${NC}"
