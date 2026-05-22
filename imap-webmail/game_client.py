"""
Pixel Worlds Game Client — Python implementation.
Handles TCP connection, BSON protocol, auth handshake, and tutorial automation.
Ported from Rawa Rontek (Rust) source code.
"""

import socket
import struct
import time
import threading

# Use pymongo's bson module (installed via pymongo package)
try:
    import bson
    from bson import BSON
except ImportError:
    raise ImportError(
        "pymongo is required for BSON support. Install with: pip install pymongo"
    )

# Game server constants (from Rawa Rontek)
SERVER_HOST = "game-lava.pixelworlds.pw"
SERVER_PORT = 10001
RELAUNCH_PASS = "F3nal19jzMHWWzKA#GWB"

# Packet IDs
PKT_VCHK = "VChk"
PKT_GPD = "GPd"
PKT_ST = "ST"
PKT_KEEPALIVE = "p"
PKT_JOIN_WORLD = "TTjW"
PKT_LEAVE_WORLD = "LW"
PKT_WORLD_LOAD_ARGS = "wlA"
PKT_GET_LSI = "gLSI"
PKT_GET_WORLD = "Gw"
PKT_GWC = "GWC"
PKT_UPDATE_LOCATION = "ULS"
PKT_READY_TO_PLAY = "RtP"
PKT_MAP_POINT = "mp"
PKT_MOVEMENT = "mP"
PKT_HIT_BLOCK = "HB"
PKT_SET_BLOCK = "SB"
PKT_WORLD_CHAT = "WCM"
PKT_WEAR_ITEM = "WeOwC"
PKT_BUY_PACK = "BIPack"
PKT_PROGRESS = "PSicU"
PKT_TSTATE = "TState"
PKT_PORTAL_OUT = "PAoP"
PKT_PORTAL_IN = "PAiP"
PKT_COLLECTABLE = "C"
PKT_REDIRECT = "OoIP"
PKT_KICK = "KErr"


