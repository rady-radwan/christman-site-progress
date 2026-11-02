import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'library_store.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);
// ignore: unused_element
AppLifecycleListener? _lifecycle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Drone photos are large; give the decoder room to keep neighbours cached.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 768 << 20;
  final store = await LibraryStore.open();
  final cfg = await LibraryStore.readConfig();
  themeMode.value = switch (cfg['theme']) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };
  themeMode.addListener(() => LibraryStore.setConfig('theme', themeMode.value.name));
  // Coming back to the app: pick up anything colleagues added via Google Drive.
  _lifecycle = AppLifecycleListener(onResume: () => store.refreshFromDisk());
  runApp(ChangeNotifierProvider<LibraryStore>.value(
    value: store,
    child: const SiteProgressApp(),
  ));
}

class SiteProgressApp extends StatelessWidget {
  const SiteProgressApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Christman Site Progress',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        home: const HomeScreen(),
      ),
    );
  }
}
