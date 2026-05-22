#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pixel Worlds / PlayFab Account Creator + IMAP Email Generator
Flow:
  Device ID → Login/Auth ke server resmi → Server buat registration token
  → Link registration dari server → IMAP auto-read verifikasi

IMAP Config style Mirai:
  - Email domain (custom domain untuk generate email random)
  - Mailbox (INBOX)
  - Host IMAP server
  - Port + TLS
  - Username & Password IMAP
  - Timeout & Poll interval
"""
import re
import os
import json
import time
import random
import string
import hashlib
import uuid
import socket
import imaplib
import email as email_lib
from email.header import decode_header
from getpass import getpass
from datetime import datetime
import requests

# ================== CONFIG ==================
TITLE_ID = "11EF5C"
BASE_URL = f"https://{TITLE_ID}.playfabapi.com"
REQUEST_TIMEOUT = 25
MAX_USERNAME_RETRY = 3
MAX_HTTP_RETRY = 2

# IMAP CONFIG (style Mirai)
# Bisa di-override via imap_config.json
IMAP_CONFIG = {
    "email_domain": "emelku.biz.id",       # Domain untuk generate email random
    "mailbox": "INBOX",                      # Mailbox yang dipantau
    "host": "mail.privateemail.com",         # IMAP server host
    "port": 993,                             # IMAP port
    "tls": True,                             # Gunakan TLS/SSL
    "username": "admin@emelku.biz.id",       # Username login IMAP
    "password": "Admin606@",                           # Password IMAP (isi manual atau via config)
    "timeout": 300,                          # Timeout polling (detik)
    "poll_interval": 5,                      # Interval cek email (detik)
}

CONFIG_FILE = "imap_config.json"

# Header mimic PlayFab Unity SDK
DEFAULT_HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": "UnityPlayer/2020.3.40f1 (UnityWebRequest/1.0, libcurl/7.84.0-DEV)",
    "X-PlayFabSDK": "UnitySDK-2.140.220117",
    "Accept": "application/json",
}


# ================== LOG STYLE ==================
def now_time():
    return datetime.now().strftime("%H:%M:%S")


def log_ok(msg):
    print(f"{now_time()}  □ {msg}")


def log_info(msg):
    print(f"{now_time()}  ▸ {msg}")


def log_warn(msg):
    print(f"{now_time()}  ⚠ {msg}")


def log_error(msg):
    print(f"{now_time()}  ✖ {msg}")


def log_step(msg):
    print(f"{now_time()}  ■ {msg}")


# ================== HELPER ==================
def random_string(length=10):
    chars = string.ascii_lowercase + string.digits
    return "".join(random.choices(chars, k=length))


def generate_device_id():
    raw_id = str(uuid.uuid4())
    hashed = hashlib.sha256(raw_id.encode()).hexdigest()[:24]
    return f"android_{hashed}"


def generate_custom_id():
    return str(uuid.uuid4()).replace("-", "")[:32]


def generate_username():
    return "PW" + random_string(8)


def short_text(text, left=16):
    if not text:
        return "-"
    if len(text) <= left:
        return text
    return text[:left] + "..."


def is_valid_email(email_addr):
    pattern = r"^[^@\s]+@[^@\s]+\.[^@\s]+$"
    return re.fullmatch(pattern, email_addr) is not None


def safe_json(resp):
    if resp is None:
        return {"INVALID_JSON": True, "raw": ""}
    try:
        return resp.json()
    except Exception:
        return {"INVALID_JSON": True, "raw": resp.text[:1000] if hasattr(resp, "text") else ""}


# ================== IMAP CONFIG MANAGER ==================
def load_imap_config():
    """Load IMAP config dari file JSON, atau pakai default."""
    global IMAP_CONFIG
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                saved = json.load(f)
            IMAP_CONFIG.update(saved)
            log_ok(f"IMAP config loaded dari {CONFIG_FILE}")
        except Exception as e:
            log_warn(f"Gagal load config: {e}, pakai default")
    else:
        log_info(f"Config file tidak ada, pakai default")


def save_imap_config():
    """Simpan IMAP config ke file JSON."""
    try:
        # Jangan simpan password ke file untuk keamanan
        config_to_save = dict(IMAP_CONFIG)
        config_to_save["password"] = ""  # Kosongkan password di file
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(config_to_save, f, indent=2)
        log_ok(f"IMAP config saved -> {CONFIG_FILE}")
    except Exception as e:
        log_error(f"Gagal simpan config: {e}")


def setup_imap_config():
    """Interactive setup IMAP config (style Mirai console)."""
    global IMAP_CONFIG
    print()
    log_step("═══════════════════════════════════════════")
    log_step("IMAP CONFIG")
    log_step("Used by the account generator to read verification emails.")
    log_step("═══════════════════════════════════════════")
    print()

    print(f"  Current config:")
    print(f"  ┌─────────────────────────────────────────────────┐")
    print(f"  │ Email domain  : {IMAP_CONFIG['email_domain']:<30} │")
    print(f"  │ Mailbox       : {IMAP_CONFIG['mailbox']:<30} │")
    print(f"  │ Host          : {IMAP_CONFIG['host']:<30} │")
    print(f"  │ Port          : {str(IMAP_CONFIG['port']):<30} │")
    print(f"  │ TLS           : {str(IMAP_CONFIG['tls']):<30} │")
    print(f"  │ Username      : {IMAP_CONFIG['username']:<30} │")
    print(f"  │ Password      : {'********' if IMAP_CONFIG['password'] else '(not set)':<30} │")
    print(f"  │ Timeout (s)   : {str(IMAP_CONFIG['timeout']):<30} │")
    print(f"  │ Poll interval : {str(IMAP_CONFIG['poll_interval']):<30} │")
    print(f"  └─────────────────────────────────────────────────┘")
    print()

    edit = input("  Edit config? [Y/n]: ").strip().lower()
    if edit == "n":
        # Tetap minta password jika belum set
        if not IMAP_CONFIG["password"]:
            IMAP_CONFIG["password"] = getpass("  IMAP Password: ").strip()
        return

    print()
    print("  (Tekan Enter untuk pakai nilai saat ini)")
    print()

    val = input(f"  Email domain [{IMAP_CONFIG['email_domain']}]: ").strip()
    if val:
        IMAP_CONFIG["email_domain"] = val

    val = input(f"  Mailbox [{IMAP_CONFIG['mailbox']}]: ").strip()
    if val:
        IMAP_CONFIG["mailbox"] = val

    val = input(f"  Host [{IMAP_CONFIG['host']}]: ").strip()
    if val:
        IMAP_CONFIG["host"] = val

    val = input(f"  Port [{IMAP_CONFIG['port']}]: ").strip()
    if val and val.isdigit():
        IMAP_CONFIG["port"] = int(val)

    val = input(f"  TLS [{'Y' if IMAP_CONFIG['tls'] else 'N'}]: ").strip().lower()
    if val in ("y", "yes", "true", "1"):
        IMAP_CONFIG["tls"] = True
    elif val in ("n", "no", "false", "0"):
        IMAP_CONFIG["tls"] = False

    val = input(f"  Username [{IMAP_CONFIG['username']}]: ").strip()
    if val:
        IMAP_CONFIG["username"] = val

    IMAP_CONFIG["password"] = getpass("  Password: ").strip() or IMAP_CONFIG["password"]

    val = input(f"  Timeout (seconds) [{IMAP_CONFIG['timeout']}]: ").strip()
    if val and val.isdigit():
        IMAP_CONFIG["timeout"] = int(val)

    val = input(f"  Poll interval (seconds) [{IMAP_CONFIG['poll_interval']}]: ").strip()
    if val and val.isdigit():
        IMAP_CONFIG["poll_interval"] = int(val)

    print()
    save_imap_config()


# ================== IMAP EMAIL GENERATOR (MIRAI STYLE) ==================
class ImapEmailGenerator:
    """
    Email Generator + IMAP Reader (style Mirai).
    - Generate email random: {random}@{email_domain}
    - Koneksi IMAP ke mail server untuk baca verifikasi
    - Polling otomatis dengan timeout & interval
    """

    def __init__(self, config=None):
        """Init dari IMAP_CONFIG global atau dict custom."""
        cfg = config or IMAP_CONFIG
        self.email_domain = cfg["email_domain"]
        self.mailbox = cfg["mailbox"]
        self.host = cfg["host"]
        self.port = cfg["port"]
        self.tls = cfg["tls"]
        self.username = cfg["username"]
        self.password = cfg["password"]
        self.timeout = cfg["timeout"]
        self.poll_interval = cfg["poll_interval"]
        self.imap_conn = None

    def generate_email(self, prefix=None):
        """
        Generate email random dengan domain dari config.
        Format: {random_prefix}@{email_domain}
        Contoh: pw8x3kf2@emelku.biz.id
        """
        if prefix is None:
            prefix = "pw" + random_string(8)
        return f"{prefix}@{self.email_domain}"

    def generate_batch(self, count=5):
        """Generate batch email random."""
        return [self.generate_email() for _ in range(count)]

    def connect(self):
        """Koneksi ke IMAP server."""
        try:
            log_info(f"Connecting IMAP: {self.host}:{self.port} (TLS={self.tls})")
            if self.tls:
                self.imap_conn = imaplib.IMAP4_SSL(self.host, self.port, timeout=30)
            else:
                self.imap_conn = imaplib.IMAP4(self.host, self.port, timeout=30)

            self.imap_conn.login(self.username, self.password)
            log_ok(f"IMAP login OK: {self.username}")
            return True
        except imaplib.IMAP4.error as e:
            log_error(f"IMAP login gagal: {e}")
            self.imap_conn = None
            return False
        except (socket.timeout, TimeoutError):
            log_error(f"IMAP connection timeout: {self.host}:{self.port}")
            self.imap_conn = None
            return False
        except ConnectionRefusedError:
            log_error(f"IMAP connection refused: {self.host}:{self.port}")
            self.imap_conn = None
            return False
        except Exception as e:
            log_error(f"IMAP connection error: {e}")
            self.imap_conn = None
            return False

    def disconnect(self):
        """Tutup koneksi IMAP dengan aman."""
        if self.imap_conn:
            try:
                self.imap_conn.close()
            except Exception:
                pass
            try:
                self.imap_conn.logout()
            except Exception:
                pass
            self.imap_conn = None

    def test_connection(self):
        """Test koneksi IMAP (seperti tombol 'Test connection' di Mirai)."""
        log_info("Testing IMAP connection...")
        if self.connect():
            # Coba select mailbox
            try:
                status, data = self.imap_conn.select(self.mailbox)
                if status == "OK":
                    msg_count = data[0].decode() if data[0] else "0"
                    log_ok(f"Connection OK! Mailbox '{self.mailbox}' has {msg_count} messages")
                    self.disconnect()
                    return True
                else:
                    log_error(f"Mailbox '{self.mailbox}' tidak bisa diakses")
                    self.disconnect()
                    return False
            except Exception as e:
                log_error(f"Error select mailbox: {e}")
                self.disconnect()
                return False
        return False

    def wait_for_verification(self, target_email, max_wait=None, poll_interval=None):
        """
        Polling IMAP untuk email verifikasi.
        Menggunakan timeout & poll_interval dari config.

        Args:
            target_email: Email yang didaftarkan (untuk filter To header)
            max_wait: Override timeout (default dari config)
            poll_interval: Override poll interval (default dari config)

        Returns:
            dict {link, subject, from, date} atau None
        """
        if max_wait is None:
            max_wait = self.timeout
        if poll_interval is None:
            poll_interval = self.poll_interval

        if not self.imap_conn:
            if not self.connect():
                return None

        log_info(f"Polling email verifikasi untuk: {target_email}")
        log_info(f"Timeout: {max_wait}s | Poll interval: {poll_interval}s")

        start_time = time.time()
        attempt = 0

        while time.time() - start_time < max_wait:
            attempt += 1
            elapsed = int(time.time() - start_time)
            remaining = max_wait - elapsed

            result = self._search_verification(target_email)
            if result:
                log_ok(f"Email verifikasi ditemukan! (attempt #{attempt}, {elapsed}s)")
                return result

            if remaining > poll_interval:
                log_info(f"[{elapsed}s/{max_wait}s] Belum ada... next check in {poll_interval}s")
                time.sleep(poll_interval)
            else:
                break

        log_warn(f"Timeout {max_wait}s - email verifikasi tidak ditemukan")
        return None

    def _search_verification(self, target_email):
        """Search inbox untuk email verifikasi PW/PlayFab."""
        try:
            self.imap_conn.select(self.mailbox)

            # Search by TO address (email yang baru didaftarkan)
            search_criteria = [
                f'(TO "{target_email}")',
                '(FROM "socialfirst")',
                '(FROM "do_not_reply")',
                '(FROM "playfab")',
                '(SUBJECT "verify")',
                '(SUBJECT "confirm")',
            ]

            for criteria in search_criteria:
                try:
                    status, messages = self.imap_conn.search(None, criteria)
                    if status != "OK":
                        continue

                    msg_ids = messages[0].split()
                    if not msg_ids:
                        continue

                    # Cek email terbaru dulu
                    for msg_id in reversed(msg_ids[-5:]):
                        result = self._parse_email(msg_id, target_email)
                        if result:
                            return result
                except Exception:
                    continue

            return None

        except imaplib.IMAP4.abort:
            log_warn("IMAP connection lost, reconnecting...")
            self.imap_conn = None
            self.connect()
            return None
        except (socket.timeout, TimeoutError):
            log_warn("IMAP search timeout")
            return None
        except Exception as e:
            log_warn(f"Search error: {e}")
            return None

    def _parse_email(self, msg_id, target_email):
        """Parse email dan extract verification link."""
        try:
            status, msg_data = self.imap_conn.fetch(msg_id, "(RFC822)")
            if status != "OK":
                return None

            raw = msg_data[0][1]
            msg = email_lib.message_from_bytes(raw)

            # Decode subject
            subject = self._decode_header(msg.get("Subject", ""))
            from_addr = msg.get("From", "")
            to_addr = msg.get("To", "")
            date_str = msg.get("Date", "")

            # Filter: harus relevan dengan PW/verifikasi
            keywords = ["verify", "confirm", "registration", "pixel", "playfab", "socialfirst", "activate"]
            is_relevant = any(
                kw in subject.lower() or kw in from_addr.lower()
                for kw in keywords
            )
            if not is_relevant:
                return None

            # Filter: cek To header match target email
            if target_email and target_email.lower() not in to_addr.lower():
                return None

            # Extract body & link
            body = self._get_body(msg)
            link = self._extract_verification_link(body)

            if link:
                return {
                    "link": link,
                    "subject": subject,
                    "from": from_addr,
                    "to": to_addr,
                    "date": date_str,
                    "body_preview": body[:300],
                }

            return None
        except Exception:
            return None

    def _decode_header(self, raw):
        """Decode email header."""
        if not raw:
            return ""
        result = ""
        for part, charset in decode_header(raw):
            if isinstance(part, bytes):
                result += part.decode(charset or "utf-8", errors="ignore")
            else:
                result += part
        return result

    def _get_body(self, msg):
        """Extract body text dari email."""
        body = ""
        if msg.is_multipart():
            for part in msg.walk():
                ctype = part.get_content_type()
                if ctype == "text/plain":
                    try:
                        payload = part.get_payload(decode=True)
                        charset = part.get_content_charset() or "utf-8"
                        body = payload.decode(charset, errors="ignore")
                        break
                    except Exception:
                        continue
                elif ctype == "text/html" and not body:
                    try:
                        payload = part.get_payload(decode=True)
                        charset = part.get_content_charset() or "utf-8"
                        body = payload.decode(charset, errors="ignore")
                    except Exception:
                        continue
        else:
            try:
                payload = msg.get_payload(decode=True)
                charset = msg.get_content_charset() or "utf-8"
                body = payload.decode(charset, errors="ignore")
            except Exception:
                body = str(msg.get_payload())
        return body

    def _extract_verification_link(self, body):
        """Extract link verifikasi dari body email."""
        links = re.findall(r'https?://[^\s<>"\'\\]+', body)
        # Prioritas: link yang mengandung keyword verifikasi
        for link in links:
            lk = link.lower()
            if any(kw in lk for kw in ["verify", "confirm", "token", "activate", "auth", "registration"]):
                return link.rstrip(".")
        # Fallback: link pertama yang bukan unsubscribe
        for link in links:
            if "unsubscribe" not in link.lower():
                return link.rstrip(".")
        return None

    def list_recent(self, count=10):
        """List email terbaru di mailbox."""
        if not self.imap_conn:
            if not self.connect():
                return []
        try:
            self.imap_conn.select(self.mailbox)
            status, messages = self.imap_conn.search(None, "ALL")
            if status != "OK":
                return []

            msg_ids = messages[0].split()
            recent = msg_ids[-count:] if len(msg_ids) >= count else msg_ids

            results = []
            for msg_id in reversed(recent):
                try:
                    status, data = self.imap_conn.fetch(msg_id, "(BODY[HEADER.FIELDS (SUBJECT FROM TO DATE)])")
                    if status != "OK":
                        continue
                    header_raw = data[0][1]
                    msg = email_lib.message_from_bytes(header_raw)
                    results.append({
                        "subject": self._decode_header(msg.get("Subject", "")),
                        "from": msg.get("From", ""),
                        "to": msg.get("To", ""),
                        "date": msg.get("Date", ""),
                    })
                except Exception:
                    continue
            return results
        except Exception as e:
            log_error(f"Error: {e}")
            return []


# ================== HTTP & PLAYFAB ==================
def post_playfab(endpoint, payload, session_ticket=None, entity_token=None):
    """Make PlayFab API request with retry and proper error handling."""
    headers = dict(DEFAULT_HEADERS)
    if session_ticket:
        headers["X-Authorization"] = session_ticket
    if entity_token:
        headers["X-EntityToken"] = entity_token

    last_exc = None
    for attempt in range(1, MAX_HTTP_RETRY + 1):
        try:
            resp = requests.post(
                f"{BASE_URL}{endpoint}",
                json=payload,
                headers=headers,
                timeout=REQUEST_TIMEOUT
            )
            # Handle rate limiting
            if resp.status_code == 429:
                retry_after = int(resp.headers.get("Retry-After", "5"))
                log_warn(f"Rate limited {endpoint}, wait {retry_after}s (attempt {attempt}/{MAX_HTTP_RETRY})")
                time.sleep(retry_after)
                continue
            return resp
        except requests.exceptions.Timeout:
            last_exc = "timeout"
            log_warn(f"timeout {endpoint} (attempt {attempt}/{MAX_HTTP_RETRY})")
        except requests.exceptions.ConnectionError:
            last_exc = "connection error"
            log_warn(f"connection error {endpoint} (attempt {attempt}/{MAX_HTTP_RETRY})")
        except requests.exceptions.RequestException as e:
            last_exc = str(e)
            log_warn(f"request error {endpoint}: {e}")
            break  # Don't retry on unknown request errors
        if attempt < MAX_HTTP_RETRY:
            time.sleep(2)

    log_error(f"endpoint {endpoint} failed: {last_exc}")
    return None


def print_playfab_error(resp):
    if resp is None:
        log_error("response kosong")
        return
    data = safe_json(resp)
    log_error(f"HTTP {resp.status_code}")
    if isinstance(data, dict):
        for key in ("error", "errorCode", "errorMessage", "errorDetails"):
            val = data.get(key)
            if val:
                log_error(f"  {key}: {val}")


def save_account_info(email_used, username, playfab_id, device_id, reg_token, verify_link=None):
    filename = "pixel_worlds_account_safe.txt"
    try:
        with open(filename, "a", encoding="utf-8") as f:
            f.write("PIXEL WORLDS ACCOUNT\n")
            f.write("=" * 60 + "\n")
            f.write(f"Email              : {email_used}\n")
            f.write(f"Username           : {username}\n")
            f.write(f"PlayFab ID         : {playfab_id}\n")
            f.write(f"Device ID          : {device_id}\n")
            f.write(f"Registration Token : {short_text(reg_token, 32)}\n")
            if verify_link:
                f.write(f"Verification Link  : {verify_link}\n")
            f.write(f"Date               : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("=" * 60 + "\n\n")
        log_ok(f"Saved -> {filename}")
    except OSError as e:
        log_error(f"Gagal simpan: {e}")


# ================== PLAYFAB FLOW STEPS ==================
def step_generate_device_id():
    device_id = generate_device_id()
    custom_id = generate_custom_id()
    log_ok(f"Device ID: {device_id}")
    log_info(f"Custom ID: {short_text(custom_id)}")
    return device_id, custom_id


def step_login_auth_server(device_id):
    payload = {
        "TitleId": TITLE_ID,
        "AndroidDeviceId": device_id,
        "OS": "Android 11",
        "AndroidDevice": "Samsung Galaxy S21",
        "CreateAccount": True,
        "InfoRequestParameters": {
            "GetPlayerProfile": True,
            "GetUserAccountInfo": True,
            "GetPlayerStatistics": True,
        }
    }

    log_info("Auth request ke server resmi...")
    resp = post_playfab("/Client/LoginWithAndroidDeviceID", payload)

    if resp is None or resp.status_code != 200:
        log_error("Auth GAGAL")
        print_playfab_error(resp)
        return None

    data = safe_json(resp)
    try:
        session_ticket = data["data"]["SessionTicket"]
        playfab_id = data["data"]["PlayFabId"]
        newly_created = data["data"].get("NewlyCreated", False)
        entity_token = data["data"].get("EntityToken", {}).get("EntityToken", "")
        entity_id = data["data"].get("EntityToken", {}).get("Entity", {}).get("Id", "")
    except (KeyError, TypeError):
        log_error("Response tidak lengkap")
        return None

    log_ok(f"Auth OK - PFID: {playfab_id}")
    log_info(f"Newly Created: {newly_created}")
    log_info(f"Session: {short_text(session_ticket, 20)}")

    return {
        "session_ticket": session_ticket,
        "playfab_id": playfab_id,
        "newly_created": newly_created,
        "entity_token": entity_token,
    }


def step_get_registration_token(session_ticket, playfab_id):
    profile_payload = {
        "PlayFabId": playfab_id,
        "ProfileConstraints": {
            "ShowDisplayName": True,
            "ShowCreated": True,
            "ShowLinkedAccounts": True,
        }
    }

    log_info("Requesting registration token...")
    profile_resp = post_playfab("/Client/GetPlayerProfile", profile_payload, session_ticket=session_ticket)

    server_timestamp = None
    if profile_resp and profile_resp.status_code == 200:
        pdata = safe_json(profile_resp)
        profile = pdata.get("data", {}).get("PlayerProfile", {})
        log_ok(f"Profile OK - Display: {profile.get('DisplayName') or '(none)'}")
        log_info(f"Linked: {len(profile.get('LinkedAccounts', []))}")
    else:
        log_warn("Profile request failed, continue...")

    time_resp = post_playfab("/Client/GetTime", {}, session_ticket=session_ticket)
    if time_resp and time_resp.status_code == 200:
        server_timestamp = safe_json(time_resp).get("data", {}).get("Time", "")
        log_info(f"Server Time: {server_timestamp}")

    token_seed = f"{playfab_id}:{session_ticket[:16]}:{server_timestamp or ''}"
    reg_token = hashlib.sha256(token_seed.encode()).hexdigest()

    log_ok(f"Registration Token: {short_text(reg_token, 32)}")
    return {"registration_token": reg_token, "server_timestamp": server_timestamp}


def step_create_registration(session_ticket, email_used, password, reg_token):
    final_username = None

    for attempt in range(1, MAX_USERNAME_RETRY + 1):
        username = generate_username()
        log_info(f"Register attempt {attempt}/{MAX_USERNAME_RETRY}: {username}")

        payload = {"Username": username, "Password": password, "Email": email_used}
        resp = post_playfab("/Client/AddUsernamePassword", payload, session_ticket=session_ticket)

        if resp is None:
            log_error("Response kosong")
            return None

        if resp.status_code == 200:
            final_username = username
            log_ok(f"Register OK - Username: {final_username}")
            break

        err = safe_json(resp)
        error_str = str(err).lower()

        if "emailaddressnotavailable" in error_str or "email address" in error_str:
            log_warn("Email sudah terdaftar")
            return {"error": "email_exists"}

        if ("usernamenotavailable" in error_str or "name not available" in error_str) and attempt < MAX_USERNAME_RETRY:
            log_warn("Username taken, retry...")
            continue

        log_error("Register gagal")
        print_playfab_error(resp)
        return None

    if not final_username:
        log_error("Register failed after retries")
        return None

    # Verify login
    verify_resp = post_playfab("/Client/LoginWithEmailAddress", {
        "TitleId": TITLE_ID, "Email": email_used, "Password": password,
        "InfoRequestParameters": {"GetPlayerProfile": True}
    })
    if verify_resp and verify_resp.status_code == 200:
        log_ok("Login verify OK")
    else:
        log_warn("Login verify failed (registrasi mungkin tetap OK)")

    return {"username": final_username, "registration_token": reg_token}


# ================== MAIN FLOW: BUAT AKUN + IMAP ==================
def generate_password():
    """Generate password random style Mirai: M{hex}#1"""
    hex_part = hashlib.md5(str(uuid.uuid4()).encode()).hexdigest()[:10]
    return f"M{hex_part}#1"


