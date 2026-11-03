import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'appearance.dart';
import 'library_store.dart';
import 'models.dart';
import 'screens/home_screen.dart';
import 'screens/welcome.dart';

// ignore: unused_element
AppLifecycleListener? _lifecycle;

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// True on first run, before the person has told us their name.
bool askForName = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Drone photos are large; give the decoder room to keep neighbours cached.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 768 << 20;

  // Who is using this computer (shown on everything they add).
  final cfg = await LibraryStore.readConfig();
  var uid = cfg['userId'] as String?;
  if (uid == null) {
    uid = const Uuid().v4();
    await LibraryStore.setConfig('userId', uid);
  }
  final savedName = (cfg['userName'] as String?)?.trim();
  askForName = savedName == null || savedName.isEmpty;
  LibraryStore.user = AppUser(
    id: uid,
    name: askForName ? (Platform.environment['USERNAME'] ?? 'Me') : savedName!,
  );

  final store = await LibraryStore.open();
  await appearance.load();

  // Tell the user when teammates add or change things.
  store.onTeamActivity = (fresh) {
    final a = fresh.first;
    final more = fresh.length > 1 ? '  (+${fresh.length - 1} more)' : '';
    scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      content: Text('${a.userName} ${a.text}${a.projectName == null ? '' : ' · ${a.projectName}'}$more'),
    ));
  };

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
      scaffoldMessengerKey: scaffoldMessengerKey,
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
      home: const StartupGate(child: HomeScreen()),
    );
  }
}
