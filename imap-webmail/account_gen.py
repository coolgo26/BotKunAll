"""
Pixel Worlds Account Generator — Web API module.
Full flow: PlayFab register → SocialFirst exchange → Tutorial → IMAP verify
"""

import hashlib
import random
import string
import time
import threading
import uuid
import requests

# PlayFab config
TITLE_ID = "11EF5C"
BASE_URL = f"https://{TITLE_ID}.playfabapi.com"
REQUEST_TIMEOUT = 30

# SocialFirst config (from Rawa Rontek constants)
SOCIALFIRST_EXCHANGE_URL = "https://pw-auth.pw.sclfrst.com/v1/auth/exchangeToken"
SOCIALFIRST_API_KEY = "QwvzCrL2CexvXs2798fetBjty"
UNITY_VERSION = "6000.3.11f1"

# Rawa Rontek API (running di port 3000)
RAWA_RONTEK_URL = "http://localhost:3000"

DEFAULT_HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": "UnityPlayer/2020.3.40f1 (UnityWebRequest/1.0, libcurl/7.84.0-DEV)",
    "X-PlayFabSDK": "UnitySDK-2.140.220117",
    "Accept": "application/json",
}

# Proxy rotation (thread-safe)
_proxy_lock = threading.Lock()
_proxy_list = []
_proxy_index = 0


def set_proxy_list(proxies):
    """Set proxy list. Format: ['socks5://user:pass@host:port', 'http://host:port', ...]"""
    global _proxy_list, _proxy_index
    with _proxy_lock:
        _proxy_list = [p.strip() for p in proxies if p.strip()]
        _proxy_index = 0


def get_next_proxy():
    """Get next proxy from rotation list (thread-safe). Returns dict for requests or None."""
    global _proxy_index
    with _proxy_lock:
        if not _proxy_list:
            return None
        proxy = _proxy_list[_proxy_index % len(_proxy_list)]
        _proxy_index += 1
    return {"http": proxy, "https": proxy}


def random_string(length=10):
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=length))


def generate_device_id():
    return hashlib.sha256(str(uuid.uuid4()).encode()).hexdigest()[:40]


def generate_password():
    return f"Pw{random_string(6)}{random.randint(10, 99)}!"


# ============================================================
# PLAYFAB API
# ============================================================

def post_playfab(endpoint, payload, session_ticket=None):
    """Make a POST request to PlayFab API with proxy rotation and retry."""
    headers = dict(DEFAULT_HEADERS)
    if session_ticket:
        headers["X-Authorization"] = session_ticket
    proxies = get_next_proxy()

    for attempt in range(2):
        try:
            resp = requests.post(
                f"{BASE_URL}{endpoint}",
                json=payload,
                headers=headers,
                timeout=REQUEST_TIMEOUT,
                proxies=proxies,
            )
            return resp
        except requests.exceptions.Timeout:
            print(f"[gen] TIMEOUT {endpoint} (attempt {attempt + 1}/2)")
        except requests.exceptions.ConnectionError as e:
            print(f"[gen] CONN {endpoint}: {e} (attempt {attempt + 1}/2)")
        except Exception as e:
            print(f"[gen] ERR {endpoint}: {e}")
            return None
        if attempt < 1:
            time.sleep(2)
            proxies = get_next_proxy()  # Try next proxy on retry
    return None


# ============================================================
# SOCIALFIRST
# ============================================================

def exchange_socialfirst(session_ticket):
    """Exchange PlayFab session ticket → SocialFirst JWT (untuk akses game server)."""
    proxies = get_next_proxy()
    try:
        r = requests.post(
            SOCIALFIRST_EXCHANGE_URL,
            json={"playfabToken": session_ticket},
            headers={
                "Content-Type": "application/json",
                "X-Sf-Client-Api-Key": SOCIALFIRST_API_KEY,
                "X-Unity-Version": UNITY_VERSION,
            },
            timeout=20,
            proxies=proxies,
        )
        if r.status_code == 200:
            data = r.json()
            jwt_token = data.get("socialFirstToken") or data.get("token")
            if jwt_token:
                return {
                    "success": True,
                    "jwt": jwt_token,
                    "data": data,
                }
            return {"success": False, "error": f"No token in response. Keys: {list(data.keys())}"}
        return {"success": False, "error": f"HTTP {r.status_code}: {r.text[:200]}"}
    except requests.exceptions.Timeout:
        return {"success": False, "error": "SocialFirst timeout (20s)"}
    except requests.exceptions.ConnectionError as e:
        return {"success": False, "error": f"Connection error: {str(e)[:100]}"}
    except Exception as e:
        return {"success": False, "error": str(e)}