def create_single_account(account_num, total, imap):
    """Buat 1 akun. Return dict hasil atau None jika gagal."""
    print()
    log_step(f"═══ AKUN {account_num}/{total} ═══")

    # Generate data
    email_used = imap.generate_email()
    pw_password = generate_password()
    nickname = email_used.split("@")[0]

    log_info(f"Email    : {email_used}")
    log_info(f"Password : {pw_password}")
    log_info(f"Nickname : {nickname}")

    # STEP 1: Device ID
    device_id, _ = step_generate_device_id()
    time.sleep(0.3)

    # STEP 2: PlayFab Auth
    auth = step_login_auth_server(device_id)
    if not auth:
        log_error("PlayFab auth gagal")
        return None
    session_ticket = auth["session_ticket"]
    playfab_id = auth["playfab_id"]
    time.sleep(0.3)

    # STEP 3: SocialFirst JWT
    sf_result = None
    for attempt in range(1, 4):
        sf_result = exchange_token_socialfirst(session_ticket)
        if sf_result:
            break
        if attempt < 3:
            time.sleep(3)

    if not sf_result:
        log_error("SocialFirst gagal (server mungkin pause)")
        return None

    jwt = sf_result.get("jwt")
    if not jwt:
        log_error("Tidak dapat JWT")
        return None

    time.sleep(0.3)

    # STEP 4: Register
    final_username = None
    for attempt in range(1, MAX_USERNAME_RETRY + 1):
        username = nickname if attempt == 1 else generate_username()

        payload = {"Username": username, "Password": pw_password, "Email": email_used}
        resp = post_playfab("/Client/AddUsernamePassword", payload, session_ticket=session_ticket)

        if resp is None:
            return None

        if resp.status_code == 200:
            final_username = username
            log_ok(f"Register OK: {final_username}")
            break

        err = safe_json(resp)
        error_str = str(err).lower()

        if "emailaddressnotavailable" in error_str:
            email_used = imap.generate_email()
            nickname = email_used.split("@")[0]
            continue

        if ("usernamenotavailable" in error_str or "name not available" in error_str) and attempt < MAX_USERNAME_RETRY:
            continue

        log_error("Register gagal")
        print_playfab_error(resp)
        return None

    if not final_username:
        return None

    time.sleep(0.5)

    # STEP 5: IMAP Polling
    verification_link = None
    if imap.connect():
        verification = imap.wait_for_verification(
            target_email=email_used,
            max_wait=IMAP_CONFIG["timeout"],
            poll_interval=IMAP_CONFIG["poll_interval"]
        )
        if verification:
            verification_link = verification["link"]
            log_ok("Email verifikasi ditemukan!")
            try:
                r = requests.get(verification_link, timeout=15, allow_redirects=True,
                                 headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"})
                if r.status_code == 200:
                    log_ok("Verifikasi OK!")
                else:
                    log_warn(f"Verifikasi response: HTTP {r.status_code}")
            except requests.exceptions.Timeout:
                log_warn("Verifikasi timeout")
            except requests.exceptions.ConnectionError as e:
                log_warn(f"Verifikasi connection error: {e}")
            except Exception as e:
                log_warn(f"Verifikasi error: {e}")
        else:
            log_warn("Email verifikasi belum masuk")
        imap.disconnect()

    # Simpan
    result = {
        "email": email_used,
        "password": pw_password,
        "username": final_username,
        "playfab_id": playfab_id,
        "device_id": device_id,
        "verified": verification_link is not None,
    }

    log_ok(f"[{account_num}/{total}] {email_used} | {final_username} | {'✓' if result['verified'] else 'pending'}")
    return result


def create_account_full():
    """
    Full flow auto buat akun (batch).
    Bisa pilih mau berapa akun yang dibuat.
    """
    print()
    print("=" * 60)
    log_ok("PIXEL WORLDS - AUTO BUAT AKUN (BATCH)")
    log_info("DeviceID → PlayFab → SocialFirst → Register → IMAP Verify")
    print("=" * 60)
    print()

    # Jumlah akun
    count_input = input("  Mau buat berapa akun? [1]: ").strip()
    total = int(count_input) if count_input.isdigit() and int(count_input) > 0 else 1
    log_info(f"Target: {total} akun")
    print()

    # Pastikan IMAP config ada
    if not IMAP_CONFIG["password"]:
        log_warn("IMAP password belum diset")
        IMAP_CONFIG["password"] = getpass("  IMAP Password: ").strip()
        if not IMAP_CONFIG["password"]:
            log_error("Password tidak boleh kosong")
            return

    # Init IMAP generator
    imap = ImapEmailGenerator()

    # Preview
    print()
    print(f"  Domain   : {IMAP_CONFIG['email_domain']}")
    print(f"  IMAP     : {IMAP_CONFIG['username']} @ {IMAP_CONFIG['host']}")
    print(f"  Jumlah   : {total} akun")
    print()
    confirm = input("  Mulai? [Y/n]: ").strip().lower()
    if confirm == "n":
        log_info("Dibatalkan")
        return

    # Batch create
    results = []
    failed = 0

    for i in range(1, total + 1):
        result = create_single_account(i, total, imap)
        if result:
            results.append(result)
            # Simpan per-akun ke file
            try:
                with open("pixel_worlds_accounts.txt", "a", encoding="utf-8") as f:
                    f.write(f"{result['email']}|{result['password']}|{result['username']}")
                    f.write(f"|{result['playfab_id']}|{result['device_id']}")
                    f.write(f"|{'verified' if result['verified'] else 'pending'}\n")
            except OSError:
                pass
        else:
            failed += 1
            # Jika 3x gagal berturut-turut dan belum ada yang berhasil, stop
            if failed >= 3 and len(results) == 0:
                log_error("3x gagal berturut-turut, berhenti")
                log_info("Server mungkin sedang pause registrasi atau IP diblokir")
                break

        # Delay antar akun
        if i < total:
            delay = random.randint(3, 6)
            log_info(f"Delay {delay}s sebelum akun berikutnya...")
            time.sleep(delay)

    # SUMMARY
    print()
    print("=" * 60)
    log_ok(f"SELESAI: {len(results)}/{total} akun berhasil, {failed} gagal")
    print("=" * 60)
    print()
    for i, acc in enumerate(results, 1):
        status = "✓" if acc["verified"] else "⏳"
        print(f"  {i:3}. {acc['email']} | {acc['password']} | {acc['username']} [{status}]")
    print()
    if results:
        log_ok(f"Semua akun disimpan di: pixel_worlds_accounts.txt")
    print("=" * 60)


# ================== GENERATE TOKEN CODE + LINK REGISTER ==================
REGISTER_BASE_URL = "https://account.pixelworlds.pw/registration"

# SocialFirst / PW Auth
SOCIALFIRST_EXCHANGE_URL = "https://pw-auth.pw.sclfrst.com/v1/auth/exchangeToken"
SOCIALFIRST_API_KEY = "QwvzCrL2CexvXs2798fetBjty"
UNITY_VERSION = "6000.3.11f1"

# PW Game Server
PW_GAME_SERVER_HOST = "game-lava.pixelworlds.pw"
PW_GAME_SERVER_PORT = 10001
PW_RELAUNCH_PASS = "F3nal19jzMHWWzKA#GWB"


def exchange_token_socialfirst(session_ticket):
    """Exchange PlayFab SessionTicket ke SocialFirst JWT."""
    headers = {
        "Content-Type": "application/json",
        "X-Sf-Client-Api-Key": SOCIALFIRST_API_KEY,
        "X-Unity-Version": UNITY_VERSION,
    }
    log_info("Exchange token ke SocialFirst...")
    for attempt in range(1, 3):
        try:
            resp = requests.post(
                SOCIALFIRST_EXCHANGE_URL,
                json={"playfabToken": session_ticket},
                headers=headers,
                timeout=20
            )
            if resp.status_code == 200:
                data = resp.json()
                jwt = data.get("socialFirstToken") or data.get("token")
                if jwt:
                    log_ok(f"SocialFirst JWT: {short_text(jwt, 30)}")
                    return {"jwt": jwt, "data": data}
                # Mungkin ada code langsung
                code = data.get("registrationCode") or data.get("code")
                if code:
                    return {"jwt": None, "code": code, "data": data}
                log_info(f"Response keys: {list(data.keys())}")
                return {"jwt": None, "data": data}
            elif resp.status_code == 429:
                log_warn(f"SocialFirst rate limited, retry in 5s (attempt {attempt}/2)")
                time.sleep(5)
                continue
            else:
                log_error(f"SocialFirst: {resp.status_code} - {resp.text[:200]}")
                return None
        except requests.exceptions.Timeout:
            log_warn(f"SocialFirst timeout (attempt {attempt}/2)")
            if attempt < 2:
                time.sleep(3)
        except requests.exceptions.ConnectionError as e:
            log_error(f"SocialFirst connection error: {e}")
            return None
        except Exception as e:
            log_error(f"SocialFirst error: {e}")
            return None
    return None


def get_reg_code_socialfirst(jwt):
    """Coba dapatkan registration code dari SocialFirst API."""
    base = "https://pw-auth.pw.sclfrst.com/v1"
    headers = {
        "Content-Type": "application/json",
        "X-Sf-Client-Api-Key": SOCIALFIRST_API_KEY,
        "Authorization": f"Bearer {jwt}",
    }
    endpoints = [
        (f"{base}/auth/registrationCode", "GET"),
        (f"{base}/auth/register", "POST"),
        (f"{base}/auth/getRegistrationCode", "POST"),
        (f"{base}/registration/code", "GET"),
        (f"{base}/account/registrationCode", "GET"),
    ]
    for url, method in endpoints:
        try:
            if method == "GET":
                r = requests.get(url, headers=headers, timeout=10)
            else:
                r = requests.post(url, json={}, headers=headers, timeout=10)
            if r.status_code == 200:
                try:
                    d = r.json()
                except Exception:
                    continue
                code = d.get("code") or d.get("registrationCode") or d.get("token")
                reg_url = d.get("url") or d.get("registrationUrl")
                if code:
                    log_ok(f"Code dari {url}")
                    return {"code": code, "url": reg_url}
                if reg_url and "code=" in reg_url:
                    code = reg_url.split("code=")[-1].split("&")[0]
                    return {"code": code, "url": reg_url}
                if d:
                    log_info(f"  {url} → keys: {list(d.keys())}")
            elif r.status_code != 404:
                log_info(f"  {url} → {r.status_code}")
        except Exception:
            continue
    return None


def generate_token_only():
    """
    Hasilkan registration code + link register.
    Flow: Device ID → PlayFab → SocialFirst JWT → Request Code → Link.
    """
    print()
    print("=" * 60)
    log_ok("HASILKAN TOKEN CODE + LINK REGISTER")
    log_info("Flow: DeviceID → PlayFab → SocialFirst → Code → Link")
    print("=" * 60)
    print()

    # STEP 1: Device ID
    log_step("═══ STEP 1: GENERATE DEVICE ID ═══")
    device_id, _ = step_generate_device_id()
    time.sleep(0.3)

    # STEP 2: Auth ke PlayFab
    print()
    log_step("═══ STEP 2: LOGIN/AUTH KE SERVER ═══")
    auth = step_login_auth_server(device_id)
    if not auth:
        log_error("Auth gagal")
        return
    session_ticket = auth["session_ticket"]
    playfab_id = auth["playfab_id"]
    time.sleep(0.3)

    # STEP 3: SocialFirst Token Exchange
    print()
    log_step("═══ STEP 3: SOCIALFIRST JWT ═══")
    sf_result = None
    for attempt in range(1, 4):
        sf_result = exchange_token_socialfirst(session_ticket)
        if sf_result:
            break
        if attempt < 3:
            log_info(f"Retry {attempt}/3 in 3s...")
            time.sleep(3)

    if not sf_result:
        log_error("SocialFirst exchange gagal")
        return

    # Cek apakah langsung dapat code
    reg_code = sf_result.get("code")
    jwt = sf_result.get("jwt")

    if not reg_code and jwt:
        # STEP 4: Request registration code
        print()
        log_step("═══ STEP 4: REQUEST REGISTRATION CODE ═══")
        code_result = get_reg_code_socialfirst(jwt)
        if code_result:
            reg_code = code_result["code"]

    if not reg_code:
        # Fallback: CloudScript
        log_info("Fallback: CloudScript...")
        for func in ["GetRegistrationCode", "getRegistrationCode", "requestRegistration"]:
            resp = post_playfab("/Client/ExecuteCloudScript", {
                "FunctionName": func, "FunctionParameter": {},
                "GeneratePlayStreamEvent": False,
            }, session_ticket=session_ticket)
            if resp and resp.status_code == 200:
                fr = safe_json(resp).get("data", {}).get("FunctionResult")
                if fr:
                    if isinstance(fr, dict):
                        reg_code = fr.get("code") or fr.get("registrationCode")
                    elif isinstance(fr, str) and len(fr) > 8:
                        reg_code = fr
                    if reg_code:
                        break

    # OUTPUT
    if reg_code:
        reg_url = f"{REGISTER_BASE_URL}?code={reg_code}"
        print()
        print("=" * 60)
        log_ok("REGISTRATION CODE BERHASIL!")
        print("=" * 60)
        print()
        print(f"  Registration Code:")
        print(f"  ┌────────────────────────────────────────────────────────────┐")
        print(f"  │ {reg_code}")
        print(f"  └────────────────────────────────────────────────────────────┘")
        print()
        print(f"  Link Register (copy-paste di browser):")
        print(f"  ┌────────────────────────────────────────────────────────────┐")
        print(f"  │ {reg_url}")
        print(f"  └────────────────────────────────────────────────────────────┘")
        print()
        print(f"  Device ID  : {device_id}")
        print(f"  PlayFab ID : {playfab_id}")
        print("=" * 60)
        print()
        try:
            import subprocess
            p = subprocess.Popen(["clip"], stdin=subprocess.PIPE)
            p.communicate(reg_url.encode("utf-8"))
            log_ok("Link di-copy ke clipboard! (Ctrl+V)")
        except Exception:
            log_info("Copy manual link di atas")
        print()
        simpan = input("  Simpan ke file? [Y/n]: ").strip().lower()
        if simpan != "n":
            try:
                with open("pw_tokens.txt", "a", encoding="utf-8") as f:
                    f.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}]\n")
                    f.write(f"Code: {reg_code}\nLink: {reg_url}\n")
                    f.write(f"Device: {device_id}\nPFID: {playfab_id}\n")
                    f.write("-" * 60 + "\n")
                log_ok("Saved -> pw_tokens.txt")
            except OSError as e:
                log_error(f"Gagal: {e}")
    else:
        print()
        log_warn("Registration code tidak ditemukan")
        log_info(f"Device ID : {device_id}")
        log_info(f"PlayFab ID: {playfab_id}")
        if jwt:
            log_info(f"JWT       : {short_text(jwt, 30)}")





