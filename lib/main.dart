import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:serious_python/serious_python.dart';
import 'screens/player_screen.dart'; // Ensure you have this screen created separately

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
  bool _pythonInitialized = false;

  // Replace with your actual GitHub Pages raw URL
  final String masterIndexUrl = 'https://jch0029987-glitch.github.io/media-client-backend/addons.json';

  @override
  void initState() {
    super.initState();
    _initPythonAndFetch();
  }

  Future<void> _initPythonAndFetch() async {
    try {
      await SeriousPython.run("plugin_runner.py");
      setState(() => _pythonInitialized = true);
    } catch (e) {
      // Fallback gracefully if python runner asset fails initialization
    }
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
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse(catalogUrl));
      if (response.statusCode == 200) {
        String rawBody = response.body;

        // Process through embedded Python interpreter bridge if ready
        if (_pythonInitialized) {
          try {
            // serious_python v2.x invocation without unsupported arguments
            final String? pythonResponse = await SeriousPython.run(
              "plugin_runner.py",
            );
            if (pythonResponse != null) {
              final decodedPython = json.decode(pythonResponse);
              if (decodedPython['status'] == 'success') {
                setState(() {
                  _currentCatalogItems = decodedPython['items'] ?? [];
                  _isLoading = false;
                });
                return;
              }
            }
          } catch (_) {
            // Fallback to standard parsing on exception
          }
        }

        // Standard JSON fallback
        final data = json.decode(rawBody);
        setState(() {
          _currentCatalogItems = data['items'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
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
              // Provider Selector Chips for D-Pad Focus
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
                              final hasFocus = Focus.of(context).hasFocus;
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
                                        ? [
                                            const BoxShadow(
                                              color: Colors.blueAccent,
                                              blurRadius: 10,
                                              spreadRadius: 2,
                                            )
                                          ]
                                        : [],
                                  ),
                                  child: InkWell(
                                    onTap: () {
                                      if (item['type'] == 'http_stream') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => PlayerScreen(
                                              streamUrl: item['stream_url'],
                                              title: item['title'],
                                            ),
                                          ),
                                        );
                                      }
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
      const repo = 'media-client-tv';
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
