import 'dart:io';
import 'dart:convert';
import 'mesh_log_provider.dart';
import 'skin_manager.dart';
import 'settings_manager.dart';

class MeshBackgroundService {
  static final MeshBackgroundService _instance = MeshBackgroundService._internal();
  factory MeshBackgroundService() => _instance;
  MeshBackgroundService._internal();

  HttpServer? _server;
  final List<WebSocket> _connectedClients = [];

  Future<void> startServer({int port = 9090}) async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      MeshLogProvider().addLog("Mesh Web Server & WebSocket daemon started on port $port");

      _server!.listen((HttpRequest request) async {
        // Handle WebSocket Upgrade on '/ws' or root
        if(WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            WebSocket socket = await WebSocketTransformer.upgrade(request);
            _handleWebSocketClient(socket);
          } catch (e) {
            MeshLogProvider().addLog("WebSocket upgrade failed: $e");
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          }
          return;
        }

        // Standard HTTP API Routing
        final path = request.uri.path;
        final response = request.response;

        response.headers.contentType = ContentType.json;
        response.headers.add('Access-Control-Allow-Origin', '*');

        if (path == '/api/logs') {
          final logs = MeshLogProvider().logs;
          response.write(json.encode({'status': 'success', 'logs': logs}));
        } else if (path == '/api/skin') {
          if (request.method == 'POST') {
            try {
              final content = await utf8.decoder.bind(request).join();
              final data = json.decode(content);
              await SkinManager().updateSkinConfig(data);
              response.write(json.encode({'status': 'success', 'message': 'Skin updated successfully'}));
            } catch (e) {
              response.statusCode = HttpStatus.badRequest;
              response.write(json.encode({'status': 'error', 'message': e.toString()}));
            }
          } else {
            response.write(json.encode({'status': 'success', 'skin': SkinManager().currentSkin.toJson()}));
          }
        } else if (path == '/api/settings') {
          if (request.method == 'POST') {
            try {
              final content = await utf8.decoder.bind(request).join();
              final data = json.decode(content);
              await SettingsManager().updateSettings(data);
              response.write(json.encode({'status': 'success', 'message': 'Settings updated'}));
            } catch (e) {
              response.statusCode = HttpStatus.badRequest;
              response.write(json.encode({'status': 'error', 'message': e.toString()}));
            }
          } else {
            response.write(json.encode({'status': 'success', 'settings': SettingsManager().customSettings}));
          }
        } else {
          response.statusCode = HttpStatus.notFound;
          response.write(json.encode({'status': 'error', 'message': 'Endpoint not found'}));
        }

        await response.close();
      });
    } catch (e) {
      MeshLogProvider().addLog("Failed to start Mesh Background Server: $e");
    }
  }

  void _handleWebSocketClient(WebSocket socket) {
    MeshLogProvider().addLog("New WebSocket client connected.");
    _connectedClients.add(socket);

    // Send welcome payload with initialization telemetry
    socket.add(json.encode({
      'event': 'welcome',
      'message': 'Connected to Media Client TV Mesh WebSocket Daemon',
      'timestamp': DateTime.now().toIso8601String(),
    }));

    socket.listen(
      (data) {
        _onWebSocketMessage(socket, data);
      },
      onDone: () {
        MeshLogProvider().addLog("WebSocket client disconnected.");
        _connectedClients.remove(socket);
      },
      onError: (error) {
        MeshLogProvider().addLog("WebSocket error: $error");
        _connectedClients.remove(socket);
      },
      cancelOnError: true,
    );
  }

  void _onWebSocketMessage(WebSocket socket, dynamic data) {
    try {
      final parsed = json.decode(data.toString());
      final String action = parsed['action'] ?? '';

      MeshLogProvider().addLog("WebSocket command received: $action");

      if (action == 'ping') {
        socket.add(json.encode({'event': 'pong', 'time': DateTime.now().toIso8601String()}));
      } else if (action == 'get_logs') {
        socket.add(json.encode({
          'event': 'logs_snapshot',
          'logs': MeshLogProvider().logs,
        }));
      } else {
        socket.add(json.encode({
          'event': 'error',
          'message': 'Unknown action command: $action',
        }));
      }
    } catch (e) {
      MeshLogProvider().addLog("Failed to parse incoming WebSocket message: $e");
      socket.add(json.encode({
        'event': 'error',
        'message': 'Invalid JSON format payload',
      }));
    }
  }

  void broadcastEvent(String eventName, Map<String, dynamic> payload) {
    final message = json.encode({
      'event': eventName,
      'data': payload,
      'timestamp': DateTime.now().toIso8601String(),
    });

    for (var client in _connectedClients) {
      try {
        client.add(message);
      } catch (_) {
        // Drop faulty sockets safely during broadcast sweep
      }
    }
  }

  Future<void> stopServer() async {
    for (var client in _connectedClients) {
      await client.close();
    }
    _connectedClients.clear();
    await _server?.close(force: true);
    _server = null;
    MeshLogProvider().addLog("Mesh Background Server stopped.");
  }
}
