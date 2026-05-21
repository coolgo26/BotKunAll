"""
IMAP Webmail Checker — Multi Account
Cek email masuk via IMAP untuk beberapa domain/akun sekaligus.
"""

import imaplib
import email
import email.header
import email.utils
import hashlib
import html as html_mod
import json
import os
import re
import socket
import time
import urllib.request
import urllib.error
from urllib.parse import urlparse, parse_qs

import socks
from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__, static_folder="static")
app.secret_key = os.getenv("SECRET_KEY", "change-me-to-a-random-secret-string")
CORS(app)

ACCOUNTS_FILE = os.path.join(os.path.dirname(__file__), "accounts.json")
ADMIN_USER = os.getenv("ADMIN_USER", "admin")
ADMIN_PASS = os.getenv("ADMIN_PASS", "admin123")

# Set default socket timeout (30 seconds)
socket.setdefaulttimeout(30)

# Save original socket class for proper reset after proxy usage
_original_socket = socket.socket

# Proxy config (dari .env atau accounts.json per-akun)
PROXY_HOST = os.getenv("PROXY_HOST", "")
PROXY_PORT = int(os.getenv("PROXY_PORT", "0"))
PROXY_TYPE = os.getenv("PROXY_TYPE", "socks5")  # socks5, socks4, http
PROXY_USER = os.getenv("PROXY_USER", "")
PROXY_PASS = os.getenv("PROXY_PASS", "")


# ============================================================
# ACCOUNT MANAGEMENT
# ============================================================

