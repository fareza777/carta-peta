import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_links.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../state/library_controller.dart';
import '../state/providers.dart';
import 'about_screen.dart';
import 'widgets/common.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int? _cacheBytes;
  int? _cacheEntries;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final repo = ref.read(mapRepositoryProvider);
    final bytes = await repo.cacheBytes();
    final entries = await repo.cacheEntries();
    if (!mounted) return;
    setState(() {
      _cacheBytes = bytes;
      _cacheEntries = entries;
    });
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    await ref.read(mapRepositoryProvider).clearCache();
    await _refresh();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Offline map data cleared')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryControllerProvider);
    final designs = library.designs.length;

    return Scaffold(
      backgroundColor: Shade.bg,
      appBar: AppBar(
        backgroundColor: Shade.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Settings',
            style: TextStyle(color: Shade.text, fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SectionLabel('Offline map data'),
          _Row(
            label: 'Stored captures',
            value: _cacheEntries == null ? '...' : '$_cacheEntries places',
          ),
          _Row(
            label: 'Disk used',
            value: _cacheBytes == null ? '...' : formatBytes(_cacheBytes!),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Text(
              'Downloaded map and terrain data lets you restyle and re-export a '
              'place with no connection. It is capped at about 260 MB and the '
              'oldest captures are dropped first.',
              style: TextStyle(color: Shade.textFaint, fontSize: 12, height: 1.45),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GhostButton(
              label: _busy ? 'Clearing...' : 'Clear offline data',
              icon: Icons.delete_outline,
              onPressed: _busy ? null : _clear,
            ),
          ),
          const SectionLabel('Library'),
          _Row(label: 'Saved designs', value: '$designs'),
          _Row(label: 'Favourites', value: '${library.favouriteCount}'),
          const SectionLabel('Language'),
          for (final language in AppLanguage.values)
            RadioListTile<AppLanguage>(
              value: language,
              // ignore: deprecated_member_use
              groupValue: ref.watch(languageProvider),
              // ignore: deprecated_member_use
              onChanged: (v) {
                if (v != null) ref.read(languageProvider.notifier).set(v);
              },
              activeColor: Shade.accent,
              title: Text(language.label,
                  style: const TextStyle(color: Shade.text, fontSize: 14.5)),
            ),
          const SectionLabel('Data & licences'),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              'Map data (c) OpenStreetMap contributors, licensed under the ODbL. '
              'That credit is rendered on every poster you export and cannot be '
              'switched off - it is the licence condition, and it is what makes '
              'the results safe to sell.\n\n'
              'Place search by Nominatim. Terrain from the public-domain '
              'Terrarium elevation tiles.\n\n'
              'Bundled typefaces: Inter, Playfair Display, Cormorant Garamond, '
              'Cinzel, Oswald, Montserrat, Josefin Sans, Bebas Neue and Space '
              'Mono, all under the SIL Open Font License 1.1.',
              style: TextStyle(color: Shade.textFaint, fontSize: 12, height: 1.55),
            ),
          ),
          const SectionLabel('About'),
          _TapRow(
            label: 'About ${AppLinks.appName}',
            value: 'v${AppLinks.version}',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
            ),
          ),
          _TapRow(
            label: 'Rate on Google Play',
            value: 'Thank you',
            onTap: () => openLink(context, AppLinks.playMarket,
                fallback: AppLinks.playListing),
          ),
          _TapRow(
            label: 'Share ${AppLinks.appName}',
            value: 'Send a link',
            onTap: shareApp,
          ),
          _TapRow(
            label: 'Privacy policy',
            value: 'Open',
            onTap: () => openLink(context, AppLinks.privacyPolicy),
          ),
        ],
      ),
    );
  }
}

class _TapRow extends StatelessWidget {
  const _TapRow({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 13, 14, 13),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: Shade.text, fontSize: 14.5)),
              ),
              Text(value,
                  style: const TextStyle(color: Shade.textDim, fontSize: 13.5)),
              const Icon(Icons.chevron_right, size: 18, color: Shade.textFaint),
            ],
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Shade.text, fontSize: 14.5)),
          ),
          Text(value, style: const TextStyle(color: Shade.textDim, fontSize: 13.5)),
        ],
      ),
    );
  }
}
