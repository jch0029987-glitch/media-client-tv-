import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;

  const PlayerScreen({super.key, required this.streamUrl, required this.title});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl))
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
        _controller.play();
      });
    
    // Listen to updates to refresh UI for the progress bar
    _controller.addListener(_updateState);
  }

  void _updateState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_updateState);
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _isInitialized
            ? GestureDetector(
                onTap: () => setState(() => _showControls = !_showControls),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Video View
                    AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),

                    // Controls Overlay
                    if (_showControls) ...[
                      // Semi-transparent backdrop
                      Container(color: Colors.black.withOpacity(0.4)),

                      // Top Bar (Title & Back Button)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: AppBar(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          leading: IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          title: Text(
                            widget.title,
                            style: const TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        ),
                      ),

                      // Center Play/Pause Toggle
                      IconButton(
                        iconSize: 64,
                        color: Colors.white,
                        icon: Icon(
                          _controller.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                        ),
                        onPressed: () {
                          setState(() {
                            _controller.value.isPlaying
                                ? _controller.pause()
                                : _controller.play();
                          });
                        },
                      ),

                      // Bottom Bar (Progress Slider & Timestamps)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: Colors.black54,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _formatDuration(_controller.value.position),
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _controller.value.position.inMilliseconds.toDouble(),
                                      min: 0.0,
                                      max: _controller.value.duration.inMilliseconds.toDouble() > 0
                                          ? _controller.value.duration.inMilliseconds.toDouble()
                                          : 1.0,
                                      activeColor: Colors.blueAccent,
                                      inactiveColor: Colors.white24,
                                      onChanged: (value) {
                                        _controller.seekTo(Duration(milliseconds: value.toInt()));
                                      },
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(_controller.value.duration),
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              )
            : const CircularProgressIndicator(color: Colors.blueAccent),
      ),
    );
  }
}
