import 'package:flutter/foundation.dart';

/// Singleton ChangeNotifier provider managing live system logs 
/// for the mesh service and UI observers.
class MeshLogProvider extends ChangeNotifier {
  static final MeshLogProvider _instance = MeshLogProvider._internal();
  factory MeshLogProvider() => _instance;
  MeshLogProvider._internal();

  final List<String> _logs = [];

  List<String> get logs => List.unmodifiable(_logs);

  void addLog(String message) {
    final timestamped = '[${DateTime.now().toIso8601String()}] $message';
    _logs.add(timestamped);
    if (_logs.length > 300) {
      _logs.removeAt(0);
    }
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }
}