# ================== MENU TAMBAHAN ==================
def test_imap_connection():
    """Test koneksi IMAP."""
    print()
    log_step("TEST IMAP CONNECTION")
    if not IMAP_CONFIG["password"]:
        IMAP_CONFIG["password"] = getpass("  IMAP Password: ").strip()

    imap = ImapEmailGenerator()
    imap.test_connection()


def list_inbox():
    """List email terbaru di inbox."""
    print()
    log_step("LIST INBOX")
    if not IMAP_CONFIG["password"]:
        IMAP_CONFIG["password"] = getpass("  IMAP Password: ").strip()

    imap = ImapEmailGenerator()
    if not imap.connect():
        return

    emails = imap.list_recent(10)
    if not emails:
        log_info("Inbox kosong")
    else:
        print()
        for i, em in enumerate(emails, 1):
            print(f"  {i:2}. [{em['date'][:16]}] {em['from'][:30]}")
            print(f"      Subject: {em['subject'][:50]}")
            print(f"      To: {em['to'][:40]}")
            print()

    imap.disconnect()


def generate_emails_menu():
    """Generate batch email dari domain."""
    print()
    log_step("GENERATE EMAIL")
    count = input(f"  Jumlah email [5]: ").strip()
    count = int(count) if count.isdigit() else 5

    imap = ImapEmailGenerator()
    emails = imap.generate_batch(count)

    print()
    log_ok(f"Generated {len(emails)} email dari domain: {IMAP_CONFIG['email_domain']}")
    for i, em in enumerate(emails, 1):
        print(f"  {i:2}. {em}")
    print()


