# 🐧 Configuración en Proxmox VE: Contenedor LXC (Ubuntu Server) + USB Passthrough + mDNS

Desplegar el **Servidor de Impresión Skunk-PC** dentro de un Contenedor LXC en **Proxmox VE** es una excelente decisión de arquitectura, ya que consume muy pocos recursos (RAM/CPU) y se levanta en segundos. Sin embargo, al estar virtualizado en un contenedor, hay **dos requisitos críticos de infraestructura** que debes configurar en el host Proxmox antes o durante la instalación para que las impresoras USB físicas sean accesibles y los celulares Android detecten el servicio por Wi-Fi.

---

## 🏗️ Requisito 1: Modo de Red en Proxmox (Puente Layer 2 / `vmbr0`)

Para que el protocolo **Avahi (mDNS / ZeroConf - UDP 5353)** pueda anunciar las impresoras y que los celulares Android las descubran automáticamente sin drivers:

1. El contenedor LXC **NO debe estar tras un NAT interno de Proxmox**.
2. En la configuración de Red del contenedor en Proxmox (**LXC -> Network -> Bridge**), asegúrate de que esté conectado al puente principal de la LAN (generalmente **`vmbr0`**).
3. Asígnale una **IP Estática** (ej. `192.168.1.100/24`) o reserva de DHCP en tu router corporativo, de modo que el contenedor esté en la **misma subred local (o VLAN)** a la que se conectan los teléfonos móviles Android por Wi-Fi.

---

## 🔌 Requisito 2: Pasarela USB del Host Proxmox al Contenedor LXC (USB Passthrough)

Por defecto, los contenedores LXC están aislados del hardware físico del servidor Proxmox (`/dev/bus/usb/` y `/dev/usb/lpX`). Para que el contenedor Ubuntu detecte las impresoras **Zebra GC420t**, debemos mapear los dispositivos USB del host Proxmox al contenedor.

### Paso A: Identificar los ID de las impresoras Zebra en la consola del HOST Proxmox
1. Abre la **Shell (Terminal) del Nodo Proxmox** (el hipervisor root, NO el contenedor).
2. Conecta las impresoras Zebra (o el Hub USB industrial) y ejecuta:
   ```bash
   lsusb
   ```
3. Verás líneas similares a:
   ```text
   Bus 001 Device 004: ID 0a5f:0080 Zebra GC420t
   ```
   *El vendedor de Zebra es `0a5f`. Toma nota de que están en la clase USB impresora o en los nodos `/dev/usb/lp0`, `/dev/bus/usb/001/004`, etc.*

4. Verifica también qué archivos de dispositivo de impresora generó el kernel de Proxmox en el host:
   ```bash
   ls -l /dev/usb/lp* /dev/bus/usb/*/*
   ```

---

### Paso B: Configurar el Passthrough en el archivo `.conf` del Contenedor en Proxmox

Supongamos que tu contenedor Ubuntu Server 26.04 tiene el **ID 101** (sustituye por el ID real en Proxmox, ej. `100`, `102`...).

1. En la consola SSH del **Host Proxmox**, edita el archivo de configuración del contenedor:
   ```bash
   nano /etc/pve/lxc/101.conf
   ```
2. Añade las siguientes líneas al final del archivo para permitir el acceso a dispositivos de impresora (`cgroup2` para Proxmox VE 8+ o `cgroup` si es PVE 7) y montar las rutas USB:

   ```ini
   # --- SKUNK-PC: PASARELA USB PARA IMPRESORAS ZEBRA ---
   # Permitir dispositivos de caracteres USB (Bus genérico 189:* e impresoras lp 180:*)
   lxc.cgroup2.devices.allow: c 180:* rwm
   lxc.cgroup2.devices.allow: c 189:* rwm

   # Montar el bus USB completo y los puertos de impresora dentro del contenedor
   lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir 0 0
   lxc.mount.entry: /dev/usb dev/usb none bind,optional,create=dir 0 0
   ```
   *(Nota: Si tu contenedor es **No Privilegiado / Unprivileged (ID de usuario remapeado 100000+)**, para evitar errores de permisos `Permission denied` en el USB, se recomienda asignar el contenedor como **Privileged** en Proxmox o ajustar el chown/chmod en `/etc/udev/rules.d/` en el host Proxmox para que el grupo 100000+ pueda leer `/dev/usb/lp*`).*

