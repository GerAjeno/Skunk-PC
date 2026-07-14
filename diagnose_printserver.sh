#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: diagnose_printserver.sh
# Descripción: Script 4/4 - Diagnóstico de servicios mDNS, verificación de colas
#              y envío de pruebas nativas en ZPL/EPL2 antes de validar móviles.
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

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 🔬  SKUNK PC: DIAGNÓSTICO INTEGRAL Y PRUEBAS DE IMPRESIÓN (PASO 4/4) ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

# 1. Verificación de Servicios del Sistema
echo -e "${BOLD}[1. Estado de Servicios del Servidor]${NC}"
for svc in cups avahi-daemon cups-browsed; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactivo")
    if [ "$STATUS" = "active" ]; then
        echo -e "  • ${svc}: ${GREEN}${BOLD}RUNNING (active)${NC}"
    else
        echo -e "  • ${svc}: ${RED}${BOLD}STOPPED (${STATUS})${NC} -> Revisa: sudo systemctl status ${svc}"
    fi
done
echo ""

# 2. Verificación de Puertos de Escucha (Red y mDNS)
echo -e "${BOLD}[2. Puertos de Red Activos (CUPS 631 y Avahi 5353)]${NC}"
if ss -tuln 2>/dev/null | grep -q ":631 " || netstat -tuln 2>/dev/null | grep -q ":631 "; then
    log_success "Puerto IPP (631) abierto y escuchando conexiones en la red."
else
    log_error "El puerto 631 no se encuentra escuchando externamente. Revisa cupsd.conf."
fi

if ss -tuln 2>/dev/null | grep -q ":5353 " || netstat -tuln 2>/dev/null | grep -q ":5353 "; then
    log_success "Puerto mDNS (5353 UDP) activo y respondiendo consultas de descubrimiento."
else
    log_warn "Puerto 5353 UDP no visible en escucha local."
fi
echo ""

# 3. Estado de CUPS y Colas Configurados
echo -e "${BOLD}[3. Colas de Impresión Activas en CUPS]${NC}"
if command -v lpstat >/dev/null 2>&1; then
    lpstat -r 2>/dev/null || echo "CUPS no responde."
    echo -e "${CYAN}--- Dispositivos y destinos ---${NC}"
    lpstat -v 2>/dev/null || echo "No hay dispositivos configurados."
    echo -e "${CYAN}--- Estado de colas ---${NC}"
    lpstat -p 2>/dev/null || echo "No hay colas activas."
else
    log_error "El comando lpstat no está disponible."
fi
echo ""

# 4. Auditoría de Anuncios mDNS / ZeroConf para Android (Avahi-Browse)
echo -e "${BOLD}[4. Auditoría de Publicación mDNS (_ipp._tcp) hacia Android]${NC}"
log_info "Consultando a Avahi los servicios de impresión anunciados en la subred local..."
if command -v avahi-browse >/dev/null 2>&1; then
    # Realizar consulta corta
    MDNS_OUTPUT=$(avahi-browse -rt _ipp._tcp 2>/dev/null | grep -iE 'hostname|address|port|txt' || echo "")
    if [ -n "$MDNS_OUTPUT" ]; then
        log_success "Se han detectado anuncios activos mDNS/IPP en la red Wi-Fi:"
        echo "$MDNS_OUTPUT" | sed 's/^/    /'
    else
        log_warn "No se encontraron registros activos instantáneos para _ipp._tcp o Avahi tardó en responder."
        log_info "Puedes ejecutar una escucha continua en otra terminal con: ${YELLOW}avahi-browse -rt _ipp._tcp${NC}"
    fi
else
    log_warn "avahi-utils no está instalado para ejecutar avahi-browse."
fi
echo ""

# 5. Generación de Archivo ZPL de Prueba y Test de Impresión
echo -e "${BOLD}[5. Prueba de Impresión Térmica en Lenguaje ZPL II / EPL2]${NC}"

TEST_ZPL="test_label.zpl"
cat << 'EOF_ZPL' > "$TEST_ZPL"
^XA
^PW609
^LL914
^FO50,50^A0N,50,50^FDPROYECTO SKUNK PC^FS
^FO50,120^GB500,4,4^FS
^FO50,150^A0N,30,30^FDServidor CUPS + Avahi^FS
^FO50,200^A0N,25,25^FDImpresora: Zebra GC420t^FS
^FO50,240^A0N,25,25^FDProtocolo: IPP / AirPrint / Mopria^FS
^FO50,300^BY3,2,100
^FO50,300^BCN,100,Y,N,N
^FDSKUNK-PC-ANDROID-OK^FS
^FO50,450^A0N,25,25^FDFecha: Test Diagnostico^FS
^XZ
EOF_ZPL

log_success "Archivo de prueba de etiqueta térmica generado: ${BOLD}${TEST_ZPL}${NC}"
echo ""

# Obtener lista de impresoras para enviar prueba
mapfile -t PRINTER_LIST < <(lpstat -p 2>/dev/null | awk '{print $2}' || true)

if [ ${#PRINTER_LIST[@]} -gt 0 ]; then
    echo -e "¿Deseas enviar ahora la etiqueta ZPL de prueba a alguna de las colas activas?"
    for i in "${!PRINTER_LIST[@]}"; do
        echo -e "  [$((i+1))] ${BOLD}${PRINTER_LIST[$i]}${NC}"
    done
    echo -e "  [0] No imprimir prueba por ahora"
    echo ""
    read -p "Selecciona la cola [0-${#PRINTER_LIST[@]}]: " SEL_PRINTER
    
    if [[ "$SEL_PRINTER" =~ ^[0-9]+$ ]] && [ "$SEL_PRINTER" -gt 0 ] && [ "$SEL_PRINTER" -le ${#PRINTER_LIST[@]} ]; then
        TARGET="${PRINTER_LIST[$((SEL_PRINTER-1))]}"
        log_info "Enviando etiqueta ${TEST_ZPL} en modo raw a la cola '${TARGET}'..."
        if lp -d "$TARGET" -o raw "$TEST_ZPL" 2>/dev/null; then
            log_success "Trabajo enviado a la impresora '${TARGET}'. Verifica si salió la etiqueta."
        else
            log_error "Fallo al enviar el trabajo. Verifica si la impresora está encendida o pausada: lpstat -p ${TARGET}"
        fi
    else
        log_info "Omitiendo envío de prueba ZPL."
    fi
else
    log_warn "No hay colas de impresión configuradas para enviar prueba. Ejecuta el Paso 3 primero."
fi

echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${BOLD} 🎉 DIAGNÓSTICO FINALIZADO CON ÉXITO ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "Si todos los servicios muestran 'RUNNING' y el puerto 631 está abierto,"
echo -e "${BOLD}el servidor Skunk PC está listo para recibir teléfonos Android por Wi-Fi.${NC}"
echo -e "Consulta el archivo ${YELLOW}TROUBLESHOOTING.md${NC} si tienes problemas en el móvil."
echo -e "${CYAN}==============================================================================${NC}"
