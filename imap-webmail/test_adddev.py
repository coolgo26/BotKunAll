#!/usr/bin/env python3
"""
Test: PlayFab LoginWithAndroidDeviceID → SocialFirst exchangeToken.
Verifies that a new device can register and get a JWT for game access.
"""

import sys
import requests

TITLE_ID = "11EF5C"
PLAYFAB_URL = f"https://{TITLE_ID}.playfabapi.com"
SOCIALFIRST_URL = "https://pw-auth.pw.sclfrst.com/v1/auth/exchangeToken"
SOCIALFIRST_API_KEY = "QwvzCrL2CexvXs2798fetBjty"
UNITY_VERSION = "6000.3.11f1"

TIMEOUT = 15


def main():
    device_id = "adddev_test_002"

    print(f"1. PlayFab LoginWithAndroidDeviceID (device: {device_id})...")
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
        print("   ERROR: PlayFab request timed out")
        sys.exit(1)
    except requests.exceptions.ConnectionError as e:
        print(f"   ERROR: Connection failed: {e}")
        sys.exit(1)

    print(f"   Status: {r.status_code}")
    if r.status_code != 200:
        print(f"   Error: {r.text[:200]}")
        sys.exit(1)

    d = r.json().get("data", {})
    ticket = d.get("SessionTicket")
    pfid = d.get("PlayFabId")
    newly_created = d.get("NewlyCreated", False)

    if not ticket or not pfid:
        print("   ERROR: Missing SessionTicket or PlayFabId in response")
        sys.exit(1)

    print(f"   PFID: {pfid}")
    print(f"   NewlyCreated: {newly_created}")

    print("\n2. SocialFirst exchangeToken...")
    try:
        r2 = requests.post(
            SOCIALFIRST_URL,
            json={"playfabToken": ticket},
            headers={
                "Content-Type": "application/json",
                "X-Sf-Client-Api-Key": SOCIALFIRST_API_KEY,
                "X-Unity-Version": UNITY_VERSION,
            },
            timeout=TIMEOUT,
        )
    except requests.exceptions.Timeout:
        print("   ERROR: SocialFirst request timed out")
        sys.exit(1)
    except requests.exceptions.ConnectionError as e:
        print(f"   ERROR: Connection failed: {e}")
        sys.exit(1)

    print(f"   Status: {r2.status_code}")

    if r2.status_code == 200:
        data = r2.json()
        jwt = data.get("socialFirstToken") or data.get("token", "")
        if jwt:
            print(f"\n   JWT: {jwt[:50]}...")
            print("\n   addDevice flow SUCCESS!")
        else:
            print(f"   WARNING: No token found. Keys: {list(data.keys())}")
            print(f"   Body: {r2.text[:300]}")
    else:
        print(f"   Body: {r2.text[:300]}")
        print("\n   SocialFirst FAILED")
        sys.exit(1)


if __name__ == "__main__":
    main()
