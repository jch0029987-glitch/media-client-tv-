import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/mesh_log_provider.dart';
import '../services/skin_manager.dart';
import '../services/toast_helper.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _hasError = false;
  String _errorMessage = '';
  
  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    MeshLogProvider().addLog("Initializing video player for URL: ${widget.streamUrl}");
    
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl));

    try {
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _controller.play();
        _controller.setLooping(false);
      }
    } catch (e) {
      MeshLogProvider().addLog("Video player initialization error: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }

    _controller.addListener(() {
      if (_controller.value.hasError) {
        MeshLogProvider().addLog("Playback Error: ${_controller.value.errorDescription}");
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = _controller.value.errorDescription ?? 'Unknown playback error';
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  void _seekRelative(Duration offset) {
    final currentPosition = _controller.value.position;
    final targetPosition = currentPosition + offset;
    _controller.seekTo(targetPosition);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SkinManager(),
      builder: (context, _) {
        final skin = SkinManager().currentSkin;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.space ||
                    event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
                  _togglePlayPause();
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _seekRelative(const Duration(seconds: -10));
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _seekRelative(const Duration(seconds: 10));
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack) {
                  Navigator.pop(context);
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Stack(
              children: [
                Center(
                  child: _hasError
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              'Playback Failed',
                              style: TextStyle(color: skin.textPrimaryColor, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32.0),
                              child: Text(
                                _errorMessage,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: skin.textSecondaryColor, fontSize: 13),
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: skin.primaryColor),
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Go Back'),
                            ),
                          ],
                        )
                      : _isInitialized
                          ? AspectRatio(
                              aspectRatio: _controller.value.aspectRatio,
                              child: VideoPlayer(_controller),
                            )
                          : CircularProgressIndicator(color: skin.primaryColor),
                ),

                // Overlay Controls Header & Footer
                if (_showControls && _isInitialized)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.7),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withOpacity(0.8),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  widget.title,
                                  style: TextStyle(color: skin.textPrimaryColor, fontSize: 22, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                VideoProgressIndicator(
                                  _controller,
                                  allowScrubbing: true,
                                  colors: VideoProgressColors(
                                    playedColor: skin.primaryColor,
                                    bufferedColor: Colors.white24,
                                    backgroundColor: Colors.white10,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                            color: Colors.white,
                                            size: 32,
                                          ),
                                          onPressed: _togglePlayPause,
                                        ),
                                        const SizedBox(width: 16),
                                        Text(
                                          '${_formatDuration(_controller.value.position)} / ${_formatDuration(_controller.value.duration)}',
                                          style: TextStyle(color: skin.textPrimaryColor, fontSize: 14),
                                        ),
                                      ],
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(backgroundColor: skin.primaryColor),
                                      icon: const Icon(Icons.cast),
                                      label: const Text('Cast to AirPlay'),
                                      onPressed: () async {
                                        await ToastHelper.showToast('AirPlay casting target selector invoked');
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
