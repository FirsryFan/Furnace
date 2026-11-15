/// `content_refs` 仓储（schema v47，2026-11-15）。
///
/// 契约：`INTEGRATION-CONTRACT-2026-11-15.md` §2.2 / §2.3 / §2.4。这一层只做
/// 「内容 id ↔ 产品对象」的引用读写，**不复制正文**：没有题干/答案/解析字段，
/// `metadata_json` 只放引用摘要。
///
/// 三条规则：
///  * 唯一键 = `(content_id, object_type, object_id, role)`；同一条引用写两次
///    是一行，不是两行；
///  * 内容换版（`content_version` / `content_hash` 变）**原地更新**，旧 hash 进
///    `metadata_json.previous_hash`，不新建第二张版本表；
///  * `content_version` 与 `content_hash` 要么同时给、要么都不给（契约 §2.3
///    第 1 条：单独一个视为脏数据）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/services/content/content_ref_vocab.dart';
import '../database/database.dart';
import '../ids.dart';

class ContentRefRepository {
  ContentRefRepository(this._db);

  final AppDatabase _db;

  /// 写一条引用：不存在就插入，存在就原地更新（hash 变化时记 previous_hash）。
  ///
  /// [contentVersion] / [contentHash] 成对校验；[metadata] 会与已有 metadata
  /// 合并（新值覆盖同名键），正文永远不进这里。
  Future<ContentRefRow> upsert({
    required String contentId,
    required String objectType,
    required String objectId,
    required String role,
    int? contentVersion,
    String? contentHash,
    String? subject,
    Map<String, Object?>? metadata,
  }) async {
    _validateContentId(contentId);
    _validateObjectType(objectType);
    _validateRole(role);
    if ((contentVersion == null) != (contentHash == null)) {
      throw ArgumentError(
        'content_version 与 content_hash 必须成对提供：'
        'contentId=$contentId version=$contentVersion hash=$contentHash',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;

    return _db.transaction(() async {
      final existing = await _find(
        contentId: contentId,
        objectType: objectType,
        objectId: objectId,
        role: role,
      );
      if (existing == null) {
        final id = Ids.next('cref');
        await _db.into(_db.contentRefs).insert(
              ContentRefsCompanion.insert(
                id: id,
                contentId: contentId,
                contentVersion: Value(contentVersion),
                contentHash: Value(contentHash),
                subject: Value(subject),
                objectType: objectType,
                objectId: objectId,
                role: role,
                metadataJson: Value(_encodeMetadata(metadata)),
                createdAt: now,
                updatedAt: now,
              ),
            );
        return (_db.select(_db.contentRefs)
              ..where((r) => r.id.equals(id)))
            .getSingle();
      }

      final nextVersion = contentVersion ?? existing.contentVersion;
      final nextHash = contentHash ?? existing.contentHash;
      if ((nextVersion == null) != (nextHash == null)) {
        throw ArgumentError(
          'content_version 与 content_hash 必须成对：'
          'contentId=$contentId version=$nextVersion hash=$nextHash',
        );
      }
      final nextSubject = subject ?? existing.subject;
      final mergedMetadata = _mergeMetadata(
        existing.metadataJson,
        metadata,
        previousVersion: existing.contentVersion,
        previousHash: existing.contentHash,
        versionChanged: nextVersion != existing.contentVersion,
        hashChanged: nextHash != existing.contentHash,
      );
      final changed = nextVersion != existing.contentVersion ||
          nextHash != existing.contentHash ||
          nextSubject != existing.subject ||
          mergedMetadata != existing.metadataJson;
      if (!changed) {
        return existing;
      }
      await (_db.update(_db.contentRefs)
            ..where((r) => r.id.equals(existing.id)))
          .write(
        ContentRefsCompanion(
          contentVersion: Value(nextVersion),
          contentHash: Value(nextHash),
          subject: Value(nextSubject),
          metadataJson: Value(mergedMetadata),
          updatedAt: Value(now),
        ),
      );
      return (_db.select(_db.contentRefs)
            ..where((r) => r.id.equals(existing.id)))
          .getSingle();
    });
  }

  /// 按内容 id 查所有引用（同一个内容对象可以挂到题目/任务/卡片等多个产品对象上）。
  Future<List<ContentRefRow>> listByContentId(String contentId) {
    return (_db.select(_db.contentRefs)
          ..where((r) => r.contentId.equals(contentId))
          ..orderBy([
            (r) => OrderingTerm.asc(r.objectType),
            (r) => OrderingTerm.asc(r.objectId),
            (r) => OrderingTerm.asc(r.role),
          ]))
        .get();
  }

  /// 按产品对象查它引用了哪些内容对象。
  Future<List<ContentRefRow>> listForObject({
    required String objectType,
    required String objectId,
  }) {
    return (_db.select(_db.contentRefs)
          ..where(
            (r) => r.objectType.equals(objectType) & r.objectId.equals(objectId),
          )
          ..orderBy([
            (r) => OrderingTerm.asc(r.contentId),
            (r) => OrderingTerm.asc(r.role),
          ]))
        .get();
  }

  /// 单条精确查询（唯一键四元组）。
  Future<ContentRefRow?> findOne({
    required String contentId,
    required String objectType,
    required String objectId,
    required String role,
  }) =>
      _find(
        contentId: contentId,
        objectType: objectType,
        objectId: objectId,
        role: role,
      );

  /// 删一条引用（引用不是正文，删掉不影响内容包；返回是否真的删了）。
  Future<bool> delete({
    required String contentId,
    required String objectType,
    required String objectId,
    required String role,
  }) async {
    final existing = await _find(
      contentId: contentId,
      objectType: objectType,
      objectId: objectId,
      role: role,
    );
    if (existing == null) {
      return false;
    }
    await (_db.delete(_db.contentRefs)
          ..where((r) => r.id.equals(existing.id)))
        .go();
    return true;
  }

  Future<ContentRefRow?> _find({
    required String contentId,
    required String objectType,
    required String objectId,
    required String role,
  }) {
    return (_db.select(_db.contentRefs)
          ..where(
            (r) =>
                r.contentId.equals(contentId) &
                r.objectType.equals(objectType) &
                r.objectId.equals(objectId) &
                r.role.equals(role),
          ))
        .getSingleOrNull();
  }

  static void _validateContentId(String contentId) {
    final trimmed = contentId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('content_id 不能为空');
    }
    if (trimmed != contentId) {
      throw ArgumentError('content_id 不能带首尾空白： "$contentId"');
    }
  }

  static void _validateObjectType(String objectType) {
    if (!ContentObjectType.values.contains(objectType)) {
      throw ArgumentError(
        'object_type "$objectType" 不在词表 ${ContentObjectType.values} 里',
      );
    }
  }

  static void _validateRole(String role) {
    if (!ContentRefRole.values.contains(role)) {
      throw ArgumentError('role "$role" 不在词表 ${ContentRefRole.values} 里');
    }
  }

  static String? _encodeMetadata(Map<String, Object?>? metadata) {
    if (metadata == null || metadata.isEmpty) {
      return null;
    }
    return jsonEncode(metadata);
  }

  /// 合并 metadata：新键覆盖旧键；版本/hash 变了就留下 previous_* 作为审计。
  static String? _mergeMetadata(
    String? existingJson,
    Map<String, Object?>? incoming, {
    required int? previousVersion,
    required String? previousHash,
    required bool versionChanged,
    required bool hashChanged,
  }) {
    Map<String, Object?> merged = const <String, Object?>{};
    if (existingJson != null && existingJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(existingJson);
        if (decoded is Map<String, Object?>) {
          merged = Map<String, Object?>.from(decoded);
        }
      } on FormatException {
        // 坏 JSON 不该让引用写入失败：保留新值，旧 metadata 丢掉即可（它只是
        // 引用摘要，不是正文，也不是学习事实）。
      }
    }
    if (incoming != null) {
      merged.addAll(incoming);
    }
    if (hashChanged && previousHash != null) {
      merged['previous_hash'] = previousHash;
    }
    if (versionChanged && previousVersion != null) {
      merged['previous_version'] = previousVersion;
    }
    return merged.isEmpty ? null : jsonEncode(merged);
  }
}
