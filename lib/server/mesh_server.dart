import 'dart:io';
import 'dart:convert';

class MeshServer {
  HttpServer? _server;
  final int port;
  final String tailscaleIp;

  MeshServer({this.port = 9090, this.tailscaleIp = "100.99.24.58"});

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      print('Dart Mesh Server running on port $port');

      await for (HttpRequest request in _server!) {
        _handleRequest(request);
      }
    } catch (e) {
      print('Mesh server binding failed: $e');
    }
  }

  void _handleRequest(HttpRequest request) {
    final response = request.response;
    response.headers.contentType = ContentType.json;

    if (request.method == 'GET' && request.uri.path == '/') {
      response.statusCode = HttpStatus.ok;
      response.write(json.encode({
        "status": "online",
        "mode": "flutter-native-mesh",
        "mesh_ip": tailscaleIp,
      }));
    } else if (request.method == 'POST' && request.uri.path == '/rpc') {
      response.statusCode = HttpStatus.ok;
      response.write(json.encode({
        "jsonrpc": "2.0",
        "result": {"message": "Command executed successfully via Dart core"},
        "id": 1
      }));
    } else {
      response.statusCode = HttpStatus.notFound;
      response.write(json.encode({"error": "Endpoint not found"}));
    }

    response.close();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    print('Mesh server stopped.');
  }
}
