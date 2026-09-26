// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProfilesTable extends Profiles with TableInfo<$ProfilesTable, Profile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _avatarColorMeta =
      const VerificationMeta('avatarColor');
  @override
  late final GeneratedColumn<int> avatarColor = GeneratedColumn<int>(
      'avatar_color', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, displayName, avatarColor, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(Insertable<Profile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('avatar_color')) {
      context.handle(
          _avatarColorMeta,
          avatarColor.isAcceptableOrUnknown(
              data['avatar_color']!, _avatarColorMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Profile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Profile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name'])!,
      avatarColor: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}avatar_color']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class Profile extends DataClass implements Insertable<Profile> {
  final String id;
  final String displayName;
  final int? avatarColor;
  final int createdAt;
  const Profile(
      {required this.id,
      required this.displayName,
      this.avatarColor,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || avatarColor != null) {
      map['avatar_color'] = Variable<int>(avatarColor);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      id: Value(id),
      displayName: Value(displayName),
      avatarColor: avatarColor == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarColor),
      createdAt: Value(createdAt),
    );
  }

  factory Profile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Profile(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      avatarColor: serializer.fromJson<int?>(json['avatarColor']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'avatarColor': serializer.toJson<int?>(avatarColor),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Profile copyWith(
          {String? id,
          String? displayName,
          Value<int?> avatarColor = const Value.absent(),
          int? createdAt}) =>
      Profile(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        avatarColor: avatarColor.present ? avatarColor.value : this.avatarColor,
        createdAt: createdAt ?? this.createdAt,
      );
  Profile copyWithCompanion(ProfilesCompanion data) {
    return Profile(
      id: data.id.present ? data.id.value : this.id,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      avatarColor:
          data.avatarColor.present ? data.avatarColor.value : this.avatarColor,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Profile(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, displayName, avatarColor, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.avatarColor == this.avatarColor &&
          other.createdAt == this.createdAt);
}

class ProfilesCompanion extends UpdateCompanion<Profile> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<int?> avatarColor;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarColor = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    required String id,
    required String displayName,
    this.avatarColor = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        displayName = Value(displayName),
        createdAt = Value(createdAt);
  static Insertable<Profile> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<int>? avatarColor,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (avatarColor != null) 'avatar_color': avatarColor,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith(
      {Value<String>? id,
      Value<String>? displayName,
      Value<int?>? avatarColor,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return ProfilesCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      avatarColor: avatarColor ?? this.avatarColor,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarColor.present) {
      map['avatar_color'] = Variable<int>(avatarColor.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSettingsTable extends LocalSettings
    with TableInfo<$LocalSettingsTable, LocalSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _languageMeta =
      const VerificationMeta('language');
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
      'language', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('system'));
  static const VerificationMeta _themeModeMeta =
      const VerificationMeta('themeMode');
  @override
  late final GeneratedColumn<String> themeMode = GeneratedColumn<String>(
      'theme_mode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('system'));
  static const VerificationMeta _profileIdMeta =
      const VerificationMeta('profileId');
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
      'profile_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _activeThemeIdMeta =
      const VerificationMeta('activeThemeId');
  @override
  late final GeneratedColumn<String> activeThemeId = GeneratedColumn<String>(
      'active_theme_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _aiEnabledMeta =
      const VerificationMeta('aiEnabled');
  @override
  late final GeneratedColumn<bool> aiEnabled = GeneratedColumn<bool>(
      'ai_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("ai_enabled" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _aiApiKeyMeta =
      const VerificationMeta('aiApiKey');
  @override
  late final GeneratedColumn<String> aiApiKey = GeneratedColumn<String>(
      'ai_api_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _aiBaseUrlMeta =
      const VerificationMeta('aiBaseUrl');
  @override
  late final GeneratedColumn<String> aiBaseUrl = GeneratedColumn<String>(
      'ai_base_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _aiModelMeta =
      const VerificationMeta('aiModel');
  @override
  late final GeneratedColumn<String> aiModel = GeneratedColumn<String>(
      'ai_model', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _aiPermissionModeMeta =
      const VerificationMeta('aiPermissionMode');
  @override
  late final GeneratedColumn<String> aiPermissionMode = GeneratedColumn<String>(
      'ai_permission_mode', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        language,
        themeMode,
        profileId,
        activeThemeId,
        aiEnabled,
        aiApiKey,
        aiBaseUrl,
        aiModel,
        aiPermissionMode,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_settings';
  @override
  VerificationContext validateIntegrity(Insertable<LocalSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('language')) {
      context.handle(_languageMeta,
          language.isAcceptableOrUnknown(data['language']!, _languageMeta));
    }
    if (data.containsKey('theme_mode')) {
      context.handle(_themeModeMeta,
          themeMode.isAcceptableOrUnknown(data['theme_mode']!, _themeModeMeta));
    }
    if (data.containsKey('profile_id')) {
      context.handle(_profileIdMeta,
          profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta));
    }
    if (data.containsKey('active_theme_id')) {
      context.handle(
          _activeThemeIdMeta,
          activeThemeId.isAcceptableOrUnknown(
              data['active_theme_id']!, _activeThemeIdMeta));
    }
    if (data.containsKey('ai_enabled')) {
      context.handle(_aiEnabledMeta,
          aiEnabled.isAcceptableOrUnknown(data['ai_enabled']!, _aiEnabledMeta));
    }
    if (data.containsKey('ai_api_key')) {
      context.handle(_aiApiKeyMeta,
          aiApiKey.isAcceptableOrUnknown(data['ai_api_key']!, _aiApiKeyMeta));
    }
    if (data.containsKey('ai_base_url')) {
      context.handle(
          _aiBaseUrlMeta,
          aiBaseUrl.isAcceptableOrUnknown(
              data['ai_base_url']!, _aiBaseUrlMeta));
    }
    if (data.containsKey('ai_model')) {
      context.handle(_aiModelMeta,
          aiModel.isAcceptableOrUnknown(data['ai_model']!, _aiModelMeta));
    }
    if (data.containsKey('ai_permission_mode')) {
      context.handle(
          _aiPermissionModeMeta,
          aiPermissionMode.isAcceptableOrUnknown(
              data['ai_permission_mode']!, _aiPermissionModeMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSetting(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      language: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}language'])!,
      themeMode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}theme_mode'])!,
      profileId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}profile_id']),
      activeThemeId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}active_theme_id']),
      aiEnabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}ai_enabled'])!,
      aiApiKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ai_api_key']),
      aiBaseUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ai_base_url']),
      aiModel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ai_model']),
      aiPermissionMode: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}ai_permission_mode']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LocalSettingsTable createAlias(String alias) {
    return $LocalSettingsTable(attachedDatabase, alias);
  }
}

class LocalSetting extends DataClass implements Insertable<LocalSetting> {
  final int id;
  final String language;
  final String themeMode;
  final String? profileId;

  /// v2: active appearance theme; NULL = follow built-in defaults.
  final String? activeThemeId;

  /// Master switch. NULL / false means the AI surface does not exist at all and
  /// the app makes no network call of any kind - which is what keeps the
  /// "offline by default" promise true rather than aspirational.
  final bool aiEnabled;

  /// Provider API key, stored in plain text on purpose (single-user app, see
  /// AI_DESIGN D18 and the requirement that key handling stay convenient).
  /// It is exported inside `.tfpkg`; the export UI says so.
  final String? aiApiKey;

  /// OpenAI-compatible endpoint. Defaults to DeepSeek when NULL.
  final String? aiBaseUrl;

  /// Model name. Defaults to `deepseek-chat` when NULL.
  final String? aiModel;

  /// `plan` | `auto` (see AI_DESIGN D12 v2).
  final String? aiPermissionMode;
  final int createdAt;
  final int updatedAt;
  const LocalSetting(
      {required this.id,
      required this.language,
      required this.themeMode,
      this.profileId,
      this.activeThemeId,
      required this.aiEnabled,
      this.aiApiKey,
      this.aiBaseUrl,
      this.aiModel,
      this.aiPermissionMode,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['language'] = Variable<String>(language);
    map['theme_mode'] = Variable<String>(themeMode);
    if (!nullToAbsent || profileId != null) {
      map['profile_id'] = Variable<String>(profileId);
    }
    if (!nullToAbsent || activeThemeId != null) {
      map['active_theme_id'] = Variable<String>(activeThemeId);
    }
    map['ai_enabled'] = Variable<bool>(aiEnabled);
    if (!nullToAbsent || aiApiKey != null) {
      map['ai_api_key'] = Variable<String>(aiApiKey);
    }
    if (!nullToAbsent || aiBaseUrl != null) {
      map['ai_base_url'] = Variable<String>(aiBaseUrl);
    }
    if (!nullToAbsent || aiModel != null) {
      map['ai_model'] = Variable<String>(aiModel);
    }
    if (!nullToAbsent || aiPermissionMode != null) {
      map['ai_permission_mode'] = Variable<String>(aiPermissionMode);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  LocalSettingsCompanion toCompanion(bool nullToAbsent) {
    return LocalSettingsCompanion(
      id: Value(id),
      language: Value(language),
      themeMode: Value(themeMode),
      profileId: profileId == null && nullToAbsent
          ? const Value.absent()
          : Value(profileId),
      activeThemeId: activeThemeId == null && nullToAbsent
          ? const Value.absent()
          : Value(activeThemeId),
      aiEnabled: Value(aiEnabled),
      aiApiKey: aiApiKey == null && nullToAbsent
          ? const Value.absent()
          : Value(aiApiKey),
      aiBaseUrl: aiBaseUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(aiBaseUrl),
      aiModel: aiModel == null && nullToAbsent
          ? const Value.absent()
          : Value(aiModel),
      aiPermissionMode: aiPermissionMode == null && nullToAbsent
          ? const Value.absent()
          : Value(aiPermissionMode),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSetting(
      id: serializer.fromJson<int>(json['id']),
      language: serializer.fromJson<String>(json['language']),
      themeMode: serializer.fromJson<String>(json['themeMode']),
      profileId: serializer.fromJson<String?>(json['profileId']),
      activeThemeId: serializer.fromJson<String?>(json['activeThemeId']),
      aiEnabled: serializer.fromJson<bool>(json['aiEnabled']),
      aiApiKey: serializer.fromJson<String?>(json['aiApiKey']),
      aiBaseUrl: serializer.fromJson<String?>(json['aiBaseUrl']),
      aiModel: serializer.fromJson<String?>(json['aiModel']),
      aiPermissionMode: serializer.fromJson<String?>(json['aiPermissionMode']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'language': serializer.toJson<String>(language),
      'themeMode': serializer.toJson<String>(themeMode),
      'profileId': serializer.toJson<String?>(profileId),
      'activeThemeId': serializer.toJson<String?>(activeThemeId),
      'aiEnabled': serializer.toJson<bool>(aiEnabled),
      'aiApiKey': serializer.toJson<String?>(aiApiKey),
      'aiBaseUrl': serializer.toJson<String?>(aiBaseUrl),
      'aiModel': serializer.toJson<String?>(aiModel),
      'aiPermissionMode': serializer.toJson<String?>(aiPermissionMode),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  LocalSetting copyWith(
          {int? id,
          String? language,
          String? themeMode,
          Value<String?> profileId = const Value.absent(),
          Value<String?> activeThemeId = const Value.absent(),
          bool? aiEnabled,
          Value<String?> aiApiKey = const Value.absent(),
          Value<String?> aiBaseUrl = const Value.absent(),
          Value<String?> aiModel = const Value.absent(),
          Value<String?> aiPermissionMode = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      LocalSetting(
        id: id ?? this.id,
        language: language ?? this.language,
        themeMode: themeMode ?? this.themeMode,
        profileId: profileId.present ? profileId.value : this.profileId,
        activeThemeId:
            activeThemeId.present ? activeThemeId.value : this.activeThemeId,
        aiEnabled: aiEnabled ?? this.aiEnabled,
        aiApiKey: aiApiKey.present ? aiApiKey.value : this.aiApiKey,
        aiBaseUrl: aiBaseUrl.present ? aiBaseUrl.value : this.aiBaseUrl,
        aiModel: aiModel.present ? aiModel.value : this.aiModel,
        aiPermissionMode: aiPermissionMode.present
            ? aiPermissionMode.value
            : this.aiPermissionMode,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LocalSetting copyWithCompanion(LocalSettingsCompanion data) {
    return LocalSetting(
      id: data.id.present ? data.id.value : this.id,
      language: data.language.present ? data.language.value : this.language,
      themeMode: data.themeMode.present ? data.themeMode.value : this.themeMode,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      activeThemeId: data.activeThemeId.present
          ? data.activeThemeId.value
          : this.activeThemeId,
      aiEnabled: data.aiEnabled.present ? data.aiEnabled.value : this.aiEnabled,
      aiApiKey: data.aiApiKey.present ? data.aiApiKey.value : this.aiApiKey,
      aiBaseUrl: data.aiBaseUrl.present ? data.aiBaseUrl.value : this.aiBaseUrl,
      aiModel: data.aiModel.present ? data.aiModel.value : this.aiModel,
      aiPermissionMode: data.aiPermissionMode.present
          ? data.aiPermissionMode.value
          : this.aiPermissionMode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSetting(')
          ..write('id: $id, ')
          ..write('language: $language, ')
          ..write('themeMode: $themeMode, ')
          ..write('profileId: $profileId, ')
          ..write('activeThemeId: $activeThemeId, ')
          ..write('aiEnabled: $aiEnabled, ')
          ..write('aiApiKey: $aiApiKey, ')
          ..write('aiBaseUrl: $aiBaseUrl, ')
          ..write('aiModel: $aiModel, ')
          ..write('aiPermissionMode: $aiPermissionMode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      language,
      themeMode,
      profileId,
      activeThemeId,
      aiEnabled,
      aiApiKey,
      aiBaseUrl,
      aiModel,
      aiPermissionMode,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSetting &&
          other.id == this.id &&
          other.language == this.language &&
          other.themeMode == this.themeMode &&
          other.profileId == this.profileId &&
          other.activeThemeId == this.activeThemeId &&
          other.aiEnabled == this.aiEnabled &&
          other.aiApiKey == this.aiApiKey &&
          other.aiBaseUrl == this.aiBaseUrl &&
          other.aiModel == this.aiModel &&
          other.aiPermissionMode == this.aiPermissionMode &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalSettingsCompanion extends UpdateCompanion<LocalSetting> {
  final Value<int> id;
  final Value<String> language;
  final Value<String> themeMode;
  final Value<String?> profileId;
  final Value<String?> activeThemeId;
  final Value<bool> aiEnabled;
  final Value<String?> aiApiKey;
  final Value<String?> aiBaseUrl;
  final Value<String?> aiModel;
  final Value<String?> aiPermissionMode;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  const LocalSettingsCompanion({
    this.id = const Value.absent(),
    this.language = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.profileId = const Value.absent(),
    this.activeThemeId = const Value.absent(),
    this.aiEnabled = const Value.absent(),
    this.aiApiKey = const Value.absent(),
    this.aiBaseUrl = const Value.absent(),
    this.aiModel = const Value.absent(),
    this.aiPermissionMode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  LocalSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.language = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.profileId = const Value.absent(),
    this.activeThemeId = const Value.absent(),
    this.aiEnabled = const Value.absent(),
    this.aiApiKey = const Value.absent(),
    this.aiBaseUrl = const Value.absent(),
    this.aiModel = const Value.absent(),
    this.aiPermissionMode = const Value.absent(),
    required int createdAt,
    required int updatedAt,
  })  : createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<LocalSetting> custom({
    Expression<int>? id,
    Expression<String>? language,
    Expression<String>? themeMode,
    Expression<String>? profileId,
    Expression<String>? activeThemeId,
    Expression<bool>? aiEnabled,
    Expression<String>? aiApiKey,
    Expression<String>? aiBaseUrl,
    Expression<String>? aiModel,
    Expression<String>? aiPermissionMode,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (language != null) 'language': language,
      if (themeMode != null) 'theme_mode': themeMode,
      if (profileId != null) 'profile_id': profileId,
      if (activeThemeId != null) 'active_theme_id': activeThemeId,
      if (aiEnabled != null) 'ai_enabled': aiEnabled,
      if (aiApiKey != null) 'ai_api_key': aiApiKey,
      if (aiBaseUrl != null) 'ai_base_url': aiBaseUrl,
      if (aiModel != null) 'ai_model': aiModel,
      if (aiPermissionMode != null) 'ai_permission_mode': aiPermissionMode,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  LocalSettingsCompanion copyWith(
      {Value<int>? id,
      Value<String>? language,
      Value<String>? themeMode,
      Value<String?>? profileId,
      Value<String?>? activeThemeId,
      Value<bool>? aiEnabled,
      Value<String?>? aiApiKey,
      Value<String?>? aiBaseUrl,
      Value<String?>? aiModel,
      Value<String?>? aiPermissionMode,
      Value<int>? createdAt,
      Value<int>? updatedAt}) {
    return LocalSettingsCompanion(
      id: id ?? this.id,
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      profileId: profileId ?? this.profileId,
      activeThemeId: activeThemeId ?? this.activeThemeId,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      aiApiKey: aiApiKey ?? this.aiApiKey,
      aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
      aiModel: aiModel ?? this.aiModel,
      aiPermissionMode: aiPermissionMode ?? this.aiPermissionMode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (themeMode.present) {
      map['theme_mode'] = Variable<String>(themeMode.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (activeThemeId.present) {
      map['active_theme_id'] = Variable<String>(activeThemeId.value);
    }
    if (aiEnabled.present) {
      map['ai_enabled'] = Variable<bool>(aiEnabled.value);
    }
    if (aiApiKey.present) {
      map['ai_api_key'] = Variable<String>(aiApiKey.value);
    }
    if (aiBaseUrl.present) {
      map['ai_base_url'] = Variable<String>(aiBaseUrl.value);
    }
    if (aiModel.present) {
      map['ai_model'] = Variable<String>(aiModel.value);
    }
    if (aiPermissionMode.present) {
      map['ai_permission_mode'] = Variable<String>(aiPermissionMode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSettingsCompanion(')
          ..write('id: $id, ')
          ..write('language: $language, ')
          ..write('themeMode: $themeMode, ')
          ..write('profileId: $profileId, ')
          ..write('activeThemeId: $activeThemeId, ')
          ..write('aiEnabled: $aiEnabled, ')
          ..write('aiApiKey: $aiApiKey, ')
          ..write('aiBaseUrl: $aiBaseUrl, ')
          ..write('aiModel: $aiModel, ')
          ..write('aiPermissionMode: $aiPermissionMode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _parentIdMeta =
      const VerificationMeta('parentId');
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
      'parent_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
      'color', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceNodeIdMeta =
      const VerificationMeta('sourceNodeId');
  @override
  late final GeneratedColumn<String> sourceNodeId = GeneratedColumn<String>(
      'source_node_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        parentId,
        name,
        path,
        color,
        description,
        sourceNodeId,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(Insertable<Tag> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(_parentIdMeta,
          parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    }
    if (data.containsKey('color')) {
      context.handle(
          _colorMeta, color.isAcceptableOrUnknown(data['color']!, _colorMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('source_node_id')) {
      context.handle(
          _sourceNodeIdMeta,
          sourceNodeId.isAcceptableOrUnknown(
              data['source_node_id']!, _sourceNodeIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {path},
      ];
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      parentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_id']),
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path']),
      color: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}color']),
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      sourceNodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_node_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class Tag extends DataClass implements Insertable<Tag> {
  final String id;
  final String? parentId;
  final String name;
  final String? path;
  final int? color;
  final String? description;
  final String? sourceNodeId;
  final int createdAt;
  final int updatedAt;
  const Tag(
      {required this.id,
      this.parentId,
      required this.name,
      this.path,
      this.color,
      this.description,
      this.sourceNodeId,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || path != null) {
      map['path'] = Variable<String>(path);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<int>(color);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || sourceNodeId != null) {
      map['source_node_id'] = Variable<String>(sourceNodeId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      path: path == null && nullToAbsent ? const Value.absent() : Value(path),
      color:
          color == null && nullToAbsent ? const Value.absent() : Value(color),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      sourceNodeId: sourceNodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceNodeId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Tag.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      id: serializer.fromJson<String>(json['id']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      path: serializer.fromJson<String?>(json['path']),
      color: serializer.fromJson<int?>(json['color']),
      description: serializer.fromJson<String?>(json['description']),
      sourceNodeId: serializer.fromJson<String?>(json['sourceNodeId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'parentId': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'path': serializer.toJson<String?>(path),
      'color': serializer.toJson<int?>(color),
      'description': serializer.toJson<String?>(description),
      'sourceNodeId': serializer.toJson<String?>(sourceNodeId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Tag copyWith(
          {String? id,
          Value<String?> parentId = const Value.absent(),
          String? name,
          Value<String?> path = const Value.absent(),
          Value<int?> color = const Value.absent(),
          Value<String?> description = const Value.absent(),
          Value<String?> sourceNodeId = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      Tag(
        id: id ?? this.id,
        parentId: parentId.present ? parentId.value : this.parentId,
        name: name ?? this.name,
        path: path.present ? path.value : this.path,
        color: color.present ? color.value : this.color,
        description: description.present ? description.value : this.description,
        sourceNodeId:
            sourceNodeId.present ? sourceNodeId.value : this.sourceNodeId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Tag copyWithCompanion(TagsCompanion data) {
    return Tag(
      id: data.id.present ? data.id.value : this.id,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      path: data.path.present ? data.path.value : this.path,
      color: data.color.present ? data.color.value : this.color,
      description:
          data.description.present ? data.description.value : this.description,
      sourceNodeId: data.sourceNodeId.present
          ? data.sourceNodeId.value
          : this.sourceNodeId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('path: $path, ')
          ..write('color: $color, ')
          ..write('description: $description, ')
          ..write('sourceNodeId: $sourceNodeId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, parentId, name, path, color, description,
      sourceNodeId, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag &&
          other.id == this.id &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.path == this.path &&
          other.color == this.color &&
          other.description == this.description &&
          other.sourceNodeId == this.sourceNodeId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<String> id;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<String?> path;
  final Value<int?> color;
  final Value<String?> description;
  final Value<String?> sourceNodeId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.path = const Value.absent(),
    this.color = const Value.absent(),
    this.description = const Value.absent(),
    this.sourceNodeId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    this.parentId = const Value.absent(),
    required String name,
    this.path = const Value.absent(),
    this.color = const Value.absent(),
    this.description = const Value.absent(),
    this.sourceNodeId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Tag> custom({
    Expression<String>? id,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<String>? path,
    Expression<int>? color,
    Expression<String>? description,
    Expression<String>? sourceNodeId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (path != null) 'path': path,
      if (color != null) 'color': color,
      if (description != null) 'description': description,
      if (sourceNodeId != null) 'source_node_id': sourceNodeId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith(
      {Value<String>? id,
      Value<String?>? parentId,
      Value<String>? name,
      Value<String?>? path,
      Value<int?>? color,
      Value<String?>? description,
      Value<String?>? sourceNodeId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return TagsCompanion(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      path: path ?? this.path,
      color: color ?? this.color,
      description: description ?? this.description,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (sourceNodeId.present) {
      map['source_node_id'] = Variable<String>(sourceNodeId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('path: $path, ')
          ..write('color: $color, ')
          ..write('description: $description, ')
          ..write('sourceNodeId: $sourceNodeId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ObjectTagsTable extends ObjectTags
    with TableInfo<$ObjectTagsTable, ObjectTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ObjectTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
      'tag_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _objectTypeMeta =
      const VerificationMeta('objectType');
  @override
  late final GeneratedColumn<String> objectType = GeneratedColumn<String>(
      'object_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _objectIdMeta =
      const VerificationMeta('objectId');
  @override
  late final GeneratedColumn<String> objectId = GeneratedColumn<String>(
      'object_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, tagId, objectType, objectId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'object_tags';
  @override
  VerificationContext validateIntegrity(Insertable<ObjectTag> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
          _tagIdMeta, tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta));
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('object_type')) {
      context.handle(
          _objectTypeMeta,
          objectType.isAcceptableOrUnknown(
              data['object_type']!, _objectTypeMeta));
    } else if (isInserting) {
      context.missing(_objectTypeMeta);
    }
    if (data.containsKey('object_id')) {
      context.handle(_objectIdMeta,
          objectId.isAcceptableOrUnknown(data['object_id']!, _objectIdMeta));
    } else if (isInserting) {
      context.missing(_objectIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {tagId, objectType, objectId},
      ];
  @override
  ObjectTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ObjectTag(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      tagId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tag_id'])!,
      objectType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}object_type'])!,
      objectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}object_id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ObjectTagsTable createAlias(String alias) {
    return $ObjectTagsTable(attachedDatabase, alias);
  }
}

class ObjectTag extends DataClass implements Insertable<ObjectTag> {
  final String id;
  final String tagId;
  final String objectType;
  final String objectId;
  final int createdAt;
  const ObjectTag(
      {required this.id,
      required this.tagId,
      required this.objectType,
      required this.objectId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tag_id'] = Variable<String>(tagId);
    map['object_type'] = Variable<String>(objectType);
    map['object_id'] = Variable<String>(objectId);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ObjectTagsCompanion toCompanion(bool nullToAbsent) {
    return ObjectTagsCompanion(
      id: Value(id),
      tagId: Value(tagId),
      objectType: Value(objectType),
      objectId: Value(objectId),
      createdAt: Value(createdAt),
    );
  }

  factory ObjectTag.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ObjectTag(
      id: serializer.fromJson<String>(json['id']),
      tagId: serializer.fromJson<String>(json['tagId']),
      objectType: serializer.fromJson<String>(json['objectType']),
      objectId: serializer.fromJson<String>(json['objectId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tagId': serializer.toJson<String>(tagId),
      'objectType': serializer.toJson<String>(objectType),
      'objectId': serializer.toJson<String>(objectId),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ObjectTag copyWith(
          {String? id,
          String? tagId,
          String? objectType,
          String? objectId,
          int? createdAt}) =>
      ObjectTag(
        id: id ?? this.id,
        tagId: tagId ?? this.tagId,
        objectType: objectType ?? this.objectType,
        objectId: objectId ?? this.objectId,
        createdAt: createdAt ?? this.createdAt,
      );
  ObjectTag copyWithCompanion(ObjectTagsCompanion data) {
    return ObjectTag(
      id: data.id.present ? data.id.value : this.id,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      objectType:
          data.objectType.present ? data.objectType.value : this.objectType,
      objectId: data.objectId.present ? data.objectId.value : this.objectId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ObjectTag(')
          ..write('id: $id, ')
          ..write('tagId: $tagId, ')
          ..write('objectType: $objectType, ')
          ..write('objectId: $objectId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, tagId, objectType, objectId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ObjectTag &&
          other.id == this.id &&
          other.tagId == this.tagId &&
          other.objectType == this.objectType &&
          other.objectId == this.objectId &&
          other.createdAt == this.createdAt);
}

class ObjectTagsCompanion extends UpdateCompanion<ObjectTag> {
  final Value<String> id;
  final Value<String> tagId;
  final Value<String> objectType;
  final Value<String> objectId;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ObjectTagsCompanion({
    this.id = const Value.absent(),
    this.tagId = const Value.absent(),
    this.objectType = const Value.absent(),
    this.objectId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ObjectTagsCompanion.insert({
    required String id,
    required String tagId,
    required String objectType,
    required String objectId,
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        tagId = Value(tagId),
        objectType = Value(objectType),
        objectId = Value(objectId),
        createdAt = Value(createdAt);
  static Insertable<ObjectTag> custom({
    Expression<String>? id,
    Expression<String>? tagId,
    Expression<String>? objectType,
    Expression<String>? objectId,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tagId != null) 'tag_id': tagId,
      if (objectType != null) 'object_type': objectType,
      if (objectId != null) 'object_id': objectId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ObjectTagsCompanion copyWith(
      {Value<String>? id,
      Value<String>? tagId,
      Value<String>? objectType,
      Value<String>? objectId,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return ObjectTagsCompanion(
      id: id ?? this.id,
      tagId: tagId ?? this.tagId,
      objectType: objectType ?? this.objectType,
      objectId: objectId ?? this.objectId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (objectType.present) {
      map['object_type'] = Variable<String>(objectType.value);
    }
    if (objectId.present) {
      map['object_id'] = Variable<String>(objectId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ObjectTagsCompanion(')
          ..write('id: $id, ')
          ..write('tagId: $tagId, ')
          ..write('objectType: $objectType, ')
          ..write('objectId: $objectId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MindMapsTable extends MindMaps with TableInfo<$MindMapsTable, MindMap> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MindMapsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 300),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _rootNodeIdMeta =
      const VerificationMeta('rootNodeId');
  @override
  late final GeneratedColumn<String> rootNodeId = GeneratedColumn<String>(
      'root_node_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, title, rootNodeId, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mind_maps';
  @override
  VerificationContext validateIntegrity(Insertable<MindMap> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('root_node_id')) {
      context.handle(
          _rootNodeIdMeta,
          rootNodeId.isAcceptableOrUnknown(
              data['root_node_id']!, _rootNodeIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MindMap map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MindMap(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      rootNodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}root_node_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $MindMapsTable createAlias(String alias) {
    return $MindMapsTable(attachedDatabase, alias);
  }
}

class MindMap extends DataClass implements Insertable<MindMap> {
  final String id;
  final String title;
  final String? rootNodeId;
  final int createdAt;
  final int updatedAt;
  const MindMap(
      {required this.id,
      required this.title,
      this.rootNodeId,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || rootNodeId != null) {
      map['root_node_id'] = Variable<String>(rootNodeId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  MindMapsCompanion toCompanion(bool nullToAbsent) {
    return MindMapsCompanion(
      id: Value(id),
      title: Value(title),
      rootNodeId: rootNodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(rootNodeId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory MindMap.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MindMap(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      rootNodeId: serializer.fromJson<String?>(json['rootNodeId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'rootNodeId': serializer.toJson<String?>(rootNodeId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  MindMap copyWith(
          {String? id,
          String? title,
          Value<String?> rootNodeId = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      MindMap(
        id: id ?? this.id,
        title: title ?? this.title,
        rootNodeId: rootNodeId.present ? rootNodeId.value : this.rootNodeId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  MindMap copyWithCompanion(MindMapsCompanion data) {
    return MindMap(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      rootNodeId:
          data.rootNodeId.present ? data.rootNodeId.value : this.rootNodeId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MindMap(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('rootNodeId: $rootNodeId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, rootNodeId, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MindMap &&
          other.id == this.id &&
          other.title == this.title &&
          other.rootNodeId == this.rootNodeId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MindMapsCompanion extends UpdateCompanion<MindMap> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> rootNodeId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const MindMapsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.rootNodeId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MindMapsCompanion.insert({
    required String id,
    required String title,
    this.rootNodeId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<MindMap> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? rootNodeId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (rootNodeId != null) 'root_node_id': rootNodeId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MindMapsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String?>? rootNodeId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return MindMapsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      rootNodeId: rootNodeId ?? this.rootNodeId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (rootNodeId.present) {
      map['root_node_id'] = Variable<String>(rootNodeId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MindMapsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('rootNodeId: $rootNodeId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MindNodesTable extends MindNodes
    with TableInfo<$MindNodesTable, MindNode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MindNodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _mapIdMeta = const VerificationMeta('mapId');
  @override
  late final GeneratedColumn<String> mapId = GeneratedColumn<String>(
      'map_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _parentIdMeta =
      const VerificationMeta('parentId');
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
      'parent_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _nodeTextMeta =
      const VerificationMeta('nodeText');
  @override
  late final GeneratedColumn<String> nodeText = GeneratedColumn<String>(
      'text', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isTagMeta = const VerificationMeta('isTag');
  @override
  late final GeneratedColumn<bool> isTag = GeneratedColumn<bool>(
      'is_tag', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_tag" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
      'tag_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _positionXMeta =
      const VerificationMeta('positionX');
  @override
  late final GeneratedColumn<double> positionX = GeneratedColumn<double>(
      'position_x', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _positionYMeta =
      const VerificationMeta('positionY');
  @override
  late final GeneratedColumn<double> positionY = GeneratedColumn<double>(
      'position_y', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _collapsedMeta =
      const VerificationMeta('collapsed');
  @override
  late final GeneratedColumn<bool> collapsed = GeneratedColumn<bool>(
      'collapsed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("collapsed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        mapId,
        parentId,
        nodeText,
        notes,
        isTag,
        tagId,
        positionX,
        positionY,
        collapsed,
        sortOrder,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mind_nodes';
  @override
  VerificationContext validateIntegrity(Insertable<MindNode> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('map_id')) {
      context.handle(
          _mapIdMeta, mapId.isAcceptableOrUnknown(data['map_id']!, _mapIdMeta));
    } else if (isInserting) {
      context.missing(_mapIdMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(_parentIdMeta,
          parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta));
    }
    if (data.containsKey('text')) {
      context.handle(_nodeTextMeta,
          nodeText.isAcceptableOrUnknown(data['text']!, _nodeTextMeta));
    } else if (isInserting) {
      context.missing(_nodeTextMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('is_tag')) {
      context.handle(
          _isTagMeta, isTag.isAcceptableOrUnknown(data['is_tag']!, _isTagMeta));
    }
    if (data.containsKey('tag_id')) {
      context.handle(
          _tagIdMeta, tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta));
    }
    if (data.containsKey('position_x')) {
      context.handle(_positionXMeta,
          positionX.isAcceptableOrUnknown(data['position_x']!, _positionXMeta));
    }
    if (data.containsKey('position_y')) {
      context.handle(_positionYMeta,
          positionY.isAcceptableOrUnknown(data['position_y']!, _positionYMeta));
    }
    if (data.containsKey('collapsed')) {
      context.handle(_collapsedMeta,
          collapsed.isAcceptableOrUnknown(data['collapsed']!, _collapsedMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MindNode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MindNode(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      mapId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}map_id'])!,
      parentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_id']),
      nodeText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}text'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      isTag: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_tag'])!,
      tagId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tag_id']),
      positionX: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}position_x']),
      positionY: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}position_y']),
      collapsed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}collapsed'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $MindNodesTable createAlias(String alias) {
    return $MindNodesTable(attachedDatabase, alias);
  }
}

class MindNode extends DataClass implements Insertable<MindNode> {
  final String id;
  final String mapId;
  final String? parentId;
  final String nodeText;
  final String? notes;
  final bool isTag;
  final String? tagId;
  final double? positionX;
  final double? positionY;
  final bool collapsed;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
  const MindNode(
      {required this.id,
      required this.mapId,
      this.parentId,
      required this.nodeText,
      this.notes,
      required this.isTag,
      this.tagId,
      this.positionX,
      this.positionY,
      required this.collapsed,
      required this.sortOrder,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['map_id'] = Variable<String>(mapId);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['text'] = Variable<String>(nodeText);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['is_tag'] = Variable<bool>(isTag);
    if (!nullToAbsent || tagId != null) {
      map['tag_id'] = Variable<String>(tagId);
    }
    if (!nullToAbsent || positionX != null) {
      map['position_x'] = Variable<double>(positionX);
    }
    if (!nullToAbsent || positionY != null) {
      map['position_y'] = Variable<double>(positionY);
    }
    map['collapsed'] = Variable<bool>(collapsed);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  MindNodesCompanion toCompanion(bool nullToAbsent) {
    return MindNodesCompanion(
      id: Value(id),
      mapId: Value(mapId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      nodeText: Value(nodeText),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      isTag: Value(isTag),
      tagId:
          tagId == null && nullToAbsent ? const Value.absent() : Value(tagId),
      positionX: positionX == null && nullToAbsent
          ? const Value.absent()
          : Value(positionX),
      positionY: positionY == null && nullToAbsent
          ? const Value.absent()
          : Value(positionY),
      collapsed: Value(collapsed),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory MindNode.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MindNode(
      id: serializer.fromJson<String>(json['id']),
      mapId: serializer.fromJson<String>(json['mapId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      nodeText: serializer.fromJson<String>(json['nodeText']),
      notes: serializer.fromJson<String?>(json['notes']),
      isTag: serializer.fromJson<bool>(json['isTag']),
      tagId: serializer.fromJson<String?>(json['tagId']),
      positionX: serializer.fromJson<double?>(json['positionX']),
      positionY: serializer.fromJson<double?>(json['positionY']),
      collapsed: serializer.fromJson<bool>(json['collapsed']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'mapId': serializer.toJson<String>(mapId),
      'parentId': serializer.toJson<String?>(parentId),
      'nodeText': serializer.toJson<String>(nodeText),
      'notes': serializer.toJson<String?>(notes),
      'isTag': serializer.toJson<bool>(isTag),
      'tagId': serializer.toJson<String?>(tagId),
      'positionX': serializer.toJson<double?>(positionX),
      'positionY': serializer.toJson<double?>(positionY),
      'collapsed': serializer.toJson<bool>(collapsed),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  MindNode copyWith(
          {String? id,
          String? mapId,
          Value<String?> parentId = const Value.absent(),
          String? nodeText,
          Value<String?> notes = const Value.absent(),
          bool? isTag,
          Value<String?> tagId = const Value.absent(),
          Value<double?> positionX = const Value.absent(),
          Value<double?> positionY = const Value.absent(),
          bool? collapsed,
          int? sortOrder,
          int? createdAt,
          int? updatedAt}) =>
      MindNode(
        id: id ?? this.id,
        mapId: mapId ?? this.mapId,
        parentId: parentId.present ? parentId.value : this.parentId,
        nodeText: nodeText ?? this.nodeText,
        notes: notes.present ? notes.value : this.notes,
        isTag: isTag ?? this.isTag,
        tagId: tagId.present ? tagId.value : this.tagId,
        positionX: positionX.present ? positionX.value : this.positionX,
        positionY: positionY.present ? positionY.value : this.positionY,
        collapsed: collapsed ?? this.collapsed,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  MindNode copyWithCompanion(MindNodesCompanion data) {
    return MindNode(
      id: data.id.present ? data.id.value : this.id,
      mapId: data.mapId.present ? data.mapId.value : this.mapId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      nodeText: data.nodeText.present ? data.nodeText.value : this.nodeText,
      notes: data.notes.present ? data.notes.value : this.notes,
      isTag: data.isTag.present ? data.isTag.value : this.isTag,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      positionX: data.positionX.present ? data.positionX.value : this.positionX,
      positionY: data.positionY.present ? data.positionY.value : this.positionY,
      collapsed: data.collapsed.present ? data.collapsed.value : this.collapsed,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MindNode(')
          ..write('id: $id, ')
          ..write('mapId: $mapId, ')
          ..write('parentId: $parentId, ')
          ..write('nodeText: $nodeText, ')
          ..write('notes: $notes, ')
          ..write('isTag: $isTag, ')
          ..write('tagId: $tagId, ')
          ..write('positionX: $positionX, ')
          ..write('positionY: $positionY, ')
          ..write('collapsed: $collapsed, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, mapId, parentId, nodeText, notes, isTag,
      tagId, positionX, positionY, collapsed, sortOrder, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MindNode &&
          other.id == this.id &&
          other.mapId == this.mapId &&
          other.parentId == this.parentId &&
          other.nodeText == this.nodeText &&
          other.notes == this.notes &&
          other.isTag == this.isTag &&
          other.tagId == this.tagId &&
          other.positionX == this.positionX &&
          other.positionY == this.positionY &&
          other.collapsed == this.collapsed &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MindNodesCompanion extends UpdateCompanion<MindNode> {
  final Value<String> id;
  final Value<String> mapId;
  final Value<String?> parentId;
  final Value<String> nodeText;
  final Value<String?> notes;
  final Value<bool> isTag;
  final Value<String?> tagId;
  final Value<double?> positionX;
  final Value<double?> positionY;
  final Value<bool> collapsed;
  final Value<int> sortOrder;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const MindNodesCompanion({
    this.id = const Value.absent(),
    this.mapId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.nodeText = const Value.absent(),
    this.notes = const Value.absent(),
    this.isTag = const Value.absent(),
    this.tagId = const Value.absent(),
    this.positionX = const Value.absent(),
    this.positionY = const Value.absent(),
    this.collapsed = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MindNodesCompanion.insert({
    required String id,
    required String mapId,
    this.parentId = const Value.absent(),
    required String nodeText,
    this.notes = const Value.absent(),
    this.isTag = const Value.absent(),
    this.tagId = const Value.absent(),
    this.positionX = const Value.absent(),
    this.positionY = const Value.absent(),
    this.collapsed = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        mapId = Value(mapId),
        nodeText = Value(nodeText),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<MindNode> custom({
    Expression<String>? id,
    Expression<String>? mapId,
    Expression<String>? parentId,
    Expression<String>? nodeText,
    Expression<String>? notes,
    Expression<bool>? isTag,
    Expression<String>? tagId,
    Expression<double>? positionX,
    Expression<double>? positionY,
    Expression<bool>? collapsed,
    Expression<int>? sortOrder,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mapId != null) 'map_id': mapId,
      if (parentId != null) 'parent_id': parentId,
      if (nodeText != null) 'text': nodeText,
      if (notes != null) 'notes': notes,
      if (isTag != null) 'is_tag': isTag,
      if (tagId != null) 'tag_id': tagId,
      if (positionX != null) 'position_x': positionX,
      if (positionY != null) 'position_y': positionY,
      if (collapsed != null) 'collapsed': collapsed,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MindNodesCompanion copyWith(
      {Value<String>? id,
      Value<String>? mapId,
      Value<String?>? parentId,
      Value<String>? nodeText,
      Value<String?>? notes,
      Value<bool>? isTag,
      Value<String?>? tagId,
      Value<double?>? positionX,
      Value<double?>? positionY,
      Value<bool>? collapsed,
      Value<int>? sortOrder,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return MindNodesCompanion(
      id: id ?? this.id,
      mapId: mapId ?? this.mapId,
      parentId: parentId ?? this.parentId,
      nodeText: nodeText ?? this.nodeText,
      notes: notes ?? this.notes,
      isTag: isTag ?? this.isTag,
      tagId: tagId ?? this.tagId,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      collapsed: collapsed ?? this.collapsed,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (mapId.present) {
      map['map_id'] = Variable<String>(mapId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (nodeText.present) {
      map['text'] = Variable<String>(nodeText.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isTag.present) {
      map['is_tag'] = Variable<bool>(isTag.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (positionX.present) {
      map['position_x'] = Variable<double>(positionX.value);
    }
    if (positionY.present) {
      map['position_y'] = Variable<double>(positionY.value);
    }
    if (collapsed.present) {
      map['collapsed'] = Variable<bool>(collapsed.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MindNodesCompanion(')
          ..write('id: $id, ')
          ..write('mapId: $mapId, ')
          ..write('parentId: $parentId, ')
          ..write('nodeText: $nodeText, ')
          ..write('notes: $notes, ')
          ..write('isTag: $isTag, ')
          ..write('tagId: $tagId, ')
          ..write('positionX: $positionX, ')
          ..write('positionY: $positionY, ')
          ..write('collapsed: $collapsed, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _parentIdMeta =
      const VerificationMeta('parentId');
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
      'parent_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 300),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('todo'));
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
      'priority', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _estimateMinutesMeta =
      const VerificationMeta('estimateMinutes');
  @override
  late final GeneratedColumn<int> estimateMinutes = GeneratedColumn<int>(
      'estimate_minutes', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<int> dueAt = GeneratedColumn<int>(
      'due_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _remindAtMeta =
      const VerificationMeta('remindAt');
  @override
  late final GeneratedColumn<int> remindAt = GeneratedColumn<int>(
      'remind_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _expectedAtMeta =
      const VerificationMeta('expectedAt');
  @override
  late final GeneratedColumn<int> expectedAt = GeneratedColumn<int>(
      'expected_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
      'started_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _energyRequiredMeta =
      const VerificationMeta('energyRequired');
  @override
  late final GeneratedColumn<int> energyRequired = GeneratedColumn<int>(
      'energy_required', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<int> completedAt = GeneratedColumn<int>(
      'completed_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        parentId,
        title,
        description,
        status,
        priority,
        estimateMinutes,
        dueAt,
        remindAt,
        expectedAt,
        startedAt,
        energyRequired,
        completedAt,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(Insertable<Task> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(_parentIdMeta,
          parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    }
    if (data.containsKey('estimate_minutes')) {
      context.handle(
          _estimateMinutesMeta,
          estimateMinutes.isAcceptableOrUnknown(
              data['estimate_minutes']!, _estimateMinutesMeta));
    }
    if (data.containsKey('due_at')) {
      context.handle(
          _dueAtMeta, dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta));
    }
    if (data.containsKey('remind_at')) {
      context.handle(_remindAtMeta,
          remindAt.isAcceptableOrUnknown(data['remind_at']!, _remindAtMeta));
    }
    if (data.containsKey('expected_at')) {
      context.handle(
          _expectedAtMeta,
          expectedAt.isAcceptableOrUnknown(
              data['expected_at']!, _expectedAtMeta));
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    }
    if (data.containsKey('energy_required')) {
      context.handle(
          _energyRequiredMeta,
          energyRequired.isAcceptableOrUnknown(
              data['energy_required']!, _energyRequiredMeta));
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      parentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_id']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}priority'])!,
      estimateMinutes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}estimate_minutes']),
      dueAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}due_at']),
      remindAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remind_at']),
      expectedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}expected_at']),
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}started_at']),
      energyRequired: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}energy_required']),
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}completed_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class Task extends DataClass implements Insertable<Task> {
  final String id;
  final String? parentId;
  final String title;
  final String? description;
  final String status;
  final int priority;
  final int? estimateMinutes;
  final int? dueAt;
  final int? remindAt;

  /// v2 (Thread events): expected time, soft constraint.
  final int? expectedAt;

  /// v3: moment the user actually started this event. Together with
  /// `completed_at` it yields the actual duration - no ticking timer is ever
  /// run (blueprint 2.6).
  final int? startedAt;

  /// v2 (Thread events): required energy 1-10; NULL = algorithm ignores it.
  final int? energyRequired;

  /// v2: completion moment (convenience; authority is CompletionLogs).
  final int? completedAt;
  final int createdAt;
  final int updatedAt;
  const Task(
      {required this.id,
      this.parentId,
      required this.title,
      this.description,
      required this.status,
      required this.priority,
      this.estimateMinutes,
      this.dueAt,
      this.remindAt,
      this.expectedAt,
      this.startedAt,
      this.energyRequired,
      this.completedAt,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['status'] = Variable<String>(status);
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || estimateMinutes != null) {
      map['estimate_minutes'] = Variable<int>(estimateMinutes);
    }
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<int>(dueAt);
    }
    if (!nullToAbsent || remindAt != null) {
      map['remind_at'] = Variable<int>(remindAt);
    }
    if (!nullToAbsent || expectedAt != null) {
      map['expected_at'] = Variable<int>(expectedAt);
    }
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<int>(startedAt);
    }
    if (!nullToAbsent || energyRequired != null) {
      map['energy_required'] = Variable<int>(energyRequired);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<int>(completedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      status: Value(status),
      priority: Value(priority),
      estimateMinutes: estimateMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimateMinutes),
      dueAt:
          dueAt == null && nullToAbsent ? const Value.absent() : Value(dueAt),
      remindAt: remindAt == null && nullToAbsent
          ? const Value.absent()
          : Value(remindAt),
      expectedAt: expectedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedAt),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      energyRequired: energyRequired == null && nullToAbsent
          ? const Value.absent()
          : Value(energyRequired),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Task.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<String>(json['id']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      status: serializer.fromJson<String>(json['status']),
      priority: serializer.fromJson<int>(json['priority']),
      estimateMinutes: serializer.fromJson<int?>(json['estimateMinutes']),
      dueAt: serializer.fromJson<int?>(json['dueAt']),
      remindAt: serializer.fromJson<int?>(json['remindAt']),
      expectedAt: serializer.fromJson<int?>(json['expectedAt']),
      startedAt: serializer.fromJson<int?>(json['startedAt']),
      energyRequired: serializer.fromJson<int?>(json['energyRequired']),
      completedAt: serializer.fromJson<int?>(json['completedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'parentId': serializer.toJson<String?>(parentId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'status': serializer.toJson<String>(status),
      'priority': serializer.toJson<int>(priority),
      'estimateMinutes': serializer.toJson<int?>(estimateMinutes),
      'dueAt': serializer.toJson<int?>(dueAt),
      'remindAt': serializer.toJson<int?>(remindAt),
      'expectedAt': serializer.toJson<int?>(expectedAt),
      'startedAt': serializer.toJson<int?>(startedAt),
      'energyRequired': serializer.toJson<int?>(energyRequired),
      'completedAt': serializer.toJson<int?>(completedAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Task copyWith(
          {String? id,
          Value<String?> parentId = const Value.absent(),
          String? title,
          Value<String?> description = const Value.absent(),
          String? status,
          int? priority,
          Value<int?> estimateMinutes = const Value.absent(),
          Value<int?> dueAt = const Value.absent(),
          Value<int?> remindAt = const Value.absent(),
          Value<int?> expectedAt = const Value.absent(),
          Value<int?> startedAt = const Value.absent(),
          Value<int?> energyRequired = const Value.absent(),
          Value<int?> completedAt = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      Task(
        id: id ?? this.id,
        parentId: parentId.present ? parentId.value : this.parentId,
        title: title ?? this.title,
        description: description.present ? description.value : this.description,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        estimateMinutes: estimateMinutes.present
            ? estimateMinutes.value
            : this.estimateMinutes,
        dueAt: dueAt.present ? dueAt.value : this.dueAt,
        remindAt: remindAt.present ? remindAt.value : this.remindAt,
        expectedAt: expectedAt.present ? expectedAt.value : this.expectedAt,
        startedAt: startedAt.present ? startedAt.value : this.startedAt,
        energyRequired:
            energyRequired.present ? energyRequired.value : this.energyRequired,
        completedAt: completedAt.present ? completedAt.value : this.completedAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      status: data.status.present ? data.status.value : this.status,
      priority: data.priority.present ? data.priority.value : this.priority,
      estimateMinutes: data.estimateMinutes.present
          ? data.estimateMinutes.value
          : this.estimateMinutes,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      remindAt: data.remindAt.present ? data.remindAt.value : this.remindAt,
      expectedAt:
          data.expectedAt.present ? data.expectedAt.value : this.expectedAt,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      energyRequired: data.energyRequired.present
          ? data.energyRequired.value
          : this.energyRequired,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('estimateMinutes: $estimateMinutes, ')
          ..write('dueAt: $dueAt, ')
          ..write('remindAt: $remindAt, ')
          ..write('expectedAt: $expectedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('energyRequired: $energyRequired, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      parentId,
      title,
      description,
      status,
      priority,
      estimateMinutes,
      dueAt,
      remindAt,
      expectedAt,
      startedAt,
      energyRequired,
      completedAt,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.parentId == this.parentId &&
          other.title == this.title &&
          other.description == this.description &&
          other.status == this.status &&
          other.priority == this.priority &&
          other.estimateMinutes == this.estimateMinutes &&
          other.dueAt == this.dueAt &&
          other.remindAt == this.remindAt &&
          other.expectedAt == this.expectedAt &&
          other.startedAt == this.startedAt &&
          other.energyRequired == this.energyRequired &&
          other.completedAt == this.completedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<String> id;
  final Value<String?> parentId;
  final Value<String> title;
  final Value<String?> description;
  final Value<String> status;
  final Value<int> priority;
  final Value<int?> estimateMinutes;
  final Value<int?> dueAt;
  final Value<int?> remindAt;
  final Value<int?> expectedAt;
  final Value<int?> startedAt;
  final Value<int?> energyRequired;
  final Value<int?> completedAt;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.estimateMinutes = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.expectedAt = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.energyRequired = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    this.parentId = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.estimateMinutes = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.expectedAt = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.energyRequired = const Value.absent(),
    this.completedAt = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Task> custom({
    Expression<String>? id,
    Expression<String>? parentId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? status,
    Expression<int>? priority,
    Expression<int>? estimateMinutes,
    Expression<int>? dueAt,
    Expression<int>? remindAt,
    Expression<int>? expectedAt,
    Expression<int>? startedAt,
    Expression<int>? energyRequired,
    Expression<int>? completedAt,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (parentId != null) 'parent_id': parentId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (estimateMinutes != null) 'estimate_minutes': estimateMinutes,
      if (dueAt != null) 'due_at': dueAt,
      if (remindAt != null) 'remind_at': remindAt,
      if (expectedAt != null) 'expected_at': expectedAt,
      if (startedAt != null) 'started_at': startedAt,
      if (energyRequired != null) 'energy_required': energyRequired,
      if (completedAt != null) 'completed_at': completedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith(
      {Value<String>? id,
      Value<String?>? parentId,
      Value<String>? title,
      Value<String?>? description,
      Value<String>? status,
      Value<int>? priority,
      Value<int?>? estimateMinutes,
      Value<int?>? dueAt,
      Value<int?>? remindAt,
      Value<int?>? expectedAt,
      Value<int?>? startedAt,
      Value<int?>? energyRequired,
      Value<int?>? completedAt,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return TasksCompanion(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      estimateMinutes: estimateMinutes ?? this.estimateMinutes,
      dueAt: dueAt ?? this.dueAt,
      remindAt: remindAt ?? this.remindAt,
      expectedAt: expectedAt ?? this.expectedAt,
      startedAt: startedAt ?? this.startedAt,
      energyRequired: energyRequired ?? this.energyRequired,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (estimateMinutes.present) {
      map['estimate_minutes'] = Variable<int>(estimateMinutes.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<int>(dueAt.value);
    }
    if (remindAt.present) {
      map['remind_at'] = Variable<int>(remindAt.value);
    }
    if (expectedAt.present) {
      map['expected_at'] = Variable<int>(expectedAt.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (energyRequired.present) {
      map['energy_required'] = Variable<int>(energyRequired.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<int>(completedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('estimateMinutes: $estimateMinutes, ')
          ..write('dueAt: $dueAt, ')
          ..write('remindAt: $remindAt, ')
          ..write('expectedAt: $expectedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('energyRequired: $energyRequired, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskDependenciesTable extends TaskDependencies
    with TableInfo<$TaskDependenciesTable, TaskDependency> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskDependenciesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
      'task_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dependsOnTaskIdMeta =
      const VerificationMeta('dependsOnTaskId');
  @override
  late final GeneratedColumn<String> dependsOnTaskId = GeneratedColumn<String>(
      'depends_on_task_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, taskId, dependsOnTaskId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_dependencies';
  @override
  VerificationContext validateIntegrity(Insertable<TaskDependency> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(_taskIdMeta,
          taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta));
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('depends_on_task_id')) {
      context.handle(
          _dependsOnTaskIdMeta,
          dependsOnTaskId.isAcceptableOrUnknown(
              data['depends_on_task_id']!, _dependsOnTaskIdMeta));
    } else if (isInserting) {
      context.missing(_dependsOnTaskIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {taskId, dependsOnTaskId},
      ];
  @override
  TaskDependency map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskDependency(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      taskId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}task_id'])!,
      dependsOnTaskId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}depends_on_task_id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $TaskDependenciesTable createAlias(String alias) {
    return $TaskDependenciesTable(attachedDatabase, alias);
  }
}

class TaskDependency extends DataClass implements Insertable<TaskDependency> {
  final String id;
  final String taskId;
  final String dependsOnTaskId;
  final int createdAt;
  const TaskDependency(
      {required this.id,
      required this.taskId,
      required this.dependsOnTaskId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['depends_on_task_id'] = Variable<String>(dependsOnTaskId);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  TaskDependenciesCompanion toCompanion(bool nullToAbsent) {
    return TaskDependenciesCompanion(
      id: Value(id),
      taskId: Value(taskId),
      dependsOnTaskId: Value(dependsOnTaskId),
      createdAt: Value(createdAt),
    );
  }

  factory TaskDependency.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskDependency(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      dependsOnTaskId: serializer.fromJson<String>(json['dependsOnTaskId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'dependsOnTaskId': serializer.toJson<String>(dependsOnTaskId),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  TaskDependency copyWith(
          {String? id,
          String? taskId,
          String? dependsOnTaskId,
          int? createdAt}) =>
      TaskDependency(
        id: id ?? this.id,
        taskId: taskId ?? this.taskId,
        dependsOnTaskId: dependsOnTaskId ?? this.dependsOnTaskId,
        createdAt: createdAt ?? this.createdAt,
      );
  TaskDependency copyWithCompanion(TaskDependenciesCompanion data) {
    return TaskDependency(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      dependsOnTaskId: data.dependsOnTaskId.present
          ? data.dependsOnTaskId.value
          : this.dependsOnTaskId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskDependency(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('dependsOnTaskId: $dependsOnTaskId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, taskId, dependsOnTaskId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskDependency &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.dependsOnTaskId == this.dependsOnTaskId &&
          other.createdAt == this.createdAt);
}

class TaskDependenciesCompanion extends UpdateCompanion<TaskDependency> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> dependsOnTaskId;
  final Value<int> createdAt;
  final Value<int> rowid;
  const TaskDependenciesCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.dependsOnTaskId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskDependenciesCompanion.insert({
    required String id,
    required String taskId,
    required String dependsOnTaskId,
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        taskId = Value(taskId),
        dependsOnTaskId = Value(dependsOnTaskId),
        createdAt = Value(createdAt);
  static Insertable<TaskDependency> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? dependsOnTaskId,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (dependsOnTaskId != null) 'depends_on_task_id': dependsOnTaskId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskDependenciesCompanion copyWith(
      {Value<String>? id,
      Value<String>? taskId,
      Value<String>? dependsOnTaskId,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return TaskDependenciesCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      dependsOnTaskId: dependsOnTaskId ?? this.dependsOnTaskId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (dependsOnTaskId.present) {
      map['depends_on_task_id'] = Variable<String>(dependsOnTaskId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskDependenciesCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('dependsOnTaskId: $dependsOnTaskId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TimeBlocksTable extends TimeBlocks
    with TableInfo<$TimeBlocksTable, TimeBlock> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TimeBlocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 300),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _startAtMeta =
      const VerificationMeta('startAt');
  @override
  late final GeneratedColumn<int> startAt = GeneratedColumn<int>(
      'start_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _endAtMeta = const VerificationMeta('endAt');
  @override
  late final GeneratedColumn<int> endAt = GeneratedColumn<int>(
      'end_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _repeatRuleMeta =
      const VerificationMeta('repeatRule');
  @override
  late final GeneratedColumn<String> repeatRule = GeneratedColumn<String>(
      'repeat_rule', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _availableMeta =
      const VerificationMeta('available');
  @override
  late final GeneratedColumn<bool> available = GeneratedColumn<bool>(
      'available', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("available" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _energyMeta = const VerificationMeta('energy');
  @override
  late final GeneratedColumn<String> energy = GeneratedColumn<String>(
      'energy', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _suitableForMeta =
      const VerificationMeta('suitableFor');
  @override
  late final GeneratedColumn<String> suitableFor = GeneratedColumn<String>(
      'suitable_for', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        startAt,
        endAt,
        repeatRule,
        available,
        energy,
        suitableFor,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'time_blocks';
  @override
  VerificationContext validateIntegrity(Insertable<TimeBlock> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('start_at')) {
      context.handle(_startAtMeta,
          startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta));
    } else if (isInserting) {
      context.missing(_startAtMeta);
    }
    if (data.containsKey('end_at')) {
      context.handle(
          _endAtMeta, endAt.isAcceptableOrUnknown(data['end_at']!, _endAtMeta));
    } else if (isInserting) {
      context.missing(_endAtMeta);
    }
    if (data.containsKey('repeat_rule')) {
      context.handle(
          _repeatRuleMeta,
          repeatRule.isAcceptableOrUnknown(
              data['repeat_rule']!, _repeatRuleMeta));
    }
    if (data.containsKey('available')) {
      context.handle(_availableMeta,
          available.isAcceptableOrUnknown(data['available']!, _availableMeta));
    }
    if (data.containsKey('energy')) {
      context.handle(_energyMeta,
          energy.isAcceptableOrUnknown(data['energy']!, _energyMeta));
    }
    if (data.containsKey('suitable_for')) {
      context.handle(
          _suitableForMeta,
          suitableFor.isAcceptableOrUnknown(
              data['suitable_for']!, _suitableForMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TimeBlock map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TimeBlock(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      startAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_at'])!,
      endAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}end_at'])!,
      repeatRule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}repeat_rule']),
      available: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}available'])!,
      energy: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}energy']),
      suitableFor: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}suitable_for']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $TimeBlocksTable createAlias(String alias) {
    return $TimeBlocksTable(attachedDatabase, alias);
  }
}

class TimeBlock extends DataClass implements Insertable<TimeBlock> {
  final String id;
  final String title;
  final int startAt;
  final int endAt;
  final String? repeatRule;
  final bool available;
  final String? energy;
  final String? suitableFor;
  final int createdAt;
  final int updatedAt;
  const TimeBlock(
      {required this.id,
      required this.title,
      required this.startAt,
      required this.endAt,
      this.repeatRule,
      required this.available,
      this.energy,
      this.suitableFor,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['start_at'] = Variable<int>(startAt);
    map['end_at'] = Variable<int>(endAt);
    if (!nullToAbsent || repeatRule != null) {
      map['repeat_rule'] = Variable<String>(repeatRule);
    }
    map['available'] = Variable<bool>(available);
    if (!nullToAbsent || energy != null) {
      map['energy'] = Variable<String>(energy);
    }
    if (!nullToAbsent || suitableFor != null) {
      map['suitable_for'] = Variable<String>(suitableFor);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  TimeBlocksCompanion toCompanion(bool nullToAbsent) {
    return TimeBlocksCompanion(
      id: Value(id),
      title: Value(title),
      startAt: Value(startAt),
      endAt: Value(endAt),
      repeatRule: repeatRule == null && nullToAbsent
          ? const Value.absent()
          : Value(repeatRule),
      available: Value(available),
      energy:
          energy == null && nullToAbsent ? const Value.absent() : Value(energy),
      suitableFor: suitableFor == null && nullToAbsent
          ? const Value.absent()
          : Value(suitableFor),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TimeBlock.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TimeBlock(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      startAt: serializer.fromJson<int>(json['startAt']),
      endAt: serializer.fromJson<int>(json['endAt']),
      repeatRule: serializer.fromJson<String?>(json['repeatRule']),
      available: serializer.fromJson<bool>(json['available']),
      energy: serializer.fromJson<String?>(json['energy']),
      suitableFor: serializer.fromJson<String?>(json['suitableFor']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'startAt': serializer.toJson<int>(startAt),
      'endAt': serializer.toJson<int>(endAt),
      'repeatRule': serializer.toJson<String?>(repeatRule),
      'available': serializer.toJson<bool>(available),
      'energy': serializer.toJson<String?>(energy),
      'suitableFor': serializer.toJson<String?>(suitableFor),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  TimeBlock copyWith(
          {String? id,
          String? title,
          int? startAt,
          int? endAt,
          Value<String?> repeatRule = const Value.absent(),
          bool? available,
          Value<String?> energy = const Value.absent(),
          Value<String?> suitableFor = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      TimeBlock(
        id: id ?? this.id,
        title: title ?? this.title,
        startAt: startAt ?? this.startAt,
        endAt: endAt ?? this.endAt,
        repeatRule: repeatRule.present ? repeatRule.value : this.repeatRule,
        available: available ?? this.available,
        energy: energy.present ? energy.value : this.energy,
        suitableFor: suitableFor.present ? suitableFor.value : this.suitableFor,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  TimeBlock copyWithCompanion(TimeBlocksCompanion data) {
    return TimeBlock(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      endAt: data.endAt.present ? data.endAt.value : this.endAt,
      repeatRule:
          data.repeatRule.present ? data.repeatRule.value : this.repeatRule,
      available: data.available.present ? data.available.value : this.available,
      energy: data.energy.present ? data.energy.value : this.energy,
      suitableFor:
          data.suitableFor.present ? data.suitableFor.value : this.suitableFor,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TimeBlock(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('available: $available, ')
          ..write('energy: $energy, ')
          ..write('suitableFor: $suitableFor, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, startAt, endAt, repeatRule,
      available, energy, suitableFor, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimeBlock &&
          other.id == this.id &&
          other.title == this.title &&
          other.startAt == this.startAt &&
          other.endAt == this.endAt &&
          other.repeatRule == this.repeatRule &&
          other.available == this.available &&
          other.energy == this.energy &&
          other.suitableFor == this.suitableFor &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TimeBlocksCompanion extends UpdateCompanion<TimeBlock> {
  final Value<String> id;
  final Value<String> title;
  final Value<int> startAt;
  final Value<int> endAt;
  final Value<String?> repeatRule;
  final Value<bool> available;
  final Value<String?> energy;
  final Value<String?> suitableFor;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const TimeBlocksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.repeatRule = const Value.absent(),
    this.available = const Value.absent(),
    this.energy = const Value.absent(),
    this.suitableFor = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TimeBlocksCompanion.insert({
    required String id,
    required String title,
    required int startAt,
    required int endAt,
    this.repeatRule = const Value.absent(),
    this.available = const Value.absent(),
    this.energy = const Value.absent(),
    this.suitableFor = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        startAt = Value(startAt),
        endAt = Value(endAt),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<TimeBlock> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<int>? startAt,
    Expression<int>? endAt,
    Expression<String>? repeatRule,
    Expression<bool>? available,
    Expression<String>? energy,
    Expression<String>? suitableFor,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (startAt != null) 'start_at': startAt,
      if (endAt != null) 'end_at': endAt,
      if (repeatRule != null) 'repeat_rule': repeatRule,
      if (available != null) 'available': available,
      if (energy != null) 'energy': energy,
      if (suitableFor != null) 'suitable_for': suitableFor,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TimeBlocksCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<int>? startAt,
      Value<int>? endAt,
      Value<String?>? repeatRule,
      Value<bool>? available,
      Value<String?>? energy,
      Value<String?>? suitableFor,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return TimeBlocksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      repeatRule: repeatRule ?? this.repeatRule,
      available: available ?? this.available,
      energy: energy ?? this.energy,
      suitableFor: suitableFor ?? this.suitableFor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<int>(startAt.value);
    }
    if (endAt.present) {
      map['end_at'] = Variable<int>(endAt.value);
    }
    if (repeatRule.present) {
      map['repeat_rule'] = Variable<String>(repeatRule.value);
    }
    if (available.present) {
      map['available'] = Variable<bool>(available.value);
    }
    if (energy.present) {
      map['energy'] = Variable<String>(energy.value);
    }
    if (suitableFor.present) {
      map['suitable_for'] = Variable<String>(suitableFor.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TimeBlocksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('available: $available, ')
          ..write('energy: $energy, ')
          ..write('suitableFor: $suitableFor, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskTimeBlocksTable extends TaskTimeBlocks
    with TableInfo<$TaskTimeBlocksTable, TaskTimeBlock> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskTimeBlocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
      'task_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _timeBlockIdMeta =
      const VerificationMeta('timeBlockId');
  @override
  late final GeneratedColumn<String> timeBlockId = GeneratedColumn<String>(
      'time_block_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isSuggestionMeta =
      const VerificationMeta('isSuggestion');
  @override
  late final GeneratedColumn<bool> isSuggestion = GeneratedColumn<bool>(
      'is_suggestion', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_suggestion" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, taskId, timeBlockId, isSuggestion, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_time_blocks';
  @override
  VerificationContext validateIntegrity(Insertable<TaskTimeBlock> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(_taskIdMeta,
          taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta));
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('time_block_id')) {
      context.handle(
          _timeBlockIdMeta,
          timeBlockId.isAcceptableOrUnknown(
              data['time_block_id']!, _timeBlockIdMeta));
    } else if (isInserting) {
      context.missing(_timeBlockIdMeta);
    }
    if (data.containsKey('is_suggestion')) {
      context.handle(
          _isSuggestionMeta,
          isSuggestion.isAcceptableOrUnknown(
              data['is_suggestion']!, _isSuggestionMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {taskId, timeBlockId},
      ];
  @override
  TaskTimeBlock map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskTimeBlock(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      taskId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}task_id'])!,
      timeBlockId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}time_block_id'])!,
      isSuggestion: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_suggestion'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $TaskTimeBlocksTable createAlias(String alias) {
    return $TaskTimeBlocksTable(attachedDatabase, alias);
  }
}

class TaskTimeBlock extends DataClass implements Insertable<TaskTimeBlock> {
  final String id;
  final String taskId;
  final String timeBlockId;
  final bool isSuggestion;
  final int createdAt;
  const TaskTimeBlock(
      {required this.id,
      required this.taskId,
      required this.timeBlockId,
      required this.isSuggestion,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['time_block_id'] = Variable<String>(timeBlockId);
    map['is_suggestion'] = Variable<bool>(isSuggestion);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  TaskTimeBlocksCompanion toCompanion(bool nullToAbsent) {
    return TaskTimeBlocksCompanion(
      id: Value(id),
      taskId: Value(taskId),
      timeBlockId: Value(timeBlockId),
      isSuggestion: Value(isSuggestion),
      createdAt: Value(createdAt),
    );
  }

  factory TaskTimeBlock.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskTimeBlock(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      timeBlockId: serializer.fromJson<String>(json['timeBlockId']),
      isSuggestion: serializer.fromJson<bool>(json['isSuggestion']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'timeBlockId': serializer.toJson<String>(timeBlockId),
      'isSuggestion': serializer.toJson<bool>(isSuggestion),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  TaskTimeBlock copyWith(
          {String? id,
          String? taskId,
          String? timeBlockId,
          bool? isSuggestion,
          int? createdAt}) =>
      TaskTimeBlock(
        id: id ?? this.id,
        taskId: taskId ?? this.taskId,
        timeBlockId: timeBlockId ?? this.timeBlockId,
        isSuggestion: isSuggestion ?? this.isSuggestion,
        createdAt: createdAt ?? this.createdAt,
      );
  TaskTimeBlock copyWithCompanion(TaskTimeBlocksCompanion data) {
    return TaskTimeBlock(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      timeBlockId:
          data.timeBlockId.present ? data.timeBlockId.value : this.timeBlockId,
      isSuggestion: data.isSuggestion.present
          ? data.isSuggestion.value
          : this.isSuggestion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskTimeBlock(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('timeBlockId: $timeBlockId, ')
          ..write('isSuggestion: $isSuggestion, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, taskId, timeBlockId, isSuggestion, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskTimeBlock &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.timeBlockId == this.timeBlockId &&
          other.isSuggestion == this.isSuggestion &&
          other.createdAt == this.createdAt);
}

class TaskTimeBlocksCompanion extends UpdateCompanion<TaskTimeBlock> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> timeBlockId;
  final Value<bool> isSuggestion;
  final Value<int> createdAt;
  final Value<int> rowid;
  const TaskTimeBlocksCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.timeBlockId = const Value.absent(),
    this.isSuggestion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskTimeBlocksCompanion.insert({
    required String id,
    required String taskId,
    required String timeBlockId,
    this.isSuggestion = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        taskId = Value(taskId),
        timeBlockId = Value(timeBlockId),
        createdAt = Value(createdAt);
  static Insertable<TaskTimeBlock> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? timeBlockId,
    Expression<bool>? isSuggestion,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (timeBlockId != null) 'time_block_id': timeBlockId,
      if (isSuggestion != null) 'is_suggestion': isSuggestion,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskTimeBlocksCompanion copyWith(
      {Value<String>? id,
      Value<String>? taskId,
      Value<String>? timeBlockId,
      Value<bool>? isSuggestion,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return TaskTimeBlocksCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      timeBlockId: timeBlockId ?? this.timeBlockId,
      isSuggestion: isSuggestion ?? this.isSuggestion,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (timeBlockId.present) {
      map['time_block_id'] = Variable<String>(timeBlockId.value);
    }
    if (isSuggestion.present) {
      map['is_suggestion'] = Variable<bool>(isSuggestion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskTimeBlocksCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('timeBlockId: $timeBlockId, ')
          ..write('isSuggestion: $isSuggestion, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KnowledgePointsTable extends KnowledgePoints
    with TableInfo<$KnowledgePointsTable, KnowledgePoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnowledgePointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 300),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentFormatMeta =
      const VerificationMeta('contentFormat');
  @override
  late final GeneratedColumn<String> contentFormat = GeneratedColumn<String>(
      'content_format', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _externalIdMeta =
      const VerificationMeta('externalId');
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
      'external_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _packageIdMeta =
      const VerificationMeta('packageId');
  @override
  late final GeneratedColumn<String> packageId = GeneratedColumn<String>(
      'package_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        content,
        contentFormat,
        source,
        externalId,
        packageId,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'knowledge_points';
  @override
  VerificationContext validateIntegrity(Insertable<KnowledgePoint> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('content_format')) {
      context.handle(
          _contentFormatMeta,
          contentFormat.isAcceptableOrUnknown(
              data['content_format']!, _contentFormatMeta));
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    }
    if (data.containsKey('external_id')) {
      context.handle(
          _externalIdMeta,
          externalId.isAcceptableOrUnknown(
              data['external_id']!, _externalIdMeta));
    }
    if (data.containsKey('package_id')) {
      context.handle(_packageIdMeta,
          packageId.isAcceptableOrUnknown(data['package_id']!, _packageIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KnowledgePoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnowledgePoint(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      contentFormat: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content_format']),
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source']),
      externalId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}external_id']),
      packageId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}package_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $KnowledgePointsTable createAlias(String alias) {
    return $KnowledgePointsTable(attachedDatabase, alias);
  }
}

class KnowledgePoint extends DataClass implements Insertable<KnowledgePoint> {
  final String id;
  final String title;
  final String content;

  /// v2: `plain` / `markdown` (NULL legacy rows read as plain).
  final String? contentFormat;
  final String? source;
  final String? externalId;
  final String? packageId;
  final int createdAt;
  final int updatedAt;
  const KnowledgePoint(
      {required this.id,
      required this.title,
      required this.content,
      this.contentFormat,
      this.source,
      this.externalId,
      this.packageId,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || contentFormat != null) {
      map['content_format'] = Variable<String>(contentFormat);
    }
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    if (!nullToAbsent || externalId != null) {
      map['external_id'] = Variable<String>(externalId);
    }
    if (!nullToAbsent || packageId != null) {
      map['package_id'] = Variable<String>(packageId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  KnowledgePointsCompanion toCompanion(bool nullToAbsent) {
    return KnowledgePointsCompanion(
      id: Value(id),
      title: Value(title),
      content: Value(content),
      contentFormat: contentFormat == null && nullToAbsent
          ? const Value.absent()
          : Value(contentFormat),
      source:
          source == null && nullToAbsent ? const Value.absent() : Value(source),
      externalId: externalId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalId),
      packageId: packageId == null && nullToAbsent
          ? const Value.absent()
          : Value(packageId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory KnowledgePoint.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnowledgePoint(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      contentFormat: serializer.fromJson<String?>(json['contentFormat']),
      source: serializer.fromJson<String?>(json['source']),
      externalId: serializer.fromJson<String?>(json['externalId']),
      packageId: serializer.fromJson<String?>(json['packageId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
      'contentFormat': serializer.toJson<String?>(contentFormat),
      'source': serializer.toJson<String?>(source),
      'externalId': serializer.toJson<String?>(externalId),
      'packageId': serializer.toJson<String?>(packageId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  KnowledgePoint copyWith(
          {String? id,
          String? title,
          String? content,
          Value<String?> contentFormat = const Value.absent(),
          Value<String?> source = const Value.absent(),
          Value<String?> externalId = const Value.absent(),
          Value<String?> packageId = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      KnowledgePoint(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        contentFormat:
            contentFormat.present ? contentFormat.value : this.contentFormat,
        source: source.present ? source.value : this.source,
        externalId: externalId.present ? externalId.value : this.externalId,
        packageId: packageId.present ? packageId.value : this.packageId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  KnowledgePoint copyWithCompanion(KnowledgePointsCompanion data) {
    return KnowledgePoint(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      contentFormat: data.contentFormat.present
          ? data.contentFormat.value
          : this.contentFormat,
      source: data.source.present ? data.source.value : this.source,
      externalId:
          data.externalId.present ? data.externalId.value : this.externalId,
      packageId: data.packageId.present ? data.packageId.value : this.packageId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgePoint(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('contentFormat: $contentFormat, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('packageId: $packageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, content, contentFormat, source,
      externalId, packageId, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnowledgePoint &&
          other.id == this.id &&
          other.title == this.title &&
          other.content == this.content &&
          other.contentFormat == this.contentFormat &&
          other.source == this.source &&
          other.externalId == this.externalId &&
          other.packageId == this.packageId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class KnowledgePointsCompanion extends UpdateCompanion<KnowledgePoint> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> content;
  final Value<String?> contentFormat;
  final Value<String?> source;
  final Value<String?> externalId;
  final Value<String?> packageId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const KnowledgePointsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.contentFormat = const Value.absent(),
    this.source = const Value.absent(),
    this.externalId = const Value.absent(),
    this.packageId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnowledgePointsCompanion.insert({
    required String id,
    required String title,
    required String content,
    this.contentFormat = const Value.absent(),
    this.source = const Value.absent(),
    this.externalId = const Value.absent(),
    this.packageId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        content = Value(content),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<KnowledgePoint> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? content,
    Expression<String>? contentFormat,
    Expression<String>? source,
    Expression<String>? externalId,
    Expression<String>? packageId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (contentFormat != null) 'content_format': contentFormat,
      if (source != null) 'source': source,
      if (externalId != null) 'external_id': externalId,
      if (packageId != null) 'package_id': packageId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnowledgePointsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? content,
      Value<String?>? contentFormat,
      Value<String?>? source,
      Value<String?>? externalId,
      Value<String?>? packageId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return KnowledgePointsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      contentFormat: contentFormat ?? this.contentFormat,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      packageId: packageId ?? this.packageId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (contentFormat.present) {
      map['content_format'] = Variable<String>(contentFormat.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (packageId.present) {
      map['package_id'] = Variable<String>(packageId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgePointsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('contentFormat: $contentFormat, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('packageId: $packageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardTemplatesTable extends CardTemplates
    with TableInfo<$CardTemplatesTable, CardTemplate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardTemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _knowledgePointIdMeta =
      const VerificationMeta('knowledgePointId');
  @override
  late final GeneratedColumn<String> knowledgePointId = GeneratedColumn<String>(
      'knowledge_point_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _questionMeta =
      const VerificationMeta('question');
  @override
  late final GeneratedColumn<String> question = GeneratedColumn<String>(
      'question', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _answerMeta = const VerificationMeta('answer');
  @override
  late final GeneratedColumn<String> answer = GeneratedColumn<String>(
      'answer', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _optionsMeta =
      const VerificationMeta('options');
  @override
  late final GeneratedColumn<String> options = GeneratedColumn<String>(
      'options', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _clozeTemplateMeta =
      const VerificationMeta('clozeTemplate');
  @override
  late final GeneratedColumn<String> clozeTemplate = GeneratedColumn<String>(
      'cloze_template', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _hintMeta = const VerificationMeta('hint');
  @override
  late final GeneratedColumn<String> hint = GeneratedColumn<String>(
      'hint', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _externalIdMeta =
      const VerificationMeta('externalId');
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
      'external_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        knowledgePointId,
        type,
        question,
        answer,
        options,
        clozeTemplate,
        hint,
        sortOrder,
        externalId,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'card_templates';
  @override
  VerificationContext validateIntegrity(Insertable<CardTemplate> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('knowledge_point_id')) {
      context.handle(
          _knowledgePointIdMeta,
          knowledgePointId.isAcceptableOrUnknown(
              data['knowledge_point_id']!, _knowledgePointIdMeta));
    } else if (isInserting) {
      context.missing(_knowledgePointIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('question')) {
      context.handle(_questionMeta,
          question.isAcceptableOrUnknown(data['question']!, _questionMeta));
    } else if (isInserting) {
      context.missing(_questionMeta);
    }
    if (data.containsKey('answer')) {
      context.handle(_answerMeta,
          answer.isAcceptableOrUnknown(data['answer']!, _answerMeta));
    } else if (isInserting) {
      context.missing(_answerMeta);
    }
    if (data.containsKey('options')) {
      context.handle(_optionsMeta,
          options.isAcceptableOrUnknown(data['options']!, _optionsMeta));
    }
    if (data.containsKey('cloze_template')) {
      context.handle(
          _clozeTemplateMeta,
          clozeTemplate.isAcceptableOrUnknown(
              data['cloze_template']!, _clozeTemplateMeta));
    }
    if (data.containsKey('hint')) {
      context.handle(
          _hintMeta, hint.isAcceptableOrUnknown(data['hint']!, _hintMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('external_id')) {
      context.handle(
          _externalIdMeta,
          externalId.isAcceptableOrUnknown(
              data['external_id']!, _externalIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CardTemplate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardTemplate(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      knowledgePointId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}knowledge_point_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      question: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}question'])!,
      answer: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}answer'])!,
      options: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}options']),
      clozeTemplate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cloze_template']),
      hint: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}hint']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      externalId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}external_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $CardTemplatesTable createAlias(String alias) {
    return $CardTemplatesTable(attachedDatabase, alias);
  }
}

class CardTemplate extends DataClass implements Insertable<CardTemplate> {
  final String id;
  final String knowledgePointId;
  final String type;
  final String question;
  final String answer;
  final String? options;
  final String? clozeTemplate;
  final String? hint;
  final int sortOrder;
  final String? externalId;
  final int createdAt;
  final int updatedAt;
  const CardTemplate(
      {required this.id,
      required this.knowledgePointId,
      required this.type,
      required this.question,
      required this.answer,
      this.options,
      this.clozeTemplate,
      this.hint,
      required this.sortOrder,
      this.externalId,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['knowledge_point_id'] = Variable<String>(knowledgePointId);
    map['type'] = Variable<String>(type);
    map['question'] = Variable<String>(question);
    map['answer'] = Variable<String>(answer);
    if (!nullToAbsent || options != null) {
      map['options'] = Variable<String>(options);
    }
    if (!nullToAbsent || clozeTemplate != null) {
      map['cloze_template'] = Variable<String>(clozeTemplate);
    }
    if (!nullToAbsent || hint != null) {
      map['hint'] = Variable<String>(hint);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || externalId != null) {
      map['external_id'] = Variable<String>(externalId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  CardTemplatesCompanion toCompanion(bool nullToAbsent) {
    return CardTemplatesCompanion(
      id: Value(id),
      knowledgePointId: Value(knowledgePointId),
      type: Value(type),
      question: Value(question),
      answer: Value(answer),
      options: options == null && nullToAbsent
          ? const Value.absent()
          : Value(options),
      clozeTemplate: clozeTemplate == null && nullToAbsent
          ? const Value.absent()
          : Value(clozeTemplate),
      hint: hint == null && nullToAbsent ? const Value.absent() : Value(hint),
      sortOrder: Value(sortOrder),
      externalId: externalId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CardTemplate.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardTemplate(
      id: serializer.fromJson<String>(json['id']),
      knowledgePointId: serializer.fromJson<String>(json['knowledgePointId']),
      type: serializer.fromJson<String>(json['type']),
      question: serializer.fromJson<String>(json['question']),
      answer: serializer.fromJson<String>(json['answer']),
      options: serializer.fromJson<String?>(json['options']),
      clozeTemplate: serializer.fromJson<String?>(json['clozeTemplate']),
      hint: serializer.fromJson<String?>(json['hint']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      externalId: serializer.fromJson<String?>(json['externalId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'knowledgePointId': serializer.toJson<String>(knowledgePointId),
      'type': serializer.toJson<String>(type),
      'question': serializer.toJson<String>(question),
      'answer': serializer.toJson<String>(answer),
      'options': serializer.toJson<String?>(options),
      'clozeTemplate': serializer.toJson<String?>(clozeTemplate),
      'hint': serializer.toJson<String?>(hint),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'externalId': serializer.toJson<String?>(externalId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  CardTemplate copyWith(
          {String? id,
          String? knowledgePointId,
          String? type,
          String? question,
          String? answer,
          Value<String?> options = const Value.absent(),
          Value<String?> clozeTemplate = const Value.absent(),
          Value<String?> hint = const Value.absent(),
          int? sortOrder,
          Value<String?> externalId = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      CardTemplate(
        id: id ?? this.id,
        knowledgePointId: knowledgePointId ?? this.knowledgePointId,
        type: type ?? this.type,
        question: question ?? this.question,
        answer: answer ?? this.answer,
        options: options.present ? options.value : this.options,
        clozeTemplate:
            clozeTemplate.present ? clozeTemplate.value : this.clozeTemplate,
        hint: hint.present ? hint.value : this.hint,
        sortOrder: sortOrder ?? this.sortOrder,
        externalId: externalId.present ? externalId.value : this.externalId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CardTemplate copyWithCompanion(CardTemplatesCompanion data) {
    return CardTemplate(
      id: data.id.present ? data.id.value : this.id,
      knowledgePointId: data.knowledgePointId.present
          ? data.knowledgePointId.value
          : this.knowledgePointId,
      type: data.type.present ? data.type.value : this.type,
      question: data.question.present ? data.question.value : this.question,
      answer: data.answer.present ? data.answer.value : this.answer,
      options: data.options.present ? data.options.value : this.options,
      clozeTemplate: data.clozeTemplate.present
          ? data.clozeTemplate.value
          : this.clozeTemplate,
      hint: data.hint.present ? data.hint.value : this.hint,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      externalId:
          data.externalId.present ? data.externalId.value : this.externalId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardTemplate(')
          ..write('id: $id, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('type: $type, ')
          ..write('question: $question, ')
          ..write('answer: $answer, ')
          ..write('options: $options, ')
          ..write('clozeTemplate: $clozeTemplate, ')
          ..write('hint: $hint, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('externalId: $externalId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      knowledgePointId,
      type,
      question,
      answer,
      options,
      clozeTemplate,
      hint,
      sortOrder,
      externalId,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardTemplate &&
          other.id == this.id &&
          other.knowledgePointId == this.knowledgePointId &&
          other.type == this.type &&
          other.question == this.question &&
          other.answer == this.answer &&
          other.options == this.options &&
          other.clozeTemplate == this.clozeTemplate &&
          other.hint == this.hint &&
          other.sortOrder == this.sortOrder &&
          other.externalId == this.externalId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CardTemplatesCompanion extends UpdateCompanion<CardTemplate> {
  final Value<String> id;
  final Value<String> knowledgePointId;
  final Value<String> type;
  final Value<String> question;
  final Value<String> answer;
  final Value<String?> options;
  final Value<String?> clozeTemplate;
  final Value<String?> hint;
  final Value<int> sortOrder;
  final Value<String?> externalId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const CardTemplatesCompanion({
    this.id = const Value.absent(),
    this.knowledgePointId = const Value.absent(),
    this.type = const Value.absent(),
    this.question = const Value.absent(),
    this.answer = const Value.absent(),
    this.options = const Value.absent(),
    this.clozeTemplate = const Value.absent(),
    this.hint = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.externalId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardTemplatesCompanion.insert({
    required String id,
    required String knowledgePointId,
    required String type,
    required String question,
    required String answer,
    this.options = const Value.absent(),
    this.clozeTemplate = const Value.absent(),
    this.hint = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.externalId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        knowledgePointId = Value(knowledgePointId),
        type = Value(type),
        question = Value(question),
        answer = Value(answer),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<CardTemplate> custom({
    Expression<String>? id,
    Expression<String>? knowledgePointId,
    Expression<String>? type,
    Expression<String>? question,
    Expression<String>? answer,
    Expression<String>? options,
    Expression<String>? clozeTemplate,
    Expression<String>? hint,
    Expression<int>? sortOrder,
    Expression<String>? externalId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (knowledgePointId != null) 'knowledge_point_id': knowledgePointId,
      if (type != null) 'type': type,
      if (question != null) 'question': question,
      if (answer != null) 'answer': answer,
      if (options != null) 'options': options,
      if (clozeTemplate != null) 'cloze_template': clozeTemplate,
      if (hint != null) 'hint': hint,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (externalId != null) 'external_id': externalId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardTemplatesCompanion copyWith(
      {Value<String>? id,
      Value<String>? knowledgePointId,
      Value<String>? type,
      Value<String>? question,
      Value<String>? answer,
      Value<String?>? options,
      Value<String?>? clozeTemplate,
      Value<String?>? hint,
      Value<int>? sortOrder,
      Value<String?>? externalId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return CardTemplatesCompanion(
      id: id ?? this.id,
      knowledgePointId: knowledgePointId ?? this.knowledgePointId,
      type: type ?? this.type,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      options: options ?? this.options,
      clozeTemplate: clozeTemplate ?? this.clozeTemplate,
      hint: hint ?? this.hint,
      sortOrder: sortOrder ?? this.sortOrder,
      externalId: externalId ?? this.externalId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (knowledgePointId.present) {
      map['knowledge_point_id'] = Variable<String>(knowledgePointId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (question.present) {
      map['question'] = Variable<String>(question.value);
    }
    if (answer.present) {
      map['answer'] = Variable<String>(answer.value);
    }
    if (options.present) {
      map['options'] = Variable<String>(options.value);
    }
    if (clozeTemplate.present) {
      map['cloze_template'] = Variable<String>(clozeTemplate.value);
    }
    if (hint.present) {
      map['hint'] = Variable<String>(hint.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardTemplatesCompanion(')
          ..write('id: $id, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('type: $type, ')
          ..write('question: $question, ')
          ..write('answer: $answer, ')
          ..write('options: $options, ')
          ..write('clozeTemplate: $clozeTemplate, ')
          ..write('hint: $hint, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('externalId: $externalId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardStatesTable extends CardStates
    with TableInfo<$CardStatesTable, CardState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cardTemplateIdMeta =
      const VerificationMeta('cardTemplateId');
  @override
  late final GeneratedColumn<String> cardTemplateId = GeneratedColumn<String>(
      'card_template_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<int> dueAt = GeneratedColumn<int>(
      'due_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _intervalDaysMeta =
      const VerificationMeta('intervalDays');
  @override
  late final GeneratedColumn<double> intervalDays = GeneratedColumn<double>(
      'interval_days', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _easeMeta = const VerificationMeta('ease');
  @override
  late final GeneratedColumn<double> ease = GeneratedColumn<double>(
      'ease', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(2.5));
  static const VerificationMeta _repetitionsMeta =
      const VerificationMeta('repetitions');
  @override
  late final GeneratedColumn<int> repetitions = GeneratedColumn<int>(
      'repetitions', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lapsesMeta = const VerificationMeta('lapses');
  @override
  late final GeneratedColumn<int> lapses = GeneratedColumn<int>(
      'lapses', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
      'state', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('new'));
  static const VerificationMeta _lastReviewedAtMeta =
      const VerificationMeta('lastReviewedAt');
  @override
  late final GeneratedColumn<int> lastReviewedAt = GeneratedColumn<int>(
      'last_reviewed_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _knowledgePointIdMeta =
      const VerificationMeta('knowledgePointId');
  @override
  late final GeneratedColumn<String> knowledgePointId = GeneratedColumn<String>(
      'knowledge_point_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _unitKeyMeta =
      const VerificationMeta('unitKey');
  @override
  late final GeneratedColumn<String> unitKey = GeneratedColumn<String>(
      'unit_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _stabilityMeta =
      const VerificationMeta('stability');
  @override
  late final GeneratedColumn<double> stability = GeneratedColumn<double>(
      'stability', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _difficultyMeta =
      const VerificationMeta('difficulty');
  @override
  late final GeneratedColumn<double> difficulty = GeneratedColumn<double>(
      'difficulty', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _encodingStrengthMeta =
      const VerificationMeta('encodingStrength');
  @override
  late final GeneratedColumn<double> encodingStrength = GeneratedColumn<double>(
      'encoding_strength', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _savingsMeta =
      const VerificationMeta('savings');
  @override
  late final GeneratedColumn<double> savings = GeneratedColumn<double>(
      'savings', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _forcedMeta = const VerificationMeta('forced');
  @override
  late final GeneratedColumn<int> forced = GeneratedColumn<int>(
      'forced', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _forcedStreakMeta =
      const VerificationMeta('forcedStreak');
  @override
  late final GeneratedColumn<int> forcedStreak = GeneratedColumn<int>(
      'forced_streak', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        cardTemplateId,
        dueAt,
        intervalDays,
        ease,
        repetitions,
        lapses,
        state,
        lastReviewedAt,
        createdAt,
        updatedAt,
        knowledgePointId,
        unitKey,
        stability,
        difficulty,
        encodingStrength,
        savings,
        forced,
        forcedStreak
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'card_states';
  @override
  VerificationContext validateIntegrity(Insertable<CardState> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('card_template_id')) {
      context.handle(
          _cardTemplateIdMeta,
          cardTemplateId.isAcceptableOrUnknown(
              data['card_template_id']!, _cardTemplateIdMeta));
    }
    if (data.containsKey('due_at')) {
      context.handle(
          _dueAtMeta, dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta));
    }
    if (data.containsKey('interval_days')) {
      context.handle(
          _intervalDaysMeta,
          intervalDays.isAcceptableOrUnknown(
              data['interval_days']!, _intervalDaysMeta));
    }
    if (data.containsKey('ease')) {
      context.handle(
          _easeMeta, ease.isAcceptableOrUnknown(data['ease']!, _easeMeta));
    }
    if (data.containsKey('repetitions')) {
      context.handle(
          _repetitionsMeta,
          repetitions.isAcceptableOrUnknown(
              data['repetitions']!, _repetitionsMeta));
    }
    if (data.containsKey('lapses')) {
      context.handle(_lapsesMeta,
          lapses.isAcceptableOrUnknown(data['lapses']!, _lapsesMeta));
    }
    if (data.containsKey('state')) {
      context.handle(
          _stateMeta, state.isAcceptableOrUnknown(data['state']!, _stateMeta));
    }
    if (data.containsKey('last_reviewed_at')) {
      context.handle(
          _lastReviewedAtMeta,
          lastReviewedAt.isAcceptableOrUnknown(
              data['last_reviewed_at']!, _lastReviewedAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('knowledge_point_id')) {
      context.handle(
          _knowledgePointIdMeta,
          knowledgePointId.isAcceptableOrUnknown(
              data['knowledge_point_id']!, _knowledgePointIdMeta));
    }
    if (data.containsKey('unit_key')) {
      context.handle(_unitKeyMeta,
          unitKey.isAcceptableOrUnknown(data['unit_key']!, _unitKeyMeta));
    }
    if (data.containsKey('stability')) {
      context.handle(_stabilityMeta,
          stability.isAcceptableOrUnknown(data['stability']!, _stabilityMeta));
    }
    if (data.containsKey('difficulty')) {
      context.handle(
          _difficultyMeta,
          difficulty.isAcceptableOrUnknown(
              data['difficulty']!, _difficultyMeta));
    }
    if (data.containsKey('encoding_strength')) {
      context.handle(
          _encodingStrengthMeta,
          encodingStrength.isAcceptableOrUnknown(
              data['encoding_strength']!, _encodingStrengthMeta));
    }
    if (data.containsKey('savings')) {
      context.handle(_savingsMeta,
          savings.isAcceptableOrUnknown(data['savings']!, _savingsMeta));
    }
    if (data.containsKey('forced')) {
      context.handle(_forcedMeta,
          forced.isAcceptableOrUnknown(data['forced']!, _forcedMeta));
    }
    if (data.containsKey('forced_streak')) {
      context.handle(
          _forcedStreakMeta,
          forcedStreak.isAcceptableOrUnknown(
              data['forced_streak']!, _forcedStreakMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {cardTemplateId},
      ];
  @override
  CardState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardState(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      cardTemplateId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}card_template_id']),
      dueAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}due_at']),
      intervalDays: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}interval_days'])!,
      ease: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}ease'])!,
      repetitions: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}repetitions'])!,
      lapses: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}lapses'])!,
      state: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!,
      lastReviewedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_reviewed_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
      knowledgePointId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}knowledge_point_id']),
      unitKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}unit_key']),
      stability: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}stability']),
      difficulty: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}difficulty']),
      encodingStrength: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}encoding_strength']),
      savings: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}savings']),
      forced: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}forced'])!,
      forcedStreak: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}forced_streak'])!,
    );
  }

  @override
  $CardStatesTable createAlias(String alias) {
    return $CardStatesTable(attachedDatabase, alias);
  }
}

class CardState extends DataClass implements Insertable<CardState> {
  final String id;
  final String? cardTemplateId;
  final int? dueAt;
  final double intervalDays;
  final double ease;
  final int repetitions;
  final int lapses;
  final String state;
  final int? lastReviewedAt;
  final int createdAt;
  final int updatedAt;

  /// v2: owning knowledge point (backfilled from card template in v1 to v2
  /// migration; code always writes non-null for new rows).
  final String? knowledgePointId;

  /// v2: presentation unit key unique within a knowledge point:
  /// `preset:{templateId}` | `cloze:{slotId}` | `essay:{kpId}`.
  final String? unitKey;

  /// v2 FSRS state.
  final double? stability;
  final double? difficulty;

  /// v6: encoding strength / encoding ceiling (MindNet `R0`).
  ///
  /// FSRS as implemented here has no separate ceiling: its curve returns an
  /// absolute retrievability, while MindNet's is `R = R0 * Psi(t/S)`. Porting
  /// the cognitive model therefore needs R0 stored, otherwise the two curves
  /// silently disagree once `R0 < 1` (see docs/MINDNET_CONTRACT.md 8.1).
  /// Nullable: NULL means "never set", not 1.0, so legacy rows stay honest.
  final double? encodingStrength;

  /// v6: savings effect (MindNet `Sigma`), used by the stability-increase term.
  /// Nullable for the same reason as [encodingStrength].
  final double? savings;

  /// v2 forced-binding state (wrong-answer rule): 1 while a short-interval
  /// (10 min) relearning loop with the same unit is active.
  final int forced;

  /// v2: consecutive correct answers while forced; releases at 2.
  final int forcedStreak;
  const CardState(
      {required this.id,
      this.cardTemplateId,
      this.dueAt,
      required this.intervalDays,
      required this.ease,
      required this.repetitions,
      required this.lapses,
      required this.state,
      this.lastReviewedAt,
      required this.createdAt,
      required this.updatedAt,
      this.knowledgePointId,
      this.unitKey,
      this.stability,
      this.difficulty,
      this.encodingStrength,
      this.savings,
      required this.forced,
      required this.forcedStreak});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || cardTemplateId != null) {
      map['card_template_id'] = Variable<String>(cardTemplateId);
    }
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<int>(dueAt);
    }
    map['interval_days'] = Variable<double>(intervalDays);
    map['ease'] = Variable<double>(ease);
    map['repetitions'] = Variable<int>(repetitions);
    map['lapses'] = Variable<int>(lapses);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || lastReviewedAt != null) {
      map['last_reviewed_at'] = Variable<int>(lastReviewedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || knowledgePointId != null) {
      map['knowledge_point_id'] = Variable<String>(knowledgePointId);
    }
    if (!nullToAbsent || unitKey != null) {
      map['unit_key'] = Variable<String>(unitKey);
    }
    if (!nullToAbsent || stability != null) {
      map['stability'] = Variable<double>(stability);
    }
    if (!nullToAbsent || difficulty != null) {
      map['difficulty'] = Variable<double>(difficulty);
    }
    if (!nullToAbsent || encodingStrength != null) {
      map['encoding_strength'] = Variable<double>(encodingStrength);
    }
    if (!nullToAbsent || savings != null) {
      map['savings'] = Variable<double>(savings);
    }
    map['forced'] = Variable<int>(forced);
    map['forced_streak'] = Variable<int>(forcedStreak);
    return map;
  }

  CardStatesCompanion toCompanion(bool nullToAbsent) {
    return CardStatesCompanion(
      id: Value(id),
      cardTemplateId: cardTemplateId == null && nullToAbsent
          ? const Value.absent()
          : Value(cardTemplateId),
      dueAt:
          dueAt == null && nullToAbsent ? const Value.absent() : Value(dueAt),
      intervalDays: Value(intervalDays),
      ease: Value(ease),
      repetitions: Value(repetitions),
      lapses: Value(lapses),
      state: Value(state),
      lastReviewedAt: lastReviewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReviewedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      knowledgePointId: knowledgePointId == null && nullToAbsent
          ? const Value.absent()
          : Value(knowledgePointId),
      unitKey: unitKey == null && nullToAbsent
          ? const Value.absent()
          : Value(unitKey),
      stability: stability == null && nullToAbsent
          ? const Value.absent()
          : Value(stability),
      difficulty: difficulty == null && nullToAbsent
          ? const Value.absent()
          : Value(difficulty),
      encodingStrength: encodingStrength == null && nullToAbsent
          ? const Value.absent()
          : Value(encodingStrength),
      savings: savings == null && nullToAbsent
          ? const Value.absent()
          : Value(savings),
      forced: Value(forced),
      forcedStreak: Value(forcedStreak),
    );
  }

  factory CardState.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardState(
      id: serializer.fromJson<String>(json['id']),
      cardTemplateId: serializer.fromJson<String?>(json['cardTemplateId']),
      dueAt: serializer.fromJson<int?>(json['dueAt']),
      intervalDays: serializer.fromJson<double>(json['intervalDays']),
      ease: serializer.fromJson<double>(json['ease']),
      repetitions: serializer.fromJson<int>(json['repetitions']),
      lapses: serializer.fromJson<int>(json['lapses']),
      state: serializer.fromJson<String>(json['state']),
      lastReviewedAt: serializer.fromJson<int?>(json['lastReviewedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      knowledgePointId: serializer.fromJson<String?>(json['knowledgePointId']),
      unitKey: serializer.fromJson<String?>(json['unitKey']),
      stability: serializer.fromJson<double?>(json['stability']),
      difficulty: serializer.fromJson<double?>(json['difficulty']),
      encodingStrength: serializer.fromJson<double?>(json['encodingStrength']),
      savings: serializer.fromJson<double?>(json['savings']),
      forced: serializer.fromJson<int>(json['forced']),
      forcedStreak: serializer.fromJson<int>(json['forcedStreak']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'cardTemplateId': serializer.toJson<String?>(cardTemplateId),
      'dueAt': serializer.toJson<int?>(dueAt),
      'intervalDays': serializer.toJson<double>(intervalDays),
      'ease': serializer.toJson<double>(ease),
      'repetitions': serializer.toJson<int>(repetitions),
      'lapses': serializer.toJson<int>(lapses),
      'state': serializer.toJson<String>(state),
      'lastReviewedAt': serializer.toJson<int?>(lastReviewedAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'knowledgePointId': serializer.toJson<String?>(knowledgePointId),
      'unitKey': serializer.toJson<String?>(unitKey),
      'stability': serializer.toJson<double?>(stability),
      'difficulty': serializer.toJson<double?>(difficulty),
      'encodingStrength': serializer.toJson<double?>(encodingStrength),
      'savings': serializer.toJson<double?>(savings),
      'forced': serializer.toJson<int>(forced),
      'forcedStreak': serializer.toJson<int>(forcedStreak),
    };
  }

  CardState copyWith(
          {String? id,
          Value<String?> cardTemplateId = const Value.absent(),
          Value<int?> dueAt = const Value.absent(),
          double? intervalDays,
          double? ease,
          int? repetitions,
          int? lapses,
          String? state,
          Value<int?> lastReviewedAt = const Value.absent(),
          int? createdAt,
          int? updatedAt,
          Value<String?> knowledgePointId = const Value.absent(),
          Value<String?> unitKey = const Value.absent(),
          Value<double?> stability = const Value.absent(),
          Value<double?> difficulty = const Value.absent(),
          Value<double?> encodingStrength = const Value.absent(),
          Value<double?> savings = const Value.absent(),
          int? forced,
          int? forcedStreak}) =>
      CardState(
        id: id ?? this.id,
        cardTemplateId:
            cardTemplateId.present ? cardTemplateId.value : this.cardTemplateId,
        dueAt: dueAt.present ? dueAt.value : this.dueAt,
        intervalDays: intervalDays ?? this.intervalDays,
        ease: ease ?? this.ease,
        repetitions: repetitions ?? this.repetitions,
        lapses: lapses ?? this.lapses,
        state: state ?? this.state,
        lastReviewedAt:
            lastReviewedAt.present ? lastReviewedAt.value : this.lastReviewedAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        knowledgePointId: knowledgePointId.present
            ? knowledgePointId.value
            : this.knowledgePointId,
        unitKey: unitKey.present ? unitKey.value : this.unitKey,
        stability: stability.present ? stability.value : this.stability,
        difficulty: difficulty.present ? difficulty.value : this.difficulty,
        encodingStrength: encodingStrength.present
            ? encodingStrength.value
            : this.encodingStrength,
        savings: savings.present ? savings.value : this.savings,
        forced: forced ?? this.forced,
        forcedStreak: forcedStreak ?? this.forcedStreak,
      );
  CardState copyWithCompanion(CardStatesCompanion data) {
    return CardState(
      id: data.id.present ? data.id.value : this.id,
      cardTemplateId: data.cardTemplateId.present
          ? data.cardTemplateId.value
          : this.cardTemplateId,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      intervalDays: data.intervalDays.present
          ? data.intervalDays.value
          : this.intervalDays,
      ease: data.ease.present ? data.ease.value : this.ease,
      repetitions:
          data.repetitions.present ? data.repetitions.value : this.repetitions,
      lapses: data.lapses.present ? data.lapses.value : this.lapses,
      state: data.state.present ? data.state.value : this.state,
      lastReviewedAt: data.lastReviewedAt.present
          ? data.lastReviewedAt.value
          : this.lastReviewedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      knowledgePointId: data.knowledgePointId.present
          ? data.knowledgePointId.value
          : this.knowledgePointId,
      unitKey: data.unitKey.present ? data.unitKey.value : this.unitKey,
      stability: data.stability.present ? data.stability.value : this.stability,
      difficulty:
          data.difficulty.present ? data.difficulty.value : this.difficulty,
      encodingStrength: data.encodingStrength.present
          ? data.encodingStrength.value
          : this.encodingStrength,
      savings: data.savings.present ? data.savings.value : this.savings,
      forced: data.forced.present ? data.forced.value : this.forced,
      forcedStreak: data.forcedStreak.present
          ? data.forcedStreak.value
          : this.forcedStreak,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardState(')
          ..write('id: $id, ')
          ..write('cardTemplateId: $cardTemplateId, ')
          ..write('dueAt: $dueAt, ')
          ..write('intervalDays: $intervalDays, ')
          ..write('ease: $ease, ')
          ..write('repetitions: $repetitions, ')
          ..write('lapses: $lapses, ')
          ..write('state: $state, ')
          ..write('lastReviewedAt: $lastReviewedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('unitKey: $unitKey, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('encodingStrength: $encodingStrength, ')
          ..write('savings: $savings, ')
          ..write('forced: $forced, ')
          ..write('forcedStreak: $forcedStreak')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      cardTemplateId,
      dueAt,
      intervalDays,
      ease,
      repetitions,
      lapses,
      state,
      lastReviewedAt,
      createdAt,
      updatedAt,
      knowledgePointId,
      unitKey,
      stability,
      difficulty,
      encodingStrength,
      savings,
      forced,
      forcedStreak);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardState &&
          other.id == this.id &&
          other.cardTemplateId == this.cardTemplateId &&
          other.dueAt == this.dueAt &&
          other.intervalDays == this.intervalDays &&
          other.ease == this.ease &&
          other.repetitions == this.repetitions &&
          other.lapses == this.lapses &&
          other.state == this.state &&
          other.lastReviewedAt == this.lastReviewedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.knowledgePointId == this.knowledgePointId &&
          other.unitKey == this.unitKey &&
          other.stability == this.stability &&
          other.difficulty == this.difficulty &&
          other.encodingStrength == this.encodingStrength &&
          other.savings == this.savings &&
          other.forced == this.forced &&
          other.forcedStreak == this.forcedStreak);
}

class CardStatesCompanion extends UpdateCompanion<CardState> {
  final Value<String> id;
  final Value<String?> cardTemplateId;
  final Value<int?> dueAt;
  final Value<double> intervalDays;
  final Value<double> ease;
  final Value<int> repetitions;
  final Value<int> lapses;
  final Value<String> state;
  final Value<int?> lastReviewedAt;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<String?> knowledgePointId;
  final Value<String?> unitKey;
  final Value<double?> stability;
  final Value<double?> difficulty;
  final Value<double?> encodingStrength;
  final Value<double?> savings;
  final Value<int> forced;
  final Value<int> forcedStreak;
  final Value<int> rowid;
  const CardStatesCompanion({
    this.id = const Value.absent(),
    this.cardTemplateId = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.intervalDays = const Value.absent(),
    this.ease = const Value.absent(),
    this.repetitions = const Value.absent(),
    this.lapses = const Value.absent(),
    this.state = const Value.absent(),
    this.lastReviewedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.knowledgePointId = const Value.absent(),
    this.unitKey = const Value.absent(),
    this.stability = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.encodingStrength = const Value.absent(),
    this.savings = const Value.absent(),
    this.forced = const Value.absent(),
    this.forcedStreak = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardStatesCompanion.insert({
    required String id,
    this.cardTemplateId = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.intervalDays = const Value.absent(),
    this.ease = const Value.absent(),
    this.repetitions = const Value.absent(),
    this.lapses = const Value.absent(),
    this.state = const Value.absent(),
    this.lastReviewedAt = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.knowledgePointId = const Value.absent(),
    this.unitKey = const Value.absent(),
    this.stability = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.encodingStrength = const Value.absent(),
    this.savings = const Value.absent(),
    this.forced = const Value.absent(),
    this.forcedStreak = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<CardState> custom({
    Expression<String>? id,
    Expression<String>? cardTemplateId,
    Expression<int>? dueAt,
    Expression<double>? intervalDays,
    Expression<double>? ease,
    Expression<int>? repetitions,
    Expression<int>? lapses,
    Expression<String>? state,
    Expression<int>? lastReviewedAt,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? knowledgePointId,
    Expression<String>? unitKey,
    Expression<double>? stability,
    Expression<double>? difficulty,
    Expression<double>? encodingStrength,
    Expression<double>? savings,
    Expression<int>? forced,
    Expression<int>? forcedStreak,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardTemplateId != null) 'card_template_id': cardTemplateId,
      if (dueAt != null) 'due_at': dueAt,
      if (intervalDays != null) 'interval_days': intervalDays,
      if (ease != null) 'ease': ease,
      if (repetitions != null) 'repetitions': repetitions,
      if (lapses != null) 'lapses': lapses,
      if (state != null) 'state': state,
      if (lastReviewedAt != null) 'last_reviewed_at': lastReviewedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (knowledgePointId != null) 'knowledge_point_id': knowledgePointId,
      if (unitKey != null) 'unit_key': unitKey,
      if (stability != null) 'stability': stability,
      if (difficulty != null) 'difficulty': difficulty,
      if (encodingStrength != null) 'encoding_strength': encodingStrength,
      if (savings != null) 'savings': savings,
      if (forced != null) 'forced': forced,
      if (forcedStreak != null) 'forced_streak': forcedStreak,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardStatesCompanion copyWith(
      {Value<String>? id,
      Value<String?>? cardTemplateId,
      Value<int?>? dueAt,
      Value<double>? intervalDays,
      Value<double>? ease,
      Value<int>? repetitions,
      Value<int>? lapses,
      Value<String>? state,
      Value<int?>? lastReviewedAt,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<String?>? knowledgePointId,
      Value<String?>? unitKey,
      Value<double?>? stability,
      Value<double?>? difficulty,
      Value<double?>? encodingStrength,
      Value<double?>? savings,
      Value<int>? forced,
      Value<int>? forcedStreak,
      Value<int>? rowid}) {
    return CardStatesCompanion(
      id: id ?? this.id,
      cardTemplateId: cardTemplateId ?? this.cardTemplateId,
      dueAt: dueAt ?? this.dueAt,
      intervalDays: intervalDays ?? this.intervalDays,
      ease: ease ?? this.ease,
      repetitions: repetitions ?? this.repetitions,
      lapses: lapses ?? this.lapses,
      state: state ?? this.state,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      knowledgePointId: knowledgePointId ?? this.knowledgePointId,
      unitKey: unitKey ?? this.unitKey,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      encodingStrength: encodingStrength ?? this.encodingStrength,
      savings: savings ?? this.savings,
      forced: forced ?? this.forced,
      forcedStreak: forcedStreak ?? this.forcedStreak,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (cardTemplateId.present) {
      map['card_template_id'] = Variable<String>(cardTemplateId.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<int>(dueAt.value);
    }
    if (intervalDays.present) {
      map['interval_days'] = Variable<double>(intervalDays.value);
    }
    if (ease.present) {
      map['ease'] = Variable<double>(ease.value);
    }
    if (repetitions.present) {
      map['repetitions'] = Variable<int>(repetitions.value);
    }
    if (lapses.present) {
      map['lapses'] = Variable<int>(lapses.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (lastReviewedAt.present) {
      map['last_reviewed_at'] = Variable<int>(lastReviewedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (knowledgePointId.present) {
      map['knowledge_point_id'] = Variable<String>(knowledgePointId.value);
    }
    if (unitKey.present) {
      map['unit_key'] = Variable<String>(unitKey.value);
    }
    if (stability.present) {
      map['stability'] = Variable<double>(stability.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<double>(difficulty.value);
    }
    if (encodingStrength.present) {
      map['encoding_strength'] = Variable<double>(encodingStrength.value);
    }
    if (savings.present) {
      map['savings'] = Variable<double>(savings.value);
    }
    if (forced.present) {
      map['forced'] = Variable<int>(forced.value);
    }
    if (forcedStreak.present) {
      map['forced_streak'] = Variable<int>(forcedStreak.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardStatesCompanion(')
          ..write('id: $id, ')
          ..write('cardTemplateId: $cardTemplateId, ')
          ..write('dueAt: $dueAt, ')
          ..write('intervalDays: $intervalDays, ')
          ..write('ease: $ease, ')
          ..write('repetitions: $repetitions, ')
          ..write('lapses: $lapses, ')
          ..write('state: $state, ')
          ..write('lastReviewedAt: $lastReviewedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('unitKey: $unitKey, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('encodingStrength: $encodingStrength, ')
          ..write('savings: $savings, ')
          ..write('forced: $forced, ')
          ..write('forcedStreak: $forcedStreak, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewLogsTable extends ReviewLogs
    with TableInfo<$ReviewLogsTable, ReviewLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cardStateIdMeta =
      const VerificationMeta('cardStateId');
  @override
  late final GeneratedColumn<String> cardStateId = GeneratedColumn<String>(
      'card_state_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cardTemplateIdMeta =
      const VerificationMeta('cardTemplateId');
  @override
  late final GeneratedColumn<String> cardTemplateId = GeneratedColumn<String>(
      'card_template_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _unitKeyMeta =
      const VerificationMeta('unitKey');
  @override
  late final GeneratedColumn<String> unitKey = GeneratedColumn<String>(
      'unit_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
      'rating', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _ratingFsrsMeta =
      const VerificationMeta('ratingFsrs');
  @override
  late final GeneratedColumn<int> ratingFsrs = GeneratedColumn<int>(
      'rating_fsrs', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _correctMeta =
      const VerificationMeta('correct');
  @override
  late final GeneratedColumn<int> correct = GeneratedColumn<int>(
      'correct', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _judgeModeMeta =
      const VerificationMeta('judgeMode');
  @override
  late final GeneratedColumn<String> judgeMode = GeneratedColumn<String>(
      'judge_mode', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
      'format', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _msTakenMeta =
      const VerificationMeta('msTaken');
  @override
  late final GeneratedColumn<int> msTaken = GeneratedColumn<int>(
      'ms_taken', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _reviewedAtMeta =
      const VerificationMeta('reviewedAt');
  @override
  late final GeneratedColumn<int> reviewedAt = GeneratedColumn<int>(
      'reviewed_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        cardStateId,
        cardTemplateId,
        unitKey,
        rating,
        ratingFsrs,
        correct,
        judgeMode,
        format,
        msTaken,
        reviewedAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_logs';
  @override
  VerificationContext validateIntegrity(Insertable<ReviewLog> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('card_state_id')) {
      context.handle(
          _cardStateIdMeta,
          cardStateId.isAcceptableOrUnknown(
              data['card_state_id']!, _cardStateIdMeta));
    } else if (isInserting) {
      context.missing(_cardStateIdMeta);
    }
    if (data.containsKey('card_template_id')) {
      context.handle(
          _cardTemplateIdMeta,
          cardTemplateId.isAcceptableOrUnknown(
              data['card_template_id']!, _cardTemplateIdMeta));
    }
    if (data.containsKey('unit_key')) {
      context.handle(_unitKeyMeta,
          unitKey.isAcceptableOrUnknown(data['unit_key']!, _unitKeyMeta));
    }
    if (data.containsKey('rating')) {
      context.handle(_ratingMeta,
          rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta));
    } else if (isInserting) {
      context.missing(_ratingMeta);
    }
    if (data.containsKey('rating_fsrs')) {
      context.handle(
          _ratingFsrsMeta,
          ratingFsrs.isAcceptableOrUnknown(
              data['rating_fsrs']!, _ratingFsrsMeta));
    }
    if (data.containsKey('correct')) {
      context.handle(_correctMeta,
          correct.isAcceptableOrUnknown(data['correct']!, _correctMeta));
    }
    if (data.containsKey('judge_mode')) {
      context.handle(_judgeModeMeta,
          judgeMode.isAcceptableOrUnknown(data['judge_mode']!, _judgeModeMeta));
    }
    if (data.containsKey('format')) {
      context.handle(_formatMeta,
          format.isAcceptableOrUnknown(data['format']!, _formatMeta));
    }
    if (data.containsKey('ms_taken')) {
      context.handle(_msTakenMeta,
          msTaken.isAcceptableOrUnknown(data['ms_taken']!, _msTakenMeta));
    }
    if (data.containsKey('reviewed_at')) {
      context.handle(
          _reviewedAtMeta,
          reviewedAt.isAcceptableOrUnknown(
              data['reviewed_at']!, _reviewedAtMeta));
    } else if (isInserting) {
      context.missing(_reviewedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewLog(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      cardStateId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}card_state_id'])!,
      cardTemplateId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}card_template_id']),
      unitKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}unit_key']),
      rating: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rating'])!,
      ratingFsrs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rating_fsrs']),
      correct: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}correct']),
      judgeMode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}judge_mode']),
      format: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}format']),
      msTaken: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ms_taken']),
      reviewedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reviewed_at'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ReviewLogsTable createAlias(String alias) {
    return $ReviewLogsTable(attachedDatabase, alias);
  }
}

class ReviewLog extends DataClass implements Insertable<ReviewLog> {
  final String id;
  final String cardStateId;
  final String? cardTemplateId;

  /// v2: unit key snapshot at review time.
  final String? unitKey;

  /// v1 legacy rating: 0=forgot 1=fuzzy 2=remembered.
  final int rating;

  /// v2 FSRS rating: 1=Again 2=Hard 3=Good 4=Easy.
  final int? ratingFsrs;

  /// v2: auto-graded correctness 0/1 (nullable for self-judged attempts).
  final int? correct;

  /// v2 judging mode: `auto` (strict char comparison) / `self`.
  final String? judgeMode;

  /// v2 presented form: mcq / mcq_multi / ordered_multi / fill / essay.
  final String? format;

  /// v2 answer time in ms.
  final int? msTaken;
  final int reviewedAt;
  final int createdAt;
  const ReviewLog(
      {required this.id,
      required this.cardStateId,
      this.cardTemplateId,
      this.unitKey,
      required this.rating,
      this.ratingFsrs,
      this.correct,
      this.judgeMode,
      this.format,
      this.msTaken,
      required this.reviewedAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['card_state_id'] = Variable<String>(cardStateId);
    if (!nullToAbsent || cardTemplateId != null) {
      map['card_template_id'] = Variable<String>(cardTemplateId);
    }
    if (!nullToAbsent || unitKey != null) {
      map['unit_key'] = Variable<String>(unitKey);
    }
    map['rating'] = Variable<int>(rating);
    if (!nullToAbsent || ratingFsrs != null) {
      map['rating_fsrs'] = Variable<int>(ratingFsrs);
    }
    if (!nullToAbsent || correct != null) {
      map['correct'] = Variable<int>(correct);
    }
    if (!nullToAbsent || judgeMode != null) {
      map['judge_mode'] = Variable<String>(judgeMode);
    }
    if (!nullToAbsent || format != null) {
      map['format'] = Variable<String>(format);
    }
    if (!nullToAbsent || msTaken != null) {
      map['ms_taken'] = Variable<int>(msTaken);
    }
    map['reviewed_at'] = Variable<int>(reviewedAt);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ReviewLogsCompanion toCompanion(bool nullToAbsent) {
    return ReviewLogsCompanion(
      id: Value(id),
      cardStateId: Value(cardStateId),
      cardTemplateId: cardTemplateId == null && nullToAbsent
          ? const Value.absent()
          : Value(cardTemplateId),
      unitKey: unitKey == null && nullToAbsent
          ? const Value.absent()
          : Value(unitKey),
      rating: Value(rating),
      ratingFsrs: ratingFsrs == null && nullToAbsent
          ? const Value.absent()
          : Value(ratingFsrs),
      correct: correct == null && nullToAbsent
          ? const Value.absent()
          : Value(correct),
      judgeMode: judgeMode == null && nullToAbsent
          ? const Value.absent()
          : Value(judgeMode),
      format:
          format == null && nullToAbsent ? const Value.absent() : Value(format),
      msTaken: msTaken == null && nullToAbsent
          ? const Value.absent()
          : Value(msTaken),
      reviewedAt: Value(reviewedAt),
      createdAt: Value(createdAt),
    );
  }

  factory ReviewLog.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewLog(
      id: serializer.fromJson<String>(json['id']),
      cardStateId: serializer.fromJson<String>(json['cardStateId']),
      cardTemplateId: serializer.fromJson<String?>(json['cardTemplateId']),
      unitKey: serializer.fromJson<String?>(json['unitKey']),
      rating: serializer.fromJson<int>(json['rating']),
      ratingFsrs: serializer.fromJson<int?>(json['ratingFsrs']),
      correct: serializer.fromJson<int?>(json['correct']),
      judgeMode: serializer.fromJson<String?>(json['judgeMode']),
      format: serializer.fromJson<String?>(json['format']),
      msTaken: serializer.fromJson<int?>(json['msTaken']),
      reviewedAt: serializer.fromJson<int>(json['reviewedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'cardStateId': serializer.toJson<String>(cardStateId),
      'cardTemplateId': serializer.toJson<String?>(cardTemplateId),
      'unitKey': serializer.toJson<String?>(unitKey),
      'rating': serializer.toJson<int>(rating),
      'ratingFsrs': serializer.toJson<int?>(ratingFsrs),
      'correct': serializer.toJson<int?>(correct),
      'judgeMode': serializer.toJson<String?>(judgeMode),
      'format': serializer.toJson<String?>(format),
      'msTaken': serializer.toJson<int?>(msTaken),
      'reviewedAt': serializer.toJson<int>(reviewedAt),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ReviewLog copyWith(
          {String? id,
          String? cardStateId,
          Value<String?> cardTemplateId = const Value.absent(),
          Value<String?> unitKey = const Value.absent(),
          int? rating,
          Value<int?> ratingFsrs = const Value.absent(),
          Value<int?> correct = const Value.absent(),
          Value<String?> judgeMode = const Value.absent(),
          Value<String?> format = const Value.absent(),
          Value<int?> msTaken = const Value.absent(),
          int? reviewedAt,
          int? createdAt}) =>
      ReviewLog(
        id: id ?? this.id,
        cardStateId: cardStateId ?? this.cardStateId,
        cardTemplateId:
            cardTemplateId.present ? cardTemplateId.value : this.cardTemplateId,
        unitKey: unitKey.present ? unitKey.value : this.unitKey,
        rating: rating ?? this.rating,
        ratingFsrs: ratingFsrs.present ? ratingFsrs.value : this.ratingFsrs,
        correct: correct.present ? correct.value : this.correct,
        judgeMode: judgeMode.present ? judgeMode.value : this.judgeMode,
        format: format.present ? format.value : this.format,
        msTaken: msTaken.present ? msTaken.value : this.msTaken,
        reviewedAt: reviewedAt ?? this.reviewedAt,
        createdAt: createdAt ?? this.createdAt,
      );
  ReviewLog copyWithCompanion(ReviewLogsCompanion data) {
    return ReviewLog(
      id: data.id.present ? data.id.value : this.id,
      cardStateId:
          data.cardStateId.present ? data.cardStateId.value : this.cardStateId,
      cardTemplateId: data.cardTemplateId.present
          ? data.cardTemplateId.value
          : this.cardTemplateId,
      unitKey: data.unitKey.present ? data.unitKey.value : this.unitKey,
      rating: data.rating.present ? data.rating.value : this.rating,
      ratingFsrs:
          data.ratingFsrs.present ? data.ratingFsrs.value : this.ratingFsrs,
      correct: data.correct.present ? data.correct.value : this.correct,
      judgeMode: data.judgeMode.present ? data.judgeMode.value : this.judgeMode,
      format: data.format.present ? data.format.value : this.format,
      msTaken: data.msTaken.present ? data.msTaken.value : this.msTaken,
      reviewedAt:
          data.reviewedAt.present ? data.reviewedAt.value : this.reviewedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewLog(')
          ..write('id: $id, ')
          ..write('cardStateId: $cardStateId, ')
          ..write('cardTemplateId: $cardTemplateId, ')
          ..write('unitKey: $unitKey, ')
          ..write('rating: $rating, ')
          ..write('ratingFsrs: $ratingFsrs, ')
          ..write('correct: $correct, ')
          ..write('judgeMode: $judgeMode, ')
          ..write('format: $format, ')
          ..write('msTaken: $msTaken, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      cardStateId,
      cardTemplateId,
      unitKey,
      rating,
      ratingFsrs,
      correct,
      judgeMode,
      format,
      msTaken,
      reviewedAt,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewLog &&
          other.id == this.id &&
          other.cardStateId == this.cardStateId &&
          other.cardTemplateId == this.cardTemplateId &&
          other.unitKey == this.unitKey &&
          other.rating == this.rating &&
          other.ratingFsrs == this.ratingFsrs &&
          other.correct == this.correct &&
          other.judgeMode == this.judgeMode &&
          other.format == this.format &&
          other.msTaken == this.msTaken &&
          other.reviewedAt == this.reviewedAt &&
          other.createdAt == this.createdAt);
}

class ReviewLogsCompanion extends UpdateCompanion<ReviewLog> {
  final Value<String> id;
  final Value<String> cardStateId;
  final Value<String?> cardTemplateId;
  final Value<String?> unitKey;
  final Value<int> rating;
  final Value<int?> ratingFsrs;
  final Value<int?> correct;
  final Value<String?> judgeMode;
  final Value<String?> format;
  final Value<int?> msTaken;
  final Value<int> reviewedAt;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ReviewLogsCompanion({
    this.id = const Value.absent(),
    this.cardStateId = const Value.absent(),
    this.cardTemplateId = const Value.absent(),
    this.unitKey = const Value.absent(),
    this.rating = const Value.absent(),
    this.ratingFsrs = const Value.absent(),
    this.correct = const Value.absent(),
    this.judgeMode = const Value.absent(),
    this.format = const Value.absent(),
    this.msTaken = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewLogsCompanion.insert({
    required String id,
    required String cardStateId,
    this.cardTemplateId = const Value.absent(),
    this.unitKey = const Value.absent(),
    required int rating,
    this.ratingFsrs = const Value.absent(),
    this.correct = const Value.absent(),
    this.judgeMode = const Value.absent(),
    this.format = const Value.absent(),
    this.msTaken = const Value.absent(),
    required int reviewedAt,
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        cardStateId = Value(cardStateId),
        rating = Value(rating),
        reviewedAt = Value(reviewedAt),
        createdAt = Value(createdAt);
  static Insertable<ReviewLog> custom({
    Expression<String>? id,
    Expression<String>? cardStateId,
    Expression<String>? cardTemplateId,
    Expression<String>? unitKey,
    Expression<int>? rating,
    Expression<int>? ratingFsrs,
    Expression<int>? correct,
    Expression<String>? judgeMode,
    Expression<String>? format,
    Expression<int>? msTaken,
    Expression<int>? reviewedAt,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardStateId != null) 'card_state_id': cardStateId,
      if (cardTemplateId != null) 'card_template_id': cardTemplateId,
      if (unitKey != null) 'unit_key': unitKey,
      if (rating != null) 'rating': rating,
      if (ratingFsrs != null) 'rating_fsrs': ratingFsrs,
      if (correct != null) 'correct': correct,
      if (judgeMode != null) 'judge_mode': judgeMode,
      if (format != null) 'format': format,
      if (msTaken != null) 'ms_taken': msTaken,
      if (reviewedAt != null) 'reviewed_at': reviewedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewLogsCompanion copyWith(
      {Value<String>? id,
      Value<String>? cardStateId,
      Value<String?>? cardTemplateId,
      Value<String?>? unitKey,
      Value<int>? rating,
      Value<int?>? ratingFsrs,
      Value<int?>? correct,
      Value<String?>? judgeMode,
      Value<String?>? format,
      Value<int?>? msTaken,
      Value<int>? reviewedAt,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return ReviewLogsCompanion(
      id: id ?? this.id,
      cardStateId: cardStateId ?? this.cardStateId,
      cardTemplateId: cardTemplateId ?? this.cardTemplateId,
      unitKey: unitKey ?? this.unitKey,
      rating: rating ?? this.rating,
      ratingFsrs: ratingFsrs ?? this.ratingFsrs,
      correct: correct ?? this.correct,
      judgeMode: judgeMode ?? this.judgeMode,
      format: format ?? this.format,
      msTaken: msTaken ?? this.msTaken,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (cardStateId.present) {
      map['card_state_id'] = Variable<String>(cardStateId.value);
    }
    if (cardTemplateId.present) {
      map['card_template_id'] = Variable<String>(cardTemplateId.value);
    }
    if (unitKey.present) {
      map['unit_key'] = Variable<String>(unitKey.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (ratingFsrs.present) {
      map['rating_fsrs'] = Variable<int>(ratingFsrs.value);
    }
    if (correct.present) {
      map['correct'] = Variable<int>(correct.value);
    }
    if (judgeMode.present) {
      map['judge_mode'] = Variable<String>(judgeMode.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (msTaken.present) {
      map['ms_taken'] = Variable<int>(msTaken.value);
    }
    if (reviewedAt.present) {
      map['reviewed_at'] = Variable<int>(reviewedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewLogsCompanion(')
          ..write('id: $id, ')
          ..write('cardStateId: $cardStateId, ')
          ..write('cardTemplateId: $cardTemplateId, ')
          ..write('unitKey: $unitKey, ')
          ..write('rating: $rating, ')
          ..write('ratingFsrs: $ratingFsrs, ')
          ..write('correct: $correct, ')
          ..write('judgeMode: $judgeMode, ')
          ..write('format: $format, ')
          ..write('msTaken: $msTaken, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KnowledgePackagesTable extends KnowledgePackages
    with TableInfo<$KnowledgePackagesTable, KnowledgePackage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnowledgePackagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 300),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
      'version', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 50),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
      'author', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _importedAtMeta =
      const VerificationMeta('importedAt');
  @override
  late final GeneratedColumn<int> importedAt = GeneratedColumn<int>(
      'imported_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _fileHashMeta =
      const VerificationMeta('fileHash');
  @override
  late final GeneratedColumn<String> fileHash = GeneratedColumn<String>(
      'file_hash', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        version,
        author,
        description,
        importedAt,
        fileHash,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'knowledge_packages';
  @override
  VerificationContext validateIntegrity(Insertable<KnowledgePackage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('author')) {
      context.handle(_authorMeta,
          author.isAcceptableOrUnknown(data['author']!, _authorMeta));
    } else if (isInserting) {
      context.missing(_authorMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('imported_at')) {
      context.handle(
          _importedAtMeta,
          importedAt.isAcceptableOrUnknown(
              data['imported_at']!, _importedAtMeta));
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    if (data.containsKey('file_hash')) {
      context.handle(_fileHashMeta,
          fileHash.isAcceptableOrUnknown(data['file_hash']!, _fileHashMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KnowledgePackage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnowledgePackage(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}version'])!,
      author: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      importedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}imported_at'])!,
      fileHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_hash']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $KnowledgePackagesTable createAlias(String alias) {
    return $KnowledgePackagesTable(attachedDatabase, alias);
  }
}

class KnowledgePackage extends DataClass
    implements Insertable<KnowledgePackage> {
  final String id;
  final String name;
  final String version;
  final String author;
  final String? description;
  final int importedAt;
  final String? fileHash;
  final int createdAt;
  final int updatedAt;
  const KnowledgePackage(
      {required this.id,
      required this.name,
      required this.version,
      required this.author,
      this.description,
      required this.importedAt,
      this.fileHash,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['version'] = Variable<String>(version);
    map['author'] = Variable<String>(author);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['imported_at'] = Variable<int>(importedAt);
    if (!nullToAbsent || fileHash != null) {
      map['file_hash'] = Variable<String>(fileHash);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  KnowledgePackagesCompanion toCompanion(bool nullToAbsent) {
    return KnowledgePackagesCompanion(
      id: Value(id),
      name: Value(name),
      version: Value(version),
      author: Value(author),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      importedAt: Value(importedAt),
      fileHash: fileHash == null && nullToAbsent
          ? const Value.absent()
          : Value(fileHash),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory KnowledgePackage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnowledgePackage(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      version: serializer.fromJson<String>(json['version']),
      author: serializer.fromJson<String>(json['author']),
      description: serializer.fromJson<String?>(json['description']),
      importedAt: serializer.fromJson<int>(json['importedAt']),
      fileHash: serializer.fromJson<String?>(json['fileHash']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'version': serializer.toJson<String>(version),
      'author': serializer.toJson<String>(author),
      'description': serializer.toJson<String?>(description),
      'importedAt': serializer.toJson<int>(importedAt),
      'fileHash': serializer.toJson<String?>(fileHash),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  KnowledgePackage copyWith(
          {String? id,
          String? name,
          String? version,
          String? author,
          Value<String?> description = const Value.absent(),
          int? importedAt,
          Value<String?> fileHash = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      KnowledgePackage(
        id: id ?? this.id,
        name: name ?? this.name,
        version: version ?? this.version,
        author: author ?? this.author,
        description: description.present ? description.value : this.description,
        importedAt: importedAt ?? this.importedAt,
        fileHash: fileHash.present ? fileHash.value : this.fileHash,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  KnowledgePackage copyWithCompanion(KnowledgePackagesCompanion data) {
    return KnowledgePackage(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      version: data.version.present ? data.version.value : this.version,
      author: data.author.present ? data.author.value : this.author,
      description:
          data.description.present ? data.description.value : this.description,
      importedAt:
          data.importedAt.present ? data.importedAt.value : this.importedAt,
      fileHash: data.fileHash.present ? data.fileHash.value : this.fileHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgePackage(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('version: $version, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('importedAt: $importedAt, ')
          ..write('fileHash: $fileHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, version, author, description,
      importedAt, fileHash, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnowledgePackage &&
          other.id == this.id &&
          other.name == this.name &&
          other.version == this.version &&
          other.author == this.author &&
          other.description == this.description &&
          other.importedAt == this.importedAt &&
          other.fileHash == this.fileHash &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class KnowledgePackagesCompanion extends UpdateCompanion<KnowledgePackage> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> version;
  final Value<String> author;
  final Value<String?> description;
  final Value<int> importedAt;
  final Value<String?> fileHash;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const KnowledgePackagesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.version = const Value.absent(),
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.fileHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnowledgePackagesCompanion.insert({
    required String id,
    required String name,
    required String version,
    required String author,
    this.description = const Value.absent(),
    required int importedAt,
    this.fileHash = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        version = Value(version),
        author = Value(author),
        importedAt = Value(importedAt),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<KnowledgePackage> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? version,
    Expression<String>? author,
    Expression<String>? description,
    Expression<int>? importedAt,
    Expression<String>? fileHash,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (version != null) 'version': version,
      if (author != null) 'author': author,
      if (description != null) 'description': description,
      if (importedAt != null) 'imported_at': importedAt,
      if (fileHash != null) 'file_hash': fileHash,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnowledgePackagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? version,
      Value<String>? author,
      Value<String?>? description,
      Value<int>? importedAt,
      Value<String?>? fileHash,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return KnowledgePackagesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      author: author ?? this.author,
      description: description ?? this.description,
      importedAt: importedAt ?? this.importedAt,
      fileHash: fileHash ?? this.fileHash,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<int>(importedAt.value);
    }
    if (fileHash.present) {
      map['file_hash'] = Variable<String>(fileHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgePackagesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('version: $version, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('importedAt: $importedAt, ')
          ..write('fileHash: $fileHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PackageItemsTable extends PackageItems
    with TableInfo<$PackageItemsTable, PackageItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PackageItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _packageIdMeta =
      const VerificationMeta('packageId');
  @override
  late final GeneratedColumn<String> packageId = GeneratedColumn<String>(
      'package_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _objectTypeMeta =
      const VerificationMeta('objectType');
  @override
  late final GeneratedColumn<String> objectType = GeneratedColumn<String>(
      'object_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _objectIdMeta =
      const VerificationMeta('objectId');
  @override
  late final GeneratedColumn<String> objectId = GeneratedColumn<String>(
      'object_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _externalIdMeta =
      const VerificationMeta('externalId');
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
      'external_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, packageId, objectType, objectId, externalId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'package_items';
  @override
  VerificationContext validateIntegrity(Insertable<PackageItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('package_id')) {
      context.handle(_packageIdMeta,
          packageId.isAcceptableOrUnknown(data['package_id']!, _packageIdMeta));
    } else if (isInserting) {
      context.missing(_packageIdMeta);
    }
    if (data.containsKey('object_type')) {
      context.handle(
          _objectTypeMeta,
          objectType.isAcceptableOrUnknown(
              data['object_type']!, _objectTypeMeta));
    } else if (isInserting) {
      context.missing(_objectTypeMeta);
    }
    if (data.containsKey('object_id')) {
      context.handle(_objectIdMeta,
          objectId.isAcceptableOrUnknown(data['object_id']!, _objectIdMeta));
    } else if (isInserting) {
      context.missing(_objectIdMeta);
    }
    if (data.containsKey('external_id')) {
      context.handle(
          _externalIdMeta,
          externalId.isAcceptableOrUnknown(
              data['external_id']!, _externalIdMeta));
    } else if (isInserting) {
      context.missing(_externalIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {packageId, objectType, objectId},
      ];
  @override
  PackageItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PackageItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      packageId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}package_id'])!,
      objectType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}object_type'])!,
      objectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}object_id'])!,
      externalId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}external_id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $PackageItemsTable createAlias(String alias) {
    return $PackageItemsTable(attachedDatabase, alias);
  }
}

class PackageItem extends DataClass implements Insertable<PackageItem> {
  final String id;
  final String packageId;
  final String objectType;
  final String objectId;
  final String externalId;
  final int createdAt;
  const PackageItem(
      {required this.id,
      required this.packageId,
      required this.objectType,
      required this.objectId,
      required this.externalId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['package_id'] = Variable<String>(packageId);
    map['object_type'] = Variable<String>(objectType);
    map['object_id'] = Variable<String>(objectId);
    map['external_id'] = Variable<String>(externalId);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  PackageItemsCompanion toCompanion(bool nullToAbsent) {
    return PackageItemsCompanion(
      id: Value(id),
      packageId: Value(packageId),
      objectType: Value(objectType),
      objectId: Value(objectId),
      externalId: Value(externalId),
      createdAt: Value(createdAt),
    );
  }

  factory PackageItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PackageItem(
      id: serializer.fromJson<String>(json['id']),
      packageId: serializer.fromJson<String>(json['packageId']),
      objectType: serializer.fromJson<String>(json['objectType']),
      objectId: serializer.fromJson<String>(json['objectId']),
      externalId: serializer.fromJson<String>(json['externalId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'packageId': serializer.toJson<String>(packageId),
      'objectType': serializer.toJson<String>(objectType),
      'objectId': serializer.toJson<String>(objectId),
      'externalId': serializer.toJson<String>(externalId),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  PackageItem copyWith(
          {String? id,
          String? packageId,
          String? objectType,
          String? objectId,
          String? externalId,
          int? createdAt}) =>
      PackageItem(
        id: id ?? this.id,
        packageId: packageId ?? this.packageId,
        objectType: objectType ?? this.objectType,
        objectId: objectId ?? this.objectId,
        externalId: externalId ?? this.externalId,
        createdAt: createdAt ?? this.createdAt,
      );
  PackageItem copyWithCompanion(PackageItemsCompanion data) {
    return PackageItem(
      id: data.id.present ? data.id.value : this.id,
      packageId: data.packageId.present ? data.packageId.value : this.packageId,
      objectType:
          data.objectType.present ? data.objectType.value : this.objectType,
      objectId: data.objectId.present ? data.objectId.value : this.objectId,
      externalId:
          data.externalId.present ? data.externalId.value : this.externalId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PackageItem(')
          ..write('id: $id, ')
          ..write('packageId: $packageId, ')
          ..write('objectType: $objectType, ')
          ..write('objectId: $objectId, ')
          ..write('externalId: $externalId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, packageId, objectType, objectId, externalId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PackageItem &&
          other.id == this.id &&
          other.packageId == this.packageId &&
          other.objectType == this.objectType &&
          other.objectId == this.objectId &&
          other.externalId == this.externalId &&
          other.createdAt == this.createdAt);
}

class PackageItemsCompanion extends UpdateCompanion<PackageItem> {
  final Value<String> id;
  final Value<String> packageId;
  final Value<String> objectType;
  final Value<String> objectId;
  final Value<String> externalId;
  final Value<int> createdAt;
  final Value<int> rowid;
  const PackageItemsCompanion({
    this.id = const Value.absent(),
    this.packageId = const Value.absent(),
    this.objectType = const Value.absent(),
    this.objectId = const Value.absent(),
    this.externalId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PackageItemsCompanion.insert({
    required String id,
    required String packageId,
    required String objectType,
    required String objectId,
    required String externalId,
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        packageId = Value(packageId),
        objectType = Value(objectType),
        objectId = Value(objectId),
        externalId = Value(externalId),
        createdAt = Value(createdAt);
  static Insertable<PackageItem> custom({
    Expression<String>? id,
    Expression<String>? packageId,
    Expression<String>? objectType,
    Expression<String>? objectId,
    Expression<String>? externalId,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (packageId != null) 'package_id': packageId,
      if (objectType != null) 'object_type': objectType,
      if (objectId != null) 'object_id': objectId,
      if (externalId != null) 'external_id': externalId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PackageItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? packageId,
      Value<String>? objectType,
      Value<String>? objectId,
      Value<String>? externalId,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return PackageItemsCompanion(
      id: id ?? this.id,
      packageId: packageId ?? this.packageId,
      objectType: objectType ?? this.objectType,
      objectId: objectId ?? this.objectId,
      externalId: externalId ?? this.externalId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (packageId.present) {
      map['package_id'] = Variable<String>(packageId.value);
    }
    if (objectType.present) {
      map['object_type'] = Variable<String>(objectType.value);
    }
    if (objectId.present) {
      map['object_id'] = Variable<String>(objectId.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PackageItemsCompanion(')
          ..write('id: $id, ')
          ..write('packageId: $packageId, ')
          ..write('objectType: $objectType, ')
          ..write('objectId: $objectId, ')
          ..write('externalId: $externalId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ThreadStatesTable extends ThreadStates
    with TableInfo<$ThreadStatesTable, ThreadState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ThreadStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _energyMeta = const VerificationMeta('energy');
  @override
  late final GeneratedColumn<int> energy = GeneratedColumn<int>(
      'energy', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _goalTextMeta =
      const VerificationMeta('goalText');
  @override
  late final GeneratedColumn<String> goalText = GeneratedColumn<String>(
      'goal_text', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _goalNodeIdMeta =
      const VerificationMeta('goalNodeId');
  @override
  late final GeneratedColumn<String> goalNodeId = GeneratedColumn<String>(
      'goal_node_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _goalPathMeta =
      const VerificationMeta('goalPath');
  @override
  late final GeneratedColumn<String> goalPath = GeneratedColumn<String>(
      'goal_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, energy, goalText, goalNodeId, goalPath, updatedAt, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'thread_states';
  @override
  VerificationContext validateIntegrity(Insertable<ThreadState> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('energy')) {
      context.handle(_energyMeta,
          energy.isAcceptableOrUnknown(data['energy']!, _energyMeta));
    }
    if (data.containsKey('goal_text')) {
      context.handle(_goalTextMeta,
          goalText.isAcceptableOrUnknown(data['goal_text']!, _goalTextMeta));
    }
    if (data.containsKey('goal_node_id')) {
      context.handle(
          _goalNodeIdMeta,
          goalNodeId.isAcceptableOrUnknown(
              data['goal_node_id']!, _goalNodeIdMeta));
    }
    if (data.containsKey('goal_path')) {
      context.handle(_goalPathMeta,
          goalPath.isAcceptableOrUnknown(data['goal_path']!, _goalPathMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ThreadState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ThreadState(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      energy: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}energy']),
      goalText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}goal_text']),
      goalNodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}goal_node_id']),
      goalPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}goal_path']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ThreadStatesTable createAlias(String alias) {
    return $ThreadStatesTable(attachedDatabase, alias);
  }
}

class ThreadState extends DataClass implements Insertable<ThreadState> {
  final int id;
  final int? energy;
  final String? goalText;
  final String? goalNodeId;
  final String? goalPath;
  final int? updatedAt;
  final int createdAt;
  const ThreadState(
      {required this.id,
      this.energy,
      this.goalText,
      this.goalNodeId,
      this.goalPath,
      this.updatedAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || energy != null) {
      map['energy'] = Variable<int>(energy);
    }
    if (!nullToAbsent || goalText != null) {
      map['goal_text'] = Variable<String>(goalText);
    }
    if (!nullToAbsent || goalNodeId != null) {
      map['goal_node_id'] = Variable<String>(goalNodeId);
    }
    if (!nullToAbsent || goalPath != null) {
      map['goal_path'] = Variable<String>(goalPath);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ThreadStatesCompanion toCompanion(bool nullToAbsent) {
    return ThreadStatesCompanion(
      id: Value(id),
      energy:
          energy == null && nullToAbsent ? const Value.absent() : Value(energy),
      goalText: goalText == null && nullToAbsent
          ? const Value.absent()
          : Value(goalText),
      goalNodeId: goalNodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(goalNodeId),
      goalPath: goalPath == null && nullToAbsent
          ? const Value.absent()
          : Value(goalPath),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      createdAt: Value(createdAt),
    );
  }

  factory ThreadState.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ThreadState(
      id: serializer.fromJson<int>(json['id']),
      energy: serializer.fromJson<int?>(json['energy']),
      goalText: serializer.fromJson<String?>(json['goalText']),
      goalNodeId: serializer.fromJson<String?>(json['goalNodeId']),
      goalPath: serializer.fromJson<String?>(json['goalPath']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'energy': serializer.toJson<int?>(energy),
      'goalText': serializer.toJson<String?>(goalText),
      'goalNodeId': serializer.toJson<String?>(goalNodeId),
      'goalPath': serializer.toJson<String?>(goalPath),
      'updatedAt': serializer.toJson<int?>(updatedAt),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ThreadState copyWith(
          {int? id,
          Value<int?> energy = const Value.absent(),
          Value<String?> goalText = const Value.absent(),
          Value<String?> goalNodeId = const Value.absent(),
          Value<String?> goalPath = const Value.absent(),
          Value<int?> updatedAt = const Value.absent(),
          int? createdAt}) =>
      ThreadState(
        id: id ?? this.id,
        energy: energy.present ? energy.value : this.energy,
        goalText: goalText.present ? goalText.value : this.goalText,
        goalNodeId: goalNodeId.present ? goalNodeId.value : this.goalNodeId,
        goalPath: goalPath.present ? goalPath.value : this.goalPath,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
        createdAt: createdAt ?? this.createdAt,
      );
  ThreadState copyWithCompanion(ThreadStatesCompanion data) {
    return ThreadState(
      id: data.id.present ? data.id.value : this.id,
      energy: data.energy.present ? data.energy.value : this.energy,
      goalText: data.goalText.present ? data.goalText.value : this.goalText,
      goalNodeId:
          data.goalNodeId.present ? data.goalNodeId.value : this.goalNodeId,
      goalPath: data.goalPath.present ? data.goalPath.value : this.goalPath,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ThreadState(')
          ..write('id: $id, ')
          ..write('energy: $energy, ')
          ..write('goalText: $goalText, ')
          ..write('goalNodeId: $goalNodeId, ')
          ..write('goalPath: $goalPath, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, energy, goalText, goalNodeId, goalPath, updatedAt, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThreadState &&
          other.id == this.id &&
          other.energy == this.energy &&
          other.goalText == this.goalText &&
          other.goalNodeId == this.goalNodeId &&
          other.goalPath == this.goalPath &&
          other.updatedAt == this.updatedAt &&
          other.createdAt == this.createdAt);
}

class ThreadStatesCompanion extends UpdateCompanion<ThreadState> {
  final Value<int> id;
  final Value<int?> energy;
  final Value<String?> goalText;
  final Value<String?> goalNodeId;
  final Value<String?> goalPath;
  final Value<int?> updatedAt;
  final Value<int> createdAt;
  const ThreadStatesCompanion({
    this.id = const Value.absent(),
    this.energy = const Value.absent(),
    this.goalText = const Value.absent(),
    this.goalNodeId = const Value.absent(),
    this.goalPath = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ThreadStatesCompanion.insert({
    this.id = const Value.absent(),
    this.energy = const Value.absent(),
    this.goalText = const Value.absent(),
    this.goalNodeId = const Value.absent(),
    this.goalPath = const Value.absent(),
    this.updatedAt = const Value.absent(),
    required int createdAt,
  }) : createdAt = Value(createdAt);
  static Insertable<ThreadState> custom({
    Expression<int>? id,
    Expression<int>? energy,
    Expression<String>? goalText,
    Expression<String>? goalNodeId,
    Expression<String>? goalPath,
    Expression<int>? updatedAt,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (energy != null) 'energy': energy,
      if (goalText != null) 'goal_text': goalText,
      if (goalNodeId != null) 'goal_node_id': goalNodeId,
      if (goalPath != null) 'goal_path': goalPath,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ThreadStatesCompanion copyWith(
      {Value<int>? id,
      Value<int?>? energy,
      Value<String?>? goalText,
      Value<String?>? goalNodeId,
      Value<String?>? goalPath,
      Value<int?>? updatedAt,
      Value<int>? createdAt}) {
    return ThreadStatesCompanion(
      id: id ?? this.id,
      energy: energy ?? this.energy,
      goalText: goalText ?? this.goalText,
      goalNodeId: goalNodeId ?? this.goalNodeId,
      goalPath: goalPath ?? this.goalPath,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (energy.present) {
      map['energy'] = Variable<int>(energy.value);
    }
    if (goalText.present) {
      map['goal_text'] = Variable<String>(goalText.value);
    }
    if (goalNodeId.present) {
      map['goal_node_id'] = Variable<String>(goalNodeId.value);
    }
    if (goalPath.present) {
      map['goal_path'] = Variable<String>(goalPath.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThreadStatesCompanion(')
          ..write('id: $id, ')
          ..write('energy: $energy, ')
          ..write('goalText: $goalText, ')
          ..write('goalNodeId: $goalNodeId, ')
          ..write('goalPath: $goalPath, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $TaskTemplatesTable extends TaskTemplates
    with TableInfo<$TaskTemplatesTable, TaskTemplate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskTemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _estimateMinutesMeta =
      const VerificationMeta('estimateMinutes');
  @override
  late final GeneratedColumn<int> estimateMinutes = GeneratedColumn<int>(
      'estimate_minutes', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _energyRequiredMeta =
      const VerificationMeta('energyRequired');
  @override
  late final GeneratedColumn<int> energyRequired = GeneratedColumn<int>(
      'energy_required', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, estimateMinutes, energyRequired, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_templates';
  @override
  VerificationContext validateIntegrity(Insertable<TaskTemplate> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('estimate_minutes')) {
      context.handle(
          _estimateMinutesMeta,
          estimateMinutes.isAcceptableOrUnknown(
              data['estimate_minutes']!, _estimateMinutesMeta));
    }
    if (data.containsKey('energy_required')) {
      context.handle(
          _energyRequiredMeta,
          energyRequired.isAcceptableOrUnknown(
              data['energy_required']!, _energyRequiredMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskTemplate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskTemplate(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      estimateMinutes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}estimate_minutes']),
      energyRequired: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}energy_required']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $TaskTemplatesTable createAlias(String alias) {
    return $TaskTemplatesTable(attachedDatabase, alias);
  }
}

class TaskTemplate extends DataClass implements Insertable<TaskTemplate> {
  final String id;
  final String name;
  final int? estimateMinutes;
  final int? energyRequired;
  final int createdAt;
  final int updatedAt;
  const TaskTemplate(
      {required this.id,
      required this.name,
      this.estimateMinutes,
      this.energyRequired,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || estimateMinutes != null) {
      map['estimate_minutes'] = Variable<int>(estimateMinutes);
    }
    if (!nullToAbsent || energyRequired != null) {
      map['energy_required'] = Variable<int>(energyRequired);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  TaskTemplatesCompanion toCompanion(bool nullToAbsent) {
    return TaskTemplatesCompanion(
      id: Value(id),
      name: Value(name),
      estimateMinutes: estimateMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimateMinutes),
      energyRequired: energyRequired == null && nullToAbsent
          ? const Value.absent()
          : Value(energyRequired),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TaskTemplate.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskTemplate(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      estimateMinutes: serializer.fromJson<int?>(json['estimateMinutes']),
      energyRequired: serializer.fromJson<int?>(json['energyRequired']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'estimateMinutes': serializer.toJson<int?>(estimateMinutes),
      'energyRequired': serializer.toJson<int?>(energyRequired),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  TaskTemplate copyWith(
          {String? id,
          String? name,
          Value<int?> estimateMinutes = const Value.absent(),
          Value<int?> energyRequired = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      TaskTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        estimateMinutes: estimateMinutes.present
            ? estimateMinutes.value
            : this.estimateMinutes,
        energyRequired:
            energyRequired.present ? energyRequired.value : this.energyRequired,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  TaskTemplate copyWithCompanion(TaskTemplatesCompanion data) {
    return TaskTemplate(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      estimateMinutes: data.estimateMinutes.present
          ? data.estimateMinutes.value
          : this.estimateMinutes,
      energyRequired: data.energyRequired.present
          ? data.energyRequired.value
          : this.energyRequired,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskTemplate(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('estimateMinutes: $estimateMinutes, ')
          ..write('energyRequired: $energyRequired, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, name, estimateMinutes, energyRequired, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskTemplate &&
          other.id == this.id &&
          other.name == this.name &&
          other.estimateMinutes == this.estimateMinutes &&
          other.energyRequired == this.energyRequired &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TaskTemplatesCompanion extends UpdateCompanion<TaskTemplate> {
  final Value<String> id;
  final Value<String> name;
  final Value<int?> estimateMinutes;
  final Value<int?> energyRequired;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const TaskTemplatesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.estimateMinutes = const Value.absent(),
    this.energyRequired = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskTemplatesCompanion.insert({
    required String id,
    required String name,
    this.estimateMinutes = const Value.absent(),
    this.energyRequired = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<TaskTemplate> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? estimateMinutes,
    Expression<int>? energyRequired,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (estimateMinutes != null) 'estimate_minutes': estimateMinutes,
      if (energyRequired != null) 'energy_required': energyRequired,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskTemplatesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<int?>? estimateMinutes,
      Value<int?>? energyRequired,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return TaskTemplatesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      estimateMinutes: estimateMinutes ?? this.estimateMinutes,
      energyRequired: energyRequired ?? this.energyRequired,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (estimateMinutes.present) {
      map['estimate_minutes'] = Variable<int>(estimateMinutes.value);
    }
    if (energyRequired.present) {
      map['energy_required'] = Variable<int>(energyRequired.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskTemplatesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('estimateMinutes: $estimateMinutes, ')
          ..write('energyRequired: $energyRequired, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CompletionLogsTable extends CompletionLogs
    with TableInfo<$CompletionLogsTable, CompletionLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CompletionLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
      'task_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 300),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _tagIdsMeta = const VerificationMeta('tagIds');
  @override
  late final GeneratedColumn<String> tagIds = GeneratedColumn<String>(
      'tag_ids', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _tagPathsMeta =
      const VerificationMeta('tagPaths');
  @override
  late final GeneratedColumn<String> tagPaths = GeneratedColumn<String>(
      'tag_paths', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _estimateMinutesMeta =
      const VerificationMeta('estimateMinutes');
  @override
  late final GeneratedColumn<int> estimateMinutes = GeneratedColumn<int>(
      'estimate_minutes', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _energyRequiredMeta =
      const VerificationMeta('energyRequired');
  @override
  late final GeneratedColumn<int> energyRequired = GeneratedColumn<int>(
      'energy_required', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<int> completedAt = GeneratedColumn<int>(
      'completed_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _actualMinutesMeta =
      const VerificationMeta('actualMinutes');
  @override
  late final GeneratedColumn<int> actualMinutes = GeneratedColumn<int>(
      'actual_minutes', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _includeInModelMeta =
      const VerificationMeta('includeInModel');
  @override
  late final GeneratedColumn<bool> includeInModel = GeneratedColumn<bool>(
      'include_in_model', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("include_in_model" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _durationSuspiciousMeta =
      const VerificationMeta('durationSuspicious');
  @override
  late final GeneratedColumn<bool> durationSuspicious = GeneratedColumn<bool>(
      'duration_suspicious', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("duration_suspicious" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        taskId,
        title,
        tagIds,
        tagPaths,
        estimateMinutes,
        energyRequired,
        completedAt,
        actualMinutes,
        includeInModel,
        durationSuspicious,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'completion_logs';
  @override
  VerificationContext validateIntegrity(Insertable<CompletionLog> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(_taskIdMeta,
          taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta));
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('tag_ids')) {
      context.handle(_tagIdsMeta,
          tagIds.isAcceptableOrUnknown(data['tag_ids']!, _tagIdsMeta));
    }
    if (data.containsKey('tag_paths')) {
      context.handle(_tagPathsMeta,
          tagPaths.isAcceptableOrUnknown(data['tag_paths']!, _tagPathsMeta));
    }
    if (data.containsKey('estimate_minutes')) {
      context.handle(
          _estimateMinutesMeta,
          estimateMinutes.isAcceptableOrUnknown(
              data['estimate_minutes']!, _estimateMinutesMeta));
    }
    if (data.containsKey('energy_required')) {
      context.handle(
          _energyRequiredMeta,
          energyRequired.isAcceptableOrUnknown(
              data['energy_required']!, _energyRequiredMeta));
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    } else if (isInserting) {
      context.missing(_completedAtMeta);
    }
    if (data.containsKey('actual_minutes')) {
      context.handle(
          _actualMinutesMeta,
          actualMinutes.isAcceptableOrUnknown(
              data['actual_minutes']!, _actualMinutesMeta));
    }
    if (data.containsKey('include_in_model')) {
      context.handle(
          _includeInModelMeta,
          includeInModel.isAcceptableOrUnknown(
              data['include_in_model']!, _includeInModelMeta));
    }
    if (data.containsKey('duration_suspicious')) {
      context.handle(
          _durationSuspiciousMeta,
          durationSuspicious.isAcceptableOrUnknown(
              data['duration_suspicious']!, _durationSuspiciousMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CompletionLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CompletionLog(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      taskId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}task_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      tagIds: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tag_ids']),
      tagPaths: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tag_paths']),
      estimateMinutes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}estimate_minutes']),
      energyRequired: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}energy_required']),
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}completed_at'])!,
      actualMinutes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}actual_minutes']),
      includeInModel: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}include_in_model'])!,
      durationSuspicious: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}duration_suspicious'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $CompletionLogsTable createAlias(String alias) {
    return $CompletionLogsTable(attachedDatabase, alias);
  }
}

class CompletionLog extends DataClass implements Insertable<CompletionLog> {
  final String id;
  final String taskId;
  final String title;
  final String? tagIds;
  final String? tagPaths;
  final int? estimateMinutes;
  final int? energyRequired;
  final int completedAt;

  /// v3 (blueprint 2.6): completion moment - start moment, whole minutes.
  final int? actualMinutes;

  /// v3: whether the user lets this record feed the duration model. A record
  /// that looks interrupted defaults to false but stays switchable.
  final bool includeInModel;

  /// v3: set when the anomaly rule flagged the record (kept for transparency).
  final bool durationSuspicious;
  final int createdAt;
  const CompletionLog(
      {required this.id,
      required this.taskId,
      required this.title,
      this.tagIds,
      this.tagPaths,
      this.estimateMinutes,
      this.energyRequired,
      required this.completedAt,
      this.actualMinutes,
      required this.includeInModel,
      required this.durationSuspicious,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || tagIds != null) {
      map['tag_ids'] = Variable<String>(tagIds);
    }
    if (!nullToAbsent || tagPaths != null) {
      map['tag_paths'] = Variable<String>(tagPaths);
    }
    if (!nullToAbsent || estimateMinutes != null) {
      map['estimate_minutes'] = Variable<int>(estimateMinutes);
    }
    if (!nullToAbsent || energyRequired != null) {
      map['energy_required'] = Variable<int>(energyRequired);
    }
    map['completed_at'] = Variable<int>(completedAt);
    if (!nullToAbsent || actualMinutes != null) {
      map['actual_minutes'] = Variable<int>(actualMinutes);
    }
    map['include_in_model'] = Variable<bool>(includeInModel);
    map['duration_suspicious'] = Variable<bool>(durationSuspicious);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  CompletionLogsCompanion toCompanion(bool nullToAbsent) {
    return CompletionLogsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      title: Value(title),
      tagIds:
          tagIds == null && nullToAbsent ? const Value.absent() : Value(tagIds),
      tagPaths: tagPaths == null && nullToAbsent
          ? const Value.absent()
          : Value(tagPaths),
      estimateMinutes: estimateMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimateMinutes),
      energyRequired: energyRequired == null && nullToAbsent
          ? const Value.absent()
          : Value(energyRequired),
      completedAt: Value(completedAt),
      actualMinutes: actualMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(actualMinutes),
      includeInModel: Value(includeInModel),
      durationSuspicious: Value(durationSuspicious),
      createdAt: Value(createdAt),
    );
  }

  factory CompletionLog.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CompletionLog(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      title: serializer.fromJson<String>(json['title']),
      tagIds: serializer.fromJson<String?>(json['tagIds']),
      tagPaths: serializer.fromJson<String?>(json['tagPaths']),
      estimateMinutes: serializer.fromJson<int?>(json['estimateMinutes']),
      energyRequired: serializer.fromJson<int?>(json['energyRequired']),
      completedAt: serializer.fromJson<int>(json['completedAt']),
      actualMinutes: serializer.fromJson<int?>(json['actualMinutes']),
      includeInModel: serializer.fromJson<bool>(json['includeInModel']),
      durationSuspicious: serializer.fromJson<bool>(json['durationSuspicious']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'title': serializer.toJson<String>(title),
      'tagIds': serializer.toJson<String?>(tagIds),
      'tagPaths': serializer.toJson<String?>(tagPaths),
      'estimateMinutes': serializer.toJson<int?>(estimateMinutes),
      'energyRequired': serializer.toJson<int?>(energyRequired),
      'completedAt': serializer.toJson<int>(completedAt),
      'actualMinutes': serializer.toJson<int?>(actualMinutes),
      'includeInModel': serializer.toJson<bool>(includeInModel),
      'durationSuspicious': serializer.toJson<bool>(durationSuspicious),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  CompletionLog copyWith(
          {String? id,
          String? taskId,
          String? title,
          Value<String?> tagIds = const Value.absent(),
          Value<String?> tagPaths = const Value.absent(),
          Value<int?> estimateMinutes = const Value.absent(),
          Value<int?> energyRequired = const Value.absent(),
          int? completedAt,
          Value<int?> actualMinutes = const Value.absent(),
          bool? includeInModel,
          bool? durationSuspicious,
          int? createdAt}) =>
      CompletionLog(
        id: id ?? this.id,
        taskId: taskId ?? this.taskId,
        title: title ?? this.title,
        tagIds: tagIds.present ? tagIds.value : this.tagIds,
        tagPaths: tagPaths.present ? tagPaths.value : this.tagPaths,
        estimateMinutes: estimateMinutes.present
            ? estimateMinutes.value
            : this.estimateMinutes,
        energyRequired:
            energyRequired.present ? energyRequired.value : this.energyRequired,
        completedAt: completedAt ?? this.completedAt,
        actualMinutes:
            actualMinutes.present ? actualMinutes.value : this.actualMinutes,
        includeInModel: includeInModel ?? this.includeInModel,
        durationSuspicious: durationSuspicious ?? this.durationSuspicious,
        createdAt: createdAt ?? this.createdAt,
      );
  CompletionLog copyWithCompanion(CompletionLogsCompanion data) {
    return CompletionLog(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      title: data.title.present ? data.title.value : this.title,
      tagIds: data.tagIds.present ? data.tagIds.value : this.tagIds,
      tagPaths: data.tagPaths.present ? data.tagPaths.value : this.tagPaths,
      estimateMinutes: data.estimateMinutes.present
          ? data.estimateMinutes.value
          : this.estimateMinutes,
      energyRequired: data.energyRequired.present
          ? data.energyRequired.value
          : this.energyRequired,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
      actualMinutes: data.actualMinutes.present
          ? data.actualMinutes.value
          : this.actualMinutes,
      includeInModel: data.includeInModel.present
          ? data.includeInModel.value
          : this.includeInModel,
      durationSuspicious: data.durationSuspicious.present
          ? data.durationSuspicious.value
          : this.durationSuspicious,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CompletionLog(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('title: $title, ')
          ..write('tagIds: $tagIds, ')
          ..write('tagPaths: $tagPaths, ')
          ..write('estimateMinutes: $estimateMinutes, ')
          ..write('energyRequired: $energyRequired, ')
          ..write('completedAt: $completedAt, ')
          ..write('actualMinutes: $actualMinutes, ')
          ..write('includeInModel: $includeInModel, ')
          ..write('durationSuspicious: $durationSuspicious, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      taskId,
      title,
      tagIds,
      tagPaths,
      estimateMinutes,
      energyRequired,
      completedAt,
      actualMinutes,
      includeInModel,
      durationSuspicious,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CompletionLog &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.title == this.title &&
          other.tagIds == this.tagIds &&
          other.tagPaths == this.tagPaths &&
          other.estimateMinutes == this.estimateMinutes &&
          other.energyRequired == this.energyRequired &&
          other.completedAt == this.completedAt &&
          other.actualMinutes == this.actualMinutes &&
          other.includeInModel == this.includeInModel &&
          other.durationSuspicious == this.durationSuspicious &&
          other.createdAt == this.createdAt);
}

class CompletionLogsCompanion extends UpdateCompanion<CompletionLog> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> title;
  final Value<String?> tagIds;
  final Value<String?> tagPaths;
  final Value<int?> estimateMinutes;
  final Value<int?> energyRequired;
  final Value<int> completedAt;
  final Value<int?> actualMinutes;
  final Value<bool> includeInModel;
  final Value<bool> durationSuspicious;
  final Value<int> createdAt;
  final Value<int> rowid;
  const CompletionLogsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.title = const Value.absent(),
    this.tagIds = const Value.absent(),
    this.tagPaths = const Value.absent(),
    this.estimateMinutes = const Value.absent(),
    this.energyRequired = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.actualMinutes = const Value.absent(),
    this.includeInModel = const Value.absent(),
    this.durationSuspicious = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CompletionLogsCompanion.insert({
    required String id,
    required String taskId,
    required String title,
    this.tagIds = const Value.absent(),
    this.tagPaths = const Value.absent(),
    this.estimateMinutes = const Value.absent(),
    this.energyRequired = const Value.absent(),
    required int completedAt,
    this.actualMinutes = const Value.absent(),
    this.includeInModel = const Value.absent(),
    this.durationSuspicious = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        taskId = Value(taskId),
        title = Value(title),
        completedAt = Value(completedAt),
        createdAt = Value(createdAt);
  static Insertable<CompletionLog> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? title,
    Expression<String>? tagIds,
    Expression<String>? tagPaths,
    Expression<int>? estimateMinutes,
    Expression<int>? energyRequired,
    Expression<int>? completedAt,
    Expression<int>? actualMinutes,
    Expression<bool>? includeInModel,
    Expression<bool>? durationSuspicious,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (title != null) 'title': title,
      if (tagIds != null) 'tag_ids': tagIds,
      if (tagPaths != null) 'tag_paths': tagPaths,
      if (estimateMinutes != null) 'estimate_minutes': estimateMinutes,
      if (energyRequired != null) 'energy_required': energyRequired,
      if (completedAt != null) 'completed_at': completedAt,
      if (actualMinutes != null) 'actual_minutes': actualMinutes,
      if (includeInModel != null) 'include_in_model': includeInModel,
      if (durationSuspicious != null) 'duration_suspicious': durationSuspicious,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CompletionLogsCompanion copyWith(
      {Value<String>? id,
      Value<String>? taskId,
      Value<String>? title,
      Value<String?>? tagIds,
      Value<String?>? tagPaths,
      Value<int?>? estimateMinutes,
      Value<int?>? energyRequired,
      Value<int>? completedAt,
      Value<int?>? actualMinutes,
      Value<bool>? includeInModel,
      Value<bool>? durationSuspicious,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return CompletionLogsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      tagIds: tagIds ?? this.tagIds,
      tagPaths: tagPaths ?? this.tagPaths,
      estimateMinutes: estimateMinutes ?? this.estimateMinutes,
      energyRequired: energyRequired ?? this.energyRequired,
      completedAt: completedAt ?? this.completedAt,
      actualMinutes: actualMinutes ?? this.actualMinutes,
      includeInModel: includeInModel ?? this.includeInModel,
      durationSuspicious: durationSuspicious ?? this.durationSuspicious,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (tagIds.present) {
      map['tag_ids'] = Variable<String>(tagIds.value);
    }
    if (tagPaths.present) {
      map['tag_paths'] = Variable<String>(tagPaths.value);
    }
    if (estimateMinutes.present) {
      map['estimate_minutes'] = Variable<int>(estimateMinutes.value);
    }
    if (energyRequired.present) {
      map['energy_required'] = Variable<int>(energyRequired.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<int>(completedAt.value);
    }
    if (actualMinutes.present) {
      map['actual_minutes'] = Variable<int>(actualMinutes.value);
    }
    if (includeInModel.present) {
      map['include_in_model'] = Variable<bool>(includeInModel.value);
    }
    if (durationSuspicious.present) {
      map['duration_suspicious'] = Variable<bool>(durationSuspicious.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CompletionLogsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('title: $title, ')
          ..write('tagIds: $tagIds, ')
          ..write('tagPaths: $tagPaths, ')
          ..write('estimateMinutes: $estimateMinutes, ')
          ..write('energyRequired: $energyRequired, ')
          ..write('completedAt: $completedAt, ')
          ..write('actualMinutes: $actualMinutes, ')
          ..write('includeInModel: $includeInModel, ')
          ..write('durationSuspicious: $durationSuspicious, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClozeSlotsTable extends ClozeSlots
    with TableInfo<$ClozeSlotsTable, ClozeSlot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClozeSlotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _knowledgePointIdMeta =
      const VerificationMeta('knowledgePointId');
  @override
  late final GeneratedColumn<String> knowledgePointId = GeneratedColumn<String>(
      'knowledge_point_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _slotKeyMeta =
      const VerificationMeta('slotKey');
  @override
  late final GeneratedColumn<String> slotKey = GeneratedColumn<String>(
      'slot_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _definitionMeta =
      const VerificationMeta('definition');
  @override
  late final GeneratedColumn<String> definition = GeneratedColumn<String>(
      'definition', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _exhaustedMeta =
      const VerificationMeta('exhausted');
  @override
  late final GeneratedColumn<int> exhausted = GeneratedColumn<int>(
      'exhausted', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        knowledgePointId,
        slotKey,
        definition,
        exhausted,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cloze_slots';
  @override
  VerificationContext validateIntegrity(Insertable<ClozeSlot> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('knowledge_point_id')) {
      context.handle(
          _knowledgePointIdMeta,
          knowledgePointId.isAcceptableOrUnknown(
              data['knowledge_point_id']!, _knowledgePointIdMeta));
    } else if (isInserting) {
      context.missing(_knowledgePointIdMeta);
    }
    if (data.containsKey('slot_key')) {
      context.handle(_slotKeyMeta,
          slotKey.isAcceptableOrUnknown(data['slot_key']!, _slotKeyMeta));
    } else if (isInserting) {
      context.missing(_slotKeyMeta);
    }
    if (data.containsKey('definition')) {
      context.handle(
          _definitionMeta,
          definition.isAcceptableOrUnknown(
              data['definition']!, _definitionMeta));
    } else if (isInserting) {
      context.missing(_definitionMeta);
    }
    if (data.containsKey('exhausted')) {
      context.handle(_exhaustedMeta,
          exhausted.isAcceptableOrUnknown(data['exhausted']!, _exhaustedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {knowledgePointId, slotKey},
      ];
  @override
  ClozeSlot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClozeSlot(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      knowledgePointId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}knowledge_point_id'])!,
      slotKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}slot_key'])!,
      definition: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}definition'])!,
      exhausted: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}exhausted'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ClozeSlotsTable createAlias(String alias) {
    return $ClozeSlotsTable(attachedDatabase, alias);
  }
}

class ClozeSlot extends DataClass implements Insertable<ClozeSlot> {
  final String id;
  final String knowledgePointId;
  final String slotKey;
  final String definition;
  final int exhausted;
  final int createdAt;
  final int updatedAt;
  const ClozeSlot(
      {required this.id,
      required this.knowledgePointId,
      required this.slotKey,
      required this.definition,
      required this.exhausted,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['knowledge_point_id'] = Variable<String>(knowledgePointId);
    map['slot_key'] = Variable<String>(slotKey);
    map['definition'] = Variable<String>(definition);
    map['exhausted'] = Variable<int>(exhausted);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ClozeSlotsCompanion toCompanion(bool nullToAbsent) {
    return ClozeSlotsCompanion(
      id: Value(id),
      knowledgePointId: Value(knowledgePointId),
      slotKey: Value(slotKey),
      definition: Value(definition),
      exhausted: Value(exhausted),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ClozeSlot.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClozeSlot(
      id: serializer.fromJson<String>(json['id']),
      knowledgePointId: serializer.fromJson<String>(json['knowledgePointId']),
      slotKey: serializer.fromJson<String>(json['slotKey']),
      definition: serializer.fromJson<String>(json['definition']),
      exhausted: serializer.fromJson<int>(json['exhausted']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'knowledgePointId': serializer.toJson<String>(knowledgePointId),
      'slotKey': serializer.toJson<String>(slotKey),
      'definition': serializer.toJson<String>(definition),
      'exhausted': serializer.toJson<int>(exhausted),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ClozeSlot copyWith(
          {String? id,
          String? knowledgePointId,
          String? slotKey,
          String? definition,
          int? exhausted,
          int? createdAt,
          int? updatedAt}) =>
      ClozeSlot(
        id: id ?? this.id,
        knowledgePointId: knowledgePointId ?? this.knowledgePointId,
        slotKey: slotKey ?? this.slotKey,
        definition: definition ?? this.definition,
        exhausted: exhausted ?? this.exhausted,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  ClozeSlot copyWithCompanion(ClozeSlotsCompanion data) {
    return ClozeSlot(
      id: data.id.present ? data.id.value : this.id,
      knowledgePointId: data.knowledgePointId.present
          ? data.knowledgePointId.value
          : this.knowledgePointId,
      slotKey: data.slotKey.present ? data.slotKey.value : this.slotKey,
      definition:
          data.definition.present ? data.definition.value : this.definition,
      exhausted: data.exhausted.present ? data.exhausted.value : this.exhausted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClozeSlot(')
          ..write('id: $id, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('slotKey: $slotKey, ')
          ..write('definition: $definition, ')
          ..write('exhausted: $exhausted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, knowledgePointId, slotKey, definition,
      exhausted, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClozeSlot &&
          other.id == this.id &&
          other.knowledgePointId == this.knowledgePointId &&
          other.slotKey == this.slotKey &&
          other.definition == this.definition &&
          other.exhausted == this.exhausted &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ClozeSlotsCompanion extends UpdateCompanion<ClozeSlot> {
  final Value<String> id;
  final Value<String> knowledgePointId;
  final Value<String> slotKey;
  final Value<String> definition;
  final Value<int> exhausted;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ClozeSlotsCompanion({
    this.id = const Value.absent(),
    this.knowledgePointId = const Value.absent(),
    this.slotKey = const Value.absent(),
    this.definition = const Value.absent(),
    this.exhausted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClozeSlotsCompanion.insert({
    required String id,
    required String knowledgePointId,
    required String slotKey,
    required String definition,
    this.exhausted = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        knowledgePointId = Value(knowledgePointId),
        slotKey = Value(slotKey),
        definition = Value(definition),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<ClozeSlot> custom({
    Expression<String>? id,
    Expression<String>? knowledgePointId,
    Expression<String>? slotKey,
    Expression<String>? definition,
    Expression<int>? exhausted,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (knowledgePointId != null) 'knowledge_point_id': knowledgePointId,
      if (slotKey != null) 'slot_key': slotKey,
      if (definition != null) 'definition': definition,
      if (exhausted != null) 'exhausted': exhausted,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClozeSlotsCompanion copyWith(
      {Value<String>? id,
      Value<String>? knowledgePointId,
      Value<String>? slotKey,
      Value<String>? definition,
      Value<int>? exhausted,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return ClozeSlotsCompanion(
      id: id ?? this.id,
      knowledgePointId: knowledgePointId ?? this.knowledgePointId,
      slotKey: slotKey ?? this.slotKey,
      definition: definition ?? this.definition,
      exhausted: exhausted ?? this.exhausted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (knowledgePointId.present) {
      map['knowledge_point_id'] = Variable<String>(knowledgePointId.value);
    }
    if (slotKey.present) {
      map['slot_key'] = Variable<String>(slotKey.value);
    }
    if (definition.present) {
      map['definition'] = Variable<String>(definition.value);
    }
    if (exhausted.present) {
      map['exhausted'] = Variable<int>(exhausted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClozeSlotsCompanion(')
          ..write('id: $id, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('slotKey: $slotKey, ')
          ..write('definition: $definition, ')
          ..write('exhausted: $exhausted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClozeHistoryTable extends ClozeHistory
    with TableInfo<$ClozeHistoryTable, ClozeHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClozeHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _knowledgePointIdMeta =
      const VerificationMeta('knowledgePointId');
  @override
  late final GeneratedColumn<String> knowledgePointId = GeneratedColumn<String>(
      'knowledge_point_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _slotKeyMeta =
      const VerificationMeta('slotKey');
  @override
  late final GeneratedColumn<String> slotKey = GeneratedColumn<String>(
      'slot_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _correctMeta =
      const VerificationMeta('correct');
  @override
  late final GeneratedColumn<int> correct = GeneratedColumn<int>(
      'correct', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _usedAtMeta = const VerificationMeta('usedAt');
  @override
  late final GeneratedColumn<int> usedAt = GeneratedColumn<int>(
      'used_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, knowledgePointId, slotKey, correct, usedAt, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cloze_history';
  @override
  VerificationContext validateIntegrity(Insertable<ClozeHistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('knowledge_point_id')) {
      context.handle(
          _knowledgePointIdMeta,
          knowledgePointId.isAcceptableOrUnknown(
              data['knowledge_point_id']!, _knowledgePointIdMeta));
    } else if (isInserting) {
      context.missing(_knowledgePointIdMeta);
    }
    if (data.containsKey('slot_key')) {
      context.handle(_slotKeyMeta,
          slotKey.isAcceptableOrUnknown(data['slot_key']!, _slotKeyMeta));
    } else if (isInserting) {
      context.missing(_slotKeyMeta);
    }
    if (data.containsKey('correct')) {
      context.handle(_correctMeta,
          correct.isAcceptableOrUnknown(data['correct']!, _correctMeta));
    }
    if (data.containsKey('used_at')) {
      context.handle(_usedAtMeta,
          usedAt.isAcceptableOrUnknown(data['used_at']!, _usedAtMeta));
    } else if (isInserting) {
      context.missing(_usedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClozeHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClozeHistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      knowledgePointId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}knowledge_point_id'])!,
      slotKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}slot_key'])!,
      correct: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}correct'])!,
      usedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}used_at'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ClozeHistoryTable createAlias(String alias) {
    return $ClozeHistoryTable(attachedDatabase, alias);
  }
}

class ClozeHistoryData extends DataClass
    implements Insertable<ClozeHistoryData> {
  final String id;
  final String knowledgePointId;
  final String slotKey;
  final int correct;
  final int usedAt;
  final int createdAt;
  const ClozeHistoryData(
      {required this.id,
      required this.knowledgePointId,
      required this.slotKey,
      required this.correct,
      required this.usedAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['knowledge_point_id'] = Variable<String>(knowledgePointId);
    map['slot_key'] = Variable<String>(slotKey);
    map['correct'] = Variable<int>(correct);
    map['used_at'] = Variable<int>(usedAt);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ClozeHistoryCompanion toCompanion(bool nullToAbsent) {
    return ClozeHistoryCompanion(
      id: Value(id),
      knowledgePointId: Value(knowledgePointId),
      slotKey: Value(slotKey),
      correct: Value(correct),
      usedAt: Value(usedAt),
      createdAt: Value(createdAt),
    );
  }

  factory ClozeHistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClozeHistoryData(
      id: serializer.fromJson<String>(json['id']),
      knowledgePointId: serializer.fromJson<String>(json['knowledgePointId']),
      slotKey: serializer.fromJson<String>(json['slotKey']),
      correct: serializer.fromJson<int>(json['correct']),
      usedAt: serializer.fromJson<int>(json['usedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'knowledgePointId': serializer.toJson<String>(knowledgePointId),
      'slotKey': serializer.toJson<String>(slotKey),
      'correct': serializer.toJson<int>(correct),
      'usedAt': serializer.toJson<int>(usedAt),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ClozeHistoryData copyWith(
          {String? id,
          String? knowledgePointId,
          String? slotKey,
          int? correct,
          int? usedAt,
          int? createdAt}) =>
      ClozeHistoryData(
        id: id ?? this.id,
        knowledgePointId: knowledgePointId ?? this.knowledgePointId,
        slotKey: slotKey ?? this.slotKey,
        correct: correct ?? this.correct,
        usedAt: usedAt ?? this.usedAt,
        createdAt: createdAt ?? this.createdAt,
      );
  ClozeHistoryData copyWithCompanion(ClozeHistoryCompanion data) {
    return ClozeHistoryData(
      id: data.id.present ? data.id.value : this.id,
      knowledgePointId: data.knowledgePointId.present
          ? data.knowledgePointId.value
          : this.knowledgePointId,
      slotKey: data.slotKey.present ? data.slotKey.value : this.slotKey,
      correct: data.correct.present ? data.correct.value : this.correct,
      usedAt: data.usedAt.present ? data.usedAt.value : this.usedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClozeHistoryData(')
          ..write('id: $id, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('slotKey: $slotKey, ')
          ..write('correct: $correct, ')
          ..write('usedAt: $usedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, knowledgePointId, slotKey, correct, usedAt, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClozeHistoryData &&
          other.id == this.id &&
          other.knowledgePointId == this.knowledgePointId &&
          other.slotKey == this.slotKey &&
          other.correct == this.correct &&
          other.usedAt == this.usedAt &&
          other.createdAt == this.createdAt);
}

class ClozeHistoryCompanion extends UpdateCompanion<ClozeHistoryData> {
  final Value<String> id;
  final Value<String> knowledgePointId;
  final Value<String> slotKey;
  final Value<int> correct;
  final Value<int> usedAt;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ClozeHistoryCompanion({
    this.id = const Value.absent(),
    this.knowledgePointId = const Value.absent(),
    this.slotKey = const Value.absent(),
    this.correct = const Value.absent(),
    this.usedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClozeHistoryCompanion.insert({
    required String id,
    required String knowledgePointId,
    required String slotKey,
    this.correct = const Value.absent(),
    required int usedAt,
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        knowledgePointId = Value(knowledgePointId),
        slotKey = Value(slotKey),
        usedAt = Value(usedAt),
        createdAt = Value(createdAt);
  static Insertable<ClozeHistoryData> custom({
    Expression<String>? id,
    Expression<String>? knowledgePointId,
    Expression<String>? slotKey,
    Expression<int>? correct,
    Expression<int>? usedAt,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (knowledgePointId != null) 'knowledge_point_id': knowledgePointId,
      if (slotKey != null) 'slot_key': slotKey,
      if (correct != null) 'correct': correct,
      if (usedAt != null) 'used_at': usedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClozeHistoryCompanion copyWith(
      {Value<String>? id,
      Value<String>? knowledgePointId,
      Value<String>? slotKey,
      Value<int>? correct,
      Value<int>? usedAt,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return ClozeHistoryCompanion(
      id: id ?? this.id,
      knowledgePointId: knowledgePointId ?? this.knowledgePointId,
      slotKey: slotKey ?? this.slotKey,
      correct: correct ?? this.correct,
      usedAt: usedAt ?? this.usedAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (knowledgePointId.present) {
      map['knowledge_point_id'] = Variable<String>(knowledgePointId.value);
    }
    if (slotKey.present) {
      map['slot_key'] = Variable<String>(slotKey.value);
    }
    if (correct.present) {
      map['correct'] = Variable<int>(correct.value);
    }
    if (usedAt.present) {
      map['used_at'] = Variable<int>(usedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClozeHistoryCompanion(')
          ..write('id: $id, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('slotKey: $slotKey, ')
          ..write('correct: $correct, ')
          ..write('usedAt: $usedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BoostEntriesTable extends BoostEntries
    with TableInfo<$BoostEntriesTable, BoostEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BoostEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _knowledgePointIdMeta =
      const VerificationMeta('knowledgePointId');
  @override
  late final GeneratedColumn<String> knowledgePointId = GeneratedColumn<String>(
      'knowledge_point_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _factorMeta = const VerificationMeta('factor');
  @override
  late final GeneratedColumn<double> factor = GeneratedColumn<double>(
      'factor', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _remainingCyclesMeta =
      const VerificationMeta('remainingCycles');
  @override
  late final GeneratedColumn<int> remainingCycles = GeneratedColumn<int>(
      'remaining_cycles', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(3));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, knowledgePointId, factor, remainingCycles, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'boost_entries';
  @override
  VerificationContext validateIntegrity(Insertable<BoostEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('knowledge_point_id')) {
      context.handle(
          _knowledgePointIdMeta,
          knowledgePointId.isAcceptableOrUnknown(
              data['knowledge_point_id']!, _knowledgePointIdMeta));
    } else if (isInserting) {
      context.missing(_knowledgePointIdMeta);
    }
    if (data.containsKey('factor')) {
      context.handle(_factorMeta,
          factor.isAcceptableOrUnknown(data['factor']!, _factorMeta));
    } else if (isInserting) {
      context.missing(_factorMeta);
    }
    if (data.containsKey('remaining_cycles')) {
      context.handle(
          _remainingCyclesMeta,
          remainingCycles.isAcceptableOrUnknown(
              data['remaining_cycles']!, _remainingCyclesMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {knowledgePointId},
      ];
  @override
  BoostEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BoostEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      knowledgePointId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}knowledge_point_id'])!,
      factor: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}factor'])!,
      remainingCycles: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remaining_cycles'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $BoostEntriesTable createAlias(String alias) {
    return $BoostEntriesTable(attachedDatabase, alias);
  }
}

class BoostEntry extends DataClass implements Insertable<BoostEntry> {
  final String id;
  final String knowledgePointId;
  final double factor;
  final int remainingCycles;
  final int createdAt;
  const BoostEntry(
      {required this.id,
      required this.knowledgePointId,
      required this.factor,
      required this.remainingCycles,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['knowledge_point_id'] = Variable<String>(knowledgePointId);
    map['factor'] = Variable<double>(factor);
    map['remaining_cycles'] = Variable<int>(remainingCycles);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  BoostEntriesCompanion toCompanion(bool nullToAbsent) {
    return BoostEntriesCompanion(
      id: Value(id),
      knowledgePointId: Value(knowledgePointId),
      factor: Value(factor),
      remainingCycles: Value(remainingCycles),
      createdAt: Value(createdAt),
    );
  }

  factory BoostEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BoostEntry(
      id: serializer.fromJson<String>(json['id']),
      knowledgePointId: serializer.fromJson<String>(json['knowledgePointId']),
      factor: serializer.fromJson<double>(json['factor']),
      remainingCycles: serializer.fromJson<int>(json['remainingCycles']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'knowledgePointId': serializer.toJson<String>(knowledgePointId),
      'factor': serializer.toJson<double>(factor),
      'remainingCycles': serializer.toJson<int>(remainingCycles),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  BoostEntry copyWith(
          {String? id,
          String? knowledgePointId,
          double? factor,
          int? remainingCycles,
          int? createdAt}) =>
      BoostEntry(
        id: id ?? this.id,
        knowledgePointId: knowledgePointId ?? this.knowledgePointId,
        factor: factor ?? this.factor,
        remainingCycles: remainingCycles ?? this.remainingCycles,
        createdAt: createdAt ?? this.createdAt,
      );
  BoostEntry copyWithCompanion(BoostEntriesCompanion data) {
    return BoostEntry(
      id: data.id.present ? data.id.value : this.id,
      knowledgePointId: data.knowledgePointId.present
          ? data.knowledgePointId.value
          : this.knowledgePointId,
      factor: data.factor.present ? data.factor.value : this.factor,
      remainingCycles: data.remainingCycles.present
          ? data.remainingCycles.value
          : this.remainingCycles,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BoostEntry(')
          ..write('id: $id, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('factor: $factor, ')
          ..write('remainingCycles: $remainingCycles, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, knowledgePointId, factor, remainingCycles, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BoostEntry &&
          other.id == this.id &&
          other.knowledgePointId == this.knowledgePointId &&
          other.factor == this.factor &&
          other.remainingCycles == this.remainingCycles &&
          other.createdAt == this.createdAt);
}

class BoostEntriesCompanion extends UpdateCompanion<BoostEntry> {
  final Value<String> id;
  final Value<String> knowledgePointId;
  final Value<double> factor;
  final Value<int> remainingCycles;
  final Value<int> createdAt;
  final Value<int> rowid;
  const BoostEntriesCompanion({
    this.id = const Value.absent(),
    this.knowledgePointId = const Value.absent(),
    this.factor = const Value.absent(),
    this.remainingCycles = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BoostEntriesCompanion.insert({
    required String id,
    required String knowledgePointId,
    required double factor,
    this.remainingCycles = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        knowledgePointId = Value(knowledgePointId),
        factor = Value(factor),
        createdAt = Value(createdAt);
  static Insertable<BoostEntry> custom({
    Expression<String>? id,
    Expression<String>? knowledgePointId,
    Expression<double>? factor,
    Expression<int>? remainingCycles,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (knowledgePointId != null) 'knowledge_point_id': knowledgePointId,
      if (factor != null) 'factor': factor,
      if (remainingCycles != null) 'remaining_cycles': remainingCycles,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BoostEntriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? knowledgePointId,
      Value<double>? factor,
      Value<int>? remainingCycles,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return BoostEntriesCompanion(
      id: id ?? this.id,
      knowledgePointId: knowledgePointId ?? this.knowledgePointId,
      factor: factor ?? this.factor,
      remainingCycles: remainingCycles ?? this.remainingCycles,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (knowledgePointId.present) {
      map['knowledge_point_id'] = Variable<String>(knowledgePointId.value);
    }
    if (factor.present) {
      map['factor'] = Variable<double>(factor.value);
    }
    if (remainingCycles.present) {
      map['remaining_cycles'] = Variable<int>(remainingCycles.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BoostEntriesCompanion(')
          ..write('id: $id, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('factor: $factor, ')
          ..write('remainingCycles: $remainingCycles, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ThemesTable extends Themes with TableInfo<$ThemesTable, ThemeProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ThemesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _isBuiltinMeta =
      const VerificationMeta('isBuiltin');
  @override
  late final GeneratedColumn<int> isBuiltin = GeneratedColumn<int>(
      'is_builtin', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, isBuiltin, payload, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'themes';
  @override
  VerificationContext validateIntegrity(Insertable<ThemeProfile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_builtin')) {
      context.handle(_isBuiltinMeta,
          isBuiltin.isAcceptableOrUnknown(data['is_builtin']!, _isBuiltinMeta));
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ThemeProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ThemeProfile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      isBuiltin: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}is_builtin'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ThemesTable createAlias(String alias) {
    return $ThemesTable(attachedDatabase, alias);
  }
}

class ThemeProfile extends DataClass implements Insertable<ThemeProfile> {
  final String id;
  final String name;
  final int isBuiltin;
  final String payload;
  final int createdAt;
  final int updatedAt;
  const ThemeProfile(
      {required this.id,
      required this.name,
      required this.isBuiltin,
      required this.payload,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['is_builtin'] = Variable<int>(isBuiltin);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ThemesCompanion toCompanion(bool nullToAbsent) {
    return ThemesCompanion(
      id: Value(id),
      name: Value(name),
      isBuiltin: Value(isBuiltin),
      payload: Value(payload),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ThemeProfile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ThemeProfile(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      isBuiltin: serializer.fromJson<int>(json['isBuiltin']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'isBuiltin': serializer.toJson<int>(isBuiltin),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ThemeProfile copyWith(
          {String? id,
          String? name,
          int? isBuiltin,
          String? payload,
          int? createdAt,
          int? updatedAt}) =>
      ThemeProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        isBuiltin: isBuiltin ?? this.isBuiltin,
        payload: payload ?? this.payload,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  ThemeProfile copyWithCompanion(ThemesCompanion data) {
    return ThemeProfile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isBuiltin: data.isBuiltin.present ? data.isBuiltin.value : this.isBuiltin,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ThemeProfile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, isBuiltin, payload, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThemeProfile &&
          other.id == this.id &&
          other.name == this.name &&
          other.isBuiltin == this.isBuiltin &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ThemesCompanion extends UpdateCompanion<ThemeProfile> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> isBuiltin;
  final Value<String> payload;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ThemesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isBuiltin = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ThemesCompanion.insert({
    required String id,
    required String name,
    this.isBuiltin = const Value.absent(),
    required String payload,
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        payload = Value(payload),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<ThemeProfile> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? isBuiltin,
    Expression<String>? payload,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isBuiltin != null) 'is_builtin': isBuiltin,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ThemesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<int>? isBuiltin,
      Value<String>? payload,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return ThemesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isBuiltin.present) {
      map['is_builtin'] = Variable<int>(isBuiltin.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThemesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttachmentsTable extends Attachments
    with TableInfo<$AttachmentsTable, Attachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerTypeMeta =
      const VerificationMeta('ownerType');
  @override
  late final GeneratedColumn<String> ownerType = GeneratedColumn<String>(
      'owner_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _relPathMeta =
      const VerificationMeta('relPath');
  @override
  late final GeneratedColumn<String> relPath = GeneratedColumn<String>(
      'rel_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
      'mime', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, ownerType, ownerId, relPath, mime, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachments';
  @override
  VerificationContext validateIntegrity(Insertable<Attachment> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_type')) {
      context.handle(_ownerTypeMeta,
          ownerType.isAcceptableOrUnknown(data['owner_type']!, _ownerTypeMeta));
    } else if (isInserting) {
      context.missing(_ownerTypeMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('rel_path')) {
      context.handle(_relPathMeta,
          relPath.isAcceptableOrUnknown(data['rel_path']!, _relPathMeta));
    } else if (isInserting) {
      context.missing(_relPathMeta);
    }
    if (data.containsKey('mime')) {
      context.handle(
          _mimeMeta, mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Attachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Attachment(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      ownerType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_type'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id'])!,
      relPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rel_path'])!,
      mime: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mime']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $AttachmentsTable createAlias(String alias) {
    return $AttachmentsTable(attachedDatabase, alias);
  }
}

class Attachment extends DataClass implements Insertable<Attachment> {
  final String id;
  final String ownerType;
  final String ownerId;
  final String relPath;
  final String? mime;
  final int createdAt;
  const Attachment(
      {required this.id,
      required this.ownerType,
      required this.ownerId,
      required this.relPath,
      this.mime,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_type'] = Variable<String>(ownerType);
    map['owner_id'] = Variable<String>(ownerId);
    map['rel_path'] = Variable<String>(relPath);
    if (!nullToAbsent || mime != null) {
      map['mime'] = Variable<String>(mime);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  AttachmentsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentsCompanion(
      id: Value(id),
      ownerType: Value(ownerType),
      ownerId: Value(ownerId),
      relPath: Value(relPath),
      mime: mime == null && nullToAbsent ? const Value.absent() : Value(mime),
      createdAt: Value(createdAt),
    );
  }

  factory Attachment.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Attachment(
      id: serializer.fromJson<String>(json['id']),
      ownerType: serializer.fromJson<String>(json['ownerType']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      relPath: serializer.fromJson<String>(json['relPath']),
      mime: serializer.fromJson<String?>(json['mime']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerType': serializer.toJson<String>(ownerType),
      'ownerId': serializer.toJson<String>(ownerId),
      'relPath': serializer.toJson<String>(relPath),
      'mime': serializer.toJson<String?>(mime),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Attachment copyWith(
          {String? id,
          String? ownerType,
          String? ownerId,
          String? relPath,
          Value<String?> mime = const Value.absent(),
          int? createdAt}) =>
      Attachment(
        id: id ?? this.id,
        ownerType: ownerType ?? this.ownerType,
        ownerId: ownerId ?? this.ownerId,
        relPath: relPath ?? this.relPath,
        mime: mime.present ? mime.value : this.mime,
        createdAt: createdAt ?? this.createdAt,
      );
  Attachment copyWithCompanion(AttachmentsCompanion data) {
    return Attachment(
      id: data.id.present ? data.id.value : this.id,
      ownerType: data.ownerType.present ? data.ownerType.value : this.ownerType,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      relPath: data.relPath.present ? data.relPath.value : this.relPath,
      mime: data.mime.present ? data.mime.value : this.mime,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Attachment(')
          ..write('id: $id, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId, ')
          ..write('relPath: $relPath, ')
          ..write('mime: $mime, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, ownerType, ownerId, relPath, mime, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Attachment &&
          other.id == this.id &&
          other.ownerType == this.ownerType &&
          other.ownerId == this.ownerId &&
          other.relPath == this.relPath &&
          other.mime == this.mime &&
          other.createdAt == this.createdAt);
}

class AttachmentsCompanion extends UpdateCompanion<Attachment> {
  final Value<String> id;
  final Value<String> ownerType;
  final Value<String> ownerId;
  final Value<String> relPath;
  final Value<String?> mime;
  final Value<int> createdAt;
  final Value<int> rowid;
  const AttachmentsCompanion({
    this.id = const Value.absent(),
    this.ownerType = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.relPath = const Value.absent(),
    this.mime = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentsCompanion.insert({
    required String id,
    required String ownerType,
    required String ownerId,
    required String relPath,
    this.mime = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        ownerType = Value(ownerType),
        ownerId = Value(ownerId),
        relPath = Value(relPath),
        createdAt = Value(createdAt);
  static Insertable<Attachment> custom({
    Expression<String>? id,
    Expression<String>? ownerType,
    Expression<String>? ownerId,
    Expression<String>? relPath,
    Expression<String>? mime,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerType != null) 'owner_type': ownerType,
      if (ownerId != null) 'owner_id': ownerId,
      if (relPath != null) 'rel_path': relPath,
      if (mime != null) 'mime': mime,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentsCompanion copyWith(
      {Value<String>? id,
      Value<String>? ownerType,
      Value<String>? ownerId,
      Value<String>? relPath,
      Value<String?>? mime,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return AttachmentsCompanion(
      id: id ?? this.id,
      ownerType: ownerType ?? this.ownerType,
      ownerId: ownerId ?? this.ownerId,
      relPath: relPath ?? this.relPath,
      mime: mime ?? this.mime,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerType.present) {
      map['owner_type'] = Variable<String>(ownerType.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (relPath.present) {
      map['rel_path'] = Variable<String>(relPath.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId, ')
          ..write('relPath: $relPath, ')
          ..write('mime: $mime, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ThreadRankSettingsTable extends ThreadRankSettings
    with TableInfo<$ThreadRankSettingsTable, ThreadRankSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ThreadRankSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _wUrgencyMeta =
      const VerificationMeta('wUrgency');
  @override
  late final GeneratedColumn<double> wUrgency = GeneratedColumn<double>(
      'w_urgency', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.4));
  static const VerificationMeta _wGoalMeta = const VerificationMeta('wGoal');
  @override
  late final GeneratedColumn<double> wGoal = GeneratedColumn<double>(
      'w_goal', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.3));
  static const VerificationMeta _wFitMeta = const VerificationMeta('wFit');
  @override
  late final GeneratedColumn<double> wFit = GeneratedColumn<double>(
      'w_fit', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.2));
  static const VerificationMeta _wFatigueMeta =
      const VerificationMeta('wFatigue');
  @override
  late final GeneratedColumn<double> wFatigue = GeneratedColumn<double>(
      'w_fatigue', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.1));
  static const VerificationMeta _wExpectedMeta =
      const VerificationMeta('wExpected');
  @override
  late final GeneratedColumn<double> wExpected = GeneratedColumn<double>(
      'w_expected', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.05));
  static const VerificationMeta _headerCollapsedMeta =
      const VerificationMeta('headerCollapsed');
  @override
  late final GeneratedColumn<bool> headerCollapsed = GeneratedColumn<bool>(
      'header_collapsed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("header_collapsed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _useActualTimeMeta =
      const VerificationMeta('useActualTime');
  @override
  late final GeneratedColumn<bool> useActualTime = GeneratedColumn<bool>(
      'use_actual_time', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("use_actual_time" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        wUrgency,
        wGoal,
        wFit,
        wFatigue,
        wExpected,
        headerCollapsed,
        useActualTime,
        updatedAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'thread_rank_settings';
  @override
  VerificationContext validateIntegrity(Insertable<ThreadRankSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('w_urgency')) {
      context.handle(_wUrgencyMeta,
          wUrgency.isAcceptableOrUnknown(data['w_urgency']!, _wUrgencyMeta));
    }
    if (data.containsKey('w_goal')) {
      context.handle(
          _wGoalMeta, wGoal.isAcceptableOrUnknown(data['w_goal']!, _wGoalMeta));
    }
    if (data.containsKey('w_fit')) {
      context.handle(
          _wFitMeta, wFit.isAcceptableOrUnknown(data['w_fit']!, _wFitMeta));
    }
    if (data.containsKey('w_fatigue')) {
      context.handle(_wFatigueMeta,
          wFatigue.isAcceptableOrUnknown(data['w_fatigue']!, _wFatigueMeta));
    }
    if (data.containsKey('w_expected')) {
      context.handle(_wExpectedMeta,
          wExpected.isAcceptableOrUnknown(data['w_expected']!, _wExpectedMeta));
    }
    if (data.containsKey('header_collapsed')) {
      context.handle(
          _headerCollapsedMeta,
          headerCollapsed.isAcceptableOrUnknown(
              data['header_collapsed']!, _headerCollapsedMeta));
    }
    if (data.containsKey('use_actual_time')) {
      context.handle(
          _useActualTimeMeta,
          useActualTime.isAcceptableOrUnknown(
              data['use_actual_time']!, _useActualTimeMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ThreadRankSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ThreadRankSetting(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      wUrgency: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}w_urgency'])!,
      wGoal: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}w_goal'])!,
      wFit: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}w_fit'])!,
      wFatigue: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}w_fatigue'])!,
      wExpected: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}w_expected'])!,
      headerCollapsed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}header_collapsed'])!,
      useActualTime: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}use_actual_time'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ThreadRankSettingsTable createAlias(String alias) {
    return $ThreadRankSettingsTable(attachedDatabase, alias);
  }
}

class ThreadRankSetting extends DataClass
    implements Insertable<ThreadRankSetting> {
  final int id;
  final double wUrgency;
  final double wGoal;
  final double wFit;
  final double wFatigue;
  final double wExpected;

  /// Whether the Thread status bar is collapsed (blueprint 2.2).
  final bool headerCollapsed;

  /// Global switch: may actual durations update the duration model?
  final bool useActualTime;
  final int? updatedAt;
  final int createdAt;
  const ThreadRankSetting(
      {required this.id,
      required this.wUrgency,
      required this.wGoal,
      required this.wFit,
      required this.wFatigue,
      required this.wExpected,
      required this.headerCollapsed,
      required this.useActualTime,
      this.updatedAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['w_urgency'] = Variable<double>(wUrgency);
    map['w_goal'] = Variable<double>(wGoal);
    map['w_fit'] = Variable<double>(wFit);
    map['w_fatigue'] = Variable<double>(wFatigue);
    map['w_expected'] = Variable<double>(wExpected);
    map['header_collapsed'] = Variable<bool>(headerCollapsed);
    map['use_actual_time'] = Variable<bool>(useActualTime);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ThreadRankSettingsCompanion toCompanion(bool nullToAbsent) {
    return ThreadRankSettingsCompanion(
      id: Value(id),
      wUrgency: Value(wUrgency),
      wGoal: Value(wGoal),
      wFit: Value(wFit),
      wFatigue: Value(wFatigue),
      wExpected: Value(wExpected),
      headerCollapsed: Value(headerCollapsed),
      useActualTime: Value(useActualTime),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      createdAt: Value(createdAt),
    );
  }

  factory ThreadRankSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ThreadRankSetting(
      id: serializer.fromJson<int>(json['id']),
      wUrgency: serializer.fromJson<double>(json['wUrgency']),
      wGoal: serializer.fromJson<double>(json['wGoal']),
      wFit: serializer.fromJson<double>(json['wFit']),
      wFatigue: serializer.fromJson<double>(json['wFatigue']),
      wExpected: serializer.fromJson<double>(json['wExpected']),
      headerCollapsed: serializer.fromJson<bool>(json['headerCollapsed']),
      useActualTime: serializer.fromJson<bool>(json['useActualTime']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'wUrgency': serializer.toJson<double>(wUrgency),
      'wGoal': serializer.toJson<double>(wGoal),
      'wFit': serializer.toJson<double>(wFit),
      'wFatigue': serializer.toJson<double>(wFatigue),
      'wExpected': serializer.toJson<double>(wExpected),
      'headerCollapsed': serializer.toJson<bool>(headerCollapsed),
      'useActualTime': serializer.toJson<bool>(useActualTime),
      'updatedAt': serializer.toJson<int?>(updatedAt),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ThreadRankSetting copyWith(
          {int? id,
          double? wUrgency,
          double? wGoal,
          double? wFit,
          double? wFatigue,
          double? wExpected,
          bool? headerCollapsed,
          bool? useActualTime,
          Value<int?> updatedAt = const Value.absent(),
          int? createdAt}) =>
      ThreadRankSetting(
        id: id ?? this.id,
        wUrgency: wUrgency ?? this.wUrgency,
        wGoal: wGoal ?? this.wGoal,
        wFit: wFit ?? this.wFit,
        wFatigue: wFatigue ?? this.wFatigue,
        wExpected: wExpected ?? this.wExpected,
        headerCollapsed: headerCollapsed ?? this.headerCollapsed,
        useActualTime: useActualTime ?? this.useActualTime,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
        createdAt: createdAt ?? this.createdAt,
      );
  ThreadRankSetting copyWithCompanion(ThreadRankSettingsCompanion data) {
    return ThreadRankSetting(
      id: data.id.present ? data.id.value : this.id,
      wUrgency: data.wUrgency.present ? data.wUrgency.value : this.wUrgency,
      wGoal: data.wGoal.present ? data.wGoal.value : this.wGoal,
      wFit: data.wFit.present ? data.wFit.value : this.wFit,
      wFatigue: data.wFatigue.present ? data.wFatigue.value : this.wFatigue,
      wExpected: data.wExpected.present ? data.wExpected.value : this.wExpected,
      headerCollapsed: data.headerCollapsed.present
          ? data.headerCollapsed.value
          : this.headerCollapsed,
      useActualTime: data.useActualTime.present
          ? data.useActualTime.value
          : this.useActualTime,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ThreadRankSetting(')
          ..write('id: $id, ')
          ..write('wUrgency: $wUrgency, ')
          ..write('wGoal: $wGoal, ')
          ..write('wFit: $wFit, ')
          ..write('wFatigue: $wFatigue, ')
          ..write('wExpected: $wExpected, ')
          ..write('headerCollapsed: $headerCollapsed, ')
          ..write('useActualTime: $useActualTime, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, wUrgency, wGoal, wFit, wFatigue,
      wExpected, headerCollapsed, useActualTime, updatedAt, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThreadRankSetting &&
          other.id == this.id &&
          other.wUrgency == this.wUrgency &&
          other.wGoal == this.wGoal &&
          other.wFit == this.wFit &&
          other.wFatigue == this.wFatigue &&
          other.wExpected == this.wExpected &&
          other.headerCollapsed == this.headerCollapsed &&
          other.useActualTime == this.useActualTime &&
          other.updatedAt == this.updatedAt &&
          other.createdAt == this.createdAt);
}

class ThreadRankSettingsCompanion extends UpdateCompanion<ThreadRankSetting> {
  final Value<int> id;
  final Value<double> wUrgency;
  final Value<double> wGoal;
  final Value<double> wFit;
  final Value<double> wFatigue;
  final Value<double> wExpected;
  final Value<bool> headerCollapsed;
  final Value<bool> useActualTime;
  final Value<int?> updatedAt;
  final Value<int> createdAt;
  const ThreadRankSettingsCompanion({
    this.id = const Value.absent(),
    this.wUrgency = const Value.absent(),
    this.wGoal = const Value.absent(),
    this.wFit = const Value.absent(),
    this.wFatigue = const Value.absent(),
    this.wExpected = const Value.absent(),
    this.headerCollapsed = const Value.absent(),
    this.useActualTime = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ThreadRankSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.wUrgency = const Value.absent(),
    this.wGoal = const Value.absent(),
    this.wFit = const Value.absent(),
    this.wFatigue = const Value.absent(),
    this.wExpected = const Value.absent(),
    this.headerCollapsed = const Value.absent(),
    this.useActualTime = const Value.absent(),
    this.updatedAt = const Value.absent(),
    required int createdAt,
  }) : createdAt = Value(createdAt);
  static Insertable<ThreadRankSetting> custom({
    Expression<int>? id,
    Expression<double>? wUrgency,
    Expression<double>? wGoal,
    Expression<double>? wFit,
    Expression<double>? wFatigue,
    Expression<double>? wExpected,
    Expression<bool>? headerCollapsed,
    Expression<bool>? useActualTime,
    Expression<int>? updatedAt,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (wUrgency != null) 'w_urgency': wUrgency,
      if (wGoal != null) 'w_goal': wGoal,
      if (wFit != null) 'w_fit': wFit,
      if (wFatigue != null) 'w_fatigue': wFatigue,
      if (wExpected != null) 'w_expected': wExpected,
      if (headerCollapsed != null) 'header_collapsed': headerCollapsed,
      if (useActualTime != null) 'use_actual_time': useActualTime,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ThreadRankSettingsCompanion copyWith(
      {Value<int>? id,
      Value<double>? wUrgency,
      Value<double>? wGoal,
      Value<double>? wFit,
      Value<double>? wFatigue,
      Value<double>? wExpected,
      Value<bool>? headerCollapsed,
      Value<bool>? useActualTime,
      Value<int?>? updatedAt,
      Value<int>? createdAt}) {
    return ThreadRankSettingsCompanion(
      id: id ?? this.id,
      wUrgency: wUrgency ?? this.wUrgency,
      wGoal: wGoal ?? this.wGoal,
      wFit: wFit ?? this.wFit,
      wFatigue: wFatigue ?? this.wFatigue,
      wExpected: wExpected ?? this.wExpected,
      headerCollapsed: headerCollapsed ?? this.headerCollapsed,
      useActualTime: useActualTime ?? this.useActualTime,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (wUrgency.present) {
      map['w_urgency'] = Variable<double>(wUrgency.value);
    }
    if (wGoal.present) {
      map['w_goal'] = Variable<double>(wGoal.value);
    }
    if (wFit.present) {
      map['w_fit'] = Variable<double>(wFit.value);
    }
    if (wFatigue.present) {
      map['w_fatigue'] = Variable<double>(wFatigue.value);
    }
    if (wExpected.present) {
      map['w_expected'] = Variable<double>(wExpected.value);
    }
    if (headerCollapsed.present) {
      map['header_collapsed'] = Variable<bool>(headerCollapsed.value);
    }
    if (useActualTime.present) {
      map['use_actual_time'] = Variable<bool>(useActualTime.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThreadRankSettingsCompanion(')
          ..write('id: $id, ')
          ..write('wUrgency: $wUrgency, ')
          ..write('wGoal: $wGoal, ')
          ..write('wFit: $wFit, ')
          ..write('wFatigue: $wFatigue, ')
          ..write('wExpected: $wExpected, ')
          ..write('headerCollapsed: $headerCollapsed, ')
          ..write('useActualTime: $useActualTime, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DiffusionLogsTable extends DiffusionLogs
    with TableInfo<$DiffusionLogsTable, DiffusionLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiffusionLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerTypeMeta =
      const VerificationMeta('ownerType');
  @override
  late final GeneratedColumn<String> ownerType = GeneratedColumn<String>(
      'owner_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _ownerTitleMeta =
      const VerificationMeta('ownerTitle');
  @override
  late final GeneratedColumn<String> ownerTitle = GeneratedColumn<String>(
      'owner_title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _knowledgePointIdMeta =
      const VerificationMeta('knowledgePointId');
  @override
  late final GeneratedColumn<String> knowledgePointId = GeneratedColumn<String>(
      'knowledge_point_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _knowledgePointTitleMeta =
      const VerificationMeta('knowledgePointTitle');
  @override
  late final GeneratedColumn<String> knowledgePointTitle =
      GeneratedColumn<String>('knowledge_point_title', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _distanceMeta =
      const VerificationMeta('distance');
  @override
  late final GeneratedColumn<int> distance = GeneratedColumn<int>(
      'distance', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _factorMeta = const VerificationMeta('factor');
  @override
  late final GeneratedColumn<double> factor = GeneratedColumn<double>(
      'factor', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
      'detail', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _dayKeyMeta = const VerificationMeta('dayKey');
  @override
  late final GeneratedColumn<String> dayKey = GeneratedColumn<String>(
      'day_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _occurredAtMeta =
      const VerificationMeta('occurredAt');
  @override
  late final GeneratedColumn<int> occurredAt = GeneratedColumn<int>(
      'occurred_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        ownerType,
        ownerId,
        ownerTitle,
        kind,
        knowledgePointId,
        knowledgePointTitle,
        distance,
        factor,
        detail,
        dayKey,
        occurredAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diffusion_logs';
  @override
  VerificationContext validateIntegrity(Insertable<DiffusionLog> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_type')) {
      context.handle(_ownerTypeMeta,
          ownerType.isAcceptableOrUnknown(data['owner_type']!, _ownerTypeMeta));
    } else if (isInserting) {
      context.missing(_ownerTypeMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    }
    if (data.containsKey('owner_title')) {
      context.handle(
          _ownerTitleMeta,
          ownerTitle.isAcceptableOrUnknown(
              data['owner_title']!, _ownerTitleMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('knowledge_point_id')) {
      context.handle(
          _knowledgePointIdMeta,
          knowledgePointId.isAcceptableOrUnknown(
              data['knowledge_point_id']!, _knowledgePointIdMeta));
    }
    if (data.containsKey('knowledge_point_title')) {
      context.handle(
          _knowledgePointTitleMeta,
          knowledgePointTitle.isAcceptableOrUnknown(
              data['knowledge_point_title']!, _knowledgePointTitleMeta));
    }
    if (data.containsKey('distance')) {
      context.handle(_distanceMeta,
          distance.isAcceptableOrUnknown(data['distance']!, _distanceMeta));
    }
    if (data.containsKey('factor')) {
      context.handle(_factorMeta,
          factor.isAcceptableOrUnknown(data['factor']!, _factorMeta));
    }
    if (data.containsKey('detail')) {
      context.handle(_detailMeta,
          detail.isAcceptableOrUnknown(data['detail']!, _detailMeta));
    }
    if (data.containsKey('day_key')) {
      context.handle(_dayKeyMeta,
          dayKey.isAcceptableOrUnknown(data['day_key']!, _dayKeyMeta));
    } else if (isInserting) {
      context.missing(_dayKeyMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
          _occurredAtMeta,
          occurredAt.isAcceptableOrUnknown(
              data['occurred_at']!, _occurredAtMeta));
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DiffusionLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiffusionLog(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      ownerType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_type'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id']),
      ownerTitle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_title']),
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      knowledgePointId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}knowledge_point_id']),
      knowledgePointTitle: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}knowledge_point_title']),
      distance: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}distance']),
      factor: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}factor']),
      detail: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}detail']),
      dayKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}day_key'])!,
      occurredAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}occurred_at'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $DiffusionLogsTable createAlias(String alias) {
    return $DiffusionLogsTable(attachedDatabase, alias);
  }
}

class DiffusionLog extends DataClass implements Insertable<DiffusionLog> {
  final String id;
  final String ownerType;

  /// `event` | `knowledge`.
  final String? ownerId;
  final String? ownerTitle;

  /// `wrong` (a blank/event went wrong) | `boost` (a related item got lifted)
  /// | `release` (a boost expired).
  final String kind;

  /// Related knowledge point, when this line is about graph diffusion.
  final String? knowledgePointId;
  final String? knowledgePointTitle;

  /// Graph distance from the item that went wrong (1 or 2).
  final int? distance;

  /// Boost factor applied (1.8 / 1.3), when [kind] == 'boost'.
  final double? factor;

  /// The text that was blanked / the correct answer, for the ledger.
  final String? detail;

  /// Local day key `yyyy-MM-dd` so the ledger can be grouped by day without
  /// timezone ambiguity.
  final String dayKey;
  final int occurredAt;
  final int createdAt;
  const DiffusionLog(
      {required this.id,
      required this.ownerType,
      this.ownerId,
      this.ownerTitle,
      required this.kind,
      this.knowledgePointId,
      this.knowledgePointTitle,
      this.distance,
      this.factor,
      this.detail,
      required this.dayKey,
      required this.occurredAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_type'] = Variable<String>(ownerType);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    if (!nullToAbsent || ownerTitle != null) {
      map['owner_title'] = Variable<String>(ownerTitle);
    }
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || knowledgePointId != null) {
      map['knowledge_point_id'] = Variable<String>(knowledgePointId);
    }
    if (!nullToAbsent || knowledgePointTitle != null) {
      map['knowledge_point_title'] = Variable<String>(knowledgePointTitle);
    }
    if (!nullToAbsent || distance != null) {
      map['distance'] = Variable<int>(distance);
    }
    if (!nullToAbsent || factor != null) {
      map['factor'] = Variable<double>(factor);
    }
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    map['day_key'] = Variable<String>(dayKey);
    map['occurred_at'] = Variable<int>(occurredAt);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  DiffusionLogsCompanion toCompanion(bool nullToAbsent) {
    return DiffusionLogsCompanion(
      id: Value(id),
      ownerType: Value(ownerType),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
      ownerTitle: ownerTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerTitle),
      kind: Value(kind),
      knowledgePointId: knowledgePointId == null && nullToAbsent
          ? const Value.absent()
          : Value(knowledgePointId),
      knowledgePointTitle: knowledgePointTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(knowledgePointTitle),
      distance: distance == null && nullToAbsent
          ? const Value.absent()
          : Value(distance),
      factor:
          factor == null && nullToAbsent ? const Value.absent() : Value(factor),
      detail:
          detail == null && nullToAbsent ? const Value.absent() : Value(detail),
      dayKey: Value(dayKey),
      occurredAt: Value(occurredAt),
      createdAt: Value(createdAt),
    );
  }

  factory DiffusionLog.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiffusionLog(
      id: serializer.fromJson<String>(json['id']),
      ownerType: serializer.fromJson<String>(json['ownerType']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
      ownerTitle: serializer.fromJson<String?>(json['ownerTitle']),
      kind: serializer.fromJson<String>(json['kind']),
      knowledgePointId: serializer.fromJson<String?>(json['knowledgePointId']),
      knowledgePointTitle:
          serializer.fromJson<String?>(json['knowledgePointTitle']),
      distance: serializer.fromJson<int?>(json['distance']),
      factor: serializer.fromJson<double?>(json['factor']),
      detail: serializer.fromJson<String?>(json['detail']),
      dayKey: serializer.fromJson<String>(json['dayKey']),
      occurredAt: serializer.fromJson<int>(json['occurredAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerType': serializer.toJson<String>(ownerType),
      'ownerId': serializer.toJson<String?>(ownerId),
      'ownerTitle': serializer.toJson<String?>(ownerTitle),
      'kind': serializer.toJson<String>(kind),
      'knowledgePointId': serializer.toJson<String?>(knowledgePointId),
      'knowledgePointTitle': serializer.toJson<String?>(knowledgePointTitle),
      'distance': serializer.toJson<int?>(distance),
      'factor': serializer.toJson<double?>(factor),
      'detail': serializer.toJson<String?>(detail),
      'dayKey': serializer.toJson<String>(dayKey),
      'occurredAt': serializer.toJson<int>(occurredAt),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  DiffusionLog copyWith(
          {String? id,
          String? ownerType,
          Value<String?> ownerId = const Value.absent(),
          Value<String?> ownerTitle = const Value.absent(),
          String? kind,
          Value<String?> knowledgePointId = const Value.absent(),
          Value<String?> knowledgePointTitle = const Value.absent(),
          Value<int?> distance = const Value.absent(),
          Value<double?> factor = const Value.absent(),
          Value<String?> detail = const Value.absent(),
          String? dayKey,
          int? occurredAt,
          int? createdAt}) =>
      DiffusionLog(
        id: id ?? this.id,
        ownerType: ownerType ?? this.ownerType,
        ownerId: ownerId.present ? ownerId.value : this.ownerId,
        ownerTitle: ownerTitle.present ? ownerTitle.value : this.ownerTitle,
        kind: kind ?? this.kind,
        knowledgePointId: knowledgePointId.present
            ? knowledgePointId.value
            : this.knowledgePointId,
        knowledgePointTitle: knowledgePointTitle.present
            ? knowledgePointTitle.value
            : this.knowledgePointTitle,
        distance: distance.present ? distance.value : this.distance,
        factor: factor.present ? factor.value : this.factor,
        detail: detail.present ? detail.value : this.detail,
        dayKey: dayKey ?? this.dayKey,
        occurredAt: occurredAt ?? this.occurredAt,
        createdAt: createdAt ?? this.createdAt,
      );
  DiffusionLog copyWithCompanion(DiffusionLogsCompanion data) {
    return DiffusionLog(
      id: data.id.present ? data.id.value : this.id,
      ownerType: data.ownerType.present ? data.ownerType.value : this.ownerType,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      ownerTitle:
          data.ownerTitle.present ? data.ownerTitle.value : this.ownerTitle,
      kind: data.kind.present ? data.kind.value : this.kind,
      knowledgePointId: data.knowledgePointId.present
          ? data.knowledgePointId.value
          : this.knowledgePointId,
      knowledgePointTitle: data.knowledgePointTitle.present
          ? data.knowledgePointTitle.value
          : this.knowledgePointTitle,
      distance: data.distance.present ? data.distance.value : this.distance,
      factor: data.factor.present ? data.factor.value : this.factor,
      detail: data.detail.present ? data.detail.value : this.detail,
      dayKey: data.dayKey.present ? data.dayKey.value : this.dayKey,
      occurredAt:
          data.occurredAt.present ? data.occurredAt.value : this.occurredAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiffusionLog(')
          ..write('id: $id, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId, ')
          ..write('ownerTitle: $ownerTitle, ')
          ..write('kind: $kind, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('knowledgePointTitle: $knowledgePointTitle, ')
          ..write('distance: $distance, ')
          ..write('factor: $factor, ')
          ..write('detail: $detail, ')
          ..write('dayKey: $dayKey, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      ownerType,
      ownerId,
      ownerTitle,
      kind,
      knowledgePointId,
      knowledgePointTitle,
      distance,
      factor,
      detail,
      dayKey,
      occurredAt,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiffusionLog &&
          other.id == this.id &&
          other.ownerType == this.ownerType &&
          other.ownerId == this.ownerId &&
          other.ownerTitle == this.ownerTitle &&
          other.kind == this.kind &&
          other.knowledgePointId == this.knowledgePointId &&
          other.knowledgePointTitle == this.knowledgePointTitle &&
          other.distance == this.distance &&
          other.factor == this.factor &&
          other.detail == this.detail &&
          other.dayKey == this.dayKey &&
          other.occurredAt == this.occurredAt &&
          other.createdAt == this.createdAt);
}

class DiffusionLogsCompanion extends UpdateCompanion<DiffusionLog> {
  final Value<String> id;
  final Value<String> ownerType;
  final Value<String?> ownerId;
  final Value<String?> ownerTitle;
  final Value<String> kind;
  final Value<String?> knowledgePointId;
  final Value<String?> knowledgePointTitle;
  final Value<int?> distance;
  final Value<double?> factor;
  final Value<String?> detail;
  final Value<String> dayKey;
  final Value<int> occurredAt;
  final Value<int> createdAt;
  final Value<int> rowid;
  const DiffusionLogsCompanion({
    this.id = const Value.absent(),
    this.ownerType = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.ownerTitle = const Value.absent(),
    this.kind = const Value.absent(),
    this.knowledgePointId = const Value.absent(),
    this.knowledgePointTitle = const Value.absent(),
    this.distance = const Value.absent(),
    this.factor = const Value.absent(),
    this.detail = const Value.absent(),
    this.dayKey = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiffusionLogsCompanion.insert({
    required String id,
    required String ownerType,
    this.ownerId = const Value.absent(),
    this.ownerTitle = const Value.absent(),
    required String kind,
    this.knowledgePointId = const Value.absent(),
    this.knowledgePointTitle = const Value.absent(),
    this.distance = const Value.absent(),
    this.factor = const Value.absent(),
    this.detail = const Value.absent(),
    required String dayKey,
    required int occurredAt,
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        ownerType = Value(ownerType),
        kind = Value(kind),
        dayKey = Value(dayKey),
        occurredAt = Value(occurredAt),
        createdAt = Value(createdAt);
  static Insertable<DiffusionLog> custom({
    Expression<String>? id,
    Expression<String>? ownerType,
    Expression<String>? ownerId,
    Expression<String>? ownerTitle,
    Expression<String>? kind,
    Expression<String>? knowledgePointId,
    Expression<String>? knowledgePointTitle,
    Expression<int>? distance,
    Expression<double>? factor,
    Expression<String>? detail,
    Expression<String>? dayKey,
    Expression<int>? occurredAt,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerType != null) 'owner_type': ownerType,
      if (ownerId != null) 'owner_id': ownerId,
      if (ownerTitle != null) 'owner_title': ownerTitle,
      if (kind != null) 'kind': kind,
      if (knowledgePointId != null) 'knowledge_point_id': knowledgePointId,
      if (knowledgePointTitle != null)
        'knowledge_point_title': knowledgePointTitle,
      if (distance != null) 'distance': distance,
      if (factor != null) 'factor': factor,
      if (detail != null) 'detail': detail,
      if (dayKey != null) 'day_key': dayKey,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiffusionLogsCompanion copyWith(
      {Value<String>? id,
      Value<String>? ownerType,
      Value<String?>? ownerId,
      Value<String?>? ownerTitle,
      Value<String>? kind,
      Value<String?>? knowledgePointId,
      Value<String?>? knowledgePointTitle,
      Value<int?>? distance,
      Value<double?>? factor,
      Value<String?>? detail,
      Value<String>? dayKey,
      Value<int>? occurredAt,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return DiffusionLogsCompanion(
      id: id ?? this.id,
      ownerType: ownerType ?? this.ownerType,
      ownerId: ownerId ?? this.ownerId,
      ownerTitle: ownerTitle ?? this.ownerTitle,
      kind: kind ?? this.kind,
      knowledgePointId: knowledgePointId ?? this.knowledgePointId,
      knowledgePointTitle: knowledgePointTitle ?? this.knowledgePointTitle,
      distance: distance ?? this.distance,
      factor: factor ?? this.factor,
      detail: detail ?? this.detail,
      dayKey: dayKey ?? this.dayKey,
      occurredAt: occurredAt ?? this.occurredAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerType.present) {
      map['owner_type'] = Variable<String>(ownerType.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (ownerTitle.present) {
      map['owner_title'] = Variable<String>(ownerTitle.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (knowledgePointId.present) {
      map['knowledge_point_id'] = Variable<String>(knowledgePointId.value);
    }
    if (knowledgePointTitle.present) {
      map['knowledge_point_title'] =
          Variable<String>(knowledgePointTitle.value);
    }
    if (distance.present) {
      map['distance'] = Variable<int>(distance.value);
    }
    if (factor.present) {
      map['factor'] = Variable<double>(factor.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (dayKey.present) {
      map['day_key'] = Variable<String>(dayKey.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<int>(occurredAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiffusionLogsCompanion(')
          ..write('id: $id, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId, ')
          ..write('ownerTitle: $ownerTitle, ')
          ..write('kind: $kind, ')
          ..write('knowledgePointId: $knowledgePointId, ')
          ..write('knowledgePointTitle: $knowledgePointTitle, ')
          ..write('distance: $distance, ')
          ..write('factor: $factor, ')
          ..write('detail: $detail, ')
          ..write('dayKey: $dayKey, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TimeTemplatesTable extends TimeTemplates
    with TableInfo<$TimeTemplatesTable, TimeTemplate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TimeTemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, kind, payload, sortOrder, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'time_templates';
  @override
  VerificationContext validateIntegrity(Insertable<TimeTemplate> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TimeTemplate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TimeTemplate(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $TimeTemplatesTable createAlias(String alias) {
    return $TimeTemplatesTable(attachedDatabase, alias);
  }
}

class TimeTemplate extends DataClass implements Insertable<TimeTemplate> {
  final String id;
  final String name;

  /// `day` | `week`.
  final String kind;
  final String payload;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
  const TimeTemplate(
      {required this.id,
      required this.name,
      required this.kind,
      required this.payload,
      required this.sortOrder,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    map['payload'] = Variable<String>(payload);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  TimeTemplatesCompanion toCompanion(bool nullToAbsent) {
    return TimeTemplatesCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      payload: Value(payload),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TimeTemplate.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TimeTemplate(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      payload: serializer.fromJson<String>(json['payload']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'payload': serializer.toJson<String>(payload),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  TimeTemplate copyWith(
          {String? id,
          String? name,
          String? kind,
          String? payload,
          int? sortOrder,
          int? createdAt,
          int? updatedAt}) =>
      TimeTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        payload: payload ?? this.payload,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  TimeTemplate copyWithCompanion(TimeTemplatesCompanion data) {
    return TimeTemplate(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      payload: data.payload.present ? data.payload.value : this.payload,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TimeTemplate(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, kind, payload, sortOrder, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimeTemplate &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.payload == this.payload &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TimeTemplatesCompanion extends UpdateCompanion<TimeTemplate> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> kind;
  final Value<String> payload;
  final Value<int> sortOrder;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const TimeTemplatesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.payload = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TimeTemplatesCompanion.insert({
    required String id,
    required String name,
    required String kind,
    required String payload,
    this.sortOrder = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        kind = Value(kind),
        payload = Value(payload),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<TimeTemplate> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? payload,
    Expression<int>? sortOrder,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (payload != null) 'payload': payload,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TimeTemplatesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? kind,
      Value<String>? payload,
      Value<int>? sortOrder,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return TimeTemplatesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TimeTemplatesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TimeViewSettingsTable extends TimeViewSettings
    with TableInfo<$TimeViewSettingsTable, TimeViewSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TimeViewSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _timelineSpanDaysMeta =
      const VerificationMeta('timelineSpanDays');
  @override
  late final GeneratedColumn<int> timelineSpanDays = GeneratedColumn<int>(
      'timeline_span_days', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(730));
  static const VerificationMeta _timelinePxPerDayMeta =
      const VerificationMeta('timelinePxPerDay');
  @override
  late final GeneratedColumn<double> timelinePxPerDay = GeneratedColumn<double>(
      'timeline_px_per_day', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(6));
  static const VerificationMeta _timelineCollapsedMeta =
      const VerificationMeta('timelineCollapsed');
  @override
  late final GeneratedColumn<bool> timelineCollapsed = GeneratedColumn<bool>(
      'timeline_collapsed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("timeline_collapsed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _minutesPerRowMeta =
      const VerificationMeta('minutesPerRow');
  @override
  late final GeneratedColumn<int> minutesPerRow = GeneratedColumn<int>(
      'minutes_per_row', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(30));
  static const VerificationMeta _minutesPerRowChosenMeta =
      const VerificationMeta('minutesPerRowChosen');
  @override
  late final GeneratedColumn<bool> minutesPerRowChosen = GeneratedColumn<bool>(
      'minutes_per_row_chosen', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("minutes_per_row_chosen" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        timelineSpanDays,
        timelinePxPerDay,
        timelineCollapsed,
        minutesPerRow,
        minutesPerRowChosen,
        updatedAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'time_view_settings';
  @override
  VerificationContext validateIntegrity(Insertable<TimeViewSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('timeline_span_days')) {
      context.handle(
          _timelineSpanDaysMeta,
          timelineSpanDays.isAcceptableOrUnknown(
              data['timeline_span_days']!, _timelineSpanDaysMeta));
    }
    if (data.containsKey('timeline_px_per_day')) {
      context.handle(
          _timelinePxPerDayMeta,
          timelinePxPerDay.isAcceptableOrUnknown(
              data['timeline_px_per_day']!, _timelinePxPerDayMeta));
    }
    if (data.containsKey('timeline_collapsed')) {
      context.handle(
          _timelineCollapsedMeta,
          timelineCollapsed.isAcceptableOrUnknown(
              data['timeline_collapsed']!, _timelineCollapsedMeta));
    }
    if (data.containsKey('minutes_per_row')) {
      context.handle(
          _minutesPerRowMeta,
          minutesPerRow.isAcceptableOrUnknown(
              data['minutes_per_row']!, _minutesPerRowMeta));
    }
    if (data.containsKey('minutes_per_row_chosen')) {
      context.handle(
          _minutesPerRowChosenMeta,
          minutesPerRowChosen.isAcceptableOrUnknown(
              data['minutes_per_row_chosen']!, _minutesPerRowChosenMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TimeViewSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TimeViewSetting(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      timelineSpanDays: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}timeline_span_days'])!,
      timelinePxPerDay: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}timeline_px_per_day'])!,
      timelineCollapsed: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}timeline_collapsed'])!,
      minutesPerRow: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}minutes_per_row'])!,
      minutesPerRowChosen: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}minutes_per_row_chosen'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $TimeViewSettingsTable createAlias(String alias) {
    return $TimeViewSettingsTable(attachedDatabase, alias);
  }
}

class TimeViewSetting extends DataClass implements Insertable<TimeViewSetting> {
  final int id;

  /// Total length of the multi-year timeline, in days.
  final int timelineSpanDays;

  /// Horizontal zoom of the timeline: pixels per day.
  final double timelinePxPerDay;

  /// Folded = the timeline wraps and scrolls vertically; unfolded = one row
  /// that scrolls horizontally.
  final bool timelineCollapsed;

  /// Last used minutes-per-row for the day/week grids (15 / 30 / 60).
  ///
  /// Defaults to 30: a whole-hour grid hides half-hour boundaries, so the
  /// finer grid is the default and the user zooms out when they want to.
  final int minutesPerRow;

  /// True once the user picked a row size themselves. Only used so the
  /// v4 -> v5 migration can move everyone who never chose off the old
  /// 60-minute default without touching a deliberate choice.
  final bool minutesPerRowChosen;
  final int? updatedAt;
  final int createdAt;
  const TimeViewSetting(
      {required this.id,
      required this.timelineSpanDays,
      required this.timelinePxPerDay,
      required this.timelineCollapsed,
      required this.minutesPerRow,
      required this.minutesPerRowChosen,
      this.updatedAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['timeline_span_days'] = Variable<int>(timelineSpanDays);
    map['timeline_px_per_day'] = Variable<double>(timelinePxPerDay);
    map['timeline_collapsed'] = Variable<bool>(timelineCollapsed);
    map['minutes_per_row'] = Variable<int>(minutesPerRow);
    map['minutes_per_row_chosen'] = Variable<bool>(minutesPerRowChosen);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  TimeViewSettingsCompanion toCompanion(bool nullToAbsent) {
    return TimeViewSettingsCompanion(
      id: Value(id),
      timelineSpanDays: Value(timelineSpanDays),
      timelinePxPerDay: Value(timelinePxPerDay),
      timelineCollapsed: Value(timelineCollapsed),
      minutesPerRow: Value(minutesPerRow),
      minutesPerRowChosen: Value(minutesPerRowChosen),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      createdAt: Value(createdAt),
    );
  }

  factory TimeViewSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TimeViewSetting(
      id: serializer.fromJson<int>(json['id']),
      timelineSpanDays: serializer.fromJson<int>(json['timelineSpanDays']),
      timelinePxPerDay: serializer.fromJson<double>(json['timelinePxPerDay']),
      timelineCollapsed: serializer.fromJson<bool>(json['timelineCollapsed']),
      minutesPerRow: serializer.fromJson<int>(json['minutesPerRow']),
      minutesPerRowChosen:
          serializer.fromJson<bool>(json['minutesPerRowChosen']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'timelineSpanDays': serializer.toJson<int>(timelineSpanDays),
      'timelinePxPerDay': serializer.toJson<double>(timelinePxPerDay),
      'timelineCollapsed': serializer.toJson<bool>(timelineCollapsed),
      'minutesPerRow': serializer.toJson<int>(minutesPerRow),
      'minutesPerRowChosen': serializer.toJson<bool>(minutesPerRowChosen),
      'updatedAt': serializer.toJson<int?>(updatedAt),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  TimeViewSetting copyWith(
          {int? id,
          int? timelineSpanDays,
          double? timelinePxPerDay,
          bool? timelineCollapsed,
          int? minutesPerRow,
          bool? minutesPerRowChosen,
          Value<int?> updatedAt = const Value.absent(),
          int? createdAt}) =>
      TimeViewSetting(
        id: id ?? this.id,
        timelineSpanDays: timelineSpanDays ?? this.timelineSpanDays,
        timelinePxPerDay: timelinePxPerDay ?? this.timelinePxPerDay,
        timelineCollapsed: timelineCollapsed ?? this.timelineCollapsed,
        minutesPerRow: minutesPerRow ?? this.minutesPerRow,
        minutesPerRowChosen: minutesPerRowChosen ?? this.minutesPerRowChosen,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
        createdAt: createdAt ?? this.createdAt,
      );
  TimeViewSetting copyWithCompanion(TimeViewSettingsCompanion data) {
    return TimeViewSetting(
      id: data.id.present ? data.id.value : this.id,
      timelineSpanDays: data.timelineSpanDays.present
          ? data.timelineSpanDays.value
          : this.timelineSpanDays,
      timelinePxPerDay: data.timelinePxPerDay.present
          ? data.timelinePxPerDay.value
          : this.timelinePxPerDay,
      timelineCollapsed: data.timelineCollapsed.present
          ? data.timelineCollapsed.value
          : this.timelineCollapsed,
      minutesPerRow: data.minutesPerRow.present
          ? data.minutesPerRow.value
          : this.minutesPerRow,
      minutesPerRowChosen: data.minutesPerRowChosen.present
          ? data.minutesPerRowChosen.value
          : this.minutesPerRowChosen,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TimeViewSetting(')
          ..write('id: $id, ')
          ..write('timelineSpanDays: $timelineSpanDays, ')
          ..write('timelinePxPerDay: $timelinePxPerDay, ')
          ..write('timelineCollapsed: $timelineCollapsed, ')
          ..write('minutesPerRow: $minutesPerRow, ')
          ..write('minutesPerRowChosen: $minutesPerRowChosen, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      timelineSpanDays,
      timelinePxPerDay,
      timelineCollapsed,
      minutesPerRow,
      minutesPerRowChosen,
      updatedAt,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimeViewSetting &&
          other.id == this.id &&
          other.timelineSpanDays == this.timelineSpanDays &&
          other.timelinePxPerDay == this.timelinePxPerDay &&
          other.timelineCollapsed == this.timelineCollapsed &&
          other.minutesPerRow == this.minutesPerRow &&
          other.minutesPerRowChosen == this.minutesPerRowChosen &&
          other.updatedAt == this.updatedAt &&
          other.createdAt == this.createdAt);
}

class TimeViewSettingsCompanion extends UpdateCompanion<TimeViewSetting> {
  final Value<int> id;
  final Value<int> timelineSpanDays;
  final Value<double> timelinePxPerDay;
  final Value<bool> timelineCollapsed;
  final Value<int> minutesPerRow;
  final Value<bool> minutesPerRowChosen;
  final Value<int?> updatedAt;
  final Value<int> createdAt;
  const TimeViewSettingsCompanion({
    this.id = const Value.absent(),
    this.timelineSpanDays = const Value.absent(),
    this.timelinePxPerDay = const Value.absent(),
    this.timelineCollapsed = const Value.absent(),
    this.minutesPerRow = const Value.absent(),
    this.minutesPerRowChosen = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TimeViewSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.timelineSpanDays = const Value.absent(),
    this.timelinePxPerDay = const Value.absent(),
    this.timelineCollapsed = const Value.absent(),
    this.minutesPerRow = const Value.absent(),
    this.minutesPerRowChosen = const Value.absent(),
    this.updatedAt = const Value.absent(),
    required int createdAt,
  }) : createdAt = Value(createdAt);
  static Insertable<TimeViewSetting> custom({
    Expression<int>? id,
    Expression<int>? timelineSpanDays,
    Expression<double>? timelinePxPerDay,
    Expression<bool>? timelineCollapsed,
    Expression<int>? minutesPerRow,
    Expression<bool>? minutesPerRowChosen,
    Expression<int>? updatedAt,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (timelineSpanDays != null) 'timeline_span_days': timelineSpanDays,
      if (timelinePxPerDay != null) 'timeline_px_per_day': timelinePxPerDay,
      if (timelineCollapsed != null) 'timeline_collapsed': timelineCollapsed,
      if (minutesPerRow != null) 'minutes_per_row': minutesPerRow,
      if (minutesPerRowChosen != null)
        'minutes_per_row_chosen': minutesPerRowChosen,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TimeViewSettingsCompanion copyWith(
      {Value<int>? id,
      Value<int>? timelineSpanDays,
      Value<double>? timelinePxPerDay,
      Value<bool>? timelineCollapsed,
      Value<int>? minutesPerRow,
      Value<bool>? minutesPerRowChosen,
      Value<int?>? updatedAt,
      Value<int>? createdAt}) {
    return TimeViewSettingsCompanion(
      id: id ?? this.id,
      timelineSpanDays: timelineSpanDays ?? this.timelineSpanDays,
      timelinePxPerDay: timelinePxPerDay ?? this.timelinePxPerDay,
      timelineCollapsed: timelineCollapsed ?? this.timelineCollapsed,
      minutesPerRow: minutesPerRow ?? this.minutesPerRow,
      minutesPerRowChosen: minutesPerRowChosen ?? this.minutesPerRowChosen,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (timelineSpanDays.present) {
      map['timeline_span_days'] = Variable<int>(timelineSpanDays.value);
    }
    if (timelinePxPerDay.present) {
      map['timeline_px_per_day'] = Variable<double>(timelinePxPerDay.value);
    }
    if (timelineCollapsed.present) {
      map['timeline_collapsed'] = Variable<bool>(timelineCollapsed.value);
    }
    if (minutesPerRow.present) {
      map['minutes_per_row'] = Variable<int>(minutesPerRow.value);
    }
    if (minutesPerRowChosen.present) {
      map['minutes_per_row_chosen'] = Variable<bool>(minutesPerRowChosen.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TimeViewSettingsCompanion(')
          ..write('id: $id, ')
          ..write('timelineSpanDays: $timelineSpanDays, ')
          ..write('timelinePxPerDay: $timelinePxPerDay, ')
          ..write('timelineCollapsed: $timelineCollapsed, ')
          ..write('minutesPerRow: $minutesPerRow, ')
          ..write('minutesPerRowChosen: $minutesPerRowChosen, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $AiConversationsTable extends AiConversations
    with TableInfo<$AiConversationsTable, AiConversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, title, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_conversations';
  @override
  VerificationContext validateIntegrity(Insertable<AiConversation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiConversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiConversation(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $AiConversationsTable createAlias(String alias) {
    return $AiConversationsTable(attachedDatabase, alias);
  }
}

class AiConversation extends DataClass implements Insertable<AiConversation> {
  final String id;

  /// Human label shown in the conversation list. Never empty: falls back to a
  /// timestamp when the first message is empty.
  final String title;
  final int createdAt;
  final int updatedAt;
  const AiConversation(
      {required this.id,
      required this.title,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  AiConversationsCompanion toCompanion(bool nullToAbsent) {
    return AiConversationsCompanion(
      id: Value(id),
      title: Value(title),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AiConversation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiConversation(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  AiConversation copyWith(
          {String? id, String? title, int? createdAt, int? updatedAt}) =>
      AiConversation(
        id: id ?? this.id,
        title: title ?? this.title,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AiConversation copyWithCompanion(AiConversationsCompanion data) {
    return AiConversation(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiConversation(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiConversation &&
          other.id == this.id &&
          other.title == this.title &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AiConversationsCompanion extends UpdateCompanion<AiConversation> {
  final Value<String> id;
  final Value<String> title;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const AiConversationsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiConversationsCompanion.insert({
    required String id,
    required String title,
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<AiConversation> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiConversationsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return AiConversationsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiConversationsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiMessagesTable extends AiMessages
    with TableInfo<$AiMessagesTable, AiMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
      'conversation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _toolCallIdMeta =
      const VerificationMeta('toolCallId');
  @override
  late final GeneratedColumn<String> toolCallId = GeneratedColumn<String>(
      'tool_call_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, conversationId, role, content, toolCallId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_messages';
  @override
  VerificationContext validateIntegrity(Insertable<AiMessage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    }
    if (data.containsKey('tool_call_id')) {
      context.handle(
          _toolCallIdMeta,
          toolCallId.isAcceptableOrUnknown(
              data['tool_call_id']!, _toolCallIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiMessage(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      conversationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conversation_id'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content']),
      toolCallId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tool_call_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $AiMessagesTable createAlias(String alias) {
    return $AiMessagesTable(attachedDatabase, alias);
  }
}

class AiMessage extends DataClass implements Insertable<AiMessage> {
  final String id;
  final String conversationId;

  /// `user` | `assistant` | `tool` | `system`.
  final String role;

  /// Message body. For `tool` rows this is the JSON result handed back to the
  /// model; for `assistant` rows it may be empty when the turn was pure tool
  /// calls.
  final String? content;

  /// Provider tool-call id, only set on `tool` rows. Needed because the Chat
  /// Completion API rejects a tool result whose id does not match the request
  /// that produced it.
  final String? toolCallId;
  final int createdAt;
  const AiMessage(
      {required this.id,
      required this.conversationId,
      required this.role,
      this.content,
      this.toolCallId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['role'] = Variable<String>(role);
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    if (!nullToAbsent || toolCallId != null) {
      map['tool_call_id'] = Variable<String>(toolCallId);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  AiMessagesCompanion toCompanion(bool nullToAbsent) {
    return AiMessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      role: Value(role),
      content: content == null && nullToAbsent
          ? const Value.absent()
          : Value(content),
      toolCallId: toolCallId == null && nullToAbsent
          ? const Value.absent()
          : Value(toolCallId),
      createdAt: Value(createdAt),
    );
  }

  factory AiMessage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiMessage(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String?>(json['content']),
      toolCallId: serializer.fromJson<String?>(json['toolCallId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String?>(content),
      'toolCallId': serializer.toJson<String?>(toolCallId),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  AiMessage copyWith(
          {String? id,
          String? conversationId,
          String? role,
          Value<String?> content = const Value.absent(),
          Value<String?> toolCallId = const Value.absent(),
          int? createdAt}) =>
      AiMessage(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        role: role ?? this.role,
        content: content.present ? content.value : this.content,
        toolCallId: toolCallId.present ? toolCallId.value : this.toolCallId,
        createdAt: createdAt ?? this.createdAt,
      );
  AiMessage copyWithCompanion(AiMessagesCompanion data) {
    return AiMessage(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      toolCallId:
          data.toolCallId.present ? data.toolCallId.value : this.toolCallId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiMessage(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, conversationId, role, content, toolCallId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiMessage &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.role == this.role &&
          other.content == this.content &&
          other.toolCallId == this.toolCallId &&
          other.createdAt == this.createdAt);
}

class AiMessagesCompanion extends UpdateCompanion<AiMessage> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> role;
  final Value<String?> content;
  final Value<String?> toolCallId;
  final Value<int> createdAt;
  final Value<int> rowid;
  const AiMessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.toolCallId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiMessagesCompanion.insert({
    required String id,
    required String conversationId,
    required String role,
    this.content = const Value.absent(),
    this.toolCallId = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        conversationId = Value(conversationId),
        role = Value(role),
        createdAt = Value(createdAt);
  static Insertable<AiMessage> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? toolCallId,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (toolCallId != null) 'tool_call_id': toolCallId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiMessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? conversationId,
      Value<String>? role,
      Value<String?>? content,
      Value<String?>? toolCallId,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return AiMessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      toolCallId: toolCallId ?? this.toolCallId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (toolCallId.present) {
      map['tool_call_id'] = Variable<String>(toolCallId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiMessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiActionsTable extends AiActions
    with TableInfo<$AiActionsTable, AiAction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiActionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _messageIdMeta =
      const VerificationMeta('messageId');
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
      'message_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
      'conversation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _toolCallIdMeta =
      const VerificationMeta('toolCallId');
  @override
  late final GeneratedColumn<String> toolCallId = GeneratedColumn<String>(
      'tool_call_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _toolNameMeta =
      const VerificationMeta('toolName');
  @override
  late final GeneratedColumn<String> toolName = GeneratedColumn<String>(
      'tool_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _argsJsonMeta =
      const VerificationMeta('argsJson');
  @override
  late final GeneratedColumn<String> argsJson = GeneratedColumn<String>(
      'args_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _riskMeta = const VerificationMeta('risk');
  @override
  late final GeneratedColumn<String> risk = GeneratedColumn<String>(
      'risk', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _beforeJsonMeta =
      const VerificationMeta('beforeJson');
  @override
  late final GeneratedColumn<String> beforeJson = GeneratedColumn<String>(
      'before_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _afterJsonMeta =
      const VerificationMeta('afterJson');
  @override
  late final GeneratedColumn<String> afterJson = GeneratedColumn<String>(
      'after_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _resultJsonMeta =
      const VerificationMeta('resultJson');
  @override
  late final GeneratedColumn<String> resultJson = GeneratedColumn<String>(
      'result_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        messageId,
        conversationId,
        toolCallId,
        toolName,
        argsJson,
        risk,
        status,
        beforeJson,
        afterJson,
        resultJson,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_actions';
  @override
  VerificationContext validateIntegrity(Insertable<AiAction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(_messageIdMeta,
          messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta));
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('tool_call_id')) {
      context.handle(
          _toolCallIdMeta,
          toolCallId.isAcceptableOrUnknown(
              data['tool_call_id']!, _toolCallIdMeta));
    }
    if (data.containsKey('tool_name')) {
      context.handle(_toolNameMeta,
          toolName.isAcceptableOrUnknown(data['tool_name']!, _toolNameMeta));
    } else if (isInserting) {
      context.missing(_toolNameMeta);
    }
    if (data.containsKey('args_json')) {
      context.handle(_argsJsonMeta,
          argsJson.isAcceptableOrUnknown(data['args_json']!, _argsJsonMeta));
    } else if (isInserting) {
      context.missing(_argsJsonMeta);
    }
    if (data.containsKey('risk')) {
      context.handle(
          _riskMeta, risk.isAcceptableOrUnknown(data['risk']!, _riskMeta));
    } else if (isInserting) {
      context.missing(_riskMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('before_json')) {
      context.handle(
          _beforeJsonMeta,
          beforeJson.isAcceptableOrUnknown(
              data['before_json']!, _beforeJsonMeta));
    }
    if (data.containsKey('after_json')) {
      context.handle(_afterJsonMeta,
          afterJson.isAcceptableOrUnknown(data['after_json']!, _afterJsonMeta));
    }
    if (data.containsKey('result_json')) {
      context.handle(
          _resultJsonMeta,
          resultJson.isAcceptableOrUnknown(
              data['result_json']!, _resultJsonMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiAction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiAction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      messageId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message_id']),
      conversationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conversation_id'])!,
      toolCallId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tool_call_id']),
      toolName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tool_name'])!,
      argsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}args_json'])!,
      risk: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}risk'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      beforeJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}before_json']),
      afterJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}after_json']),
      resultJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}result_json']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at']),
    );
  }

  @override
  $AiActionsTable createAlias(String alias) {
    return $AiActionsTable(attachedDatabase, alias);
  }
}

class AiAction extends DataClass implements Insertable<AiAction> {
  final String id;

  /// The assistant message whose turn proposed this call.
  final String? messageId;
  final String conversationId;

  /// Provider-side call id, so a result can be matched back.
  final String? toolCallId;
  final String toolName;

  /// Raw JSON arguments exactly as the model produced them. Kept verbatim so a
  /// failed validation can be shown to the user and replayed.
  final String argsJson;

  /// `write` | `destructive` (mirrors ToolRisk).
  final String risk;

  /// `pending` | `approved` | `rejected` | `executed` | `failed`.
  final String status;

  /// Row(s) as they were before the call, JSON. Enables undo.
  final String? beforeJson;

  /// Row(s) as they became, JSON.
  final String? afterJson;

  /// Failure reason, or the human-readable result summary.
  final String? resultJson;
  final int createdAt;
  final int? updatedAt;
  const AiAction(
      {required this.id,
      this.messageId,
      required this.conversationId,
      this.toolCallId,
      required this.toolName,
      required this.argsJson,
      required this.risk,
      required this.status,
      this.beforeJson,
      this.afterJson,
      this.resultJson,
      required this.createdAt,
      this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || messageId != null) {
      map['message_id'] = Variable<String>(messageId);
    }
    map['conversation_id'] = Variable<String>(conversationId);
    if (!nullToAbsent || toolCallId != null) {
      map['tool_call_id'] = Variable<String>(toolCallId);
    }
    map['tool_name'] = Variable<String>(toolName);
    map['args_json'] = Variable<String>(argsJson);
    map['risk'] = Variable<String>(risk);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || beforeJson != null) {
      map['before_json'] = Variable<String>(beforeJson);
    }
    if (!nullToAbsent || afterJson != null) {
      map['after_json'] = Variable<String>(afterJson);
    }
    if (!nullToAbsent || resultJson != null) {
      map['result_json'] = Variable<String>(resultJson);
    }
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    return map;
  }

  AiActionsCompanion toCompanion(bool nullToAbsent) {
    return AiActionsCompanion(
      id: Value(id),
      messageId: messageId == null && nullToAbsent
          ? const Value.absent()
          : Value(messageId),
      conversationId: Value(conversationId),
      toolCallId: toolCallId == null && nullToAbsent
          ? const Value.absent()
          : Value(toolCallId),
      toolName: Value(toolName),
      argsJson: Value(argsJson),
      risk: Value(risk),
      status: Value(status),
      beforeJson: beforeJson == null && nullToAbsent
          ? const Value.absent()
          : Value(beforeJson),
      afterJson: afterJson == null && nullToAbsent
          ? const Value.absent()
          : Value(afterJson),
      resultJson: resultJson == null && nullToAbsent
          ? const Value.absent()
          : Value(resultJson),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory AiAction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiAction(
      id: serializer.fromJson<String>(json['id']),
      messageId: serializer.fromJson<String?>(json['messageId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      toolCallId: serializer.fromJson<String?>(json['toolCallId']),
      toolName: serializer.fromJson<String>(json['toolName']),
      argsJson: serializer.fromJson<String>(json['argsJson']),
      risk: serializer.fromJson<String>(json['risk']),
      status: serializer.fromJson<String>(json['status']),
      beforeJson: serializer.fromJson<String?>(json['beforeJson']),
      afterJson: serializer.fromJson<String?>(json['afterJson']),
      resultJson: serializer.fromJson<String?>(json['resultJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'messageId': serializer.toJson<String?>(messageId),
      'conversationId': serializer.toJson<String>(conversationId),
      'toolCallId': serializer.toJson<String?>(toolCallId),
      'toolName': serializer.toJson<String>(toolName),
      'argsJson': serializer.toJson<String>(argsJson),
      'risk': serializer.toJson<String>(risk),
      'status': serializer.toJson<String>(status),
      'beforeJson': serializer.toJson<String?>(beforeJson),
      'afterJson': serializer.toJson<String?>(afterJson),
      'resultJson': serializer.toJson<String?>(resultJson),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int?>(updatedAt),
    };
  }

  AiAction copyWith(
          {String? id,
          Value<String?> messageId = const Value.absent(),
          String? conversationId,
          Value<String?> toolCallId = const Value.absent(),
          String? toolName,
          String? argsJson,
          String? risk,
          String? status,
          Value<String?> beforeJson = const Value.absent(),
          Value<String?> afterJson = const Value.absent(),
          Value<String?> resultJson = const Value.absent(),
          int? createdAt,
          Value<int?> updatedAt = const Value.absent()}) =>
      AiAction(
        id: id ?? this.id,
        messageId: messageId.present ? messageId.value : this.messageId,
        conversationId: conversationId ?? this.conversationId,
        toolCallId: toolCallId.present ? toolCallId.value : this.toolCallId,
        toolName: toolName ?? this.toolName,
        argsJson: argsJson ?? this.argsJson,
        risk: risk ?? this.risk,
        status: status ?? this.status,
        beforeJson: beforeJson.present ? beforeJson.value : this.beforeJson,
        afterJson: afterJson.present ? afterJson.value : this.afterJson,
        resultJson: resultJson.present ? resultJson.value : this.resultJson,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
      );
  AiAction copyWithCompanion(AiActionsCompanion data) {
    return AiAction(
      id: data.id.present ? data.id.value : this.id,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      toolCallId:
          data.toolCallId.present ? data.toolCallId.value : this.toolCallId,
      toolName: data.toolName.present ? data.toolName.value : this.toolName,
      argsJson: data.argsJson.present ? data.argsJson.value : this.argsJson,
      risk: data.risk.present ? data.risk.value : this.risk,
      status: data.status.present ? data.status.value : this.status,
      beforeJson:
          data.beforeJson.present ? data.beforeJson.value : this.beforeJson,
      afterJson: data.afterJson.present ? data.afterJson.value : this.afterJson,
      resultJson:
          data.resultJson.present ? data.resultJson.value : this.resultJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiAction(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('toolName: $toolName, ')
          ..write('argsJson: $argsJson, ')
          ..write('risk: $risk, ')
          ..write('status: $status, ')
          ..write('beforeJson: $beforeJson, ')
          ..write('afterJson: $afterJson, ')
          ..write('resultJson: $resultJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      messageId,
      conversationId,
      toolCallId,
      toolName,
      argsJson,
      risk,
      status,
      beforeJson,
      afterJson,
      resultJson,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiAction &&
          other.id == this.id &&
          other.messageId == this.messageId &&
          other.conversationId == this.conversationId &&
          other.toolCallId == this.toolCallId &&
          other.toolName == this.toolName &&
          other.argsJson == this.argsJson &&
          other.risk == this.risk &&
          other.status == this.status &&
          other.beforeJson == this.beforeJson &&
          other.afterJson == this.afterJson &&
          other.resultJson == this.resultJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AiActionsCompanion extends UpdateCompanion<AiAction> {
  final Value<String> id;
  final Value<String?> messageId;
  final Value<String> conversationId;
  final Value<String?> toolCallId;
  final Value<String> toolName;
  final Value<String> argsJson;
  final Value<String> risk;
  final Value<String> status;
  final Value<String?> beforeJson;
  final Value<String?> afterJson;
  final Value<String?> resultJson;
  final Value<int> createdAt;
  final Value<int?> updatedAt;
  final Value<int> rowid;
  const AiActionsCompanion({
    this.id = const Value.absent(),
    this.messageId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.toolCallId = const Value.absent(),
    this.toolName = const Value.absent(),
    this.argsJson = const Value.absent(),
    this.risk = const Value.absent(),
    this.status = const Value.absent(),
    this.beforeJson = const Value.absent(),
    this.afterJson = const Value.absent(),
    this.resultJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiActionsCompanion.insert({
    required String id,
    this.messageId = const Value.absent(),
    required String conversationId,
    this.toolCallId = const Value.absent(),
    required String toolName,
    required String argsJson,
    required String risk,
    required String status,
    this.beforeJson = const Value.absent(),
    this.afterJson = const Value.absent(),
    this.resultJson = const Value.absent(),
    required int createdAt,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        conversationId = Value(conversationId),
        toolName = Value(toolName),
        argsJson = Value(argsJson),
        risk = Value(risk),
        status = Value(status),
        createdAt = Value(createdAt);
  static Insertable<AiAction> custom({
    Expression<String>? id,
    Expression<String>? messageId,
    Expression<String>? conversationId,
    Expression<String>? toolCallId,
    Expression<String>? toolName,
    Expression<String>? argsJson,
    Expression<String>? risk,
    Expression<String>? status,
    Expression<String>? beforeJson,
    Expression<String>? afterJson,
    Expression<String>? resultJson,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageId != null) 'message_id': messageId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (toolCallId != null) 'tool_call_id': toolCallId,
      if (toolName != null) 'tool_name': toolName,
      if (argsJson != null) 'args_json': argsJson,
      if (risk != null) 'risk': risk,
      if (status != null) 'status': status,
      if (beforeJson != null) 'before_json': beforeJson,
      if (afterJson != null) 'after_json': afterJson,
      if (resultJson != null) 'result_json': resultJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiActionsCompanion copyWith(
      {Value<String>? id,
      Value<String?>? messageId,
      Value<String>? conversationId,
      Value<String?>? toolCallId,
      Value<String>? toolName,
      Value<String>? argsJson,
      Value<String>? risk,
      Value<String>? status,
      Value<String?>? beforeJson,
      Value<String?>? afterJson,
      Value<String?>? resultJson,
      Value<int>? createdAt,
      Value<int?>? updatedAt,
      Value<int>? rowid}) {
    return AiActionsCompanion(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      argsJson: argsJson ?? this.argsJson,
      risk: risk ?? this.risk,
      status: status ?? this.status,
      beforeJson: beforeJson ?? this.beforeJson,
      afterJson: afterJson ?? this.afterJson,
      resultJson: resultJson ?? this.resultJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (toolCallId.present) {
      map['tool_call_id'] = Variable<String>(toolCallId.value);
    }
    if (toolName.present) {
      map['tool_name'] = Variable<String>(toolName.value);
    }
    if (argsJson.present) {
      map['args_json'] = Variable<String>(argsJson.value);
    }
    if (risk.present) {
      map['risk'] = Variable<String>(risk.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (beforeJson.present) {
      map['before_json'] = Variable<String>(beforeJson.value);
    }
    if (afterJson.present) {
      map['after_json'] = Variable<String>(afterJson.value);
    }
    if (resultJson.present) {
      map['result_json'] = Variable<String>(resultJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiActionsCompanion(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('toolName: $toolName, ')
          ..write('argsJson: $argsJson, ')
          ..write('risk: $risk, ')
          ..write('status: $status, ')
          ..write('beforeJson: $beforeJson, ')
          ..write('afterJson: $afterJson, ')
          ..write('resultJson: $resultJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $LocalSettingsTable localSettings = $LocalSettingsTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $ObjectTagsTable objectTags = $ObjectTagsTable(this);
  late final $MindMapsTable mindMaps = $MindMapsTable(this);
  late final $MindNodesTable mindNodes = $MindNodesTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $TaskDependenciesTable taskDependencies =
      $TaskDependenciesTable(this);
  late final $TimeBlocksTable timeBlocks = $TimeBlocksTable(this);
  late final $TaskTimeBlocksTable taskTimeBlocks = $TaskTimeBlocksTable(this);
  late final $KnowledgePointsTable knowledgePoints =
      $KnowledgePointsTable(this);
  late final $CardTemplatesTable cardTemplates = $CardTemplatesTable(this);
  late final $CardStatesTable cardStates = $CardStatesTable(this);
  late final $ReviewLogsTable reviewLogs = $ReviewLogsTable(this);
  late final $KnowledgePackagesTable knowledgePackages =
      $KnowledgePackagesTable(this);
  late final $PackageItemsTable packageItems = $PackageItemsTable(this);
  late final $ThreadStatesTable threadStates = $ThreadStatesTable(this);
  late final $TaskTemplatesTable taskTemplates = $TaskTemplatesTable(this);
  late final $CompletionLogsTable completionLogs = $CompletionLogsTable(this);
  late final $ClozeSlotsTable clozeSlots = $ClozeSlotsTable(this);
  late final $ClozeHistoryTable clozeHistory = $ClozeHistoryTable(this);
  late final $BoostEntriesTable boostEntries = $BoostEntriesTable(this);
  late final $ThemesTable themes = $ThemesTable(this);
  late final $AttachmentsTable attachments = $AttachmentsTable(this);
  late final $ThreadRankSettingsTable threadRankSettings =
      $ThreadRankSettingsTable(this);
  late final $DiffusionLogsTable diffusionLogs = $DiffusionLogsTable(this);
  late final $TimeTemplatesTable timeTemplates = $TimeTemplatesTable(this);
  late final $TimeViewSettingsTable timeViewSettings =
      $TimeViewSettingsTable(this);
  late final $AiConversationsTable aiConversations =
      $AiConversationsTable(this);
  late final $AiMessagesTable aiMessages = $AiMessagesTable(this);
  late final $AiActionsTable aiActions = $AiActionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        profiles,
        localSettings,
        tags,
        objectTags,
        mindMaps,
        mindNodes,
        tasks,
        taskDependencies,
        timeBlocks,
        taskTimeBlocks,
        knowledgePoints,
        cardTemplates,
        cardStates,
        reviewLogs,
        knowledgePackages,
        packageItems,
        threadStates,
        taskTemplates,
        completionLogs,
        clozeSlots,
        clozeHistory,
        boostEntries,
        themes,
        attachments,
        threadRankSettings,
        diffusionLogs,
        timeTemplates,
        timeViewSettings,
        aiConversations,
        aiMessages,
        aiActions
      ];
}

typedef $$ProfilesTableCreateCompanionBuilder = ProfilesCompanion Function({
  required String id,
  required String displayName,
  Value<int?> avatarColor,
  required int createdAt,
  Value<int> rowid,
});
typedef $$ProfilesTableUpdateCompanionBuilder = ProfilesCompanion Function({
  Value<String> id,
  Value<String> displayName,
  Value<int?> avatarColor,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$ProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get avatarColor => $composableBuilder(
      column: $table.avatarColor, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get avatarColor => $composableBuilder(
      column: $table.avatarColor, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<int> get avatarColor => $composableBuilder(
      column: $table.avatarColor, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ProfilesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProfilesTable,
    Profile,
    $$ProfilesTableFilterComposer,
    $$ProfilesTableOrderingComposer,
    $$ProfilesTableAnnotationComposer,
    $$ProfilesTableCreateCompanionBuilder,
    $$ProfilesTableUpdateCompanionBuilder,
    (Profile, BaseReferences<_$AppDatabase, $ProfilesTable, Profile>),
    Profile,
    PrefetchHooks Function()> {
  $$ProfilesTableTableManager(_$AppDatabase db, $ProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            Value<int?> avatarColor = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProfilesCompanion(
            id: id,
            displayName: displayName,
            avatarColor: avatarColor,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String displayName,
            Value<int?> avatarColor = const Value.absent(),
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ProfilesCompanion.insert(
            id: id,
            displayName: displayName,
            avatarColor: avatarColor,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ProfilesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProfilesTable,
    Profile,
    $$ProfilesTableFilterComposer,
    $$ProfilesTableOrderingComposer,
    $$ProfilesTableAnnotationComposer,
    $$ProfilesTableCreateCompanionBuilder,
    $$ProfilesTableUpdateCompanionBuilder,
    (Profile, BaseReferences<_$AppDatabase, $ProfilesTable, Profile>),
    Profile,
    PrefetchHooks Function()>;
typedef $$LocalSettingsTableCreateCompanionBuilder = LocalSettingsCompanion
    Function({
  Value<int> id,
  Value<String> language,
  Value<String> themeMode,
  Value<String?> profileId,
  Value<String?> activeThemeId,
  Value<bool> aiEnabled,
  Value<String?> aiApiKey,
  Value<String?> aiBaseUrl,
  Value<String?> aiModel,
  Value<String?> aiPermissionMode,
  required int createdAt,
  required int updatedAt,
});
typedef $$LocalSettingsTableUpdateCompanionBuilder = LocalSettingsCompanion
    Function({
  Value<int> id,
  Value<String> language,
  Value<String> themeMode,
  Value<String?> profileId,
  Value<String?> activeThemeId,
  Value<bool> aiEnabled,
  Value<String?> aiApiKey,
  Value<String?> aiBaseUrl,
  Value<String?> aiModel,
  Value<String?> aiPermissionMode,
  Value<int> createdAt,
  Value<int> updatedAt,
});

class $$LocalSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalSettingsTable> {
  $$LocalSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get language => $composableBuilder(
      column: $table.language, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get themeMode => $composableBuilder(
      column: $table.themeMode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get profileId => $composableBuilder(
      column: $table.profileId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get activeThemeId => $composableBuilder(
      column: $table.activeThemeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get aiEnabled => $composableBuilder(
      column: $table.aiEnabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get aiApiKey => $composableBuilder(
      column: $table.aiApiKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get aiBaseUrl => $composableBuilder(
      column: $table.aiBaseUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get aiModel => $composableBuilder(
      column: $table.aiModel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get aiPermissionMode => $composableBuilder(
      column: $table.aiPermissionMode,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalSettingsTable> {
  $$LocalSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get language => $composableBuilder(
      column: $table.language, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get themeMode => $composableBuilder(
      column: $table.themeMode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get profileId => $composableBuilder(
      column: $table.profileId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get activeThemeId => $composableBuilder(
      column: $table.activeThemeId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get aiEnabled => $composableBuilder(
      column: $table.aiEnabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get aiApiKey => $composableBuilder(
      column: $table.aiApiKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get aiBaseUrl => $composableBuilder(
      column: $table.aiBaseUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get aiModel => $composableBuilder(
      column: $table.aiModel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get aiPermissionMode => $composableBuilder(
      column: $table.aiPermissionMode,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalSettingsTable> {
  $$LocalSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get themeMode =>
      $composableBuilder(column: $table.themeMode, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get activeThemeId => $composableBuilder(
      column: $table.activeThemeId, builder: (column) => column);

  GeneratedColumn<bool> get aiEnabled =>
      $composableBuilder(column: $table.aiEnabled, builder: (column) => column);

  GeneratedColumn<String> get aiApiKey =>
      $composableBuilder(column: $table.aiApiKey, builder: (column) => column);

  GeneratedColumn<String> get aiBaseUrl =>
      $composableBuilder(column: $table.aiBaseUrl, builder: (column) => column);

  GeneratedColumn<String> get aiModel =>
      $composableBuilder(column: $table.aiModel, builder: (column) => column);

  GeneratedColumn<String> get aiPermissionMode => $composableBuilder(
      column: $table.aiPermissionMode, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalSettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalSettingsTable,
    LocalSetting,
    $$LocalSettingsTableFilterComposer,
    $$LocalSettingsTableOrderingComposer,
    $$LocalSettingsTableAnnotationComposer,
    $$LocalSettingsTableCreateCompanionBuilder,
    $$LocalSettingsTableUpdateCompanionBuilder,
    (
      LocalSetting,
      BaseReferences<_$AppDatabase, $LocalSettingsTable, LocalSetting>
    ),
    LocalSetting,
    PrefetchHooks Function()> {
  $$LocalSettingsTableTableManager(_$AppDatabase db, $LocalSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> language = const Value.absent(),
            Value<String> themeMode = const Value.absent(),
            Value<String?> profileId = const Value.absent(),
            Value<String?> activeThemeId = const Value.absent(),
            Value<bool> aiEnabled = const Value.absent(),
            Value<String?> aiApiKey = const Value.absent(),
            Value<String?> aiBaseUrl = const Value.absent(),
            Value<String?> aiModel = const Value.absent(),
            Value<String?> aiPermissionMode = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
          }) =>
              LocalSettingsCompanion(
            id: id,
            language: language,
            themeMode: themeMode,
            profileId: profileId,
            activeThemeId: activeThemeId,
            aiEnabled: aiEnabled,
            aiApiKey: aiApiKey,
            aiBaseUrl: aiBaseUrl,
            aiModel: aiModel,
            aiPermissionMode: aiPermissionMode,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> language = const Value.absent(),
            Value<String> themeMode = const Value.absent(),
            Value<String?> profileId = const Value.absent(),
            Value<String?> activeThemeId = const Value.absent(),
            Value<bool> aiEnabled = const Value.absent(),
            Value<String?> aiApiKey = const Value.absent(),
            Value<String?> aiBaseUrl = const Value.absent(),
            Value<String?> aiModel = const Value.absent(),
            Value<String?> aiPermissionMode = const Value.absent(),
            required int createdAt,
            required int updatedAt,
          }) =>
              LocalSettingsCompanion.insert(
            id: id,
            language: language,
            themeMode: themeMode,
            profileId: profileId,
            activeThemeId: activeThemeId,
            aiEnabled: aiEnabled,
            aiApiKey: aiApiKey,
            aiBaseUrl: aiBaseUrl,
            aiModel: aiModel,
            aiPermissionMode: aiPermissionMode,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalSettingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalSettingsTable,
    LocalSetting,
    $$LocalSettingsTableFilterComposer,
    $$LocalSettingsTableOrderingComposer,
    $$LocalSettingsTableAnnotationComposer,
    $$LocalSettingsTableCreateCompanionBuilder,
    $$LocalSettingsTableUpdateCompanionBuilder,
    (
      LocalSetting,
      BaseReferences<_$AppDatabase, $LocalSettingsTable, LocalSetting>
    ),
    LocalSetting,
    PrefetchHooks Function()>;
typedef $$TagsTableCreateCompanionBuilder = TagsCompanion Function({
  required String id,
  Value<String?> parentId,
  required String name,
  Value<String?> path,
  Value<int?> color,
  Value<String?> description,
  Value<String?> sourceNodeId,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$TagsTableUpdateCompanionBuilder = TagsCompanion Function({
  Value<String> id,
  Value<String?> parentId,
  Value<String> name,
  Value<String?> path,
  Value<int?> color,
  Value<String?> description,
  Value<String?> sourceNodeId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceNodeId => $composableBuilder(
      column: $table.sourceNodeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceNodeId => $composableBuilder(
      column: $table.sourceNodeId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get sourceNodeId => $composableBuilder(
      column: $table.sourceNodeId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TagsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TagsTable,
    Tag,
    $$TagsTableFilterComposer,
    $$TagsTableOrderingComposer,
    $$TagsTableAnnotationComposer,
    $$TagsTableCreateCompanionBuilder,
    $$TagsTableUpdateCompanionBuilder,
    (Tag, BaseReferences<_$AppDatabase, $TagsTable, Tag>),
    Tag,
    PrefetchHooks Function()> {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> parentId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> path = const Value.absent(),
            Value<int?> color = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> sourceNodeId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TagsCompanion(
            id: id,
            parentId: parentId,
            name: name,
            path: path,
            color: color,
            description: description,
            sourceNodeId: sourceNodeId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> parentId = const Value.absent(),
            required String name,
            Value<String?> path = const Value.absent(),
            Value<int?> color = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> sourceNodeId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TagsCompanion.insert(
            id: id,
            parentId: parentId,
            name: name,
            path: path,
            color: color,
            description: description,
            sourceNodeId: sourceNodeId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TagsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TagsTable,
    Tag,
    $$TagsTableFilterComposer,
    $$TagsTableOrderingComposer,
    $$TagsTableAnnotationComposer,
    $$TagsTableCreateCompanionBuilder,
    $$TagsTableUpdateCompanionBuilder,
    (Tag, BaseReferences<_$AppDatabase, $TagsTable, Tag>),
    Tag,
    PrefetchHooks Function()>;
typedef $$ObjectTagsTableCreateCompanionBuilder = ObjectTagsCompanion Function({
  required String id,
  required String tagId,
  required String objectType,
  required String objectId,
  required int createdAt,
  Value<int> rowid,
});
typedef $$ObjectTagsTableUpdateCompanionBuilder = ObjectTagsCompanion Function({
  Value<String> id,
  Value<String> tagId,
  Value<String> objectType,
  Value<String> objectId,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$ObjectTagsTableFilterComposer
    extends Composer<_$AppDatabase, $ObjectTagsTable> {
  $$ObjectTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagId => $composableBuilder(
      column: $table.tagId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get objectType => $composableBuilder(
      column: $table.objectType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get objectId => $composableBuilder(
      column: $table.objectId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ObjectTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $ObjectTagsTable> {
  $$ObjectTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagId => $composableBuilder(
      column: $table.tagId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get objectType => $composableBuilder(
      column: $table.objectType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get objectId => $composableBuilder(
      column: $table.objectId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ObjectTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ObjectTagsTable> {
  $$ObjectTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);

  GeneratedColumn<String> get objectType => $composableBuilder(
      column: $table.objectType, builder: (column) => column);

  GeneratedColumn<String> get objectId =>
      $composableBuilder(column: $table.objectId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ObjectTagsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ObjectTagsTable,
    ObjectTag,
    $$ObjectTagsTableFilterComposer,
    $$ObjectTagsTableOrderingComposer,
    $$ObjectTagsTableAnnotationComposer,
    $$ObjectTagsTableCreateCompanionBuilder,
    $$ObjectTagsTableUpdateCompanionBuilder,
    (ObjectTag, BaseReferences<_$AppDatabase, $ObjectTagsTable, ObjectTag>),
    ObjectTag,
    PrefetchHooks Function()> {
  $$ObjectTagsTableTableManager(_$AppDatabase db, $ObjectTagsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ObjectTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ObjectTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ObjectTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> tagId = const Value.absent(),
            Value<String> objectType = const Value.absent(),
            Value<String> objectId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ObjectTagsCompanion(
            id: id,
            tagId: tagId,
            objectType: objectType,
            objectId: objectId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String tagId,
            required String objectType,
            required String objectId,
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ObjectTagsCompanion.insert(
            id: id,
            tagId: tagId,
            objectType: objectType,
            objectId: objectId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ObjectTagsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ObjectTagsTable,
    ObjectTag,
    $$ObjectTagsTableFilterComposer,
    $$ObjectTagsTableOrderingComposer,
    $$ObjectTagsTableAnnotationComposer,
    $$ObjectTagsTableCreateCompanionBuilder,
    $$ObjectTagsTableUpdateCompanionBuilder,
    (ObjectTag, BaseReferences<_$AppDatabase, $ObjectTagsTable, ObjectTag>),
    ObjectTag,
    PrefetchHooks Function()>;
typedef $$MindMapsTableCreateCompanionBuilder = MindMapsCompanion Function({
  required String id,
  required String title,
  Value<String?> rootNodeId,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$MindMapsTableUpdateCompanionBuilder = MindMapsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String?> rootNodeId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$MindMapsTableFilterComposer
    extends Composer<_$AppDatabase, $MindMapsTable> {
  $$MindMapsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rootNodeId => $composableBuilder(
      column: $table.rootNodeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$MindMapsTableOrderingComposer
    extends Composer<_$AppDatabase, $MindMapsTable> {
  $$MindMapsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rootNodeId => $composableBuilder(
      column: $table.rootNodeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$MindMapsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MindMapsTable> {
  $$MindMapsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get rootNodeId => $composableBuilder(
      column: $table.rootNodeId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MindMapsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MindMapsTable,
    MindMap,
    $$MindMapsTableFilterComposer,
    $$MindMapsTableOrderingComposer,
    $$MindMapsTableAnnotationComposer,
    $$MindMapsTableCreateCompanionBuilder,
    $$MindMapsTableUpdateCompanionBuilder,
    (MindMap, BaseReferences<_$AppDatabase, $MindMapsTable, MindMap>),
    MindMap,
    PrefetchHooks Function()> {
  $$MindMapsTableTableManager(_$AppDatabase db, $MindMapsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MindMapsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MindMapsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MindMapsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> rootNodeId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MindMapsCompanion(
            id: id,
            title: title,
            rootNodeId: rootNodeId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            Value<String?> rootNodeId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              MindMapsCompanion.insert(
            id: id,
            title: title,
            rootNodeId: rootNodeId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MindMapsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MindMapsTable,
    MindMap,
    $$MindMapsTableFilterComposer,
    $$MindMapsTableOrderingComposer,
    $$MindMapsTableAnnotationComposer,
    $$MindMapsTableCreateCompanionBuilder,
    $$MindMapsTableUpdateCompanionBuilder,
    (MindMap, BaseReferences<_$AppDatabase, $MindMapsTable, MindMap>),
    MindMap,
    PrefetchHooks Function()>;
typedef $$MindNodesTableCreateCompanionBuilder = MindNodesCompanion Function({
  required String id,
  required String mapId,
  Value<String?> parentId,
  required String nodeText,
  Value<String?> notes,
  Value<bool> isTag,
  Value<String?> tagId,
  Value<double?> positionX,
  Value<double?> positionY,
  Value<bool> collapsed,
  Value<int> sortOrder,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$MindNodesTableUpdateCompanionBuilder = MindNodesCompanion Function({
  Value<String> id,
  Value<String> mapId,
  Value<String?> parentId,
  Value<String> nodeText,
  Value<String?> notes,
  Value<bool> isTag,
  Value<String?> tagId,
  Value<double?> positionX,
  Value<double?> positionY,
  Value<bool> collapsed,
  Value<int> sortOrder,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$MindNodesTableFilterComposer
    extends Composer<_$AppDatabase, $MindNodesTable> {
  $$MindNodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mapId => $composableBuilder(
      column: $table.mapId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get nodeText => $composableBuilder(
      column: $table.nodeText, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isTag => $composableBuilder(
      column: $table.isTag, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagId => $composableBuilder(
      column: $table.tagId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get positionX => $composableBuilder(
      column: $table.positionX, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get positionY => $composableBuilder(
      column: $table.positionY, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get collapsed => $composableBuilder(
      column: $table.collapsed, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$MindNodesTableOrderingComposer
    extends Composer<_$AppDatabase, $MindNodesTable> {
  $$MindNodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mapId => $composableBuilder(
      column: $table.mapId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get nodeText => $composableBuilder(
      column: $table.nodeText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isTag => $composableBuilder(
      column: $table.isTag, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagId => $composableBuilder(
      column: $table.tagId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get positionX => $composableBuilder(
      column: $table.positionX, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get positionY => $composableBuilder(
      column: $table.positionY, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get collapsed => $composableBuilder(
      column: $table.collapsed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$MindNodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MindNodesTable> {
  $$MindNodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mapId =>
      $composableBuilder(column: $table.mapId, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get nodeText =>
      $composableBuilder(column: $table.nodeText, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get isTag =>
      $composableBuilder(column: $table.isTag, builder: (column) => column);

  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);

  GeneratedColumn<double> get positionX =>
      $composableBuilder(column: $table.positionX, builder: (column) => column);

  GeneratedColumn<double> get positionY =>
      $composableBuilder(column: $table.positionY, builder: (column) => column);

  GeneratedColumn<bool> get collapsed =>
      $composableBuilder(column: $table.collapsed, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MindNodesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MindNodesTable,
    MindNode,
    $$MindNodesTableFilterComposer,
    $$MindNodesTableOrderingComposer,
    $$MindNodesTableAnnotationComposer,
    $$MindNodesTableCreateCompanionBuilder,
    $$MindNodesTableUpdateCompanionBuilder,
    (MindNode, BaseReferences<_$AppDatabase, $MindNodesTable, MindNode>),
    MindNode,
    PrefetchHooks Function()> {
  $$MindNodesTableTableManager(_$AppDatabase db, $MindNodesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MindNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MindNodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MindNodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> mapId = const Value.absent(),
            Value<String?> parentId = const Value.absent(),
            Value<String> nodeText = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<bool> isTag = const Value.absent(),
            Value<String?> tagId = const Value.absent(),
            Value<double?> positionX = const Value.absent(),
            Value<double?> positionY = const Value.absent(),
            Value<bool> collapsed = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MindNodesCompanion(
            id: id,
            mapId: mapId,
            parentId: parentId,
            nodeText: nodeText,
            notes: notes,
            isTag: isTag,
            tagId: tagId,
            positionX: positionX,
            positionY: positionY,
            collapsed: collapsed,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String mapId,
            Value<String?> parentId = const Value.absent(),
            required String nodeText,
            Value<String?> notes = const Value.absent(),
            Value<bool> isTag = const Value.absent(),
            Value<String?> tagId = const Value.absent(),
            Value<double?> positionX = const Value.absent(),
            Value<double?> positionY = const Value.absent(),
            Value<bool> collapsed = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              MindNodesCompanion.insert(
            id: id,
            mapId: mapId,
            parentId: parentId,
            nodeText: nodeText,
            notes: notes,
            isTag: isTag,
            tagId: tagId,
            positionX: positionX,
            positionY: positionY,
            collapsed: collapsed,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MindNodesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MindNodesTable,
    MindNode,
    $$MindNodesTableFilterComposer,
    $$MindNodesTableOrderingComposer,
    $$MindNodesTableAnnotationComposer,
    $$MindNodesTableCreateCompanionBuilder,
    $$MindNodesTableUpdateCompanionBuilder,
    (MindNode, BaseReferences<_$AppDatabase, $MindNodesTable, MindNode>),
    MindNode,
    PrefetchHooks Function()>;
typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  required String id,
  Value<String?> parentId,
  required String title,
  Value<String?> description,
  Value<String> status,
  Value<int> priority,
  Value<int?> estimateMinutes,
  Value<int?> dueAt,
  Value<int?> remindAt,
  Value<int?> expectedAt,
  Value<int?> startedAt,
  Value<int?> energyRequired,
  Value<int?> completedAt,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<String> id,
  Value<String?> parentId,
  Value<String> title,
  Value<String?> description,
  Value<String> status,
  Value<int> priority,
  Value<int?> estimateMinutes,
  Value<int?> dueAt,
  Value<int?> remindAt,
  Value<int?> expectedAt,
  Value<int?> startedAt,
  Value<int?> energyRequired,
  Value<int?> completedAt,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get estimateMinutes => $composableBuilder(
      column: $table.estimateMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dueAt => $composableBuilder(
      column: $table.dueAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get remindAt => $composableBuilder(
      column: $table.remindAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get expectedAt => $composableBuilder(
      column: $table.expectedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get energyRequired => $composableBuilder(
      column: $table.energyRequired,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get estimateMinutes => $composableBuilder(
      column: $table.estimateMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dueAt => $composableBuilder(
      column: $table.dueAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get remindAt => $composableBuilder(
      column: $table.remindAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get expectedAt => $composableBuilder(
      column: $table.expectedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get energyRequired => $composableBuilder(
      column: $table.energyRequired,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get estimateMinutes => $composableBuilder(
      column: $table.estimateMinutes, builder: (column) => column);

  GeneratedColumn<int> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<int> get remindAt =>
      $composableBuilder(column: $table.remindAt, builder: (column) => column);

  GeneratedColumn<int> get expectedAt => $composableBuilder(
      column: $table.expectedAt, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get energyRequired => $composableBuilder(
      column: $table.energyRequired, builder: (column) => column);

  GeneratedColumn<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TasksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TasksTable,
    Task,
    $$TasksTableFilterComposer,
    $$TasksTableOrderingComposer,
    $$TasksTableAnnotationComposer,
    $$TasksTableCreateCompanionBuilder,
    $$TasksTableUpdateCompanionBuilder,
    (Task, BaseReferences<_$AppDatabase, $TasksTable, Task>),
    Task,
    PrefetchHooks Function()> {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> parentId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<int?> estimateMinutes = const Value.absent(),
            Value<int?> dueAt = const Value.absent(),
            Value<int?> remindAt = const Value.absent(),
            Value<int?> expectedAt = const Value.absent(),
            Value<int?> startedAt = const Value.absent(),
            Value<int?> energyRequired = const Value.absent(),
            Value<int?> completedAt = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TasksCompanion(
            id: id,
            parentId: parentId,
            title: title,
            description: description,
            status: status,
            priority: priority,
            estimateMinutes: estimateMinutes,
            dueAt: dueAt,
            remindAt: remindAt,
            expectedAt: expectedAt,
            startedAt: startedAt,
            energyRequired: energyRequired,
            completedAt: completedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> parentId = const Value.absent(),
            required String title,
            Value<String?> description = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<int?> estimateMinutes = const Value.absent(),
            Value<int?> dueAt = const Value.absent(),
            Value<int?> remindAt = const Value.absent(),
            Value<int?> expectedAt = const Value.absent(),
            Value<int?> startedAt = const Value.absent(),
            Value<int?> energyRequired = const Value.absent(),
            Value<int?> completedAt = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TasksCompanion.insert(
            id: id,
            parentId: parentId,
            title: title,
            description: description,
            status: status,
            priority: priority,
            estimateMinutes: estimateMinutes,
            dueAt: dueAt,
            remindAt: remindAt,
            expectedAt: expectedAt,
            startedAt: startedAt,
            energyRequired: energyRequired,
            completedAt: completedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TasksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TasksTable,
    Task,
    $$TasksTableFilterComposer,
    $$TasksTableOrderingComposer,
    $$TasksTableAnnotationComposer,
    $$TasksTableCreateCompanionBuilder,
    $$TasksTableUpdateCompanionBuilder,
    (Task, BaseReferences<_$AppDatabase, $TasksTable, Task>),
    Task,
    PrefetchHooks Function()>;
typedef $$TaskDependenciesTableCreateCompanionBuilder
    = TaskDependenciesCompanion Function({
  required String id,
  required String taskId,
  required String dependsOnTaskId,
  required int createdAt,
  Value<int> rowid,
});
typedef $$TaskDependenciesTableUpdateCompanionBuilder
    = TaskDependenciesCompanion Function({
  Value<String> id,
  Value<String> taskId,
  Value<String> dependsOnTaskId,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$TaskDependenciesTableFilterComposer
    extends Composer<_$AppDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dependsOnTaskId => $composableBuilder(
      column: $table.dependsOnTaskId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$TaskDependenciesTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dependsOnTaskId => $composableBuilder(
      column: $table.dependsOnTaskId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$TaskDependenciesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get dependsOnTaskId => $composableBuilder(
      column: $table.dependsOnTaskId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TaskDependenciesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TaskDependenciesTable,
    TaskDependency,
    $$TaskDependenciesTableFilterComposer,
    $$TaskDependenciesTableOrderingComposer,
    $$TaskDependenciesTableAnnotationComposer,
    $$TaskDependenciesTableCreateCompanionBuilder,
    $$TaskDependenciesTableUpdateCompanionBuilder,
    (
      TaskDependency,
      BaseReferences<_$AppDatabase, $TaskDependenciesTable, TaskDependency>
    ),
    TaskDependency,
    PrefetchHooks Function()> {
  $$TaskDependenciesTableTableManager(
      _$AppDatabase db, $TaskDependenciesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskDependenciesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskDependenciesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskDependenciesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> taskId = const Value.absent(),
            Value<String> dependsOnTaskId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TaskDependenciesCompanion(
            id: id,
            taskId: taskId,
            dependsOnTaskId: dependsOnTaskId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String taskId,
            required String dependsOnTaskId,
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TaskDependenciesCompanion.insert(
            id: id,
            taskId: taskId,
            dependsOnTaskId: dependsOnTaskId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TaskDependenciesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TaskDependenciesTable,
    TaskDependency,
    $$TaskDependenciesTableFilterComposer,
    $$TaskDependenciesTableOrderingComposer,
    $$TaskDependenciesTableAnnotationComposer,
    $$TaskDependenciesTableCreateCompanionBuilder,
    $$TaskDependenciesTableUpdateCompanionBuilder,
    (
      TaskDependency,
      BaseReferences<_$AppDatabase, $TaskDependenciesTable, TaskDependency>
    ),
    TaskDependency,
    PrefetchHooks Function()>;
typedef $$TimeBlocksTableCreateCompanionBuilder = TimeBlocksCompanion Function({
  required String id,
  required String title,
  required int startAt,
  required int endAt,
  Value<String?> repeatRule,
  Value<bool> available,
  Value<String?> energy,
  Value<String?> suitableFor,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$TimeBlocksTableUpdateCompanionBuilder = TimeBlocksCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<int> startAt,
  Value<int> endAt,
  Value<String?> repeatRule,
  Value<bool> available,
  Value<String?> energy,
  Value<String?> suitableFor,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$TimeBlocksTableFilterComposer
    extends Composer<_$AppDatabase, $TimeBlocksTable> {
  $$TimeBlocksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startAt => $composableBuilder(
      column: $table.startAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endAt => $composableBuilder(
      column: $table.endAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get repeatRule => $composableBuilder(
      column: $table.repeatRule, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get available => $composableBuilder(
      column: $table.available, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get energy => $composableBuilder(
      column: $table.energy, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get suitableFor => $composableBuilder(
      column: $table.suitableFor, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$TimeBlocksTableOrderingComposer
    extends Composer<_$AppDatabase, $TimeBlocksTable> {
  $$TimeBlocksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startAt => $composableBuilder(
      column: $table.startAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endAt => $composableBuilder(
      column: $table.endAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get repeatRule => $composableBuilder(
      column: $table.repeatRule, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get available => $composableBuilder(
      column: $table.available, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get energy => $composableBuilder(
      column: $table.energy, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get suitableFor => $composableBuilder(
      column: $table.suitableFor, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$TimeBlocksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TimeBlocksTable> {
  $$TimeBlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<int> get endAt =>
      $composableBuilder(column: $table.endAt, builder: (column) => column);

  GeneratedColumn<String> get repeatRule => $composableBuilder(
      column: $table.repeatRule, builder: (column) => column);

  GeneratedColumn<bool> get available =>
      $composableBuilder(column: $table.available, builder: (column) => column);

  GeneratedColumn<String> get energy =>
      $composableBuilder(column: $table.energy, builder: (column) => column);

  GeneratedColumn<String> get suitableFor => $composableBuilder(
      column: $table.suitableFor, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TimeBlocksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TimeBlocksTable,
    TimeBlock,
    $$TimeBlocksTableFilterComposer,
    $$TimeBlocksTableOrderingComposer,
    $$TimeBlocksTableAnnotationComposer,
    $$TimeBlocksTableCreateCompanionBuilder,
    $$TimeBlocksTableUpdateCompanionBuilder,
    (TimeBlock, BaseReferences<_$AppDatabase, $TimeBlocksTable, TimeBlock>),
    TimeBlock,
    PrefetchHooks Function()> {
  $$TimeBlocksTableTableManager(_$AppDatabase db, $TimeBlocksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TimeBlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TimeBlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TimeBlocksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int> startAt = const Value.absent(),
            Value<int> endAt = const Value.absent(),
            Value<String?> repeatRule = const Value.absent(),
            Value<bool> available = const Value.absent(),
            Value<String?> energy = const Value.absent(),
            Value<String?> suitableFor = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TimeBlocksCompanion(
            id: id,
            title: title,
            startAt: startAt,
            endAt: endAt,
            repeatRule: repeatRule,
            available: available,
            energy: energy,
            suitableFor: suitableFor,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            required int startAt,
            required int endAt,
            Value<String?> repeatRule = const Value.absent(),
            Value<bool> available = const Value.absent(),
            Value<String?> energy = const Value.absent(),
            Value<String?> suitableFor = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TimeBlocksCompanion.insert(
            id: id,
            title: title,
            startAt: startAt,
            endAt: endAt,
            repeatRule: repeatRule,
            available: available,
            energy: energy,
            suitableFor: suitableFor,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TimeBlocksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TimeBlocksTable,
    TimeBlock,
    $$TimeBlocksTableFilterComposer,
    $$TimeBlocksTableOrderingComposer,
    $$TimeBlocksTableAnnotationComposer,
    $$TimeBlocksTableCreateCompanionBuilder,
    $$TimeBlocksTableUpdateCompanionBuilder,
    (TimeBlock, BaseReferences<_$AppDatabase, $TimeBlocksTable, TimeBlock>),
    TimeBlock,
    PrefetchHooks Function()>;
typedef $$TaskTimeBlocksTableCreateCompanionBuilder = TaskTimeBlocksCompanion
    Function({
  required String id,
  required String taskId,
  required String timeBlockId,
  Value<bool> isSuggestion,
  required int createdAt,
  Value<int> rowid,
});
typedef $$TaskTimeBlocksTableUpdateCompanionBuilder = TaskTimeBlocksCompanion
    Function({
  Value<String> id,
  Value<String> taskId,
  Value<String> timeBlockId,
  Value<bool> isSuggestion,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$TaskTimeBlocksTableFilterComposer
    extends Composer<_$AppDatabase, $TaskTimeBlocksTable> {
  $$TaskTimeBlocksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get timeBlockId => $composableBuilder(
      column: $table.timeBlockId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSuggestion => $composableBuilder(
      column: $table.isSuggestion, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$TaskTimeBlocksTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskTimeBlocksTable> {
  $$TaskTimeBlocksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get timeBlockId => $composableBuilder(
      column: $table.timeBlockId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSuggestion => $composableBuilder(
      column: $table.isSuggestion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$TaskTimeBlocksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskTimeBlocksTable> {
  $$TaskTimeBlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get timeBlockId => $composableBuilder(
      column: $table.timeBlockId, builder: (column) => column);

  GeneratedColumn<bool> get isSuggestion => $composableBuilder(
      column: $table.isSuggestion, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TaskTimeBlocksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TaskTimeBlocksTable,
    TaskTimeBlock,
    $$TaskTimeBlocksTableFilterComposer,
    $$TaskTimeBlocksTableOrderingComposer,
    $$TaskTimeBlocksTableAnnotationComposer,
    $$TaskTimeBlocksTableCreateCompanionBuilder,
    $$TaskTimeBlocksTableUpdateCompanionBuilder,
    (
      TaskTimeBlock,
      BaseReferences<_$AppDatabase, $TaskTimeBlocksTable, TaskTimeBlock>
    ),
    TaskTimeBlock,
    PrefetchHooks Function()> {
  $$TaskTimeBlocksTableTableManager(
      _$AppDatabase db, $TaskTimeBlocksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskTimeBlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskTimeBlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskTimeBlocksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> taskId = const Value.absent(),
            Value<String> timeBlockId = const Value.absent(),
            Value<bool> isSuggestion = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TaskTimeBlocksCompanion(
            id: id,
            taskId: taskId,
            timeBlockId: timeBlockId,
            isSuggestion: isSuggestion,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String taskId,
            required String timeBlockId,
            Value<bool> isSuggestion = const Value.absent(),
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TaskTimeBlocksCompanion.insert(
            id: id,
            taskId: taskId,
            timeBlockId: timeBlockId,
            isSuggestion: isSuggestion,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TaskTimeBlocksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TaskTimeBlocksTable,
    TaskTimeBlock,
    $$TaskTimeBlocksTableFilterComposer,
    $$TaskTimeBlocksTableOrderingComposer,
    $$TaskTimeBlocksTableAnnotationComposer,
    $$TaskTimeBlocksTableCreateCompanionBuilder,
    $$TaskTimeBlocksTableUpdateCompanionBuilder,
    (
      TaskTimeBlock,
      BaseReferences<_$AppDatabase, $TaskTimeBlocksTable, TaskTimeBlock>
    ),
    TaskTimeBlock,
    PrefetchHooks Function()>;
typedef $$KnowledgePointsTableCreateCompanionBuilder = KnowledgePointsCompanion
    Function({
  required String id,
  required String title,
  required String content,
  Value<String?> contentFormat,
  Value<String?> source,
  Value<String?> externalId,
  Value<String?> packageId,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$KnowledgePointsTableUpdateCompanionBuilder = KnowledgePointsCompanion
    Function({
  Value<String> id,
  Value<String> title,
  Value<String> content,
  Value<String?> contentFormat,
  Value<String?> source,
  Value<String?> externalId,
  Value<String?> packageId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$KnowledgePointsTableFilterComposer
    extends Composer<_$AppDatabase, $KnowledgePointsTable> {
  $$KnowledgePointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contentFormat => $composableBuilder(
      column: $table.contentFormat, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get packageId => $composableBuilder(
      column: $table.packageId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$KnowledgePointsTableOrderingComposer
    extends Composer<_$AppDatabase, $KnowledgePointsTable> {
  $$KnowledgePointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contentFormat => $composableBuilder(
      column: $table.contentFormat,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get packageId => $composableBuilder(
      column: $table.packageId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$KnowledgePointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KnowledgePointsTable> {
  $$KnowledgePointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get contentFormat => $composableBuilder(
      column: $table.contentFormat, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => column);

  GeneratedColumn<String> get packageId =>
      $composableBuilder(column: $table.packageId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$KnowledgePointsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $KnowledgePointsTable,
    KnowledgePoint,
    $$KnowledgePointsTableFilterComposer,
    $$KnowledgePointsTableOrderingComposer,
    $$KnowledgePointsTableAnnotationComposer,
    $$KnowledgePointsTableCreateCompanionBuilder,
    $$KnowledgePointsTableUpdateCompanionBuilder,
    (
      KnowledgePoint,
      BaseReferences<_$AppDatabase, $KnowledgePointsTable, KnowledgePoint>
    ),
    KnowledgePoint,
    PrefetchHooks Function()> {
  $$KnowledgePointsTableTableManager(
      _$AppDatabase db, $KnowledgePointsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnowledgePointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnowledgePointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnowledgePointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String?> contentFormat = const Value.absent(),
            Value<String?> source = const Value.absent(),
            Value<String?> externalId = const Value.absent(),
            Value<String?> packageId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              KnowledgePointsCompanion(
            id: id,
            title: title,
            content: content,
            contentFormat: contentFormat,
            source: source,
            externalId: externalId,
            packageId: packageId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            required String content,
            Value<String?> contentFormat = const Value.absent(),
            Value<String?> source = const Value.absent(),
            Value<String?> externalId = const Value.absent(),
            Value<String?> packageId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              KnowledgePointsCompanion.insert(
            id: id,
            title: title,
            content: content,
            contentFormat: contentFormat,
            source: source,
            externalId: externalId,
            packageId: packageId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$KnowledgePointsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $KnowledgePointsTable,
    KnowledgePoint,
    $$KnowledgePointsTableFilterComposer,
    $$KnowledgePointsTableOrderingComposer,
    $$KnowledgePointsTableAnnotationComposer,
    $$KnowledgePointsTableCreateCompanionBuilder,
    $$KnowledgePointsTableUpdateCompanionBuilder,
    (
      KnowledgePoint,
      BaseReferences<_$AppDatabase, $KnowledgePointsTable, KnowledgePoint>
    ),
    KnowledgePoint,
    PrefetchHooks Function()>;
typedef $$CardTemplatesTableCreateCompanionBuilder = CardTemplatesCompanion
    Function({
  required String id,
  required String knowledgePointId,
  required String type,
  required String question,
  required String answer,
  Value<String?> options,
  Value<String?> clozeTemplate,
  Value<String?> hint,
  Value<int> sortOrder,
  Value<String?> externalId,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$CardTemplatesTableUpdateCompanionBuilder = CardTemplatesCompanion
    Function({
  Value<String> id,
  Value<String> knowledgePointId,
  Value<String> type,
  Value<String> question,
  Value<String> answer,
  Value<String?> options,
  Value<String?> clozeTemplate,
  Value<String?> hint,
  Value<int> sortOrder,
  Value<String?> externalId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$CardTemplatesTableFilterComposer
    extends Composer<_$AppDatabase, $CardTemplatesTable> {
  $$CardTemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get question => $composableBuilder(
      column: $table.question, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get answer => $composableBuilder(
      column: $table.answer, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get options => $composableBuilder(
      column: $table.options, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get clozeTemplate => $composableBuilder(
      column: $table.clozeTemplate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get hint => $composableBuilder(
      column: $table.hint, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CardTemplatesTableOrderingComposer
    extends Composer<_$AppDatabase, $CardTemplatesTable> {
  $$CardTemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get question => $composableBuilder(
      column: $table.question, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get answer => $composableBuilder(
      column: $table.answer, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get options => $composableBuilder(
      column: $table.options, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get clozeTemplate => $composableBuilder(
      column: $table.clozeTemplate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get hint => $composableBuilder(
      column: $table.hint, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CardTemplatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardTemplatesTable> {
  $$CardTemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get question =>
      $composableBuilder(column: $table.question, builder: (column) => column);

  GeneratedColumn<String> get answer =>
      $composableBuilder(column: $table.answer, builder: (column) => column);

  GeneratedColumn<String> get options =>
      $composableBuilder(column: $table.options, builder: (column) => column);

  GeneratedColumn<String> get clozeTemplate => $composableBuilder(
      column: $table.clozeTemplate, builder: (column) => column);

  GeneratedColumn<String> get hint =>
      $composableBuilder(column: $table.hint, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CardTemplatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CardTemplatesTable,
    CardTemplate,
    $$CardTemplatesTableFilterComposer,
    $$CardTemplatesTableOrderingComposer,
    $$CardTemplatesTableAnnotationComposer,
    $$CardTemplatesTableCreateCompanionBuilder,
    $$CardTemplatesTableUpdateCompanionBuilder,
    (
      CardTemplate,
      BaseReferences<_$AppDatabase, $CardTemplatesTable, CardTemplate>
    ),
    CardTemplate,
    PrefetchHooks Function()> {
  $$CardTemplatesTableTableManager(_$AppDatabase db, $CardTemplatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardTemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardTemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardTemplatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> knowledgePointId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> question = const Value.absent(),
            Value<String> answer = const Value.absent(),
            Value<String?> options = const Value.absent(),
            Value<String?> clozeTemplate = const Value.absent(),
            Value<String?> hint = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<String?> externalId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CardTemplatesCompanion(
            id: id,
            knowledgePointId: knowledgePointId,
            type: type,
            question: question,
            answer: answer,
            options: options,
            clozeTemplate: clozeTemplate,
            hint: hint,
            sortOrder: sortOrder,
            externalId: externalId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String knowledgePointId,
            required String type,
            required String question,
            required String answer,
            Value<String?> options = const Value.absent(),
            Value<String?> clozeTemplate = const Value.absent(),
            Value<String?> hint = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<String?> externalId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CardTemplatesCompanion.insert(
            id: id,
            knowledgePointId: knowledgePointId,
            type: type,
            question: question,
            answer: answer,
            options: options,
            clozeTemplate: clozeTemplate,
            hint: hint,
            sortOrder: sortOrder,
            externalId: externalId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CardTemplatesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CardTemplatesTable,
    CardTemplate,
    $$CardTemplatesTableFilterComposer,
    $$CardTemplatesTableOrderingComposer,
    $$CardTemplatesTableAnnotationComposer,
    $$CardTemplatesTableCreateCompanionBuilder,
    $$CardTemplatesTableUpdateCompanionBuilder,
    (
      CardTemplate,
      BaseReferences<_$AppDatabase, $CardTemplatesTable, CardTemplate>
    ),
    CardTemplate,
    PrefetchHooks Function()>;
typedef $$CardStatesTableCreateCompanionBuilder = CardStatesCompanion Function({
  required String id,
  Value<String?> cardTemplateId,
  Value<int?> dueAt,
  Value<double> intervalDays,
  Value<double> ease,
  Value<int> repetitions,
  Value<int> lapses,
  Value<String> state,
  Value<int?> lastReviewedAt,
  required int createdAt,
  required int updatedAt,
  Value<String?> knowledgePointId,
  Value<String?> unitKey,
  Value<double?> stability,
  Value<double?> difficulty,
  Value<double?> encodingStrength,
  Value<double?> savings,
  Value<int> forced,
  Value<int> forcedStreak,
  Value<int> rowid,
});
typedef $$CardStatesTableUpdateCompanionBuilder = CardStatesCompanion Function({
  Value<String> id,
  Value<String?> cardTemplateId,
  Value<int?> dueAt,
  Value<double> intervalDays,
  Value<double> ease,
  Value<int> repetitions,
  Value<int> lapses,
  Value<String> state,
  Value<int?> lastReviewedAt,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<String?> knowledgePointId,
  Value<String?> unitKey,
  Value<double?> stability,
  Value<double?> difficulty,
  Value<double?> encodingStrength,
  Value<double?> savings,
  Value<int> forced,
  Value<int> forcedStreak,
  Value<int> rowid,
});

class $$CardStatesTableFilterComposer
    extends Composer<_$AppDatabase, $CardStatesTable> {
  $$CardStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardTemplateId => $composableBuilder(
      column: $table.cardTemplateId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dueAt => $composableBuilder(
      column: $table.dueAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get intervalDays => $composableBuilder(
      column: $table.intervalDays, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get ease => $composableBuilder(
      column: $table.ease, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get repetitions => $composableBuilder(
      column: $table.repetitions, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lapses => $composableBuilder(
      column: $table.lapses, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastReviewedAt => $composableBuilder(
      column: $table.lastReviewedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get unitKey => $composableBuilder(
      column: $table.unitKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get stability => $composableBuilder(
      column: $table.stability, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get encodingStrength => $composableBuilder(
      column: $table.encodingStrength,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get savings => $composableBuilder(
      column: $table.savings, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get forced => $composableBuilder(
      column: $table.forced, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get forcedStreak => $composableBuilder(
      column: $table.forcedStreak, builder: (column) => ColumnFilters(column));
}

class $$CardStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $CardStatesTable> {
  $$CardStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardTemplateId => $composableBuilder(
      column: $table.cardTemplateId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dueAt => $composableBuilder(
      column: $table.dueAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get intervalDays => $composableBuilder(
      column: $table.intervalDays,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get ease => $composableBuilder(
      column: $table.ease, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get repetitions => $composableBuilder(
      column: $table.repetitions, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lapses => $composableBuilder(
      column: $table.lapses, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastReviewedAt => $composableBuilder(
      column: $table.lastReviewedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get unitKey => $composableBuilder(
      column: $table.unitKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get stability => $composableBuilder(
      column: $table.stability, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get encodingStrength => $composableBuilder(
      column: $table.encodingStrength,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get savings => $composableBuilder(
      column: $table.savings, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get forced => $composableBuilder(
      column: $table.forced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get forcedStreak => $composableBuilder(
      column: $table.forcedStreak,
      builder: (column) => ColumnOrderings(column));
}

class $$CardStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardStatesTable> {
  $$CardStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cardTemplateId => $composableBuilder(
      column: $table.cardTemplateId, builder: (column) => column);

  GeneratedColumn<int> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<double> get intervalDays => $composableBuilder(
      column: $table.intervalDays, builder: (column) => column);

  GeneratedColumn<double> get ease =>
      $composableBuilder(column: $table.ease, builder: (column) => column);

  GeneratedColumn<int> get repetitions => $composableBuilder(
      column: $table.repetitions, builder: (column) => column);

  GeneratedColumn<int> get lapses =>
      $composableBuilder(column: $table.lapses, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get lastReviewedAt => $composableBuilder(
      column: $table.lastReviewedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId, builder: (column) => column);

  GeneratedColumn<String> get unitKey =>
      $composableBuilder(column: $table.unitKey, builder: (column) => column);

  GeneratedColumn<double> get stability =>
      $composableBuilder(column: $table.stability, builder: (column) => column);

  GeneratedColumn<double> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => column);

  GeneratedColumn<double> get encodingStrength => $composableBuilder(
      column: $table.encodingStrength, builder: (column) => column);

  GeneratedColumn<double> get savings =>
      $composableBuilder(column: $table.savings, builder: (column) => column);

  GeneratedColumn<int> get forced =>
      $composableBuilder(column: $table.forced, builder: (column) => column);

  GeneratedColumn<int> get forcedStreak => $composableBuilder(
      column: $table.forcedStreak, builder: (column) => column);
}

class $$CardStatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CardStatesTable,
    CardState,
    $$CardStatesTableFilterComposer,
    $$CardStatesTableOrderingComposer,
    $$CardStatesTableAnnotationComposer,
    $$CardStatesTableCreateCompanionBuilder,
    $$CardStatesTableUpdateCompanionBuilder,
    (CardState, BaseReferences<_$AppDatabase, $CardStatesTable, CardState>),
    CardState,
    PrefetchHooks Function()> {
  $$CardStatesTableTableManager(_$AppDatabase db, $CardStatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> cardTemplateId = const Value.absent(),
            Value<int?> dueAt = const Value.absent(),
            Value<double> intervalDays = const Value.absent(),
            Value<double> ease = const Value.absent(),
            Value<int> repetitions = const Value.absent(),
            Value<int> lapses = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<int?> lastReviewedAt = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<String?> knowledgePointId = const Value.absent(),
            Value<String?> unitKey = const Value.absent(),
            Value<double?> stability = const Value.absent(),
            Value<double?> difficulty = const Value.absent(),
            Value<double?> encodingStrength = const Value.absent(),
            Value<double?> savings = const Value.absent(),
            Value<int> forced = const Value.absent(),
            Value<int> forcedStreak = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CardStatesCompanion(
            id: id,
            cardTemplateId: cardTemplateId,
            dueAt: dueAt,
            intervalDays: intervalDays,
            ease: ease,
            repetitions: repetitions,
            lapses: lapses,
            state: state,
            lastReviewedAt: lastReviewedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            knowledgePointId: knowledgePointId,
            unitKey: unitKey,
            stability: stability,
            difficulty: difficulty,
            encodingStrength: encodingStrength,
            savings: savings,
            forced: forced,
            forcedStreak: forcedStreak,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> cardTemplateId = const Value.absent(),
            Value<int?> dueAt = const Value.absent(),
            Value<double> intervalDays = const Value.absent(),
            Value<double> ease = const Value.absent(),
            Value<int> repetitions = const Value.absent(),
            Value<int> lapses = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<int?> lastReviewedAt = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<String?> knowledgePointId = const Value.absent(),
            Value<String?> unitKey = const Value.absent(),
            Value<double?> stability = const Value.absent(),
            Value<double?> difficulty = const Value.absent(),
            Value<double?> encodingStrength = const Value.absent(),
            Value<double?> savings = const Value.absent(),
            Value<int> forced = const Value.absent(),
            Value<int> forcedStreak = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CardStatesCompanion.insert(
            id: id,
            cardTemplateId: cardTemplateId,
            dueAt: dueAt,
            intervalDays: intervalDays,
            ease: ease,
            repetitions: repetitions,
            lapses: lapses,
            state: state,
            lastReviewedAt: lastReviewedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            knowledgePointId: knowledgePointId,
            unitKey: unitKey,
            stability: stability,
            difficulty: difficulty,
            encodingStrength: encodingStrength,
            savings: savings,
            forced: forced,
            forcedStreak: forcedStreak,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CardStatesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CardStatesTable,
    CardState,
    $$CardStatesTableFilterComposer,
    $$CardStatesTableOrderingComposer,
    $$CardStatesTableAnnotationComposer,
    $$CardStatesTableCreateCompanionBuilder,
    $$CardStatesTableUpdateCompanionBuilder,
    (CardState, BaseReferences<_$AppDatabase, $CardStatesTable, CardState>),
    CardState,
    PrefetchHooks Function()>;
typedef $$ReviewLogsTableCreateCompanionBuilder = ReviewLogsCompanion Function({
  required String id,
  required String cardStateId,
  Value<String?> cardTemplateId,
  Value<String?> unitKey,
  required int rating,
  Value<int?> ratingFsrs,
  Value<int?> correct,
  Value<String?> judgeMode,
  Value<String?> format,
  Value<int?> msTaken,
  required int reviewedAt,
  required int createdAt,
  Value<int> rowid,
});
typedef $$ReviewLogsTableUpdateCompanionBuilder = ReviewLogsCompanion Function({
  Value<String> id,
  Value<String> cardStateId,
  Value<String?> cardTemplateId,
  Value<String?> unitKey,
  Value<int> rating,
  Value<int?> ratingFsrs,
  Value<int?> correct,
  Value<String?> judgeMode,
  Value<String?> format,
  Value<int?> msTaken,
  Value<int> reviewedAt,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$ReviewLogsTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewLogsTable> {
  $$ReviewLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardStateId => $composableBuilder(
      column: $table.cardStateId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardTemplateId => $composableBuilder(
      column: $table.cardTemplateId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get unitKey => $composableBuilder(
      column: $table.unitKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ratingFsrs => $composableBuilder(
      column: $table.ratingFsrs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get correct => $composableBuilder(
      column: $table.correct, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get judgeMode => $composableBuilder(
      column: $table.judgeMode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get format => $composableBuilder(
      column: $table.format, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get msTaken => $composableBuilder(
      column: $table.msTaken, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get reviewedAt => $composableBuilder(
      column: $table.reviewedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ReviewLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewLogsTable> {
  $$ReviewLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardStateId => $composableBuilder(
      column: $table.cardStateId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardTemplateId => $composableBuilder(
      column: $table.cardTemplateId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get unitKey => $composableBuilder(
      column: $table.unitKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ratingFsrs => $composableBuilder(
      column: $table.ratingFsrs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get correct => $composableBuilder(
      column: $table.correct, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get judgeMode => $composableBuilder(
      column: $table.judgeMode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get format => $composableBuilder(
      column: $table.format, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get msTaken => $composableBuilder(
      column: $table.msTaken, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get reviewedAt => $composableBuilder(
      column: $table.reviewedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ReviewLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewLogsTable> {
  $$ReviewLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cardStateId => $composableBuilder(
      column: $table.cardStateId, builder: (column) => column);

  GeneratedColumn<String> get cardTemplateId => $composableBuilder(
      column: $table.cardTemplateId, builder: (column) => column);

  GeneratedColumn<String> get unitKey =>
      $composableBuilder(column: $table.unitKey, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get ratingFsrs => $composableBuilder(
      column: $table.ratingFsrs, builder: (column) => column);

  GeneratedColumn<int> get correct =>
      $composableBuilder(column: $table.correct, builder: (column) => column);

  GeneratedColumn<String> get judgeMode =>
      $composableBuilder(column: $table.judgeMode, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<int> get msTaken =>
      $composableBuilder(column: $table.msTaken, builder: (column) => column);

  GeneratedColumn<int> get reviewedAt => $composableBuilder(
      column: $table.reviewedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ReviewLogsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ReviewLogsTable,
    ReviewLog,
    $$ReviewLogsTableFilterComposer,
    $$ReviewLogsTableOrderingComposer,
    $$ReviewLogsTableAnnotationComposer,
    $$ReviewLogsTableCreateCompanionBuilder,
    $$ReviewLogsTableUpdateCompanionBuilder,
    (ReviewLog, BaseReferences<_$AppDatabase, $ReviewLogsTable, ReviewLog>),
    ReviewLog,
    PrefetchHooks Function()> {
  $$ReviewLogsTableTableManager(_$AppDatabase db, $ReviewLogsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> cardStateId = const Value.absent(),
            Value<String?> cardTemplateId = const Value.absent(),
            Value<String?> unitKey = const Value.absent(),
            Value<int> rating = const Value.absent(),
            Value<int?> ratingFsrs = const Value.absent(),
            Value<int?> correct = const Value.absent(),
            Value<String?> judgeMode = const Value.absent(),
            Value<String?> format = const Value.absent(),
            Value<int?> msTaken = const Value.absent(),
            Value<int> reviewedAt = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ReviewLogsCompanion(
            id: id,
            cardStateId: cardStateId,
            cardTemplateId: cardTemplateId,
            unitKey: unitKey,
            rating: rating,
            ratingFsrs: ratingFsrs,
            correct: correct,
            judgeMode: judgeMode,
            format: format,
            msTaken: msTaken,
            reviewedAt: reviewedAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String cardStateId,
            Value<String?> cardTemplateId = const Value.absent(),
            Value<String?> unitKey = const Value.absent(),
            required int rating,
            Value<int?> ratingFsrs = const Value.absent(),
            Value<int?> correct = const Value.absent(),
            Value<String?> judgeMode = const Value.absent(),
            Value<String?> format = const Value.absent(),
            Value<int?> msTaken = const Value.absent(),
            required int reviewedAt,
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ReviewLogsCompanion.insert(
            id: id,
            cardStateId: cardStateId,
            cardTemplateId: cardTemplateId,
            unitKey: unitKey,
            rating: rating,
            ratingFsrs: ratingFsrs,
            correct: correct,
            judgeMode: judgeMode,
            format: format,
            msTaken: msTaken,
            reviewedAt: reviewedAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ReviewLogsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ReviewLogsTable,
    ReviewLog,
    $$ReviewLogsTableFilterComposer,
    $$ReviewLogsTableOrderingComposer,
    $$ReviewLogsTableAnnotationComposer,
    $$ReviewLogsTableCreateCompanionBuilder,
    $$ReviewLogsTableUpdateCompanionBuilder,
    (ReviewLog, BaseReferences<_$AppDatabase, $ReviewLogsTable, ReviewLog>),
    ReviewLog,
    PrefetchHooks Function()>;
typedef $$KnowledgePackagesTableCreateCompanionBuilder
    = KnowledgePackagesCompanion Function({
  required String id,
  required String name,
  required String version,
  required String author,
  Value<String?> description,
  required int importedAt,
  Value<String?> fileHash,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$KnowledgePackagesTableUpdateCompanionBuilder
    = KnowledgePackagesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> version,
  Value<String> author,
  Value<String?> description,
  Value<int> importedAt,
  Value<String?> fileHash,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$KnowledgePackagesTableFilterComposer
    extends Composer<_$AppDatabase, $KnowledgePackagesTable> {
  $$KnowledgePackagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get importedAt => $composableBuilder(
      column: $table.importedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileHash => $composableBuilder(
      column: $table.fileHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$KnowledgePackagesTableOrderingComposer
    extends Composer<_$AppDatabase, $KnowledgePackagesTable> {
  $$KnowledgePackagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get importedAt => $composableBuilder(
      column: $table.importedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileHash => $composableBuilder(
      column: $table.fileHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$KnowledgePackagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $KnowledgePackagesTable> {
  $$KnowledgePackagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<int> get importedAt => $composableBuilder(
      column: $table.importedAt, builder: (column) => column);

  GeneratedColumn<String> get fileHash =>
      $composableBuilder(column: $table.fileHash, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$KnowledgePackagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $KnowledgePackagesTable,
    KnowledgePackage,
    $$KnowledgePackagesTableFilterComposer,
    $$KnowledgePackagesTableOrderingComposer,
    $$KnowledgePackagesTableAnnotationComposer,
    $$KnowledgePackagesTableCreateCompanionBuilder,
    $$KnowledgePackagesTableUpdateCompanionBuilder,
    (
      KnowledgePackage,
      BaseReferences<_$AppDatabase, $KnowledgePackagesTable, KnowledgePackage>
    ),
    KnowledgePackage,
    PrefetchHooks Function()> {
  $$KnowledgePackagesTableTableManager(
      _$AppDatabase db, $KnowledgePackagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnowledgePackagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnowledgePackagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnowledgePackagesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> version = const Value.absent(),
            Value<String> author = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<int> importedAt = const Value.absent(),
            Value<String?> fileHash = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              KnowledgePackagesCompanion(
            id: id,
            name: name,
            version: version,
            author: author,
            description: description,
            importedAt: importedAt,
            fileHash: fileHash,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String version,
            required String author,
            Value<String?> description = const Value.absent(),
            required int importedAt,
            Value<String?> fileHash = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              KnowledgePackagesCompanion.insert(
            id: id,
            name: name,
            version: version,
            author: author,
            description: description,
            importedAt: importedAt,
            fileHash: fileHash,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$KnowledgePackagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $KnowledgePackagesTable,
    KnowledgePackage,
    $$KnowledgePackagesTableFilterComposer,
    $$KnowledgePackagesTableOrderingComposer,
    $$KnowledgePackagesTableAnnotationComposer,
    $$KnowledgePackagesTableCreateCompanionBuilder,
    $$KnowledgePackagesTableUpdateCompanionBuilder,
    (
      KnowledgePackage,
      BaseReferences<_$AppDatabase, $KnowledgePackagesTable, KnowledgePackage>
    ),
    KnowledgePackage,
    PrefetchHooks Function()>;
typedef $$PackageItemsTableCreateCompanionBuilder = PackageItemsCompanion
    Function({
  required String id,
  required String packageId,
  required String objectType,
  required String objectId,
  required String externalId,
  required int createdAt,
  Value<int> rowid,
});
typedef $$PackageItemsTableUpdateCompanionBuilder = PackageItemsCompanion
    Function({
  Value<String> id,
  Value<String> packageId,
  Value<String> objectType,
  Value<String> objectId,
  Value<String> externalId,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$PackageItemsTableFilterComposer
    extends Composer<_$AppDatabase, $PackageItemsTable> {
  $$PackageItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get packageId => $composableBuilder(
      column: $table.packageId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get objectType => $composableBuilder(
      column: $table.objectType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get objectId => $composableBuilder(
      column: $table.objectId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$PackageItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $PackageItemsTable> {
  $$PackageItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get packageId => $composableBuilder(
      column: $table.packageId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get objectType => $composableBuilder(
      column: $table.objectType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get objectId => $composableBuilder(
      column: $table.objectId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$PackageItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PackageItemsTable> {
  $$PackageItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get packageId =>
      $composableBuilder(column: $table.packageId, builder: (column) => column);

  GeneratedColumn<String> get objectType => $composableBuilder(
      column: $table.objectType, builder: (column) => column);

  GeneratedColumn<String> get objectId =>
      $composableBuilder(column: $table.objectId, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
      column: $table.externalId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PackageItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PackageItemsTable,
    PackageItem,
    $$PackageItemsTableFilterComposer,
    $$PackageItemsTableOrderingComposer,
    $$PackageItemsTableAnnotationComposer,
    $$PackageItemsTableCreateCompanionBuilder,
    $$PackageItemsTableUpdateCompanionBuilder,
    (
      PackageItem,
      BaseReferences<_$AppDatabase, $PackageItemsTable, PackageItem>
    ),
    PackageItem,
    PrefetchHooks Function()> {
  $$PackageItemsTableTableManager(_$AppDatabase db, $PackageItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PackageItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PackageItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PackageItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> packageId = const Value.absent(),
            Value<String> objectType = const Value.absent(),
            Value<String> objectId = const Value.absent(),
            Value<String> externalId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PackageItemsCompanion(
            id: id,
            packageId: packageId,
            objectType: objectType,
            objectId: objectId,
            externalId: externalId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String packageId,
            required String objectType,
            required String objectId,
            required String externalId,
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PackageItemsCompanion.insert(
            id: id,
            packageId: packageId,
            objectType: objectType,
            objectId: objectId,
            externalId: externalId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PackageItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PackageItemsTable,
    PackageItem,
    $$PackageItemsTableFilterComposer,
    $$PackageItemsTableOrderingComposer,
    $$PackageItemsTableAnnotationComposer,
    $$PackageItemsTableCreateCompanionBuilder,
    $$PackageItemsTableUpdateCompanionBuilder,
    (
      PackageItem,
      BaseReferences<_$AppDatabase, $PackageItemsTable, PackageItem>
    ),
    PackageItem,
    PrefetchHooks Function()>;
typedef $$ThreadStatesTableCreateCompanionBuilder = ThreadStatesCompanion
    Function({
  Value<int> id,
  Value<int?> energy,
  Value<String?> goalText,
  Value<String?> goalNodeId,
  Value<String?> goalPath,
  Value<int?> updatedAt,
  required int createdAt,
});
typedef $$ThreadStatesTableUpdateCompanionBuilder = ThreadStatesCompanion
    Function({
  Value<int> id,
  Value<int?> energy,
  Value<String?> goalText,
  Value<String?> goalNodeId,
  Value<String?> goalPath,
  Value<int?> updatedAt,
  Value<int> createdAt,
});

class $$ThreadStatesTableFilterComposer
    extends Composer<_$AppDatabase, $ThreadStatesTable> {
  $$ThreadStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get energy => $composableBuilder(
      column: $table.energy, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get goalText => $composableBuilder(
      column: $table.goalText, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get goalNodeId => $composableBuilder(
      column: $table.goalNodeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get goalPath => $composableBuilder(
      column: $table.goalPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ThreadStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $ThreadStatesTable> {
  $$ThreadStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get energy => $composableBuilder(
      column: $table.energy, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get goalText => $composableBuilder(
      column: $table.goalText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get goalNodeId => $composableBuilder(
      column: $table.goalNodeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get goalPath => $composableBuilder(
      column: $table.goalPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ThreadStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ThreadStatesTable> {
  $$ThreadStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get energy =>
      $composableBuilder(column: $table.energy, builder: (column) => column);

  GeneratedColumn<String> get goalText =>
      $composableBuilder(column: $table.goalText, builder: (column) => column);

  GeneratedColumn<String> get goalNodeId => $composableBuilder(
      column: $table.goalNodeId, builder: (column) => column);

  GeneratedColumn<String> get goalPath =>
      $composableBuilder(column: $table.goalPath, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ThreadStatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ThreadStatesTable,
    ThreadState,
    $$ThreadStatesTableFilterComposer,
    $$ThreadStatesTableOrderingComposer,
    $$ThreadStatesTableAnnotationComposer,
    $$ThreadStatesTableCreateCompanionBuilder,
    $$ThreadStatesTableUpdateCompanionBuilder,
    (
      ThreadState,
      BaseReferences<_$AppDatabase, $ThreadStatesTable, ThreadState>
    ),
    ThreadState,
    PrefetchHooks Function()> {
  $$ThreadStatesTableTableManager(_$AppDatabase db, $ThreadStatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ThreadStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ThreadStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ThreadStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> energy = const Value.absent(),
            Value<String?> goalText = const Value.absent(),
            Value<String?> goalNodeId = const Value.absent(),
            Value<String?> goalPath = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
          }) =>
              ThreadStatesCompanion(
            id: id,
            energy: energy,
            goalText: goalText,
            goalNodeId: goalNodeId,
            goalPath: goalPath,
            updatedAt: updatedAt,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> energy = const Value.absent(),
            Value<String?> goalText = const Value.absent(),
            Value<String?> goalNodeId = const Value.absent(),
            Value<String?> goalPath = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            required int createdAt,
          }) =>
              ThreadStatesCompanion.insert(
            id: id,
            energy: energy,
            goalText: goalText,
            goalNodeId: goalNodeId,
            goalPath: goalPath,
            updatedAt: updatedAt,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ThreadStatesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ThreadStatesTable,
    ThreadState,
    $$ThreadStatesTableFilterComposer,
    $$ThreadStatesTableOrderingComposer,
    $$ThreadStatesTableAnnotationComposer,
    $$ThreadStatesTableCreateCompanionBuilder,
    $$ThreadStatesTableUpdateCompanionBuilder,
    (
      ThreadState,
      BaseReferences<_$AppDatabase, $ThreadStatesTable, ThreadState>
    ),
    ThreadState,
    PrefetchHooks Function()>;
typedef $$TaskTemplatesTableCreateCompanionBuilder = TaskTemplatesCompanion
    Function({
  required String id,
  required String name,
  Value<int?> estimateMinutes,
  Value<int?> energyRequired,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$TaskTemplatesTableUpdateCompanionBuilder = TaskTemplatesCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<int?> estimateMinutes,
  Value<int?> energyRequired,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$TaskTemplatesTableFilterComposer
    extends Composer<_$AppDatabase, $TaskTemplatesTable> {
  $$TaskTemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get estimateMinutes => $composableBuilder(
      column: $table.estimateMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get energyRequired => $composableBuilder(
      column: $table.energyRequired,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$TaskTemplatesTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskTemplatesTable> {
  $$TaskTemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get estimateMinutes => $composableBuilder(
      column: $table.estimateMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get energyRequired => $composableBuilder(
      column: $table.energyRequired,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$TaskTemplatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskTemplatesTable> {
  $$TaskTemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get estimateMinutes => $composableBuilder(
      column: $table.estimateMinutes, builder: (column) => column);

  GeneratedColumn<int> get energyRequired => $composableBuilder(
      column: $table.energyRequired, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TaskTemplatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TaskTemplatesTable,
    TaskTemplate,
    $$TaskTemplatesTableFilterComposer,
    $$TaskTemplatesTableOrderingComposer,
    $$TaskTemplatesTableAnnotationComposer,
    $$TaskTemplatesTableCreateCompanionBuilder,
    $$TaskTemplatesTableUpdateCompanionBuilder,
    (
      TaskTemplate,
      BaseReferences<_$AppDatabase, $TaskTemplatesTable, TaskTemplate>
    ),
    TaskTemplate,
    PrefetchHooks Function()> {
  $$TaskTemplatesTableTableManager(_$AppDatabase db, $TaskTemplatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskTemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskTemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskTemplatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int?> estimateMinutes = const Value.absent(),
            Value<int?> energyRequired = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TaskTemplatesCompanion(
            id: id,
            name: name,
            estimateMinutes: estimateMinutes,
            energyRequired: energyRequired,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<int?> estimateMinutes = const Value.absent(),
            Value<int?> energyRequired = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TaskTemplatesCompanion.insert(
            id: id,
            name: name,
            estimateMinutes: estimateMinutes,
            energyRequired: energyRequired,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TaskTemplatesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TaskTemplatesTable,
    TaskTemplate,
    $$TaskTemplatesTableFilterComposer,
    $$TaskTemplatesTableOrderingComposer,
    $$TaskTemplatesTableAnnotationComposer,
    $$TaskTemplatesTableCreateCompanionBuilder,
    $$TaskTemplatesTableUpdateCompanionBuilder,
    (
      TaskTemplate,
      BaseReferences<_$AppDatabase, $TaskTemplatesTable, TaskTemplate>
    ),
    TaskTemplate,
    PrefetchHooks Function()>;
typedef $$CompletionLogsTableCreateCompanionBuilder = CompletionLogsCompanion
    Function({
  required String id,
  required String taskId,
  required String title,
  Value<String?> tagIds,
  Value<String?> tagPaths,
  Value<int?> estimateMinutes,
  Value<int?> energyRequired,
  required int completedAt,
  Value<int?> actualMinutes,
  Value<bool> includeInModel,
  Value<bool> durationSuspicious,
  required int createdAt,
  Value<int> rowid,
});
typedef $$CompletionLogsTableUpdateCompanionBuilder = CompletionLogsCompanion
    Function({
  Value<String> id,
  Value<String> taskId,
  Value<String> title,
  Value<String?> tagIds,
  Value<String?> tagPaths,
  Value<int?> estimateMinutes,
  Value<int?> energyRequired,
  Value<int> completedAt,
  Value<int?> actualMinutes,
  Value<bool> includeInModel,
  Value<bool> durationSuspicious,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$CompletionLogsTableFilterComposer
    extends Composer<_$AppDatabase, $CompletionLogsTable> {
  $$CompletionLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagIds => $composableBuilder(
      column: $table.tagIds, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagPaths => $composableBuilder(
      column: $table.tagPaths, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get estimateMinutes => $composableBuilder(
      column: $table.estimateMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get energyRequired => $composableBuilder(
      column: $table.energyRequired,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get actualMinutes => $composableBuilder(
      column: $table.actualMinutes, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get includeInModel => $composableBuilder(
      column: $table.includeInModel,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get durationSuspicious => $composableBuilder(
      column: $table.durationSuspicious,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$CompletionLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $CompletionLogsTable> {
  $$CompletionLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagIds => $composableBuilder(
      column: $table.tagIds, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagPaths => $composableBuilder(
      column: $table.tagPaths, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get estimateMinutes => $composableBuilder(
      column: $table.estimateMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get energyRequired => $composableBuilder(
      column: $table.energyRequired,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get actualMinutes => $composableBuilder(
      column: $table.actualMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get includeInModel => $composableBuilder(
      column: $table.includeInModel,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get durationSuspicious => $composableBuilder(
      column: $table.durationSuspicious,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$CompletionLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CompletionLogsTable> {
  $$CompletionLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get tagIds =>
      $composableBuilder(column: $table.tagIds, builder: (column) => column);

  GeneratedColumn<String> get tagPaths =>
      $composableBuilder(column: $table.tagPaths, builder: (column) => column);

  GeneratedColumn<int> get estimateMinutes => $composableBuilder(
      column: $table.estimateMinutes, builder: (column) => column);

  GeneratedColumn<int> get energyRequired => $composableBuilder(
      column: $table.energyRequired, builder: (column) => column);

  GeneratedColumn<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);

  GeneratedColumn<int> get actualMinutes => $composableBuilder(
      column: $table.actualMinutes, builder: (column) => column);

  GeneratedColumn<bool> get includeInModel => $composableBuilder(
      column: $table.includeInModel, builder: (column) => column);

  GeneratedColumn<bool> get durationSuspicious => $composableBuilder(
      column: $table.durationSuspicious, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CompletionLogsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CompletionLogsTable,
    CompletionLog,
    $$CompletionLogsTableFilterComposer,
    $$CompletionLogsTableOrderingComposer,
    $$CompletionLogsTableAnnotationComposer,
    $$CompletionLogsTableCreateCompanionBuilder,
    $$CompletionLogsTableUpdateCompanionBuilder,
    (
      CompletionLog,
      BaseReferences<_$AppDatabase, $CompletionLogsTable, CompletionLog>
    ),
    CompletionLog,
    PrefetchHooks Function()> {
  $$CompletionLogsTableTableManager(
      _$AppDatabase db, $CompletionLogsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CompletionLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CompletionLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CompletionLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> taskId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> tagIds = const Value.absent(),
            Value<String?> tagPaths = const Value.absent(),
            Value<int?> estimateMinutes = const Value.absent(),
            Value<int?> energyRequired = const Value.absent(),
            Value<int> completedAt = const Value.absent(),
            Value<int?> actualMinutes = const Value.absent(),
            Value<bool> includeInModel = const Value.absent(),
            Value<bool> durationSuspicious = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CompletionLogsCompanion(
            id: id,
            taskId: taskId,
            title: title,
            tagIds: tagIds,
            tagPaths: tagPaths,
            estimateMinutes: estimateMinutes,
            energyRequired: energyRequired,
            completedAt: completedAt,
            actualMinutes: actualMinutes,
            includeInModel: includeInModel,
            durationSuspicious: durationSuspicious,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String taskId,
            required String title,
            Value<String?> tagIds = const Value.absent(),
            Value<String?> tagPaths = const Value.absent(),
            Value<int?> estimateMinutes = const Value.absent(),
            Value<int?> energyRequired = const Value.absent(),
            required int completedAt,
            Value<int?> actualMinutes = const Value.absent(),
            Value<bool> includeInModel = const Value.absent(),
            Value<bool> durationSuspicious = const Value.absent(),
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CompletionLogsCompanion.insert(
            id: id,
            taskId: taskId,
            title: title,
            tagIds: tagIds,
            tagPaths: tagPaths,
            estimateMinutes: estimateMinutes,
            energyRequired: energyRequired,
            completedAt: completedAt,
            actualMinutes: actualMinutes,
            includeInModel: includeInModel,
            durationSuspicious: durationSuspicious,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CompletionLogsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CompletionLogsTable,
    CompletionLog,
    $$CompletionLogsTableFilterComposer,
    $$CompletionLogsTableOrderingComposer,
    $$CompletionLogsTableAnnotationComposer,
    $$CompletionLogsTableCreateCompanionBuilder,
    $$CompletionLogsTableUpdateCompanionBuilder,
    (
      CompletionLog,
      BaseReferences<_$AppDatabase, $CompletionLogsTable, CompletionLog>
    ),
    CompletionLog,
    PrefetchHooks Function()>;
typedef $$ClozeSlotsTableCreateCompanionBuilder = ClozeSlotsCompanion Function({
  required String id,
  required String knowledgePointId,
  required String slotKey,
  required String definition,
  Value<int> exhausted,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$ClozeSlotsTableUpdateCompanionBuilder = ClozeSlotsCompanion Function({
  Value<String> id,
  Value<String> knowledgePointId,
  Value<String> slotKey,
  Value<String> definition,
  Value<int> exhausted,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$ClozeSlotsTableFilterComposer
    extends Composer<_$AppDatabase, $ClozeSlotsTable> {
  $$ClozeSlotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get slotKey => $composableBuilder(
      column: $table.slotKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get definition => $composableBuilder(
      column: $table.definition, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get exhausted => $composableBuilder(
      column: $table.exhausted, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ClozeSlotsTableOrderingComposer
    extends Composer<_$AppDatabase, $ClozeSlotsTable> {
  $$ClozeSlotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get slotKey => $composableBuilder(
      column: $table.slotKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get definition => $composableBuilder(
      column: $table.definition, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get exhausted => $composableBuilder(
      column: $table.exhausted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ClozeSlotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClozeSlotsTable> {
  $$ClozeSlotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId, builder: (column) => column);

  GeneratedColumn<String> get slotKey =>
      $composableBuilder(column: $table.slotKey, builder: (column) => column);

  GeneratedColumn<String> get definition => $composableBuilder(
      column: $table.definition, builder: (column) => column);

  GeneratedColumn<int> get exhausted =>
      $composableBuilder(column: $table.exhausted, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ClozeSlotsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ClozeSlotsTable,
    ClozeSlot,
    $$ClozeSlotsTableFilterComposer,
    $$ClozeSlotsTableOrderingComposer,
    $$ClozeSlotsTableAnnotationComposer,
    $$ClozeSlotsTableCreateCompanionBuilder,
    $$ClozeSlotsTableUpdateCompanionBuilder,
    (ClozeSlot, BaseReferences<_$AppDatabase, $ClozeSlotsTable, ClozeSlot>),
    ClozeSlot,
    PrefetchHooks Function()> {
  $$ClozeSlotsTableTableManager(_$AppDatabase db, $ClozeSlotsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClozeSlotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClozeSlotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClozeSlotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> knowledgePointId = const Value.absent(),
            Value<String> slotKey = const Value.absent(),
            Value<String> definition = const Value.absent(),
            Value<int> exhausted = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ClozeSlotsCompanion(
            id: id,
            knowledgePointId: knowledgePointId,
            slotKey: slotKey,
            definition: definition,
            exhausted: exhausted,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String knowledgePointId,
            required String slotKey,
            required String definition,
            Value<int> exhausted = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ClozeSlotsCompanion.insert(
            id: id,
            knowledgePointId: knowledgePointId,
            slotKey: slotKey,
            definition: definition,
            exhausted: exhausted,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ClozeSlotsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ClozeSlotsTable,
    ClozeSlot,
    $$ClozeSlotsTableFilterComposer,
    $$ClozeSlotsTableOrderingComposer,
    $$ClozeSlotsTableAnnotationComposer,
    $$ClozeSlotsTableCreateCompanionBuilder,
    $$ClozeSlotsTableUpdateCompanionBuilder,
    (ClozeSlot, BaseReferences<_$AppDatabase, $ClozeSlotsTable, ClozeSlot>),
    ClozeSlot,
    PrefetchHooks Function()>;
typedef $$ClozeHistoryTableCreateCompanionBuilder = ClozeHistoryCompanion
    Function({
  required String id,
  required String knowledgePointId,
  required String slotKey,
  Value<int> correct,
  required int usedAt,
  required int createdAt,
  Value<int> rowid,
});
typedef $$ClozeHistoryTableUpdateCompanionBuilder = ClozeHistoryCompanion
    Function({
  Value<String> id,
  Value<String> knowledgePointId,
  Value<String> slotKey,
  Value<int> correct,
  Value<int> usedAt,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$ClozeHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $ClozeHistoryTable> {
  $$ClozeHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get slotKey => $composableBuilder(
      column: $table.slotKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get correct => $composableBuilder(
      column: $table.correct, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get usedAt => $composableBuilder(
      column: $table.usedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ClozeHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $ClozeHistoryTable> {
  $$ClozeHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get slotKey => $composableBuilder(
      column: $table.slotKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get correct => $composableBuilder(
      column: $table.correct, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get usedAt => $composableBuilder(
      column: $table.usedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ClozeHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClozeHistoryTable> {
  $$ClozeHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId, builder: (column) => column);

  GeneratedColumn<String> get slotKey =>
      $composableBuilder(column: $table.slotKey, builder: (column) => column);

  GeneratedColumn<int> get correct =>
      $composableBuilder(column: $table.correct, builder: (column) => column);

  GeneratedColumn<int> get usedAt =>
      $composableBuilder(column: $table.usedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ClozeHistoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ClozeHistoryTable,
    ClozeHistoryData,
    $$ClozeHistoryTableFilterComposer,
    $$ClozeHistoryTableOrderingComposer,
    $$ClozeHistoryTableAnnotationComposer,
    $$ClozeHistoryTableCreateCompanionBuilder,
    $$ClozeHistoryTableUpdateCompanionBuilder,
    (
      ClozeHistoryData,
      BaseReferences<_$AppDatabase, $ClozeHistoryTable, ClozeHistoryData>
    ),
    ClozeHistoryData,
    PrefetchHooks Function()> {
  $$ClozeHistoryTableTableManager(_$AppDatabase db, $ClozeHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClozeHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClozeHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClozeHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> knowledgePointId = const Value.absent(),
            Value<String> slotKey = const Value.absent(),
            Value<int> correct = const Value.absent(),
            Value<int> usedAt = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ClozeHistoryCompanion(
            id: id,
            knowledgePointId: knowledgePointId,
            slotKey: slotKey,
            correct: correct,
            usedAt: usedAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String knowledgePointId,
            required String slotKey,
            Value<int> correct = const Value.absent(),
            required int usedAt,
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ClozeHistoryCompanion.insert(
            id: id,
            knowledgePointId: knowledgePointId,
            slotKey: slotKey,
            correct: correct,
            usedAt: usedAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ClozeHistoryTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ClozeHistoryTable,
    ClozeHistoryData,
    $$ClozeHistoryTableFilterComposer,
    $$ClozeHistoryTableOrderingComposer,
    $$ClozeHistoryTableAnnotationComposer,
    $$ClozeHistoryTableCreateCompanionBuilder,
    $$ClozeHistoryTableUpdateCompanionBuilder,
    (
      ClozeHistoryData,
      BaseReferences<_$AppDatabase, $ClozeHistoryTable, ClozeHistoryData>
    ),
    ClozeHistoryData,
    PrefetchHooks Function()>;
typedef $$BoostEntriesTableCreateCompanionBuilder = BoostEntriesCompanion
    Function({
  required String id,
  required String knowledgePointId,
  required double factor,
  Value<int> remainingCycles,
  required int createdAt,
  Value<int> rowid,
});
typedef $$BoostEntriesTableUpdateCompanionBuilder = BoostEntriesCompanion
    Function({
  Value<String> id,
  Value<String> knowledgePointId,
  Value<double> factor,
  Value<int> remainingCycles,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$BoostEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $BoostEntriesTable> {
  $$BoostEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get factor => $composableBuilder(
      column: $table.factor, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get remainingCycles => $composableBuilder(
      column: $table.remainingCycles,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$BoostEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $BoostEntriesTable> {
  $$BoostEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get factor => $composableBuilder(
      column: $table.factor, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get remainingCycles => $composableBuilder(
      column: $table.remainingCycles,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$BoostEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BoostEntriesTable> {
  $$BoostEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId, builder: (column) => column);

  GeneratedColumn<double> get factor =>
      $composableBuilder(column: $table.factor, builder: (column) => column);

  GeneratedColumn<int> get remainingCycles => $composableBuilder(
      column: $table.remainingCycles, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$BoostEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BoostEntriesTable,
    BoostEntry,
    $$BoostEntriesTableFilterComposer,
    $$BoostEntriesTableOrderingComposer,
    $$BoostEntriesTableAnnotationComposer,
    $$BoostEntriesTableCreateCompanionBuilder,
    $$BoostEntriesTableUpdateCompanionBuilder,
    (BoostEntry, BaseReferences<_$AppDatabase, $BoostEntriesTable, BoostEntry>),
    BoostEntry,
    PrefetchHooks Function()> {
  $$BoostEntriesTableTableManager(_$AppDatabase db, $BoostEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BoostEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BoostEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BoostEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> knowledgePointId = const Value.absent(),
            Value<double> factor = const Value.absent(),
            Value<int> remainingCycles = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BoostEntriesCompanion(
            id: id,
            knowledgePointId: knowledgePointId,
            factor: factor,
            remainingCycles: remainingCycles,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String knowledgePointId,
            required double factor,
            Value<int> remainingCycles = const Value.absent(),
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              BoostEntriesCompanion.insert(
            id: id,
            knowledgePointId: knowledgePointId,
            factor: factor,
            remainingCycles: remainingCycles,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BoostEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BoostEntriesTable,
    BoostEntry,
    $$BoostEntriesTableFilterComposer,
    $$BoostEntriesTableOrderingComposer,
    $$BoostEntriesTableAnnotationComposer,
    $$BoostEntriesTableCreateCompanionBuilder,
    $$BoostEntriesTableUpdateCompanionBuilder,
    (BoostEntry, BaseReferences<_$AppDatabase, $BoostEntriesTable, BoostEntry>),
    BoostEntry,
    PrefetchHooks Function()>;
typedef $$ThemesTableCreateCompanionBuilder = ThemesCompanion Function({
  required String id,
  required String name,
  Value<int> isBuiltin,
  required String payload,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$ThemesTableUpdateCompanionBuilder = ThemesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> isBuiltin,
  Value<String> payload,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$ThemesTableFilterComposer
    extends Composer<_$AppDatabase, $ThemesTable> {
  $$ThemesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get isBuiltin => $composableBuilder(
      column: $table.isBuiltin, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ThemesTableOrderingComposer
    extends Composer<_$AppDatabase, $ThemesTable> {
  $$ThemesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get isBuiltin => $composableBuilder(
      column: $table.isBuiltin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ThemesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ThemesTable> {
  $$ThemesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get isBuiltin =>
      $composableBuilder(column: $table.isBuiltin, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ThemesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ThemesTable,
    ThemeProfile,
    $$ThemesTableFilterComposer,
    $$ThemesTableOrderingComposer,
    $$ThemesTableAnnotationComposer,
    $$ThemesTableCreateCompanionBuilder,
    $$ThemesTableUpdateCompanionBuilder,
    (ThemeProfile, BaseReferences<_$AppDatabase, $ThemesTable, ThemeProfile>),
    ThemeProfile,
    PrefetchHooks Function()> {
  $$ThemesTableTableManager(_$AppDatabase db, $ThemesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ThemesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ThemesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ThemesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> isBuiltin = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ThemesCompanion(
            id: id,
            name: name,
            isBuiltin: isBuiltin,
            payload: payload,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<int> isBuiltin = const Value.absent(),
            required String payload,
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ThemesCompanion.insert(
            id: id,
            name: name,
            isBuiltin: isBuiltin,
            payload: payload,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ThemesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ThemesTable,
    ThemeProfile,
    $$ThemesTableFilterComposer,
    $$ThemesTableOrderingComposer,
    $$ThemesTableAnnotationComposer,
    $$ThemesTableCreateCompanionBuilder,
    $$ThemesTableUpdateCompanionBuilder,
    (ThemeProfile, BaseReferences<_$AppDatabase, $ThemesTable, ThemeProfile>),
    ThemeProfile,
    PrefetchHooks Function()>;
typedef $$AttachmentsTableCreateCompanionBuilder = AttachmentsCompanion
    Function({
  required String id,
  required String ownerType,
  required String ownerId,
  required String relPath,
  Value<String?> mime,
  required int createdAt,
  Value<int> rowid,
});
typedef $$AttachmentsTableUpdateCompanionBuilder = AttachmentsCompanion
    Function({
  Value<String> id,
  Value<String> ownerType,
  Value<String> ownerId,
  Value<String> relPath,
  Value<String?> mime,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$AttachmentsTableFilterComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerType => $composableBuilder(
      column: $table.ownerType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get relPath => $composableBuilder(
      column: $table.relPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mime => $composableBuilder(
      column: $table.mime, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$AttachmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerType => $composableBuilder(
      column: $table.ownerType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get relPath => $composableBuilder(
      column: $table.relPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mime => $composableBuilder(
      column: $table.mime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$AttachmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerType =>
      $composableBuilder(column: $table.ownerType, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get relPath =>
      $composableBuilder(column: $table.relPath, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AttachmentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AttachmentsTable,
    Attachment,
    $$AttachmentsTableFilterComposer,
    $$AttachmentsTableOrderingComposer,
    $$AttachmentsTableAnnotationComposer,
    $$AttachmentsTableCreateCompanionBuilder,
    $$AttachmentsTableUpdateCompanionBuilder,
    (Attachment, BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>),
    Attachment,
    PrefetchHooks Function()> {
  $$AttachmentsTableTableManager(_$AppDatabase db, $AttachmentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> ownerType = const Value.absent(),
            Value<String> ownerId = const Value.absent(),
            Value<String> relPath = const Value.absent(),
            Value<String?> mime = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AttachmentsCompanion(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            relPath: relPath,
            mime: mime,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String ownerType,
            required String ownerId,
            required String relPath,
            Value<String?> mime = const Value.absent(),
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AttachmentsCompanion.insert(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            relPath: relPath,
            mime: mime,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AttachmentsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AttachmentsTable,
    Attachment,
    $$AttachmentsTableFilterComposer,
    $$AttachmentsTableOrderingComposer,
    $$AttachmentsTableAnnotationComposer,
    $$AttachmentsTableCreateCompanionBuilder,
    $$AttachmentsTableUpdateCompanionBuilder,
    (Attachment, BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>),
    Attachment,
    PrefetchHooks Function()>;
typedef $$ThreadRankSettingsTableCreateCompanionBuilder
    = ThreadRankSettingsCompanion Function({
  Value<int> id,
  Value<double> wUrgency,
  Value<double> wGoal,
  Value<double> wFit,
  Value<double> wFatigue,
  Value<double> wExpected,
  Value<bool> headerCollapsed,
  Value<bool> useActualTime,
  Value<int?> updatedAt,
  required int createdAt,
});
typedef $$ThreadRankSettingsTableUpdateCompanionBuilder
    = ThreadRankSettingsCompanion Function({
  Value<int> id,
  Value<double> wUrgency,
  Value<double> wGoal,
  Value<double> wFit,
  Value<double> wFatigue,
  Value<double> wExpected,
  Value<bool> headerCollapsed,
  Value<bool> useActualTime,
  Value<int?> updatedAt,
  Value<int> createdAt,
});

class $$ThreadRankSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $ThreadRankSettingsTable> {
  $$ThreadRankSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get wUrgency => $composableBuilder(
      column: $table.wUrgency, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get wGoal => $composableBuilder(
      column: $table.wGoal, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get wFit => $composableBuilder(
      column: $table.wFit, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get wFatigue => $composableBuilder(
      column: $table.wFatigue, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get wExpected => $composableBuilder(
      column: $table.wExpected, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get headerCollapsed => $composableBuilder(
      column: $table.headerCollapsed,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get useActualTime => $composableBuilder(
      column: $table.useActualTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ThreadRankSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $ThreadRankSettingsTable> {
  $$ThreadRankSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get wUrgency => $composableBuilder(
      column: $table.wUrgency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get wGoal => $composableBuilder(
      column: $table.wGoal, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get wFit => $composableBuilder(
      column: $table.wFit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get wFatigue => $composableBuilder(
      column: $table.wFatigue, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get wExpected => $composableBuilder(
      column: $table.wExpected, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get headerCollapsed => $composableBuilder(
      column: $table.headerCollapsed,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get useActualTime => $composableBuilder(
      column: $table.useActualTime,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ThreadRankSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ThreadRankSettingsTable> {
  $$ThreadRankSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get wUrgency =>
      $composableBuilder(column: $table.wUrgency, builder: (column) => column);

  GeneratedColumn<double> get wGoal =>
      $composableBuilder(column: $table.wGoal, builder: (column) => column);

  GeneratedColumn<double> get wFit =>
      $composableBuilder(column: $table.wFit, builder: (column) => column);

  GeneratedColumn<double> get wFatigue =>
      $composableBuilder(column: $table.wFatigue, builder: (column) => column);

  GeneratedColumn<double> get wExpected =>
      $composableBuilder(column: $table.wExpected, builder: (column) => column);

  GeneratedColumn<bool> get headerCollapsed => $composableBuilder(
      column: $table.headerCollapsed, builder: (column) => column);

  GeneratedColumn<bool> get useActualTime => $composableBuilder(
      column: $table.useActualTime, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ThreadRankSettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ThreadRankSettingsTable,
    ThreadRankSetting,
    $$ThreadRankSettingsTableFilterComposer,
    $$ThreadRankSettingsTableOrderingComposer,
    $$ThreadRankSettingsTableAnnotationComposer,
    $$ThreadRankSettingsTableCreateCompanionBuilder,
    $$ThreadRankSettingsTableUpdateCompanionBuilder,
    (
      ThreadRankSetting,
      BaseReferences<_$AppDatabase, $ThreadRankSettingsTable, ThreadRankSetting>
    ),
    ThreadRankSetting,
    PrefetchHooks Function()> {
  $$ThreadRankSettingsTableTableManager(
      _$AppDatabase db, $ThreadRankSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ThreadRankSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ThreadRankSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ThreadRankSettingsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<double> wUrgency = const Value.absent(),
            Value<double> wGoal = const Value.absent(),
            Value<double> wFit = const Value.absent(),
            Value<double> wFatigue = const Value.absent(),
            Value<double> wExpected = const Value.absent(),
            Value<bool> headerCollapsed = const Value.absent(),
            Value<bool> useActualTime = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
          }) =>
              ThreadRankSettingsCompanion(
            id: id,
            wUrgency: wUrgency,
            wGoal: wGoal,
            wFit: wFit,
            wFatigue: wFatigue,
            wExpected: wExpected,
            headerCollapsed: headerCollapsed,
            useActualTime: useActualTime,
            updatedAt: updatedAt,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<double> wUrgency = const Value.absent(),
            Value<double> wGoal = const Value.absent(),
            Value<double> wFit = const Value.absent(),
            Value<double> wFatigue = const Value.absent(),
            Value<double> wExpected = const Value.absent(),
            Value<bool> headerCollapsed = const Value.absent(),
            Value<bool> useActualTime = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            required int createdAt,
          }) =>
              ThreadRankSettingsCompanion.insert(
            id: id,
            wUrgency: wUrgency,
            wGoal: wGoal,
            wFit: wFit,
            wFatigue: wFatigue,
            wExpected: wExpected,
            headerCollapsed: headerCollapsed,
            useActualTime: useActualTime,
            updatedAt: updatedAt,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ThreadRankSettingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ThreadRankSettingsTable,
    ThreadRankSetting,
    $$ThreadRankSettingsTableFilterComposer,
    $$ThreadRankSettingsTableOrderingComposer,
    $$ThreadRankSettingsTableAnnotationComposer,
    $$ThreadRankSettingsTableCreateCompanionBuilder,
    $$ThreadRankSettingsTableUpdateCompanionBuilder,
    (
      ThreadRankSetting,
      BaseReferences<_$AppDatabase, $ThreadRankSettingsTable, ThreadRankSetting>
    ),
    ThreadRankSetting,
    PrefetchHooks Function()>;
typedef $$DiffusionLogsTableCreateCompanionBuilder = DiffusionLogsCompanion
    Function({
  required String id,
  required String ownerType,
  Value<String?> ownerId,
  Value<String?> ownerTitle,
  required String kind,
  Value<String?> knowledgePointId,
  Value<String?> knowledgePointTitle,
  Value<int?> distance,
  Value<double?> factor,
  Value<String?> detail,
  required String dayKey,
  required int occurredAt,
  required int createdAt,
  Value<int> rowid,
});
typedef $$DiffusionLogsTableUpdateCompanionBuilder = DiffusionLogsCompanion
    Function({
  Value<String> id,
  Value<String> ownerType,
  Value<String?> ownerId,
  Value<String?> ownerTitle,
  Value<String> kind,
  Value<String?> knowledgePointId,
  Value<String?> knowledgePointTitle,
  Value<int?> distance,
  Value<double?> factor,
  Value<String?> detail,
  Value<String> dayKey,
  Value<int> occurredAt,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$DiffusionLogsTableFilterComposer
    extends Composer<_$AppDatabase, $DiffusionLogsTable> {
  $$DiffusionLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerType => $composableBuilder(
      column: $table.ownerType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerTitle => $composableBuilder(
      column: $table.ownerTitle, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get knowledgePointTitle => $composableBuilder(
      column: $table.knowledgePointTitle,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get distance => $composableBuilder(
      column: $table.distance, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get factor => $composableBuilder(
      column: $table.factor, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get detail => $composableBuilder(
      column: $table.detail, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dayKey => $composableBuilder(
      column: $table.dayKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$DiffusionLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $DiffusionLogsTable> {
  $$DiffusionLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerType => $composableBuilder(
      column: $table.ownerType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerTitle => $composableBuilder(
      column: $table.ownerTitle, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get knowledgePointTitle => $composableBuilder(
      column: $table.knowledgePointTitle,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get distance => $composableBuilder(
      column: $table.distance, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get factor => $composableBuilder(
      column: $table.factor, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get detail => $composableBuilder(
      column: $table.detail, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dayKey => $composableBuilder(
      column: $table.dayKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$DiffusionLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiffusionLogsTable> {
  $$DiffusionLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerType =>
      $composableBuilder(column: $table.ownerType, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get ownerTitle => $composableBuilder(
      column: $table.ownerTitle, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get knowledgePointId => $composableBuilder(
      column: $table.knowledgePointId, builder: (column) => column);

  GeneratedColumn<String> get knowledgePointTitle => $composableBuilder(
      column: $table.knowledgePointTitle, builder: (column) => column);

  GeneratedColumn<int> get distance =>
      $composableBuilder(column: $table.distance, builder: (column) => column);

  GeneratedColumn<double> get factor =>
      $composableBuilder(column: $table.factor, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => column);

  GeneratedColumn<int> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DiffusionLogsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DiffusionLogsTable,
    DiffusionLog,
    $$DiffusionLogsTableFilterComposer,
    $$DiffusionLogsTableOrderingComposer,
    $$DiffusionLogsTableAnnotationComposer,
    $$DiffusionLogsTableCreateCompanionBuilder,
    $$DiffusionLogsTableUpdateCompanionBuilder,
    (
      DiffusionLog,
      BaseReferences<_$AppDatabase, $DiffusionLogsTable, DiffusionLog>
    ),
    DiffusionLog,
    PrefetchHooks Function()> {
  $$DiffusionLogsTableTableManager(_$AppDatabase db, $DiffusionLogsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiffusionLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiffusionLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiffusionLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> ownerType = const Value.absent(),
            Value<String?> ownerId = const Value.absent(),
            Value<String?> ownerTitle = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String?> knowledgePointId = const Value.absent(),
            Value<String?> knowledgePointTitle = const Value.absent(),
            Value<int?> distance = const Value.absent(),
            Value<double?> factor = const Value.absent(),
            Value<String?> detail = const Value.absent(),
            Value<String> dayKey = const Value.absent(),
            Value<int> occurredAt = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DiffusionLogsCompanion(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            ownerTitle: ownerTitle,
            kind: kind,
            knowledgePointId: knowledgePointId,
            knowledgePointTitle: knowledgePointTitle,
            distance: distance,
            factor: factor,
            detail: detail,
            dayKey: dayKey,
            occurredAt: occurredAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String ownerType,
            Value<String?> ownerId = const Value.absent(),
            Value<String?> ownerTitle = const Value.absent(),
            required String kind,
            Value<String?> knowledgePointId = const Value.absent(),
            Value<String?> knowledgePointTitle = const Value.absent(),
            Value<int?> distance = const Value.absent(),
            Value<double?> factor = const Value.absent(),
            Value<String?> detail = const Value.absent(),
            required String dayKey,
            required int occurredAt,
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              DiffusionLogsCompanion.insert(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            ownerTitle: ownerTitle,
            kind: kind,
            knowledgePointId: knowledgePointId,
            knowledgePointTitle: knowledgePointTitle,
            distance: distance,
            factor: factor,
            detail: detail,
            dayKey: dayKey,
            occurredAt: occurredAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DiffusionLogsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DiffusionLogsTable,
    DiffusionLog,
    $$DiffusionLogsTableFilterComposer,
    $$DiffusionLogsTableOrderingComposer,
    $$DiffusionLogsTableAnnotationComposer,
    $$DiffusionLogsTableCreateCompanionBuilder,
    $$DiffusionLogsTableUpdateCompanionBuilder,
    (
      DiffusionLog,
      BaseReferences<_$AppDatabase, $DiffusionLogsTable, DiffusionLog>
    ),
    DiffusionLog,
    PrefetchHooks Function()>;
typedef $$TimeTemplatesTableCreateCompanionBuilder = TimeTemplatesCompanion
    Function({
  required String id,
  required String name,
  required String kind,
  required String payload,
  Value<int> sortOrder,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$TimeTemplatesTableUpdateCompanionBuilder = TimeTemplatesCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String> kind,
  Value<String> payload,
  Value<int> sortOrder,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$TimeTemplatesTableFilterComposer
    extends Composer<_$AppDatabase, $TimeTemplatesTable> {
  $$TimeTemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$TimeTemplatesTableOrderingComposer
    extends Composer<_$AppDatabase, $TimeTemplatesTable> {
  $$TimeTemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$TimeTemplatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TimeTemplatesTable> {
  $$TimeTemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TimeTemplatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TimeTemplatesTable,
    TimeTemplate,
    $$TimeTemplatesTableFilterComposer,
    $$TimeTemplatesTableOrderingComposer,
    $$TimeTemplatesTableAnnotationComposer,
    $$TimeTemplatesTableCreateCompanionBuilder,
    $$TimeTemplatesTableUpdateCompanionBuilder,
    (
      TimeTemplate,
      BaseReferences<_$AppDatabase, $TimeTemplatesTable, TimeTemplate>
    ),
    TimeTemplate,
    PrefetchHooks Function()> {
  $$TimeTemplatesTableTableManager(_$AppDatabase db, $TimeTemplatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TimeTemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TimeTemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TimeTemplatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TimeTemplatesCompanion(
            id: id,
            name: name,
            kind: kind,
            payload: payload,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String kind,
            required String payload,
            Value<int> sortOrder = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TimeTemplatesCompanion.insert(
            id: id,
            name: name,
            kind: kind,
            payload: payload,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TimeTemplatesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TimeTemplatesTable,
    TimeTemplate,
    $$TimeTemplatesTableFilterComposer,
    $$TimeTemplatesTableOrderingComposer,
    $$TimeTemplatesTableAnnotationComposer,
    $$TimeTemplatesTableCreateCompanionBuilder,
    $$TimeTemplatesTableUpdateCompanionBuilder,
    (
      TimeTemplate,
      BaseReferences<_$AppDatabase, $TimeTemplatesTable, TimeTemplate>
    ),
    TimeTemplate,
    PrefetchHooks Function()>;
typedef $$TimeViewSettingsTableCreateCompanionBuilder
    = TimeViewSettingsCompanion Function({
  Value<int> id,
  Value<int> timelineSpanDays,
  Value<double> timelinePxPerDay,
  Value<bool> timelineCollapsed,
  Value<int> minutesPerRow,
  Value<bool> minutesPerRowChosen,
  Value<int?> updatedAt,
  required int createdAt,
});
typedef $$TimeViewSettingsTableUpdateCompanionBuilder
    = TimeViewSettingsCompanion Function({
  Value<int> id,
  Value<int> timelineSpanDays,
  Value<double> timelinePxPerDay,
  Value<bool> timelineCollapsed,
  Value<int> minutesPerRow,
  Value<bool> minutesPerRowChosen,
  Value<int?> updatedAt,
  Value<int> createdAt,
});

class $$TimeViewSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $TimeViewSettingsTable> {
  $$TimeViewSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get timelineSpanDays => $composableBuilder(
      column: $table.timelineSpanDays,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get timelinePxPerDay => $composableBuilder(
      column: $table.timelinePxPerDay,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get timelineCollapsed => $composableBuilder(
      column: $table.timelineCollapsed,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get minutesPerRow => $composableBuilder(
      column: $table.minutesPerRow, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get minutesPerRowChosen => $composableBuilder(
      column: $table.minutesPerRowChosen,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$TimeViewSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $TimeViewSettingsTable> {
  $$TimeViewSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get timelineSpanDays => $composableBuilder(
      column: $table.timelineSpanDays,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get timelinePxPerDay => $composableBuilder(
      column: $table.timelinePxPerDay,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get timelineCollapsed => $composableBuilder(
      column: $table.timelineCollapsed,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get minutesPerRow => $composableBuilder(
      column: $table.minutesPerRow,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get minutesPerRowChosen => $composableBuilder(
      column: $table.minutesPerRowChosen,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$TimeViewSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TimeViewSettingsTable> {
  $$TimeViewSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get timelineSpanDays => $composableBuilder(
      column: $table.timelineSpanDays, builder: (column) => column);

  GeneratedColumn<double> get timelinePxPerDay => $composableBuilder(
      column: $table.timelinePxPerDay, builder: (column) => column);

  GeneratedColumn<bool> get timelineCollapsed => $composableBuilder(
      column: $table.timelineCollapsed, builder: (column) => column);

  GeneratedColumn<int> get minutesPerRow => $composableBuilder(
      column: $table.minutesPerRow, builder: (column) => column);

  GeneratedColumn<bool> get minutesPerRowChosen => $composableBuilder(
      column: $table.minutesPerRowChosen, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TimeViewSettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TimeViewSettingsTable,
    TimeViewSetting,
    $$TimeViewSettingsTableFilterComposer,
    $$TimeViewSettingsTableOrderingComposer,
    $$TimeViewSettingsTableAnnotationComposer,
    $$TimeViewSettingsTableCreateCompanionBuilder,
    $$TimeViewSettingsTableUpdateCompanionBuilder,
    (
      TimeViewSetting,
      BaseReferences<_$AppDatabase, $TimeViewSettingsTable, TimeViewSetting>
    ),
    TimeViewSetting,
    PrefetchHooks Function()> {
  $$TimeViewSettingsTableTableManager(
      _$AppDatabase db, $TimeViewSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TimeViewSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TimeViewSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TimeViewSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> timelineSpanDays = const Value.absent(),
            Value<double> timelinePxPerDay = const Value.absent(),
            Value<bool> timelineCollapsed = const Value.absent(),
            Value<int> minutesPerRow = const Value.absent(),
            Value<bool> minutesPerRowChosen = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
          }) =>
              TimeViewSettingsCompanion(
            id: id,
            timelineSpanDays: timelineSpanDays,
            timelinePxPerDay: timelinePxPerDay,
            timelineCollapsed: timelineCollapsed,
            minutesPerRow: minutesPerRow,
            minutesPerRowChosen: minutesPerRowChosen,
            updatedAt: updatedAt,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> timelineSpanDays = const Value.absent(),
            Value<double> timelinePxPerDay = const Value.absent(),
            Value<bool> timelineCollapsed = const Value.absent(),
            Value<int> minutesPerRow = const Value.absent(),
            Value<bool> minutesPerRowChosen = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            required int createdAt,
          }) =>
              TimeViewSettingsCompanion.insert(
            id: id,
            timelineSpanDays: timelineSpanDays,
            timelinePxPerDay: timelinePxPerDay,
            timelineCollapsed: timelineCollapsed,
            minutesPerRow: minutesPerRow,
            minutesPerRowChosen: minutesPerRowChosen,
            updatedAt: updatedAt,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TimeViewSettingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TimeViewSettingsTable,
    TimeViewSetting,
    $$TimeViewSettingsTableFilterComposer,
    $$TimeViewSettingsTableOrderingComposer,
    $$TimeViewSettingsTableAnnotationComposer,
    $$TimeViewSettingsTableCreateCompanionBuilder,
    $$TimeViewSettingsTableUpdateCompanionBuilder,
    (
      TimeViewSetting,
      BaseReferences<_$AppDatabase, $TimeViewSettingsTable, TimeViewSetting>
    ),
    TimeViewSetting,
    PrefetchHooks Function()>;
typedef $$AiConversationsTableCreateCompanionBuilder = AiConversationsCompanion
    Function({
  required String id,
  required String title,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$AiConversationsTableUpdateCompanionBuilder = AiConversationsCompanion
    Function({
  Value<String> id,
  Value<String> title,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$AiConversationsTableFilterComposer
    extends Composer<_$AppDatabase, $AiConversationsTable> {
  $$AiConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$AiConversationsTableOrderingComposer
    extends Composer<_$AppDatabase, $AiConversationsTable> {
  $$AiConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$AiConversationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiConversationsTable> {
  $$AiConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AiConversationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AiConversationsTable,
    AiConversation,
    $$AiConversationsTableFilterComposer,
    $$AiConversationsTableOrderingComposer,
    $$AiConversationsTableAnnotationComposer,
    $$AiConversationsTableCreateCompanionBuilder,
    $$AiConversationsTableUpdateCompanionBuilder,
    (
      AiConversation,
      BaseReferences<_$AppDatabase, $AiConversationsTable, AiConversation>
    ),
    AiConversation,
    PrefetchHooks Function()> {
  $$AiConversationsTableTableManager(
      _$AppDatabase db, $AiConversationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AiConversationsCompanion(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AiConversationsCompanion.insert(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AiConversationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AiConversationsTable,
    AiConversation,
    $$AiConversationsTableFilterComposer,
    $$AiConversationsTableOrderingComposer,
    $$AiConversationsTableAnnotationComposer,
    $$AiConversationsTableCreateCompanionBuilder,
    $$AiConversationsTableUpdateCompanionBuilder,
    (
      AiConversation,
      BaseReferences<_$AppDatabase, $AiConversationsTable, AiConversation>
    ),
    AiConversation,
    PrefetchHooks Function()>;
typedef $$AiMessagesTableCreateCompanionBuilder = AiMessagesCompanion Function({
  required String id,
  required String conversationId,
  required String role,
  Value<String?> content,
  Value<String?> toolCallId,
  required int createdAt,
  Value<int> rowid,
});
typedef $$AiMessagesTableUpdateCompanionBuilder = AiMessagesCompanion Function({
  Value<String> id,
  Value<String> conversationId,
  Value<String> role,
  Value<String?> content,
  Value<String?> toolCallId,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$AiMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $AiMessagesTable> {
  $$AiMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get toolCallId => $composableBuilder(
      column: $table.toolCallId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$AiMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $AiMessagesTable> {
  $$AiMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get toolCallId => $composableBuilder(
      column: $table.toolCallId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$AiMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiMessagesTable> {
  $$AiMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
      column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get toolCallId => $composableBuilder(
      column: $table.toolCallId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AiMessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AiMessagesTable,
    AiMessage,
    $$AiMessagesTableFilterComposer,
    $$AiMessagesTableOrderingComposer,
    $$AiMessagesTableAnnotationComposer,
    $$AiMessagesTableCreateCompanionBuilder,
    $$AiMessagesTableUpdateCompanionBuilder,
    (AiMessage, BaseReferences<_$AppDatabase, $AiMessagesTable, AiMessage>),
    AiMessage,
    PrefetchHooks Function()> {
  $$AiMessagesTableTableManager(_$AppDatabase db, $AiMessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> conversationId = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String?> content = const Value.absent(),
            Value<String?> toolCallId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AiMessagesCompanion(
            id: id,
            conversationId: conversationId,
            role: role,
            content: content,
            toolCallId: toolCallId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String conversationId,
            required String role,
            Value<String?> content = const Value.absent(),
            Value<String?> toolCallId = const Value.absent(),
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AiMessagesCompanion.insert(
            id: id,
            conversationId: conversationId,
            role: role,
            content: content,
            toolCallId: toolCallId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AiMessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AiMessagesTable,
    AiMessage,
    $$AiMessagesTableFilterComposer,
    $$AiMessagesTableOrderingComposer,
    $$AiMessagesTableAnnotationComposer,
    $$AiMessagesTableCreateCompanionBuilder,
    $$AiMessagesTableUpdateCompanionBuilder,
    (AiMessage, BaseReferences<_$AppDatabase, $AiMessagesTable, AiMessage>),
    AiMessage,
    PrefetchHooks Function()>;
typedef $$AiActionsTableCreateCompanionBuilder = AiActionsCompanion Function({
  required String id,
  Value<String?> messageId,
  required String conversationId,
  Value<String?> toolCallId,
  required String toolName,
  required String argsJson,
  required String risk,
  required String status,
  Value<String?> beforeJson,
  Value<String?> afterJson,
  Value<String?> resultJson,
  required int createdAt,
  Value<int?> updatedAt,
  Value<int> rowid,
});
typedef $$AiActionsTableUpdateCompanionBuilder = AiActionsCompanion Function({
  Value<String> id,
  Value<String?> messageId,
  Value<String> conversationId,
  Value<String?> toolCallId,
  Value<String> toolName,
  Value<String> argsJson,
  Value<String> risk,
  Value<String> status,
  Value<String?> beforeJson,
  Value<String?> afterJson,
  Value<String?> resultJson,
  Value<int> createdAt,
  Value<int?> updatedAt,
  Value<int> rowid,
});

class $$AiActionsTableFilterComposer
    extends Composer<_$AppDatabase, $AiActionsTable> {
  $$AiActionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get messageId => $composableBuilder(
      column: $table.messageId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get toolCallId => $composableBuilder(
      column: $table.toolCallId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get toolName => $composableBuilder(
      column: $table.toolName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get argsJson => $composableBuilder(
      column: $table.argsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get risk => $composableBuilder(
      column: $table.risk, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get beforeJson => $composableBuilder(
      column: $table.beforeJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get afterJson => $composableBuilder(
      column: $table.afterJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resultJson => $composableBuilder(
      column: $table.resultJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$AiActionsTableOrderingComposer
    extends Composer<_$AppDatabase, $AiActionsTable> {
  $$AiActionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get messageId => $composableBuilder(
      column: $table.messageId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get toolCallId => $composableBuilder(
      column: $table.toolCallId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get toolName => $composableBuilder(
      column: $table.toolName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get argsJson => $composableBuilder(
      column: $table.argsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get risk => $composableBuilder(
      column: $table.risk, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get beforeJson => $composableBuilder(
      column: $table.beforeJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get afterJson => $composableBuilder(
      column: $table.afterJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resultJson => $composableBuilder(
      column: $table.resultJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$AiActionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiActionsTable> {
  $$AiActionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
      column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get toolCallId => $composableBuilder(
      column: $table.toolCallId, builder: (column) => column);

  GeneratedColumn<String> get toolName =>
      $composableBuilder(column: $table.toolName, builder: (column) => column);

  GeneratedColumn<String> get argsJson =>
      $composableBuilder(column: $table.argsJson, builder: (column) => column);

  GeneratedColumn<String> get risk =>
      $composableBuilder(column: $table.risk, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get beforeJson => $composableBuilder(
      column: $table.beforeJson, builder: (column) => column);

  GeneratedColumn<String> get afterJson =>
      $composableBuilder(column: $table.afterJson, builder: (column) => column);

  GeneratedColumn<String> get resultJson => $composableBuilder(
      column: $table.resultJson, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AiActionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AiActionsTable,
    AiAction,
    $$AiActionsTableFilterComposer,
    $$AiActionsTableOrderingComposer,
    $$AiActionsTableAnnotationComposer,
    $$AiActionsTableCreateCompanionBuilder,
    $$AiActionsTableUpdateCompanionBuilder,
    (AiAction, BaseReferences<_$AppDatabase, $AiActionsTable, AiAction>),
    AiAction,
    PrefetchHooks Function()> {
  $$AiActionsTableTableManager(_$AppDatabase db, $AiActionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiActionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiActionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiActionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> messageId = const Value.absent(),
            Value<String> conversationId = const Value.absent(),
            Value<String?> toolCallId = const Value.absent(),
            Value<String> toolName = const Value.absent(),
            Value<String> argsJson = const Value.absent(),
            Value<String> risk = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> beforeJson = const Value.absent(),
            Value<String?> afterJson = const Value.absent(),
            Value<String?> resultJson = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AiActionsCompanion(
            id: id,
            messageId: messageId,
            conversationId: conversationId,
            toolCallId: toolCallId,
            toolName: toolName,
            argsJson: argsJson,
            risk: risk,
            status: status,
            beforeJson: beforeJson,
            afterJson: afterJson,
            resultJson: resultJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> messageId = const Value.absent(),
            required String conversationId,
            Value<String?> toolCallId = const Value.absent(),
            required String toolName,
            required String argsJson,
            required String risk,
            required String status,
            Value<String?> beforeJson = const Value.absent(),
            Value<String?> afterJson = const Value.absent(),
            Value<String?> resultJson = const Value.absent(),
            required int createdAt,
            Value<int?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AiActionsCompanion.insert(
            id: id,
            messageId: messageId,
            conversationId: conversationId,
            toolCallId: toolCallId,
            toolName: toolName,
            argsJson: argsJson,
            risk: risk,
            status: status,
            beforeJson: beforeJson,
            afterJson: afterJson,
            resultJson: resultJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AiActionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AiActionsTable,
    AiAction,
    $$AiActionsTableFilterComposer,
    $$AiActionsTableOrderingComposer,
    $$AiActionsTableAnnotationComposer,
    $$AiActionsTableCreateCompanionBuilder,
    $$AiActionsTableUpdateCompanionBuilder,
    (AiAction, BaseReferences<_$AppDatabase, $AiActionsTable, AiAction>),
    AiAction,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$LocalSettingsTableTableManager get localSettings =>
      $$LocalSettingsTableTableManager(_db, _db.localSettings);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$ObjectTagsTableTableManager get objectTags =>
      $$ObjectTagsTableTableManager(_db, _db.objectTags);
  $$MindMapsTableTableManager get mindMaps =>
      $$MindMapsTableTableManager(_db, _db.mindMaps);
  $$MindNodesTableTableManager get mindNodes =>
      $$MindNodesTableTableManager(_db, _db.mindNodes);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$TaskDependenciesTableTableManager get taskDependencies =>
      $$TaskDependenciesTableTableManager(_db, _db.taskDependencies);
  $$TimeBlocksTableTableManager get timeBlocks =>
      $$TimeBlocksTableTableManager(_db, _db.timeBlocks);
  $$TaskTimeBlocksTableTableManager get taskTimeBlocks =>
      $$TaskTimeBlocksTableTableManager(_db, _db.taskTimeBlocks);
  $$KnowledgePointsTableTableManager get knowledgePoints =>
      $$KnowledgePointsTableTableManager(_db, _db.knowledgePoints);
  $$CardTemplatesTableTableManager get cardTemplates =>
      $$CardTemplatesTableTableManager(_db, _db.cardTemplates);
  $$CardStatesTableTableManager get cardStates =>
      $$CardStatesTableTableManager(_db, _db.cardStates);
  $$ReviewLogsTableTableManager get reviewLogs =>
      $$ReviewLogsTableTableManager(_db, _db.reviewLogs);
  $$KnowledgePackagesTableTableManager get knowledgePackages =>
      $$KnowledgePackagesTableTableManager(_db, _db.knowledgePackages);
  $$PackageItemsTableTableManager get packageItems =>
      $$PackageItemsTableTableManager(_db, _db.packageItems);
  $$ThreadStatesTableTableManager get threadStates =>
      $$ThreadStatesTableTableManager(_db, _db.threadStates);
  $$TaskTemplatesTableTableManager get taskTemplates =>
      $$TaskTemplatesTableTableManager(_db, _db.taskTemplates);
  $$CompletionLogsTableTableManager get completionLogs =>
      $$CompletionLogsTableTableManager(_db, _db.completionLogs);
  $$ClozeSlotsTableTableManager get clozeSlots =>
      $$ClozeSlotsTableTableManager(_db, _db.clozeSlots);
  $$ClozeHistoryTableTableManager get clozeHistory =>
      $$ClozeHistoryTableTableManager(_db, _db.clozeHistory);
  $$BoostEntriesTableTableManager get boostEntries =>
      $$BoostEntriesTableTableManager(_db, _db.boostEntries);
  $$ThemesTableTableManager get themes =>
      $$ThemesTableTableManager(_db, _db.themes);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db, _db.attachments);
  $$ThreadRankSettingsTableTableManager get threadRankSettings =>
      $$ThreadRankSettingsTableTableManager(_db, _db.threadRankSettings);
  $$DiffusionLogsTableTableManager get diffusionLogs =>
      $$DiffusionLogsTableTableManager(_db, _db.diffusionLogs);
  $$TimeTemplatesTableTableManager get timeTemplates =>
      $$TimeTemplatesTableTableManager(_db, _db.timeTemplates);
  $$TimeViewSettingsTableTableManager get timeViewSettings =>
      $$TimeViewSettingsTableTableManager(_db, _db.timeViewSettings);
  $$AiConversationsTableTableManager get aiConversations =>
      $$AiConversationsTableTableManager(_db, _db.aiConversations);
  $$AiMessagesTableTableManager get aiMessages =>
      $$AiMessagesTableTableManager(_db, _db.aiMessages);
  $$AiActionsTableTableManager get aiActions =>
      $$AiActionsTableTableManager(_db, _db.aiActions);
}
