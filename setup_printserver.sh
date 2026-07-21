#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: setup_printserver.sh
# Descripción: Script 1/3 - Instalación de dependencias, configuración de
#              grupos administrativos e inicialización de servicios para
#              impresoras térmicas Zebra GC420t y móviles Android (Mopria/IPP).
# ==============================================================================

set -euo pipefail

# Colores para salida en terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} ${BOLD}$1${NC}"; }
log_success() { echo -e "${GREEN}[OK]${NC} ${BOLD}$1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ------------------------------------------------------------------------------
# 1. Validación de Privilegios
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    log_error "Este script requiere privilegios de superusuario (root)."
    log_info "Por favor, ejecútalo utilizando sudo: ${YELLOW}sudo ./setup_printserver.sh${NC}"
    exit 1
fi

# Detectar el usuario real que invocó sudo (o el usuario actual si entró como root directo)
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
if [ "$REAL_USER" = "root" ]; then
    log_warn "Se está ejecutando como root directo. Es recomendable asignar un usuario estándar al grupo lpadmin."
    read -p "Introduce el nombre del usuario estándar para administrar CUPS (deja en blanco si solo usarás root): " INPUT_USER
    if [ -n "$INPUT_USER" ]; then
        REAL_USER="$INPUT_USER"
    fi
fi

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 🖨️  SKUNK PC: CONFIGURACIÓN BASE DE SERVIDOR DE IMPRESIÓN (PASO 1/4) ${NC}"
echo -e "${CYAN}==============================================================================${NC}"
log_info "Usuario administrador detectado para CUPS: ${YELLOW}${REAL_USER}${NC}"
echo ""

# ------------------------------------------------------------------------------
# 2. Actualización del Sistema e Instalación de Paquetes
# ------------------------------------------------------------------------------
log_info "Actualizando las listas de paquetes del sistema (apt-get update)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || {
    log_error "Fallo al actualizar los repositorios de paquetes. Verifica tu conexión a internet."
    exit 1
}

PACKAGES=(
    "cups"
    "cups-client"
    "cups-bsd"
    "cups-browsed"
    "cups-filters"
    "avahi-daemon"
    "avahi-utils"
    "printer-driver-foo2zjs"
    "usbutils"
    "udev"
)

log_info "Instalando paquetes obligatorios para impresión nativa e IPP/AirPrint/Mopria:"
for pkg in "${PACKAGES[@]}"; do
    echo -e "   -> ${CYAN}${pkg}${NC}"
done

apt-get install -y "${PACKAGES[@]}" || {
    log_error "Ocurrió un error al instalar uno o varios paquetes."
    exit 1
}
log_success "Todos los paquetes obligatorios han sido instalados correctamente."
echo ""

# ------------------------------------------------------------------------------
# 3. Configuración del Grupo Administrativo (lpadmin)
# ------------------------------------------------------------------------------
log_info "Configurando permisos administrativos para CUPS..."

if getent group lpadmin >/dev/null 2>&1; then
    if id "$REAL_USER" >/dev/null 2>&1; then
        usermod -aG lpadmin "$REAL_USER"
        log_success "Usuario '${REAL_USER}' añadido exitosamente al grupo 'lpadmin'."
        log_info "Nota: Es posible que '${REAL_USER}' deba cerrar y abrir sesión para que los permisos de grupo surtan efecto en la CLI sin sudo."
    else
        log_warn "El usuario '${REAL_USER}' no existe en el sistema. Omitiendo usermod."
    fi
else
    log_warn "El grupo 'lpadmin' no se encontró en el sistema después de instalar CUPS."
fi
echo ""

# ------------------------------------------------------------------------------
# 4. Habilitación e Inicialización de Servicios (Systemd)
# ------------------------------------------------------------------------------
log_info "Habilitando e iniciando servicios de impresión y descubrimiento ZeroConf (mDNS)..."

# Deshabilitar cups-browsed para EVITAR la creación automática no deseada de impresoras de red/USB
systemctl disable --now cups-browsed 2>/dev/null || true
SERVICES=("cups" "avahi-daemon")

for svc in "${SERVICES[@]}"; do
    if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1 || systemctl list-units --all "${svc}.service" >/dev/null 2>&1; then
        log_info "Activando ${svc}..."
        systemctl enable --now "$svc" || log_warn "No se pudo activar ${svc} automáticamente, intentando reinicio..."
        systemctl restart "$svc" || true
        
        if systemctl is-active --quiet "$svc"; then
            log_success "Servicio ${BOLD}${svc}${NC} en ejecución (Active: running)."
        else
            log_warn "El servicio ${svc} no está activo. Verifica con: systemctl status ${svc}"
        fi
    else
        log_warn "El servicio ${svc}.service no fue detectado en systemd."
    fi
done
echo ""

# ------------------------------------------------------------------------------
# 5. Resumen de Verificación y Próximos Pasos
# ------------------------------------------------------------------------------
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${BOLD} ✅  INSTALACIÓN BASE COMPLETADA EXITOSAMENTE ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "Resumen de estado:"
echo -e "  • Versión de CUPS instalada : ${BOLD}$(cups-config --version 2>/dev/null || echo 'Desconocida')${NC}"
echo -e "  • Estado de Avahi (mDNS)    : ${BOLD}$(systemctl is-active avahi-daemon 2>/dev/null || echo 'Inactivo')${NC}"
echo -e "  • Usuario Administrador     : ${BOLD}${REAL_USER} (en grupo lpadmin)${NC}"
echo -e "  • Soporte USB detectado     : ${BOLD}$(lsusb >/dev/null 2>&1 && echo 'OK' || echo 'Revisar')${NC}"
echo ""
echo -e "${CYAN}Próximo paso en la arquitectura Skunk PC:${NC}"
echo -e "👉 Proceder al ${BOLD}Paso 2${NC}: Configurar ${YELLOW}/etc/cups/cupsd.conf${NC} para permitir escucha en red,"
echo -e "   descubrimiento IPP/AirPrint/Mopria por subred Wi-Fi y políticas de acceso."
echo -e "${CYAN}==============================================================================${NC}"
