import socket
import json
import secrets
import hashlib
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

# Generate a random temporary password on boot (e.g., 6 uppercase chars/numbers)
DYNAMIC_PASSWORD = secrets.token_hex(3).upper()
STORED_PASSWORD_HASH = hashlib.sha256(DYNAMIC_PASSWORD.encode('utf-8')).hexdigest()

valid_device_tokens = set()

def get_tailscale_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('100.100.100.100', 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

class SecureRPCHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/jsonrpc':
            self.send_response(404)
            self.end_headers()
            return

        client_ip = self.client_address[0]
        is_tailscale_client = client_ip.startswith("100.")

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        try:
            request = json.loads(body.decode('utf-8'))
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return

        method = request.get("method")
        params = request.get("params", {})
        req_id = request.get("id", 1)
        
        result = None
        error = None

        if method == "System.VerifyPassword":
            client_hash = params.get("password_hash")
            if client_hash == STORED_PASSWORD_HASH:
                device_token = secrets.token_hex(32)
                valid_device_tokens.add(device_token)
                result = {"device_token": device_token}
            else:
                error = {"code": -401, "message": "Incorrect password."}
        else:
            auth_token = self.headers.get("X-Device-Token") or params.get("device_token")
            
            if auth_token not in valid_device_tokens:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Unauthorized: Active session required."}).encode('utf-8'))
                return

            if method == "VideoLibrary.GetMovies":
                with open("addons/public_archive/catalog.json", "r") as f:
                    catalog = json.load(f)
                result = {"movies": catalog.get("items", [])}
                
            elif method == "Player.Open":
                item = params.get("item", {})
                print(f"[Tailscale RPC] Playing stream on TV: {params.get('options', {}).get('title')} -> {item.get('file')}")
                result = {"status": "OK"}
            else:
                error = {"code": -32601, "message": f"Method not found: {method}"}

        response = {"jsonrpc": "2.0", "id": req_id}
        if error:
            response["error"] = error
        else:
            response["result"] = result

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode('utf-8'))

def start_secure_server():
    tv_ip = get_tailscale_ip()
    port = 9090
    
    print(f"\n==========================================")
    print(f"  TV SECURE STARTUP PASSWORD: {DYNAMIC_PASSWORD}")
    print(f"==========================================\n")
    
    # Save the IP, port, and temporary password state so Flutter can read it
    os.makedirs("shared", exist_ok=True)
    with open("shared/pairing_state.json", "w") as f:
        json.dump({
            "ip": tv_ip, 
            "port": port,
            "temp_password": DYNAMIC_PASSWORD
        }, f)

    server = HTTPServer(('0.0.0.0', port), SecureRPCHandler)
    print(f"Server running on http://{tv_ip}:{port}...\n")
    server.serve_forever()

if __name__ == '__main__':
    start_secure_server()
