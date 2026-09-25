import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

enum AirPlayConnectionState { disconnected, discovering, connecting, connected, streaming, error }

class AirPlayDevice {
  final String name;
  final String ipAddress;
  final int port;

  AirPlayDevice({required this.name, required this.ipAddress, required this.port});
}

class AirPlaySystem extends ChangeNotifier {
  AirPlayConnectionState _state = AirPlayConnectionState.disconnected;
  AirPlayConnectionState get state => _state;

  String? _currentDevice;
  String? get currentDevice => _currentDevice;

  final List<AirPlayDevice> _discoveredDevices = [];
  List<AirPlayDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);

  // Discover available AirPlay devices (iPhones, Apple TVs, etc.) on the local network via mDNS
  Future<void> discoverDevices() async {
    if (_state == AirPlayConnectionState.discovering) return;
    
    _setState(AirPlayConnectionState.discovering);
    _discoveredDevices.clear();
    notifyListeners();

    final MDnsClient mdns = MDnsClient();
    try {
      await mdns.start();

      // Query both AirPlay video/mirroring and RAOP (AirPlay audio) service types
      const serviceTypes = ['_airplay._tcp.local', '_raop._tcp.local'];

      for (final type in serviceTypes) {
        try {
          await for (final PtrResourceRecord ptr in mdns.lookup<PtrResourceRecord>(
            ResourceRecordQuery.ptr(type),
          )) {
            await for (final SrvResourceRecord srv in mdns.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            )) {
              // Lookup corresponding IP address using modern address API
              await for (final IPAddressResourceRecord ip in mdns.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.address(srv.target),
              )) {
                final deviceName = ptr.domainName.replaceAll('.' + type, '');
                final ipAddress = ip.address.address;

                // Avoid duplicates based on target/IP
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
          debugPrint('Notice during lookup for $type: $e');
        }
      }
    } catch (e) {
      debugPrint('Error starting mDNS client: $e');
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
