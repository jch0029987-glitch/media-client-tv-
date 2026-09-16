import 'package:serious_python/serious_python.dart';

class PythonBridgeService {
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await SeriousPython.run("plugin_runner.py");
      _isInitialized = true;
    } catch (e) {
      // Handle init error gracefully
    }
  }

  static Future<String?> executeTask(String jsonPayload) async {
    try {
      if (!_isInitialized) await initialize();
      return await SeriousPython.run("plugin_runner.py", args: [jsonPayload]);
    } catch (e) {
      return null;
    }
  }
}
