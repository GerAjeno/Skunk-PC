#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ==============================================================================
# Proyecto: Skunk PC - Servidor de Impresión Universal (CUPS + Avahi / ZeroConf)
# Archivo: skunk_webui.py
# Descripción: Interfaz Web de Gestión Integral (Web UI Dashboard) basada en
#              Flask para administrar colas, red, pruebas térmicas y respaldos.
# ==============================================================================

import os
import subprocess
import re
import socket
import json
from flask import Flask, render_template_string, request, jsonify, send_file, session, redirect, url_for

app = Flask(__name__, static_folder=os.path.join(os.path.dirname(os.path.abspath(__file__)), "static"), static_url_path="/static")
app.secret_key = os.environ.get("SKUNK_SECRET_KEY", "SkunkPC_SuperSecret_2026_Key_Secure")

# Contraseña de acceso al portal Web UI (Predeterminada: Lasgarzas911)
ADMIN_PASSWORD = os.environ.get("SKUNK_WEBUI_PASSWORD", "Lasgarzas911")

# Directorio base y de respaldos
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BACKUP_DIR = "/var/backups/skunk-pc"
os.makedirs(BACKUP_DIR, exist_ok=True)

def run_cmd(cmd_list):
    try:
        env = os.environ.copy()
        env["LC_ALL"] = "C"
        res = subprocess.run(cmd_list, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15, env=env)
        return res.returncode == 0, res.stdout.strip(), res.stderr.strip()
    except Exception as e:
        return False, "", str(e)

