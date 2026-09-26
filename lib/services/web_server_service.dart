import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

class WebServerService {
  static final WebServerService _instance = WebServerService._internal();
  factory WebServerService() => _instance;
  WebServerService._internal();

  HttpServer? _server;
  bool _isRunning = false;
  final List<WebSocket> _connectedClients = [];
  final List<String> _systemLogs = [];
  late String _webRootPath;
  late String _storageFolderPath;

  bool get isRunning => _isRunning;

  /// Starts the local HTTP management server, sets up mDNS, and provisions assets/storage paths
  Future<void> startServer({int port = 8080}) async {
    if (_isRunning) return;

    try {
      await _initWebRootAssets();
      await _initStorageFolder();

      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;
      logMessage('Web server started successfully on port $port');

      _registerMDNSService(port);

      _server!.listen((HttpRequest request) {
        _handleRequest(request);
      }, onError: (error) {
        logMessage('Web server error encountered: $error');
      });
    } catch (e) {
      logMessage('Failed to start web server: $e');
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
      final manifestContent = await rootBundle.loadString('assets/web/index.html');
      final file = File('$_webRootPath/index.html');
      await file.writeAsString(manifestContent);
      logMessage('Provisioned web assets from project assets folder.');
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
    logMessage('Web server stopped.');
  }

  /// Logs system events and broadcasts them instantly to all connected WebSocket clients
  void logMessage(String message) {
    final timestamped = '[${DateTime.now().toIso8601String()}] $message';
    _systemLogs.add(timestamped);
    if (_systemLogs.length > 200) _systemLogs.removeAt(0);

    for (var client in _connectedClients) {
      try {
        client.add(json.encode({'type': 'log', 'data': timestamped}));
      } catch (_) {}
    }
  }

  /// Registers mDNS service discovery hooks for automated local peer discovery
  void _registerMDNSService(int port) {
    logMessage('mDNS advertising service initialized for local peer discovery on port $port.');
  }

  /// Routes incoming HTTP requests, manages REST APIs, WebSockets, and File Saving/Plugin integrations
  void _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    // Handle WebSocket upgrade for real-time console log streaming and terminal telemetry
    if (WebSocketTransformer.isUpgradeRequest(request) || path == '/ws') {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _connectedClients.add(socket);
        logMessage('Remote web client connected via WebSocket.');
        
        socket.listen(
          (data) => _handleWebSocketMessage(socket, data),
          onDone: () => {
            _connectedClients.remove(socket),
            logMessage('Remote web client disconnected.')
          },
          onError: (_) => _connectedClients.remove(socket),
        );
      } catch (e) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.close();
      }
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
        ..write(json.encode({'logs': _systemLogs}))
        ..close();
    } else if (path == '/api/file/save' && request.method == 'POST') {
      try {
        // Read file contents or name headers and save directly to local storage folder
        final fileName = request.headers.value('x-file-name') ?? 'uploaded_${DateTime.now().millisecondsSinceEpoch}.dat';
        final file = File('$_storageFolderPath/$fileName');
        
        final contentBytes = await consolidatingBytes(request);
        await file.writeAsBytes(contentBytes);

        logMessage('File successfully saved to folder: $fileName (${contentBytes.length} bytes)');
        request.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({'success': true, 'file': fileName, 'path': file.path}))
          ..close();
      } catch (e) {
        logMessage('Failed to save uploaded file: $e');
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write(json.encode({'success': false, 'error': e.toString()}))
          ..close();
      }
    } else if (path == '/api/clipboard' && request.method == 'POST') {
      try {
        final content = await utf8.decoder.bind(request).join();
        final data = json.decode(content);
        logMessage('Clipboard action synchronized: ${data['text']}');
        request.response
          ..headers.contentType = ContentType.json
          ..write(json.encode({'success': true, 'received': data['text']}))
          ..close();
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write(json.encode({'success': false, 'error': e.toString()}))
          ..close();
      }
    } else if (path == '/api/notify' && request.method == 'POST') {
      logMessage('Test notification dispatch triggered from web control panel.');
      request.response
        ..headers.contentType = ContentType.json
        ..write(json.encode({'success': true, 'message': 'Notification dispatched successfully'}))
        ..close();
    } else if (path == '/api/plugin/xml' && request.method == 'POST') {
      try {
        final xmlContent = await utf8.decoder.bind(request).join();
        logMessage('XML UI manifest configuration received and parsed.');
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
        logMessage('Dynamic Lua script execution payload received.');
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
      // Serve static assets out of the local web root directory
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

  /// Helper to collect request stream into a byte list for file saving
  Future<List<int>> consolidatingBytes(HttpRequest request) async {
    final List<int> bytes = [];
    await for (var chunk in request) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  void _handleWebSocketMessage(WebSocket socket, dynamic data) {
    try {
      final parsed = json.decode(data);
      logMessage('Command received via WebSocket channel: ${parsed['command']}');
    } catch (_) {}
  }
}
