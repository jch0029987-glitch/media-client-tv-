import 'dart:async';
import 'dart:convert'; // Added for jsonDecode
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

  void startListening(String meshServerUrl) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final response = await http.get(Uri.parse('$meshServerUrl/api/clipboard'));
        if (response.statusCode == 200) {
          // Decode the JSON response map sent by the backend
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

  void stopListening() {
    _syncTimer?.cancel();
  }
}