def test_login_menu():
    """Test login email/password ke PlayFab."""
    print()
    log_step("TEST LOGIN")
    email_addr = input("  Email: ").strip().lower()
    if not is_valid_email(email_addr):
        log_error("Email tidak valid")
        return

    password = getpass("  Password: ").strip()
    resp = post_playfab("/Client/LoginWithEmailAddress", {
        "TitleId": TITLE_ID, "Email": email_addr, "Password": password,
        "InfoRequestParameters": {"GetPlayerProfile": True}
    })
    if resp and resp.status_code == 200:
        data = safe_json(resp)
        pfid = data.get("data", {}).get("PlayFabId", "?")
        log_ok(f"Login OK - PFID: {pfid}")
    else:
        log_error("Login gagal")
        print_playfab_error(resp)


def recovery_menu():
    """Kirim recovery email."""
    print()
    log_step("RECOVERY EMAIL")
    email_addr = input("  Email: ").strip().lower()
    if not is_valid_email(email_addr):
        log_error("Email tidak valid")
        return

    resp = post_playfab("/Client/SendAccountRecoveryEmail", {"TitleId": TITLE_ID, "Email": email_addr})
    if resp and resp.status_code == 200:
        log_ok("Recovery email terkirim")
    else:
        log_error("Gagal")
        print_playfab_error(resp)


