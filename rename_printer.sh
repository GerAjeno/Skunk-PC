#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: rename_printer.sh
# Descripción: Herramienta 5 - Renombrar una impresora existente en CUPS de
#              forma segura conservando su URI USB/red y sus parámetros.
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
    log_error "Este script requiere privilegios root: sudo ./rename_printer.sh"
    exit 1
fi

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} ✏️  SKUNK PC: CAMBIAR NOMBRE DE IMPRESORA EN CUPS ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

# Obtener lista de colas actuales en CUPS
mapfile -t PRINTERS < <(LC_ALL=C lpstat -p 2>/dev/null | awk '{print $2}' || true)

if [ ${#PRINTERS[@]} -eq 0 ]; then
    log_error "No hay ninguna impresora configurada actualmente en CUPS."
    log_info "Ejecuta primero el Paso 3 para agregar una impresora por USB."
    exit 1
fi

echo -e "Impresoras actuales configuradas en el servidor:"
for i in "${!PRINTERS[@]}"; do
    # Obtener el URI de conexión de cada una
    URI=$(lpstat -v "${PRINTERS[$i]}" 2>/dev/null | awk '{print $3}' || echo "Desconocido")
    echo -e "  [$((i+1))] ${BOLD}${PRINTERS[$i]}${NC} -> ${YELLOW}${URI}${NC}"
done
echo ""

read -p "Selecciona el número de la impresora que deseas renombrar [1-${#PRINTERS[@]}]: " SEL_IDX
if ! [[ "$SEL_IDX" =~ ^[0-9]+$ ]] || [ "$SEL_IDX" -lt 1 ] || [ "$SEL_IDX" -gt ${#PRINTERS[@]} ]; then
    log_error "Selección inválida."
    exit 1
fi

OLD_URI=$(lpstat -v "$OLD_NAME" 2>/dev/null | sed 's/.*device for [^:]*: //' || echo "")

if [ -z "$OLD_URI" ]; then
    OLD_URI="file:///dev/null"
fi

echo ""
log_info "Impresora seleccionada: ${YELLOW}${OLD_NAME}${NC}"
log_info "URI de conexión detectado: ${CYAN}${OLD_URI}${NC}"
echo ""

while true; do
    read -p "Introduce el NUEVO NOMBRE para la impresora (sin espacios, ej. Zebra_Caja_Final): " NEW_NAME
    if [[ "$NEW_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        if [ "$NEW_NAME" = "$OLD_NAME" ]; then
            log_warn "El nuevo nombre es idéntico al actual."
            exit 0
        fi
        break
    else
        log_error "El nombre solo puede contener letras, números, guiones (-) y guiones bajos (_), sin espacios ni tildes."
    fi
done

read -p "¿Descripción corta fácil de identificar en Android? [ej. Zebra Almacén 1]: " NEW_DESC
NEW_DESC="${NEW_DESC:-Zebra Térmica - ${NEW_NAME}}"

# Verificar si la impresora vieja era la predeterminada del sistema
IS_DEFAULT=false
if lpstat -d 2>/dev/null | grep -q "$OLD_NAME"; then
    IS_DEFAULT=true
fi

log_info "Creando nueva cola '${BOLD}${NEW_NAME}${NC}' apuntando al mismo puerto USB..."
lpadmin -p "$NEW_NAME" -v "$OLD_URI" -E -o raw -o printer-is-shared=true -D "$NEW_DESC" -L "Almacén / Red Skunk-PC" || {
    log_error "Fallo al crear la cola '${NEW_NAME}'."
    exit 1
}

# Activar la nueva cola y aceptar trabajos
cupsaccept "$NEW_NAME" || true
cupsenable "$NEW_NAME" || true

# Si era la impresora por defecto, asignar la nueva
if [ "$IS_DEFAULT" = true ]; then
    lpadmin -d "$NEW_NAME" || true
    log_info "Asignada '${NEW_NAME}' como impresora por defecto en el servidor."
fi

# Eliminar la cola antigua
log_info "Eliminando la cola antigua '${OLD_NAME}'..."
lpadmin -x "$OLD_NAME" || log_warn "No se pudo eliminar la cola antigua completamente, revísalo en CUPS."

echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${BOLD} ✅  IMPRESORA RENOMBRADA EXITOSAMENTE A: ${NEW_NAME} ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
lpstat -p -v "$NEW_NAME" 2>/dev/null || true
echo -e "Los teléfonos Android en la red ahora detectarán la impresora como: ${BOLD}${NEW_DESC} (${NEW_NAME})${NC}"
echo -e "${CYAN}==============================================================================${NC}"