def load_accounts():
    if not os.path.exists(ACCOUNTS_FILE):
        return []
    with open(ACCOUNTS_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def save_accounts(accounts):
    with open(ACCOUNTS_FILE, "w", encoding="utf-8") as f:
        json.dump(accounts, f, indent=2, ensure_ascii=False)


def get_account_by_id(account_id):
    for acc in load_accounts():
        if acc["id"] == account_id:
            return acc
    return None


# ============================================================
# IMAP HELPERS
# ============================================================

def connect_imap(account):
    """Connect ke IMAP server dengan proxy & timeout handling."""
    host = account["host"]
    port = account.get("port", 993)
    use_tls = account.get("tls", True)
    username = account["username"]
    password = account.get("password", "")

    if not password:
        raise Exception(f"Password kosong untuk {username}")

    # Proxy: per-akun override > global .env
    proxy_host = account.get("proxy_host", "") or PROXY_HOST
    proxy_port = int(account.get("proxy_port", 0) or PROXY_PORT)
    proxy_type_str = account.get("proxy_type", "") or PROXY_TYPE
    proxy_user = account.get("proxy_user", "") or PROXY_USER
    proxy_pass = account.get("proxy_pass", "") or PROXY_PASS

    use_proxy = bool(proxy_host and proxy_port)

    # Set/unset proxy for this connection
    if use_proxy:
        ptype = {
            "socks5": socks.SOCKS5,
            "socks4": socks.SOCKS4,
            "http": socks.HTTP,
        }.get(proxy_type_str.lower(), socks.SOCKS5)
        socks.set_default_proxy(ptype, proxy_host, proxy_port,
                                username=proxy_user or None,
                                password=proxy_pass or None)
        socket.socket = socks.socksocket
    else:
        # No proxy — ensure we use the original socket
        socks.set_default_proxy()
        socket.socket = _original_socket

    try:
        if use_tls:
            mail = imaplib.IMAP4_SSL(host, port, timeout=20)
        else:
            mail = imaplib.IMAP4(host, port, timeout=20)
    except socket.timeout:
        raise Exception(f"Timeout connecting to {host}:{port} — cek firewall/ISP atau gunakan proxy")
    except socks.ProxyConnectionError as e:
        raise Exception(f"Proxy connection error: {str(e)}")
    except socks.GeneralProxyError as e:
        raise Exception(f"Proxy error: {str(e)}")
    except socket.gaierror:
        raise Exception(f"DNS error: host '{host}' tidak ditemukan")
    except ConnectionRefusedError:
        raise Exception(f"Connection refused {host}:{port}")
    except OSError as e:
        raise Exception(f"Network error: {str(e)}")
    finally:
        # Always reset socket to original after connection attempt
        socks.set_default_proxy()
        socket.socket = _original_socket

    try:
        mail.login(username, password)
    except imaplib.IMAP4.error as e:
        raise Exception(f"Login gagal: {str(e)}")

    return mail


def decode_header_value(value):
    if not value:
        return ""
    try:
        decoded_parts = email.header.decode_header(value)
        result = []
        for part, charset in decoded_parts:
            if isinstance(part, bytes):
                result.append(part.decode(charset or "utf-8", errors="replace"))
            else:
                result.append(part)
        return " ".join(result)
    except Exception:
        return str(value)


def get_email_body(msg):
    body = ""
    is_html = False
    try:
        if msg.is_multipart():
            for part in msg.walk():
                ct = part.get_content_type()
                if ct == "text/html":
                    payload = part.get_payload(decode=True)
                    if payload:
                        body = payload.decode(part.get_content_charset() or "utf-8", errors="replace")
                        is_html = True
                        break
                elif ct == "text/plain" and not body:
                    payload = part.get_payload(decode=True)
                    if payload:
                        body = payload.decode(part.get_content_charset() or "utf-8", errors="replace")
                        is_html = False
        else:
            payload = msg.get_payload(decode=True)
            if payload:
                body = payload.decode(msg.get_content_charset() or "utf-8", errors="replace")
                is_html = msg.get_content_type() == "text/html"
    except Exception:
        body = "(Error reading email body)"

    # Kalau plain text, convert URLs jadi clickable links dan wrap dalam HTML
    if body and not is_html:
        body = html_mod.escape(body)
        # Convert URLs ke <a> tags
        body = re.sub(
            r'(https?://[^\s<>&]+)',
            r'<a href="\1" target="_blank" style="color:#1565c0;word-break:break-all;">\1</a>',
            body
        )
        # Convert newlines ke <br>
        body = body.replace("\n", "<br>\n")
        body = f"<div style='white-space:pre-wrap;'>{body}</div>"

    return body


def parse_date(date_str):
    if not date_str:
        return ""
    try:
        parsed = email.utils.parsedate_to_datetime(date_str)
        return parsed.strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return date_str


# ============================================================
# ROUTES — STATIC
# ============================================================

@app.route("/")
def index():
    return send_from_directory("static", "index.html")


# ============================================================
# ROUTES — AUTH
# ============================================================

# Simple token store (in-memory, resets on restart)
active_tokens = {}

def generate_token(username):
    raw = f"{username}:{time.time()}:{os.urandom(16).hex()}"
    token = hashlib.sha256(raw.encode()).hexdigest()
    active_tokens[token] = {"user": username, "created": time.time()}
    return token

def verify_token():
    """Check auth token from header or cookie."""
    token = request.headers.get("X-Auth-Token", "")
    if not token:
        token = request.cookies.get("auth_token", "")
    if not token or token not in active_tokens:
        return False
    # Token expires after 24 hours
    if time.time() - active_tokens[token]["created"] > 86400:
        del active_tokens[token]
        return False
    return True

@app.route("/api/login", methods=["POST"])
def login():
    data = request.json
    if not data:
        return jsonify({"success": False, "error": "No data"}), 400
    username = data.get("username", "")
    password = data.get("password", "")
    if username == ADMIN_USER and password == ADMIN_PASS:
        token = generate_token(username)
        resp = jsonify({"success": True, "token": token})
        resp.set_cookie("auth_token", token, max_age=86400, httponly=True)
        return resp
    return jsonify({"success": False, "error": "Username atau password salah"}), 401

@app.route("/api/logout", methods=["POST"])
def logout():
    token = request.headers.get("X-Auth-Token", "") or request.cookies.get("auth_token", "")
    if token in active_tokens:
        del active_tokens[token]
    resp = jsonify({"success": True})
    resp.delete_cookie("auth_token")
    return resp

@app.route("/api/check-auth")
def check_auth():
    if verify_token():
        return jsonify({"authenticated": True})
    return jsonify({"authenticated": False}), 401


# ============================================================
# ROUTES — ACCOUNTS
# ============================================================

@app.route("/api/accounts", methods=["GET"])
def list_accounts():
    accounts = load_accounts()
    safe = [{
        "id": a["id"],
        "name": a.get("name", a["id"]),
        "host": a["host"],
        "port": a.get("port", 993),
        "username": a["username"],
        "domain": a.get("domain", ""),
        "tls": a.get("tls", True),
        "has_password": bool(a.get("password")),
    } for a in accounts]
    return jsonify({"accounts": safe})


@app.route("/api/accounts", methods=["POST"])
def add_account():
    if not verify_token():
        return jsonify({"error": "Unauthorized — login dulu"}), 401
    data = request.json
    if not data:
        return jsonify({"error": "No data"}), 400

    for field in ["id", "host", "username", "password"]:
        if not data.get(field):
            return jsonify({"error": f"Field '{field}' wajib diisi"}), 400

    accounts = load_accounts()
    for acc in accounts:
        if acc["id"] == data["id"]:
            return jsonify({"error": f"ID '{data['id']}' sudah ada"}), 400

    new_acc = {
        "id": data["id"].strip(),
        "name": data.get("name", data["id"]).strip(),
        "host": data["host"].strip(),
        "port": int(data.get("port", 993)),
        "tls": data.get("tls", True),
        "username": data["username"].strip(),
        "password": data["password"],
        "domain": data.get("domain", "").strip(),
    }

    # Test connection
    try:
        mail = connect_imap(new_acc)
        mail.select("INBOX", readonly=True)
        mail.logout()
    except Exception as e:
        return jsonify({"error": str(e)}), 400

    accounts.append(new_acc)
    save_accounts(accounts)
    return jsonify({"message": "✅ Account added", "id": new_acc["id"]})


@app.route("/api/accounts/<account_id>", methods=["PUT"])
def update_account(account_id):
    """Update akun (password, host, dll)."""
    if not verify_token():
        return jsonify({"error": "Unauthorized"}), 401
    data = request.json
    if not data:
        return jsonify({"error": "No data"}), 400

    accounts = load_accounts()
    found = False
    for acc in accounts:
        if acc["id"] == account_id:
            if data.get("host"): acc["host"] = data["host"].strip()
            if data.get("port"): acc["port"] = int(data["port"])
            if data.get("username"): acc["username"] = data["username"].strip()
            if data.get("password"): acc["password"] = data["password"]
            if data.get("name"): acc["name"] = data["name"].strip()
            if data.get("domain"): acc["domain"] = data["domain"].strip()
            if "tls" in data: acc["tls"] = data["tls"]
            found = True
            break

    if not found:
        return jsonify({"error": "Account not found"}), 404

    save_accounts(accounts)
    return jsonify({"message": "Updated"})


@app.route("/api/accounts/<account_id>", methods=["DELETE"])
def delete_account(account_id):
    if not verify_token():
        return jsonify({"error": "Unauthorized"}), 401
    accounts = load_accounts()
    accounts = [a for a in accounts if a["id"] != account_id]
    save_accounts(accounts)
    return jsonify({"message": "Deleted"})


@app.route("/api/accounts/<account_id>/test", methods=["POST"])
def test_account(account_id):
    account = get_account_by_id(account_id)
    if not account:
        return jsonify({"error": "Account not found"}), 404
    try:
        mail = connect_imap(account)
        status, count = mail.select("INBOX", readonly=True)
        msg_count = int(count[0]) if status == "OK" else 0
        mail.logout()
        return jsonify({"status": "ok", "messages": msg_count})
    except Exception as e:
        return jsonify({"status": "error", "error": str(e)}), 500


# ============================================================
# ROUTES — EMAIL
# ============================================================

@app.route("/api/accounts/<account_id>/inbox")
def get_inbox(account_id):
    account = get_account_by_id(account_id)
    if not account:
        return jsonify({"error": "Account not found"}), 404

    mailbox = request.args.get("mailbox", "INBOX")
    limit = int(request.args.get("limit", "30"))
    search_to = request.args.get("to", "")
    search_from = request.args.get("from", "")
    search_subject = request.args.get("subject", "")

    try:
        mail = connect_imap(account)
        mail.select(mailbox, readonly=True)

        criteria = []
        if search_to:
            criteria.append(f'TO "{search_to}"')
        if search_from:
            criteria.append(f'FROM "{search_from}"')
        if search_subject:
            criteria.append(f'SUBJECT "{search_subject}"')

        search_str = "(" + " ".join(criteria) + ")" if criteria else "ALL"
        status, messages = mail.search(None, search_str)

        if status != "OK":
            mail.logout()
            return jsonify({"error": "Search failed"}), 500

        msg_ids = messages[0].split() if messages[0] else []
        msg_ids = msg_ids[-limit:]
        msg_ids.reverse()

        emails = []
        if msg_ids:
            # Batch fetch headers (satu command untuk semua, jauh lebih cepat)
            id_str = ",".join(m.decode() for m in msg_ids)
            status, all_data = mail.fetch(id_str.encode(), "(RFC822.HEADER)")
            if status == "OK":
                # Parse response: setiap email = tuple (header info, raw data)
                idx = 0
                for item in all_data:
                    if isinstance(item, tuple) and len(item) == 2:
                        try:
                            raw_header = item[1]
                            msg = email.message_from_bytes(raw_header)
                            emails.append({
                                "id": msg_ids[idx].decode() if idx < len(msg_ids) else str(idx),
                                "from": decode_header_value(msg.get("From", "")),
                                "to": decode_header_value(msg.get("To", "")),
                                "subject": decode_header_value(msg.get("Subject", "(no subject)")),
                                "date": parse_date(msg.get("Date", "")),
                            })
                            idx += 1
                        except Exception:
                            idx += 1
                            continue

        mail.logout()
        return jsonify({
            "emails": emails,
            "total": len(emails),
            "mailbox": mailbox,
            "account_id": account_id,
            "domain": account.get("domain", ""),
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/accounts/<account_id>/email/<msg_id>")
def get_email_detail(account_id, msg_id):
    account = get_account_by_id(account_id)
    if not account:
        return jsonify({"error": "Account not found"}), 404

    try:
        mail = connect_imap(account)
        mail.select("INBOX", readonly=True)

        status, msg_data = mail.fetch(msg_id.encode(), "(RFC822)")
        if status != "OK":
            mail.logout()
            return jsonify({"error": "Email not found"}), 404

        raw_email = msg_data[0][1]
        msg = email.message_from_bytes(raw_email)
        body = get_email_body(msg)
        links = re.findall(r'https?://[^\s<>"\']+', body)

        mail.logout()
        return jsonify({
            "id": msg_id,
            "from": decode_header_value(msg.get("From", "")),
            "to": decode_header_value(msg.get("To", "")),
            "subject": decode_header_value(msg.get("Subject", "")),
            "date": parse_date(msg.get("Date", "")),
            "body": body,
            "links": links[:20],
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/accounts/<account_id>/verification")
def search_verification(account_id):
    account = get_account_by_id(account_id)
    if not account:
        return jsonify({"error": "Account not found"}), 404

    to_email = request.args.get("to", "")
    limit = int(request.args.get("limit", "10"))

    try:
        mail = connect_imap(account)
        mail.select("INBOX", readonly=True)

        criteria = []
        if to_email:
            criteria.append(f'TO "{to_email}"')
        criteria.append('OR SUBJECT "verify" SUBJECT "confirm"')

        search_str = "(" + " ".join(criteria) + ")"
        status, messages = mail.search(None, search_str)

        if status != "OK":
            mail.logout()
            return jsonify({"error": "Search failed"}), 500

        msg_ids = messages[0].split() if messages[0] else []
        msg_ids = msg_ids[-limit:]
        msg_ids.reverse()

        results = []
        for msg_id in msg_ids:
            try:
                st, msg_data = mail.fetch(msg_id, "(RFC822)")
                if st != "OK":
                    continue
                raw_email = msg_data[0][1]
                msg = email.message_from_bytes(raw_email)
                body = get_email_body(msg)
                links = re.findall(r'https?://[^\s<>"\']+', body)
                verify_links = [l for l in links if any(
                    kw in l.lower() for kw in ["verify", "confirm", "activate", "validate", "token"]
                )]
                results.append({
                    "id": msg_id.decode(),
                    "from": decode_header_value(msg.get("From", "")),
                    "to": decode_header_value(msg.get("To", "")),
                    "subject": decode_header_value(msg.get("Subject", "")),
                    "date": parse_date(msg.get("Date", "")),
                    "verify_links": verify_links[:5],
                    "all_links": links[:10],
                })
            except Exception:
                continue

        mail.logout()
        return jsonify({"results": results, "total": len(results)})

    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/search/all")
def search_all_accounts():
    to_email = request.args.get("to", "")
    search_from = request.args.get("from", "")
    subject = request.args.get("subject", "")
    limit = int(request.args.get("limit", "10"))

    if not to_email and not search_from and not subject:
        return jsonify({"error": "Isi minimal satu filter (to/from/subject)"}), 400

    accounts = load_accounts()
    all_results = []

    for account in accounts:
        try:
            mail = connect_imap(account)
            mail.select("INBOX", readonly=True)

            criteria = []
            if to_email:
                criteria.append(f'TO "{to_email}"')
            if search_from:
                criteria.append(f'FROM "{search_from}"')
            if subject:
                criteria.append(f'SUBJECT "{subject}"')

            search_str = "(" + " ".join(criteria) + ")"
            status, messages = mail.search(None, search_str)

            if status == "OK" and messages[0]:
                msg_ids = messages[0].split()[-limit:]
                msg_ids.reverse()
                for msg_id in msg_ids:
                    try:
                        st, msg_data = mail.fetch(msg_id, "(RFC822.HEADER)")
                        if st != "OK":
                            continue
                        msg = email.message_from_bytes(msg_data[0][1])
                        all_results.append({
                            "account_id": account["id"],
                            "account_name": account.get("name", account["id"]),
                            "id": msg_id.decode(),
                            "from": decode_header_value(msg.get("From", "")),
                            "to": decode_header_value(msg.get("To", "")),
                            "subject": decode_header_value(msg.get("Subject", "")),
                            "date": parse_date(msg.get("Date", "")),
                        })
                    except Exception:
                        continue
            mail.logout()
        except Exception:
            continue

    all_results.sort(key=lambda x: x.get("date", ""), reverse=True)
    return jsonify({"results": all_results, "total": len(all_results)})


# ============================================================
# ROUTES — ACCOUNT GENERATOR
# ============================================================

@app.route("/api/generate-account", methods=["POST"])
def generate_account():
    """Generate satu akun Pixel Worlds."""
    from account_gen import create_account, generate_password, random_string, rawa_check

    data = request.json or {}
    email_domain = data.get("domain", "")
    password = data.get("password", "")
    prefix = data.get("prefix", "pw")
    do_tutorial = data.get("tutorial", False)

    if not email_domain:
        return jsonify({"success": False, "error": "Domain email required"}), 400

    email_addr = f"{prefix}{random_string(8)}@{email_domain}"
    if not password:
        password = generate_password()

    result = create_account(email_addr, password, do_tutorial=do_tutorial)
    return jsonify(result)


@app.route("/api/generate-batch", methods=["POST"])
def generate_batch():
    """Generate satu akun (dipanggil per-email dari frontend)."""
    from account_gen import create_account, generate_password

    data = request.json or {}
    email_addr = data.get("email", "")
    password = data.get("password", "")
    do_tutorial = data.get("tutorial", False)

    if not email_addr:
        return jsonify({"success": False, "error": "Email required"}), 400
    if not password:
        password = generate_password()

    result = create_account(email_addr, password, do_tutorial=do_tutorial)
    return jsonify(result)


@app.route("/api/rawa-status", methods=["GET"])
def rawa_status():
    """Check if Rawa Rontek is running."""
    from account_gen import rawa_check
    return jsonify({"running": rawa_check()})


@app.route("/api/set-proxies", methods=["POST"])
def set_proxies():
    """Set proxy list for account generator."""
    from account_gen import set_proxy_list
    data = request.json or {}
    proxies = data.get("proxies", [])
    if isinstance(proxies, str):
        proxies = [p.strip() for p in proxies.split("\n") if p.strip()]
    set_proxy_list(proxies)
    return jsonify({"success": True, "count": len(proxies)})


@app.route("/api/repair-account", methods=["POST"])
def repair_account():
    """
    Repair akun yang stuck 'User not found' di SocialFirst.
    Login via PlayFab email/password → exchange ke SocialFirst → akun terdaftar.
    """
    from account_gen import post_playfab, exchange_socialfirst, TITLE_ID

    data = request.json or {}
    email_addr = data.get("email", "").strip()
    password = data.get("password", "").strip()

    if not email_addr or not password:
        return jsonify({"success": False, "error": "Email dan password required"})

    # Step 1: Login via email/password
    resp = post_playfab("/Client/LoginWithEmailAddress", {
        "TitleId": TITLE_ID,
        "Email": email_addr,
        "Password": password,
    })

    if not resp:
        return jsonify({"success": False, "error": "Network error (PlayFab)"})

    if resp.status_code != 200:
        try:
            error = resp.json().get("errorMessage", f"HTTP {resp.status_code}")
        except:
            error = f"HTTP {resp.status_code}"
        return jsonify({"success": False, "error": error})

    pf_data = resp.json().get("data", {})
    session_ticket = pf_data.get("SessionTicket")
    playfab_id = pf_data.get("PlayFabId")

    if not session_ticket:
        return jsonify({"success": False, "error": "No session ticket"})

    # Step 2: Exchange ke SocialFirst
    sf = exchange_socialfirst(session_ticket)
    if sf.get("success") and sf.get("jwt"):
        return jsonify({
            "success": True,
            "playfab_id": playfab_id,
            "jwt": sf["jwt"][:30] + "...",
            "message": "Account repaired! SocialFirst sekarang kenal akun ini.",
        })
    else:
        return jsonify({
            "success": False,
            "error": f"SocialFirst failed: {sf.get('error', '?')}",
            "playfab_id": playfab_id,
        })


@app.route("/api/visit-link", methods=["POST"])
def visit_link():
    """Visit a URL (for email verification clicks)."""
    data = request.json or {}
    url = data.get("url", "")
    if not url:
        return jsonify({"success": False, "error": "URL required"}), 400

    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        })
        with urllib.request.urlopen(req, timeout=15) as resp:
            return jsonify({"success": True, "status": resp.status})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


# ============================================================
# ROUTES — RESET PASSWORD (Pixel Worlds)
# ============================================================

@app.route("/api/reset-password", methods=["POST"])
def reset_password():
    """Request reset password via PlayFab API (Pixel Worlds)."""
    data = request.json
    if not data or not data.get("email"):
        return jsonify({"success": False, "error": "Email required"}), 400

    email_addr = data["email"].strip()

    # Pixel Worlds uses PlayFab — Title ID from account_gen
    from account_gen import TITLE_ID
    api_url = f"https://{TITLE_ID}.playfabapi.com/Client/SendAccountRecoveryEmail"

    payload = json.dumps({
        "TitleId": TITLE_ID,
        "Email": email_addr,
    }).encode("utf-8")

    try:
        req = urllib.request.Request(
            api_url,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "User-Agent": "UnityPlayer/6000.3.11f1",
            },
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            status_code = resp.status
            body = resp.read().decode("utf-8", errors="replace")
            resp_data = json.loads(body) if body else {}

        if status_code == 200:
            return jsonify({"success": True, "email": email_addr, "response": resp_data})
        else:
            error_msg = resp_data.get("errorMessage", f"HTTP {status_code}")
            return jsonify({"success": False, "error": error_msg, "email": email_addr})

    except urllib.error.HTTPError as e:
        try:
            err_body = e.read().decode("utf-8", errors="replace")
            err_data = json.loads(err_body)
            error_msg = err_data.get("errorMessage", f"HTTP {e.code}")
        except Exception:
            error_msg = f"HTTP {e.code}: {e.reason}"
        return jsonify({"success": False, "error": error_msg, "email": email_addr})
    except urllib.error.URLError as e:
        return jsonify({"success": False, "error": f"Connection error: {str(e.reason)}", "email": email_addr})
    except Exception as e:
        return jsonify({"success": False, "error": str(e), "email": email_addr})


@app.route("/api/reset-set-password", methods=["POST"])
def reset_set_password():
    """Set password baru via headless browser (Selenium)."""
    data = request.json
    if not data or not data.get("link") or not data.get("password"):
        return jsonify({"success": False, "error": "Link and password required"}), 400

    link = data["link"].strip()
    new_password = data["password"].strip()

    # Validate link has token
    parsed = urlparse(link)
    params = parse_qs(parsed.query)
    if not params.get("token") and not params.get("Token"):
        return jsonify({"success": False, "error": "No token in link"}), 400

    try:
        from selenium import webdriver
        from selenium.webdriver.common.by import By
        from selenium.webdriver.support.ui import WebDriverWait
        from selenium.webdriver.support import expected_conditions as EC
        from selenium.webdriver.chrome.options import Options
        from selenium.webdriver.chrome.service import Service

        options = Options()
        options.add_argument("--headless")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("--disable-gpu")
        options.add_argument("--window-size=1280,720")

        driver = webdriver.Chrome(options=options)
        driver.set_page_load_timeout(20)

        try:
            # Buka link reset
            driver.get(link)

            # Tunggu form muncul (input password)
            wait = WebDriverWait(driver, 10)
            password_input = wait.until(
                EC.presence_of_element_located((By.CSS_SELECTOR, "input[type='password'], input[name='password'], input[placeholder*='assword']"))
            )

            # Isi password
            password_input.clear()
            password_input.send_keys(new_password)

            # Cari confirm password field (jika ada)
            confirm_inputs = driver.find_elements(By.CSS_SELECTOR, "input[type='password']")
            if len(confirm_inputs) > 1:
                confirm_inputs[1].clear()
                confirm_inputs[1].send_keys(new_password)

            # Klik submit button
            submit_btn = driver.find_element(By.CSS_SELECTOR, "button[type='submit'], input[type='submit'], button")
            submit_btn.click()

            # Tunggu response (success message atau redirect)
            time.sleep(3)

            # Cek apakah berhasil
            page_text = driver.page_source.lower()
            if "success" in page_text or "changed" in page_text or "updated" in page_text or "reset" in page_text:
                return jsonify({"success": True, "method": "selenium"})
            elif "invalid" in page_text or "expired" in page_text or "error" in page_text:
                return jsonify({"success": False, "error": "Token expired atau invalid (halaman menunjukkan error)"})
            else:
                # Assume success jika tidak ada error visible
                return jsonify({"success": True, "method": "selenium-assumed"})

        finally:
            driver.quit()

    except ImportError:
        return jsonify({"success": False, "error": "Selenium not installed. Run: pip install selenium"})
    except Exception as e:
        error_msg = str(e)
        if "chromedriver" in error_msg.lower() or "chrome" in error_msg.lower():
            return jsonify({"success": False, "error": f"ChromeDriver error: {error_msg}. Install Chrome & chromedriver."})
        return jsonify({"success": False, "error": error_msg})


if __name__ == "__main__":
    accounts = load_accounts()
    print("\n📧 IMAP Webmail Checker — Multi Account")
    print(f"   Accounts: {len(accounts)}")
    for acc in accounts:
        pw_status = "✅" if acc.get("password") else "❌ NO PASSWORD"
        print(f"   • {acc.get('name', acc['id'])} ({acc['username']}) {pw_status}")
    print(f"\n   🌐 http://localhost:5000\n")
    app.run(host="0.0.0.0", port=5000, debug=True)
