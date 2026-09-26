import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

// C Function Signatures for Native AirPlay Receiver Daemon
typedef StartAirPlayC = ffi.Int32 Function(ffi.Int32 port);
typedef StartAirPlayDart = int Function(int port);

typedef StopAirPlayC = ffi.Void Function();
typedef StopAirPlayDart = void Function();

enum AirPlayConnectionState { disconnected, discovering, connecting, connected, streaming, error }

class AirPlayDevice {
  final String name;
  final String ipAddress;
  final int port;

  AirPlayDevice({required this.name, required this.ipAddress, required this.port});
}

class AirPlaySystem extends ChangeNotifier {
  static final AirPlaySystem _instance = AirPlaySystem._internal();
  factory AirPlaySystem() => _instance;
  AirPlaySystem._internal();

  AirPlayConnectionState _state = AirPlayConnectionState.disconnected;
  AirPlayConnectionState get state => _state;

  String? _currentDevice;
  String? get currentDevice => _currentDevice;

  final List<AirPlayDevice> _discoveredDevices = [];
  List<AirPlayDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);

  // Native FFI Handles
  late final ffi.DynamicLibrary _lib;
  late final StartAirPlayDart _startServer;
  late final StopAirPlayDart _stopServer;
  bool _nativeInitialized = false;

  void initializeNativeDaemon() {
    if (_nativeInitialized) return;
    try {
      _lib = Platform.isAndroid
          ? ffi.DynamicLibrary.open('libairplay_daemon.so')
          : ffi.DynamicLibrary.process();

      _startServer = _lib
          .lookup<ffi.NativeFunction<StartAirPlayC>>('airplay_server_start')
          .asFunction();

      _stopServer = _lib
          .lookup<ffi.NativeFunction<StopAirPlayC>>('airplay_server_stop')
          .asFunction();

      _nativeInitialized = true;
      debugPrint('[AirPlaySystem] Native daemon loaded successfully.');
    } catch (e) {
      debugPrint('[AirPlaySystem] Failed to load libairplay_daemon.so: $e');
    }
  }

  Future<bool> startNativeServer(int port) async {
    if (!_nativeInitialized) initializeNativeDaemon();
    if (!_nativeInitialized) return false;
    
    try {
      final result = _startServer(port);
      if (result == 0) {
        debugPrint('[AirPlaySystem] Native receiver server successfully bound to port $port.');
        return true;
      }
    } catch (e) {
      debugPrint('[AirPlaySystem] Error starting native server: $e');
    }
    return false;
  }

  void stopNativeServer() {
    if (_nativeInitialized) {
      _stopServer();
      _setState(AirPlayConnectionState.disconnected);
      debugPrint('[AirPlaySystem] Native receiver server stopped.');
    }
  }

  Future<void> discoverDevices() async {
    if (_state == AirPlayConnectionState.discovering) return;
    
    _setState(AirPlayConnectionState.discovering);
    _discoveredDevices.clear();
    notifyListeners();

    final MDnsClient mdns = MDnsClient();
    try {
      await mdns.start();
      const serviceTypes = ['_airplay._tcp.local', '_raop._tcp.local'];

      for (final type in serviceTypes) {
        try {
          await for (final PtrResourceRecord ptr in mdns.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(type),
          )) {
            await for (final SrvResourceRecord srv in mdns.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            )) {
              await for (final IPAddressResourceRecord ip in mdns.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
              )) {
                final deviceName = ptr.domainName.replaceAll('.$type', '');
                final ipAddress = ip.address.address;

                if (!_discoveredDevices.any((d) => d.ipAddress == ipAddress || d.name == deviceName)) {
                  _discoveredDevices.add(
                    AirPlayDevice(
                      name: deviceName.isNotEmpty ? deviceName : srv.target,
                      ipAddress: ipAddress,
                      port: srv.port,
                    ),
                  );
                  notifyListeners();
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[AirPlaySystem] Notice during lookup for $type: $e');
        }
      }
    } catch (e) {
      debugPrint('[AirPlaySystem] Error running mDNS discovery: $e');
      _setState(AirPlayConnectionState.error);
    } finally {
      mdns.stop();
      if (_state == AirPlayConnectionState.discovering) {
        _setState(AirPlayConnectionState.disconnected);
      }
    }
  }

  Future<void> startSession(AirPlayDevice device) async {
    _currentDevice = device.name;
    _setState(AirPlayConnectionState.streaming);
  }

  Future<void> stopSession() async {
    _currentDevice = null;
    _setState(AirPlayConnectionState.disconnected);
  }

  void _setState(AirPlayConnectionState newState) {
    _state = newState;
    notifyListeners();
  }
}