def get_system_status():
    cups_ok, _, _ = run_cmd(["systemctl", "is-active", "cups"])
    avahi_ok, _, _ = run_cmd(["systemctl", "is-active", "avahi-daemon"])
    watchdog_ok, _, _ = run_cmd(["systemctl", "is-active", "skunk-watchdog.timer"])
    
    # Obtener subredes en cupsd.conf
    subnets = []
    if os.path.exists("/etc/cups/cupsd.conf"):
        with open("/etc/cups/cupsd.conf", "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("Allow ") and not line.startswith("Allow all"):
                    sub = line.split("Allow ")[1].strip()
                    if sub not in subnets and sub != "127.0.0.1":
                        subnets.append(sub)
                        
    # Obtener IP local del servidor
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        server_ip = s.getsockname()[0]
        s.close()
    except:
        server_ip = "127.0.0.1"
        
    return {
        "cups": "running" if cups_ok else "stopped",
        "avahi": "running" if avahi_ok else "stopped",
        "watchdog": "active" if watchdog_ok else "inactive",
        "server_ip": server_ip,
        "subnets": subnets
    }

def get_printers():
    ok, stdout, _ = run_cmd(["lpstat", "-v"])
    printers = []
    if not ok or not stdout:
        return printers
        
    for line in stdout.split("\n"):
        line = line.strip()
        if not line:
            continue
        match = re.match(r"^(?:device for|dispositivo para)\s+([^:]+):\s+(.*)$", line, re.IGNORECASE)
        if match:
            pname = match.group(1).strip()
            uri = match.group(2).strip()
            
            # Obtener estado
            s_ok, s_out, _ = run_cmd(["lpstat", "-p", pname])
            status = "idle"
            s_lower = s_out.lower()
            if "idle" in s_lower or "inactiva" in s_lower or "libre" in s_lower:
                status = "idle"
            elif "printing" in s_lower or "imprimiendo" in s_lower:
                status = "printing"
            elif "stopped" in s_lower or "disabled" in s_lower or "detenida" in s_lower or "desactivada" in s_lower:
                status = "stopped"
                
            printers.append({
                "name": pname,
                "uri": uri,
                "status": status,
                "raw_status": s_out
            })
    return printers

def get_usb_devices():
    ok, stdout, _ = run_cmd(["lpinfo", "-v"])
    usb_list = []
    if ok and stdout:
        for line in stdout.split("\n"):
            line = line.strip()
            if "usb://" in line:
                parts = line.split("usb://", 1)
                uri = "usb://" + parts[1].strip()
                if uri not in usb_list:
                    usb_list.append(uri)
    return usb_list

LOGIN_TEMPLATE = """
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Acceso Seguro - Skunk PC Portal</title>
    <link rel="icon" type="image/png" href="/static/icon.png">
    <link rel="apple-touch-icon" href="/static/icon.png">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;600;700;800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
    <script>
        (function() {
            const saved = localStorage.getItem('skunk_theme') || 'amoled';
            document.documentElement.setAttribute('data-theme', saved);
        })();
        function toggleTheme() {
            const current = document.documentElement.getAttribute('data-theme');
            const next = current === 'light' ? 'amoled' : 'light';
            document.documentElement.setAttribute('data-theme', next);
            localStorage.setItem('skunk_theme', next);
            updateThemeBtn();
        }
        function updateThemeBtn() {
            const btn = document.getElementById('theme-toggle-btn');
            if (btn) {
                const current = document.documentElement.getAttribute('data-theme');
                btn.innerHTML = current === 'light' ? '🌑 AMOLED Oscuro' : '☀️ Modo Claro';
            }
        }
        window.addEventListener('DOMContentLoaded', updateThemeBtn);
    </script>
    <style>
        :root, [data-theme="amoled"] {
            --bg: #000000;
            --card-bg: #000000;
            --border: rgba(255, 255, 255, 0.22);
            --primary: #38bdf8;
            --danger: #f43f5e;
            --text: #ffffff;
            --subtext: #a1a1aa;
            --grad-start: #000000;
            --grad-end: #000000;
        }
        [data-theme="light"] {
            --bg: #f8fafc;
            --card-bg: rgba(255, 255, 255, 0.95);
            --border: rgba(15, 23, 42, 0.15);
            --primary: #0284c7;
            --danger: #e11d48;
            --text: #0f172a;
            --subtext: #475569;
            --grad-start: #e2e8f0;
            --grad-end: #f8fafc;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Inter', sans-serif;
            background: radial-gradient(circle at top right, var(--grad-start), var(--grad-end) 70%);
            color: var(--text);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 1.5rem;
            transition: background 0.3s, color 0.3s;
        }
        .login-card {
            background: var(--card-bg);
            backdrop-filter: blur(16px);
            border: 1px solid var(--border);
            border-radius: 24px;
            padding: 2.5rem;
            width: 100%;
            max-width: 440px;
            box-shadow: 0 20px 50px rgba(0,0,0,0.5);
            text-align: center;
            transition: background 0.3s, border-color 0.3s;
        }
        .logo-icon { font-size: 3rem; margin-bottom: 1rem; display: inline-block; }
        h2 { font-family: 'Outfit', sans-serif; font-size: 1.6rem; margin-bottom: 0.5rem; color: var(--text); }
        p { color: var(--subtext); font-size: 0.9rem; margin-bottom: 2rem; }
        .form-group { margin-bottom: 1.5rem; text-align: left; }
        label { display: block; font-size: 0.85rem; color: var(--subtext); margin-bottom: 8px; font-weight: 500; }
        input[type="password"] {
            width: 100%;
            padding: 14px;
            background: transparent;
            border: 1px solid var(--border);
            border-radius: 12px;
            color: var(--text);
            font-size: 1rem;
            transition: border-color 0.2s;
        }
        input[type="password"]:focus { outline: none; border-color: var(--primary); }
        .btn-submit {
            background: linear-gradient(135deg, var(--primary), #0284c7);
            color: #0b1120;
            font-weight: 700;
            border: none;
            padding: 14px;
            border-radius: 12px;
            width: 100%;
            font-size: 1rem;
            cursor: pointer;
            transition: all 0.2s;
            font-family: 'Outfit', sans-serif;
        }
        .btn-submit:hover { filter: brightness(1.15); transform: translateY(-2px); }
        .btn-submit:active, .theme-btn:active {
            transform: scale(0.93) translateY(2px) !important;
            filter: brightness(0.85) !important;
            box-shadow: inset 0 3px 6px rgba(0,0,0,0.5) !important;
            transition: all 0.05s ease !important;
        }
        .error-msg {
            background: rgba(244, 63, 94, 0.15);
            border: 1px solid rgba(244, 63, 94, 0.3);
            color: var(--danger);
            padding: 10px;
            border-radius: 10px;
            font-size: 0.85rem;
            margin-bottom: 1.5rem;
        }
        .theme-btn {
            background: transparent;
            border: 1px solid var(--border);
            color: var(--text);
            padding: 8px 16px;
            border-radius: 99px;
            font-size: 0.8rem;
            cursor: pointer;
            margin-top: 1.5rem;
            transition: all 0.2s;
        }
        .theme-btn:hover { background: rgba(128,128,128,0.1); }
    </style>
</head>
<body>
    <div class="login-card">
        <img src="/static/icon.png" alt="Skunk PC Logo" style="width: 86px; height: 86px; object-fit: contain; margin-bottom: 1rem; filter: drop-shadow(0 4px 12px rgba(56, 189, 248, 0.25));">
        <h2>Skunk PC Print Server</h2>
        <p>Introduce la contraseña de seguridad para administrar las colas de impresión de la nave.</p>
        {% if error %}
        <div class="error-msg">❌ {{ error }}</div>
        {% endif %}
        <form method="POST" action="/login" onsubmit="document.querySelector('.btn-submit').innerHTML = '⏳ Entrando al portal...'; document.querySelector('.btn-submit').style.opacity = '0.8';">
            <div class="form-group">
                <label>Contraseña de Acceso al Portal</label>
                <input type="password" name="password" placeholder="••••••••••••" required autofocus>
            </div>
            <button type="submit" class="btn-submit">Entrar al Portal</button>
        </form>
        <button type="button" id="theme-toggle-btn" onclick="toggleTheme()" class="theme-btn">☀️ Modo Claro</button>
        <div style="margin-top: 2rem; font-size: 0.8rem; color: var(--subtext); border-top: 1px solid var(--border); padding-top: 1.2rem;">
            Desarrollado por German Marambio © <script>document.write(new Date().getFullYear())</script>
        </div>
    </div>
</body>
</html>
"""

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Skunk PC - Enterprise Print Server Dashboard</title>
    <link rel="icon" type="image/png" href="/static/icon.png">
    <link rel="apple-touch-icon" href="/static/icon.png">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;600;700;800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
    <script>
        (function() {
            const saved = localStorage.getItem('skunk_theme') || 'amoled';
            document.documentElement.setAttribute('data-theme', saved);
        })();
        function toggleTheme() {
            const current = document.documentElement.getAttribute('data-theme');
            const next = current === 'light' ? 'amoled' : 'light';
            document.documentElement.setAttribute('data-theme', next);
            localStorage.setItem('skunk_theme', next);
            updateThemeBtn();
        }
        function updateThemeBtn() {
            const btn = document.getElementById('theme-toggle-btn');
            if (btn) {
                const current = document.documentElement.getAttribute('data-theme');
                btn.innerHTML = current === 'light' ? '🌑 AMOLED Oscuro' : '☀️ Modo Claro';
            }
        }
        window.addEventListener('DOMContentLoaded', updateThemeBtn);
    </script>
    <style>
        :root, [data-theme="amoled"] {
            --bg: #000000;
            --card-bg: #000000;
            --border: rgba(255, 255, 255, 0.22);
            --primary: #38bdf8;
            --success: #10b981;
            --warning: #f59e0b;
            --danger: #f43f5e;
            --text: #ffffff;
            --subtext: #a1a1aa;
            --grad-start: #000000;
            --grad-end: #000000;
        }
        [data-theme="light"] {
            --bg: #f8fafc;
            --card-bg: rgba(255, 255, 255, 0.95);
            --border: rgba(15, 23, 42, 0.15);
            --primary: #0284c7;
            --success: #059669;
            --warning: #d97706;
            --danger: #e11d48;
            --text: #0f172a;
            --subtext: #475569;
            --grad-start: #e2e8f0;
            --grad-end: #f8fafc;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Inter', sans-serif;
            background: radial-gradient(circle at top right, var(--grad-start), var(--grad-end) 70%);
            color: var(--text);
            min-height: 100vh;
            padding: 2rem;
            transition: background 0.3s, color 0.3s;
        }
        h1, h2, h3 { font-family: 'Outfit', sans-serif; color: var(--text); }
        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding-bottom: 2rem;
            border-bottom: 1px solid var(--border);
            margin-bottom: 2rem;
        }
        .logo {
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .logo-icon {
            font-size: 2.2rem;
            background: linear-gradient(135deg, var(--primary), var(--success));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .status-badge {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 6px 14px;
            border-radius: 999px;
            font-size: 0.85rem;
            font-weight: 600;
            background: rgba(16, 185, 129, 0.15);
            color: var(--success);
            border: 1px solid rgba(16, 185, 129, 0.3);
        }
        .status-badge.stopped {
            background: rgba(244, 63, 94, 0.15);
            color: var(--danger);
            border-color: rgba(244, 63, 94, 0.3);
        }
        .grid-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 1.25rem;
            margin-bottom: 2.5rem;
        }
        .card {
            background: var(--card-bg);
            backdrop-filter: blur(12px);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 1.5rem;
            box-shadow: 0 10px 25px rgba(0,0,0,0.3);
            transition: transform 0.2s, border-color 0.2s, background 0.3s;
        }
        .card:hover { transform: translateY(-3px); border-color: var(--primary); }
        .card-title { font-size: 0.9rem; color: var(--subtext); margin-bottom: 0.5rem; text-transform: uppercase; letter-spacing: 0.5px; }
        .card-value { font-size: 1.6rem; font-weight: 700; color: var(--text); display: flex; align-items: center; justify-content: space-between; }
        
        .section-title {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 1.5rem;
        }
        .btn {
            background: var(--primary);
            color: #0b1120;
            border: none;
            padding: 10px 18px;
            border-radius: 10px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.2s;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            font-size: 0.9rem;
        }
        .btn:hover { filter: brightness(1.15); transform: scale(1.02); }
        .btn:active, button:active, .btn-outline:active, .btn-success:active, .btn-danger:active, .btn-warning:active {
            transform: scale(0.92) translateY(2px) !important;
            filter: brightness(0.8) !important;
            box-shadow: inset 0 3px 6px rgba(0,0,0,0.5) !important;
            transition: all 0.05s ease !important;
        }
        .btn-success { background: var(--success); color: #fff; }
        .btn-danger { background: var(--danger); color: #fff; }
        .btn-warning { background: var(--warning); color: #000; }
        .btn-outline { background: transparent; color: var(--text); border: 1px solid var(--border); }
        .btn-outline:hover { background: rgba(128,128,128,0.1); }

        .printer-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(360px, 1fr));
            gap: 1.5rem;
            margin-bottom: 3rem;
        }
        .printer-card {
            background: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 1.5rem;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
            gap: 1.2rem;
            transition: background 0.3s, border-color 0.3s;
        }
        .printer-header { display: flex; justify-content: space-between; align-items: flex-start; }
        .printer-name { font-size: 1.25rem; font-weight: 700; color: var(--primary); font-family: 'Outfit', sans-serif; }
        .printer-uri { font-size: 0.8rem; color: var(--subtext); word-break: break-all; margin-top: 4px; }
        
        .printer-actions {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 8px;
        }
        .printer-actions .btn { font-size: 0.8rem; padding: 8px 10px; justify-content: center; }
        .full-width { grid-column: span 2; }

        modal {
            display: none;
            position: fixed;
            top: 0; left: 0; width: 100%; height: 100%;
            background: rgba(0,0,0,0.7);
            backdrop-filter: blur(5px);
            align-items: center; justify-content: center;
            z-index: 1000;
        }
        .modal-content {
            background: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 20px;
            padding: 2rem;
            width: 90%;
            max-width: 520px;
            transition: background 0.3s, border-color 0.3s;
        }
        .form-group { margin-bottom: 1.2rem; }
        label { display: block; font-size: 0.85rem; color: var(--subtext); margin-bottom: 6px; }
        input, select {
            width: 100%;
            padding: 12px;
            background: transparent;
            border: 1px solid var(--border);
            border-radius: 10px;
            color: var(--text);
            font-size: 0.95rem;
        }
        input:focus, select:focus { outline: none; border-color: var(--primary); }
        select option { background: var(--card-bg); color: var(--text); }
        .modal-buttons { display: flex; gap: 10px; justify-content: flex-end; margin-top: 1.8rem; }
    </style>
</head>
<body>
    <header>
        <div class="logo">
            <img src="/static/icon.png" alt="Skunk PC Logo" style="width: 52px; height: 52px; object-fit: contain; filter: drop-shadow(0 2px 8px rgba(56, 189, 248, 0.25));">
            <div>
                <h1>Skunk PC Print Server</h1>
                <p style="color: var(--subtext); font-size: 0.85rem;">Universal mDNS / AirPrint / Mopria Industrial Gateway</p>
            </div>
        </div>
        <div style="display: flex; align-items: center; gap: 10px; flex-wrap: wrap;">
            <span class="status-badge" id="cups-badge">● CUPS: {{ status.cups.upper() }}</span>
            <span class="status-badge" id="avahi-badge">● mDNS: {{ status.avahi.upper() }}</span>
            <button type="button" id="theme-toggle-btn" onclick="toggleTheme()" class="btn btn-outline" style="padding: 6px 14px; font-size: 0.85rem; border-radius: 99px;">☀️ Modo Claro</button>
            <a href="/logout" class="btn btn-outline" style="padding: 6px 14px; font-size: 0.85rem; text-decoration: none;">🚪 Salir</a>
        </div>
    </header>

    <!-- STATS -->
    <div class="grid-stats">
        <div class="card">
            <div class="card-title">Impresoras Activas</div>
            <div class="card-value">{{ printers|length }} <small style="font-size: 0.9rem; color: var(--success);">● Colas CUPS</small></div>
        </div>
        <div class="card">
            <div class="card-title">Dirección IP en Planta</div>
            <div class="card-value">{{ status.server_ip }} <small style="font-size: 0.85rem; color: var(--primary);">Puerto 631 / 8080</small></div>
        </div>
        <div class="card">
            <div class="card-title">Watchdog de Auto-Recuperación</div>
            <div class="card-value">
                <span>{{ status.watchdog.upper() }}</span>
                <button class="btn btn-outline" style="padding: 6px 12px; font-size: 0.75rem;" onclick="toggleWatchdog()">⚡ Cambiar</button>
            </div>
        </div>
        <div class="card">
            <div class="card-title">Respaldos & Desastres</div>
            <div class="card-value" style="gap: 8px;">
                <button class="btn btn-success" style="font-size: 0.8rem; flex: 1; justify-content: center;" onclick="backupSystem()">📦 Descargar</button>
                <button class="btn btn-outline" style="font-size: 0.8rem; flex: 1; justify-content: center;" onclick="openRestoreModal()">📤 Importar</button>
            </div>
        </div>
    </div>

    <!-- PRINTERS SECTION -->
    <div class="section-title">
        <h2>🖨️ Colas de Impresión & Calibración de Hardware</h2>
        <button class="btn btn-success" onclick="openAddModal()">+ Añadir Impresora (USB o Red)</button>
    </div>

    <div class="printer-grid">
        {% for p in printers %}
        <div class="printer-card">
            <div class="printer-header">
                <div>
                    <div class="printer-name">{{ p.name }}</div>
                    <div class="printer-uri">{{ p.uri }}</div>
                </div>
                <span class="status-badge {% if p.status == 'stopped' %}stopped{% endif %}">
                    {{ p.status.upper() }}
                </span>
            </div>
            
            <div class="printer-actions">
                <button class="btn" onclick="sendTest('{{ p.name }}', 'epl')">🧪 Test EPL2</button>
                <button class="btn" onclick="sendTest('{{ p.name }}', 'zpl')">🧪 Test ZPL II</button>
                <button class="btn btn-outline" onclick="sendTest('{{ p.name }}', 'barcode')">🏷️ Cód. Barras</button>
                <button class="btn btn-outline" onclick="openLabelModal('{{ p.name }}')">📐 Tamaño Etiqueta</button>
                <button class="btn btn-outline" onclick="calibrate('{{ p.name }}')">📏 Calibrar Sensor</button>
                <button class="btn btn-warning" onclick="resetQueue('{{ p.name }}')">⚡ Desatascar</button>
                <button class="btn btn-outline" onclick="openRenameModal('{{ p.name }}')">✏️ Renombrar</button>
                <button class="btn btn-danger full-width" onclick="deleteQueue('{{ p.name }}')">🗑️ Eliminar Cola CUPS</button>
            </div>
        </div>
        {% else %}
        <div class="card" style="grid-column: 1 / -1; text-align: center; padding: 3rem;">
            <p style="font-size: 1.1rem; color: var(--subtext);">No hay impresoras añadidas aún en el servidor.</p>
            <button class="btn btn-success" style="margin-top: 1rem;" onclick="openAddModal()">+ Añadir Primera Impresora</button>
        </div>
        {% endfor %}
    </div>

    <!-- ADD MODAL -->
    <div id="addModal" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.7); backdrop-filter:blur(5px); z-index:1000; align-items:center; justify-content:center;">
        <div class="modal-content">
            <h3 style="margin-bottom: 1.5rem;">+ Añadir Nueva Impresora Zebra</h3>
            <div class="form-group">
                <label>Nombre de la Cola (Sin espacios)</label>
                <input type="text" id="addName" placeholder="Zebra_TLP2844_Caja1">
            </div>
            <div class="form-group">
                <label>Tipo de Conexión</label>
                <select id="connType" onchange="toggleConnField()">
                    <option value="usb">Dispositivo Físico USB (Autodetectado)</option>
                    <option value="net">Impresora en Red Ethernet / Wi-Fi (IP)</option>
                </select>
            </div>
            <div class="form-group" id="usbField">
                <label>Puerto USB Detectado (`lpinfo -v`)</label>
                <select id="usbUri">
                    {% for u in usb_devices %}
                    <option value="{{ u }}">{{ u }}</option>
                    {% else %}
                    <option value="">No se encontraron dispositivos USB en este instante</option>
                    {% endfor %}
                </select>
            </div>
            <div class="form-group" id="netField" style="display:none;">
                <label>Dirección IP de la Impresora de Red (`socket://`)</label>
                <input type="text" id="netIp" placeholder="192.168.1.50">
            </div>
            <div class="form-group">
                <label>Controlador PPD y Lenguaje Nativo</label>
                <select id="driverModel">
                    <option value="drv:///sample.drv/zebraep2.ppd">Zebra EPL2 Label Printer (Nativo TLP2844 / LP2844)</option>
                    <option value="drv:///sample.drv/zebra.ppd">Zebra ZPL Label Printer (Nativo GC420t / ZD420)</option>
                    <option value="raw">Raw Queue (Sin filtro de sistema - Solo envíos directos)</option>
                </select>
            </div>
            <div class="modal-buttons">
                <button class="btn btn-outline" onclick="closeModal('addModal')">Cancelar</button>
                <button class="btn btn-success" onclick="submitAddPrinter()">Guardar Impresora</button>
            </div>
        </div>
    </div>

    <!-- RENAME MODAL -->
    <div id="renameModal" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.7); backdrop-filter:blur(5px); z-index:1000; align-items:center; justify-content:center;">
        <div class="modal-content">
            <h3 style="margin-bottom: 1.5rem;">✏️ Renombrar Impresora</h3>
            <input type="hidden" id="oldName">
            <div class="form-group">
                <label>Nuevo Nombre para la Cola CUPS</label>
                <input type="text" id="newName" placeholder="Zebra_Almacen_Norte">
            </div>
            <div class="modal-buttons">
                <button class="btn btn-outline" onclick="closeModal('renameModal')">Cancelar</button>
                <button class="btn btn-primary" onclick="submitRename()">Renombrar</button>
            </div>
        </div>
    </div>

    <!-- LABEL SIZE MODAL -->
    <div id="labelModal" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.7); backdrop-filter:blur(5px); z-index:1000; align-items:center; justify-content:center;">
        <div class="modal-content">
            <h3 style="margin-bottom: 1.5rem;">📐 Configurar Tamaño de Etiqueta / Papel</h3>
            <input type="hidden" id="labelPrinterTarget">
            <div class="form-group">
                <label>Seleccionar Formato Predeterminado</label>
                <select id="presetLabelSize" onchange="toggleCustomLabelField()">
                    <option value="w288h432">🏷️ 100 x 150 mm (4 x 6 pulgadas) - Estándar Almacén</option>
                    <option value="w144h72">🏷️ 50 x 25 mm (2 x 1 pulgada)</option>
                    <option value="w288h288">🏷️ 100 x 100 mm (4 x 4 pulgadas)</option>
                    <option value="w216h144">🏷️ 75 x 50 mm (3 x 2 pulgadas)</option>
                    <option value="A4">📄 ISO A4 (210 x 297 mm)</option>
                    <option value="custom">✏️ Tamaño Personalizado en mm (Ancho x Alto)</option>
                </select>
            </div>
            <div id="customLabelFields" style="display:none; gap: 10px;">
                <div class="form-group" style="flex:1;">
                    <label>Ancho (mm)</label>
                    <input type="number" id="customWidth" placeholder="100">
                </div>
                <div class="form-group" style="flex:1;">
                    <label>Alto (mm)</label>
                    <input type="number" id="customHeight" placeholder="150">
                </div>
            </div>
            <div class="modal-buttons">
                <button class="btn btn-outline" onclick="closeModal('labelModal')">Cancelar</button>
                <button class="btn btn-success" onclick="submitLabelSize()">Guardar Tamaño</button>
            </div>
        </div>
    </div>

    <!-- RESTORE MODAL -->
    <div id="restoreModal" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.7); backdrop-filter:blur(5px); z-index:1000; align-items:center; justify-content:center;">
        <div class="modal-content">
            <h3 style="margin-bottom: 1.5rem;">📤 Importar y Restaurar Respaldo (.tar.gz)</h3>
            <p style="font-size: 0.9rem; color: var(--subtext); margin-bottom: 1.2rem;">
                Selecciona el archivo de copia de seguridad descargado previamente para restaurar al instante todas tus colas y parámetros.
            </p>
            <div class="form-group">
                <label>Archivo de Copia de Seguridad (`.tar.gz`)</label>
                <input type="file" id="backupFileInput" accept=".tar.gz,.tgz">
            </div>
            <div class="modal-buttons">
                <button class="btn btn-outline" onclick="closeModal('restoreModal')">Cancelar</button>
                <button class="btn btn-danger" onclick="submitRestore()">Restaurar Configuración</button>
            </div>
        </div>
    </div>

    <script>
        function openAddModal() { document.getElementById('addModal').style.display = 'flex'; }
        function openRestoreModal() { document.getElementById('restoreModal').style.display = 'flex'; }
        function closeModal(id) { document.getElementById(id).style.display = 'none'; }
        function openRenameModal(name) {
            document.getElementById('oldName').value = name;
            document.getElementById('newName').value = name;
            document.getElementById('renameModal').style.display = 'flex';
        }
        function openLabelModal(name) {
            document.getElementById('labelPrinterTarget').value = name;
            document.getElementById('presetLabelSize').value = 'w288h432';
            toggleCustomLabelField();
            document.getElementById('labelModal').style.display = 'flex';
        }
        function toggleCustomLabelField() {
            const isCustom = document.getElementById('presetLabelSize').value === 'custom';
            document.getElementById('customLabelFields').style.display = isCustom ? 'flex' : 'none';
        }
        async function submitLabelSize() {
            const printer = document.getElementById('labelPrinterTarget').value;
            const preset = document.getElementById('presetLabelSize').value;
            let payload = {};
            if (preset === 'custom') {
                const width = document.getElementById('customWidth').value.trim();
                const height = document.getElementById('customHeight').value.trim();
                if (!width || !height) { alert("Ingresa ancho y alto en milímetros"); return; }
                payload = { width, height };
            } else {
                payload = { size: preset };
            }
            
            const resetBtn = btnLoading(window.event, '⏳ Guardando...');
            try {
                const res = await fetch(`/api/label_size/${printer}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                const data = await res.json();
                if (resetBtn) resetBtn();
                alert(data.msg);
                if (data.ok) location.reload();
            } catch (e) {
                if (resetBtn) resetBtn();
                alert("Error de red al actualizar tamaño.");
            }
        }
        function toggleConnField() {
            const val = document.getElementById('connType').value;
            document.getElementById('usbField').style.display = (val === 'usb') ? 'block' : 'none';
            document.getElementById('netField').style.display = (val === 'net') ? 'block' : 'none';
        }

        function btnLoading(e, msg = '⏳ Procesando...') {
            if (!e || !e.target) return null;
            const btn = e.target.closest('button') || e.target.closest('a');
            if (!btn) return null;
            const oldHtml = btn.innerHTML;
            btn.innerHTML = msg;
            btn.style.opacity = '0.75';
            btn.disabled = true;
            return () => {
                btn.innerHTML = oldHtml;
                btn.style.opacity = '1';
                btn.disabled = false;
            };
        }

        async function sendTest(printer, type) {
            const resetBtn = btnLoading(window.event, '⏳ Enviando...');
            try {
                const res = await fetch(`/api/test/${printer}?type=${type}`, { method: 'POST' });
                const data = await res.json();
                if (resetBtn) resetBtn();
                alert(data.msg);
            } catch (e) {
                if (resetBtn) resetBtn();
                alert("Error de red al intentar enviar prueba.");
            }
        }

        async function calibrate(printer) {
            if (!confirm(`¿Fuerzar calibración de sensor en ${printer}? La impresora expulsará 2 o 3 etiquetas en blanco.`)) return;
            const resetBtn = btnLoading(window.event, '⏳ Calibrando...');
            try {
                const res = await fetch(`/api/calibrate/${printer}`, { method: 'POST' });
                const data = await res.json();
                if (resetBtn) resetBtn();
                alert(data.msg);
            } catch (e) {
                if (resetBtn) resetBtn();
                alert("Error al ejecutar calibración.");
            }
        }

        async function resetQueue(printer) {
            const resetBtn = btnLoading(window.event, '⏳ Limpiando...');
            try {
                const res = await fetch(`/api/reset/${printer}`, { method: 'POST' });
                const data = await res.json();
                if (resetBtn) resetBtn();
                alert(data.msg);
                location.reload();
            } catch (e) {
                if (resetBtn) resetBtn();
                alert("Error al intentar reiniciar cola.");
            }
        }

        async function deleteQueue(printer) {
            if (!confirm(`⚠️ ¿Estás completamente seguro de ELIMINAR la impresora '${printer}' del servidor CUPS?`)) return;
            const resetBtn = btnLoading(window.event, '⏳ Eliminando...');
            try {
                const res = await fetch(`/api/delete/${printer}`, { method: 'POST' });
                const data = await res.json();
                if (resetBtn) resetBtn();
                alert(data.msg);
                if (data.ok) location.reload();
            } catch (e) {
                if (resetBtn) resetBtn();
                alert("Error de conexión al intentar eliminar la impresora.");
            }
        }

        async function submitAddPrinter() {
            const name = document.getElementById('addName').value.trim();
            const connType = document.getElementById('connType').value;
            const driver = document.getElementById('driverModel').value;
            let uri = "";
            
            if (connType === 'usb') {
                uri = document.getElementById('usbUri').value;
            } else {
                const ip = document.getElementById('netIp').value.trim();
                uri = `socket://${ip}:9100`;
            }
            
            if (!name || !uri) { alert("Nombre y URI o IP son obligatorios"); return; }
            
            const resetBtn = btnLoading(window.event, '⏳ Instalando...');
            try {
                const res = await fetch('/api/add', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name, uri, driver })
                });
                const data = await res.json();
                if (resetBtn) resetBtn();
                if (data.ok) location.reload(); else alert(data.msg);
            } catch (e) {
                if (resetBtn) resetBtn();
                alert("Error de red al añadir impresora.");
            }
        }

        async function submitRename() {
            const old_name = document.getElementById('oldName').value;
            const new_name = document.getElementById('newName').value.trim();
            if (!new_name) return;
            
            const resetBtn = btnLoading(window.event, '⏳ Renombrando...');
            try {
                const res = await fetch('/api/rename', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ old_name, new_name })
                });
                const data = await res.json();
                if (resetBtn) resetBtn();
                if (data.ok) location.reload(); else alert(data.msg);
            } catch (e) {
                if (resetBtn) resetBtn();
                alert("Error de red al renombrar.");
            }
        }

        async function toggleWatchdog() {
            const resetBtn = btnLoading(window.event, '⏳ Cambiando...');
            await fetch('/api/toggle_watchdog', { method: 'POST' });
            location.reload();
        }

        function backupSystem() {
            btnLoading(window.event, '📦 Generando...');
            window.location.href = '/api/backup';
        }

        async function submitRestore() {
            const fileInput = document.getElementById('backupFileInput');
            if (!fileInput.files || fileInput.files.length === 0) {
                alert("Por favor selecciona un archivo .tar.gz");
                return;
            }
            if (!confirm("⚠️ ¿Estás seguro de restaurar este respaldo? Se sobrescribirán las colas actuales.")) return;
            
            const formData = new FormData();
            formData.append("backup_file", fileInput.files[0]);
            
            const resetBtn = btnLoading(window.event, '⏳ Restaurando...');
            try {
                const res = await fetch('/api/restore', {
                    method: 'POST',
                    body: formData
                });
                const data = await res.json();
                if (resetBtn) resetBtn();
                alert(data.msg);
                if (data.ok) location.reload();
            } catch (e) {
                if (resetBtn) resetBtn();
                alert("Error de red al restaurar respaldo.");
            }
        }
    </script>
    <footer style="text-align: center; margin-top: 4rem; padding-top: 1.5rem; border-top: 1px solid var(--border); color: var(--subtext); font-size: 0.85rem; font-weight: 500;">
        Desarrollado por German Marambio © <script>document.write(new Date().getFullYear())</script>
    </footer>
