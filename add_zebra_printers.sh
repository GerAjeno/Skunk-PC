#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: add_zebra_printers.sh
# Descripción: Script 3/4 - Escaneo de puertos USB, detección automática y/o
#              configuración interactiva de hasta 6 impresoras Zebra GC420t.
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
    log_error "Este script requiere privilegios root: sudo ./add_zebra_printers.sh"
    exit 1
fi

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 🖨️  SKUNK PC: DETECCIÓN USB Y CONFIGURACIÓN DE IMPRESORAS (PASO 3/4) ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

# 1. Búsqueda y selección del controlador (Driver/PPD) óptimo para Zebra GC420t
log_info "Verificando controladores disponibles en CUPS para Zebra EPL2/ZPL..."
PPD_MODEL=""

# Intentar buscar PPD en lpinfo -m
if PPD_MODEL=$(lpinfo -m 2>/dev/null | awk '/Zebra.*ZPL/ || /foo2zjs.*Zebra/ || /Zebra.*TLP2844/ || /drv:\/\/\/sample.drv\/zebra.ppd/ || /Zebra.*EPL2/ {print $1; exit}'); then
    if [ -n "$PPD_MODEL" ]; then
        log_success "Driver compatible detectado en CUPS: ${YELLOW}${PPD_MODEL}${NC}"
    fi
fi

if [ -z "$PPD_MODEL" ]; then
    log_warn "No se encontró un PPD explícito de Zebra en la cache rápida de CUPS."
    log_info "Asignando controlador genérico nativo 'raw' o 'drv:///sample.drv/zebra.ppd'."
    PPD_MODEL="drv:///sample.drv/zebra.ppd"
fi
echo ""

# Función para añadir y configurar una cola en CUPS
add_cups_printer() {
    local NAME="$1"
    local URI="$2"
    local MODEL="$3"
    local DESCRIPTION="${4:-Impresora Térmica Zebra (GC420t / TLP2844)}"

    log_info "Registrando cola de impresión '${BOLD}${NAME}${NC}' en CUPS..."
    log_info "  -> URI: ${URI}"
    log_info "  -> Driver: ${MODEL}"

    # Si la cola ya existe, lpadmin la sobrescribirá y actualizará
    if [ "$MODEL" = "raw" ]; then
        lpadmin -p "$NAME" -v "$URI" -E -o raw -o printer-is-shared=true -D "$DESCRIPTION" -L "Almacén / Red Skunk-PC" || {
            log_error "Fallo al crear la cola en modo raw."
            return 1
        }
    else
        # Intentar con PPD especificado
        if ! lpadmin -p "$NAME" -v "$URI" -E -m "$MODEL" -o printer-is-shared=true -D "$DESCRIPTION" -L "Almacén / Red Skunk-PC" 2>/dev/null; then
            log_warn "El driver ${MODEL} no pudo inicializarse por fallo de PPD. Reintentando en modo genérico 'raw' (común en EPL2/ZPL directo)..."
            lpadmin -p "$NAME" -v "$URI" -E -o raw -o printer-is-shared=true -D "$DESCRIPTION" -L "Almacén / Red Skunk-PC"
        fi
    fi

    # Habilitar y aceptar trabajos
    cupsaccept "$NAME" || true
    cupsenable "$NAME" || true

    # Configurar opciones térmicas predeterminadas si el driver PPD lo soporta
    lpadmin -p "$NAME" -o printer-error-policy=retry-job 2>/dev/null || true

    log_success "Impresora ${BOLD}${NAME}${NC} añadida y compartida en red (@mDNS)."
}

# 2. Escaneo de dispositivos USB en el servidor
log_info "Escaneando puertos USB físicos buscando dispositivos Zebra (lpinfo -v)..."
mapfile -t USB_URIS < <(lpinfo -v 2>/dev/null | grep -iE "usb://.*(Zebra|GC420|TLP2844|LP2844|GK420|GX420|ZD420|ZD620)" | awk '{print $2}' || true)

