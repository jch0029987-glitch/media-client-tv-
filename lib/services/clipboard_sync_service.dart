import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'http/http.dart' as http;
import 'mesh_log_provider.dart';

class ClipboardSyncService {
  static final ClipboardSyncService _instance = ClipboardSyncService._internal();
  factory ClipboardSyncService() => _instance;
  ClipboardSyncService._internal();

  Timer? _syncTimer;
  String _lastSyncedText = '';
  Function(String)? onClipboardReceived;

  /// Starts periodic polling (GET) from the mesh server to catch remote updates
  void startListening(String meshServerUrl) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final response = await http.get(Uri.parse('$meshServerUrl/api/clipboard'));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final remoteText = (data['clipboard'] ?? '').toString().trim();

          if (remoteText.isNotEmpty && remoteText != _lastSyncedText) {
            _lastSyncedText = remoteText;
            MeshLogProvider().addLog("Synced clipboard from web mesh: $remoteText");
            
            // Update device system clipboard
            await Clipboard.setData(ClipboardData(text: remoteText));
            
            if (onClipboardReceived != null) {
              onClipboardReceived!(remoteText);
            }
          }
        }
      } catch (e) {
        // Silently catch network dropouts when mesh server isn't active
      }
    });
  }

  /// Stops background polling
  void stopListening() {
    _syncTimer?.cancel();
  }

  /// Pushes local clipboard or text changes from the TV app to the mesh server (POST)
  Future<bool> pushClipboard(String meshServerUrl, String text) async {
    try {
      final response = await http.post(
        Uri.parse('$meshServerUrl/api/clipboard'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'clipboard': text}),
      );

      if (response.statusCode == 200) {
        _lastSyncedText = text.trim();
        MeshLogProvider().addLog("Pushed local clipboard to mesh: $text");
        return true;
      }
    } catch (e) {
      MeshLogProvider().addLog("Failed to push clipboard to mesh: $e");
    }
    return false;
  }
}
