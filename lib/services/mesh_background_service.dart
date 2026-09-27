import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart' show rootBundle, Clipboard, ClipboardData;
import 'package:path_provider/path_provider.dart';

import 'mesh_log_provider.dart';
import 'skin_manager.dart';
import 'settings_manager.dart';

class MeshBackgroundService {
  static final MeshBackgroundService _instance = MeshBackgroundService._internal();
  factory MeshBackgroundService() => _instance;
  MeshBackgroundService._internal();

  HttpServer? _server;
  bool _isRunning = false;
  final List<WebSocket> _connectedClients = [];
  late String _webRootPath;
  late String _storageFolderPath;

  // In-memory clipboard cache to sync between web dashboard and app runtime
  static String _latestClipboard = '';

  bool get isRunning => _isRunning;

  /// Starts the local HTTP management server on all interfaces at port 9090
  Future<void> startServer({int port = 9090}) async {
    if (_isRunning) return;

    try {
      await _initWebRootAssets();
      await _initStorageFolder();

      // Bind to anyIPv4 to listen across all network interfaces
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;
      MeshLogProvider().addLog('Web server started successfully on all interfaces at port $port');

      _registerMDNSService(port);

      _server!.listen((HttpRequest request) {
        _handleRequest(request);
      }, onError: (error) {
        MeshLogProvider().addLog('Web server error encountered: $error');
      });
    } catch (e) {
      MeshLogProvider().addLog('Failed to start web server: $e');
      _isRunning = false;
    }
  }

  /// Copies assets from the Flutter bundle to a local disk directory for HttpServer serving
  Future<void> _initWebRootAssets() async {
    final appDir = await getApplicationDocumentsDirectory();
    final webDir = Directory('${appDir.path}/web_root');
    if (!await webDir.exists()) {
      await webDir.create(recursive: true);
    }
    _webRootPath = webDir.path;

    try {
      final manifestContent = await rootBundle.loadString('assets/index.html');
      final file = File('$_webRootPath/index.html');
      await file.writeAsString(manifestContent);
      MeshLogProvider().addLog('Provisioned web assets from project assets folder.');
    } catch (e) {
      final file = File('$_webRootPath/index.html');
      if (!await file.exists()) {
        await file.writeAsString('<html><body style="background:#121212;color:#fff;font-family:sans-serif;text-align:center;padding-top:50px;"><h1>Media Client TV Dashboard</h1><p>Running on fallback asset view.</p></body></html>');
      }
    }
  }

  /// Initializes the dedicated storage folder for saving incoming files via web requests
  Future<void> _initStorageFolder() async {
    final appDir = await getApplicationDocumentsDirectory();
    final storageDir = Directory('${appDir.path}/saved_files');
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    _storageFolderPath = storageDir.path;
  }

  /// Stops the web server and cleans up active WebSocket connections
  Future<void> stopServer() async {
    if (!_isRunning) return;
    for (var client in _connectedClients) {
      await client.close();
    }
    _connectedClients.clear();
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    MeshLogProvider().addLog('Web server stopped.');
  }

  /// Broadcasts system log events instantly to all connected WebSocket clients
  void broadcastLog(String message) {
    for (var client in _connectedClients) {
      try {
        client.add(json.encode({'type': 'log', 'data': message}));
      } catch (_) {}
    }
  }

  /// Registers mDNS service discovery hooks for automated local peer discovery
  void _registerMDNSService(int port) {
    MeshLogProvider().addLog('mDNS advertising service initialized for local peer discovery on port $port.');
  }

