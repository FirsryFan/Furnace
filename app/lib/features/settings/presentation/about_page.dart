import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_info.dart';
import '../../../l10n/app_localizations.dart';

/// Settings -> About.
///
/// Three facts a user actually needs: which version they are running, that the
/// project is open source and under which licence, and where to read the source
/// or report a problem.
///
/// What used to be here is gone rather than moved. The data directory now lives
/// in Settings -> Data (where a user looks for it), and the network-egress and
/// "known gaps" cards were developer bookkeeping: both ended by pointing at the
/// developer docs, which is not what a user opens About for.
///
/// The app has no `url_launcher` dependency, so links are shown as copyable text
/// (the same choice the 组卷网 entry makes) instead of promising a browser.
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
            body: kAppVersion,
          ),
          _LicenseCard(l10n: l10n),
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

/// Open source + licence + the links a user may want to follow.
class _LicenseCard extends StatelessWidget {
  const _LicenseCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.code,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.aboutLicenseTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.aboutLicenseBody,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 4),
            const Divider(height: 16),
            _AboutLinkRow(
              icon: Icons.source_outlined,
              label: l10n.aboutRepoLabel,
              url: kAppRepoUrl,
            ),
            _AboutLinkRow(
              icon: Icons.bug_report_outlined,
              label: l10n.aboutIssuesLabel,
              url: kAppIssuesUrl,
            ),
            _AboutLinkRow(
              icon: Icons.description_outlined,
              label: l10n.aboutViewLicenses,
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Furnace',
                applicationVersion: kAppVersion,
                applicationLegalese: '$kAppLicenseName License',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One link row: a copyable URL, or an action (the third-party licence list).
class _AboutLinkRow extends StatelessWidget {
  const _AboutLinkRow({
    required this.icon,
    required this.label,
    this.url,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// When set, tapping copies it; the row then shows the URL itself.
  final String? url;

  /// Used when there is no URL to copy (opens another page in the app).
  final VoidCallback? onTap;

  Future<void> _copy(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: url!));
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.aboutLinkCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = url;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: Icon(icon, size: 20),
      title: Text(label, style: theme.textTheme.bodyMedium),
      subtitle: target == null
          ? null
          : Text(
              target,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Icon(
        target == null ? Icons.chevron_right : Icons.copy_all_outlined,
        size: 18,
      ),
      onTap: target == null ? onTap : () => _copy(context),
    );
  }
}
