import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/native_torrent_engine.dart';
import '../services/skin_manager.dart';
import '../services/mesh_log_provider.dart';
import '../services/toast_helper.dart';
import 'player_screen.dart';

class TorrentScreen extends StatefulWidget {
  const TorrentScreen({super.key});

  @override
  State<TorrentScreen> createState() => _TorrentScreenState();
}

class _TorrentScreenState extends State<TorrentScreen> {
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
