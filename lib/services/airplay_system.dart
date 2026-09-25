import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

enum AirPlayConnectionState { disconnected, discovering, connecting, connected, streaming, error }

class AirPlaySystem extends ChangeNotifier {
  AirPlayConnectionState _state = AirPlayConnectionState.disconnected;
  AirPlayConnectionState get state => _state;

  String? _currentDevice;
  String? get currentDevice => _currentDevice;

  final List<String> _discoveredDevices = [];
  List<String> get discoveredDevices => List.unmodifiable(_discoveredDevices);

  // Discover available AirPlay devices on the local network via mDNS
  Future<void> discoverDevices() async {
    _setState(AirPlayConnectionState.discovering);
    _discoveredDevices.clear();
    
    final MDnsClient mdns = MDnsClient();
    try {
      await mdns.start();

      // Query PTR records for the standard AirPlay service type
      await for (final PtrResourceRecord ptr in mdns.lookup<PtrResourceRecord>(
        ResourceRecordQuery.ptr(name: '_airplay._tcp.local'),
      )) {
        await for (final SrvResourceRecord srv in mdns.lookup<SrvResourceRecord>(
          ResourceRecordQuery.srv(name: ptr.domainName),
        )) {
          if (!_discoveredDevices.contains(srv.target)) {
            _discoveredDevices.add(srv.target);
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('Error during mDNS discovery: $e');
      _setState(AirPlayConnectionState.error);
      return;
    } finally {
      mdns.stop();
    }

    _setState(AirPlayConnectionState.disconnected);
  }

  // Connect or start session with a target device
  Future<void> startSession(String deviceName) async {
    _currentDevice = deviceName;
    _setState(AirPlayConnectionState.streaming);
    // TODO: Implement RTSP/RAOP protocol handshake here
  }

  // Tear down session and close sockets
  Future<void> stopSession() async {
    _currentDevice = null;
    _setState(AirPlayConnectionState.disconnected);
  }

  void _setState(AirPlayConnectionState newState) {
    _state = newState;
    notifyListeners();
  }
}
