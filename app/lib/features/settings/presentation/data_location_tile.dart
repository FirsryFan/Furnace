/// 「数据 → 数据位置」一行：显示本机数据目录，点按复制路径。
///
/// 重构前"数据在哪"只在「关于」页里以说明文字出现；这一行把它放回数据分区，
/// 因为用户找数据位置时不会先想到"关于"。路径读取失败时禁用整行并退回说明
/// 文案（不显示一个假的路径）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/storage/app_storage.dart';
import '../../../l10n/app_localizations.dart';

/// 数据位置行（测试按 key 点它）。
const Key settingsDataLocationTileKey = Key('settings-data-location-tile');

class SettingsDataLocationTile extends StatefulWidget {
  const SettingsDataLocationTile({super.key});

  @override
  State<SettingsDataLocationTile> createState() =>
      _SettingsDataLocationTileState();
}

class _SettingsDataLocationTileState extends State<SettingsDataLocationTile> {
  /// 解析出的数据目录；null = 还在读或读失败。
  String? _path;

  /// 读失败的原因（保留下来，副标题据此决定是否禁用整行）。
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final directory = await AppStorage.supportDirectory();
      if (!mounted) {
        return;
      }
      setState(() {
        _path = directory.path;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error);
    }
  }

  Future<void> _copy() async {
    final path = _path;
    if (path == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: path));
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsDataLocationCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final path = _path;
    return ListTile(
      key: settingsDataLocationTileKey,
      leading: const Icon(Icons.folder_open_outlined),
      title: Text(l10n.settingsDataLocation),
      subtitle: Text(
        path ?? l10n.settingsDataLocationHint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.copy_all_outlined),
      enabled: path != null && _error == null,
      onTap: path == null ? null : _copy,
    );
  }
}
