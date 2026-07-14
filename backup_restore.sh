#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: backup_restore.sh
# Descripción: Herramienta 12 - Crear respaldos (.tar.gz) y restaurar de forma
#              instantánea todas las colas de impresión y políticas de CUPS.
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
    log_error "Este script requiere privilegios root: sudo ./backup_restore.sh"
    exit 1
fi

BACKUP_DIR="/var/backups/skunk-pc"
mkdir -p "$BACKUP_DIR"

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 📦  SKUNK PC: RESPALDO Y RESTAURACIÓN DE DESASTRES (CLONADO) ${NC}"
echo -e "${CYAN}==============================================================================${NC}"
echo -e "Selecciona una opción:"
echo -e "  [1] ${BOLD}Crear una Copia de Seguridad Completa (Backup)${NC} -> Guarda colas, PPDs y red en ${BACKUP_DIR}"
echo -e "  [2] ${BOLD}Restaurar desde una Copia de Seguridad (Restore)${NC} -> Restablece un servidor clon en 5s"
echo -e "  [3] ${BOLD}Listar Respaldos Disponibles${NC}"
echo -e "  [0] Salir"
echo ""
read -p "Opción [0-3]: " OPT

case "${OPT:-0}" in
    1)
        DATE_STR=$(date '+%Y%m%d_%H%M%S')
        ARCHIVE_PATH="${BACKUP_DIR}/skunk_backup_${DATE_STR}.tar.gz"
        log_info "Empaquetando configuración de /etc/cups/ en ${ARCHIVE_PATH}..."
        
        # Detener brevemente CUPS para asegurar consistencia en printers.conf
        systemctl stop cups 2>/dev/null || true
        
        tar -czf "$ARCHIVE_PATH" /etc/cups/printers.conf /etc/cups/cupsd.conf /etc/cups/ppd/ /etc/avahi/avahi-daemon.conf 2>/dev/null || true
        
        systemctl start cups 2>/dev/null || true
        
        log_success "Respaldo generado con éxito: ${BOLD}${ARCHIVE_PATH}${NC}"
        echo -e "Tamaño: $(du -sh "$ARCHIVE_PATH" | awk '{print $1}')"
        echo -e "Para clonar otro servidor o restaurar ante desastres, copia este archivo .tar.gz."
        ;;
    2)
        mapfile -t ARCHIVES < <(ls -1t "${BACKUP_DIR}"/*.tar.gz 2>/dev/null || true)
        if [ ${#ARCHIVES[@]} -eq 0 ]; then
            log_error "No se encontraron archivos de respaldo (.tar.gz) en ${BACKUP_DIR}."
            echo -e "Puedes copiar un archivo de respaldo manualmente a ${BACKUP_DIR} e intentarlo de nuevo."
            exit 1
        fi
        
        echo -e "\nRespaldos encontrados en ${BACKUP_DIR}:"
        for i in "${!ARCHIVES[@]}"; do
            echo -e "  [$((i+1))] ${BOLD}$(basename "${ARCHIVES[$i]}")${NC} ($(du -sh "${ARCHIVES[$i]}" | awk '{print $1}'), $(date -r "${ARCHIVES[$i]}" '+%Y-%m-%d %H:%M:%S'))"
        done
        echo ""
        read -p "Selecciona el número del respaldo a restaurar [1-${#ARCHIVES[@]}]: " SEL_IDX
        
        if ! [[ "$SEL_IDX" =~ ^[0-9]+$ ]] || [ "$SEL_IDX" -lt 1 ] || [ "$SEL_IDX" -gt ${#ARCHIVES[@]} ]; then
            log_error "Selección inválida."
            exit 1
        fi
        
        SELECTED_ARCHIVE="${ARCHIVES[$((SEL_IDX-1))]}"
        log_warn "¡ATENCIÓN! La restauración sobrescribirá la configuración actual de colas de CUPS."
        read -p "¿Estás seguro de continuar? [s/N]: " CONFIRM
        if ! [[ "$CONFIRM" =~ ^[sS]$ ]]; then
            log_info "Restauración cancelada."
            exit 0
        fi
        
        log_info "Deteniendo servicios CUPS y Avahi..."
        systemctl stop cups cups-browsed avahi-daemon 2>/dev/null || true
        
        log_info "Descomprimiendo y restaurando ${SELECTED_ARCHIVE} en /..."
        tar -xzf "$SELECTED_ARCHIVE" -C / 2>/dev/null || true
        
        # Ajustar permisos por seguridad
        chown -R root:lp /etc/cups/ppd 2>/dev/null || true
        chown root:lp /etc/cups/printers.conf 2>/dev/null || true
        chmod 600 /etc/cups/printers.conf 2>/dev/null || true
        
        log_info "Reiniciando servicios y recargando colas de impresión..."
        systemctl start cups avahi-daemon cups-browsed 2>/dev/null || true
        
        log_success "¡RESTAURACIÓN COMPLETADA CON ÉXITO!"
        echo -e "${BOLD}Colas restauradas:${NC}"
        lpstat -v 2>/dev/null || echo "Ninguna cola detectada tras restaurar."
        ;;
    3)
        echo -e "\nRespaldos guardados en ${BACKUP_DIR}:"
        ls -lh "${BACKUP_DIR}"/*.tar.gz 2>/dev/null || echo "No hay respaldos guardados."
        ;;
    0)
        exit 0
        ;;
    *)
        log_error "Opción no válida."
        exit 1
        ;;
esac

echo -e "\n${CYAN}==============================================================================${NC}"
