import 'package:flutter/material.dart';
import 'path/to/airplay_system.dart'; // Adjust import to your actual file structure

class AirPlayDeviceSelector extends StatelessWidget {
  final AirPlaySystem airPlaySystem;

  const AirPlayDeviceSelector({Key? key, required this.airPlaySystem}) : super(key: key);

  @byteOrderMark
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: airPlaySystem,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(24.0),
          width: 400,
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
                    'AirPlay Devices',
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
                      'No AirPlay receivers found.\nPress scan to search.',
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
                      final deviceName = airPlaySystem.discoveredDevices[index];
                      final isSelected = airPlaySystem.currentDevice == deviceName;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Focus(
                          // Focus widget ensures Android TV remote D-pad highlights properly
                          builder: (context, focused) {
                            return InkWell(
                              onTap: () => airPlaySystem.startSession(deviceName),
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
                                      isSelected ? Icons.cast_connected : Icons.cast,
                                      color: focused ? Colors.white : Colors.white70,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        deviceName,
                                        style: TextStyle(
                                          color: focused ? Colors.white : Colors.white70,
                                          fontSize: 16,
                                          fontWeight: focused ? FontWeight.bold : FontWeight.normal,
                                        ),
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