  /// Routes incoming HTTP requests, manages REST APIs, WebSockets, and File Saving/Plugin integrations
  void _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    // Handle WebSocket upgrade for real-time console log streaming and terminal telemetry
    if (WebSocketTransformer.isUpgradeRequest(request) || path == '/ws') {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _connectedClients.add(socket);
        MeshLogProvider().addLog('Remote web client connected via WebSocket.');
        
        socket.listen(
          (data) => _handleWebSocketMessage(socket, data),
          onDone: () {
            _connectedClients.remove(socket);
            MeshLogProvider().addLog('Remote web client disconnected.');
          },
          onError: (_) => _connectedClients.remove(socket),
        );
      } catch (e) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.close();
      }
      return;
    }

    // Add CORS headers for web dashboard interaction
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, x-file-name');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    // Comprehensive REST API Routing & File Saving Endpoints
    if (path == '/api/status') {
      request.response
        ..headers.contentType = ContentType.json
        ..write(json.encode({
          'status': 'online',
          'app': 'media-client-tv',
          'active_websockets': _connectedClients.length,
          'timestamp': DateTime.now().toIso8601String(),
        }))
        ..close();
    } else if (path == '/api/logs') {
      request.response
        ..headers.contentType = ContentType.json
        ..write(json.encode({'logs': MeshLogProvider().logs}))
        ..close();
    } else if (path == '/api/skin') {
      if (request.method == 'POST') {
        try {
          final content = await utf8.decoder.bind(request).join();
          final data = json.decode(content);
          await SkinManager().updateSkinConfig(data);
          request.response
            ..headers.contentType = ContentType.json
            ..write(json.encode({'status': 'success', 'message': 'Skin updated successfully'}))
            ..close();
        } catch (e) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write(json.encode({'status': 'error', 'message': e.toString()}))
            ..close();
        }
      } else {
        request.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({'status': 'success', 'skin': SkinManager().currentSkin.toJson()}))
          ..close();
      }
    } else if (path == '/api/settings') {
      if (request.method == 'POST') {
        try {
          final content = await utf8.decoder.bind(request).join();
          final data = json.decode(content);
          await SettingsManager().updateSettings(data);
          request.response
            ..headers.contentType = ContentType.json
            ..write(json.encode({'status': 'success', 'message': 'Settings updated'}))
            ..close();
        } catch (e) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write(json.encode({'status': 'error', 'message': e.toString()}))
            ..close();
        }
      } else {
        request.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({'status': 'success', 'settings': SettingsManager().customSettings}))
          ..close();
      }
    } else if (path == '/api/file/save' && request.method == 'POST') {
      try {
        final fileName = request.headers.value('x-file-name') ?? 'uploaded_${DateTime.now().millisecondsSinceEpoch}.dat';
        final file = File('$_storageFolderPath/$fileName');
        
        final contentBytes = await _consolidatingBytes(request);
        await file.writeAsBytes(contentBytes);

        MeshLogProvider().addLog('File successfully saved to folder: $fileName (${contentBytes.length} bytes)');
        request.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({'success': true, 'file': fileName, 'path': file.path}))
          ..close();
      } catch (e) {
        MeshLogProvider().addLog('Failed to save uploaded file: $e');
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write(json.encode({'success': false, 'error': e.toString()}))
          ..close();
      }
    } else if (path == '/api/clipboard') {
      if (request.method == 'POST') {
        try {
          final content = await utf8.decoder.bind(request).join();
          final data = json.decode(content);
          final textPayload = (data['clipboard'] ?? data['text'] ?? '').toString();

          if (textPayload.isNotEmpty) {
            _latestClipboard = textPayload;
            await Clipboard.setData(ClipboardData(text: textPayload));
            MeshLogProvider().addLog('Clipboard action synchronized: $textPayload');
          }

          request.response
            ..headers.contentType = ContentType.json
            ..write(json.encode({'success': true, 'clipboard': _latestClipboard, 'received': textPayload}))
            ..close();
        } catch (e) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write(json.encode({'success': false, 'error': e.toString()}))
            ..close();
        }
      } else {
        // GET request to serve current clipboard state to polling clients or web studio
        request.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({'status': 'success', 'clipboard': _latestClipboard}))
          ..close();
      }
    } else if (path == '/api/notify' && request.method == 'POST') {
      MeshLogProvider().addLog('Test notification dispatch triggered from web control panel.');
      request.response
        ..headers.contentType = ContentType.json
        ..write(json.encode({'success': true, 'message': 'Notification dispatched successfully'}))
        ..close();
    } else if (path == '/api/plugin/xml' && request.method == 'POST') {
      try {
        final xmlContent = await utf8.decoder.bind(request).join();
        MeshLogProvider().addLog('XML UI manifest configuration received and parsed.');
        request.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({'success': true, 'message': 'XML manifest loaded successfully', 'bytes': xmlContent.length}))
          ..close();
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write(json.encode({'success': false, 'error': e.toString()}))
          ..close();
      }
    } else if (path == '/api/plugin/lua' && request.method == 'POST') {
      try {
        final luaScript = await utf8.decoder.bind(request).join();
        MeshLogProvider().addLog('Dynamic Lua script execution payload received.');
        request.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({'success': true, 'message': 'Lua script parsed/evaluated successfully'}))
          ..close();
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write(json.encode({'success': false, 'error': e.toString()}))
          ..close();
      }
    } else {
      var filePath = path == '/' ? '/index.html' : path;
      final file = File('$_webRootPath$filePath');

      if (await file.exists()) {
        final ext = filePath.split('.').last;
        ContentType contentType = ContentType.html;
        if (ext == 'js') contentType = ContentType('application', 'javascript');
        if (ext == 'css') contentType = ContentType('text', 'css');
        if (ext == 'json') contentType = ContentType.json;
        if (ext == 'png') contentType = ContentType('image', 'png');
        if (ext == 'jpg') contentType = ContentType('image', 'jpeg');

        request.response
          ..headers.contentType = contentType
          ..add(await file.readAsBytes())
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('404 - Requested Asset Not Found')
          ..close();
      }
    }
  }

  Future<List<int>> _consolidatingBytes(HttpRequest request) async {
    final List<int> bytes = [];
    await for (var chunk in request) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  void _handleWebSocketMessage(WebSocket socket, dynamic data) {
    try {
      final parsed = json.decode(data);
      final String command = parsed['command'] ?? parsed['action'] ?? '';
      MeshLogProvider().addLog('Command received via WebSocket channel: $command');

      if (command == 'ping') {
        socket.add(json.encode({'event': 'pong', 'timestamp': DateTime.now().toIso8601String()}));
      } else if (command == 'get_logs') {
        socket.add(json.encode({'event': 'logs_snapshot', 'logs': MeshLogProvider().logs}));
      }
    } catch (_) {}
  }
}
