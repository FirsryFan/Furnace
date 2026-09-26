import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/theme_profile.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../application/appearance_providers.dart';

/// Folder inside the app support directory that holds imported background
/// images. The theme document stores a path relative to that directory.
const String _backgroundDirName = 'theme-backgrounds';

/// Editor for one theme document (spec §4).
///
/// Edits are kept in memory and only written when the user saves, so a
/// half-finished theme never becomes the active one. Saving over a built-in
/// theme stores a COPY (see ThemeRepository.save), which is why the page tells
/// the user when it is editing a built-in.
class ThemeEditorPage extends ConsumerStatefulWidget {
  const ThemeEditorPage({super.key, required this.themeId});

  final String themeId;

  @override
  ConsumerState<ThemeEditorPage> createState() => _ThemeEditorPageState();
}

class _ThemeEditorPageState extends ConsumerState<ThemeEditorPage> {
  ThemeProfileData? _data;
  bool _loading = true;
  bool _isBuiltin = false;

  static const List<({String label, Color color})> _palette = [
    (label: '绿', color: Color(0xFF2F6F4F)),
    (label: '蓝', color: Color(0xFF1565C0)),
    (label: '青', color: Color(0xFF00838F)),
    (label: '紫', color: Color(0xFF6A1B9A)),
    (label: '橙', color: Color(0xFFEF6C00)),
    (label: '红', color: Color(0xFFC62828)),
    (label: '灰', color: Color(0xFF546E7A)),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(themeRepositoryProvider);
    final row = await repo.getById(widget.themeId);
    if (!mounted) {
      return;
    }
    setState(() {
      _data = row == null ? ThemeProfileData.builtinDark : repo.dataOf(row);
      _isBuiltin = row?.isBuiltin == 1;
      _loading = false;
    });
  }

