import 'package:flutter/material.dart';

class LibraryPluginProvider extends ChangeNotifier {
  static final LibraryPluginProvider _instance = LibraryPluginProvider._internal();
  factory LibraryPluginProvider() => _instance;
  LibraryPluginProvider._internal();

  final List<dynamic> _dynamicCatalogItems = [];
  List<dynamic> get dynamicCatalogItems => _dynamicCatalogItems;

  final List<dynamic> _dynamicRows = [];
  List<dynamic> get dynamicRows => _dynamicRows;

  final List<Map<String, String>> _loadedPlugins = [];
  List<Map<String, String>> get loadedPlugins => _loadedPlugins;

  void registerLoadedPlugin(String name, String code) {
    _loadedPlugins.removeWhere((p) => p['name'] == name);
    _loadedPlugins.add({'name': name, 'code': code, 'time': DateTime.now().toIso8601String()});
    notifyListeners();
  }

  void injectPluginPayload(dynamic parsedOutput) {
    _dynamicCatalogItems.clear();
    _dynamicRows.clear();

    if (parsedOutput is List) {
      _dynamicCatalogItems.addAll(parsedOutput);
    } else if (parsedOutput is Map) {
      if (parsedOutput['rows'] != null && parsedOutput['rows'] is List) {
        final rowsList = List<dynamic>.from(parsedOutput['rows']);
        rowsList.sort((a, b) => (a['priority'] ?? 0).compareTo(b['priority'] ?? 0));
        _dynamicRows.addAll(rowsList);
      }
      if (parsedOutput['items'] != null && parsedOutput['items'] is List) {
        _dynamicCatalogItems.addAll(parsedOutput['items']);
      }
    }
    notifyListeners();
  }
}
