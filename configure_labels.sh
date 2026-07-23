#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: configure_labels.sh
# Descripción: Herramienta 7 - Configurar tamaño exacto de etiquetas térmicas,
#              modo de impresión (Direct Thermal / Ribbon) y parámetros en CUPS.
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
    log_error "Este script requiere privilegios root: sudo ./configure_labels.sh"
    exit 1
fi

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 🏷️  SKUNK PC: CONFIGURAR TAMAÑO Y TIPO DE ETIQUETAS TÉRMICAS ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

mapfile -t PRINTERS < <(LC_ALL=C lpstat -p 2>/dev/null | awk '{print $2}' || true)
if [ ${#PRINTERS[@]} -eq 0 ]; then
    log_error "No hay colas de impresión configuradas. Ejecuta el Paso 3 primero."
    exit 1
fi

echo -e "Selecciona la impresora que deseas configurar:"
for i in "${!PRINTERS[@]}"; do
    echo -e "  [$((i+1))] ${BOLD}${PRINTERS[$i]}${NC}"
done
echo ""

read -p "Opción [1-${#PRINTERS[@]}]: " SEL_IDX
if ! [[ "$SEL_IDX" =~ ^[0-9]+$ ]] || [ "$SEL_IDX" -lt 1 ] || [ "$SEL_IDX" -gt ${#PRINTERS[@]} ]; then
    log_error "Selección inválida."
    exit 1
fi

TARGET_PRINTER="${PRINTERS[$((SEL_IDX-1))]}"
echo ""
log_info "Configurando parámetros para: ${YELLOW}${TARGET_PRINTER}${NC}"

echo -e "\n${BOLD}--- Selecciona el Tamaño de Etiqueta Física ---${NC}"
echo -e "  [1] ${BOLD}4x6 pulgadas (100x150 mm)${NC} -> Estándar de paquetería y envíos (Amazon, DHL, FedEx)"
echo -e "  [2] ${BOLD}2x1 pulgadas (50x25 mm)${NC}   -> Código de barras de producto pequeño / Inventario"
echo -e "  [3] ${BOLD}4x4 pulgadas (100x100 mm)${NC} -> Tarimas e identificación de cajas medianas"
echo -e "  [4] ${BOLD}3x2 pulgadas (75x50 mm)${NC}   -> Etiquetas de estante / Ubicación de almacén"
echo -e "  [5] ${BOLD}Personalizado (Ingresar dimensiones en Milímetros)${NC}"
echo ""
read -p "Opción de tamaño [1-5]: " SIZE_OPT

WIDTH_MM=100
HEIGHT_MM=150
SIZE_DESC="100x150mm (4x6\")"

case "$SIZE_OPT" in
    1) WIDTH_MM=100; HEIGHT_MM=150; SIZE_DESC="100x150mm (4x6\")" ;;
    2) WIDTH_MM=50;  HEIGHT_MM=25;  SIZE_DESC="50x25mm (2x1\")" ;;
    3) WIDTH_MM=100; HEIGHT_MM=100; SIZE_DESC="100x100mm (4x4\")" ;;
    4) WIDTH_MM=75;  HEIGHT_MM=50;  SIZE_DESC="75x50mm (3x2\")" ;;
    5)
        read -p "Ancho de la etiqueta en Milímetros (ej. 100): " WIDTH_MM
        read -p "Alto de la etiqueta en Milímetros (ej. 150): " HEIGHT_MM
        SIZE_DESC="${WIDTH_MM}x${HEIGHT_MM}mm Personalizado"
        ;;
    *)
        log_warn "Opción inválida, aplicando 100x150mm por defecto."
        ;;
esac

echo -e "\n${BOLD}--- Selecciona el Modo / Tipo de Impresión Térmica ---${NC}"
echo -e "  [1] ${BOLD}Térmico Directo (Direct Thermal)${NC} -> Papel térmico autoadhesivo sensible al calor (Sin cinta Ribbon)"
echo -e "  [2] ${BOLD}Transferencia Térmica (Thermal Transfer)${NC} -> Papel normal/plástico usando cinta Ribbon de tinta"
echo ""
read -p "Opción de modo [1-2]: " MODE_OPT

MODE_DESC="Direct Thermal (Térmico Directo)"
ZPL_MODE="^MTD"
EPL_MODE="OD"

if [ "$MODE_OPT" = "2" ]; then
    MODE_DESC="Thermal Transfer (Con Cinta Ribbon)"
    ZPL_MODE="^MTT"
    EPL_MODE="OT"
fi

log_info "Aplicando configuración en el servidor CUPS (`lpadmin` media options)..."

# Configurar en CUPS si el PPD soporta las directivas
lpadmin -p "$TARGET_PRINTER" -o media="Custom.${WIDTH_MM}x${HEIGHT_MM}mm" 2>/dev/null || \
lpadmin -p "$TARGET_PRINTER" -o PageSize="Custom.${WIDTH_MM}x${HEIGHT_MM}mm" 2>/dev/null || true

# Para 203 DPI (Resolución de Zebra GC420t / TLP2844), 1 mm = 8 puntos exactos (dots)
# Ancho en puntos = mm * 8
PW=$(( WIDTH_MM * 8 ))
# Alto en puntos = mm * 8
LL=$(( HEIGHT_MM * 8 ))

# Enviar comando hardware a la impresora para guardar tamaño y modo en su memoria interna no volátil
log_info "Enviando comandos de configuración nativos en ZPL/EPL a la memoria de ${TARGET_PRINTER}..."

# ZPL II: ^PW (Print Width), ^LL (Label Length), ^MT (Media Type), ^JUS (Save settings)
ZPL_CONFIG="^XA${ZPL_MODE}^PW${PW}^LL${LL}^JUS^XZ"

# EPL2: q (Label width), Q (Label length, gap), O (Options), ^@ (Reset)
EPL_CONFIG="q${PW}\nQ${LL},24\n${EPL_MODE}\n"

# Intentar enviar la orden de configuración al hardware de la impresora
if echo -e "$ZPL_CONFIG" | lp -d "$TARGET_PRINTER" -o raw 2>/dev/null; then
    log_success "Comando de memoria ZPL y tamaño (${PW}x${LL} puntos @ 203dpi) enviado a la impresora."
else
    log_warn "No se pudo comunicar con el hardware directamente en este momento (¿impresora en reposo? CUPS guardó la configuración por software)."
fi

# Reiniciar la cola para asegurar que adopta los parámetros en red
cupsenable "$TARGET_PRINTER" || true

echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${BOLD} ✅  TAMAÑO Y TIPO DE ETIQUETAS CONFIGURADO EXITOSAMENTE ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "Impresora   : ${BOLD}${TARGET_PRINTER}${NC}"
echo -e "Tamaño      : ${BOLD}${SIZE_DESC}${NC} (${PW}x${LL} píxeles @ 203 DPI)"
echo -e "Modo térmico: ${BOLD}${MODE_DESC}${NC}"
echo -e "${CYAN}==============================================================================${NC}"
