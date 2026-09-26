import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart' as xml;
import 'mesh_log_provider.dart';

class SkinConfig {
  String skinName = "Default Kodi Skin";
  
  Color primaryColor = Colors.blueAccent;
  Color backgroundColor = const Color(0xFF121212);
  Color surfaceColor = const Color(0xFF1E1E1E);
  Color cardBackgroundColor = const Color(0xFF2C2C2C);
  Color textPrimaryColor = Colors.white;
  Color textSecondaryColor = Colors.white70;
  
  int gridColumns = 3;
  double cardCornerRadius = 8.0;
  double borderWidth = 3.0;
  double contentPadding = 40.0;
  double headerFontSize = 28.0;
  bool showNavigationLabels = true;
  String navigationLayout = "rail";
  bool enableDynamicFanart = true;

  static SkinConfig parseXml(String xmlString) {
    final skin = SkinConfig();
    try {
      final document = xml.XmlDocument.parse(xmlString);
      
      final metaElements = document.findAllElements('metadata');
      if (metaElements.isNotEmpty) {
        final nameEl = metaElements.first.findElements('name').firstOrNull;
        if (nameEl != null) skin.skinName = nameEl.innerText.trim();
      }

      final colorElements = document.findAllElements('colors');
      if (colorElements.isNotEmpty) {
        for (var child in colorElements.first.children.whereType<xml.XmlElement>()) {
          final hex = child.innerText.trim();
          final color = _colorFromHex(hex);
          switch (child.name.local) {
            case 'primary': skin.primaryColor = color; break;
            case 'background': skin.backgroundColor = color; break;
            case 'surface': skin.surfaceColor = color; break;
            case 'card_bg': skin.cardBackgroundColor = color; break;
            case 'text_primary': skin.textPrimaryColor = color; break;
            case 'text_secondary': skin.textSecondaryColor = color; break;
          }
        }
      }

      final layoutElements = document.findAllElements('layout');
      if (layoutElements.isNotEmpty) {
        for (var child in layoutElements.first.children.whereType<xml.XmlElement>()) {
          final val = child.innerText.trim();
          switch (child.name.local) {
            case 'grid_columns': skin.gridColumns = int.tryParse(val) ?? 3; break;
            case 'corner_radius': skin.cardCornerRadius = double.tryParse(val) ?? 8.0; break;
            case 'border_width': skin.borderWidth = double.tryParse(val) ?? 3.0; break;
            case 'content_padding': skin.contentPadding = double.tryParse(val) ?? 40.0; break;
            case 'header_font_size': skin.headerFontSize = double.tryParse(val) ?? 28.0; break;
            case 'show_nav_labels': skin.showNavigationLabels = val.toLowerCase() == 'true'; break;
            case 'nav_layout': skin.navigationLayout = val; break;
            case 'enable_dynamic_fanart': skin.enableDynamicFanart = val.toLowerCase() == 'true'; break;
          }
        }
      }
    } catch (e) {
      MeshLogProvider().addLog("Failed to parse full Kodi XML skin document: $e");
    }
    return skin;
  }

  static Color _colorFromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('FF');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

class SkinManager extends ChangeNotifier {
  static final SkinManager _instance = SkinManager._internal();
  factory SkinManager() => _instance;
  SkinManager._internal();

  SkinConfig _currentSkin = SkinConfig();
  SkinConfig get currentSkin => _currentSkin;
  String _rawXmlPayload = "";
  String get rawXmlPayload => _rawXmlPayload;

  Future<void> loadSavedSkin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedXml = prefs.getString('mesh_active_skin_xml');
      if (savedXml != null && savedXml.isNotEmpty) {
        _rawXmlPayload = savedXml;
        _currentSkin = SkinConfig.parseXml(savedXml);
        notifyListeners();
      }
    } catch (e) {
      MeshLogProvider().addLog("Failed to load saved skin: $e");
    }
  }

  Future<void> applySkinXml(String xmlString) async {
    _rawXmlPayload = xmlString;
    _currentSkin = SkinConfig.parseXml(xmlString);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mesh_active_skin_xml', xmlString);
    } catch (e) {
      MeshLogProvider().addLog("Failed to persist skin XML: $e");
    }
  }
}