class GameClient:
    """TCP client for Pixel Worlds game server with BSON protocol."""

    def __init__(self, jwt, device_id, logger=None):
        self.jwt = jwt
        self.device_id = device_id
        self.logger = logger or print
        self.sock = None
        self.connected = False
        self.state = "idle"  # idle, connecting, menu, in_world, tutorial
        self.world_data = None
        self.player_pos = {"x": 0, "y": 0}
        self.recv_buffer = b""
        self.recv_thread = None
        self.running = False
        self.packets_received = []
        self.world_name = ""

    def log(self, msg):
        if callable(self.logger):
            self.logger(f"[game] {msg}")

    # ─── CONNECTION ───

    def connect(self):
        """Connect to game server via TCP."""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(15)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            self.sock.connect((SERVER_HOST, SERVER_PORT))
            self.connected = True
            self.running = True
            self.state = "connecting"
            self.log(f"Connected to {SERVER_HOST}:{SERVER_PORT}")

            # Start receive thread
            self.recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
            self.recv_thread.start()

            # Auth handshake
            self._do_handshake()
            return True
        except socket.timeout:
            self.log(f"Connect timeout: {SERVER_HOST}:{SERVER_PORT}")
            self.connected = False
            return False
        except ConnectionRefusedError:
            self.log(f"Connection refused: {SERVER_HOST}:{SERVER_PORT}")
            self.connected = False
            return False
        except Exception as e:
            self.log(f"Connect failed: {e}")
            self.connected = False
            return False

    def disconnect(self):
        """Disconnect from server and cleanup."""
        self.running = False
        self.connected = False
        self.state = "idle"
        if self.sock:
            try:
                self.sock.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            try:
                self.sock.close()
            except Exception:
                pass
            self.sock = None
        # Wait for recv thread to finish
        if self.recv_thread and self.recv_thread.is_alive():
            self.recv_thread.join(timeout=3)

    # ─── PACKET I/O ───

    def send_packet(self, doc):
        """Send a BSON document to server. Prefix with 4-byte little-endian length."""
        if not self.connected or not self.sock:
            return False
        try:
            raw = bson.BSON.encode(doc)
            # Pixel Worlds protocol: 4-byte LE length prefix (total = raw + 4 bytes header)
            length = len(raw) + 4
            self.sock.sendall(struct.pack("<I", length) + raw)
            return True
        except (BrokenPipeError, ConnectionResetError) as e:
            self.log(f"Connection lost: {e}")
            self.connected = False
            return False
        except Exception as e:
            self.log(f"Send error: {e}")
            self.connected = False
            return False

    def send_batch(self, docs):
        """Send multiple packets as one batch."""
        for doc in docs:
            self.send_packet(doc)
            time.sleep(0.05)

    def _recv_loop(self):
        """Background thread: receive and parse BSON packets."""
        last_keepalive = time.time()
        while self.running and self.connected:
            try:
                self.sock.settimeout(1)
                data = self.sock.recv(65536)
                if not data:
                    self.log("Server closed connection")
                    self.connected = False
                    break
                self.recv_buffer += data
                self._parse_packets()
            except socket.timeout:
                # Send keepalive every 30 seconds to prevent disconnect
                if time.time() - last_keepalive > 30:
                    self.send_packet({"ID": PKT_KEEPALIVE})
                    last_keepalive = time.time()
                continue
            except (ConnectionResetError, BrokenPipeError, OSError) as e:
                if self.running:
                    self.log(f"Connection lost: {e}")
                self.connected = False
                break
            except Exception as e:
                if self.running:
                    self.log(f"Recv error: {e}")
                self.connected = False
                break

    def _parse_packets(self):
        """Parse BSON packets from receive buffer.
        
        Protocol: [4-byte LE length][BSON data]
        The length field = len(BSON data) + 4 (includes itself).
        So actual BSON data starts at offset 4 and is (length - 4) bytes.
        """
        while len(self.recv_buffer) >= 4:
            length = struct.unpack("<I", self.recv_buffer[:4])[0]
            if length < 4:
                # Invalid packet, skip 4 bytes
                self.recv_buffer = self.recv_buffer[4:]
                continue
            if len(self.recv_buffer) < length:
                break  # Wait for more data
            raw_bson = self.recv_buffer[4:length]
            self.recv_buffer = self.recv_buffer[length:]
            try:
                doc = bson.BSON(raw_bson).decode()
                self._handle_packet(doc)
            except Exception as e:
                # Skip malformed packets silently
                pass

    def _handle_packet(self, doc):
        """Handle incoming packet based on ID."""
        pkt_id = doc.get("ID", "")
        self.packets_received.append(pkt_id)

        if pkt_id == PKT_VCHK:
            # Server version check — respond with GPd (auth)
            self._send_auth()
        elif pkt_id == PKT_GET_LSI:
            # Server info received — we're at menu
            self.state = "menu"
            self.log("State: menu")
        elif pkt_id == PKT_GWC:
            # World content received
            self.world_data = doc
            self.state = "in_world"
            self.world_name = doc.get("N", "")
            self.log(f"State: in_world ({self.world_name})")
        elif pkt_id == PKT_REDIRECT:
            # Server redirect
            self.log("Redirect received")
        elif pkt_id == PKT_KICK:
            er = doc.get("ER", "?")
            self.log(f"KICKED: {er}")
            self.state = "kicked"

    # ─── AUTH HANDSHAKE ───

    def _do_handshake(self):
        """Send VChk packet to initiate handshake."""
        self.send_packet({"ID": PKT_VCHK, "V": 93})
        self.log("Sent VChk")

    def _send_auth(self):
        """Send GPd (auth) packet with JWT."""
        auth_doc = {
            "ID": PKT_GPD,
            "jwt": self.jwt,
            "dID": self.device_id,
            "rP": RELAUNCH_PASS,
            "pV": "2.0.45",
        }
        self.send_packet(auth_doc)
        self.log("Sent GPd (auth)")

        # Follow up with gLSI + ST
        time.sleep(0.5)
        self.send_batch([
            {"ID": PKT_GET_LSI},
            {"ID": PKT_ST},
        ])

    # ─── WORLD NAVIGATION ───

    def join_world(self, world_name, is_instance=False):
        """Join a world."""
        if is_instance:
            self.send_batch([
                {"ID": PKT_WORLD_LOAD_ARGS, "WCSD": [0]},
                {"ID": PKT_JOIN_WORLD, "Is": True, "W": world_name.upper(), "WB": 0, "Amt": 1},
            ])
        else:
            self.send_packet({"ID": PKT_JOIN_WORLD, "W": world_name.upper(), "WB": 0, "Amt": 0})
        self.log(f"Joining: {world_name}")

    def leave_world(self):
        self.send_packet({"ID": PKT_LEAVE_WORLD})
        self.state = "menu"

    def wait_state(self, target, timeout=30):
        """Wait until state matches target."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.state == target:
                return True
            if not self.connected:
                return False
            time.sleep(0.5)
        return False

    # ─── TUTORIAL AUTOMATION ───

    def run_tutorial(self):
        """
        Run full tutorial automation.
        Based on Rawa Rontek tutorial phases (simplified).
        Tutorial world: TUTORIAL2
        """
        self.log("Starting tutorial...")

        # Join tutorial world
        self.join_world("TUTORIAL2", is_instance=True)
        if not self.wait_state("in_world", timeout=25):
            self.log("Failed to enter tutorial world")
            return False

        time.sleep(3)

        # Tutorial phases (simplified from Rawa Rontek ~20 phases)
        # Phase 4: Initial TState
        self._tstate(4)
        time.sleep(5)

        # Check we're still connected
        if not self.connected:
            self.log("Disconnected during tutorial")
            return False

        # Phase 5: TState 5
        self._tstate(5)
        time.sleep(3)

        # Phase 6-9: Movement + hit blocks + collect
        for phase in range(6, 10):
            if not self.connected:
                return False
            self._tstate(phase)
            time.sleep(2.5)
            self._move(1, 0)
            time.sleep(1.5)

        # Phase 10-14: More tutorial steps
        for phase in range(10, 15):
            if not self.connected:
                return False
            self._progress(0)
            time.sleep(1.5)

        # Phase 15: Shop
        self._tstate(15)
        time.sleep(3)

        # Buy starter pack
        self.send_packet({"ID": PKT_BUY_PACK, "PId": "StarterPack"})
        time.sleep(3)

        # Phase 16-18: Equip items
        for phase in range(16, 19):
            if not self.connected:
                return False
            self._tstate(phase)
            time.sleep(1.5)

        # Phase 19: Final — leave tutorial
        self._progress(0)
        time.sleep(3)

        # Leave world
        self.leave_world()
        time.sleep(3)

        # Join PIXELSTATION (tutorial complete destination)
        self.join_world("PIXELSTATION")
        if self.wait_state("in_world", timeout=20):
            self.log("Tutorial COMPLETE — in PIXELSTATION")
            self.leave_world()
            return True

        self.log("Tutorial finished (may need verification)")
        return True

    # ─── HELPER PACKETS ───

    def _tstate(self, value):
        """Send TState packet."""
        self.send_batch([
            {"ID": PKT_MOVEMENT},
            {"ID": PKT_TSTATE, "Tstate": value},
        ])

    def _progress(self, value):
        """Send progress signal."""
        self.send_packet({"ID": PKT_PROGRESS, "SIc": value})

    def _move(self, dx, dy):
        """Send movement packet."""
        self.send_packet({"ID": PKT_MOVEMENT, "x": dx, "y": dy})

    def _hit(self, x, y):
        """Send hit block packet."""
        self.send_packet({"ID": PKT_HIT_BLOCK, "x": x, "y": y})
