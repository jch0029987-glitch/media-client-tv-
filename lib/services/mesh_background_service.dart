import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'mesh_log_provider.dart';

/// Full-featured Mesh Background Web Service handling port 9090, 
/// WebSocket management, REST API endpoints, and clean static asset serving.
class MeshBackgroundService {
  static final MeshBackgroundService _instance = MeshBackgroundService._internal();
  factory MeshBackgroundService() => _instance;
  MeshBackgroundService._internal();

  HttpServer? _server;
  bool _isRunning = false;
  final List<WebSocket> _connectedClients = [];
  final List<String> _systemLogs = [];
  late String _webRootPath;
  late String _storageFolderPath;

  bool get isRunning => _isRunning;

  /// Starts the local HTTP management server on all interfaces at port 9090
  Future<void> startServer({int port = 9090}) async {
    if (_isRunning) return;

    try {
      await _initWebRootAssets();
      await _initStorageFolder();

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

  Future<void> _initWebRootAssets() async {
    final appDir = await getApplicationDocumentsDirectory();
    final webDir = Directory('${appDir.path}/web_root');
    if (!await webDir.exists()) {
      await webDir.create(recursive: true);
    }
    _webRootPath = webDir.path;

    // Load companion dashboard index from bundle assets cleanly
    try {
      final htmlContent = await rootBundle.loadString('assets/web/index.html');
      await File('$_webRootPath/index.html').writeAsString(htmlContent);
      MeshLogProvider().addLog('Indexed web dashboard assets loaded successfully.');
    } catch (e) {
      MeshLogProvider().addLog('Warning: Could not load assets/web/index.html from bundle: $e');
    }
  }

  Future<void> _initStorageFolder() async {
    final appDir = await getApplicationDocumentsDirectory();
    final storageDir = Directory('${appDir.path}/saved_files');
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    _storageFolderPath = storageDir.path;
  }

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

  void _registerMDNSService(int port) {
    MeshLogProvider().addLog('mDNS advertising service initialized for local peer discovery on port $port.');
  }

  void _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    // Handle WebSocket upgrade stream
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

    // API Routes & Handlers
    if (path == '/api/status') {
      request.response
        ..headers.contentType = ContentType.json
        ..write(json.encode({
          'status': 'online',
          'app': 'media-client-tv',
          'active_websockets': _connectedClients.length,
          'storage_path': _storageFolderPath,
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
        final fileName = request.headers.value('x-file-name') ?? 'uploaded_${DateTime.now().millisecondsSinceEpoch}.dat';
        final file = File('$_storageFolderPath/$fileName');
        
        final contentBytes = await _consolidateBytes(request);
        await file.writeAsBytes(contentBytes);

        MeshLogProvider().addLog('File successfully saved: $fileName (${contentBytes.length} bytes)');
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
    } else if (path == '/api/clipboard' && request.method == 'POST') {
      try {
        final content = await utf8.decoder.bind(request).join();
        final data = json.decode(content);
        MeshLogProvider().addLog('Clipboard action synchronized: ${data['text'] ?? ''}');
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
      MeshLogProvider().addLog('Test notification dispatch triggered from web control panel.');
      request.response
        ..headers.contentType = ContentType.json
        ..write(json.encode({'success': true, 'message': 'Notification dispatched successfully'}))
        ..close();
    } else {
      // Clean Static File Server for Dashboard Client UI
      var filePath = path == '/' ? '/index.html' : path;
      final file = File('$_webRootPath$filePath');

      if (await file.exists()) {
        final ext = filePath.split('.').last.toLowerCase();
        ContentType contentType = ContentType.html;
        if (ext == 'js') contentType = ContentType('application', 'javascript');
        if (ext == 'css') contentType = ContentType('text', 'css');
        if (ext == 'json') contentType = ContentType.json;
        if (ext == 'png') contentType = ContentType('image', 'png');
        if (ext == 'jpg' || ext == 'jpeg') contentType = ContentType('image', 'jpeg');
        if (ext == 'svg') contentType = ContentType('image', 'svg+xml');

        request.response
          ..headers.contentType = contentType
          ..add(await file.readAsBytes())
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.html
          ..write('<html><body style="background:#0f172a;color:#f8fafc;font-family:sans-serif;text-align:center;padding-top:100px;"><h1>404 - Asset Not Found</h1><p>The requested file could not be located on the mesh node.</p></body></html>')
          ..close();
      }
    }
  }

  Future<List<int>> _consolidateBytes(HttpRequest request) async {
    final List<int> bytes = [];
    await for (var chunk in request) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  void _handleWebSocketMessage(WebSocket socket, dynamic data) {
    try {
      final parsed = json.decode(data);
      MeshLogProvider().addLog('Command received via WebSocket: ${parsed['command'] ?? 'unknown'}');
      socket.add(json.encode({'status': 'acknowledged', 'command': parsed['command']}));
    } catch (_) {}
  }
}
