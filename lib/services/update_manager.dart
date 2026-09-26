import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'mesh_log_provider.dart';

/// Manages OTA background checks against repository releases, 
/// parses APK asset download links, and triggers Android installation intents.
class UpdateManager {
  static final UpdateManager _instance = UpdateManager._internal();
  factory UpdateManager() => _instance;
  UpdateManager._internal();

  static const MethodChannel _platformChannel = MethodChannel('com.media.client.tv/installer');

  bool _updateAvailable = false;
  String? _latestVersion;
  String? _downloadUrl;

  bool get updateAvailable => _updateAvailable;
  String? get latestVersion => _latestVersion;
  String? get downloadUrl => _downloadUrl;

  /// Queries the live GitHub release endpoint to check for newer versions
  Future<void> initializeAndCheckForUpdates() async {
    MeshLogProvider().addLog('Checking for OTA updates from repository releases...');
    try {
      final client = HttpClient();
      // Pointing directly to the repository's latest release API endpoint
      final request = await client.getUrl(Uri.parse('https://api.github.com/repos/jch0029987-glitch/media-client-tv-/releases/latest'));
      request.headers.set('User-Agent', 'MediaClientTV-App');
      
      final response = await request.close();
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = jsonDecode(responseBody);

        _latestVersion = data['tag_name'];
        
        // Extract the browser download URL for the first APK asset attached to the release
        final assets = data['assets'] as List<dynamic>?;
        if (assets != null && assets.isNotEmpty) {
          final apkAsset = assets.firstWhere(
            (asset) => asset['name'].toString().endsWith('.apk'),
            orElse: () => null,
          );
          if (apkAsset != null) {
            _downloadUrl = apkAsset['browser_download_url'];
          }
        }

        // Compare versions (simplified check; integrate semantic versioning comparison as needed)
        MeshLogProvider().addLog('Latest release found: $_latestVersion. Download URL: $_downloadUrl');
        _updateAvailable = _downloadUrl != null;
      } else {
        MeshLogProvider().addLog('Failed to fetch release manifest. Status code: ${response.statusCode}');
      }
    } catch (e) {
      MeshLogProvider().addLog('Error checking for repository updates: $e');
    }
  }

  /// Downloads the release APK and invokes the native package installer
  Future<void> downloadAndApplyUpdate() async {
    if (_downloadUrl == null) {
      MeshLogProvider().addLog('No update download URL available.');
      return;
    }

    MeshLogProvider().addLog('Downloading update package from $_downloadUrl...');
    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/update.apk';
      
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(_downloadUrl!));
      final response = await request.close();
      
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.close();

      MeshLogProvider().addLog('Update APK downloaded successfully to $filePath. Triggering installer intent...');
      
      // Hand off to Android system package manager via platform channel
      await _platformChannel.invokeMethod('installApk', {'path': filePath});
    } catch (e) {
      MeshLogProvider().addLog('Failed to download or apply update: $e');
    }
  }
}
