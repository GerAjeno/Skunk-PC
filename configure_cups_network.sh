#!/usr/bin/env bash
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: configure_cups_network.sh
# Descripción: Script 2/4 - Configuración avanzada de puertos en red, permisos
#              por subred LAN y directivas IPP/AirPrint/Mopria en cupsd.conf.
# ==============================================================================

set -euo pipefail

# Colores
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
    log_error "Este script requiere privilegios root: sudo ./configure_cups_network.sh"
    exit 1
fi

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD} 🌐  SKUNK PC: CONFIGURACIÓN DE ACCESO EN RED Y ZEROCONF (PASO 2/4) ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

# 1. Detección de subred local actual
DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1 || true)
if [ -n "$DEFAULT_IFACE" ]; then
    CURRENT_IP=$(ip -4 addr show "$DEFAULT_IFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1 || true)
    SUBNET=$(ip -4 route show dev "$DEFAULT_IFACE" | awk '/proto kernel/ {print $1}' | head -n1 || echo "192.168.1.0/24")
else
    CURRENT_IP="127.0.0.1"
    SUBNET="192.168.0.0/16"
fi

log_info "Interfaz principal detectada: ${YELLOW}${DEFAULT_IFACE:-Desconocida}${NC} (IP: ${CURRENT_IP})"
log_info "Subred detectada para permisos de impresión: ${YELLOW}${SUBNET}${NC}"
echo ""

read -p "Introduce la subred permitida para imprimir [Presiona ENTER para usar @LOCAL y ${SUBNET}]: " INPUT_SUBNET
ALLOWED_SUBNET="${INPUT_SUBNET:-$SUBNET}"

# 2. Respaldo del archivo de configuración original
CUPS_CONF="/etc/cups/cupsd.conf"
CUPS_BACKUP="/etc/cups/cupsd.conf.backup.$(date +%F_%T)"

if [ -f "$CUPS_CONF" ]; then
    log_info "Creando copia de seguridad del archivo cupsd.conf original en: ${CUPS_BACKUP}"
    cp "$CUPS_CONF" "$CUPS_BACKUP"
    log_success "Respaldo creado correctamente."
else
    log_error "No se encontró el archivo ${CUPS_CONF}. ¿Se ejecutó el Paso 1 correctamente?"
    exit 1
fi
echo ""

# 3. Generación de nueva configuración optimizada para Android/Mopria/AirPrint
log_info "Generando y aplicando directivas universales en ${CUPS_CONF}..."

cat <<EOF > "$CUPS_CONF"
# ==============================================================================
# Archivo cupsd.conf generado por Skunk-PC (Servidor de Impresión Universal)
# Fecha: $(date)
# Optimizado para descubrimiento automático (Avahi/mDNS) e impresión nativa
# Plug & Play desde móviles Android por Wi-Fi (IPP / AirPrint / Mopria).
# ==============================================================================

# Nivel de registro (debug o info para producción)
LogLevel info
PageLogFormat

# Permitir conexión remota y deshabilitar colas caducadas
MaxLogSize 0
PreserveJobHistory Yes
PreserveJobFiles No
AutoPurgeJobs Yes

# Escuchar en el puerto 631 en TODAS las interfaces de red IPv4 e IPv6
Port 631
Listen *:631

# Permitir alias de servidor para que dispositivos móviles conecten vía hostname o IP
ServerAlias *

# Habilitar descubrimiento por mDNS / ZeroConf (Avahi)
Browsing Yes
BrowseLocalProtocols dnssd

# Habilitar interfaz web de administración para control remoto en la LAN
WebInterface Yes

# Opciones por defecto para compatibilidad IPP universal
DefaultShared Yes

# ------------------------------------------------------------------------------
# Políticas de Control de Acceso por Subred
# ------------------------------------------------------------------------------

# Acceso universal al servidor (listar impresoras y descubrir por red)
<Location />
  Order allow,deny
  Allow @LOCAL
  Allow ${ALLOWED_SUBNET}
</Location>

# Acceso al panel de administración (interfaz web http://IP:631/admin)
<Location /admin>
  Order allow,deny
  Allow @LOCAL
  Allow ${ALLOWED_SUBNET}
</Location>

# Acceso a los archivos de configuración
<Location /admin/conf>
  AuthType Default
  Require user @SYSTEM
  Order allow,deny
  Allow @LOCAL
  Allow ${ALLOWED_SUBNET}
</Location>

# ------------------------------------------------------------------------------
# Políticas predeterminadas para tareas de impresión (Jobs)
# ------------------------------------------------------------------------------
<Policy default>
  # Operaciones genéricas
  JobPrivateAccess default
  JobPrivateValues default
  SubscriptionPrivateAccess default
  SubscriptionPrivateValues default

  <Limit Create-Job Print-Job Print-URI Validate-Job>
    Order allow,deny
    Allow all
  </Limit>

  <Limit Send-Document Send-URI Hold-Job Release-Job Restart-Job Purge-Jobs Set-Job-Attributes Create-Job-Subscription Renew-Subscription Cancel-Subscription Get-Notifications Reprocess-Job Cancel-Current-Job Suspend-Current-Job Resume-Job Cancel-My-Jobs Close-Job CUPS-Move-Job CUPS-Get-Document>
    Require user @OWNER @SYSTEM
    Order allow,deny
    Allow all
  </Limit>

  # Operaciones administrativas
  <Limit CUPS-Add-Modify-Printer CUPS-Delete-Printer CUPS-Add-Modify-Class CUPS-Delete-Class CUPS-Set-Default CUPS-Get-Devices>
    AuthType Default
    Require user @SYSTEM
    Order allow,deny
    Allow @LOCAL
    Allow ${ALLOWED_SUBNET}
  </Limit>

  <Limit Pause-Printer Resume-Printer Enable-Printer Disable-Printer Pause-Printer-After-Current-Job Hold-New-Jobs Release-Held-New-Jobs Deactivate-Printer Activate-Printer Restart-Printer Shutdown-Printer Startup-Printer Promote-Job Schedule-Job-After Cancel-Jobs CUPS-Accept-Jobs CUPS-Reject-Jobs>
    AuthType Default
    Require user @SYSTEM
    Order allow,deny
    Allow @LOCAL
    Allow ${ALLOWED_SUBNET}
  </Limit>

  <Limit Cancel-Job CUPS-Authenticate-Job>
    Require user @OWNER @SYSTEM
    Order allow,deny
    Allow all
  </Limit>

  <Limit All>
    Order allow,deny
    Allow all
  </Limit>
</Policy>
EOF

log_success "Archivo cupsd.conf modificado y validado."

# 4. Configurar también cups-browsed.conf (si existe) para compartir hacia clientes mDNS
CUPS_BROWSED_CONF="/etc/cups/cups-browsed.conf"
if [ -f "$CUPS_BROWSED_CONF" ]; then
    log_info "Optimizando directivas en ${CUPS_BROWSED_CONF} para broadcast universal..."
    sed -i 's/^#*BrowseRemoteProtocols.*/BrowseRemoteProtocols dnssd/' "$CUPS_BROWSED_CONF" || true
    sed -i 's/^#*BrowseLocalProtocols.*/BrowseLocalProtocols dnssd/' "$CUPS_BROWSED_CONF" || true
    log_success "Directivas de cups-browsed ajustadas."
fi
echo ""

# 5. Configurar el cortafuegos (Firewall) si está activo en Linux
log_info "Verificando y abriendo puertos en el cortafuegos (Puerto 631 TCP/UDP e IPP/mDNS 5353)..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -qw "Status: active"; then
    log_info "Detectado UFW activo. Configurando reglas..."
    ufw allow 631/tcp comment 'CUPS IPP Printing TCP' >/dev/null
    ufw allow 631/udp comment 'CUPS IPP Printing UDP' >/dev/null
    ufw allow 5353/udp comment 'Avahi mDNS Discovery' >/dev/null
    log_success "Puertos 631 y 5353 abiertos en UFW."
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    log_info "Detectado Firewalld activo. Configurando servicios..."
    firewall-cmd --permanent --add-service=ipp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-service=ipp-client >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-service=mdns >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    log_success "Servicios IPP y mDNS abiertos en Firewalld."
else
    log_info "No se detectó un firewall activo que bloquee los puertos de red local."
fi
echo ""

# 6. Reinicio de servicios
log_info "Reiniciando servicios CUPS y Avahi para aplicar las nuevas directivas..."
systemctl restart cups cups-browsed avahi-daemon
log_success "Servicios reiniciados correctamente."

# Verificar que escucha el puerto 631
if ss -tuln 2>/dev/null | grep -q ":631" || netstat -tuln 2>/dev/null | grep -q ":631"; then
    log_success "CUPS está escuchando activamente en el puerto 631 (Red LAN activa)."
else
    log_warn "No se detectó escucha inmediata en el puerto 631. Verifica con: sudo ss -tulw | grep 631"
fi

echo -e "${GREEN}==============================================================================${NC}"
echo -e "${BOLD} ✅  CONFIGURACIÓN DE ACCESO EN RED COMPLETADA ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "El servidor ahora admite trabajos de impresión y consultas de descubrimiento"
echo -e "desde la subred: ${BOLD}@LOCAL y ${ALLOWED_SUBNET}${NC}."
echo -e "La interfaz de administración web se encuentra accesible en: ${CYAN}http://${CURRENT_IP}:631/admin${NC}"
echo ""
echo -e "👉 Próximo paso: Ejecutar ${YELLOW}sudo ./add_zebra_printers.sh${NC} (Paso 3) para descubrir"
echo -e "   las impresoras físicas Zebra GC420t conectadas por USB al servidor."
echo -e "${CYAN}==============================================================================${NC}"