</body>
</html>
"""

@app.before_request
def require_login():
    if request.path.startswith("/static") or request.path in ["/login", "/logout"]:
        return
    if not session.get("authenticated"):
        if request.path.startswith("/api/"):
            return jsonify({"ok": False, "msg": "Sesión no autenticada o expirada. Por favor ingresa al portal."}), 401
        return redirect(url_for("login"))

@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        pwd = request.form.get("password", "")
        if pwd == ADMIN_PASSWORD:
            session["authenticated"] = True
            return redirect(url_for("index"))
        else:
            error = "Contraseña incorrecta. Inténtalo nuevamente."
    return render_template_string(LOGIN_TEMPLATE, error=error)

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

@app.route("/")
def index():
    status = get_system_status()
    printers = get_printers()
    usb_devices = get_usb_devices()
    return render_template_string(HTML_TEMPLATE, status=status, printers=printers, usb_devices=usb_devices)

@app.route("/api/test/<printer>", methods=["POST"])
def api_test(printer):
    t = request.args.get("type", "epl")
    if t == "epl":
        payload = '\nN\nq609\nQ914,24\nA50,50,0,4,1,1,N,"PRUEBA WEB UI - EPL2 OK"\nA50,130,0,3,1,1,N,"Servidor: Ubuntu / Proxmox"\nA50,190,0,3,1,1,N,"Impresora: Zebra TLP2844 OK"\nP1\n'
    elif t == "zpl":
        payload = '^XA^PW609^LL914^FO50,50^A0N,45,45^FDPRUEBA WEB UI - ZPL OK^FS^FO50,130^A0N,30,30^FDTLP2844 / GC420t OK^FS^XZ'
    else:
        payload = '\nN\nq609\nQ914,24\nA60,60,0,4,1,1,N,"CODIGO BARRAS SKUNK"\nB60,130,0,1,2,6,100,B,"SKUNK-WEBUI-2026"\nP1\n'
        
    p = subprocess.Popen(["lp", "-d", printer, "-o", "raw"], stdin=subprocess.PIPE, text=True)
    p.communicate(input=payload)
    return jsonify({"ok": p.returncode == 0, "msg": f"Prueba '{t.upper()}' enviada a {printer}."})

@app.route("/api/calibrate/<printer>", methods=["POST"])
def api_calibrate(printer):
    p1 = subprocess.Popen(["lp", "-d", printer, "-o", "raw"], stdin=subprocess.PIPE, text=True)
    p1.communicate(input="\njc\n")
    p2 = subprocess.Popen(["lp", "-d", printer, "-o", "raw"], stdin=subprocess.PIPE, text=True)
    p2.communicate(input="~JC\n^XA^JUS^XZ")
    return jsonify({"ok": True, "msg": f"Orden de calibración física (jc/~JC) enviada a {printer}."})

@app.route("/api/reset/<printer>", methods=["POST"])
def api_reset(printer):
    run_cmd(["cupsaccept", printer])
    run_cmd(["cupsenable", printer])
    run_cmd(["lpadmin", "-p", printer, "-o", "printer-error-policy=retry-job", "-E"])
    return jsonify({"ok": True, "msg": f"Cola {printer} reactivada y errores limpiados."})

@app.route("/api/delete/<printer>", methods=["DELETE", "POST"])
def api_delete(printer):
    run_cmd(["lpadmin", "-x", printer])
    return jsonify({"ok": True, "msg": f"✔ Impresora '{printer}' eliminada exitosamente del servidor."})

@app.route("/api/add", methods=["POST"])
def api_add():
    data = request.json
    name = data.get("name", "").strip()
    uri = data.get("uri", "").strip()
    driver = data.get("driver", "drv:///sample.drv/zebraep2.ppd")
    
    if not name or not uri:
        return jsonify({"ok": False, "msg": "Nombre y URI requeridos."})
        
    cmd = ["lpadmin", "-p", name, "-v", uri, "-E", "-o", "printer-is-shared=true", "-D", f"Zebra ({name})", "-L", "Almacén Skunk-PC"]
    if driver != "raw":
        cmd += ["-m", driver]
    else:
        cmd += ["-o", "raw"]
        
    ok, stdout, stderr = run_cmd(cmd)
    if not ok and driver != "raw":
        # Reintento con raw si falla el PPD
        cmd_raw = ["lpadmin", "-p", name, "-v", uri, "-E", "-o", "raw", "-o", "printer-is-shared=true", "-D", f"Zebra ({name})", "-L", "Almacén Skunk-PC"]
        ok, stdout, stderr = run_cmd(cmd_raw)
        
    if ok:
        run_cmd(["cupsaccept", name])
        run_cmd(["cupsenable", name])
        return jsonify({"ok": True, "msg": f"Impresora {name} creada."})
    else:
        return jsonify({"ok": False, "msg": f"Error al crear impresora: {stderr}"})

@app.route("/api/rename", methods=["POST"])
def api_rename():
    data = request.json
    old_name = data.get("old_name", "").strip()
    new_name = data.get("new_name", "").strip()
    
    ok, stdout, _ = run_cmd(["lpstat", "-v", old_name])
    if not ok or not stdout:
        return jsonify({"ok": False, "msg": "Impresora origen no existe."})
        
    uri = stdout.split(": ", 1)[1].strip() if ": " in stdout else stdout.split()[2].strip()
    
    # Preservar PPD existente si está en /etc/cups/ppd/
    old_ppd = f"/etc/cups/ppd/{old_name}.ppd"
    cmd = ["lpadmin", "-p", new_name, "-v", uri, "-E", "-o", "printer-is-shared=true", "-D", f"Zebra ({new_name})", "-L", "Almacén Skunk-PC"]
    if os.path.exists(old_ppd):
        cmd += ["-i", old_ppd]
    else:
        # Fallback a PPD ZPL por defecto si no hay PPD previo
        cmd += ["-m", "drv:///sample.drv/zebra.ppd"]
        
    run_cmd(cmd)
    run_cmd(["cupsaccept", new_name])
    run_cmd(["cupsenable", new_name])
    run_cmd(["lpadmin", "-x", old_name])
    return jsonify({"ok": True, "msg": f"Renombrado a {new_name} exitoso."})

@app.route("/api/label_size/<printer>", methods=["POST"])
def api_label_size(printer):
    data = request.json or {}
    size = data.get("size", "").strip()
    width = data.get("width")
    height = data.get("height")
    
    if width and height:
        size = f"Custom.{width}x{height}mm"
        
    if not size:
        return jsonify({"ok": False, "msg": "Tamaño de etiqueta inválido."})
        
    cmd = ["lpadmin", "-p", printer, "-o", f"PageSize={size}", "-o", f"media={size}"]
    ok, stdout, stderr = run_cmd(cmd)
    if ok:
        run_cmd(["cupsaccept", printer])
        run_cmd(["cupsenable", printer])
        return jsonify({"ok": True, "msg": f"✔ Tamaño de etiqueta de '{printer}' cambiado exitosamente a {size}."})
    else:
        return jsonify({"ok": False, "msg": f"Error al cambiar tamaño: {stderr}"})

@app.route("/api/toggle_watchdog", methods=["POST"])
def api_toggle_watchdog():
    ok, _, _ = run_cmd(["systemctl", "is-active", "skunk-watchdog.timer"])
    if ok:
        run_cmd(["systemctl", "disable", "--now", "skunk-watchdog.timer"])
    else:
        run_cmd(["systemctl", "enable", "--now", "skunk-watchdog.timer"])
        run_cmd(["systemctl", "start", "skunk-watchdog.service"])
    return jsonify({"ok": True})

@app.route("/api/backup", methods=["GET"])
def api_backup():
    import tarfile
    from datetime import datetime
    
    fname = f"skunk_backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.tar.gz"
    fpath = os.path.join(BACKUP_DIR, fname)
    
    with tarfile.open(fpath, "w:gz") as tar:
        for p in ["/etc/cups/printers.conf", "/etc/cups/cupsd.conf", "/etc/cups/ppd", "/etc/avahi/avahi-daemon.conf"]:
            if os.path.exists(p):
                tar.add(p, arcname=p.lstrip("/"))
                
    return send_file(fpath, as_attachment=True, download_name=fname)

@app.route("/api/restore", methods=["POST"])
def api_restore():
    if "backup_file" not in request.files:
        return jsonify({"ok": False, "msg": "No se envió ningún archivo."})
        
    f = request.files["backup_file"]
    if not f.filename.endswith(".tar.gz") and not f.filename.endswith(".tgz"):
        return jsonify({"ok": False, "msg": "Formato inválido. Debe ser un archivo .tar.gz"})
        
    fpath = os.path.join(BACKUP_DIR, "uploaded_restore.tar.gz")
    f.save(fpath)
    
    # Detener servicios temporalmente
    run_cmd(["systemctl", "stop", "cups", "avahi-daemon", "cups-browsed"])
    
    # Descomprimir en la raíz /
    import tarfile
    try:
        with tarfile.open(fpath, "r:gz") as tar:
            tar.extractall(path="/")
    except Exception as e:
        run_cmd(["systemctl", "start", "cups", "avahi-daemon", "cups-browsed"])
        return jsonify({"ok": False, "msg": f"Error al extraer archivo de respaldo: {str(e)}"})
        
    # Ajustar permisos de CUPS tras la restauración
    run_cmd(["chown", "-R", "root:lp", "/etc/cups/ppd"])
    run_cmd(["chown", "root:lp", "/etc/cups/printers.conf"])
    run_cmd(["chmod", "600", "/etc/cups/printers.conf"])
    
    # Reiniciar servicios con la configuración clonada/restaurada
    run_cmd(["systemctl", "start", "cups", "avahi-daemon", "cups-browsed"])
    return jsonify({"ok": True, "msg": "¡Restauración exitosa! Todas las colas y ajustes del respaldo han sido aplicados al servidor."})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
