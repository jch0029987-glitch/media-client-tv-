import 'package:flutter/material.dart';
import '../services/airplay_system.dart';

class AirPlayDeviceSelector extends StatelessWidget {
  final AirPlaySystem airPlaySystem;

  const AirPlayDeviceSelector({super.key, required this.airPlaySystem});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: airPlaySystem,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(24.0),
          width: 500,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: Colors.grey[800]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'AirPlay Devices & iPhones',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (airPlaySystem.state == AirPlayConnectionState.discovering)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      onPressed: () => airPlaySystem.discoverDevices(),
                      tooltip: 'Scan for Devices',
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (airPlaySystem.discoveredDevices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32.0),
                  child: Center(
                    child: Text(
                      'No AirPlay receivers or iPhones found.\nMake sure Wi-Fi & AirPlay are enabled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 250,
                  child: ListView.builder(
                    itemCount: airPlaySystem.discoveredDevices.length,
                    itemBuilder: (context, index) {
                      final device = airPlaySystem.discoveredDevices[index];
                      final isSelected = airPlaySystem.currentDevice == device.name;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Focus(
                          child: Builder(
                            builder: (context) {
                              final focused = Focus.of(context).hasFocus;
                              return InkWell(
                                onTap: () => airPlaySystem.startSession(device),
                                borderRadius: BorderRadius.circular(8.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: focused
                                        ? Colors.blueAccent
                                        : (isSelected ? Colors.grey[800] : Colors.transparent),
                                    borderRadius: BorderRadius.circular(8.0),
                                    border: Border.all(
                                      color: focused ? Colors.white : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected ? Icons.cast_connected : Icons.phone_iphone,
                                        color: focused ? Colors.white : Colors.white70,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              device.name,
                                              style: TextStyle(
                                                color: focused ? Colors.white : Colors.white70,
                                                fontSize: 16,
                                                fontWeight: focused ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${device.ipAddress}:${device.port}',
                                              style: TextStyle(
                                                color: focused ? Colors.white70 : Colors.grey,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(Icons.check, color: Colors.greenAccent),
                                    ],
                                  ),
                                ),
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
        );
      },
    );
  }
}
