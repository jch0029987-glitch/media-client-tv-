import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart' as xml;
import 'screens/player_screen.dart';
import 'services/airplay_system.dart';
import 'widgets/airplay_device_selector.dart';

// Define C function signature mapping for dynamic Lua FFI bindings
typedef EvalLuaScriptC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> scriptContent);
typedef EvalLuaScriptDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> scriptContent);

typedef CallLuaSearchC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> scriptContent, ffi.Pointer<Utf8> queryTerm);
typedef CallLuaSearchDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> scriptContent, ffi.Pointer<Utf8> queryTerm);

class ToastHelper {
  static const MethodChannel _platform = MethodChannel('com.example.media_client_tv/installer');

  static Future<void> showToast(String message) async {
    try {
      await _platform.invokeMethod('showToast', {'message': message});
    } catch (e) {
      MeshLogProvider().addLog("Failed to show toast: $e");
    }
  }
}

/// Global Real-Time Log Buffer Provider for Web Dashboard Broadcasting
class MeshLogProvider extends ChangeNotifier {
  static final MeshLogProvider _instance = MeshLogProvider._internal();
  factory MeshLogProvider() => _instance;
  MeshLogProvider._internal();

  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

  void addLog(String message) {
    final timestamp = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    final entry = "[$timestamp] $message";
    _logs.insert(0, entry); // newest first
    if (_logs.length > 200) {
      _logs.removeLast();
    }
    notifyListeners();
  }
}

