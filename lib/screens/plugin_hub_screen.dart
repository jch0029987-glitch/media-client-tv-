import 'package:flutter/material.dart';
import '../services/skin_manager.dart';
import '../services/library_plugin_provider.dart';
import '../services/storage_manager.dart';

class PluginHubScreen extends StatelessWidget {
  const PluginHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([SkinManager(), LibraryPluginProvider(), StorageManager()]),
      builder: (context, _) {
        final skin = SkinManager().currentSkin;
        final loadedPlugins = LibraryPluginProvider().loadedPlugins;
        final linkedFolder = StorageManager().linkedFolderPath;
        final linkedFiles = StorageManager().linkedFiles;

        return Padding(
          padding: EdgeInsets.all(skin.contentPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plugin & Mesh Storage Hub',
                style: TextStyle(fontSize: skin.headerFontSize, fontWeight: FontWeight.bold, color: skin.textPrimaryColor),
              ),
              const SizedBox(height: 8),
              Text(
                linkedFolder != null ? 'Linked Folder: $linkedFolder' : 'No storage folder linked yet.',
                style: TextStyle(fontSize: 14, color: skin.primaryColor),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Loaded Active Plugins (${loadedPlugins.length})', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: skin.textPrimaryColor)),
                          const SizedBox(height: 12),
                          Expanded(
                            child: loadedPlugins.isEmpty
                                ? Center(child: Text('No active plugins loaded.', style: TextStyle(color: skin.textSecondaryColor)))
                                : ListView.builder(
                                    itemCount: loadedPlugins.length,
                                    itemBuilder: (context, index) {
                                      final plugin = loadedPlugins[index];
                                      return Card(
                                        color: skin.cardBackgroundColor,
                                        margin: const EdgeInsets.only(bottom: 12),
                                        child: ListTile(
                                          leading: Icon(Icons.extension, color: skin.primaryColor),
                                          title: Text(plugin['name'] ?? 'Plugin', style: TextStyle(color: skin.textPrimaryColor, fontWeight: FontWeight.bold)),
                                          subtitle: Text('Deployed: ${plugin['time']}', style: TextStyle(color: skin.textSecondaryColor, fontSize: 12)),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Linked Directory Contents (${linkedFiles.length})', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: skin.textPrimaryColor)),
                          const SizedBox(height: 12),
                          Expanded(
                            child: linkedFiles.isEmpty
                                ? Center(child: Text('Folder is empty or unlinked.', style: TextStyle(color: skin.textSecondaryColor)))
                                : ListView.builder(
                                    itemCount: linkedFiles.length,
                                    itemBuilder: (context, index) {
                                      final file = linkedFiles[index];
                                      final name = file.path.split('/').last;
                                      return Card(
                                        color: skin.cardBackgroundColor,
                                        margin: const EdgeInsets.only(bottom: 8),
                                        child: ListTile(
                                          leading: Icon(Icons.insert_drive_file, color: skin.textSecondaryColor),
                                          title: Text(name, style: TextStyle(color: skin.textPrimaryColor, fontSize: 14)),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
