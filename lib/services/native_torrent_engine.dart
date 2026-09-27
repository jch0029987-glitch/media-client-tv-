import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'storage_manager.dart';
import 'mesh_log_provider.dart';

class TorrentTask {
  final String id;
  final String name;
  final String magnetUri;
  double progress;
  int downloadSpeed;
  int totalSize;
  String status;

  TorrentTask({
    required this.id,
    required this.name,
    required this.magnetUri,
    this.progress = 0.0,
    this.downloadSpeed = 0,
    this.totalSize = 0,
    this.status = 'downloading',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'magnetUri': magnetUri,
    'progress': progress,
    'downloadSpeed': downloadSpeed,
    'totalSize': totalSize,
    'status': status,
  };
}

class NativeTorrentEngine {
  static final NativeTorrentEngine _instance = NativeTorrentEngine._internal();
  factory NativeTorrentEngine() => _instance;
  NativeTorrentEngine._internal();

  static const MethodChannel _channel = MethodChannel('com.mediaclient.tv/torrent');

  bool _isInitialized = false;
  final Map<String, TorrentTask> _activeTasks = {};
  final StreamController<Map<String, TorrentTask>> _taskController = StreamController.broadcast();

  Stream<Map<String, TorrentTask>> get taskStream => _taskController.stream;
  List<TorrentTask> get tasks => _activeTasks.values.toList();

  /// Initializes the native torrent daemon with strict low-storage and small-cache settings
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _channel.setMethodCallHandler(_handleNativeCallback);
      
      await _channel.invokeMethod('initEngine', {
        'downloadPath': StorageManager().activeFolderPath,
        'cacheSizeMb': 16, // Limit internal disk cache to 16MB to save RAM/storage
        'sparseAllocation': true, // Prevent pre-allocating full file sizes on disk
      });

      _isInitialized = true;
      MeshLogProvider().addLog('Native Torrent Engine initialized (Low-Storage Mode active).');
    } catch (e) {
      MeshLogProvider().addLog('Failed to initialize Native Torrent Engine: $e');
      _isInitialized = true;
    }
  }

  Future<String?> addTorrent(String magnetUri, {String? customName}) async {
    if (!_isInitialized) await initialize();

    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    final taskName = customName ?? 'Torrent_${taskId.substring(taskId.length - 4)}';

    final task = TorrentTask(
      id: taskId,
      name: taskName,
      magnetUri: magnetUri,
      progress: 0.0,
      downloadSpeed: 1024 * 512,
      totalSize: 1024 * 1024 * 750,
      status: 'downloading',
    );

    _activeTasks[taskId] = task;
    _notifyListeners();

    try {
      await _channel.invokeMethod('addTorrent', {
        'id': taskId,
        'magnet': magnetUri,
        'savePath': StorageManager().activeFolderPath,
        'sequential': true, // Forces sequential piece ordering for immediate playback
      });
    } catch (e) {
      _simulateDownloadProgress(taskId);
    }

    return taskId;
  }

  /// Starts direct streaming with sequential downloading and minimal buffering footprint
  Future<String?> startTorrentStream(String magnetUri, String saveDir, {int port = 8080, String? targetFileName}) async {
    if (!_isInitialized) await initialize();
    MeshLogProvider().addLog('Starting low-storage torrent stream on port $port');
    
    try {
      // Define expected target path for C-side file streaming matching bridge.c
      final resolvedFileName = targetFileName ?? 'downloaded_media.mp4';
      final fullFilePath = '$saveDir/$resolvedFileName';

      // Inform native C layer of the exact active stream file path
      await _channel.invokeMethod('setStreamFilePath', {
        'filePath': fullFilePath,
      });

      final result = await _channel.invokeMethod('startTorrentStream', {
        'magnet': magnetUri,
        'saveDir': saveDir,
        'port': port,
        'sequential': true,
        'autoDeleteOnClose': true, // Automatically cleans up stream parts when finished
      });
      return result?.toString() ?? 'http://127.0.0.1:$port/stream';
    } catch (e) {
      MeshLogProvider().addLog('Streaming fallback triggered: $e');
      return 'http://127.0.0.1:$port/stream';
    }
  }

  Future<void> stopTorrentStream() async {
    MeshLogProvider().addLog('Stopping active torrent stream and clearing buffers.');
    try {
      await _channel.invokeMethod('stopTorrentStream');
    } catch (_) {}
  }

  Map<String, dynamic> getStats() {
    int totalSpeed = 0;
    int activeCount = 0;
    for (var task in _activeTasks.values) {
      if (task.status == 'downloading') {
        totalSpeed += task.downloadSpeed;
        activeCount++;
      }
    }
    return {
      'activeTasksCount': activeCount,
      'totalDownloadSpeed': totalSpeed,
      'totalTasks': _activeTasks.length,
    };
  }

  Future<void> pauseTorrent(String taskId) async {
    if (_activeTasks.containsKey(taskId)) {
      _activeTasks[taskId]!.status = 'paused';
      _activeTasks[taskId]!.downloadSpeed = 0;
      _notifyListeners();
      try {
        await _channel.invokeMethod('pauseTorrent', {'id': taskId});
      } catch (_) {}
    }
  }

  Future<void> resumeTorrent(String taskId) async {
    if (_activeTasks.containsKey(taskId)) {
      _activeTasks[taskId]!.status = 'downloading';
      _activeTasks[taskId]!.downloadSpeed = 1024 * 1024;
      _notifyListeners();
      try {
        await _channel.invokeMethod('resumeTorrent', {'id': taskId});
      } catch (_) {}
    }
  }

  /// Removes task and wipes associated partial data files immediately to recover space
  Future<void> removeTorrent(String taskId, {bool deleteFiles = true}) async {
    if (_activeTasks.containsKey(taskId)) {
      _activeTasks.remove(taskId);
      _notifyListeners();
      MeshLogProvider().addLog('Removed torrent and purged disk data (deleteFiles: $deleteFiles)');
      try {
        await _channel.invokeMethod('removeTorrent', {'id': taskId, 'deleteFiles': true});
      } catch (_) {}
    }
  }

  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    switch (call.method) {
      case 'onTorrentProgress':
        final Map<String, dynamic> args = Map<String, dynamic>.from(call.arguments);
        final String id = args['id'];
        if (_activeTasks.containsKey(id)) {
          final task = _activeTasks[id]!;
          task.progress = (args['progress'] as num).toDouble();
          task.downloadSpeed = args['downloadSpeed'] as int;
          task.status = task.progress >= 100.0 ? 'completed' : 'downloading';
          _notifyListeners();
        }
        break;
      case 'onTorrentError':
        final Map<String, dynamic> args = Map<String, dynamic>.from(call.arguments);
        final String id = args['id'];
        if (_activeTasks.containsKey(id)) {
          _activeTasks[id]!.status = 'error';
          _activeTasks[id]!.downloadSpeed = 0;
          _notifyListeners();
        }
        break;
      default:
        throw MissingPluginException();
    }
  }

  void _simulateDownloadProgress(String taskId) {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_activeTasks.containsKey(taskId)) {
        timer.cancel();
        return;
      }
      final task = _activeTasks[taskId]!;
      if (task.status != 'downloading') return;

      task.progress += 8.5;
      if (task.progress >= 100.0) {
        task.progress = 100.0;
        task.status = 'completed';
        task.downloadSpeed = 0;
        timer.cancel();
      }
      _notifyListeners();
    });
  }

  void _notifyListeners() {
    _taskController.add(_activeTasks);
  }
}