/// Persistent Local Storage & Folder Link Manager
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
      if (_linkedFolderPath != null) {
        await scanLinkedFolder();
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

class LuaJitEngine {
  late final ffi.DynamicLibrary _lib;
  late final EvalLuaScriptDart _evalScript;
  late final CallLuaSearchDart _callSearch;
  bool _initialized = false;

  void initialize() {
    if (_initialized) return;

    try {
      _lib = Platform.isAndroid
          ? ffi.DynamicLibrary.open('libluajit.so')
          : ffi.DynamicLibrary.process();

      _evalScript = _lib
          .lookup<ffi.NativeFunction<EvalLuaScriptC>>('eval_lua_script')
          .asFunction();

      _callSearch = _lib
          .lookup<ffi.NativeFunction<CallLuaSearchC>>('call_lua_search')
          .asFunction();

      _initialized = true;
      MeshLogProvider().addLog("LuaJIT Engine initialized successfully.");
    } catch (e) {
      MeshLogProvider().addLog("Failed to load LuaJIT native library: $e");
    }
  }

  String eval(String scriptContent) {
    if (!_initialized) initialize();
    if (!_initialized) return 'Error: Lua engine not initialized';

    final scriptPtr = scriptContent.toNativeUtf8();
    try {
      final resultPtr = _evalScript(scriptPtr);
      return resultPtr.toDartString();
    } finally {
      calloc.free(scriptPtr);
    }
  }

  String executeAction(String scriptContent, String action, String query) {
    if (!_initialized) initialize();
    if (!_initialized) return '{"status": "error", "message": "Lua engine not initialized"}';

    final wrappedScript = '''
      action = "$action"
      query = "$query"
      $scriptContent
    ''';

    final scriptPtr = wrappedScript.toNativeUtf8();
    try {
      final resultPtr = _evalScript(scriptPtr);
      return resultPtr.toDartString();
    } finally {
      calloc.free(scriptPtr);
    }
  }

  String search(String scriptContent, String queryTerm) {
    if (!_initialized) initialize();
    if (!_initialized) return '{"status": "error", "items": []}';

    final wrappedScript = '''
      search_query = "$queryTerm"
      action = "search"
      $scriptContent
    ''';

    final scriptPtr = wrappedScript.toNativeUtf8();
    try {
      final resultPtr = _evalScript(scriptPtr);
      return resultPtr.toDartString();
    } finally {
      calloc.free(scriptPtr);
    }
  }
}

/// Comprehensive Kodi-Style XML Skin Configuration Model
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

class MeshBackgroundService {
  static final MeshBackgroundService _instance = MeshBackgroundService._internal();
  factory MeshBackgroundService() => _instance;
  MeshBackgroundService._internal();

  HttpServer? _server;
  bool _isRunning = false;
  final int _port = 9090;
  final LuaJitEngine _luaEngine = LuaJitEngine();

  bool get isRunning => _isRunning;

  Future<void> startServer() async {
    if (_isRunning) return;
    try {
      _luaEngine.initialize();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _isRunning = true;
      MeshLogProvider().addLog("Background Mesh Server started successfully on port $_port");

      _server!.listen(_handleMeshRequest, onError: (e) {
        MeshLogProvider().addLog("Mesh server stream error: $e");
      });
    } catch (e) {
      _isRunning = false;
      MeshLogProvider().addLog("Failed to start background mesh server: $e");
    }
  }

  Future<void> _handleMeshRequest(HttpRequest request) async {
    final response = request.response;

    try {
      if (request.method == 'GET' && request.uri.path == '/') {
        final htmlContent = await rootBundle.loadString('assets/index.html');
        response.headers.contentType = ContentType.html;
        response.statusCode = HttpStatus.ok;
        response.write(htmlContent);
      } else if (request.method == 'GET' && request.uri.path == '/api/system/logs') {
        response.headers.contentType = ContentType.json;
        response.statusCode = HttpStatus.ok;
        response.write(json.encode({'logs': MeshLogProvider().logs}));
      } else if (request.method == 'POST' && request.uri.path == '/api/storage/link') {
        response.headers.contentType = ContentType.json;
        final content = await utf8.decoder.bind(request).join();
        final data = json.decode(content);
        final String folderPath = data['path'] ?? '';

        if (folderPath.isNotEmpty) {
          await StorageManager().linkFolder(folderPath);
          await ToastHelper.showToast('Storage Folder Linked Successfully!');
          response.statusCode = HttpStatus.ok;
          response.write(json.encode({'status': 'success', 'path': folderPath}));
        } else {
          response.statusCode = HttpStatus.badRequest;
          response.write(json.encode({'error': 'Invalid path'}));
        }
      } else if (request.method == 'POST' && request.uri.path == '/api/plugins/save') {
        response.headers.contentType = ContentType.json;
        final content = await utf8.decoder.bind(request).join();
        final data = json.decode(content);
        
        final String filename = data['name'] ?? 'plugin.lua';
        final String luaCode = data['code'] ?? '';
        
        bool success = false;
        String targetPath = '';

        if (StorageManager().linkedFolderPath != null) {
          success = await StorageManager().savePluginToLinkedFolder(filename, luaCode);
          targetPath = '${StorageManager().linkedFolderPath}/$filename';
        } else {
          final appDir = await getApplicationDocumentsDirectory();
          final pluginDir = Directory('${appDir.path}/plugins');
          if (!await pluginDir.exists()) await pluginDir.create(recursive: true);
          
          final file = File('${pluginDir.path}/$filename');
          await file.writeAsString(luaCode);
          targetPath = file.path;
          success = true;
        }

        if (success) {
          LibraryPluginProvider().registerLoadedPlugin(filename, luaCode);
          MeshLogProvider().addLog("Saved and registered Lua plugin: $filename");

          try {
            final executionResult = _luaEngine.eval(luaCode);
            if (executionResult.isNotEmpty && !executionResult.startsWith('Error')) {
              final parsedOutput = json.decode(executionResult);
              LibraryPluginProvider().injectPluginPayload(parsedOutput);
            }
          } catch (e) {
            MeshLogProvider().addLog("Lua execution evaluation notice: $e");
          }

          await ToastHelper.showToast('Lua Plugin $filename Deployed!');
          response.statusCode = HttpStatus.ok;
          response.write(json.encode({'status': 'success', 'path': targetPath}));
        } else {
          response.statusCode = HttpStatus.internalServerError;
          response.write(json.encode({'error': 'Failed to save plugin file'}));
        }
      } else if (request.method == 'POST' && request.uri.path == '/api/skin/save') {
        response.headers.contentType = ContentType.json;
        final content = await utf8.decoder.bind(request).join();
        final data = json.decode(content);
        
        final String filename = data['name'] ?? 'skin.xml';
        final String xmlCode = data['code'] ?? '';

        final appDir = await getApplicationDocumentsDirectory();
        final skinDir = Directory('${appDir.path}/skins');
        if (!await skinDir.exists()) await skinDir.create(recursive: true);
        
        final file = File('${skinDir.path}/$filename');
        await file.writeAsString(xmlCode);

        await SkinManager().applySkinXml(xmlCode);
        MeshLogProvider().addLog("Applied and saved Kodi skin: $filename");
        await ToastHelper.showToast('Kodi Skin $filename Applied & Saved!');

        response.statusCode = HttpStatus.ok;
        response.write(json.encode({'status': 'success', 'path': file.path}));
      } else if (request.method == 'POST' && request.uri.path == '/api/system/toast') {
        response.headers.contentType = ContentType.json;
        final content = await utf8.decoder.bind(request).join();
        final data = json.decode(content);
        final String message = data['message'] ?? 'Notification';
        
        await ToastHelper.showToast(message);
        MeshLogProvider().addLog("Broadcasted toast: $message");
        response.statusCode = HttpStatus.ok;
        response.write(json.encode({'status': 'success'}));
      } else {
        response.headers.contentType = ContentType.json;
        response.statusCode = HttpStatus.notFound;
        response.write(json.encode({"error": "Endpoint not found"}));
      }
    } catch (e) {
      MeshLogProvider().addLog("Mesh request error: $e");
      response.headers.contentType = ContentType.json;
      response.statusCode = HttpStatus.internalServerError;
      response.write(json.encode({"error": e.toString()}));
    } finally {
      await response.close();
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MeshLogProvider().addLog("App initialization started.");
  
  await SkinManager().loadSavedSkin();
  await SettingsManager().loadSavedSettings();
  await StorageManager().loadLinkedFolder();
  
  await MeshBackgroundService().startServer();

  AirPlaySystem().initializeNativeDaemon();
  await AirPlaySystem().startNativeServer(7000);

  MeshLogProvider().addLog("App fully booted up on Android TV.");
  runApp(const MediaClientApp());
}

class MediaClientApp extends StatelessWidget {
  const MediaClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SkinManager(),
      builder: (context, _) {
        final skin = SkinManager().currentSkin;
        return MaterialApp(
          title: 'Media Client TV',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: skin.backgroundColor,
            colorScheme: ColorScheme.dark(
              primary: skin.primaryColor,
              surface: skin.surfaceColor,
            ),
          ),
          home: const MainScreen(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final AirPlaySystem _airPlaySystem = AirPlaySystem();

  late final List<Widget> _screens = [
    const LibraryScreen(),
    const PluginHubScreen(),
    AirPlayHubTab(airPlaySystem: _airPlaySystem),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SkinManager(),
      builder: (context, _) {
        final skin = SkinManager().currentSkin;
        
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (int index) => setState(() => _selectedIndex = index),
                labelType: skin.showNavigationLabels 
                    ? NavigationRailLabelType.all 
                    : NavigationRailLabelType.none,
                backgroundColor: skin.surfaceColor,
                selectedIconTheme: IconThemeData(color: skin.primaryColor),
                unselectedIconTheme: const IconThemeData(color: Colors.white60),
                selectedLabelTextStyle: TextStyle(color: skin.primaryColor, fontWeight: FontWeight.bold),
                unselectedLabelTextStyle: TextStyle(color: skin.textSecondaryColor),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.video_library),
                    label: Text('Library'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.extension),
                    label: Text('Plugin Hub'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.cast),
                    label: Text('AirPlay'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings),
                    label: Text('Settings'),
                  ),
                ],
              ),
              const VerticalDivider(thickness: 1, width: 1, color: Colors.white24),
              Expanded(
                child: _screens[_selectedIndex],
              ),
            ],
          ),
        );
      },
    );
  }
}

