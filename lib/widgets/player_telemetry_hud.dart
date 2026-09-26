import 'package:flutter/material.dart';

class PlayerTelemetryHud extends StatelessWidget {
  final bool isVisible;
  final Map<String, dynamic> torrentStats;
  final Duration currentPosition;
  final Duration totalDuration;
  final double playbackSpeed;

  const PlayerTelemetryHud({
    super.key,
    required this.isVisible,
    required this.torrentStats,
    required this.currentPosition,
    required this.totalDuration,
    required this.playbackSpeed,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    final peers = torrentStats['peers'] ?? 0;
    final downloadSpeed = torrentStats['download_speed_kbps'] ?? 0;
    final progress = torrentStats['progress'] ?? 0.0;
    final endpoint = torrentStats['endpoint'] ?? 'http://127.0.0.1:8080/stream';

    return Positioned(
      top: 24,
      left: 24,
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'STATS FOR NERDS',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${playbackSpeed}x',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 16),
            _buildHudRow('Position / Length', '${_formatDuration(currentPosition)} / ${_formatDuration(totalDuration)}'),
            _buildHudRow('Engine Status', torrentStats['status'] ?? 'Streaming'),
            _buildHudRow('Download Speed', '$downloadSpeed KB/s'),
            _buildHudRow('Connected Peers', '$peers active'),
            _buildHudRow('Buffer Progress', '${progress.toStringAsFixed(1)}%'),
            _buildHudRow('Stream Endpoint', endpoint, isMonospace: true),
          ],
        ),
      ),
    );
  }

  Widget _buildHudRow(String label, String value, {bool isMonospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: isMonospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60).abs());
    final seconds = twoDigits(duration.inSeconds.remainder(60).abs());
    return duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
