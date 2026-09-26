import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart' as xml;

import 'screens/player_screen.dart';
import 'services/airplay_system.dart';
import 'widgets/airplay_device_selector.dart';

import 'services/toast_helper.dart';
import 'services/mesh_log_provider.dart';
import 'services/storage_manager.dart';
import 'services/lua_jit_engine.dart';
import 'services/native_torrent_engine.dart';
import 'services/skin_manager.dart';
import 'services/settings_manager.dart';
import 'services/library_plugin_provider.dart';
import 'services/mesh_background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MeshLogProvider().addLog("App initialization started.");
  
  await SkinManager().loadSavedSkin();
  await SettingsManager().loadSavedSettings();
  await StorageManager().loadLinkedFolder(); 
  
  NativeTorrentEngine().initialize();
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
    const TorrentHubScreen(),
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
                    label: Text('Plugins'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.download),
                    label: Text('Torrent Hub'),
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

class TorrentHubScreen extends StatefulWidget {
  const TorrentHubScreen({super.key});

  @override
  State<TorrentHubScreen> createState() => _TorrentHubScreenState();
}

class _TorrentHubScreenState extends State<TorrentHubScreen> {
  final TextEditingController _magnetController = TextEditingController();
  Map<String, dynamic> _stats = {};
  Timer? _pollTimer;
  bool _isStreaming = false;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollStats());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _magnetController.dispose();
    super.dispose();
  }

  void _pollStats() {
    final stats = NativeTorrentEngine().getStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isStreaming = stats['status'] == 'streaming' || stats['active'] == true;
      });
    }
  }

  Future<void> _startStream() async {
    final magnet = _magnetController.text.trim();
    if (magnet.isEmpty) {
      await ToastHelper.showToast('Please enter a valid magnet link');
      return;
    }

    final appDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final saveDir = '${appDir.path}/torrents';
    await Directory(saveDir).create(recursive: true);

    MeshLogProvider().addLog("Starting native torrent stream from UI...");
    final resultStr = NativeTorrentEngine().startTorrentStream(magnet, saveDir, port: 8080);
    try {
      final res = json.decode(resultStr);
      if (res['status'] == 'success' || res['stream_url'] != null) {
        await ToastHelper.showToast('Torrent streaming initialized!');
        final streamUrl = res['stream_url'] ?? 'http://127.0.0.1:8080/stream';
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlayerScreen(streamUrl: streamUrl, title: 'Torrent Stream'),
          ),
        );
      } else {
        await ToastHelper.showToast('Failed to start torrent stream');
      }
    } catch (e) {
      MeshLogProvider().addLog("Torrent start error: $e");
    }
  }

  void _stopStream() {
    NativeTorrentEngine().stopTorrentStream();
    ToastHelper.showToast('Torrent stream stopped');
    _pollStats();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SkinManager(),
      builder: (context, _) {
        final skin = SkinManager().currentSkin;

        return Padding(
          padding: EdgeInsets.all(skin.contentPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Native C BitTorrent Engine Hub',
                style: TextStyle(fontSize: skin.headerFontSize, fontWeight: FontWeight.bold, color: skin.textPrimaryColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Stream media directly via magnet links using the zero-copy C libtorrent backend.',
                style: TextStyle(fontSize: 14, color: skin.textSecondaryColor),
              ),
              const SizedBox(height: 24),
              Card(
                color: skin.cardBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Magnet Link Input', style: TextStyle(color: skin.primaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _magnetController,
                        style: TextStyle(color: skin.textPrimaryColor, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'magnet:?xt=urn:btih:...',
                          hintStyle: TextStyle(color: skin.textSecondaryColor),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: skin.primaryColor)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: skin.primaryColor),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start Stream'),
                            onPressed: _startStream,
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop Engine'),
                            onPressed: _stopStream,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Live Engine Telemetry', style: TextStyle(color: skin.primaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  color: skin.cardBackgroundColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ListView(
                      children: [
                        ListTile(
                          title: const Text('Engine Status'),
                          trailing: Text(_isStreaming ? 'STREAMING' : 'IDLE', style: TextStyle(color: _isStreaming ? Colors.greenAccent : skin.textSecondaryColor, fontWeight: FontWeight.bold)),
                        ),
                        const Divider(color: Colors.white24),
                        ListTile(
                          title: const Text('Connected Peers'),
                          trailing: Text('${_stats['peers'] ?? 0}'),
                        ),
                        const Divider(color: Colors.white24),
                        ListTile(
                          title: const Text('Download Speed'),
                          trailing: Text('${_stats['download_speed_kbps'] ?? 0} KB/s'),
                        ),
                        const Divider(color: Colors.white24),
                        ListTile(
                          title: const Text('Buffer Progress'),
                          trailing: Text('${(_stats['progress'] ?? 0.0).toStringAsFixed(1)}%'),
                        ),
                        const Divider(color: Colors.white24),
                        ListTile(
                          title: const Text('Local Stream Endpoint'),
                          trailing: Text('${_stats['endpoint'] ?? 'http://127.0.0.1:8080/stream'}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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

      if (_pluginProvider.loadedPlugins.isNotEmpty) {
        _selectCatalogProvider(0, 'local://lua_plugin');
      } else if (_addons.isNotEmpty) {
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

    MeshLogProvider().addLog("Action Triggered: [$action] on item: $itemTitle (ID: $itemId)");
    await ToastHelper.showToast('Executing: $itemTitle');

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
          MeshLogProvider().addLog("Successfully loaded directory action: $action");
        } catch (e) {
          MeshLogProvider().addLog("Failed to parse directory action result: $e");
          await ToastHelper.showToast('Error loading directory');
          setState(() => _isLoading = false);
        }
      } else {
        MeshLogProvider().addLog("No active Lua plugin found for action: $action");
        setState(() => _isLoading = false);
      }
    } else {
      final url = item['stream_url'] ?? item['url'] ?? '';
      if (url.isNotEmpty) {
        MeshLogProvider().addLog("Opening player for stream URL: $url");
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
              MeshLogProvider().addLog("Successfully resolved stream URL for ID: $itemId");
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(streamUrl: streamUrl, title: itemTitle),
                ),
              );
            } else {
              MeshLogProvider().addLog("Resolved stream URL was empty for item ID: $itemId");
              await ToastHelper.showToast('Stream resolution failed');
            }
          } catch (e) {
            MeshLogProvider().addLog("Failed to resolve stream JSON: $e");
            await ToastHelper.showToast('Stream resolution error');
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