class AirPlayHubTab extends StatelessWidget {
  final AirPlaySystem airPlaySystem;

  const AirPlayHubTab({super.key, required this.airPlaySystem});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AirPlay Receiver Hub',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            'Discover and connect to AirPlay senders on your local network.',
            style: TextStyle(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 32),
          Center(
            child: AirPlayDeviceSelector(airPlaySystem: airPlaySystem),
          ),
        ],
      ),
    );
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<dynamic> _addons = [];
  List<dynamic> _currentCatalogItems = [];
  List<dynamic> _currentDynamicRows = [];
  bool _isLoading = true;
  int _selectedAddonIndex = 0;
  String? _activeCatalogUrl;
  String? _activeFanartUrl;

  final String masterIndexUrl = 'https://jch0029987-glitch.github.io/media-client-backend/addons.json';
  late final LibraryPluginProvider _pluginProvider;

  @override
  void initState() {
    super.initState();
    _pluginProvider = LibraryPluginProvider();
    _pluginProvider.addListener(_onPluginCatalogUpdated);
    _fetchMasterIndex();
  }

  @override
  void dispose() {
    _pluginProvider.removeListener(_onPluginCatalogUpdated);
    super.dispose();
  }

  void _onPluginCatalogUpdated() {
    if (_activeCatalogUrl == 'local://lua_plugin') {
      setState(() {
        _currentCatalogItems = _pluginProvider.dynamicCatalogItems;
        _currentDynamicRows = _pluginProvider.dynamicRows;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchMasterIndex() async {
    try {
      final response = await http.get(Uri.parse(masterIndexUrl));
      List<dynamic> fetchedAddons = [];
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        fetchedAddons = data['addons'] ?? [];
      }

      setState(() {
        _addons = [
          {'name': 'Local Lua Plugin', 'catalog_url': 'local://lua_plugin'},
          ...fetchedAddons
        ];
      });

      if (_addons.isNotEmpty) {
        _selectCatalogProvider(0, _addons[0]['catalog_url']);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      MeshLogProvider().addLog("Failed to fetch master addon index: $e");
      setState(() {
        _addons = [
          {'name': 'Local Lua Plugin', 'catalog_url': 'local://lua_plugin'}
        ];
        _selectCatalogProvider(0, 'local://lua_plugin');
      });
    }
  }

  void _selectCatalogProvider(int index, String catalogUrl) {
    setState(() {
      _selectedAddonIndex = index;
      _activeCatalogUrl = catalogUrl;
    });

    if (catalogUrl == 'local://lua_plugin') {
      setState(() {
        _currentCatalogItems = _pluginProvider.dynamicCatalogItems;
        _currentDynamicRows = _pluginProvider.dynamicRows;
        _isLoading = false;
      });
    } else {
      _fetchCatalog(catalogUrl);
    }
  }

  Future<void> _fetchCatalog(String catalogUrl) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse(catalogUrl));
      if (_activeCatalogUrl != catalogUrl) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _currentCatalogItems = data['items'] ?? [];
          _currentDynamicRows = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      MeshLogProvider().addLog("Failed to fetch catalog from $catalogUrl: $e");
      if (_activeCatalogUrl == catalogUrl) setState(() => _isLoading = false);
    }
  }

  void _openSearchDialog(BuildContext context, SkinConfig skin) {
    final TextEditingController searchController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: skin.cardBackgroundColor,
          title: Text('Global Search', style: TextStyle(color: skin.textPrimaryColor)),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchController,
                  autofocus: true,
                  style: TextStyle(color: skin.textPrimaryColor),
                  decoration: InputDecoration(
                    hintText: 'Search videos, channels, playlists...',
                    hintStyle: TextStyle(color: skin.textSecondaryColor),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: skin.primaryColor)),
                  ),
                  onSubmitted: (query) async {
                    Navigator.pop(context);
                    await _executeGlobalSearch(query);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: skin.textSecondaryColor)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: skin.primaryColor),
              onPressed: () async {
                final query = searchController.text.trim();
                Navigator.pop(context);
                if (query.isNotEmpty) await _executeGlobalSearch(query);
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _executeGlobalSearch(String query) async {
    setState(() => _isLoading = true);
    final luaCode = _pluginProvider.loadedPlugins.isNotEmpty
        ? _pluginProvider.loadedPlugins.last['code'] ?? ''
        : '';

    if (luaCode.isNotEmpty) {
      final engine = LuaJitEngine();
      final resultJson = engine.search(luaCode, query);
      try {
        final data = json.decode(resultJson);
        setState(() {
          _currentCatalogItems = data['items'] ?? [];
          _currentDynamicRows = [];
          _isLoading = false;
        });
      } catch (e) {
        MeshLogProvider().addLog("Failed to parse search results: $e");
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleItemTap(Map<String, dynamic> item) async {
    final String action = item['action'] ?? 'none';
    final String itemId = item['id'] ?? '';
    final String itemType = item['type'] ?? 'video';
    final String itemTitle = item['title'] ?? 'Media Item';

    if (itemType == 'directory' || action == 'trending' || action == 'popular') {
      setState(() => _isLoading = true);
      
      final luaCode = _pluginProvider.loadedPlugins.isNotEmpty
          ? _pluginProvider.loadedPlugins.last['code'] ?? ''
          : '';

      if (luaCode.isNotEmpty) {
        final engine = LuaJitEngine();
        final resultJson = engine.executeAction(luaCode, action, itemId);
        
        try {
          final data = json.decode(resultJson);
          setState(() {
            _currentCatalogItems = data['items'] ?? [];
            _currentDynamicRows = [];
            _isLoading = false;
          });
        } catch (e) {
          MeshLogProvider().addLog("Failed to parse directory action result: $e");
          setState(() => _isLoading = false);
        }
      } else {
        setState(() => _isLoading = false);
      }
    } else {
      final url = item['stream_url'] ?? item['url'] ?? '';
      if (url.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlayerScreen(streamUrl: url, title: itemTitle),
          ),
        );
      } else if (action == 'resolve_stream' || itemId.isNotEmpty) {
        setState(() => _isLoading = true);
        
        final luaCode = _pluginProvider.loadedPlugins.isNotEmpty
            ? _pluginProvider.loadedPlugins.last['code'] ?? ''
            : '';

        if (luaCode.isNotEmpty) {
          final engine = LuaJitEngine();
          final resultJson = engine.executeAction(luaCode, 'resolve_stream', itemId);
          
          try {
            final data = json.decode(resultJson);
            final streamUrl = data['stream_url'] ?? '';
            setState(() => _isLoading = false);

            if (streamUrl.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(streamUrl: streamUrl, title: itemTitle),
                ),
              );
            } else {
              MeshLogProvider().addLog("Resolved stream URL was empty for item ID: $itemId");
            }
          } catch (e) {
            MeshLogProvider().addLog("Failed to resolve stream JSON: $e");
            setState(() => _isLoading = false);
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SkinManager(),
      builder: (context, _) {
        final skin = SkinManager().currentSkin;

        return Stack(
          children: [
            // Dynamic Fanart Background Layer
            if (skin.enableDynamicFanart && _activeFanartUrl != null && _activeFanartUrl!.isNotEmpty)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.22,
                  child: Image.network(
                    _activeFanartUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(color: skin.backgroundColor),
                  ),
                ),
              ),

            // Main Content Layer
            Padding(
              padding: EdgeInsets.all(skin.contentPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Media Library [${skin.skinName}]',
                            style: TextStyle(fontSize: skin.headerFontSize, fontWeight: FontWeight.bold, color: skin.textPrimaryColor),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: Icon(Icons.search, color: skin.primaryColor),
                            tooltip: 'Global Search',
                            onPressed: () => _openSearchDialog(context, skin),
                          ),
                        ],
                      ),
                      if (_addons.isNotEmpty)
                        SizedBox(
                          height: 40,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            shrinkWrap: true,
                            itemCount: _addons.length,
                            itemBuilder: (context, index) {
                              final addon = _addons[index];
                              final isSelected = _selectedAddonIndex == index;
                              return Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: ActionChip(
                                  backgroundColor: isSelected ? skin.primaryColor : skin.cardBackgroundColor,
                                  label: Text(addon['name'] ?? 'Provider'),
                                  labelStyle: TextStyle(color: skin.textPrimaryColor),
                                  onPressed: () {
                                    _selectCatalogProvider(index, addon['catalog_url']);
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _isLoading
                        ? Center(child: CircularProgressIndicator(color: skin.primaryColor))
                        : (_activeCatalogUrl == 'local://lua_plugin' && _currentDynamicRows.isNotEmpty)
                            ? ListView.builder(
                                itemCount: _currentDynamicRows.length,
                                itemBuilder: (context, rowIndex) {
                                  final row = _currentDynamicRows[rowIndex];
                                  final rowTitle = row['title'] ?? 'Shelf';
                                  final items = (row['items'] as List?) ?? [];

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                                        child: Text(
                                          rowTitle,
                                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: skin.textPrimaryColor),
                                        ),
                                      ),
                                      SizedBox(
                                        height: 180,
                                        child: ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: items.length,
                                          itemBuilder: (context, itemIndex) {
                                            final item = items[itemIndex];
                                            return Focus(
                                              onFocusChange: (hasFocus) {
                                                if (hasFocus) {
                                                  setState(() {
                                                    _activeFanartUrl = item['thumbnail'] ?? item['banner'] ?? '';
                                                  });
                                                }
                                              },
                                              child: Builder(
                                                builder: (context) {
                                                  final hasFocus = Focus.of(context).hasFocus;
                                                  return AnimatedContainer(
                                                    duration: const Duration(milliseconds: 200),
                                                    width: 140,
                                                    margin: const EdgeInsets.only(right: 16, bottom: 12),
                                                    decoration: BoxDecoration(
                                                      color: skin.cardBackgroundColor,
                                                      borderRadius: BorderRadius.circular(skin.cardCornerRadius),
                                                      border: Border.all(
                                                        color: hasFocus ? skin.primaryColor : Colors.transparent,
                                                        width: skin.borderWidth,
                                                      ),
                                                      boxShadow: hasFocus
                                                          ? [BoxShadow(color: skin.primaryColor, blurRadius: 10, spreadRadius: 2)]
                                                          : [],
                                                    ),
                                                    child: InkWell(
                                                      onTap: () => _handleItemTap(item),
                                                      borderRadius: BorderRadius.circular(skin.cardCornerRadius),
                                                      child: Center(
                                                        child: Padding(
                                                          padding: const EdgeInsets.all(8.0),
                                                          child: Text(
                                                            item['title'] ?? 'Item',
                                                            textAlign: TextAlign.center,
                                                            style: TextStyle(fontSize: 14, color: skin.textPrimaryColor, fontWeight: FontWeight.bold),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  );
                                },
                              )
                            : _currentCatalogItems.isEmpty
                                ? Center(
                                    child: Text(
                                      _activeCatalogUrl == 'local://lua_plugin'
                                          ? 'No items or rows from Lua plugin yet.\nDeploy a Lua script via the web mesh UI.'
                                          : 'No media items found.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: skin.textSecondaryColor),
                                    ),
                                  )
                                : GridView.builder(
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: skin.gridColumns,
                                      crossAxisSpacing: 20,
                                      mainAxisSpacing: 20,
                                      childAspectRatio: 16 / 9,
                                    ),
                                    itemCount: _currentCatalogItems.length,
                                    itemBuilder: (context, index) {
                                      final item = _currentCatalogItems[index];
                                      return Focus(
                                        onFocusChange: (hasFocus) {
                                          if (hasFocus) {
                                            setState(() {
                                              _activeFanartUrl = item['thumbnail'] ?? item['banner'] ?? '';
                                            });
                                          }
                                        },
                                        child: Builder(
                                          builder: (context) {
                                            final hasFocus = Focus.of(context).hasFocus;
                                            return AnimatedContainer(
                                              duration: const Duration(milliseconds: 200),
                                              decoration: BoxDecoration(
                                                color: skin.cardBackgroundColor,
                                                borderRadius: BorderRadius.circular(skin.cardCornerRadius),
                                                border: Border.all(
                                                  color: hasFocus ? skin.primaryColor : Colors.transparent,
                                                  width: skin.borderWidth,
                                                ),
                                                boxShadow: hasFocus
                                                    ? [BoxShadow(color: skin.primaryColor, blurRadius: 10, spreadRadius: 2)]
                                                    : [],
                                              ),
                                              child: InkWell(
                                                onTap: () => _handleItemTap(item),
                                                borderRadius: BorderRadius.circular(skin.cardCornerRadius),
                                                child: Center(
                                                  child: Padding(
                                                    padding: const EdgeInsets.all(12.0),
                                                    child: Text(
                                                      item['title'] ?? item['name'] ?? 'Item',
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(fontSize: 16, color: skin.textPrimaryColor, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class PluginHubScreen extends StatelessWidget {
  const PluginHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([SkinManager(), LibraryPluginProvider(), StorageManager()]),
      builder: (context, _) {
        final skin = SkinManager().currentSkin;
        final loadedPlugins = LibraryPluginProvider().loadedPlugins;
        final linkedFolder = StorageManager().linkedFolderPath;
        final linkedFiles = StorageManager().linkedFiles;

        return Padding(
          padding: EdgeInsets.all(skin.contentPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plugin & Mesh Storage Hub',
                style: TextStyle(fontSize: skin.headerFontSize, fontWeight: FontWeight.bold, color: skin.textPrimaryColor),
              ),
              const SizedBox(height: 8),
              Text(
                linkedFolder != null ? 'Linked Folder: $linkedFolder' : 'No storage folder linked yet.',
                style: TextStyle(fontSize: 14, color: skin.primaryColor),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Loaded Active Plugins (${loadedPlugins.length})', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: skin.textPrimaryColor)),
                          const SizedBox(height: 12),
                          Expanded(
                            child: loadedPlugins.isEmpty
                                ? Center(child: Text('No active plugins loaded.', style: TextStyle(color: skin.textSecondaryColor)))
                                : ListView.builder(
                                    itemCount: loadedPlugins.length,
                                    itemBuilder: (context, index) {
                                      final plugin = loadedPlugins[index];
                                      return Card(
                                        color: skin.cardBackgroundColor,
                                        margin: const EdgeInsets.only(bottom: 12),
                                        child: ListTile(
                                          leading: Icon(Icons.extension, color: skin.primaryColor),
                                          title: Text(plugin['name'] ?? 'Plugin', style: TextStyle(color: skin.textPrimaryColor, fontWeight: FontWeight.bold)),
                                          subtitle: Text('Deployed: ${plugin['time']}', style: TextStyle(color: skin.textSecondaryColor, fontSize: 12)),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Linked Directory Contents (${linkedFiles.length})', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: skin.textPrimaryColor)),
                          const SizedBox(height: 12),
                          Expanded(
                            child: linkedFiles.isEmpty
                                ? Center(child: Text('Folder is empty or unlinked.', style: TextStyle(color: skin.textSecondaryColor)))
                                : ListView.builder(
                                    itemCount: linkedFiles.length,
                                    itemBuilder: (context, index) {
                                      final file = linkedFiles[index];
                                      final name = file.path.split('/').last;
                                      return Card(
                                        color: skin.cardBackgroundColor,
                                        margin: const EdgeInsets.only(bottom: 8),
                                        child: ListTile(
                                          leading: Icon(Icons.insert_drive_file, color: skin.textSecondaryColor),
                                          title: Text(name, style: TextStyle(color: skin.textPrimaryColor, fontSize: 14)),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checking = false;
  String _statusMessage = 'System up to date.';
  static const MethodChannel _platform = MethodChannel('com.example.media_client_tv/installer');

  Future<void> _checkAndRequestStoragePermission() async {
    try {
      final bool hasPermission = await _platform.invokeMethod('checkStoragePermission') ?? true;
      if (!hasPermission) {
        MeshLogProvider().addLog("Storage permission not granted. Requesting MANAGE_EXTERNAL_STORAGE...");
        await _platform.invokeMethod('requestStoragePermission');
      }
    } catch (e) {
      MeshLogProvider().addLog("Failed to check/request storage permission: $e");
    }
  }

  void _showConfigureStorageDialog(BuildContext context, SkinConfig skin) async {
    await _checkAndRequestStoragePermission();

    final TextEditingController controller = TextEditingController(
      text: StorageManager().linkedFolderPath ?? '/sdcard/media-client-tv',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: skin.cardBackgroundColor,
          title: Text('Configure Storage Folder', style: TextStyle(color: skin.textPrimaryColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                style: TextStyle(color: skin.textPrimaryColor),
                decoration: InputDecoration(
                  hintText: '/sdcard/media-client-tv',
                  hintStyle: TextStyle(color: skin.textSecondaryColor),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: skin.primaryColor)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Note: Ensure "All Files Access" is enabled in system settings for full read/write access to shared storage paths.',
                style: TextStyle(color: skin.textSecondaryColor, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: skin.textSecondaryColor)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: skin.primaryColor),
              onPressed: () async {
                final newPath = controller.text.trim();
                if (newPath.isNotEmpty) {
                  await StorageManager().linkFolder(newPath);
                  await ToastHelper.showToast('Storage Folder Updated!');
                }
                Navigator.pop(context);
                setState(() {});
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleCheckForUpdate() async {
    setState(() {
      _checking = true;
      _statusMessage = 'Checking for updates...';
    });

    try {
      const owner = 'jch0029987-glitch';
      const repo = 'media-client-tv-';
      final url = Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest');
      
      final response = await http.get(url, headers: {'Accept': 'application/vnd.github.v3+json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String latestTag = data['tag_name'] ?? '';
        
        const currentVersion = 'v1.0.0-1';
        if (latestTag != currentVersion) {
          final assets = data['assets'] as List;
          final apkAsset = assets.firstWhere(
            (asset) => asset['name'].toString().endsWith('.apk'),
            orElse: () => null,
          );

          if (apkAsset != null) {
            setState(() => _statusMessage = 'New version $latestTag found. Downloading...');
            await _downloadAndInstall(apkAsset['browser_download_url']);
            return;
          }
        }
        setState(() => _statusMessage = 'You are running the latest version ($currentVersion).');
      } else {
        setState(() => _statusMessage = 'No release updates found on GitHub.');
      }
    } catch (e) {
      setState(() => _statusMessage = 'Update check failed: $e');
    } finally {
      setState(() => _checking = false);
    }
  }

  Future<void> _downloadAndInstall(String apkUrl) async {
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
          setState(() {
            _statusMessage = 'Downloading: ${(downloaded / contentLength * 100).toStringAsFixed(0)}%';
          });
        }
      });

      await sink.flush();
      await sink.close();
      client.close();

      await _platform.invokeMethod('installApk', {'path': filePath});
    } catch (e) {
      setState(() => _statusMessage = 'Download/Install failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([SkinManager(), SettingsManager(), StorageManager()]),
      builder: (context, _) {
        final skin = SkinManager().currentSkin;
        final customSettings = SettingsManager().customSettings;
        final linkedFolder = StorageManager().linkedFolderPath ?? 'Not set';

        return Padding(
          padding: EdgeInsets.all(skin.contentPadding),
          child: ListView(
            children: [
              Text(
                'Settings & System Updates',
                style: TextStyle(fontSize: skin.headerFontSize, fontWeight: FontWeight.bold, color: skin.textPrimaryColor),
              ),
              const SizedBox(height: 24),
              Card(
                color: skin.cardBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Linked Storage Path', style: TextStyle(color: skin.primaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: skin.primaryColor),
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Configure'),
                            onPressed: () => _showConfigureStorageDialog(context, skin),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(linkedFolder, style: TextStyle(color: skin.textPrimaryColor, fontFamily: 'monospace', fontSize: 13)),
                      const SizedBox(height: 8),
                      Text('Configure paths on-device here or remotely via your web mesh dashboard on port 9090.', style: TextStyle(color: skin.textSecondaryColor, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (customSettings.isNotEmpty) ...[
                Text('Dynamic Web Settings', style: TextStyle(color: skin.primaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                ...customSettings.entries.map((entry) => Card(
                  color: skin.cardBackgroundColor,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(entry.key, style: TextStyle(color: skin.textPrimaryColor, fontWeight: FontWeight.bold)),
                    subtitle: Text('${entry.value}', style: TextStyle(color: skin.textSecondaryColor)),
                  ),
                )),
                const Divider(height: 32),
              ],
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: skin.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                onPressed: _checking ? null : _handleCheckForUpdate,
                child: Text(_checking ? 'Checking...' : 'Check for App Updates', style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),
              Text(_statusMessage, style: TextStyle(color: skin.textSecondaryColor, fontSize: 14)),
            ],
          ),
        );
      },
    );
  }
}
