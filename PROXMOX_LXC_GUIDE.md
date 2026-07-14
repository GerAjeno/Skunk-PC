# 🖥️ Despliegue de Skunk-PC en Proxmox VE (Contenedor LXC Ubuntu)

¡Excelente decisión! Alojar el Servidor de Impresión Universal en un **Contenedor LXC (Linux Container)** de **Proxmox VE** aporta alta eficiencia, consumos mínimos de RAM/CPU y facilidad de respaldo.

Sin embargo, al estar virtualizado dentro de un contenedor LXC, existen **2 configuraciones críticas en el Host Proxmox** que se deben realizar antes de ejecutar los scripts dentro del contenedor:

1. **Pasarela USB (USB Passthrough):** Permitir que el contenedor LXC acceda físicamente a los puertos USB donde están conectadas las impresoras térmicas **Zebra GC420t**.
2. **Puente de Red Layer 2 (mDNS Broadcast):** Asegurar que los paquetes ZeroConf de Avahi lleguen al SSID Wi-Fi donde están conectados los teléfonos Android.

---

## 🛠️ PARTE 1: Configurar Pasarela USB en el Host Proxmox (Shell de PVE)

A diferencia de una Máquina Virtual (VM), los contenedores LXC comparten el kernel del host y requieren permisos explícitos para acceder a los dispositivos de caracteres USB (`/dev/bus/usb` y `/dev/usb/lp*`).

### Paso 1.1: Identificar los dispositivos en el Host Proxmox
1. Conecta tus impresoras **Zebra GC420t** a los puertos USB (o Hub USB) del servidor físico.
2. Abre la **Shell del Nodo Proxmox** (desde la interfaz web de Proxmox en tu navegador -> Selecciona el nodo PVE -> **Shell**) y ejecuta:
   ```bash
   lsusb
   ```
   Verás una salida parecida a esto:
   ```text
   Bus 001 Device 003: ID 0a5f:0080 Zebra GC420t
   Bus 001 Device 004: ID 0a5f:0080 Zebra GC420t
   ```
   *(Anotar el ID del fabricante `0a5f` para Zebra).*

3. Verifica si el kernel de Proxmox creó los nodos del módulo de impresora (`usblp`):
   ```bash
   ls -la /dev/usb/lp*
   ```
   *(Si existen, verás `/dev/usb/lp0`, `/dev/usb/lp1`, etc.)*.

---

### Paso 1.2: Editar el archivo de configuración del Contenedor LXC
Supongamos que el ID de tu contenedor Ubuntu en Proxmox es **`101`** (sustituye `101` por el ID real de tu contenedor).

1. En la misma Shell de Proxmox, edita el archivo de configuración del contenedor:
   ```bash
   nano /etc/pve/lxc/101.conf
   ```

2. **Añade las siguientes líneas al final del archivo** para otorgar acceso a los nodos USB y montarlos dentro del contenedor:

   ```conf
   # --- PASARELA USB PARA IMPRESORAS ZEBRA (SKUNK PC) ---
   # Permitir dispositivos USB crudos (Major 189) y colas de impresora usblp (Major 180)
   lxc.cgroup2.devices.allow: c 189:* rwm
   lxc.cgroup2.devices.allow: c 180:* rwm

   # Montar el bus USB para que lpinfo -v y lsusb funcionen en el LXC
   lxc.mount.entry: /dev/bus/usb /dev/bus/usb none bind,optional,create=dir 0 0

   # Montar las colas de dispositivos de impresión (si el host usa usblp)
   lxc.mount.entry: /dev/usb /dev/usb none bind,optional,create=dir 0 0
   ```

