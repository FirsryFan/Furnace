import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:furnace/data/storage/app_storage.dart';

class GaokaoLibraryPage extends StatefulWidget {
  const GaokaoLibraryPage({super.key});
  @override
  State<GaokaoLibraryPage> createState() => _GaokaoLibraryPageState();
}

class _GaokaoLibraryPageState extends State<GaokaoLibraryPage> {
  List<_LibraryFile>? _files;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final root = await AppStorage.supportDirectory();
      final dir = root.path + Platform.pathSeparator + 'gaokao-library';
      final manifest = File(dir + Platform.pathSeparator + 'manifest.json');
      if (!await manifest.exists()) {
        setState(() => _error = '没有找到资源清单：' + manifest.path);
        return;
      }
      final decoded =
          jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
      final raw = (decoded['files'] as List?) ?? const [];
      final files = <_LibraryFile>[];
      for (final item in raw) {
        if (item is Map) {
          files.add(_LibraryFile.fromJson(item.cast<String, Object?>()));
        }
      }
      if (mounted) setState(() => _files = files);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '资源清单读取失败：' + error.toString());
    }
  }

  List<_LibraryFile> get _visible {
    final files = _files ?? const <_LibraryFile>[];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return files;
    return files
        .where((f) =>
            f.title.toLowerCase().contains(q) ||
            f.path.toLowerCase().contains(q) ||
            f.group.toLowerCase().contains(q))
        .toList(growable: false);
  }

  Future<void> _open(_LibraryFile file) async {
    if (!Platform.isWindows) return;
    await Process.run('explorer.exe', <String>[file.path]);
  }

  @override
  Widget build(BuildContext context) {
    final files = _visible;
    return Scaffold(
      appBar: AppBar(title: const Text('高考资源库')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜年份 / 卷别 / 文件名',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (_files != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    '共 ' +
                        _files!.length.toString() +
                        ' 个文件' +
                        (_query.trim().isEmpty
                            ? ''
                            : '，匹配 ' + files.length.toString() + ' 个'),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          Expanded(child: _body(files)),
        ],
      ),
    );
  }

  Widget _body(List<_LibraryFile> files) {
    if (_error != null)
      return Center(
          child:
              Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    if (_files == null) return const Center(child: CircularProgressIndicator());
    if (files.isEmpty) return const Center(child: Text('没有匹配的文件'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: files.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final f = files[index];
        return ListTile(
          leading: Icon(_iconFor(f.format)),
          title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              _groupLabel(f.group) +
                  ' · ' +
                  (f.year?.toString() ?? '年份未知') +
                  ' · ' +
                  f.kindLabel +
                  ' · ' +
                  f.format.toUpperCase() +
                  ' · ' +
                  _size(f.bytes),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _open(f),
        );
      },
    );
  }

  static String _groupLabel(String group) => switch (group) {
        'wechat' => '高考试题分析',
        'physics' => '物理真题',
        'chemistry' => '化学真题',
        'dsn' => '数学 DSN',
        _ => group,
      };

  static IconData _iconFor(String format) => switch (format) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'doc' || 'docx' => Icons.description_outlined,
        'ppt' || 'pptx' => Icons.slideshow_outlined,
        _ => Icons.insert_drive_file_outlined,
      };

  static String _size(int bytes) {
    if (bytes < 1024) return bytes.toString() + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toStringAsFixed(1) + ' KB';
    return (bytes / 1024 / 1024).toStringAsFixed(1) + ' MB';
  }
}

class _LibraryFile {
  const _LibraryFile(
      {required this.group,
      required this.subject,
      required this.year,
      required this.kind,
      required this.format,
      required this.title,
      required this.path,
      required this.bytes});
  factory _LibraryFile.fromJson(Map<String, Object?> json) => _LibraryFile(
        group: (json['group'] ?? '').toString(),
        subject: (json['subject'] ?? '').toString(),
        year: json['year'] is num ? (json['year'] as num).toInt() : null,
        kind: (json['kind'] ?? '').toString(),
        format: (json['format'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        path: (json['path'] ?? '').toString(),
        bytes: json['bytes'] is num ? (json['bytes'] as num).toInt() : 0,
      );
  final String group;
  final String subject;
  final int? year;
  final String kind;
  final String format;
  final String title;
  final String path;
  final int bytes;
  String get kindLabel => switch (kind) {
        'analysis' => '解析卷',
        'blank' => '空白卷',
        _ => '资料',
      };
}
