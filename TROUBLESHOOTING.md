# 🔧 Guía de Depuración y Diagnóstico de Problemas (Troubleshooting Checklist)

Esta guía documenta los procedimientos de verificación avanzada, comandos de terminal de diagnóstico y resolución de problemas comunes en planta o almacén cuando los teléfonos Android (o el servidor CUPS) no detectan o no imprimen en las impresoras **Zebra GC420t**.

---

## 📋 Lista de Verificación Previa (Checklist Rápido)

Antes de realizar pruebas con los teléfonos móviles, ejecuta en la terminal del servidor Skunk PC:

```bash
sudo ./diagnose_printserver.sh
```

O verifica manualmente cada punto crítico con los siguientes comandos:

### 1. Estado y Cola del Servidor CUPS (`lpstat`)
Verifica que el demonio de CUPS está en ejecución y las colas no se encuentran pausadas ni rechazando tareas:
```bash
# Ver estado general del demonio y colas activas
lpstat -r -p -d -v
```
* **Indicador de Éxito (`lpstat -r`):** `scheduler is running`
* **Indicador de Éxito (`lpstat -p`):** `printer Zebra_GC420t_Caja_1 is idle. enabled since ...`
* **Si una impresora aparece como `stopped` o `disabled`:**
  ```bash
  sudo cupsenable Zebra_GC420t_Caja_1
  sudo cupsaccept Zebra_GC420t_Caja_1
  ```

---

### 2. Publicación de Registros mDNS/ZeroConf (`avahi-browse`)
Para que Android descubra la impresora en el menú emergente sin instalar drivers, **Avahi** debe estar anunciando el servicio IPP en la subred local (`_ipp._tcp.local` / `_pdl-datastream._tcp.local`):
```bash
# Escuchar en tiempo real los servicios de impresión anunciados por Avahi
avahi-browse -rt _ipp._tcp
```
* **Salida esperada:**
  ```text
  + enp3s0 IPv4 Zebra_GC420t_Caja_1 @ Skunk-PC        Internet Printer     local
  = enp3s0 IPv4 Zebra_GC420t_Caja_1 @ Skunk-PC        Internet Printer     local
     hostname = [Skunk-PC.local]
     address = [192.168.1.100]
     port = [631]
     txt = ["pdl=application/vnd.cups-raw,application/octet-stream" "printer-is-shared=true" ...]
  ```
* **Si no aparece ningún registro:**
  1. Verifica el servicio: `sudo systemctl status avahi-daemon`
  2. Asegúrate de que `cups-browsed` está corriendo: `sudo systemctl status cups-browsed`
  3. Reinicia la comunicación: `sudo systemctl restart avahi-daemon cups-browsed`

---

### 3. Conectividad Física y Permisos USB (`lsusb` y `lpinfo -v`)
Si CUPS no envía datos al cable USB, verifica la comunicación en la capa física del kernel Linux:
```bash
# Listar dispositivos USB de Zebra
lsusb | grep -i zebra

# Listar URIs reconocidos por CUPS
sudo lpinfo -v | grep -i usb://
```
* **Solución de problemas de permisos USB:**
  Si `lpinfo -v` muestra la impresora pero los trabajos fallan por permisos de acceso (`Permission denied on /dev/usb/lp0`), verifica que el usuario `cups` tenga acceso al grupo `lp`:
  ```bash
  sudo usermod -aG lp cups
  sudo usermod -aG lp root
  sudo udevadm control --reload-rules && sudo udevadm trigger
  ```

---

### 4. Prueba de Impresión por Línea de Comandos (ZPL II Directo)
Las impresoras **Zebra GC420t** entienden de forma nativa los lenguajes térmicos **ZPL II** y **EPL2**. El método más confiable para verificar que el hardware imprime es enviar una cadena ZPL en formato bruto (`-o raw`):

```bash
# Crear un archivo de prueba ZPL rápido y enviarlo a la cola CUPS en modo raw
echo -e "^XA^FO50,50^A0N,50,50^FDPRUEBA DE PLANTA OK^FS^XZ" | lp -d Zebra_GC420t_Caja_1 -o raw
```
* Si la etiqueta térmica sale impresa en menos de 1 segundo con el texto **"PRUEBA DE PLANTA OK"**, la comunicación hardware + CUPS es 100% exitosa.

---

## 📱 Solución de Problemas en Smartphones Android

### Problema A: La impresora no aparece en el menú "Imprimir" de Chrome en Android
1. **Verificar Subred y Aislamiento de Red Wi-Fi (AP Isolation / Client Isolation):**
   Muchos routers o access points corporativos tienen activada la función *"Client Isolation"* en el SSID Wi-Fi. Esto impide que el móvil (ej. IP `192.168.1.50`) se comunique por mDNS con el servidor Skunk PC (`192.168.1.100`).
   * **Prueba:** Abre Chrome en Android y entra a `http://192.168.1.100:631` (la IP de tu servidor Skunk PC). Si no abre la página web de CUPS, hay un bloqueo de firewall o aislamiento en el Wi-Fi de la empresa.
2. **Revisar el Servicio Nativo de Impresión:**
   En Android, ve a **Ajustes -> Conexiones -> Más ajustes de conexión -> Impresión -> Servicio de impresión predeterminado** (o servicio **Mopria Print Service** si se instaló). Asegúrate de que esté **Activado (`ON`)**.

### Problema B: La impresora aparece en Android, pero al dar "Imprimir" da error o se queda "Enviando"
1. **Revisar Políticas de Acceso por Subred en `cupsd.conf`:**
   Asegúrate de haber configurado en `configure_cups_network.sh` el rango de subred exacto desde donde navega el teléfono Android (por ejemplo `Allow 192.168.1.0/24` en la directiva `<Location />` y `<Limit All>`).
2. **Revisar el archivo de error log de CUPS:**
   ```bash
   sudo tail -f /var/log/cups/error_log
   ```
   Si observas `Filter failed` o `Job stopped due to printer error`:
   * Verifica si la impresora se quedó sin papel térmico o la tapa está mal cerrada (la luz indicadora de la Zebra parpadea en rojo o ámbar).
   * Vuelve a aplicar la política de reintento: `sudo lpadmin -p Zebra_GC420t_Caja_1 -o printer-error-policy=retry-job`
