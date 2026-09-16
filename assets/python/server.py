import socket
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

def get_tailscale_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('100.100.100.100', 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = '100.99.24.58'  # Fallback to your explicit Tailscale IP
    finally:
        s.close()
    return ip

TV_IP = get_tailscale_ip()
PORT = 9090

class MeshRPCHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Friendly health check endpoint when opened directly in Chrome
        if self.path == '/' or self.path == '/status':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                "status": "online",
                "ip": TV_IP,
                "message": "Tailscale Media Client RPC Active"
            }).encode('utf-8'))
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        if self.path != '/jsonrpc':
            self.send_response(404)
            self.end_headers()
            return

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

        if method == "VideoLibrary.GetMovies":
            try:
                catalog_path = "addons/public_archive/catalog.json"
                if os.path.exists(catalog_path):
                    with open(catalog_path, "r") as f:
                        catalog = json.load(f)
                    result = {"movies": catalog.get("items", [])}
                else:
                    result = {"movies": []}
            except Exception as e:
                error = {"code": -32603, "message": str(e)}
                
        elif method == "Player.Open":
            item = params.get("item", {})
            print(f"[Tailscale Mesh RPC] Playing stream on TV: {params.get('options', {}).get('title')} -> {item.get('file')}")
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

def start_mesh_server():
    server = HTTPServer((TV_IP, PORT), MeshRPCHandler)
    print(f"\n[Tailscale Mesh RPC] Server listening on http://{TV_IP}:{PORT}\n")
    server.serve_forever()

if __name__ == '__main__':
    start_mesh_server()
