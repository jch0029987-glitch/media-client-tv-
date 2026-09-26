import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mesh_log_provider.dart';
import 'library_plugin_provider.dart';
import 'lua_jit_engine.dart';

class StorageManager extends ChangeNotifier {
  static final StorageManager _instance = StorageManager._internal();
  factory StorageManager() => _instance;
  StorageManager._internal();

  String? _linkedFolderPath;
  String? get linkedFolderPath => _linkedFolderPath;

  List<FileSystemEntity> _linkedFiles = [];
  List<FileSystemEntity> get linkedFiles => List.unmodifiable(_linkedFiles);

  Future<void> loadLinkedFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _linkedFolderPath = prefs.getString('mesh_linked_folder_path');
      
      if (_linkedFolderPath == null) {
        final appDir = await getApplicationDocumentsDirectory();
        final pluginDir = Directory('${appDir.path}/plugins');
        if (await pluginDir.exists()) {
          _linkedFolderPath = pluginDir.path;
        }
      }

      if (_linkedFolderPath != null) {
        await scanLinkedFolder();
        await _reloadSavedPluginsFromDisk();
      }
    } catch (e) {
      MeshLogProvider().addLog("Failed to load linked folder: $e");
    }
  }

  Future<void> linkFolder(String path) async {
    _linkedFolderPath = path;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mesh_linked_folder_path', path);
      await scanLinkedFolder();
      await _reloadSavedPluginsFromDisk();
      MeshLogProvider().addLog("Successfully linked storage folder: $path");
      notifyListeners();
    } catch (e) {
      MeshLogProvider().addLog("Failed to link folder $path: $e");
    }
  }

  Future<void> scanLinkedFolder() async {
    if (_linkedFolderPath == null) return;
    try {
      final dir = Directory(_linkedFolderPath!);
      if (await dir.exists()) {
        _linkedFiles = dir.listSync(recursive: false, followLinks: false);
        notifyListeners();
        MeshLogProvider().addLog("Scanned linked folder: ${_linkedFiles.length} items found.");
      } else {
        _linkedFiles = [];
        notifyListeners();
        MeshLogProvider().addLog("Linked folder path does not exist on disk.");
      }
    } catch (e) {
      MeshLogProvider().addLog("Error scanning linked folder: $e");
    }
  }

  Future<void> _reloadSavedPluginsFromDisk() async {
    if (_linkedFolderPath == null) return;
    try {
      final engine = LuaJitEngine();
      for (var entity in _linkedFiles) {
        if (entity is File && entity.path.endsWith('.lua')) {
          final filename = entity.path.split('/').last;
          final luaCode = await entity.readAsString();
          
          LibraryPluginProvider().registerLoadedPlugin(filename, luaCode);
          
          try {
            final executionResult = engine.eval(luaCode);
            if (executionResult.isNotEmpty && !executionResult.startsWith('Error')) {
              final parsedOutput = json.decode(executionResult);
              LibraryPluginProvider().injectPluginPayload(parsedOutput);
            }
          } catch (e) {
            MeshLogProvider().addLog("Lua reboot evaluation notice for $filename: $e");
          }
          
          MeshLogProvider().addLog("Restored plugin from disk on reboot: $filename");
        }
      }
    } catch (e) {
      MeshLogProvider().addLog("Failed to reload plugins from disk: $e");
    }
  }

  Future<bool> savePluginToLinkedFolder(String filename, String code) async {
    if (_linkedFolderPath == null) return false;
    try {
      final dir = Directory(_linkedFolderPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${_linkedFolderPath!}/$filename');
      await file.writeAsString(code);
      await scanLinkedFolder();
      MeshLogProvider().addLog("Saved plugin to linked folder: $filename");
      return true;
    } catch (e) {
      MeshLogProvider().addLog("Failed to save plugin to linked folder: $e");
      return false;
    }
  }
}