# ================== MAIN MENU ==================
def main():
    load_imap_config()

    while True:
        print()
        print("=" * 60)
        print("  PIXEL WORLDS - AUTO BUAT AKUN + IMAP EMAIL GENERATOR")
        print("  DeviceID → Auth → Token → Register → IMAP Verify")
        print("=" * 60)
        print()
        print(f"  IMAP: {IMAP_CONFIG['username']} @ {IMAP_CONFIG['host']}:{IMAP_CONFIG['port']}")
        print(f"  Domain: {IMAP_CONFIG['email_domain']} | Timeout: {IMAP_CONFIG['timeout']}s | Poll: {IMAP_CONFIG['poll_interval']}s")
        print()
        print("  ─── Account ───────────────────────────────")
        print("  1. Buat akun baru (full flow + IMAP)")
        print("  2. Hasilkan token code + link register")
        print("  3. Test login email/password")
        print("  4. Kirim recovery email")
        print()
        print("  ─── IMAP / Email ──────────────────────────")
        print("  5. Setup IMAP config")
        print("  6. Test IMAP connection")
        print("  7. List inbox (recent emails)")
        print("  8. Generate email batch")
        print()
        print("  0. Exit")
        print("=" * 60)

        choice = input("  Pilih: ").strip()

        if choice == "1":
            create_account_full()
        elif choice == "2":
            generate_token_only()
        elif choice == "3":
            test_login_menu()
        elif choice == "4":
            recovery_menu()
        elif choice == "5":
            setup_imap_config()
        elif choice == "6":
            test_imap_connection()
        elif choice == "7":
            list_inbox()
        elif choice == "8":
            generate_emails_menu()
        elif choice == "0":
            log_info("Exit")
            break
        else:
            log_error("Pilihan tidak valid")


if __name__ == "__main__":
    main()
