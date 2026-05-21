#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ProtonVPN IP Rotator
- Rotasi IP otomatis menggunakan ProtonVPN CLI
- Support random server, country-specific, atau sequential
- Bisa dipanggil dari script lain sebagai module
- Cek IP sebelum dan sesudah rotate

Requirement:
- ProtonVPN CLI terinstall (protonvpn-cli atau proton-cli)
  Install: https://protonvpn.com/support/official-linux-vpn-tool/
  Windows: https://protonvpn.com/support/protonvpn-windows-vpn-application/
- Atau pakai OpenVPN config files dari ProtonVPN

Mode:
1. ProtonVPN CLI (Linux/Mac) - pakai `protonvpn-cli`
2. OpenVPN config rotation (Windows/Linux) - pakai .ovpn files
3. ProtonVPN Windows app CLI
"""
import os
import sys
import time
import json
import random
import subprocess
import requests
from datetime import datetime

# ================== CONFIG ==================
CONFIG = {
    # ProtonVPN credentials (untuk OpenVPN mode)
    "username": "",          # ProtonVPN OpenVPN username (bukan email)
    "password": "",          # ProtonVPN OpenVPN password

    # Mode: "cli" | "openvpn" | "windows"
    "mode": "openvpn",

    # OpenVPN config directory (folder berisi .ovpn files)
    "ovpn_dir": r"d:\PROJEK BOT\protonvpn_configs",

    # Rotation settings
    "rotate_interval": 300,  # Rotasi setiap X detik (0 = manual)
    "max_rotations": 0,      # 0 = unlimited
    "country_filter": [],    # Kosong = semua negara. Contoh: ["US", "NL", "JP"]
    "random_order": True,    # True = random, False = sequential

    # Connection settings
    "connect_timeout": 30,   # Timeout koneksi (detik)
    "retry_count": 3,        # Retry jika gagal konek
    "kill_switch": True,     # Kill existing VPN sebelum rotate

    # Logging
    "log_file": "vpn_rotation.log",
    "verbose": True,
}

CONFIG_FILE = "protonvpn_config.json"


# ================== LOG ==================
def now_time():
    return datetime.now().strftime("%H:%M:%S")


def log(msg, level="info"):
    prefix = {"info": "▸", "ok": "□", "warn": "⚠", "error": "✖", "step": "■"}
    symbol = prefix.get(level, "▸")
    line = f"{now_time()}  {symbol} {msg}"
    print(line)
    if CONFIG.get("log_file"):
        try:
            with open(CONFIG["log_file"], "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError:
            pass


# ================== CONFIG MANAGER ==================
def load_config():
    global CONFIG
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                saved = json.load(f)
            CONFIG.update(saved)
            log(f"Config loaded: {CONFIG_FILE}", "ok")
        except Exception as e:
            log(f"Config load error: {e}", "warn")


def save_config():
    try:
        config_save = dict(CONFIG)
        config_save["password"] = ""  # Jangan simpan password
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(config_save, f, indent=2)
        log(f"Config saved: {CONFIG_FILE}", "ok")
    except Exception as e:
        log(f"Config save error: {e}", "error")


def setup_config():
    """Interactive config setup."""
    print()
    log("SETUP PROTONVPN CONFIG", "step")
    print()
    print("  Mode:")
    print("  1. OpenVPN (.ovpn files) - Recommended untuk Windows")
    print("  2. ProtonVPN CLI (Linux)")
    print("  3. ProtonVPN Windows App")
    print()

    mode_choice = input("  Pilih mode [1]: ").strip() or "1"
    mode_map = {"1": "openvpn", "2": "cli", "3": "windows"}
    CONFIG["mode"] = mode_map.get(mode_choice, "openvpn")

    if CONFIG["mode"] == "openvpn":
        print()
        print("  ╔═══════════════════════════════════════════════════╗")
        print("  ║ Download .ovpn configs dari:                      ║")
        print("  ║ https://account.protonvpn.com/downloads           ║")
        print("  ║ Pilih: OpenVPN configuration files                ║")
        print("  ║ Extract ke folder, lalu masukkan path-nya         ║")
        print("  ╚═══════════════════════════════════════════════════╝")
        print()

        val = input(f"  OVPN folder [{CONFIG['ovpn_dir']}]: ").strip()
        if val:
            CONFIG["ovpn_dir"] = val

        print()
        print("  Username & Password OpenVPN bisa didapat di:")
        print("  https://account.protonvpn.com/account#openvpn")
        print()

        val = input(f"  OpenVPN Username: ").strip()
        if val:
            CONFIG["username"] = val

        from getpass import getpass
        val = getpass("  OpenVPN Password: ").strip()
        if val:
            CONFIG["password"] = val

    val = input(f"  Rotate interval (detik) [{CONFIG['rotate_interval']}]: ").strip()
    if val.isdigit():
        CONFIG["rotate_interval"] = int(val)

    val = input(f"  Country filter (comma separated, kosong=semua) [{','.join(CONFIG['country_filter'])}]: ").strip()
    if val:
        CONFIG["country_filter"] = [c.strip().upper() for c in val.split(",")]

    print()
    save_config()


# ================== IP CHECK ==================
def get_current_ip():
    """Cek IP publik saat ini."""
    services = [
        "https://api.ipify.org?format=json",
        "https://ipinfo.io/json",
        "https://ifconfig.me/all.json",
    ]
    for url in services:
        try:
            resp = requests.get(url, timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                ip = data.get("ip") or data.get("origin") or data.get("ip_addr")
                country = data.get("country", "?")
                city = data.get("city", "?")
                org = data.get("org", data.get("isp", "?"))
                return {
                    "ip": ip,
                    "country": country,
                    "city": city,
                    "org": org,
                }
        except Exception:
            continue
    return None


def show_ip():
    """Tampilkan IP saat ini."""
    info = get_current_ip()
    if info:
        log(f"IP: {info['ip']} | {info['country']} | {info['city']} | {info['org']}", "ok")
        return info
    else:
        log("Gagal cek IP", "error")
        return None


# ================== OPENVPN MODE ==================
class OpenVPNRotator:
    """Rotasi IP menggunakan OpenVPN config files dari ProtonVPN."""

    def __init__(self):
        self.configs = []
        self.current_index = 0
        self.process = None
        self.auth_file = "proton_auth.txt"
        self._load_configs()

    def _load_configs(self):
        """Load semua .ovpn files dari folder."""
        ovpn_dir = CONFIG["ovpn_dir"]
        if not os.path.isdir(ovpn_dir):
            log(f"OVPN folder tidak ada: {ovpn_dir}", "error")
            log("Download dari: https://account.protonvpn.com/downloads", "info")
            return

        files = [f for f in os.listdir(ovpn_dir) if f.endswith(".ovpn")]

        # Filter by country jika ada
        if CONFIG["country_filter"]:
            filtered = []
            for f in files:
                for country in CONFIG["country_filter"]:
                    if f.upper().startswith(country) or f"-{country}" in f.upper():
                        filtered.append(f)
                        break
            files = filtered

        if CONFIG["random_order"]:
            random.shuffle(files)
        else:
            files.sort()

        self.configs = [os.path.join(ovpn_dir, f) for f in files]
        log(f"Loaded {len(self.configs)} OpenVPN configs", "ok")

    def _create_auth_file(self):
        """Buat file auth untuk OpenVPN."""
        if CONFIG["username"] and CONFIG["password"]:
            with open(self.auth_file, "w") as f:
                f.write(f"{CONFIG['username']}\n{CONFIG['password']}\n")
            return True
        return False

    def connect(self, config_path=None):
        """Connect ke VPN server."""
        if not self.configs and not config_path:
            log("Tidak ada config tersedia", "error")
            return False

        if config_path is None:
            config_path = self.configs[self.current_index % len(self.configs)]
            self.current_index += 1

        # Kill existing connection
        self.disconnect()
        time.sleep(1)

        server_name = os.path.basename(config_path).replace(".ovpn", "")
        log(f"Connecting: {server_name}...", "info")

        # Build command
        cmd = ["openvpn", "--config", config_path, "--daemon"]

        if self._create_auth_file():
            cmd.extend(["--auth-user-pass", self.auth_file])

        # Tambah options
        cmd.extend([
            "--connect-retry", "3",
            "--connect-timeout", str(CONFIG["connect_timeout"]),
            "--verb", "1",
        ])

        try:
            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
            )

            # Tunggu koneksi establish
            log("Waiting for connection...", "info")
            time.sleep(8)

            # Verify IP changed
            new_ip = get_current_ip()
            if new_ip:
                log(f"Connected! IP: {new_ip['ip']} ({new_ip['country']})", "ok")
                return True
            else:
                log("Connection mungkin gagal (tidak bisa cek IP)", "warn")
                return True  # Mungkin masih connecting

        except FileNotFoundError:
            log("OpenVPN tidak terinstall!", "error")
            log("Download: https://openvpn.net/community-downloads/", "info")
            return False
        except Exception as e:
            log(f"Connect error: {e}", "error")
            return False

    def disconnect(self):
        """Disconnect VPN."""
        if sys.platform == "win32":
            os.system("taskkill /f /im openvpn.exe >nul 2>&1")
        else:
            os.system("killall openvpn 2>/dev/null")

        if self.process:
            try:
                self.process.terminate()
                self.process.wait(timeout=5)
            except Exception:
                try:
                    self.process.kill()
                except Exception:
                    pass
            self.process = None

    def rotate(self):
        """Rotate ke server berikutnya."""
        if not self.configs:
            self._load_configs()
            if not self.configs:
                return False

        return self.connect()

    def cleanup(self):
        """Cleanup resources."""
        self.disconnect()
        if os.path.exists(self.auth_file):
            try:
                os.remove(self.auth_file)
            except OSError:
                pass


# ================== CLI MODE ==================
class ProtonCLIRotator:
    """Rotasi IP menggunakan ProtonVPN CLI (Linux)."""

    def __init__(self):
        self.servers = []
        self.current_index = 0

    def connect(self, server=None):
        """Connect via protonvpn-cli."""
        self.disconnect()
        time.sleep(1)

        if server:
            cmd = ["protonvpn-cli", "connect", "--sc", server]
        elif CONFIG["country_filter"]:
            country = random.choice(CONFIG["country_filter"])
            cmd = ["protonvpn-cli", "connect", "--cc", country]
        else:
            cmd = ["protonvpn-cli", "connect", "--random"]

        log(f"Connecting: {' '.join(cmd)}", "info")

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True,
                timeout=CONFIG["connect_timeout"]
            )
            if result.returncode == 0:
                time.sleep(3)
                new_ip = get_current_ip()
                if new_ip:
                    log(f"Connected! IP: {new_ip['ip']} ({new_ip['country']})", "ok")
                return True
            else:
                log(f"Connect failed: {result.stderr}", "error")
                return False
        except FileNotFoundError:
            log("protonvpn-cli tidak terinstall", "error")
            return False
        except Exception as e:
            log(f"Error: {e}", "error")
            return False

    def disconnect(self):
        """Disconnect via CLI."""
        try:
            subprocess.run(
                ["protonvpn-cli", "disconnect"],
                capture_output=True, timeout=10
            )
        except Exception:
            pass

    def rotate(self):
        return self.connect()

    def cleanup(self):
        self.disconnect()


# ================== WINDOWS APP MODE ==================
class ProtonWindowsRotator:
    """Rotasi menggunakan ProtonVPN Windows app CLI."""

    def connect(self, server=None):
        """Connect via ProtonVPN Windows app."""
        self.disconnect()
        time.sleep(2)

        # ProtonVPN Windows app path
        app_path = r"C:\Program Files\Proton\VPN\ProtonVPN.exe"
        if not os.path.exists(app_path):
            app_path = r"C:\Program Files (x86)\Proton\VPN\ProtonVPN.exe"

        if not os.path.exists(app_path):
            log("ProtonVPN Windows app tidak ditemukan", "error")
            return False

        try:
            if CONFIG["country_filter"]:
                country = random.choice(CONFIG["country_filter"])
                cmd = [app_path, "/connect", f"/country:{country}"]
            else:
                cmd = [app_path, "/connect", "/random"]

            log(f"Connecting via Windows app...", "info")
            subprocess.Popen(cmd)
            time.sleep(10)

            new_ip = get_current_ip()
            if new_ip:
                log(f"Connected! IP: {new_ip['ip']} ({new_ip['country']})", "ok")
                return True
            return False
        except Exception as e:
            log(f"Error: {e}", "error")
            return False

    def disconnect(self):
        app_path = r"C:\Program Files\Proton\VPN\ProtonVPN.exe"
        try:
            subprocess.run([app_path, "/disconnect"], capture_output=True, timeout=10)
        except Exception:
            pass

    def rotate(self):
        return self.connect()

    def cleanup(self):
        self.disconnect()


# ================== ROTATOR FACTORY ==================
def get_rotator():
    """Get rotator berdasarkan mode config."""
    mode = CONFIG["mode"]
    if mode == "openvpn":
        return OpenVPNRotator()
    elif mode == "cli":
        return ProtonCLIRotator()
    elif mode == "windows":
        return ProtonWindowsRotator()
    else:
        log(f"Mode tidak dikenal: {mode}", "error")
        return OpenVPNRotator()


# ================== AUTO ROTATION ==================
def auto_rotate():
    """Auto-rotate IP berdasarkan interval."""
    print()
    log("AUTO IP ROTATION - ProtonVPN", "step")
    print()

    rotator = get_rotator()
    interval = CONFIG["rotate_interval"]
    max_rot = CONFIG["max_rotations"]

    log(f"Mode     : {CONFIG['mode']}", "info")
    log(f"Interval : {interval}s", "info")
    log(f"Max      : {'unlimited' if max_rot == 0 else max_rot}", "info")
    log(f"Countries: {CONFIG['country_filter'] or 'all'}", "info")
    print()

    # Show current IP
    log("IP sebelum VPN:", "info")
    show_ip()
    print()

    rotation_count = 0
    try:
        while True:
            rotation_count += 1
            if max_rot > 0 and rotation_count > max_rot:
                log(f"Max rotations ({max_rot}) reached", "ok")
                break

            log(f"Rotation #{rotation_count}", "step")

            success = False
            for retry in range(CONFIG["retry_count"]):
                if rotator.rotate():
                    success = True
                    break
                log(f"Retry {retry + 1}/{CONFIG['retry_count']}...", "warn")
                time.sleep(3)

            if not success:
                log("Rotation gagal setelah retry", "error")

            show_ip()

            if interval > 0:
                log(f"Next rotation in {interval}s (Ctrl+C to stop)", "info")
                time.sleep(interval)
            else:
                input("\n  Tekan Enter untuk rotate lagi (Ctrl+C to stop)...")

    except KeyboardInterrupt:
        print()
        log("Stopped by user", "warn")
    finally:
        print()
        cleanup = input("  Disconnect VPN? [Y/n]: ").strip().lower()
        if cleanup != "n":
            rotator.cleanup()
            log("VPN disconnected", "ok")


def single_rotate():
    """Rotate IP sekali."""
    print()
    log("SINGLE IP ROTATION", "step")
    print()

    log("IP sebelum:", "info")
    show_ip()
    print()

    rotator = get_rotator()
    if rotator.rotate():
        print()
        log("IP sesudah:", "info")
        show_ip()
    else:
        log("Rotation gagal", "error")


# ================== MAIN MENU ==================
def main():
    load_config()

    while True:
        print()
        print("=" * 55)
        print("  PROTONVPN IP ROTATOR")
        print("=" * 55)
        print()
        print(f"  Mode: {CONFIG['mode']} | Interval: {CONFIG['rotate_interval']}s")
        print(f"  Countries: {CONFIG['country_filter'] or 'all'}")
        print()
        print("  1. Auto rotate (loop)")
        print("  2. Single rotate (sekali)")
        print("  3. Cek IP sekarang")
        print("  4. Disconnect VPN")
        print("  5. Setup config")
        print()
        print("  0. Exit")
        print("=" * 55)

        choice = input("  Pilih: ").strip()

        if choice == "1":
            auto_rotate()
        elif choice == "2":
            single_rotate()
        elif choice == "3":
            print()
            show_ip()
        elif choice == "4":
            rotator = get_rotator()
            rotator.disconnect()
            log("Disconnected", "ok")
        elif choice == "5":
            setup_config()
        elif choice == "0":
            log("Exit", "info")
            break
        else:
            log("Pilihan tidak valid", "error")


if __name__ == "__main__":
    main()
