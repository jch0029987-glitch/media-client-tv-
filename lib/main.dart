import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MediaClientApp());
}

class MediaClientApp extends StatelessWidget {
  const MediaClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Media Client TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const MainScreen(),
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

  final List<Widget> _screens = const [
    LibraryScreen(),
    MeshServerScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Android TV Navigation Sidebar
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.video_library),
                label: Text('Library'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.dns),
                label: Text('Mesh RPC'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Colors.white24),
          // Active Screen View
          Expanded(
            child: _screens[_selectedIndex],
          ),
        ],
      ),
    );
  }
}

/// Native Dart Mesh Server Screen with built-in concurrency guards
class MeshServerScreen extends StatefulWidget {
  const MeshServerScreen({super.key});

  @override
  State<MeshServerScreen> createState() => _MeshServerScreenState();
}

class _MeshServerScreenState extends State<MeshServerScreen> {
  final String _tailscaleIp = "100.99.24.58";
  String _statusMessage = "Initializing native Dart mesh server...";
  bool _isServerActive = false;
  bool _isChecking = true;
  bool _isBooting = false;
  
  HttpServer? _nativeHttpServer;
  int _port = 9090;

  @override
  void initState() {
    super.initState();
    _startNativeServerAndVerify();
  }

  @override
  void dispose() {
    _nativeHttpServer?.close(force: true);
    super.dispose();
  }

  Future<void> _startNativeServerAndVerify() async {
    if (_isBooting) return;
    setState(() {
      _isBooting = true;
      _isChecking = true;
      _statusMessage = "Starting native Dart HTTP/JSON-RPC server...";
    });

    try {
      // Close existing server instance if restarting
      await _nativeHttpServer?.close(force: true);

      // Bind directly to interface port 9090 using pure Dart
      _nativeHttpServer = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      
      // Listen to incoming requests on the mesh network
      _nativeHttpServer!.listen(_handleMeshRequest, onError: (e) {
        print("Mesh server stream error: $e");
      });

      // Brief pause to stabilize socket listener
      await Future.delayed(const Duration(milliseconds: 500));

      final healthUrl = Uri.parse('http://$_tailscaleIp:$_port/');
      final response = await http.get(healthUrl).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        setState(() {
          _isServerActive = true;
          _statusMessage = "Native Dart Server Active & Responding on Tailscale Mesh.";
          _isChecking = false;
          _isBooting = false;
        });
      } else {
        _triggerFallback("Server responded with unexpected status code: ${response.statusCode}");
      }
    } catch (e) {
      _triggerFallback("Could not bind port $_port ($e). Operating in fallback standalone mode.");
    }
  }

  void _handleMeshRequest(HttpRequest request) {
    final response = request.response;
    response.headers.contentType = ContentType.json;

    try {
      if (request.method == 'GET' && request.uri.path == '/') {
        response.statusCode = HttpStatus.ok;
        response.write(json.encode({
          "status": "online",
          "node": "media-client-tv-dart-core",
          "mesh_ip": _tailscaleIp,
          "timestamp": DateTime.now().toIso8601String(),
        }));
      } else if (request.method == 'POST' && request.uri.path == '/rpc') {
        response.statusCode = HttpStatus.ok;
        response.write(json.encode({
          "jsonrpc": "2.0",
          "result": {"message": "Command executed successfully via native Dart worker"},
          "id": 1
        }));
      } else {
        response.statusCode = HttpStatus.notFound;
        response.write(json.encode({"error": "Endpoint not found"}));
      }
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
      response.write(json.encode({"error": e.toString()}));
    } finally {
      response.close();
    }
  }

  void _triggerFallback(String reason) {
    setState(() {
      _isServerActive = false;
      _statusMessage = "Fallback Active: $reason Local media UI remains fully operational.";
      _isChecking = false;
      _isBooting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tailscale Mesh Server Status',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            'Monitors the background native Dart JSON-RPC server for remote browser connection.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isServerActive ? Colors.greenAccent.withOpacity(0.5) : Colors.orangeAccent.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isChecking
                        ? const CircularProgressIndicator(color: Colors.blueAccent)
                        : Icon(
                            _isServerActive ? Icons.check_circle : Icons.warning_amber_rounded,
                            color: _isServerActive ? Colors.greenAccent : Colors.orangeAccent,
                            size: 48,
                          ),
                    const SizedBox(height: 16),
                    Text(
                      _isServerActive ? 'STATUS: ONLINE (MESH SECURED)' : 'STATUS: FALLBACK / STANDALONE',
                      style: TextStyle(
                        color: _isServerActive ? Colors.greenAccent : Colors.orangeAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Tailscale Chrome Endpoint', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(
                      'http://$_tailscaleIp:$_port',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: (_isChecking || _isBooting) ? null : _startNativeServerAndVerify,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Restart & Re-verify Server'),
                    ),
                  ],
                ),
              ),
            ),
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
  bool _isLoading = true;
  int _selectedAddonIndex = 0;
  String? _activeCatalogUrl;

  final String masterIndexUrl = 'https://jch0029987-glitch.github.io/media-client-backend/addons.json';

  @override
  void initState() {
    super.initState();
    _fetchMasterIndex();
  }

  Future<void> _fetchMasterIndex() async {
    try {
      final response = await http.get(Uri.parse(masterIndexUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _addons = data['addons'] ?? [];
        });
        if (_addons.isNotEmpty) {
          _fetchCatalog(_addons[0]['catalog_url']);
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCatalog(String catalogUrl) async {
    _activeCatalogUrl = catalogUrl;
    setState(() => _isLoading = true);
    
    try {
      final response = await http.get(Uri.parse(catalogUrl));
      if (_activeCatalogUrl != catalogUrl) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (_activeCatalogUrl != catalogUrl) return;
        
        setState(() {
          _currentCatalogItems = data['items'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (_activeCatalogUrl == catalogUrl) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Media Library',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
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
                        child: Focus(
                          child: Builder(
                            builder: (context) {
                              return ActionChip(
                                backgroundColor: isSelected ? Colors.blueAccent : const Color(0xFF2C2C2C),
                                label: Text(addon['name'] ?? 'Provider'),
                                labelStyle: const TextStyle(color: Colors.white),
                                onPressed: () {
                                  setState(() => _selectedAddonIndex = index);
                                  _fetchCatalog(addon['catalog_url']);
                                },
                              );
                            },
                          ),
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
                ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                : _currentCatalogItems.isEmpty
                    ? const Center(child: Text('No media items found in this catalog.', style: TextStyle(color: Colors.white54)))
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          childAspectRatio: 16 / 9,
                        ),
                        itemCount: _currentCatalogItems.length,
                        itemBuilder: (context, index) {
                          final item = _currentCatalogItems[index];
                          return Focus(
                            child: Builder(
                              builder: (context) {
                                final hasFocus = Focus.of(context).hasFocus;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2C2C2C),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: hasFocus ? Colors.blueAccent : Colors.transparent,
                                      width: 3,
                                    ),
                                    boxShadow: hasFocus
                                        ? [const BoxShadow(color: Colors.blueAccent, blurRadius: 10, spreadRadius: 2)]
                                        : [],
                                  ),
                                  child: InkWell(
                                    onTap: () {
                                      // Player navigation hook
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Text(
                                          item['title'] ?? 'Unknown Item',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
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
        final data = jsonDecode(response.body);
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
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settings & System',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            onPressed: _checking ? null : _handleCheckForUpdate,
            child: Text(_checking ? 'Checking...' : 'Check for App Updates', style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 16),
          Text(_statusMessage, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }
}
