import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class UpdateService {
  // TODO: Replace with your actual GitHub owner and repo name
  static const String _owner = 'YOUR_GITHUB_USERNAME';
  static const String _repo = 'media-client-tv';
  
  static const MethodChannel _platform = MethodChannel('com.example.media_client_tv/installer');

  /// Checks GitHub releases for a newer version than [currentVersion]
  static Future<Map<String, dynamic>?> checkForUpdate(String currentVersion) async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest');
      final response = await http.get(url, headers: {'Accept': 'application/vnd.github.v3+json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String latestTag = data['tag_name'] ?? ''; // e.g., "v1.0.0-5"
        
        if (latestTag != currentVersion) {
          // Find the APK asset download URL
          final assets = data['assets'] as List;
          final apkAsset = assets.firstWhere(
            (asset) => asset['name'].toString().endsWith('.apk'),
            orElse: () => null,
          );

          if (apkAsset != null) {
            return {
              'version': latestTag,
              'url': apkAsset['browser_download_url'],
              'changelog': data['body'] ?? 'No changelog provided.',
            };
          }
        }
      }
    } catch (e) {
      print('Update check failed: $e');
    }
    return null;
  }

  /// Downloads the APK and triggers the Android system installer
  static Future<void> downloadAndInstall(String apkUrl, Function(double progress) onProgress) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await client.send(request);

      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/update.apk';
      final file = File(filePath);
      final sink = file.openWrite();

      await response.stream.forEach((chunk) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          onProgress(downloaded / contentLength);
        }
      });

      await sink.flush();
      await sink.close();
      client.close();

      // Trigger native package installation
      await _installApk(filePath);
    } catch (e) {
      print('Download/Install failed: $e');
    }
  }

  static Future<void> _installApk(String filePath) async {
    try {
      await _platform.invokeMethod('installApk', {'path': filePath});
    } on PlatformException catch (e) {
      print("Failed to install APK: '${e.message}'.");
    }
  }
}
