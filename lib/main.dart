import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/airplay_system.dart';
import 'services/mesh_background_service.dart';
import 'services/mesh_log_provider.dart';
import 'services/storage_manager.dart';
import 'services/native_torrent_engine.dart';
import 'services/skin_manager.dart';
import 'services/settings_manager.dart';
import 'services/update_manager.dart';

import 'screens/main_screen.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Lock orientation and set immersive mode for Android TV
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    MeshLogProvider().addLog("App initialization started.");
    
    // Global error handler redirection to mesh logs
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      MeshLogProvider().addLog('Flutter Error: ${details.exception}');
    };

    // Load saved application state & preferences
    await SkinManager().loadSavedSkin();
    await SettingsManager().loadSavedSettings();
    await StorageManager().loadLinkedFolder(); 
    
    // Initialize native engines and background daemons
    NativeTorrentEngine().initialize();
    await MeshBackgroundService().startServer();

    AirPlaySystem().initializeNativeDaemon();
    await AirPlaySystem().startNativeServer(7000);

    // Run background OTA update check against repository releases
    await UpdateManager().initializeAndCheckForUpdates();

    MeshLogProvider().addLog("App fully booted up on Android TV.");
    runApp(const MediaClientApp());
  }, (error, stackTrace) {
    MeshLogProvider().addLog('Uncaught Zone Error: $error');
  });
}

class MediaClientApp extends StatelessWidget {
  const MediaClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SkinManager(),
      builder: (context, _) {
        final skin = SkinManager().currentSkin;
        return MaterialApp(
          title: 'Media Client TV',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: skin.backgroundColor,
            colorScheme: ColorScheme.dark(
              primary: skin.primaryColor,
              surface: skin.surfaceColor,
            ),
          ),
          home: const MainScreen(),
        );
      },
    );
  }
}
