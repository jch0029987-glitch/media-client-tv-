import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _endpointKey = 'custom_media_endpoint';

  static Future<void> saveEndpoint(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_endpointKey, url);
  }

  static Future<String> loadEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_endpointKey) ?? '';
  }
}
