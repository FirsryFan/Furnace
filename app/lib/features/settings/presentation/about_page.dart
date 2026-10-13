import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/app_info.dart';
import '../../../l10n/app_localizations.dart';

/// Settings -> About.
///
/// Four facts a user cannot check anywhere else in the app: which build they are
/// running, where the data actually is, which two code paths reach the network,
/// and what this build knowingly does not do. The last one is deliberate - a
/// list of gaps is more useful than a list of promises, and every line here is
/// something the code or the docs already state.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAbout)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          _AboutCard(
            icon: Icons.info_outline,
            title: l10n.aboutVersionLabel,
            body: l10n.aboutVersionValue(kAppVersion, kAppBuildNumber),
          ),
          _DataDirCard(
            title: l10n.aboutDataTitle,
            body: l10n.aboutDataBody,
            dirLabel: l10n.aboutDataDirLabel,
          ),
          _AboutCard(
            icon: Icons.cloud_outlined,
            title: l10n.aboutNetworkTitle,
            body: l10n.aboutNetworkBody,
          ),
          _AboutCard(
            icon: Icons.construction_outlined,
            title: l10n.aboutGapsTitle,
            body: l10n.aboutGapsBody,
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// The data directory is a runtime value, so it is resolved here rather than
/// baked into a string constant - a path the user can copy and open is the
/// point of showing it at all.
class _DataDirCard extends StatelessWidget {
  const _DataDirCard({
    required this.title,
    required this.body,
    required this.dirLabel,
  });

  final String title;
  final String body;
  final String dirLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 10),
            Text(dirLabel, style: theme.textTheme.labelSmall),
            const SizedBox(height: 2),
            FutureBuilder<String>(
              future: getApplicationSupportDirectory()
                  .then((directory) => directory.path),
              builder: (context, snapshot) {
                final path = snapshot.data;
                if (path == null) {
                  return Text(
                    snapshot.hasError ? '—' : '…',
                    style: theme.textTheme.bodySmall,
                  );
                }
                return SelectableText(
                  path,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
