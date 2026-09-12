import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_links.dart';
import '../core/theme.dart';
import 'widgets/common.dart';

/// Opens a link, telling the user plainly when the device has nothing that can
/// handle it instead of failing silently.
Future<void> openLink(BuildContext context, String url, {String? fallback}) async {
  final messenger = ScaffoldMessenger.of(context);
  Future<bool> tryOpen(String target) async {
    try {
      return await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }

  if (await tryOpen(url)) return;
  if (fallback != null && await tryOpen(fallback)) return;
  messenger.showSnackBar(
    SnackBar(content: Text('Could not open $url')),
  );
}

Future<void> shareApp() =>
    Share.share(AppLinks.shareMessage(), subject: '${AppLinks.appName} for Android');

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Shade.bg,
      appBar: AppBar(
        backgroundColor: Shade.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('About',
            style: TextStyle(color: Shade.text, fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 44),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Column(
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Shade.accent, Shade.accentSoft],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'C',
                    style: TextStyle(
                      color: Shade.bg,
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '${AppLinks.appName} · ${AppLinks.tagline}',
                  style: TextStyle(
                      color: Shade.text, fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text('Version ${AppLinks.version}',
                    style: TextStyle(color: Shade.textFaint, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              'CARTA turns any place on Earth into a print-ready poster. Every '
              'line is drawn on your device from OpenStreetMap data, so a place '
              'you have already captured can be restyled and exported with no '
              'connection at all.',
              style: TextStyle(color: Shade.textDim, fontSize: 13.5, height: 1.6),
            ),
          ),
          const SectionLabel('Support the app'),
          _LinkRow(
            icon: Icons.star_outline,
            label: 'Rate on Google Play',
            detail: 'Ratings are what get an independent app seen',
            onTap: () => openLink(context, AppLinks.playMarket,
                fallback: AppLinks.playListing),
          ),
          _LinkRow(
            icon: Icons.ios_share,
            label: 'Share CARTA',
            detail: 'Send the app to someone who would enjoy it',
            onTap: shareApp,
          ),
          const SectionLabel('Legal'),
          _LinkRow(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy policy',
            detail: 'What the app stores, and what it never sends',
            onTap: () => openLink(context, AppLinks.privacyPolicy),
          ),
          _LinkRow(
            icon: Icons.public,
            label: 'OpenStreetMap copyright',
            detail: 'Map data © OpenStreetMap contributors, ODbL',
            onTap: () => openLink(context, AppLinks.osmCopyright),
          ),
          _LinkRow(
            icon: Icons.mail_outline,
            label: 'Contact support',
            detail: AppLinks.supportEmail,
            onTap: () => openLink(context,
                'mailto:${AppLinks.supportEmail}?subject=${Uri.encodeComponent('${AppLinks.appName} ${AppLinks.version}')}'),
          ),
          const SectionLabel('Credits'),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 22, 10),
            child: Text(
              'Map data © OpenStreetMap contributors, licensed under the '
              'ODbL. Place search by Nominatim. Routing by the public OSRM '
              'instances run by FOSSGIS. Terrain from the public-domain '
              'Terrarium elevation tiles.\n\n'
              'Typefaces: Inter, Playfair Display, Cormorant Garamond, Cinzel, '
              'Oswald, Montserrat, Josefin Sans, Bebas Neue and Space Mono, all '
              'under the SIL Open Font License 1.1.',
              style: TextStyle(color: Shade.textFaint, fontSize: 12, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 13, 18, 13),
        child: Row(
          children: [
            Icon(icon, size: 19, color: Shade.textDim),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(color: Shade.text, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(detail,
                      style:
                          const TextStyle(color: Shade.textFaint, fontSize: 11.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Shade.textFaint),
          ],
        ),
      ),
    );
  }
}
