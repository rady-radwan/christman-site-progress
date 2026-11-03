import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'appearance.dart';
import 'library_store.dart';
import 'screens/home_screen.dart';

// ignore: unused_element
AppLifecycleListener? _lifecycle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Drone photos are large; give the decoder room to keep neighbours cached.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 768 << 20;
  final store = await LibraryStore.open();
  await appearance.load();
  // Coming back to the app: pick up anything colleagues added via Google Drive.
  _lifecycle = AppLifecycleListener(onResume: () => store.refreshFromDisk());
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider<LibraryStore>.value(value: store),
      ChangeNotifierProvider<AppAppearance>.value(value: appearance),
    ],
    child: const SiteProgressApp(),
  ));
}

class SiteProgressApp extends StatelessWidget {
  const SiteProgressApp({super.key});

  @override
  Widget build(BuildContext context) {
    final look = context.watch<AppAppearance>();
    return MaterialApp(
      title: 'Christman Site Progress',
      debugShowCheckedModeBanner: false,
      theme: look.light,
      darkTheme: look.dark,
      themeMode: look.mode,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(look.textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeScreen(),
    );
  }
}
