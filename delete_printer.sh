#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: delete_printer.sh
# Descripción: Herramienta para desinstalar / eliminar colas de impresión de CUPS.
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Por favor, ejecuta el script con sudo: ${YELLOW}sudo ./delete_printer.sh${NC}"
    exit 1
fi

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 🗑️  SKUNK PC: ELIMINACIÓN Y DESINSTALACIÓN DE IMPRESORAS EN CUPS ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

# Verificar si CUPS está corriendo
if ! systemctl is-active --quiet cups; then
    echo -e "${YELLOW}[ADVERTENCIA] CUPS no está activo. Iniciando servicio...${NC}"
    systemctl start cups || true
fi

# Listar impresoras instaladas
PRINTERS=($(lpstat -p 2>/dev/null | awk '{print $2}' || true))

if [ ${#PRINTERS[@]} -eq 0 ]; then
    echo -e "${YELLOW}[INFO] No hay impresoras instaladas en este servidor CUPS.${NC}"
    exit 0
fi

echo -e "Impresoras actualmente registradas en el sistema:\n"
for i in "${!PRINTERS[@]}"; do
    URI="$(lpstat -v "${PRINTERS[$i]}" 2>/dev/null | awk -F': ' '{print $2}' || echo 'Desconocida')"
    echo -e "  ${BOLD}[$((i+1))] ${PRINTERS[$i]}${NC} (Conexión: ${CYAN}${URI}${NC})"
done
echo -e "  ${BOLD}[0] Cancelar / Salir${NC}"
echo -e "${CYAN}------------------------------------------------------------------------------${NC}"

read -p "Selecciona el número de la impresora que deseas ELIMINAR [0-${#PRINTERS[@]}]: " SEL

if [ -z "$SEL" ] || ! [[ "$SEL" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}[ERROR] Selección inválida.${NC}"
    exit 1
fi

if [ "$SEL" -eq 0 ]; then
    echo -e "${GREEN}Operación cancelada.${NC}"
    exit 0
fi

if [ "$SEL" -gt ${#PRINTERS[@]} ]; then
    echo -e "${RED}[ERROR] Número fuera de rango.${NC}"
    exit 1
fi

TARGET_PRINTER="${PRINTERS[$((SEL-1))]}"

echo -e "\n${YELLOW}⚠️  ¿Estás completamente seguro de eliminar la cola '${BOLD}${TARGET_PRINTER}${NC}${YELLOW}'?${NC}"
read -p "Escribe 's' o 'y' para confirmar: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[sSyY]$ ]]; then
    echo -e "${GREEN}Operación cancelada.${NC}"
    exit 0
fi

echo -e "${CYAN}[INFO] Desinstalando impresora ${TARGET_PRINTER}...${NC}"
lpadmin -x "${TARGET_PRINTER}" || true

# Verificar si se eliminó correctamente
if ! lpstat -p "${TARGET_PRINTER}" >/dev/null 2>&1; then
    echo -e "${GREEN}✔ ¡Impresora '${TARGET_PRINTER}' eliminada exitosamente del servidor!${NC}"
    echo -e "${CYAN}[INFO] Los anuncios mDNS y AirPrint/Mopria para esta cola cesarán de inmediato.${NC}"
else
    echo -e "${RED}[ERROR] No se pudo eliminar la impresora.${NC}"
    exit 1
fi
