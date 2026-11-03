import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../main.dart' show askForName;
import '../models.dart';
import 'settings_screen.dart';

/// Saves the person's name for this computer and announces it to the team.
Future<void> saveUserName(LibraryStore store, String name) async {
  final clean = name.trim();
  if (clean.isEmpty) return;
  final u = LibraryStore.user;
  LibraryStore.user = AppUser(id: u?.id ?? 'me', name: clean);
  await LibraryStore.setConfig('userName', clean);
  await store.heartbeat();
  store.touch();
}

/// Shows the first-run welcome once, on top of [child].
class StartupGate extends StatefulWidget {
  const StartupGate({super.key, required this.child});
  final Widget child;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  @override
  void initState() {
    super.initState();
    if (askForName) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        askForName = false;
        if (mounted) await showWelcome(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showWelcome(BuildContext context) async {
  final store = context.read<LibraryStore>();
  final nameC = TextEditingController(text: LibraryStore.user?.name ?? '');
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      Widget option(String value, IconData icon, String title, String text) => Card(
            child: InkWell(
              onTap: () {
                if (nameC.text.trim().isEmpty) return;
                Navigator.pop(ctx, value);
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(icon, size: 30, color: scheme.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(text, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          );
      return AlertDialog(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/logo.png', width: 36, height: 36),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Welcome to Christman Site Progress')),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Your name is shown to your team on every photo and change you make.'),
                const SizedBox(height: 12),
                TextField(
                  controller: nameC,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    hintText: 'e.g. Rady Radwan',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                Text('How will you use the app?', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                option('join', Icons.group_add_outlined, 'Join my team\'s shared library',
                    'A teammate shared the "Christman Site Progress" folder with you in Google Drive.'),
                option('share', Icons.cloud_upload_outlined, 'Start a shared library on Google Drive',
                    'Create the team library in your Google Drive, then invite your colleagues.'),
                option('local', Icons.computer_rounded, 'Just me, on this computer',
                    'You can move it to Google Drive later from Settings.'),
              ],
            ),
          ),
        ),
      );
    },
  );
  await saveUserName(store, nameC.text);
  if (!context.mounted) return;
  if (choice == 'join' || choice == 'share') {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }
}
