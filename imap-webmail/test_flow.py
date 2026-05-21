#!/usr/bin/env python3
"""
Test flow: PlayFab login → SocialFirst exchange.
Verifies the basic auth pipeline works end-to-end.
"""

import sys
import requests

TITLE_ID = "11EF5C"
PLAYFAB_URL = f"https://{TITLE_ID}.playfabapi.com"
SOCIALFIRST_URL = "https://pw-auth.pw.sclfrst.com/v1/auth/exchangeToken"
SOCIALFIRST_API_KEY = "QwvzCrL2CexvXs2798fetBjty"
UNITY_VERSION = "6000.3.11f1"

TIMEOUT = 15


def test_playfab_login(device_id="vpntest_final_001"):
    """Step 1: Login to PlayFab with Android Device ID."""
    print(f"Step 1: PlayFab login (device: {device_id})...")
    try:
        r = requests.post(
            f"{PLAYFAB_URL}/Client/LoginWithAndroidDeviceID",
            json={
                "AndroidDeviceId": device_id,
                "CreateAccount": True,
                "TitleId": TITLE_ID,
            },
            timeout=TIMEOUT,
        )
    except requests.exceptions.Timeout:
        print("  ERROR: Request timed out")
        return None, None
    except requests.exceptions.ConnectionError as e:
        print(f"  ERROR: Connection failed: {e}")
        return None, None

    print(f"  Status: {r.status_code}")
    if r.status_code != 200:
        print(f"  Error: {r.text[:200]}")
        return None, None

    data = r.json().get("data", {})
    ticket = data.get("SessionTicket")
    pfid = data.get("PlayFabId")
    print(f"  PFID: {pfid}")
    print(f"  Ticket: {ticket[:40]}..." if ticket else "  Ticket: None")
    return ticket, pfid


def test_socialfirst_exchange(session_ticket):
    """Step 2: Exchange PlayFab ticket for SocialFirst JWT."""
    print("\nStep 2: SocialFirst exchange...")
    if not session_ticket:
        print("  SKIP: No session ticket")
        return None

    try:
        r = requests.post(
            SOCIALFIRST_URL,
            json={"playfabToken": session_ticket},
            headers={
                "Content-Type": "application/json",
                "X-Sf-Client-Api-Key": SOCIALFIRST_API_KEY,
                "X-Unity-Version": UNITY_VERSION,
            },
            timeout=TIMEOUT,
        )
    except requests.exceptions.Timeout:
        print("  ERROR: Request timed out")
        return None
    except requests.exceptions.ConnectionError as e:
        print(f"  ERROR: Connection failed: {e}")
        return None

    print(f"  Status: {r.status_code}")
    if r.status_code == 200:
        data = r.json()
        jwt = data.get("socialFirstToken") or data.get("token")
        if jwt:
            print(f"  JWT: {jwt[:50]}...")
            print("\n  SUCCESS: Full auth pipeline works!")
            return jwt
        else:
            print(f"  WARNING: No token in response. Keys: {list(data.keys())}")
    else:
        print(f"  Body: {r.text[:300]}")
        print("\n  FAILED: SocialFirst exchange error")
    return None


def main():
    print("=" * 60)
    print("  TEST: PlayFab → SocialFirst Auth Flow")
    print("=" * 60)
    print()

    ticket, pfid = test_playfab_login()
    if not ticket:
        print("\nFAILED at Step 1")
        sys.exit(1)

    jwt = test_socialfirst_exchange(ticket)
    if not jwt:
        print("\nFAILED at Step 2")
        sys.exit(1)

    print("\n" + "=" * 60)
    print("  ALL TESTS PASSED")
    print("=" * 60)


if __name__ == "__main__":
    main()