3. Guarda el archivo (`Ctrl + O`, `Enter`, `Ctrl + X`).
4. **Reinicia el contenedor** desde la web de Proxmox o por terminal:
   ```bash
   pct stop 101 && pct start 101
   ```

---

## 💻 Paso 3: Instalación del Proyecto dentro del Contenedor Ubuntu Server

Ahora entra a la consola o SSH **dentro del contenedor Ubuntu Server** y ejecuta la instalación del proyecto Skunk-PC:

### 1. Instalar Git y Clonar el Repositorio
```bash
sudo apt-get update && sudo apt-get install -y git curl
git clone https://github.com/GerAjeno/Skunk-PC.git
cd Skunk-PC
```

### 2. Verificar que el Contenedor detecta el USB del Host Proxmox
Antes de correr los scripts, comprueba en la terminal del contenedor que la pasarela USB funcionó:
```bash
lsusb
ls -l /dev/usb/lp* 2>/dev/null || ls -l /dev/bus/usb/*/* 2>/dev/null
```
*Si ves las impresoras Zebra o los nodos en `/dev/`, el hardware está perfectamente conectado al contenedor.*

### 3. Ejecutar el Panel Unificado (`skunk_manager.sh`)
```bash
sudo chmod +x *.sh
sudo ./skunk_manager.sh
```

Dentro del menú interactivo de `skunk_manager.sh`:
* Pulsa **`[1]`** para instalar `cups`, `avahi-daemon`, `cups-browsed` y `foo2zjs`.
* Pulsa **`[2]`** para configurar `cupsd.conf` con escucha en red e IPP/AirPrint.
* Pulsa **`[3]`** para escanear y agregar las impresoras Zebra por USB.
* Pulsa **`[4]`** para verificar la publicación mDNS y realizar la prueba de impresión ZPL de diagnóstico.

---

## 🚨 Solución a Errores Específicos de Contenedores LXC

### 1. `avahi-daemon` falla al iniciar con error "chroot / rlimit"
En algunos contenedores LXC Ubuntu, Avahi intenta establecer límites de recursos que el kernel del contenedor prohíbe.
Si al ejecutar el Paso 1 ves que `avahi-daemon` no inicia:
1. Edita el archivo de Avahi:
   ```bash
   sudo nano /etc/avahi/avahi-daemon.conf
   ```
2. Busca la sección `[server]` y asegúrate de que estas opciones estén configuradas así:
   ```ini
   use-ipv4=yes
   use-ipv6=no
   allow-interfaces=eth0
   rlimit-nproc=0
   ```
3. Reinicia Avahi:
   ```bash
   sudo systemctl restart avahi-daemon
   sudo systemctl status avahi-daemon
   ```

### 2. CUPS o `lp -d` da "Permission denied" sobre `/dev/usb/lp0` en Contenedor No Privilegiado
Si el contenedor está en modo *Unprivileged (No Privilegiado)*, el ID real del usuario en el host Proxmox es `100000 + ID_interno`.
**Solución rápida y limpia en Proxmox:**
* En el **Host Proxmox**, edita un archivo de reglas udev para dar permisos globales de lectura/escritura a las impresoras USB:
  ```bash
  echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0a5f", MODE="0666"' > /etc/udev/rules.d/99-zebra-usb.rules
  echo 'SUBSYSTEM=="usb_printer", MODE="0666"' >> /etc/udev/rules.d/99-zebra-usb.rules
  udevadm control --reload-rules && udevadm trigger
  ```
  O alternativamente, convierte el contenedor en **Privilegiado (Privileged container: Yes)** en Proxmox realizando un Backup del contenedor y restaurándolo marcando la casilla *"Privileged"*.