> [!IMPORTANT]
> **Contenedores Privilegiados vs. No Privilegiados (Unprivileged LXC):**
> Si al crear el contenedor en Proxmox seleccionaste **"Contenedor no privilegiado" (Unprivileged = Sí)**, el usuario `root` dentro del contenedor se mapea a un usuario sin privilegios en el host y no podrá leer los puertos USB aunque estén montados.
> 
> **Solución Recomendada en Proxmox:**
> Para servidores de hardware (como un Print Server con múltiples USB), es mucho más sencillo e industrial ejecutar un **Contenedor Privilegiado (`unprivileged: 0`)**. Si tu contenedor actual es no privilegiado, puedes hacer un respaldo rápido en Proxmox y restaurarlo desmarcando la casilla *"Unprivileged container"*, o crear las reglas de mapeo `udev` en el host (ver sección de Troubleshooting).

3. Guarda el archivo en nano (`Ctrl + O`, `Enter`, `Ctrl + X`).
4. **Reinicia el contenedor Ubuntu** desde la interfaz web de Proxmox o por comando:
   ```bash
   pct stop 101 && pct start 101
   ```

---

### Paso 1.3: Verificar el passthrough dentro del Contenedor LXC
Ahora entra a la terminal o consola de tu contenedor Ubuntu (`pct enter 101`) y comprueba que ve el hardware:
```bash
lsusb | grep -i zebra
```
*Si la impresora aparece listada en pantalla, **¡el passthrough USB es un éxito!***

---

## 🌐 PARTE 2: Configuración del Puente de Red (Network Bridge) en Proxmox

Para que las alertas **mDNS/ZeroConf de Avahi** (`_ipp._tcp.local`) salgan del contenedor Ubuntu y sean recibidas por el router Wi-Fi hacia los teléfonos Android:

1. En la interfaz web de Proxmox, selecciona tu contenedor Ubuntu -> **Red (Network)**.
2. Verifica que el dispositivo de red (`net0`) esté conectado al puente principal del host (generalmente **`vmbr0`**) y tenga asignada una IP en la **misma subred LAN/Wi-Fi de la fábrica o local** (por DHCP o IP Estática en el mismo rango, ej. `192.168.1.X / 24`).
3. **No utilices redes NAT ocultas** para este contenedor, ya que el protocolo mDNS (Puerto 5353 UDP multicast) no atraviesa routers NAT por defecto sin un repetidor avahi.

---

## 🚀 PARTE 3: Instalación de Skunk-PC dentro del Contenedor Ubuntu

Una vez verificado `lsusb` dentro de tu contenedor Ubuntu, sigue estos 3 pasos simples en la consola del contenedor:

```bash
# 1. Actualizar el sistema e instalar git
sudo apt update && sudo apt install -y git

# 2. Clonar el repositorio del proyecto
git clone https://github.com/GerAjeno/Skunk-PC.git
cd Skunk-PC

# 3. Dar permisos e iniciar el Panel Interactivo de Orquestación
chmod +x *.sh
sudo ./skunk_manager.sh
```

Dentro del menú de `skunk_manager.sh`:
* Pulsa **`[1]`** para instalar CUPS, Avahi y drivers `foo2zjs`.
* Pulsa **`[2]`** para configurar `cupsd.conf` para la red local.
* Pulsa **`[3]`** para escanear las Zebra por USB y crear las colas `Zebra_GC420t_Caja_1`.
* Pulsa **`[4]`** para hacer la primera prueba ZPL de impresión.

---

## 🔧 Solución de Problemas Específicos en Proxmox LXC

* **Error `Permission denied` al imprimir por USB en contenedor No Privilegiado:**
  Si prefieres mantener el contenedor como no privilegiado, ejecuta esto en la **Shell del Host Proxmox (PVE)** para dar permisos globales de lectura/escritura al bus USB térmico:
  ```bash
  # En el HOST Proxmox:
  chmod -R 666 /dev/bus/usb/
  chmod 666 /dev/usb/lp* 2>/dev/null || true
  ```
* **El teléfono Android está en otro VLAN Wi-Fi separado de `vmbr0`:**
  Si la empresa tiene un SSID "Invitados/Móviles" en una VLAN diferente al contenedor de Proxmox, debes activar la opción **"mDNS Reflector / Avahi Repeater"** en el router corporativo (o MikroTik/PfSense/UniFi) para permitir el reenvío del puerto `5353 UDP` entre VLANs.