  /// Copies a chosen image into the app's own directory and points the theme at
  /// it.
  ///
  /// Copying rather than referencing the original path is deliberate: the user
  /// may move or delete the file they picked, and a theme that silently loses
  /// its background (or worse, breaks on another machine) is a bad trade for a
  /// few hundred kilobytes. The stored path stays relative, so the theme
  /// document itself never contains a machine-specific absolute path.
  Future<void> _pickBackgroundImage(ThemeProfileData data) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
      );
      if (picked.isEmpty) {
        return;
      }
      final source = picked.first;
      final bytes = await source.readAsBytes();
      if (bytes.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsThemeBackgroundFailed)),
        );
        return;
      }

      final dir = await getApplicationSupportDirectory();
      final target = Directory(p.join(dir.path, _backgroundDirName));
      await target.create(recursive: true);
      // A fresh name per import: overwriting the previous file would leave any
      // other theme pointing at a picture it never chose.
      final name = 'bg-${DateTime.now().millisecondsSinceEpoch}'
          '${p.extension(source.name).toLowerCase()}';
      await File(p.join(target.path, name)).writeAsBytes(bytes);

      if (!mounted) {
        return;
      }
      setState(() {
        // Use the CURRENT edit state, not the value captured when the card was
        // built: the user may have changed colours in the meantime, and saving
        // the stale snapshot would silently discard those edits.
        _data = (_data ?? data).copyWith(
          backgroundImagePath: p.join(_backgroundDirName, name),
        );
      });
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.settingsThemeBackgroundPick}: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _data;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsThemeEdit),
        actions: [
          IconButton(
            tooltip: l10n.commonSave,
            icon: const Icon(Icons.check),
            onPressed: data == null ? null : _save,
          ),
        ],
      ),
      body: _loading || data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                if (_isBuiltin)
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(l10n.settingsThemeBuiltinHint)),
                        ],
                      ),
                    ),
                  ),
                _Card(
                  icon: Icons.label_outline,
                  title: l10n.commonName,
                  child: TextFormField(
                    initialValue: data.name,
                    textInputAction: TextInputAction.done,
                    onChanged: (value) =>
                        setState(() => _data = data.copyWith(name: value)),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                _Card(
                  icon: Icons.brightness_6,
                  title: l10n.settingsThemeBrightness,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 'dark', label: Text(l10n.settingsThemeDark)),
                      ButtonSegment(value: 'light', label: Text(l10n.settingsThemeLight)),
                    ],
                    selected: {data.brightness},
                    onSelectionChanged: (selection) => setState(
                      () => _data = data.copyWith(brightness: selection.first),
                    ),
                  ),
                ),
                _Card(
                  icon: Icons.color_lens_outlined,
                  title: l10n.settingsThemePrimary,
                  child: _Swatches(
                    palette: _palette,
                    current: data.primary,
                    onPick: (color) => setState(
                      () => _data = data.copyWith(primary: _hex(color)),
                    ),
                  ),
                ),
                _Card(
                  icon: Icons.gradient_outlined,
                  title: l10n.settingsThemeBackground,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Swatches(
                        palette: [
                          (label: '默认', color: data.isDark
                              ? const Color(0xFF101211)
                              : const Color(0xFFFFFFFF)),
                          ..._palette,
                        ],
                        current: data.background ?? '',
                        onPick: (color) => setState(
                          () => _data = data.copyWith(background: _hex(color)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('${l10n.settingsThemeOpacity}: '
                          '${(data.backgroundOpacity * 100).round()}%'),
                      Slider(
                        value: data.backgroundOpacity,
                        divisions: 20,
                        onChanged: (value) => setState(
                          () => _data =
                              data.copyWith(backgroundOpacity: value),
                        ),
                      ),
                      const Divider(),
                      // The image fields existed in the theme document but had
                      // no way to be set and nothing rendered them. Both halves
                      // are wired here.
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data.backgroundImagePath == null
                                  ? l10n.settingsThemeBackgroundNone
                                  : l10n.settingsThemeBackgroundSet,
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.image_outlined),
                            label: Text(l10n.settingsThemeBackgroundPick),
                            onPressed: () => _pickBackgroundImage(data),
                          ),
                          if (data.backgroundImagePath != null)
                            IconButton(
                              tooltip: l10n.commonClear,
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(
                                () => _data = data.copyWith(
                                  clearBackgroundImage: true,
                                  backgroundBlur: 0,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (data.backgroundImagePath != null) ...[
                        Text('${l10n.settingsThemeBackgroundBlur}: '
                            '${data.backgroundBlur.round()}'),
                        Slider(
                          value: data.backgroundBlur.clamp(0, 30),
                          max: 30,
                          divisions: 30,
                          onChanged: (value) => setState(
                            () => _data = data.copyWith(backgroundBlur: value),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _Card(
                  icon: Icons.format_size,
                  title: l10n.settingsThemeScale,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${(data.scale * 100).round()}%'),
                      Slider(
                        value: ThemeScale.clamp(data.scale),
                        min: ThemeScale.min,
                        max: ThemeScale.max,
                        divisions: 14,
                        label: '${(data.scale * 100).round()}%',
                        onChanged: (value) => setState(
                          () => _data = data.copyWith(scale: value),
                        ),
                      ),
                      Text(
                        l10n.settingsThemeScaleHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _Card(
                  icon: Icons.animation,
                  title: l10n.settingsThemeAnimations,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: data.animations,
                    title: Text(data.animations
                        ? l10n.settingsThemeAnimationsOn
                        : l10n.settingsThemeAnimationsOff),
                    onChanged: (value) => setState(
                      () => _data = data.copyWith(animations: value),
                    ),
                  ),
                ),
                _Card(
                  icon: Icons.text_fields,
                  title: l10n.settingsThemeFonts,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          labelText: l10n.settingsThemeFontUi,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        controller:
                            TextEditingController(text: data.uiFont ?? ''),
                        onChanged: (value) => _data = data.copyWith(
                          uiFont: value.trim().isEmpty ? null : value.trim(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          labelText: l10n.settingsThemeFontEditor,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        controller:
                            TextEditingController(text: data.editorFont ?? ''),
                        onChanged: (value) => _data = data.copyWith(
                          editorFont:
                              value.trim().isEmpty ? null : value.trim(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.settingsThemeFontHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _save() async {
    final data = _data;
    if (data == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await saveTheme(ref, id: widget.themeId, data: data);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsThemeSaved)),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  static String _hex(Color color) {
    final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${value.substring(2).toUpperCase()}';
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.palette,
    required this.current,
    required this.onPick,
  });

  final List<({String label, Color color})> palette;
  final String current;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in palette)
          Tooltip(
            message: entry.label,
            child: InkWell(
              onTap: () => onPick(entry.color),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: entry.color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isSelected(entry.color)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerColor,
                    width: _isSelected(entry.color) ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isSelected(Color color) {
    if (current.isEmpty) {
      return false;
    }
    final parsed = ThemeProfileData.colorOf(current, fallback: color);
    return parsed.toARGB32() == color.toARGB32();
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
