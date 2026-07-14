#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: test_center.sh
# Descripción: Herramienta 8 - Centro interactivo de pruebas de impresión ZPL,
#              código de barras, página de prueba CUPS y calibración de sensor.
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
    log_error "Este script requiere privilegios root: sudo ./test_center.sh"
    exit 1
fi

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 🧪  SKUNK PC: CENTRO DE PRUEBAS DE IMPRESIÓN Y CALIBRACIÓN ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

mapfile -t PRINTERS < <(lpstat -p 2>/dev/null | awk '{print $2}' || true)
if [ ${#PRINTERS[@]} -eq 0 ]; then
    log_error "No hay colas de impresión activas en CUPS. Ejecuta primero el Paso 3."
    exit 1
fi

echo -e "Impresoras disponibles para pruebas:"
for i in "${!PRINTERS[@]}"; do
    STATUS=$(lpstat -p "${PRINTERS[$i]}" 2>/dev/null | awk '{print $3}' || echo "idle")
    echo -e "  [$((i+1))] ${BOLD}${PRINTERS[$i]}${NC} (${CYAN}${STATUS}${NC})"
done
echo ""

read -p "Selecciona la impresora que deseas probar [1-${#PRINTERS[@]}]: " SEL_IDX
if ! [[ "$SEL_IDX" =~ ^[0-9]+$ ]] || [ "$SEL_IDX" -lt 1 ] || [ "$SEL_IDX" -gt ${#PRINTERS[@]} ]; then
    log_error "Selección inválida."
    exit 1
fi

TARGET="${PRINTERS[$((SEL_IDX-1))]}"
echo ""
log_info "Impresora seleccionada para pruebas: ${YELLOW}${TARGET}${NC}"

echo -e "\n${BOLD}--- Selecciona el Tipo de Prueba o Calibración ---${NC}"
echo -e "  [1] ${BOLD}Etiqueta de Prueba Estándar (Texto y Cuadro ZPL)${NC} -> Verifica alineación básica y nitidez"
echo -e "  [2] ${BOLD}Etiqueta Logística con Código de Barras (ZPL II)${NC} -> Simula una etiqueta real de almacén con código 128"
echo -e "  [3] ${BOLD}Calibración Física del Papel Térmico (~JC / gap calibration)${NC} -> Fuerza al sensor a medir el corte entre etiquetas"
echo -e "  [4] ${BOLD}Página de Prueba Nativa de CUPS (`testprint` / PPD)${NC} -> Verifica el filtro del controlador del sistema"
echo -e "  [0] Salir sin imprimir"
echo ""
read -p "Opción [0-4]: " TEST_OPT

case "${TEST_OPT:-0}" in
    1)
        log_info "Enviando etiqueta de prueba ZPL básica a '${TARGET}'..."
        TEST_FILE="/tmp/skunk_basic.zpl"
        cat << 'EOF' > "$TEST_FILE"
^XA
^PW609
^LL914
^FO50,50^GB500,800,4^FS
^FO80,100^A0N,45,45^FDPRUEBA SKUNK PC^FS
^FO80,180^A0N,30,30^FDServidor: Ubuntu / Proxmox^FS
^FO80,240^A0N,30,30^FDImpresora: Zebra OK^FS
^FO80,320^A0N,30,30^FDEstado: Conectada y Lista^FS
^FO80,500^A0N,35,35^FD--- TEST EXITOSO ---^FS
^XZ
EOF
        lp -d "$TARGET" -o raw "$TEST_FILE" || log_error "Fallo al enviar el trabajo."
        log_success "Trabajo enviado correctamente. Revisa la salida en la impresora."
        ;;
    2)
        log_info "Enviando etiqueta con Código de Barras (Code 128) a '${TARGET}'..."
        TEST_FILE="/tmp/skunk_barcode.zpl"
        cat << 'EOF' > "$TEST_FILE"
^XA
^PW609
^LL914
^FO50,50^GB500,4,4^FS
^FO60,80^A0N,40,40^FDETIQUETA LOGISTICA SKUNK^FS
^FO60,140^A0N,25,25^FDDOMINIO: SKUNK-PC.LOCAL^FS
^FO60,200^BY3,2,120
^FO60,200^BCN,120,Y,N,N
^FDSKUNK-PRINTOK-2026^FS
^FO60,380^A0N,25,25^FDMOPRIA / AIRPRINT / IPP COMPATIBLE^FS
^FO50,440^GB500,4,4^FS
^XZ
EOF
        lp -d "$TARGET" -o raw "$TEST_FILE" || log_error "Fallo al enviar el código de barras."
        log_success "Etiqueta con código de barras enviada."
        ;;
    3)
        log_info "Iniciando CALIBRACIÓN DE SENSOR en '${TARGET}'..."
        log_warn "La impresora expulsará 2 o 3 etiquetas en blanco mientras mide el corte (gap) entre ellas."
        # Comando ZPL de calibración de sensor: ~JC
        echo -e "~JC\n^XA^JUS^XZ" | lp -d "$TARGET" -o raw || log_error "Fallo al enviar orden de calibración."
        # También enviar comando en EPL por si la impresora está operando en modo EPL2 puro
        echo -e "jc\n" | lp -d "$TARGET" -o raw 2>/dev/null || true
        log_success "Orden de calibración enviada. El sensor del papel térmico se ha calibrado y guardado en memoria."
        ;;
    4)
        log_info "Enviando página de prueba nativa del motor CUPS (`testprint`) a '${TARGET}'..."
        if [ -f "/usr/share/cups/data/testprint" ]; then
            lp -d "$TARGET" /usr/share/cups/data/testprint || log_error "Fallo al enviar la prueba nativa."
            log_success "Página de prueba PPD nativa enviada."
        else
            log_warn "No se encontró /usr/share/cups/data/testprint. Enviando prueba ZPL alternativa..."
            echo -e "^XA^FO50,50^A0N,50,50^FDCUPS TEST PRINT OK^FS^XZ" | lp -d "$TARGET" -o raw
        fi
        ;;
    0)
        log_info "Saliendo sin enviar trabajos."
        exit 0
        ;;
    *)
        log_error "Opción no válida."
        exit 1
        ;;
esac

echo -e "\n${CYAN}==============================================================================${NC}"
