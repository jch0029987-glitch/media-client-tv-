import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MediaClientTvApp());
}

class MediaClientTvApp extends StatelessWidget {
  const MediaClientTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Media Client TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        primarySwatch: Colors.blue,
      ),
      home: const MainNavigatorScreen(),
    );
  }
}

class MainNavigatorScreen extends StatefulWidget {
  const MainNavigatorScreen({super.key});

  @override
  State<MainNavigatorScreen> createState() => _MainNavigatorScreenState();
}

class _MainNavigatorScreenState extends State<MainNavigatorScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const BrowseScreen(),
    const CustomSourceScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // D-Pad Friendly Side Navigation Rail
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            backgroundColor: const Color(0xFF161616),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home),
                label: Text('Browse'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.link),
                label: Text('Custom Source'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Colors.white24),
          
          // Active Screen Content
          Expanded(
            child: _screens[_selectedIndex],
          ),
        ],
      ),
    );
  }
}

/// 1. Browse Screen (Media Grid)
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final FocusNode _firstCardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstCardFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _firstCardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Media Stream Library',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.builder(
              itemCount: 8,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 16 / 9,
              ),
              itemBuilder: (context, index) {
                return FocusableCard(
                  focusNode: index == 0 ? _firstCardFocusNode : null,
                  title: 'Stream Item ${index + 1}',
                  onSelected: () {
                    // TODO: Trigger playback intent via local loopback proxy
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 2. Custom Source Screen (BYOS Configuration)
class CustomSourceScreen extends StatefulWidget {
  const CustomSourceScreen({super.key});

  @override
  State<CustomSourceScreen> createState() => _CustomSourceScreenState();
}

class _CustomSourceScreenState extends State<CustomSourceScreen> {
  final TextEditingController _urlController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bring Your Own Source (BYOS)',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            'Enter your custom API endpoint, manifest URL, or extension repository source below.',
            style: TextStyle(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Source URL / Endpoint',
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            onPressed: () {
              // TODO: Save custom source URL locally or pass to backend engine
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Source configuration saved.')),
              );
            },
            child: const Text('Save Configuration', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

/// 3. Settings Screen Placeholder
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(40.0),
      child: Text(
        'Settings',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }
}

/// Reusable focus-reactive Card for TV D-pad navigation
class FocusableCard extends StatefulWidget {
  final FocusNode? focusNode;
  final String title;
  final VoidCallback onSelected;

  const FocusableCard({
    super.key,
    this.focusNode,
    required this.title,
    required this.onSelected,
  });

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (hasFocus) => setState(() => _isFocused = hasFocus),
      onKey: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onSelected();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.blue.shade800 : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.transparent,
              width: 3,
            ),
            boxShadow: _isFocused
                ? [BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)]
                : [],
          ),
          child: Center(
            child: Text(
              widget.title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: _isFocused ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