# ============================================================
# RAWA RONTEK INTEGRATION
# ============================================================

def rawa_check():
    try:
        r = requests.get(f"{RAWA_RONTEK_URL}/api/sessions", timeout=5)
        return r.status_code == 200
    except:
        return False


def rawa_create_session(auth_data):
    """auth_data: {kind:'android_device'} or {kind:'email_password',email,password} or {kind:'jwt',jwt,device_id}"""
    try:
        r = requests.post(f"{RAWA_RONTEK_URL}/api/sessions/connect", json={"auth": auth_data}, timeout=30)
        if r.status_code == 200:
            data = r.json()
            sid = data.get("id") or data.get("session_id") or data.get("data", {}).get("id", "")
            return {"success": True, "session_id": sid, "data": data}
        return {"success": False, "error": f"HTTP {r.status_code}: {r.text[:200]}"}
    except requests.exceptions.ConnectionError:
        return {"success": False, "error": "Rawa Rontek not running (localhost:3000)"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def rawa_tutorial(session_id):
    try:
        r = requests.post(f"{RAWA_RONTEK_URL}/api/sessions/{session_id}/tutorial/automate", timeout=10)
        return {"success": r.status_code == 200, "error": r.text[:200] if r.status_code != 200 else None}
    except Exception as e:
        return {"success": False, "error": str(e)}


def rawa_session_status(session_id):
    try:
        r = requests.get(f"{RAWA_RONTEK_URL}/api/sessions/{session_id}", timeout=10)
        if r.status_code == 200:
            d = r.json()
            return (d.get("status") or d.get("state") or "").lower()
    except:
        pass
    return ""


def rawa_wait_status(session_id, target_statuses, max_wait=120):
    """Wait until session reaches one of target_statuses."""
    deadline = time.time() + max_wait
    last = ""
    while time.time() < deadline:
        last = rawa_session_status(session_id)
        if last in [s.lower() for s in target_statuses]:
            return {"success": True, "status": last}
        time.sleep(3)
    return {"success": False, "error": f"timeout (last: {last})"}


def rawa_disconnect(session_id):
    try:
        requests.post(f"{RAWA_RONTEK_URL}/api/sessions/{session_id}/disconnect", timeout=5)
    except:
        pass


# ============================================================
# MAIN: CREATE ACCOUNT
# ============================================================

def create_account(email_addr, password=None, username=None, do_tutorial=True):
    """
    Full account creation flow:
      1. PlayFab LoginWithAndroidDeviceID (CreateAccount)
      2. SocialFirst exchangeToken → JWT
      3. AddUsernamePassword (register email/password)
      4. Rawa Rontek: create session pakai JWT → trigger tutorial → wait done
      5. Test login via PlayFab
    """
    if not password:
        password = generate_password()
    if not username:
        username = email_addr.split("@")[0][:18]

    result = {"email": email_addr, "password": password, "username": username}
    logs = []

    # ───── STEP 1: PlayFab login (create account via Android Device) ─────
    device_id = generate_device_id()
    result["device_id"] = device_id
    logs.append(f"Device: {device_id[:12]}...")

    resp = post_playfab("/Client/LoginWithAndroidDeviceID", {
        "AndroidDeviceId": device_id,
        "CreateAccount": True,
        "TitleId": TITLE_ID,
    })
    if not resp or resp.status_code != 200:
        error = "PlayFab login failed"
        if resp:
            try: error = resp.json().get("errorMessage", f"HTTP {resp.status_code}")
            except: error = f"HTTP {resp.status_code}"
        else:
            error = "Network error"
        logs.append(f"❌ {error}")
        return {"success": False, "error": error, "logs": logs, **result}

    pf_data = resp.json().get("data", {})
    session_ticket = pf_data.get("SessionTicket")
    playfab_id = pf_data.get("PlayFabId")
    result["playfab_id"] = playfab_id
    logs.append(f"✓ PlayFab auth: {playfab_id}")

    time.sleep(0.5)

    # ───── STEP 2: SocialFirst exchange → JWT (WAJIB untuk game server) ─────
    sf = exchange_socialfirst(session_ticket)
    jwt = None
    if sf.get("success") and sf.get("jwt"):
        jwt = sf["jwt"]
        result["jwt"] = jwt[:30] + "..."
        logs.append(f"✓ SocialFirst JWT: {jwt[:20]}...")
    else:
        error = sf.get('error', 'failed')
        logs.append(f"❌ SocialFirst: {error}")
        logs.append("  → Akun TIDAK bisa login game tanpa SocialFirst!")
        logs.append("  → Pastikan IP tidak di-ban oleh SocialFirst")
        return {"success": False, "error": f"SocialFirst failed: {error}", "logs": logs, **result}

    time.sleep(0.3)

    # ───── STEP 3: Register username + email + password ─────
    reg_resp = None
    for attempt in range(3):
        reg_resp = post_playfab("/Client/AddUsernamePassword", {
            "Username": username,
            "Password": password,
            "Email": email_addr,
        }, session_ticket)
        if reg_resp:
            break
        logs.append(f"  Register retry {attempt+1}...")
        time.sleep(2)

    if not reg_resp:
        logs.append("❌ Register network error")
        return {"success": False, "error": "Register failed (network)", "logs": logs, **result}

    if reg_resp.status_code != 200:
        try:
            err = reg_resp.json()
            error_msg = err.get("errorMessage", f"HTTP {reg_resp.status_code}")
            # Retry with new username if taken
            if "NameNotAvailable" in str(err):
                got_it = False
                for _ in range(3):
                    username = "PW" + random_string(8)
                    time.sleep(0.5)
                    reg_resp = post_playfab("/Client/AddUsernamePassword", {
                        "Username": username, "Password": password, "Email": email_addr,
                    }, session_ticket)
                    if reg_resp and reg_resp.status_code == 200:
                        result["username"] = username
                        got_it = True
                        break
                if not got_it:
                    logs.append(f"❌ {error_msg}")
                    return {"success": False, "error": error_msg, "logs": logs, **result}
            else:
                logs.append(f"❌ {error_msg}")
                return {"success": False, "error": error_msg, "logs": logs, **result}
        except Exception:
            logs.append(f"❌ HTTP {reg_resp.status_code}")
            return {"success": False, "error": f"HTTP {reg_resp.status_code}", "logs": logs, **result}

    logs.append(f"✓ Register: {username}")
    result["username"] = username

    # ───── STEP 4: Tutorial via game server (pakai JWT) ─────
    result["tutorial_done"] = False
    if do_tutorial:
        if not jwt:
            logs.append("⚠ Tutorial skipped: no JWT (SocialFirst gagal)")
        else:
            logs.append("→ Connecting to game server for tutorial...")
            try:
                from game_client import GameClient
            except ImportError as e:
                logs.append(f"⚠ Tutorial skipped: missing dependency ({e})")
                logs.append("  → Install: pip install pymongo")
                do_tutorial = False

            if do_tutorial:
                try:
                    client = GameClient(jwt, device_id, logger=lambda m: logs.append(f"  {m}"))

                    if client.connect():
                        # Wait for menu state
                        if client.wait_state("menu", timeout=15):
                            logs.append("  ✓ Connected to game server")
                            # Run tutorial
                            success = client.run_tutorial()
                            if success:
                                logs.append("✓ Tutorial DONE")
                                result["tutorial_done"] = True
                            else:
                                logs.append("⚠ Tutorial may have failed")
                        else:
                            logs.append(f"⚠ Could not reach menu state (state: {client.state})")
                        client.disconnect()
                    else:
                        logs.append("⚠ Game server connection failed")
                except Exception as e:
                    logs.append(f"⚠ Tutorial error: {e}")

    # ───── STEP 5: Test login via email + password ─────
    time.sleep(1)
    test = post_playfab("/Client/LoginWithEmailAddress", {
        "TitleId": TITLE_ID, "Email": email_addr, "Password": password,
    })
    if test and test.status_code == 200:
        logs.append("✓ Login test OK")
        result["login_verified"] = True
    else:
        result["login_verified"] = False
        if test:
            try: logs.append(f"⚠ Login test: {test.json().get('errorMessage', '?')}")
            except: logs.append(f"⚠ Login test: HTTP {test.status_code}")
        else:
            logs.append("⚠ Login test: network")

    result["success"] = True
    result["logs"] = logs
    return result
