import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/skin_manager.dart';
import '../services/library_plugin_provider.dart';
import '../services/lua_jit_engine.dart';
import '../services/mesh_log_provider.dart';
import '../services/toast_helper.dart';
import 'player_screen.dart';

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
                                  onPressed: () => _selectCatalogProvider(index, addon['catalog_url']),
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
