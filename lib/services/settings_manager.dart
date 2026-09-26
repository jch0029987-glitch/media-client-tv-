import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mesh_log_provider.dart';

class SettingsManager extends ChangeNotifier {
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;
  SettingsManager._internal();

  Map<String, dynamic> _customSettings = {};
  Map<String, dynamic> get customSettings => _customSettings;

  Future<void> loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedJson = prefs.getString('mesh_custom_settings');
      if (savedJson != null) {
        _customSettings = json.decode(savedJson);
        notifyListeners();
      }
    } catch (e) {
      MeshLogProvider().addLog("Failed to load saved settings: $e");
    }
  }

  Future<void> updateSettings(Map<String, dynamic> newSettings) async {
    _customSettings = newSettings;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mesh_custom_settings', json.encode(newSettings));
    } catch (e) {
      MeshLogProvider().addLog("Failed to persist settings: $e");
    }
  }
}
