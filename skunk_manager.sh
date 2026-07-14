#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: skunk_manager.sh
# Descripción: Panel de Orquestación y Administración unificado para ejecutar
#              los 4 pasos de forma interactiva en el servidor final.
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
    echo -e "${RED}[ERROR]${NC} Por favor, ejecuta el administrador con sudo: ${YELLOW}sudo ./skunk_manager.sh${NC}"
    exit 1
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
    clear
    echo -e "${CYAN}==============================================================================${NC}"
    echo -e "${BOLD} 🖨️  SKUNK PC: PANEL UNIFICADO DE ADMINISTRACIÓN Y SERVIDOR DE IMPRESIÓN ${NC}"
    echo -e "${CYAN}==============================================================================${NC}"
    echo -e "Servidor local: ${BOLD}$(hostname)${NC} | OS: ${BOLD}$(grep ^PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo 'Linux')${NC}"
    echo -e "Estado de CUPS: $(systemctl is-active cups 2>/dev/null | sed 's/active/RUNNING/' || echo 'INACTIVO') | Estado Avahi (mDNS): $(systemctl is-active avahi-daemon 2>/dev/null | sed 's/active/RUNNING/' || echo 'INACTIVO')"
    echo -e "${CYAN}------------------------------------------------------------------------------${NC}"
    echo -e "  ${BOLD}[1] PASO 1: Instalación de Dependencias y Servicios${NC} (${YELLOW}setup_printserver.sh${NC})"
    echo -e "  ${BOLD}[2] PASO 2: Configuración de Acceso en Red e IPP/mDNS${NC} (${YELLOW}configure_cups_network.sh${NC})"
    echo -e "  ${BOLD}[3] PASO 3: Detección USB y Autoconfiguración Zebra${NC} (${YELLOW}add_zebra_printers.sh${NC})"
    echo -e "  ${BOLD}[4] PASO 4: Diagnóstico Integral, mDNS y Test ZPL${NC} (${YELLOW}diagnose_printserver.sh${NC})"
    echo -e "${CYAN}------------------------------------------------------------------------------${NC}"
    echo -e "  ${BOLD}[5] Ver Estado de Colas y Trabajos${NC} (${CYAN}lpstat -r -p -d -v${NC})"
    echo -e "  ${BOLD}[6] Consultar Guía de Depuración${NC} (${CYAN}TROUBLESHOOTING.md${NC})"
    echo -e "  ${BOLD}[0] Salir${NC}"
    echo -e "${CYAN}==============================================================================${NC}"
    read -p "Selecciona una opción [0-6]: " OPT

    case "$OPT" in
        1)
            bash "${BASE_DIR}/setup_printserver.sh"
            read -p "Presiona ENTER para volver al menú..." || true
            ;;
        2)
            bash "${BASE_DIR}/configure_cups_network.sh"
            read -p "Presiona ENTER para volver al menú..." || true
            ;;
        3)
            bash "${BASE_DIR}/add_zebra_printers.sh"
            read -p "Presiona ENTER para volver al menú..." || true
            ;;
        4)
            bash "${BASE_DIR}/diagnose_printserver.sh"
            read -p "Presiona ENTER para volver al menú..." || true
            ;;
        5)
            echo -e "\n${BOLD}=== ESTADO EN TIEMPO REAL DE CUPS ===${NC}"
            lpstat -r -p -d -v 2>/dev/null || echo -e "${RED}Error al consultar lpstat.${NC}"
            echo ""
            read -p "Presiona ENTER para continuar..." || true
            ;;
        6)
            if command -v less >/dev/null 2>&1 && [ -f "${BASE_DIR}/TROUBLESHOOTING.md" ]; then
                less "${BASE_DIR}/TROUBLESHOOTING.md"
            else
                cat "${BASE_DIR}/TROUBLESHOOTING.md" | head -n 40
                echo -e "\n${YELLOW}... (Lee el archivo completo con 'cat TROUBLESHOOTING.md') ...${NC}"
                read -p "Presiona ENTER para continuar..." || true
            fi
            ;;
        0)
            echo -e "${GREEN}¡Hasta pronto! Skunk PC en línea.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opción inválida.${NC}"
            sleep 1
            ;;
    esac
done