# Si lpinfo no devuelve específicamente 'Zebra', buscar cualquier impresora USB conectada
if [ ${#USB_URIS[@]} -eq 0 ]; then
    log_warn "lpinfo no encontró URIs explícitos con nombre 'Zebra/TLP2844'."
    mapfile -t USB_URIS < <(lpinfo -v 2>/dev/null | grep -i "^direct usb://" | awk '{print $2}' || true)
fi

echo -e "${CYAN}------------------------------------------------------------------------------${NC}"
echo -e "${BOLD}DISPOSITIVOS USB DETECTADOS (${#USB_URIS[@]}):${NC}"
if [ ${#USB_URIS[@]} -gt 0 ]; then
    for i in "${!USB_URIS[@]}"; do
        echo -e "  [$((i+1))] ${GREEN}${USB_URIS[$i]}${NC}"
    done
else
    echo -e "  ${YELLOW}(Ninguna impresora USB detectada en este momento)${NC}"
fi
echo -e "${CYAN}------------------------------------------------------------------------------${NC}"
echo ""

# 3. Menú de Modo de Configuración
echo -e "Selecciona el modo de instalación de las impresoras:"
echo -e "  ${BOLD}[1] Automático:${NC} Registrar todas las impresoras USB detectadas (Zebra_GC420t_Caja_1, etc.)"
echo -e "  ${BOLD}[2] Interactivo:${NC} Elegir qué impresora agregar y asignar nombre personalizado sin espacios"
echo -e "  ${BOLD}[3] Emulación / Prueba (Simulación LAN):${NC} Crear una impresora virtual de prueba para verificar descubrimiento Android sin hardware"
echo -e "  ${BOLD}[4] Salir${NC}"
echo ""
read -p "Opción [1-4]: " OPTION

case "${OPTION:-1}" in
    1)
        if [ ${#USB_URIS[@]} -eq 0 ]; then
            log_error "No hay impresoras físicas USB conectadas para el modo automático."
            exit 1
        fi
        log_info "Iniciando registro automático de ${#USB_URIS[@]} impresoras..."
        for i in "${!USB_URIS[@]}"; do
            IDX=$((i+1))
            PNAME="Zebra_GC420t_Caja_${IDX}"
            add_cups_printer "$PNAME" "${USB_URIS[$i]}" "$PPD_MODEL" "Zebra GC420t Térmica - Caja ${IDX}"
            echo ""
        done
        ;;
    2)
        if [ ${#USB_URIS[@]} -eq 0 ]; then
            log_error "No hay impresoras USB detectadas para seleccionar."
            exit 1
        fi
        read -p "Selecciona el número de URI [1-${#USB_URIS[@]}]: " SEL_IDX
        if ! [[ "$SEL_IDX" =~ ^[0-9]+$ ]] || [ "$SEL_IDX" -lt 1 ] || [ "$SEL_IDX" -gt ${#USB_URIS[@]} ]; then
            log_error "Selección inválida."
            exit 1
        fi
        SELECTED_URI="${USB_URIS[$((SEL_IDX-1))]}"
        
        while true; do
            read -p "Nombre para la cola CUPS (sin espacios, ej. Zebra_Almacen_Sur): " CUSTOM_NAME
            if [[ "$CUSTOM_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                break
            else
                log_error "El nombre solo puede contener letras, números, guiones y guiones bajos (sin espacios)."
            fi
        done
        
        add_cups_printer "$CUSTOM_NAME" "$SELECTED_URI" "$PPD_MODEL" "Zebra GC420t - ${CUSTOM_NAME}"
        ;;
    3)
        log_info "Modo Simulación: Creando cola virtual 'Zebra_GC420t_Simulada_Android'..."
        # Si no existe impresora física, apuntamos a /dev/null o file:/dev/null para testear broadcast mDNS
        add_cups_printer "Zebra_GC420t_Simulada_Android" "file:///dev/null" "$PPD_MODEL" "Impresora Zebra Emulada para Prueba Android Wi-Fi"
        ;;
    4)
        log_info "Saliendo sin realizar cambios adicionales."
        exit 0
        ;;
    *)
        log_error "Opción no válida."
        exit 1
        ;;
esac

echo -e "${GREEN}==============================================================================${NC}"
echo -e "${BOLD} ✅  COLAS DE IMPRESIÓN CONFIGURADAS ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "Lista de impresoras compartidas activas en CUPS en este momento:"
lpstat -p -d 2>/dev/null || true
echo ""
echo -e "👉 Próximo paso: Ejecutar ${YELLOW}sudo ./diagnose_printserver.sh${NC} (Paso 4) para realizar"
echo -e "   el diagnóstico final de red mDNS, salud de las colas y prueba de impresión ZPL."
echo -e "${CYAN}==============================================================================${NC}"
