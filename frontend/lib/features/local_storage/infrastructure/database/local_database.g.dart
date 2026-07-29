// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $AccountSessionsTable extends AccountSessions
    with TableInfo<$AccountSessionsTable, AccountSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonIdMeta = const VerificationMeta(
    'singletonId',
  );
  @override
  late final GeneratedColumn<int> singletonId = GeneratedColumn<int>(
    'singleton_id',
    aliasedName,
    false,
    check: () => singletonId.equals(1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _userIdCiphertextMeta = const VerificationMeta(
    'userIdCiphertext',
  );
  @override
  late final GeneratedColumn<Uint8List> userIdCiphertext =
      GeneratedColumn<Uint8List>(
        'user_id_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _deviceIdCiphertextMeta =
      const VerificationMeta('deviceIdCiphertext');
  @override
  late final GeneratedColumn<Uint8List> deviceIdCiphertext =
      GeneratedColumn<Uint8List>(
        'device_id_ciphertext',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<int> scope = GeneratedColumn<int>(
    'scope',
    aliasedName,
    false,
    check: () => ComparableExpr(scope).isBetweenValues(0, 1),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenMetadataCiphertextMeta =
      const VerificationMeta('tokenMetadataCiphertext');
  @override
  late final GeneratedColumn<Uint8List> tokenMetadataCiphertext =
      GeneratedColumn<Uint8List>(
        'token_metadata_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _serverProfileCiphertextMeta =
      const VerificationMeta('serverProfileCiphertext');
  @override
  late final GeneratedColumn<Uint8List> serverProfileCiphertext =
      GeneratedColumn<Uint8List>(
        'server_profile_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    singletonId,
    userIdCiphertext,
    deviceIdCiphertext,
    scope,
    tokenMetadataCiphertext,
    serverProfileCiphertext,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'account_session';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton_id')) {
      context.handle(
        _singletonIdMeta,
        singletonId.isAcceptableOrUnknown(
          data['singleton_id']!,
          _singletonIdMeta,
        ),
      );
    }
    if (data.containsKey('user_id_ciphertext')) {
      context.handle(
        _userIdCiphertextMeta,
        userIdCiphertext.isAcceptableOrUnknown(
          data['user_id_ciphertext']!,
          _userIdCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_userIdCiphertextMeta);
    }
    if (data.containsKey('device_id_ciphertext')) {
      context.handle(
        _deviceIdCiphertextMeta,
        deviceIdCiphertext.isAcceptableOrUnknown(
          data['device_id_ciphertext']!,
          _deviceIdCiphertextMeta,
        ),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('token_metadata_ciphertext')) {
      context.handle(
        _tokenMetadataCiphertextMeta,
        tokenMetadataCiphertext.isAcceptableOrUnknown(
          data['token_metadata_ciphertext']!,
          _tokenMetadataCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tokenMetadataCiphertextMeta);
    }
    if (data.containsKey('server_profile_ciphertext')) {
      context.handle(
        _serverProfileCiphertextMeta,
        serverProfileCiphertext.isAcceptableOrUnknown(
          data['server_profile_ciphertext']!,
          _serverProfileCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverProfileCiphertextMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singletonId};
  @override
  AccountSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountSession(
      singletonId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton_id'],
      )!,
      userIdCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}user_id_ciphertext'],
      )!,
      deviceIdCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}device_id_ciphertext'],
      ),
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scope'],
      )!,
      tokenMetadataCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}token_metadata_ciphertext'],
      )!,
      serverProfileCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}server_profile_ciphertext'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
    );
  }

  @override
  $AccountSessionsTable createAlias(String alias) {
    return $AccountSessionsTable(attachedDatabase, alias);
  }
}

class AccountSession extends DataClass implements Insertable<AccountSession> {
  final int singletonId;
  final Uint8List userIdCiphertext;
  final Uint8List? deviceIdCiphertext;
  final int scope;
  final Uint8List tokenMetadataCiphertext;
  final Uint8List serverProfileCiphertext;
  final DateTime? expiresAt;
  const AccountSession({
    required this.singletonId,
    required this.userIdCiphertext,
    this.deviceIdCiphertext,
    required this.scope,
    required this.tokenMetadataCiphertext,
    required this.serverProfileCiphertext,
    this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton_id'] = Variable<int>(singletonId);
    map['user_id_ciphertext'] = Variable<Uint8List>(userIdCiphertext);
    if (!nullToAbsent || deviceIdCiphertext != null) {
      map['device_id_ciphertext'] = Variable<Uint8List>(deviceIdCiphertext);
    }
    map['scope'] = Variable<int>(scope);
    map['token_metadata_ciphertext'] = Variable<Uint8List>(
      tokenMetadataCiphertext,
    );
    map['server_profile_ciphertext'] = Variable<Uint8List>(
      serverProfileCiphertext,
    );
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    return map;
  }

  AccountSessionsCompanion toCompanion(bool nullToAbsent) {
    return AccountSessionsCompanion(
      singletonId: Value(singletonId),
      userIdCiphertext: Value(userIdCiphertext),
      deviceIdCiphertext: deviceIdCiphertext == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceIdCiphertext),
      scope: Value(scope),
      tokenMetadataCiphertext: Value(tokenMetadataCiphertext),
      serverProfileCiphertext: Value(serverProfileCiphertext),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
    );
  }

  factory AccountSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountSession(
      singletonId: serializer.fromJson<int>(json['singletonId']),
      userIdCiphertext: serializer.fromJson<Uint8List>(
        json['userIdCiphertext'],
      ),
      deviceIdCiphertext: serializer.fromJson<Uint8List?>(
        json['deviceIdCiphertext'],
      ),
      scope: serializer.fromJson<int>(json['scope']),
      tokenMetadataCiphertext: serializer.fromJson<Uint8List>(
        json['tokenMetadataCiphertext'],
      ),
      serverProfileCiphertext: serializer.fromJson<Uint8List>(
        json['serverProfileCiphertext'],
      ),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singletonId': serializer.toJson<int>(singletonId),
      'userIdCiphertext': serializer.toJson<Uint8List>(userIdCiphertext),
      'deviceIdCiphertext': serializer.toJson<Uint8List?>(deviceIdCiphertext),
      'scope': serializer.toJson<int>(scope),
      'tokenMetadataCiphertext': serializer.toJson<Uint8List>(
        tokenMetadataCiphertext,
      ),
      'serverProfileCiphertext': serializer.toJson<Uint8List>(
        serverProfileCiphertext,
      ),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
    };
  }

  AccountSession copyWith({
    int? singletonId,
    Uint8List? userIdCiphertext,
    Value<Uint8List?> deviceIdCiphertext = const Value.absent(),
    int? scope,
    Uint8List? tokenMetadataCiphertext,
    Uint8List? serverProfileCiphertext,
    Value<DateTime?> expiresAt = const Value.absent(),
  }) => AccountSession(
    singletonId: singletonId ?? this.singletonId,
    userIdCiphertext: userIdCiphertext ?? this.userIdCiphertext,
    deviceIdCiphertext: deviceIdCiphertext.present
        ? deviceIdCiphertext.value
        : this.deviceIdCiphertext,
    scope: scope ?? this.scope,
    tokenMetadataCiphertext:
        tokenMetadataCiphertext ?? this.tokenMetadataCiphertext,
    serverProfileCiphertext:
        serverProfileCiphertext ?? this.serverProfileCiphertext,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
  );
  AccountSession copyWithCompanion(AccountSessionsCompanion data) {
    return AccountSession(
      singletonId: data.singletonId.present
          ? data.singletonId.value
          : this.singletonId,
      userIdCiphertext: data.userIdCiphertext.present
          ? data.userIdCiphertext.value
          : this.userIdCiphertext,
      deviceIdCiphertext: data.deviceIdCiphertext.present
          ? data.deviceIdCiphertext.value
          : this.deviceIdCiphertext,
      scope: data.scope.present ? data.scope.value : this.scope,
      tokenMetadataCiphertext: data.tokenMetadataCiphertext.present
          ? data.tokenMetadataCiphertext.value
          : this.tokenMetadataCiphertext,
      serverProfileCiphertext: data.serverProfileCiphertext.present
          ? data.serverProfileCiphertext.value
          : this.serverProfileCiphertext,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountSession(')
          ..write('singletonId: $singletonId, ')
          ..write('userIdCiphertext: $userIdCiphertext, ')
          ..write('deviceIdCiphertext: $deviceIdCiphertext, ')
          ..write('scope: $scope, ')
          ..write('tokenMetadataCiphertext: $tokenMetadataCiphertext, ')
          ..write('serverProfileCiphertext: $serverProfileCiphertext, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    singletonId,
    $driftBlobEquality.hash(userIdCiphertext),
    $driftBlobEquality.hash(deviceIdCiphertext),
    scope,
    $driftBlobEquality.hash(tokenMetadataCiphertext),
    $driftBlobEquality.hash(serverProfileCiphertext),
    expiresAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountSession &&
          other.singletonId == this.singletonId &&
          $driftBlobEquality.equals(
            other.userIdCiphertext,
            this.userIdCiphertext,
          ) &&
          $driftBlobEquality.equals(
            other.deviceIdCiphertext,
            this.deviceIdCiphertext,
          ) &&
          other.scope == this.scope &&
          $driftBlobEquality.equals(
            other.tokenMetadataCiphertext,
            this.tokenMetadataCiphertext,
          ) &&
          $driftBlobEquality.equals(
            other.serverProfileCiphertext,
            this.serverProfileCiphertext,
          ) &&
          other.expiresAt == this.expiresAt);
}

class AccountSessionsCompanion extends UpdateCompanion<AccountSession> {
  final Value<int> singletonId;
  final Value<Uint8List> userIdCiphertext;
  final Value<Uint8List?> deviceIdCiphertext;
  final Value<int> scope;
  final Value<Uint8List> tokenMetadataCiphertext;
  final Value<Uint8List> serverProfileCiphertext;
  final Value<DateTime?> expiresAt;
  const AccountSessionsCompanion({
    this.singletonId = const Value.absent(),
    this.userIdCiphertext = const Value.absent(),
    this.deviceIdCiphertext = const Value.absent(),
    this.scope = const Value.absent(),
    this.tokenMetadataCiphertext = const Value.absent(),
    this.serverProfileCiphertext = const Value.absent(),
    this.expiresAt = const Value.absent(),
  });
  AccountSessionsCompanion.insert({
    this.singletonId = const Value.absent(),
    required Uint8List userIdCiphertext,
    this.deviceIdCiphertext = const Value.absent(),
    required int scope,
    required Uint8List tokenMetadataCiphertext,
    required Uint8List serverProfileCiphertext,
    this.expiresAt = const Value.absent(),
  }) : userIdCiphertext = Value(userIdCiphertext),
       scope = Value(scope),
       tokenMetadataCiphertext = Value(tokenMetadataCiphertext),
       serverProfileCiphertext = Value(serverProfileCiphertext);
  static Insertable<AccountSession> custom({
    Expression<int>? singletonId,
    Expression<Uint8List>? userIdCiphertext,
    Expression<Uint8List>? deviceIdCiphertext,
    Expression<int>? scope,
    Expression<Uint8List>? tokenMetadataCiphertext,
    Expression<Uint8List>? serverProfileCiphertext,
    Expression<DateTime>? expiresAt,
  }) {
    return RawValuesInsertable({
      if (singletonId != null) 'singleton_id': singletonId,
      if (userIdCiphertext != null) 'user_id_ciphertext': userIdCiphertext,
      if (deviceIdCiphertext != null)
        'device_id_ciphertext': deviceIdCiphertext,
      if (scope != null) 'scope': scope,
      if (tokenMetadataCiphertext != null)
        'token_metadata_ciphertext': tokenMetadataCiphertext,
      if (serverProfileCiphertext != null)
        'server_profile_ciphertext': serverProfileCiphertext,
      if (expiresAt != null) 'expires_at': expiresAt,
    });
  }

  AccountSessionsCompanion copyWith({
    Value<int>? singletonId,
    Value<Uint8List>? userIdCiphertext,
    Value<Uint8List?>? deviceIdCiphertext,
    Value<int>? scope,
    Value<Uint8List>? tokenMetadataCiphertext,
    Value<Uint8List>? serverProfileCiphertext,
    Value<DateTime?>? expiresAt,
  }) {
    return AccountSessionsCompanion(
      singletonId: singletonId ?? this.singletonId,
      userIdCiphertext: userIdCiphertext ?? this.userIdCiphertext,
      deviceIdCiphertext: deviceIdCiphertext ?? this.deviceIdCiphertext,
      scope: scope ?? this.scope,
      tokenMetadataCiphertext:
          tokenMetadataCiphertext ?? this.tokenMetadataCiphertext,
      serverProfileCiphertext:
          serverProfileCiphertext ?? this.serverProfileCiphertext,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singletonId.present) {
      map['singleton_id'] = Variable<int>(singletonId.value);
    }
    if (userIdCiphertext.present) {
      map['user_id_ciphertext'] = Variable<Uint8List>(userIdCiphertext.value);
    }
    if (deviceIdCiphertext.present) {
      map['device_id_ciphertext'] = Variable<Uint8List>(
        deviceIdCiphertext.value,
      );
    }
    if (scope.present) {
      map['scope'] = Variable<int>(scope.value);
    }
    if (tokenMetadataCiphertext.present) {
      map['token_metadata_ciphertext'] = Variable<Uint8List>(
        tokenMetadataCiphertext.value,
      );
    }
    if (serverProfileCiphertext.present) {
      map['server_profile_ciphertext'] = Variable<Uint8List>(
        serverProfileCiphertext.value,
      );
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountSessionsCompanion(')
          ..write('singletonId: $singletonId, ')
          ..write('userIdCiphertext: $userIdCiphertext, ')
          ..write('deviceIdCiphertext: $deviceIdCiphertext, ')
          ..write('scope: $scope, ')
          ..write('tokenMetadataCiphertext: $tokenMetadataCiphertext, ')
          ..write('serverProfileCiphertext: $serverProfileCiphertext, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }
}

class $SecureSecretsTable extends SecureSecrets
    with TableInfo<$SecureSecretsTable, SecureSecret> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SecureSecretsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _secretIdMeta = const VerificationMeta(
    'secretId',
  );
  @override
  late final GeneratedColumn<String> secretId = GeneratedColumn<String>(
    'secret_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
    'kind',
    aliasedName,
    false,
    check: () => ComparableExpr(kind).isBetweenValues(0, 31),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wrappedCiphertextOrOpaqueHandleMeta =
      const VerificationMeta('wrappedCiphertextOrOpaqueHandle');
  @override
  late final GeneratedColumn<Uint8List> wrappedCiphertextOrOpaqueHandle =
      GeneratedColumn<Uint8List>(
        'wrapped_ciphertext_or_opaque_handle',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _formatVersionMeta = const VerificationMeta(
    'formatVersion',
  );
  @override
  late final GeneratedColumn<int> formatVersion = GeneratedColumn<int>(
    'format_version',
    aliasedName,
    false,
    check: () => ComparableExpr(formatVersion).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    secretId,
    kind,
    wrappedCiphertextOrOpaqueHandle,
    formatVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'secure_secrets';
  @override
  VerificationContext validateIntegrity(
    Insertable<SecureSecret> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('secret_id')) {
      context.handle(
        _secretIdMeta,
        secretId.isAcceptableOrUnknown(data['secret_id']!, _secretIdMeta),
      );
    } else if (isInserting) {
      context.missing(_secretIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('wrapped_ciphertext_or_opaque_handle')) {
      context.handle(
        _wrappedCiphertextOrOpaqueHandleMeta,
        wrappedCiphertextOrOpaqueHandle.isAcceptableOrUnknown(
          data['wrapped_ciphertext_or_opaque_handle']!,
          _wrappedCiphertextOrOpaqueHandleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_wrappedCiphertextOrOpaqueHandleMeta);
    }
    if (data.containsKey('format_version')) {
      context.handle(
        _formatVersionMeta,
        formatVersion.isAcceptableOrUnknown(
          data['format_version']!,
          _formatVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_formatVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {secretId};
  @override
  SecureSecret map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SecureSecret(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      secretId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secret_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kind'],
      )!,
      wrappedCiphertextOrOpaqueHandle: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}wrapped_ciphertext_or_opaque_handle'],
      )!,
      formatVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}format_version'],
      )!,
    );
  }

  @override
  $SecureSecretsTable createAlias(String alias) {
    return $SecureSecretsTable(attachedDatabase, alias);
  }
}

class SecureSecret extends DataClass implements Insertable<SecureSecret> {
  final DateTime createdAt;
  final String secretId;
  final int kind;
  final Uint8List wrappedCiphertextOrOpaqueHandle;
  final int formatVersion;
  const SecureSecret({
    required this.createdAt,
    required this.secretId,
    required this.kind,
    required this.wrappedCiphertextOrOpaqueHandle,
    required this.formatVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<DateTime>(createdAt);
    map['secret_id'] = Variable<String>(secretId);
    map['kind'] = Variable<int>(kind);
    map['wrapped_ciphertext_or_opaque_handle'] = Variable<Uint8List>(
      wrappedCiphertextOrOpaqueHandle,
    );
    map['format_version'] = Variable<int>(formatVersion);
    return map;
  }

  SecureSecretsCompanion toCompanion(bool nullToAbsent) {
    return SecureSecretsCompanion(
      createdAt: Value(createdAt),
      secretId: Value(secretId),
      kind: Value(kind),
      wrappedCiphertextOrOpaqueHandle: Value(wrappedCiphertextOrOpaqueHandle),
      formatVersion: Value(formatVersion),
    );
  }

  factory SecureSecret.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SecureSecret(
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      secretId: serializer.fromJson<String>(json['secretId']),
      kind: serializer.fromJson<int>(json['kind']),
      wrappedCiphertextOrOpaqueHandle: serializer.fromJson<Uint8List>(
        json['wrappedCiphertextOrOpaqueHandle'],
      ),
      formatVersion: serializer.fromJson<int>(json['formatVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'secretId': serializer.toJson<String>(secretId),
      'kind': serializer.toJson<int>(kind),
      'wrappedCiphertextOrOpaqueHandle': serializer.toJson<Uint8List>(
        wrappedCiphertextOrOpaqueHandle,
      ),
      'formatVersion': serializer.toJson<int>(formatVersion),
    };
  }

  SecureSecret copyWith({
    DateTime? createdAt,
    String? secretId,
    int? kind,
    Uint8List? wrappedCiphertextOrOpaqueHandle,
    int? formatVersion,
  }) => SecureSecret(
    createdAt: createdAt ?? this.createdAt,
    secretId: secretId ?? this.secretId,
    kind: kind ?? this.kind,
    wrappedCiphertextOrOpaqueHandle:
        wrappedCiphertextOrOpaqueHandle ?? this.wrappedCiphertextOrOpaqueHandle,
    formatVersion: formatVersion ?? this.formatVersion,
  );
  SecureSecret copyWithCompanion(SecureSecretsCompanion data) {
    return SecureSecret(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      secretId: data.secretId.present ? data.secretId.value : this.secretId,
      kind: data.kind.present ? data.kind.value : this.kind,
      wrappedCiphertextOrOpaqueHandle:
          data.wrappedCiphertextOrOpaqueHandle.present
          ? data.wrappedCiphertextOrOpaqueHandle.value
          : this.wrappedCiphertextOrOpaqueHandle,
      formatVersion: data.formatVersion.present
          ? data.formatVersion.value
          : this.formatVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SecureSecret(')
          ..write('createdAt: $createdAt, ')
          ..write('secretId: $secretId, ')
          ..write('kind: $kind, ')
          ..write(
            'wrappedCiphertextOrOpaqueHandle: $wrappedCiphertextOrOpaqueHandle, ',
          )
          ..write('formatVersion: $formatVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    secretId,
    kind,
    $driftBlobEquality.hash(wrappedCiphertextOrOpaqueHandle),
    formatVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SecureSecret &&
          other.createdAt == this.createdAt &&
          other.secretId == this.secretId &&
          other.kind == this.kind &&
          $driftBlobEquality.equals(
            other.wrappedCiphertextOrOpaqueHandle,
            this.wrappedCiphertextOrOpaqueHandle,
          ) &&
          other.formatVersion == this.formatVersion);
}

class SecureSecretsCompanion extends UpdateCompanion<SecureSecret> {
  final Value<DateTime> createdAt;
  final Value<String> secretId;
  final Value<int> kind;
  final Value<Uint8List> wrappedCiphertextOrOpaqueHandle;
  final Value<int> formatVersion;
  final Value<int> rowid;
  const SecureSecretsCompanion({
    this.createdAt = const Value.absent(),
    this.secretId = const Value.absent(),
    this.kind = const Value.absent(),
    this.wrappedCiphertextOrOpaqueHandle = const Value.absent(),
    this.formatVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SecureSecretsCompanion.insert({
    this.createdAt = const Value.absent(),
    required String secretId,
    required int kind,
    required Uint8List wrappedCiphertextOrOpaqueHandle,
    required int formatVersion,
    this.rowid = const Value.absent(),
  }) : secretId = Value(secretId),
       kind = Value(kind),
       wrappedCiphertextOrOpaqueHandle = Value(wrappedCiphertextOrOpaqueHandle),
       formatVersion = Value(formatVersion);
  static Insertable<SecureSecret> custom({
    Expression<DateTime>? createdAt,
    Expression<String>? secretId,
    Expression<int>? kind,
    Expression<Uint8List>? wrappedCiphertextOrOpaqueHandle,
    Expression<int>? formatVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (secretId != null) 'secret_id': secretId,
      if (kind != null) 'kind': kind,
      if (wrappedCiphertextOrOpaqueHandle != null)
        'wrapped_ciphertext_or_opaque_handle': wrappedCiphertextOrOpaqueHandle,
      if (formatVersion != null) 'format_version': formatVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SecureSecretsCompanion copyWith({
    Value<DateTime>? createdAt,
    Value<String>? secretId,
    Value<int>? kind,
    Value<Uint8List>? wrappedCiphertextOrOpaqueHandle,
    Value<int>? formatVersion,
    Value<int>? rowid,
  }) {
    return SecureSecretsCompanion(
      createdAt: createdAt ?? this.createdAt,
      secretId: secretId ?? this.secretId,
      kind: kind ?? this.kind,
      wrappedCiphertextOrOpaqueHandle:
          wrappedCiphertextOrOpaqueHandle ??
          this.wrappedCiphertextOrOpaqueHandle,
      formatVersion: formatVersion ?? this.formatVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (secretId.present) {
      map['secret_id'] = Variable<String>(secretId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (wrappedCiphertextOrOpaqueHandle.present) {
      map['wrapped_ciphertext_or_opaque_handle'] = Variable<Uint8List>(
        wrappedCiphertextOrOpaqueHandle.value,
      );
    }
    if (formatVersion.present) {
      map['format_version'] = Variable<int>(formatVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SecureSecretsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('secretId: $secretId, ')
          ..write('kind: $kind, ')
          ..write(
            'wrappedCiphertextOrOpaqueHandle: $wrappedCiphertextOrOpaqueHandle, ',
          )
          ..write('formatVersion: $formatVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountIdentitiesTable extends AccountIdentities
    with TableInfo<$AccountIdentitiesTable, AccountIdentity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountIdentitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonIdMeta = const VerificationMeta(
    'singletonId',
  );
  @override
  late final GeneratedColumn<int> singletonId = GeneratedColumn<int>(
    'singleton_id',
    aliasedName,
    false,
    check: () => singletonId.equals(1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _verifiedPublicStateCiphertextMeta =
      const VerificationMeta('verifiedPublicStateCiphertext');
  @override
  late final GeneratedColumn<Uint8List> verifiedPublicStateCiphertext =
      GeneratedColumn<Uint8List>(
        'verified_public_state_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _backupVersionMeta = const VerificationMeta(
    'backupVersion',
  );
  @override
  late final GeneratedColumn<int> backupVersion = GeneratedColumn<int>(
    'backup_version',
    aliasedName,
    false,
    check: () => ComparableExpr(backupVersion).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _recoveryStatusMeta = const VerificationMeta(
    'recoveryStatus',
  );
  @override
  late final GeneratedColumn<int> recoveryStatus = GeneratedColumn<int>(
    'recovery_status',
    aliasedName,
    false,
    check: () => ComparableExpr(recoveryStatus).isBetweenValues(0, 4),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    singletonId,
    verifiedPublicStateCiphertext,
    backupVersion,
    recoveryStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'account_identity';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountIdentity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton_id')) {
      context.handle(
        _singletonIdMeta,
        singletonId.isAcceptableOrUnknown(
          data['singleton_id']!,
          _singletonIdMeta,
        ),
      );
    }
    if (data.containsKey('verified_public_state_ciphertext')) {
      context.handle(
        _verifiedPublicStateCiphertextMeta,
        verifiedPublicStateCiphertext.isAcceptableOrUnknown(
          data['verified_public_state_ciphertext']!,
          _verifiedPublicStateCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_verifiedPublicStateCiphertextMeta);
    }
    if (data.containsKey('backup_version')) {
      context.handle(
        _backupVersionMeta,
        backupVersion.isAcceptableOrUnknown(
          data['backup_version']!,
          _backupVersionMeta,
        ),
      );
    }
    if (data.containsKey('recovery_status')) {
      context.handle(
        _recoveryStatusMeta,
        recoveryStatus.isAcceptableOrUnknown(
          data['recovery_status']!,
          _recoveryStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recoveryStatusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singletonId};
  @override
  AccountIdentity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountIdentity(
      singletonId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton_id'],
      )!,
      verifiedPublicStateCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}verified_public_state_ciphertext'],
      )!,
      backupVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}backup_version'],
      )!,
      recoveryStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recovery_status'],
      )!,
    );
  }

  @override
  $AccountIdentitiesTable createAlias(String alias) {
    return $AccountIdentitiesTable(attachedDatabase, alias);
  }
}

class AccountIdentity extends DataClass implements Insertable<AccountIdentity> {
  final int singletonId;
  final Uint8List verifiedPublicStateCiphertext;
  final int backupVersion;
  final int recoveryStatus;
  const AccountIdentity({
    required this.singletonId,
    required this.verifiedPublicStateCiphertext,
    required this.backupVersion,
    required this.recoveryStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton_id'] = Variable<int>(singletonId);
    map['verified_public_state_ciphertext'] = Variable<Uint8List>(
      verifiedPublicStateCiphertext,
    );
    map['backup_version'] = Variable<int>(backupVersion);
    map['recovery_status'] = Variable<int>(recoveryStatus);
    return map;
  }

  AccountIdentitiesCompanion toCompanion(bool nullToAbsent) {
    return AccountIdentitiesCompanion(
      singletonId: Value(singletonId),
      verifiedPublicStateCiphertext: Value(verifiedPublicStateCiphertext),
      backupVersion: Value(backupVersion),
      recoveryStatus: Value(recoveryStatus),
    );
  }

  factory AccountIdentity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountIdentity(
      singletonId: serializer.fromJson<int>(json['singletonId']),
      verifiedPublicStateCiphertext: serializer.fromJson<Uint8List>(
        json['verifiedPublicStateCiphertext'],
      ),
      backupVersion: serializer.fromJson<int>(json['backupVersion']),
      recoveryStatus: serializer.fromJson<int>(json['recoveryStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singletonId': serializer.toJson<int>(singletonId),
      'verifiedPublicStateCiphertext': serializer.toJson<Uint8List>(
        verifiedPublicStateCiphertext,
      ),
      'backupVersion': serializer.toJson<int>(backupVersion),
      'recoveryStatus': serializer.toJson<int>(recoveryStatus),
    };
  }

  AccountIdentity copyWith({
    int? singletonId,
    Uint8List? verifiedPublicStateCiphertext,
    int? backupVersion,
    int? recoveryStatus,
  }) => AccountIdentity(
    singletonId: singletonId ?? this.singletonId,
    verifiedPublicStateCiphertext:
        verifiedPublicStateCiphertext ?? this.verifiedPublicStateCiphertext,
    backupVersion: backupVersion ?? this.backupVersion,
    recoveryStatus: recoveryStatus ?? this.recoveryStatus,
  );
  AccountIdentity copyWithCompanion(AccountIdentitiesCompanion data) {
    return AccountIdentity(
      singletonId: data.singletonId.present
          ? data.singletonId.value
          : this.singletonId,
      verifiedPublicStateCiphertext: data.verifiedPublicStateCiphertext.present
          ? data.verifiedPublicStateCiphertext.value
          : this.verifiedPublicStateCiphertext,
      backupVersion: data.backupVersion.present
          ? data.backupVersion.value
          : this.backupVersion,
      recoveryStatus: data.recoveryStatus.present
          ? data.recoveryStatus.value
          : this.recoveryStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountIdentity(')
          ..write('singletonId: $singletonId, ')
          ..write(
            'verifiedPublicStateCiphertext: $verifiedPublicStateCiphertext, ',
          )
          ..write('backupVersion: $backupVersion, ')
          ..write('recoveryStatus: $recoveryStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    singletonId,
    $driftBlobEquality.hash(verifiedPublicStateCiphertext),
    backupVersion,
    recoveryStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountIdentity &&
          other.singletonId == this.singletonId &&
          $driftBlobEquality.equals(
            other.verifiedPublicStateCiphertext,
            this.verifiedPublicStateCiphertext,
          ) &&
          other.backupVersion == this.backupVersion &&
          other.recoveryStatus == this.recoveryStatus);
}

class AccountIdentitiesCompanion extends UpdateCompanion<AccountIdentity> {
  final Value<int> singletonId;
  final Value<Uint8List> verifiedPublicStateCiphertext;
  final Value<int> backupVersion;
  final Value<int> recoveryStatus;
  const AccountIdentitiesCompanion({
    this.singletonId = const Value.absent(),
    this.verifiedPublicStateCiphertext = const Value.absent(),
    this.backupVersion = const Value.absent(),
    this.recoveryStatus = const Value.absent(),
  });
  AccountIdentitiesCompanion.insert({
    this.singletonId = const Value.absent(),
    required Uint8List verifiedPublicStateCiphertext,
    this.backupVersion = const Value.absent(),
    required int recoveryStatus,
  }) : verifiedPublicStateCiphertext = Value(verifiedPublicStateCiphertext),
       recoveryStatus = Value(recoveryStatus);
  static Insertable<AccountIdentity> custom({
    Expression<int>? singletonId,
    Expression<Uint8List>? verifiedPublicStateCiphertext,
    Expression<int>? backupVersion,
    Expression<int>? recoveryStatus,
  }) {
    return RawValuesInsertable({
      if (singletonId != null) 'singleton_id': singletonId,
      if (verifiedPublicStateCiphertext != null)
        'verified_public_state_ciphertext': verifiedPublicStateCiphertext,
      if (backupVersion != null) 'backup_version': backupVersion,
      if (recoveryStatus != null) 'recovery_status': recoveryStatus,
    });
  }

  AccountIdentitiesCompanion copyWith({
    Value<int>? singletonId,
    Value<Uint8List>? verifiedPublicStateCiphertext,
    Value<int>? backupVersion,
    Value<int>? recoveryStatus,
  }) {
    return AccountIdentitiesCompanion(
      singletonId: singletonId ?? this.singletonId,
      verifiedPublicStateCiphertext:
          verifiedPublicStateCiphertext ?? this.verifiedPublicStateCiphertext,
      backupVersion: backupVersion ?? this.backupVersion,
      recoveryStatus: recoveryStatus ?? this.recoveryStatus,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singletonId.present) {
      map['singleton_id'] = Variable<int>(singletonId.value);
    }
    if (verifiedPublicStateCiphertext.present) {
      map['verified_public_state_ciphertext'] = Variable<Uint8List>(
        verifiedPublicStateCiphertext.value,
      );
    }
    if (backupVersion.present) {
      map['backup_version'] = Variable<int>(backupVersion.value);
    }
    if (recoveryStatus.present) {
      map['recovery_status'] = Variable<int>(recoveryStatus.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountIdentitiesCompanion(')
          ..write('singletonId: $singletonId, ')
          ..write(
            'verifiedPublicStateCiphertext: $verifiedPublicStateCiphertext, ',
          )
          ..write('backupVersion: $backupVersion, ')
          ..write('recoveryStatus: $recoveryStatus')
          ..write(')'))
        .toString();
  }
}

class $EnrollmentIntentsTable extends EnrollmentIntents
    with TableInfo<$EnrollmentIntentsTable, EnrollmentIntent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EnrollmentIntentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _flowMeta = const VerificationMeta('flow');
  @override
  late final GeneratedColumn<int> flow = GeneratedColumn<int>(
    'flow',
    aliasedName,
    false,
    check: () => ComparableExpr(flow).isBetweenValues(0, 1),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  @override
  late final GeneratedColumn<int> phase = GeneratedColumn<int>(
    'phase',
    aliasedName,
    false,
    check: () => ComparableExpr(phase).isBetweenValues(0, 17),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<Uint8List> fingerprint =
      GeneratedColumn<Uint8List>(
        'fingerprint',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _deviceStateMeta = const VerificationMeta(
    'deviceState',
  );
  @override
  late final GeneratedColumn<Uint8List> deviceState =
      GeneratedColumn<Uint8List>(
        'device_state',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _identityStateMeta = const VerificationMeta(
    'identityState',
  );
  @override
  late final GeneratedColumn<Uint8List> identityState =
      GeneratedColumn<Uint8List>(
        'identity_state',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _backupMeta = const VerificationMeta('backup');
  @override
  late final GeneratedColumn<Uint8List> backup = GeneratedColumn<Uint8List>(
    'backup',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backupVersionMeta = const VerificationMeta(
    'backupVersion',
  );
  @override
  late final GeneratedColumn<int> backupVersion = GeneratedColumn<int>(
    'backup_version',
    aliasedName,
    false,
    check: () => ComparableExpr(backupVersion).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _identityVersionMeta = const VerificationMeta(
    'identityVersion',
  );
  @override
  late final GeneratedColumn<int> identityVersion = GeneratedColumn<int>(
    'identity_version',
    aliasedName,
    false,
    check: () => ComparableExpr(identityVersion).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _expectedSequenceMeta = const VerificationMeta(
    'expectedSequence',
  );
  @override
  late final GeneratedColumn<int> expectedSequence = GeneratedColumn<int>(
    'expected_sequence',
    aliasedName,
    true,
    check: () =>
        expectedSequence.isNull() |
        ComparableExpr(expectedSequence).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _previousHashMeta = const VerificationMeta(
    'previousHash',
  );
  @override
  late final GeneratedColumn<Uint8List> previousHash =
      GeneratedColumn<Uint8List>(
        'previous_hash',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _pendingLogRecordMeta = const VerificationMeta(
    'pendingLogRecord',
  );
  @override
  late final GeneratedColumn<Uint8List> pendingLogRecord =
      GeneratedColumn<Uint8List>(
        'pending_log_record',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<int> message = GeneratedColumn<int>(
    'message',
    aliasedName,
    true,
    check: () =>
        message.isNull() | ComparableExpr(message).isBetweenValues(0, 14),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recoverySecretDisplayedMeta =
      const VerificationMeta('recoverySecretDisplayed');
  @override
  late final GeneratedColumn<bool> recoverySecretDisplayed =
      GeneratedColumn<bool>(
        'recovery_secret_displayed',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("recovery_secret_displayed" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _recoveryConfirmedMeta = const VerificationMeta(
    'recoveryConfirmed',
  );
  @override
  late final GeneratedColumn<bool> recoveryConfirmed = GeneratedColumn<bool>(
    'recovery_confirmed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("recovery_confirmed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    flow,
    phase,
    fingerprint,
    deviceState,
    deviceId,
    identityState,
    backup,
    backupVersion,
    identityVersion,
    expectedSequence,
    previousHash,
    pendingLogRecord,
    message,
    recoverySecretDisplayed,
    recoveryConfirmed,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'enrollment_intent';
  @override
  VerificationContext validateIntegrity(
    Insertable<EnrollmentIntent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('flow')) {
      context.handle(
        _flowMeta,
        flow.isAcceptableOrUnknown(data['flow']!, _flowMeta),
      );
    } else if (isInserting) {
      context.missing(_flowMeta);
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    } else if (isInserting) {
      context.missing(_phaseMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('device_state')) {
      context.handle(
        _deviceStateMeta,
        deviceState.isAcceptableOrUnknown(
          data['device_state']!,
          _deviceStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deviceStateMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('identity_state')) {
      context.handle(
        _identityStateMeta,
        identityState.isAcceptableOrUnknown(
          data['identity_state']!,
          _identityStateMeta,
        ),
      );
    }
    if (data.containsKey('backup')) {
      context.handle(
        _backupMeta,
        backup.isAcceptableOrUnknown(data['backup']!, _backupMeta),
      );
    }
    if (data.containsKey('backup_version')) {
      context.handle(
        _backupVersionMeta,
        backupVersion.isAcceptableOrUnknown(
          data['backup_version']!,
          _backupVersionMeta,
        ),
      );
    }
    if (data.containsKey('identity_version')) {
      context.handle(
        _identityVersionMeta,
        identityVersion.isAcceptableOrUnknown(
          data['identity_version']!,
          _identityVersionMeta,
        ),
      );
    }
    if (data.containsKey('expected_sequence')) {
      context.handle(
        _expectedSequenceMeta,
        expectedSequence.isAcceptableOrUnknown(
          data['expected_sequence']!,
          _expectedSequenceMeta,
        ),
      );
    }
    if (data.containsKey('previous_hash')) {
      context.handle(
        _previousHashMeta,
        previousHash.isAcceptableOrUnknown(
          data['previous_hash']!,
          _previousHashMeta,
        ),
      );
    }
    if (data.containsKey('pending_log_record')) {
      context.handle(
        _pendingLogRecordMeta,
        pendingLogRecord.isAcceptableOrUnknown(
          data['pending_log_record']!,
          _pendingLogRecordMeta,
        ),
      );
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    if (data.containsKey('recovery_secret_displayed')) {
      context.handle(
        _recoverySecretDisplayedMeta,
        recoverySecretDisplayed.isAcceptableOrUnknown(
          data['recovery_secret_displayed']!,
          _recoverySecretDisplayedMeta,
        ),
      );
    }
    if (data.containsKey('recovery_confirmed')) {
      context.handle(
        _recoveryConfirmedMeta,
        recoveryConfirmed.isAcceptableOrUnknown(
          data['recovery_confirmed']!,
          _recoveryConfirmedMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  EnrollmentIntent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EnrollmentIntent(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      flow: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}flow'],
      )!,
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}phase'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}fingerprint'],
      )!,
      deviceState: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}device_state'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      identityState: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}identity_state'],
      ),
      backup: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}backup'],
      ),
      backupVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}backup_version'],
      )!,
      identityVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}identity_version'],
      )!,
      expectedSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_sequence'],
      ),
      previousHash: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}previous_hash'],
      ),
      pendingLogRecord: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}pending_log_record'],
      ),
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message'],
      ),
      recoverySecretDisplayed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}recovery_secret_displayed'],
      )!,
      recoveryConfirmed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}recovery_confirmed'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EnrollmentIntentsTable createAlias(String alias) {
    return $EnrollmentIntentsTable(attachedDatabase, alias);
  }
}

class EnrollmentIntent extends DataClass
    implements Insertable<EnrollmentIntent> {
  final String userId;
  final int flow;
  final int phase;
  final Uint8List fingerprint;
  final Uint8List deviceState;
  final String? deviceId;
  final Uint8List? identityState;
  final Uint8List? backup;
  final int backupVersion;
  final int identityVersion;
  final int? expectedSequence;
  final Uint8List? previousHash;
  final Uint8List? pendingLogRecord;
  final int? message;
  final bool recoverySecretDisplayed;
  final bool recoveryConfirmed;
  final DateTime updatedAt;
  const EnrollmentIntent({
    required this.userId,
    required this.flow,
    required this.phase,
    required this.fingerprint,
    required this.deviceState,
    this.deviceId,
    this.identityState,
    this.backup,
    required this.backupVersion,
    required this.identityVersion,
    this.expectedSequence,
    this.previousHash,
    this.pendingLogRecord,
    this.message,
    required this.recoverySecretDisplayed,
    required this.recoveryConfirmed,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['flow'] = Variable<int>(flow);
    map['phase'] = Variable<int>(phase);
    map['fingerprint'] = Variable<Uint8List>(fingerprint);
    map['device_state'] = Variable<Uint8List>(deviceState);
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    if (!nullToAbsent || identityState != null) {
      map['identity_state'] = Variable<Uint8List>(identityState);
    }
    if (!nullToAbsent || backup != null) {
      map['backup'] = Variable<Uint8List>(backup);
    }
    map['backup_version'] = Variable<int>(backupVersion);
    map['identity_version'] = Variable<int>(identityVersion);
    if (!nullToAbsent || expectedSequence != null) {
      map['expected_sequence'] = Variable<int>(expectedSequence);
    }
    if (!nullToAbsent || previousHash != null) {
      map['previous_hash'] = Variable<Uint8List>(previousHash);
    }
    if (!nullToAbsent || pendingLogRecord != null) {
      map['pending_log_record'] = Variable<Uint8List>(pendingLogRecord);
    }
    if (!nullToAbsent || message != null) {
      map['message'] = Variable<int>(message);
    }
    map['recovery_secret_displayed'] = Variable<bool>(recoverySecretDisplayed);
    map['recovery_confirmed'] = Variable<bool>(recoveryConfirmed);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  EnrollmentIntentsCompanion toCompanion(bool nullToAbsent) {
    return EnrollmentIntentsCompanion(
      userId: Value(userId),
      flow: Value(flow),
      phase: Value(phase),
      fingerprint: Value(fingerprint),
      deviceState: Value(deviceState),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      identityState: identityState == null && nullToAbsent
          ? const Value.absent()
          : Value(identityState),
      backup: backup == null && nullToAbsent
          ? const Value.absent()
          : Value(backup),
      backupVersion: Value(backupVersion),
      identityVersion: Value(identityVersion),
      expectedSequence: expectedSequence == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedSequence),
      previousHash: previousHash == null && nullToAbsent
          ? const Value.absent()
          : Value(previousHash),
      pendingLogRecord: pendingLogRecord == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingLogRecord),
      message: message == null && nullToAbsent
          ? const Value.absent()
          : Value(message),
      recoverySecretDisplayed: Value(recoverySecretDisplayed),
      recoveryConfirmed: Value(recoveryConfirmed),
      updatedAt: Value(updatedAt),
    );
  }

  factory EnrollmentIntent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EnrollmentIntent(
      userId: serializer.fromJson<String>(json['userId']),
      flow: serializer.fromJson<int>(json['flow']),
      phase: serializer.fromJson<int>(json['phase']),
      fingerprint: serializer.fromJson<Uint8List>(json['fingerprint']),
      deviceState: serializer.fromJson<Uint8List>(json['deviceState']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      identityState: serializer.fromJson<Uint8List?>(json['identityState']),
      backup: serializer.fromJson<Uint8List?>(json['backup']),
      backupVersion: serializer.fromJson<int>(json['backupVersion']),
      identityVersion: serializer.fromJson<int>(json['identityVersion']),
      expectedSequence: serializer.fromJson<int?>(json['expectedSequence']),
      previousHash: serializer.fromJson<Uint8List?>(json['previousHash']),
      pendingLogRecord: serializer.fromJson<Uint8List?>(
        json['pendingLogRecord'],
      ),
      message: serializer.fromJson<int?>(json['message']),
      recoverySecretDisplayed: serializer.fromJson<bool>(
        json['recoverySecretDisplayed'],
      ),
      recoveryConfirmed: serializer.fromJson<bool>(json['recoveryConfirmed']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'flow': serializer.toJson<int>(flow),
      'phase': serializer.toJson<int>(phase),
      'fingerprint': serializer.toJson<Uint8List>(fingerprint),
      'deviceState': serializer.toJson<Uint8List>(deviceState),
      'deviceId': serializer.toJson<String?>(deviceId),
      'identityState': serializer.toJson<Uint8List?>(identityState),
      'backup': serializer.toJson<Uint8List?>(backup),
      'backupVersion': serializer.toJson<int>(backupVersion),
      'identityVersion': serializer.toJson<int>(identityVersion),
      'expectedSequence': serializer.toJson<int?>(expectedSequence),
      'previousHash': serializer.toJson<Uint8List?>(previousHash),
      'pendingLogRecord': serializer.toJson<Uint8List?>(pendingLogRecord),
      'message': serializer.toJson<int?>(message),
      'recoverySecretDisplayed': serializer.toJson<bool>(
        recoverySecretDisplayed,
      ),
      'recoveryConfirmed': serializer.toJson<bool>(recoveryConfirmed),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  EnrollmentIntent copyWith({
    String? userId,
    int? flow,
    int? phase,
    Uint8List? fingerprint,
    Uint8List? deviceState,
    Value<String?> deviceId = const Value.absent(),
    Value<Uint8List?> identityState = const Value.absent(),
    Value<Uint8List?> backup = const Value.absent(),
    int? backupVersion,
    int? identityVersion,
    Value<int?> expectedSequence = const Value.absent(),
    Value<Uint8List?> previousHash = const Value.absent(),
    Value<Uint8List?> pendingLogRecord = const Value.absent(),
    Value<int?> message = const Value.absent(),
    bool? recoverySecretDisplayed,
    bool? recoveryConfirmed,
    DateTime? updatedAt,
  }) => EnrollmentIntent(
    userId: userId ?? this.userId,
    flow: flow ?? this.flow,
    phase: phase ?? this.phase,
    fingerprint: fingerprint ?? this.fingerprint,
    deviceState: deviceState ?? this.deviceState,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    identityState: identityState.present
        ? identityState.value
        : this.identityState,
    backup: backup.present ? backup.value : this.backup,
    backupVersion: backupVersion ?? this.backupVersion,
    identityVersion: identityVersion ?? this.identityVersion,
    expectedSequence: expectedSequence.present
        ? expectedSequence.value
        : this.expectedSequence,
    previousHash: previousHash.present ? previousHash.value : this.previousHash,
    pendingLogRecord: pendingLogRecord.present
        ? pendingLogRecord.value
        : this.pendingLogRecord,
    message: message.present ? message.value : this.message,
    recoverySecretDisplayed:
        recoverySecretDisplayed ?? this.recoverySecretDisplayed,
    recoveryConfirmed: recoveryConfirmed ?? this.recoveryConfirmed,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EnrollmentIntent copyWithCompanion(EnrollmentIntentsCompanion data) {
    return EnrollmentIntent(
      userId: data.userId.present ? data.userId.value : this.userId,
      flow: data.flow.present ? data.flow.value : this.flow,
      phase: data.phase.present ? data.phase.value : this.phase,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      deviceState: data.deviceState.present
          ? data.deviceState.value
          : this.deviceState,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      identityState: data.identityState.present
          ? data.identityState.value
          : this.identityState,
      backup: data.backup.present ? data.backup.value : this.backup,
      backupVersion: data.backupVersion.present
          ? data.backupVersion.value
          : this.backupVersion,
      identityVersion: data.identityVersion.present
          ? data.identityVersion.value
          : this.identityVersion,
      expectedSequence: data.expectedSequence.present
          ? data.expectedSequence.value
          : this.expectedSequence,
      previousHash: data.previousHash.present
          ? data.previousHash.value
          : this.previousHash,
      pendingLogRecord: data.pendingLogRecord.present
          ? data.pendingLogRecord.value
          : this.pendingLogRecord,
      message: data.message.present ? data.message.value : this.message,
      recoverySecretDisplayed: data.recoverySecretDisplayed.present
          ? data.recoverySecretDisplayed.value
          : this.recoverySecretDisplayed,
      recoveryConfirmed: data.recoveryConfirmed.present
          ? data.recoveryConfirmed.value
          : this.recoveryConfirmed,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EnrollmentIntent(')
          ..write('userId: $userId, ')
          ..write('flow: $flow, ')
          ..write('phase: $phase, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('deviceState: $deviceState, ')
          ..write('deviceId: $deviceId, ')
          ..write('identityState: $identityState, ')
          ..write('backup: $backup, ')
          ..write('backupVersion: $backupVersion, ')
          ..write('identityVersion: $identityVersion, ')
          ..write('expectedSequence: $expectedSequence, ')
          ..write('previousHash: $previousHash, ')
          ..write('pendingLogRecord: $pendingLogRecord, ')
          ..write('message: $message, ')
          ..write('recoverySecretDisplayed: $recoverySecretDisplayed, ')
          ..write('recoveryConfirmed: $recoveryConfirmed, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    flow,
    phase,
    $driftBlobEquality.hash(fingerprint),
    $driftBlobEquality.hash(deviceState),
    deviceId,
    $driftBlobEquality.hash(identityState),
    $driftBlobEquality.hash(backup),
    backupVersion,
    identityVersion,
    expectedSequence,
    $driftBlobEquality.hash(previousHash),
    $driftBlobEquality.hash(pendingLogRecord),
    message,
    recoverySecretDisplayed,
    recoveryConfirmed,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EnrollmentIntent &&
          other.userId == this.userId &&
          other.flow == this.flow &&
          other.phase == this.phase &&
          $driftBlobEquality.equals(other.fingerprint, this.fingerprint) &&
          $driftBlobEquality.equals(other.deviceState, this.deviceState) &&
          other.deviceId == this.deviceId &&
          $driftBlobEquality.equals(other.identityState, this.identityState) &&
          $driftBlobEquality.equals(other.backup, this.backup) &&
          other.backupVersion == this.backupVersion &&
          other.identityVersion == this.identityVersion &&
          other.expectedSequence == this.expectedSequence &&
          $driftBlobEquality.equals(other.previousHash, this.previousHash) &&
          $driftBlobEquality.equals(
            other.pendingLogRecord,
            this.pendingLogRecord,
          ) &&
          other.message == this.message &&
          other.recoverySecretDisplayed == this.recoverySecretDisplayed &&
          other.recoveryConfirmed == this.recoveryConfirmed &&
          other.updatedAt == this.updatedAt);
}

class EnrollmentIntentsCompanion extends UpdateCompanion<EnrollmentIntent> {
  final Value<String> userId;
  final Value<int> flow;
  final Value<int> phase;
  final Value<Uint8List> fingerprint;
  final Value<Uint8List> deviceState;
  final Value<String?> deviceId;
  final Value<Uint8List?> identityState;
  final Value<Uint8List?> backup;
  final Value<int> backupVersion;
  final Value<int> identityVersion;
  final Value<int?> expectedSequence;
  final Value<Uint8List?> previousHash;
  final Value<Uint8List?> pendingLogRecord;
  final Value<int?> message;
  final Value<bool> recoverySecretDisplayed;
  final Value<bool> recoveryConfirmed;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const EnrollmentIntentsCompanion({
    this.userId = const Value.absent(),
    this.flow = const Value.absent(),
    this.phase = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.deviceState = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.identityState = const Value.absent(),
    this.backup = const Value.absent(),
    this.backupVersion = const Value.absent(),
    this.identityVersion = const Value.absent(),
    this.expectedSequence = const Value.absent(),
    this.previousHash = const Value.absent(),
    this.pendingLogRecord = const Value.absent(),
    this.message = const Value.absent(),
    this.recoverySecretDisplayed = const Value.absent(),
    this.recoveryConfirmed = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EnrollmentIntentsCompanion.insert({
    required String userId,
    required int flow,
    required int phase,
    required Uint8List fingerprint,
    required Uint8List deviceState,
    this.deviceId = const Value.absent(),
    this.identityState = const Value.absent(),
    this.backup = const Value.absent(),
    this.backupVersion = const Value.absent(),
    this.identityVersion = const Value.absent(),
    this.expectedSequence = const Value.absent(),
    this.previousHash = const Value.absent(),
    this.pendingLogRecord = const Value.absent(),
    this.message = const Value.absent(),
    this.recoverySecretDisplayed = const Value.absent(),
    this.recoveryConfirmed = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       flow = Value(flow),
       phase = Value(phase),
       fingerprint = Value(fingerprint),
       deviceState = Value(deviceState);
  static Insertable<EnrollmentIntent> custom({
    Expression<String>? userId,
    Expression<int>? flow,
    Expression<int>? phase,
    Expression<Uint8List>? fingerprint,
    Expression<Uint8List>? deviceState,
    Expression<String>? deviceId,
    Expression<Uint8List>? identityState,
    Expression<Uint8List>? backup,
    Expression<int>? backupVersion,
    Expression<int>? identityVersion,
    Expression<int>? expectedSequence,
    Expression<Uint8List>? previousHash,
    Expression<Uint8List>? pendingLogRecord,
    Expression<int>? message,
    Expression<bool>? recoverySecretDisplayed,
    Expression<bool>? recoveryConfirmed,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (flow != null) 'flow': flow,
      if (phase != null) 'phase': phase,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (deviceState != null) 'device_state': deviceState,
      if (deviceId != null) 'device_id': deviceId,
      if (identityState != null) 'identity_state': identityState,
      if (backup != null) 'backup': backup,
      if (backupVersion != null) 'backup_version': backupVersion,
      if (identityVersion != null) 'identity_version': identityVersion,
      if (expectedSequence != null) 'expected_sequence': expectedSequence,
      if (previousHash != null) 'previous_hash': previousHash,
      if (pendingLogRecord != null) 'pending_log_record': pendingLogRecord,
      if (message != null) 'message': message,
      if (recoverySecretDisplayed != null)
        'recovery_secret_displayed': recoverySecretDisplayed,
      if (recoveryConfirmed != null) 'recovery_confirmed': recoveryConfirmed,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EnrollmentIntentsCompanion copyWith({
    Value<String>? userId,
    Value<int>? flow,
    Value<int>? phase,
    Value<Uint8List>? fingerprint,
    Value<Uint8List>? deviceState,
    Value<String?>? deviceId,
    Value<Uint8List?>? identityState,
    Value<Uint8List?>? backup,
    Value<int>? backupVersion,
    Value<int>? identityVersion,
    Value<int?>? expectedSequence,
    Value<Uint8List?>? previousHash,
    Value<Uint8List?>? pendingLogRecord,
    Value<int?>? message,
    Value<bool>? recoverySecretDisplayed,
    Value<bool>? recoveryConfirmed,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return EnrollmentIntentsCompanion(
      userId: userId ?? this.userId,
      flow: flow ?? this.flow,
      phase: phase ?? this.phase,
      fingerprint: fingerprint ?? this.fingerprint,
      deviceState: deviceState ?? this.deviceState,
      deviceId: deviceId ?? this.deviceId,
      identityState: identityState ?? this.identityState,
      backup: backup ?? this.backup,
      backupVersion: backupVersion ?? this.backupVersion,
      identityVersion: identityVersion ?? this.identityVersion,
      expectedSequence: expectedSequence ?? this.expectedSequence,
      previousHash: previousHash ?? this.previousHash,
      pendingLogRecord: pendingLogRecord ?? this.pendingLogRecord,
      message: message ?? this.message,
      recoverySecretDisplayed:
          recoverySecretDisplayed ?? this.recoverySecretDisplayed,
      recoveryConfirmed: recoveryConfirmed ?? this.recoveryConfirmed,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (flow.present) {
      map['flow'] = Variable<int>(flow.value);
    }
    if (phase.present) {
      map['phase'] = Variable<int>(phase.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<Uint8List>(fingerprint.value);
    }
    if (deviceState.present) {
      map['device_state'] = Variable<Uint8List>(deviceState.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (identityState.present) {
      map['identity_state'] = Variable<Uint8List>(identityState.value);
    }
    if (backup.present) {
      map['backup'] = Variable<Uint8List>(backup.value);
    }
    if (backupVersion.present) {
      map['backup_version'] = Variable<int>(backupVersion.value);
    }
    if (identityVersion.present) {
      map['identity_version'] = Variable<int>(identityVersion.value);
    }
    if (expectedSequence.present) {
      map['expected_sequence'] = Variable<int>(expectedSequence.value);
    }
    if (previousHash.present) {
      map['previous_hash'] = Variable<Uint8List>(previousHash.value);
    }
    if (pendingLogRecord.present) {
      map['pending_log_record'] = Variable<Uint8List>(pendingLogRecord.value);
    }
    if (message.present) {
      map['message'] = Variable<int>(message.value);
    }
    if (recoverySecretDisplayed.present) {
      map['recovery_secret_displayed'] = Variable<bool>(
        recoverySecretDisplayed.value,
      );
    }
    if (recoveryConfirmed.present) {
      map['recovery_confirmed'] = Variable<bool>(recoveryConfirmed.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EnrollmentIntentsCompanion(')
          ..write('userId: $userId, ')
          ..write('flow: $flow, ')
          ..write('phase: $phase, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('deviceState: $deviceState, ')
          ..write('deviceId: $deviceId, ')
          ..write('identityState: $identityState, ')
          ..write('backup: $backup, ')
          ..write('backupVersion: $backupVersion, ')
          ..write('identityVersion: $identityVersion, ')
          ..write('expectedSequence: $expectedSequence, ')
          ..write('previousHash: $previousHash, ')
          ..write('pendingLogRecord: $pendingLogRecord, ')
          ..write('message: $message, ')
          ..write('recoverySecretDisplayed: $recoverySecretDisplayed, ')
          ..write('recoveryConfirmed: $recoveryConfirmed, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UsersTable extends Users with TableInfo<$UsersTable, User> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activatedMeta = const VerificationMeta(
    'activated',
  );
  @override
  late final GeneratedColumn<bool> activated = GeneratedColumn<bool>(
    'activated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("activated" IN (0, 1))',
    ),
  );
  static const VerificationMeta _directoryEntryCiphertextMeta =
      const VerificationMeta('directoryEntryCiphertext');
  @override
  late final GeneratedColumn<Uint8List> directoryEntryCiphertext =
      GeneratedColumn<Uint8List>(
        'directory_entry_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _localStateMeta = const VerificationMeta(
    'localState',
  );
  @override
  late final GeneratedColumn<int> localState = GeneratedColumn<int>(
    'local_state',
    aliasedName,
    false,
    check: () => ComparableExpr(localState).isBetweenValues(0, 7),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    activated,
    directoryEntryCiphertext,
    localState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<User> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('activated')) {
      context.handle(
        _activatedMeta,
        activated.isAcceptableOrUnknown(data['activated']!, _activatedMeta),
      );
    } else if (isInserting) {
      context.missing(_activatedMeta);
    }
    if (data.containsKey('directory_entry_ciphertext')) {
      context.handle(
        _directoryEntryCiphertextMeta,
        directoryEntryCiphertext.isAcceptableOrUnknown(
          data['directory_entry_ciphertext']!,
          _directoryEntryCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_directoryEntryCiphertextMeta);
    }
    if (data.containsKey('local_state')) {
      context.handle(
        _localStateMeta,
        localState.isAcceptableOrUnknown(data['local_state']!, _localStateMeta),
      );
    } else if (isInserting) {
      context.missing(_localStateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  User map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return User(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      activated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}activated'],
      )!,
      directoryEntryCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}directory_entry_ciphertext'],
      )!,
      localState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_state'],
      )!,
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class User extends DataClass implements Insertable<User> {
  final String userId;
  final bool activated;
  final Uint8List directoryEntryCiphertext;
  final int localState;
  const User({
    required this.userId,
    required this.activated,
    required this.directoryEntryCiphertext,
    required this.localState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['activated'] = Variable<bool>(activated);
    map['directory_entry_ciphertext'] = Variable<Uint8List>(
      directoryEntryCiphertext,
    );
    map['local_state'] = Variable<int>(localState);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      userId: Value(userId),
      activated: Value(activated),
      directoryEntryCiphertext: Value(directoryEntryCiphertext),
      localState: Value(localState),
    );
  }

  factory User.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return User(
      userId: serializer.fromJson<String>(json['userId']),
      activated: serializer.fromJson<bool>(json['activated']),
      directoryEntryCiphertext: serializer.fromJson<Uint8List>(
        json['directoryEntryCiphertext'],
      ),
      localState: serializer.fromJson<int>(json['localState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'activated': serializer.toJson<bool>(activated),
      'directoryEntryCiphertext': serializer.toJson<Uint8List>(
        directoryEntryCiphertext,
      ),
      'localState': serializer.toJson<int>(localState),
    };
  }

  User copyWith({
    String? userId,
    bool? activated,
    Uint8List? directoryEntryCiphertext,
    int? localState,
  }) => User(
    userId: userId ?? this.userId,
    activated: activated ?? this.activated,
    directoryEntryCiphertext:
        directoryEntryCiphertext ?? this.directoryEntryCiphertext,
    localState: localState ?? this.localState,
  );
  User copyWithCompanion(UsersCompanion data) {
    return User(
      userId: data.userId.present ? data.userId.value : this.userId,
      activated: data.activated.present ? data.activated.value : this.activated,
      directoryEntryCiphertext: data.directoryEntryCiphertext.present
          ? data.directoryEntryCiphertext.value
          : this.directoryEntryCiphertext,
      localState: data.localState.present
          ? data.localState.value
          : this.localState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('User(')
          ..write('userId: $userId, ')
          ..write('activated: $activated, ')
          ..write('directoryEntryCiphertext: $directoryEntryCiphertext, ')
          ..write('localState: $localState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    activated,
    $driftBlobEquality.hash(directoryEntryCiphertext),
    localState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          other.userId == this.userId &&
          other.activated == this.activated &&
          $driftBlobEquality.equals(
            other.directoryEntryCiphertext,
            this.directoryEntryCiphertext,
          ) &&
          other.localState == this.localState);
}

class UsersCompanion extends UpdateCompanion<User> {
  final Value<String> userId;
  final Value<bool> activated;
  final Value<Uint8List> directoryEntryCiphertext;
  final Value<int> localState;
  final Value<int> rowid;
  const UsersCompanion({
    this.userId = const Value.absent(),
    this.activated = const Value.absent(),
    this.directoryEntryCiphertext = const Value.absent(),
    this.localState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersCompanion.insert({
    required String userId,
    required bool activated,
    required Uint8List directoryEntryCiphertext,
    required int localState,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       activated = Value(activated),
       directoryEntryCiphertext = Value(directoryEntryCiphertext),
       localState = Value(localState);
  static Insertable<User> custom({
    Expression<String>? userId,
    Expression<bool>? activated,
    Expression<Uint8List>? directoryEntryCiphertext,
    Expression<int>? localState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (activated != null) 'activated': activated,
      if (directoryEntryCiphertext != null)
        'directory_entry_ciphertext': directoryEntryCiphertext,
      if (localState != null) 'local_state': localState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersCompanion copyWith({
    Value<String>? userId,
    Value<bool>? activated,
    Value<Uint8List>? directoryEntryCiphertext,
    Value<int>? localState,
    Value<int>? rowid,
  }) {
    return UsersCompanion(
      userId: userId ?? this.userId,
      activated: activated ?? this.activated,
      directoryEntryCiphertext:
          directoryEntryCiphertext ?? this.directoryEntryCiphertext,
      localState: localState ?? this.localState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (activated.present) {
      map['activated'] = Variable<bool>(activated.value);
    }
    if (directoryEntryCiphertext.present) {
      map['directory_entry_ciphertext'] = Variable<Uint8List>(
        directoryEntryCiphertext.value,
      );
    }
    if (localState.present) {
      map['local_state'] = Variable<int>(localState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('userId: $userId, ')
          ..write('activated: $activated, ')
          ..write('directoryEntryCiphertext: $directoryEntryCiphertext, ')
          ..write('localState: $localState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfilesTable extends Profiles with TableInfo<$ProfilesTable, Profile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (user_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _profileCiphertextMeta = const VerificationMeta(
    'profileCiphertext',
  );
  @override
  late final GeneratedColumn<Uint8List> profileCiphertext =
      GeneratedColumn<Uint8List>(
        'profile_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    check: () => ComparableExpr(version).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _verificationStateMeta = const VerificationMeta(
    'verificationState',
  );
  @override
  late final GeneratedColumn<int> verificationState = GeneratedColumn<int>(
    'verification_state',
    aliasedName,
    false,
    check: () => ComparableExpr(verificationState).isBetweenValues(0, 4),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    profileCiphertext,
    version,
    verificationState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<Profile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('profile_ciphertext')) {
      context.handle(
        _profileCiphertextMeta,
        profileCiphertext.isAcceptableOrUnknown(
          data['profile_ciphertext']!,
          _profileCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_profileCiphertextMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('verification_state')) {
      context.handle(
        _verificationStateMeta,
        verificationState.isAcceptableOrUnknown(
          data['verification_state']!,
          _verificationStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_verificationStateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  Profile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Profile(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      profileCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}profile_ciphertext'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      verificationState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}verification_state'],
      )!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class Profile extends DataClass implements Insertable<Profile> {
  final String userId;
  final Uint8List profileCiphertext;
  final int version;
  final int verificationState;
  const Profile({
    required this.userId,
    required this.profileCiphertext,
    required this.version,
    required this.verificationState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['profile_ciphertext'] = Variable<Uint8List>(profileCiphertext);
    map['version'] = Variable<int>(version);
    map['verification_state'] = Variable<int>(verificationState);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      userId: Value(userId),
      profileCiphertext: Value(profileCiphertext),
      version: Value(version),
      verificationState: Value(verificationState),
    );
  }

  factory Profile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Profile(
      userId: serializer.fromJson<String>(json['userId']),
      profileCiphertext: serializer.fromJson<Uint8List>(
        json['profileCiphertext'],
      ),
      version: serializer.fromJson<int>(json['version']),
      verificationState: serializer.fromJson<int>(json['verificationState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'profileCiphertext': serializer.toJson<Uint8List>(profileCiphertext),
      'version': serializer.toJson<int>(version),
      'verificationState': serializer.toJson<int>(verificationState),
    };
  }

  Profile copyWith({
    String? userId,
    Uint8List? profileCiphertext,
    int? version,
    int? verificationState,
  }) => Profile(
    userId: userId ?? this.userId,
    profileCiphertext: profileCiphertext ?? this.profileCiphertext,
    version: version ?? this.version,
    verificationState: verificationState ?? this.verificationState,
  );
  Profile copyWithCompanion(ProfilesCompanion data) {
    return Profile(
      userId: data.userId.present ? data.userId.value : this.userId,
      profileCiphertext: data.profileCiphertext.present
          ? data.profileCiphertext.value
          : this.profileCiphertext,
      version: data.version.present ? data.version.value : this.version,
      verificationState: data.verificationState.present
          ? data.verificationState.value
          : this.verificationState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Profile(')
          ..write('userId: $userId, ')
          ..write('profileCiphertext: $profileCiphertext, ')
          ..write('version: $version, ')
          ..write('verificationState: $verificationState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    $driftBlobEquality.hash(profileCiphertext),
    version,
    verificationState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          other.userId == this.userId &&
          $driftBlobEquality.equals(
            other.profileCiphertext,
            this.profileCiphertext,
          ) &&
          other.version == this.version &&
          other.verificationState == this.verificationState);
}

class ProfilesCompanion extends UpdateCompanion<Profile> {
  final Value<String> userId;
  final Value<Uint8List> profileCiphertext;
  final Value<int> version;
  final Value<int> verificationState;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.userId = const Value.absent(),
    this.profileCiphertext = const Value.absent(),
    this.version = const Value.absent(),
    this.verificationState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    required String userId,
    required Uint8List profileCiphertext,
    required int version,
    required int verificationState,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       profileCiphertext = Value(profileCiphertext),
       version = Value(version),
       verificationState = Value(verificationState);
  static Insertable<Profile> custom({
    Expression<String>? userId,
    Expression<Uint8List>? profileCiphertext,
    Expression<int>? version,
    Expression<int>? verificationState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (profileCiphertext != null) 'profile_ciphertext': profileCiphertext,
      if (version != null) 'version': version,
      if (verificationState != null) 'verification_state': verificationState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith({
    Value<String>? userId,
    Value<Uint8List>? profileCiphertext,
    Value<int>? version,
    Value<int>? verificationState,
    Value<int>? rowid,
  }) {
    return ProfilesCompanion(
      userId: userId ?? this.userId,
      profileCiphertext: profileCiphertext ?? this.profileCiphertext,
      version: version ?? this.version,
      verificationState: verificationState ?? this.verificationState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (profileCiphertext.present) {
      map['profile_ciphertext'] = Variable<Uint8List>(profileCiphertext.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (verificationState.present) {
      map['verification_state'] = Variable<int>(verificationState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('userId: $userId, ')
          ..write('profileCiphertext: $profileCiphertext, ')
          ..write('version: $version, ')
          ..write('verificationState: $verificationState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DevicesTable extends Devices with TableInfo<$DevicesTable, Device> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (user_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _publicBundleMeta = const VerificationMeta(
    'publicBundle',
  );
  @override
  late final GeneratedColumn<Uint8List> publicBundle =
      GeneratedColumn<Uint8List>(
        'public_bundle',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _etagCiphertextMeta = const VerificationMeta(
    'etagCiphertext',
  );
  @override
  late final GeneratedColumn<Uint8List> etagCiphertext =
      GeneratedColumn<Uint8List>(
        'etag_ciphertext',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _labelCiphertextMeta = const VerificationMeta(
    'labelCiphertext',
  );
  @override
  late final GeneratedColumn<Uint8List> labelCiphertext =
      GeneratedColumn<Uint8List>(
        'label_ciphertext',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _revocationStateMeta = const VerificationMeta(
    'revocationState',
  );
  @override
  late final GeneratedColumn<int> revocationState = GeneratedColumn<int>(
    'revocation_state',
    aliasedName,
    false,
    check: () => ComparableExpr(revocationState).isBetweenValues(0, 3),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bundleVersionMeta = const VerificationMeta(
    'bundleVersion',
  );
  @override
  late final GeneratedColumn<int> bundleVersion = GeneratedColumn<int>(
    'bundle_version',
    aliasedName,
    true,
    check: () =>
        bundleVersion.isNull() |
        ComparableExpr(bundleVersion).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    userId,
    publicBundle,
    etagCiphertext,
    labelCiphertext,
    revocationState,
    bundleVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<Device> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('public_bundle')) {
      context.handle(
        _publicBundleMeta,
        publicBundle.isAcceptableOrUnknown(
          data['public_bundle']!,
          _publicBundleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_publicBundleMeta);
    }
    if (data.containsKey('etag_ciphertext')) {
      context.handle(
        _etagCiphertextMeta,
        etagCiphertext.isAcceptableOrUnknown(
          data['etag_ciphertext']!,
          _etagCiphertextMeta,
        ),
      );
    }
    if (data.containsKey('label_ciphertext')) {
      context.handle(
        _labelCiphertextMeta,
        labelCiphertext.isAcceptableOrUnknown(
          data['label_ciphertext']!,
          _labelCiphertextMeta,
        ),
      );
    }
    if (data.containsKey('revocation_state')) {
      context.handle(
        _revocationStateMeta,
        revocationState.isAcceptableOrUnknown(
          data['revocation_state']!,
          _revocationStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_revocationStateMeta);
    }
    if (data.containsKey('bundle_version')) {
      context.handle(
        _bundleVersionMeta,
        bundleVersion.isAcceptableOrUnknown(
          data['bundle_version']!,
          _bundleVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  Device map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Device(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      publicBundle: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}public_bundle'],
      )!,
      etagCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}etag_ciphertext'],
      ),
      labelCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}label_ciphertext'],
      ),
      revocationState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revocation_state'],
      )!,
      bundleVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bundle_version'],
      ),
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }
}

class Device extends DataClass implements Insertable<Device> {
  final String deviceId;
  final String userId;
  final Uint8List publicBundle;
  final Uint8List? etagCiphertext;
  final Uint8List? labelCiphertext;
  final int revocationState;
  final int? bundleVersion;
  const Device({
    required this.deviceId,
    required this.userId,
    required this.publicBundle,
    this.etagCiphertext,
    this.labelCiphertext,
    required this.revocationState,
    this.bundleVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['user_id'] = Variable<String>(userId);
    map['public_bundle'] = Variable<Uint8List>(publicBundle);
    if (!nullToAbsent || etagCiphertext != null) {
      map['etag_ciphertext'] = Variable<Uint8List>(etagCiphertext);
    }
    if (!nullToAbsent || labelCiphertext != null) {
      map['label_ciphertext'] = Variable<Uint8List>(labelCiphertext);
    }
    map['revocation_state'] = Variable<int>(revocationState);
    if (!nullToAbsent || bundleVersion != null) {
      map['bundle_version'] = Variable<int>(bundleVersion);
    }
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      deviceId: Value(deviceId),
      userId: Value(userId),
      publicBundle: Value(publicBundle),
      etagCiphertext: etagCiphertext == null && nullToAbsent
          ? const Value.absent()
          : Value(etagCiphertext),
      labelCiphertext: labelCiphertext == null && nullToAbsent
          ? const Value.absent()
          : Value(labelCiphertext),
      revocationState: Value(revocationState),
      bundleVersion: bundleVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(bundleVersion),
    );
  }

  factory Device.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Device(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      userId: serializer.fromJson<String>(json['userId']),
      publicBundle: serializer.fromJson<Uint8List>(json['publicBundle']),
      etagCiphertext: serializer.fromJson<Uint8List?>(json['etagCiphertext']),
      labelCiphertext: serializer.fromJson<Uint8List?>(json['labelCiphertext']),
      revocationState: serializer.fromJson<int>(json['revocationState']),
      bundleVersion: serializer.fromJson<int?>(json['bundleVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'userId': serializer.toJson<String>(userId),
      'publicBundle': serializer.toJson<Uint8List>(publicBundle),
      'etagCiphertext': serializer.toJson<Uint8List?>(etagCiphertext),
      'labelCiphertext': serializer.toJson<Uint8List?>(labelCiphertext),
      'revocationState': serializer.toJson<int>(revocationState),
      'bundleVersion': serializer.toJson<int?>(bundleVersion),
    };
  }

  Device copyWith({
    String? deviceId,
    String? userId,
    Uint8List? publicBundle,
    Value<Uint8List?> etagCiphertext = const Value.absent(),
    Value<Uint8List?> labelCiphertext = const Value.absent(),
    int? revocationState,
    Value<int?> bundleVersion = const Value.absent(),
  }) => Device(
    deviceId: deviceId ?? this.deviceId,
    userId: userId ?? this.userId,
    publicBundle: publicBundle ?? this.publicBundle,
    etagCiphertext: etagCiphertext.present
        ? etagCiphertext.value
        : this.etagCiphertext,
    labelCiphertext: labelCiphertext.present
        ? labelCiphertext.value
        : this.labelCiphertext,
    revocationState: revocationState ?? this.revocationState,
    bundleVersion: bundleVersion.present
        ? bundleVersion.value
        : this.bundleVersion,
  );
  Device copyWithCompanion(DevicesCompanion data) {
    return Device(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      userId: data.userId.present ? data.userId.value : this.userId,
      publicBundle: data.publicBundle.present
          ? data.publicBundle.value
          : this.publicBundle,
      etagCiphertext: data.etagCiphertext.present
          ? data.etagCiphertext.value
          : this.etagCiphertext,
      labelCiphertext: data.labelCiphertext.present
          ? data.labelCiphertext.value
          : this.labelCiphertext,
      revocationState: data.revocationState.present
          ? data.revocationState.value
          : this.revocationState,
      bundleVersion: data.bundleVersion.present
          ? data.bundleVersion.value
          : this.bundleVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Device(')
          ..write('deviceId: $deviceId, ')
          ..write('userId: $userId, ')
          ..write('publicBundle: $publicBundle, ')
          ..write('etagCiphertext: $etagCiphertext, ')
          ..write('labelCiphertext: $labelCiphertext, ')
          ..write('revocationState: $revocationState, ')
          ..write('bundleVersion: $bundleVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    userId,
    $driftBlobEquality.hash(publicBundle),
    $driftBlobEquality.hash(etagCiphertext),
    $driftBlobEquality.hash(labelCiphertext),
    revocationState,
    bundleVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Device &&
          other.deviceId == this.deviceId &&
          other.userId == this.userId &&
          $driftBlobEquality.equals(other.publicBundle, this.publicBundle) &&
          $driftBlobEquality.equals(
            other.etagCiphertext,
            this.etagCiphertext,
          ) &&
          $driftBlobEquality.equals(
            other.labelCiphertext,
            this.labelCiphertext,
          ) &&
          other.revocationState == this.revocationState &&
          other.bundleVersion == this.bundleVersion);
}

class DevicesCompanion extends UpdateCompanion<Device> {
  final Value<String> deviceId;
  final Value<String> userId;
  final Value<Uint8List> publicBundle;
  final Value<Uint8List?> etagCiphertext;
  final Value<Uint8List?> labelCiphertext;
  final Value<int> revocationState;
  final Value<int?> bundleVersion;
  final Value<int> rowid;
  const DevicesCompanion({
    this.deviceId = const Value.absent(),
    this.userId = const Value.absent(),
    this.publicBundle = const Value.absent(),
    this.etagCiphertext = const Value.absent(),
    this.labelCiphertext = const Value.absent(),
    this.revocationState = const Value.absent(),
    this.bundleVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    required String deviceId,
    required String userId,
    required Uint8List publicBundle,
    this.etagCiphertext = const Value.absent(),
    this.labelCiphertext = const Value.absent(),
    required int revocationState,
    this.bundleVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       userId = Value(userId),
       publicBundle = Value(publicBundle),
       revocationState = Value(revocationState);
  static Insertable<Device> custom({
    Expression<String>? deviceId,
    Expression<String>? userId,
    Expression<Uint8List>? publicBundle,
    Expression<Uint8List>? etagCiphertext,
    Expression<Uint8List>? labelCiphertext,
    Expression<int>? revocationState,
    Expression<int>? bundleVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (userId != null) 'user_id': userId,
      if (publicBundle != null) 'public_bundle': publicBundle,
      if (etagCiphertext != null) 'etag_ciphertext': etagCiphertext,
      if (labelCiphertext != null) 'label_ciphertext': labelCiphertext,
      if (revocationState != null) 'revocation_state': revocationState,
      if (bundleVersion != null) 'bundle_version': bundleVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith({
    Value<String>? deviceId,
    Value<String>? userId,
    Value<Uint8List>? publicBundle,
    Value<Uint8List?>? etagCiphertext,
    Value<Uint8List?>? labelCiphertext,
    Value<int>? revocationState,
    Value<int?>? bundleVersion,
    Value<int>? rowid,
  }) {
    return DevicesCompanion(
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      publicBundle: publicBundle ?? this.publicBundle,
      etagCiphertext: etagCiphertext ?? this.etagCiphertext,
      labelCiphertext: labelCiphertext ?? this.labelCiphertext,
      revocationState: revocationState ?? this.revocationState,
      bundleVersion: bundleVersion ?? this.bundleVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (publicBundle.present) {
      map['public_bundle'] = Variable<Uint8List>(publicBundle.value);
    }
    if (etagCiphertext.present) {
      map['etag_ciphertext'] = Variable<Uint8List>(etagCiphertext.value);
    }
    if (labelCiphertext.present) {
      map['label_ciphertext'] = Variable<Uint8List>(labelCiphertext.value);
    }
    if (revocationState.present) {
      map['revocation_state'] = Variable<int>(revocationState.value);
    }
    if (bundleVersion.present) {
      map['bundle_version'] = Variable<int>(bundleVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('userId: $userId, ')
          ..write('publicBundle: $publicBundle, ')
          ..write('etagCiphertext: $etagCiphertext, ')
          ..write('labelCiphertext: $labelCiphertext, ')
          ..write('revocationState: $revocationState, ')
          ..write('bundleVersion: $bundleVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeviceLogRecordsTable extends DeviceLogRecords
    with TableInfo<$DeviceLogRecordsTable, DeviceLogRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeviceLogRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (user_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    check: () => ComparableExpr(sequence).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _signedOpaqueRecordMeta =
      const VerificationMeta('signedOpaqueRecord');
  @override
  late final GeneratedColumn<Uint8List> signedOpaqueRecord =
      GeneratedColumn<Uint8List>(
        'signed_opaque_record',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _recordHashMeta = const VerificationMeta(
    'recordHash',
  );
  @override
  late final GeneratedColumn<Uint8List> recordHash = GeneratedColumn<Uint8List>(
    'record_hash',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _forkStateMeta = const VerificationMeta(
    'forkState',
  );
  @override
  late final GeneratedColumn<int> forkState = GeneratedColumn<int>(
    'fork_state',
    aliasedName,
    false,
    check: () => ComparableExpr(forkState).isBetweenValues(0, 2),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gossipStateMeta = const VerificationMeta(
    'gossipState',
  );
  @override
  late final GeneratedColumn<int> gossipState = GeneratedColumn<int>(
    'gossip_state',
    aliasedName,
    false,
    check: () => ComparableExpr(gossipState).isBetweenValues(0, 3),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    sequence,
    signedOpaqueRecord,
    recordHash,
    forkState,
    gossipState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceLogRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('signed_opaque_record')) {
      context.handle(
        _signedOpaqueRecordMeta,
        signedOpaqueRecord.isAcceptableOrUnknown(
          data['signed_opaque_record']!,
          _signedOpaqueRecordMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_signedOpaqueRecordMeta);
    }
    if (data.containsKey('record_hash')) {
      context.handle(
        _recordHashMeta,
        recordHash.isAcceptableOrUnknown(data['record_hash']!, _recordHashMeta),
      );
    } else if (isInserting) {
      context.missing(_recordHashMeta);
    }
    if (data.containsKey('fork_state')) {
      context.handle(
        _forkStateMeta,
        forkState.isAcceptableOrUnknown(data['fork_state']!, _forkStateMeta),
      );
    } else if (isInserting) {
      context.missing(_forkStateMeta);
    }
    if (data.containsKey('gossip_state')) {
      context.handle(
        _gossipStateMeta,
        gossipState.isAcceptableOrUnknown(
          data['gossip_state']!,
          _gossipStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_gossipStateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, sequence};
  @override
  DeviceLogRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceLogRecord(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      signedOpaqueRecord: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}signed_opaque_record'],
      )!,
      recordHash: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}record_hash'],
      )!,
      forkState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fork_state'],
      )!,
      gossipState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gossip_state'],
      )!,
    );
  }

  @override
  $DeviceLogRecordsTable createAlias(String alias) {
    return $DeviceLogRecordsTable(attachedDatabase, alias);
  }
}

class DeviceLogRecord extends DataClass implements Insertable<DeviceLogRecord> {
  final String userId;
  final int sequence;
  final Uint8List signedOpaqueRecord;
  final Uint8List recordHash;
  final int forkState;
  final int gossipState;
  const DeviceLogRecord({
    required this.userId,
    required this.sequence,
    required this.signedOpaqueRecord,
    required this.recordHash,
    required this.forkState,
    required this.gossipState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['sequence'] = Variable<int>(sequence);
    map['signed_opaque_record'] = Variable<Uint8List>(signedOpaqueRecord);
    map['record_hash'] = Variable<Uint8List>(recordHash);
    map['fork_state'] = Variable<int>(forkState);
    map['gossip_state'] = Variable<int>(gossipState);
    return map;
  }

  DeviceLogRecordsCompanion toCompanion(bool nullToAbsent) {
    return DeviceLogRecordsCompanion(
      userId: Value(userId),
      sequence: Value(sequence),
      signedOpaqueRecord: Value(signedOpaqueRecord),
      recordHash: Value(recordHash),
      forkState: Value(forkState),
      gossipState: Value(gossipState),
    );
  }

  factory DeviceLogRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceLogRecord(
      userId: serializer.fromJson<String>(json['userId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      signedOpaqueRecord: serializer.fromJson<Uint8List>(
        json['signedOpaqueRecord'],
      ),
      recordHash: serializer.fromJson<Uint8List>(json['recordHash']),
      forkState: serializer.fromJson<int>(json['forkState']),
      gossipState: serializer.fromJson<int>(json['gossipState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'sequence': serializer.toJson<int>(sequence),
      'signedOpaqueRecord': serializer.toJson<Uint8List>(signedOpaqueRecord),
      'recordHash': serializer.toJson<Uint8List>(recordHash),
      'forkState': serializer.toJson<int>(forkState),
      'gossipState': serializer.toJson<int>(gossipState),
    };
  }

  DeviceLogRecord copyWith({
    String? userId,
    int? sequence,
    Uint8List? signedOpaqueRecord,
    Uint8List? recordHash,
    int? forkState,
    int? gossipState,
  }) => DeviceLogRecord(
    userId: userId ?? this.userId,
    sequence: sequence ?? this.sequence,
    signedOpaqueRecord: signedOpaqueRecord ?? this.signedOpaqueRecord,
    recordHash: recordHash ?? this.recordHash,
    forkState: forkState ?? this.forkState,
    gossipState: gossipState ?? this.gossipState,
  );
  DeviceLogRecord copyWithCompanion(DeviceLogRecordsCompanion data) {
    return DeviceLogRecord(
      userId: data.userId.present ? data.userId.value : this.userId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      signedOpaqueRecord: data.signedOpaqueRecord.present
          ? data.signedOpaqueRecord.value
          : this.signedOpaqueRecord,
      recordHash: data.recordHash.present
          ? data.recordHash.value
          : this.recordHash,
      forkState: data.forkState.present ? data.forkState.value : this.forkState,
      gossipState: data.gossipState.present
          ? data.gossipState.value
          : this.gossipState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceLogRecord(')
          ..write('userId: $userId, ')
          ..write('sequence: $sequence, ')
          ..write('signedOpaqueRecord: $signedOpaqueRecord, ')
          ..write('recordHash: $recordHash, ')
          ..write('forkState: $forkState, ')
          ..write('gossipState: $gossipState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    sequence,
    $driftBlobEquality.hash(signedOpaqueRecord),
    $driftBlobEquality.hash(recordHash),
    forkState,
    gossipState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceLogRecord &&
          other.userId == this.userId &&
          other.sequence == this.sequence &&
          $driftBlobEquality.equals(
            other.signedOpaqueRecord,
            this.signedOpaqueRecord,
          ) &&
          $driftBlobEquality.equals(other.recordHash, this.recordHash) &&
          other.forkState == this.forkState &&
          other.gossipState == this.gossipState);
}

class DeviceLogRecordsCompanion extends UpdateCompanion<DeviceLogRecord> {
  final Value<String> userId;
  final Value<int> sequence;
  final Value<Uint8List> signedOpaqueRecord;
  final Value<Uint8List> recordHash;
  final Value<int> forkState;
  final Value<int> gossipState;
  final Value<int> rowid;
  const DeviceLogRecordsCompanion({
    this.userId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.signedOpaqueRecord = const Value.absent(),
    this.recordHash = const Value.absent(),
    this.forkState = const Value.absent(),
    this.gossipState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeviceLogRecordsCompanion.insert({
    required String userId,
    required int sequence,
    required Uint8List signedOpaqueRecord,
    required Uint8List recordHash,
    required int forkState,
    required int gossipState,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       sequence = Value(sequence),
       signedOpaqueRecord = Value(signedOpaqueRecord),
       recordHash = Value(recordHash),
       forkState = Value(forkState),
       gossipState = Value(gossipState);
  static Insertable<DeviceLogRecord> custom({
    Expression<String>? userId,
    Expression<int>? sequence,
    Expression<Uint8List>? signedOpaqueRecord,
    Expression<Uint8List>? recordHash,
    Expression<int>? forkState,
    Expression<int>? gossipState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (sequence != null) 'sequence': sequence,
      if (signedOpaqueRecord != null)
        'signed_opaque_record': signedOpaqueRecord,
      if (recordHash != null) 'record_hash': recordHash,
      if (forkState != null) 'fork_state': forkState,
      if (gossipState != null) 'gossip_state': gossipState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeviceLogRecordsCompanion copyWith({
    Value<String>? userId,
    Value<int>? sequence,
    Value<Uint8List>? signedOpaqueRecord,
    Value<Uint8List>? recordHash,
    Value<int>? forkState,
    Value<int>? gossipState,
    Value<int>? rowid,
  }) {
    return DeviceLogRecordsCompanion(
      userId: userId ?? this.userId,
      sequence: sequence ?? this.sequence,
      signedOpaqueRecord: signedOpaqueRecord ?? this.signedOpaqueRecord,
      recordHash: recordHash ?? this.recordHash,
      forkState: forkState ?? this.forkState,
      gossipState: gossipState ?? this.gossipState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (signedOpaqueRecord.present) {
      map['signed_opaque_record'] = Variable<Uint8List>(
        signedOpaqueRecord.value,
      );
    }
    if (recordHash.present) {
      map['record_hash'] = Variable<Uint8List>(recordHash.value);
    }
    if (forkState.present) {
      map['fork_state'] = Variable<int>(forkState.value);
    }
    if (gossipState.present) {
      map['gossip_state'] = Variable<int>(gossipState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceLogRecordsCompanion(')
          ..write('userId: $userId, ')
          ..write('sequence: $sequence, ')
          ..write('signedOpaqueRecord: $signedOpaqueRecord, ')
          ..write('recordHash: $recordHash, ')
          ..write('forkState: $forkState, ')
          ..write('gossipState: $gossipState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PairwiseSessionsTable extends PairwiseSessions
    with TableInfo<$PairwiseSessionsTable, PairwiseSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PairwiseSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localDeviceIdMeta = const VerificationMeta(
    'localDeviceId',
  );
  @override
  late final GeneratedColumn<String> localDeviceId = GeneratedColumn<String>(
    'local_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteDeviceIdMeta = const VerificationMeta(
    'remoteDeviceId',
  );
  @override
  late final GeneratedColumn<String> remoteDeviceId = GeneratedColumn<String>(
    'remote_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opaqueCryptoStateHandleMeta =
      const VerificationMeta('opaqueCryptoStateHandle');
  @override
  late final GeneratedColumn<Uint8List> opaqueCryptoStateHandle =
      GeneratedColumn<Uint8List>(
        'opaque_crypto_state_handle',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _stateVersionMeta = const VerificationMeta(
    'stateVersion',
  );
  @override
  late final GeneratedColumn<int> stateVersion = GeneratedColumn<int>(
    'state_version',
    aliasedName,
    false,
    check: () => ComparableExpr(stateVersion).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localDeviceId,
    remoteDeviceId,
    opaqueCryptoStateHandle,
    stateVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pairwise_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PairwiseSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_device_id')) {
      context.handle(
        _localDeviceIdMeta,
        localDeviceId.isAcceptableOrUnknown(
          data['local_device_id']!,
          _localDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localDeviceIdMeta);
    }
    if (data.containsKey('remote_device_id')) {
      context.handle(
        _remoteDeviceIdMeta,
        remoteDeviceId.isAcceptableOrUnknown(
          data['remote_device_id']!,
          _remoteDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remoteDeviceIdMeta);
    }
    if (data.containsKey('opaque_crypto_state_handle')) {
      context.handle(
        _opaqueCryptoStateHandleMeta,
        opaqueCryptoStateHandle.isAcceptableOrUnknown(
          data['opaque_crypto_state_handle']!,
          _opaqueCryptoStateHandleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_opaqueCryptoStateHandleMeta);
    }
    if (data.containsKey('state_version')) {
      context.handle(
        _stateVersionMeta,
        stateVersion.isAcceptableOrUnknown(
          data['state_version']!,
          _stateVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_stateVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localDeviceId, remoteDeviceId};
  @override
  PairwiseSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PairwiseSession(
      localDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_device_id'],
      )!,
      remoteDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_device_id'],
      )!,
      opaqueCryptoStateHandle: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}opaque_crypto_state_handle'],
      )!,
      stateVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}state_version'],
      )!,
    );
  }

  @override
  $PairwiseSessionsTable createAlias(String alias) {
    return $PairwiseSessionsTable(attachedDatabase, alias);
  }
}

class PairwiseSession extends DataClass implements Insertable<PairwiseSession> {
  final String localDeviceId;
  final String remoteDeviceId;
  final Uint8List opaqueCryptoStateHandle;
  final int stateVersion;
  const PairwiseSession({
    required this.localDeviceId,
    required this.remoteDeviceId,
    required this.opaqueCryptoStateHandle,
    required this.stateVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_device_id'] = Variable<String>(localDeviceId);
    map['remote_device_id'] = Variable<String>(remoteDeviceId);
    map['opaque_crypto_state_handle'] = Variable<Uint8List>(
      opaqueCryptoStateHandle,
    );
    map['state_version'] = Variable<int>(stateVersion);
    return map;
  }

  PairwiseSessionsCompanion toCompanion(bool nullToAbsent) {
    return PairwiseSessionsCompanion(
      localDeviceId: Value(localDeviceId),
      remoteDeviceId: Value(remoteDeviceId),
      opaqueCryptoStateHandle: Value(opaqueCryptoStateHandle),
      stateVersion: Value(stateVersion),
    );
  }

  factory PairwiseSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PairwiseSession(
      localDeviceId: serializer.fromJson<String>(json['localDeviceId']),
      remoteDeviceId: serializer.fromJson<String>(json['remoteDeviceId']),
      opaqueCryptoStateHandle: serializer.fromJson<Uint8List>(
        json['opaqueCryptoStateHandle'],
      ),
      stateVersion: serializer.fromJson<int>(json['stateVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localDeviceId': serializer.toJson<String>(localDeviceId),
      'remoteDeviceId': serializer.toJson<String>(remoteDeviceId),
      'opaqueCryptoStateHandle': serializer.toJson<Uint8List>(
        opaqueCryptoStateHandle,
      ),
      'stateVersion': serializer.toJson<int>(stateVersion),
    };
  }

  PairwiseSession copyWith({
    String? localDeviceId,
    String? remoteDeviceId,
    Uint8List? opaqueCryptoStateHandle,
    int? stateVersion,
  }) => PairwiseSession(
    localDeviceId: localDeviceId ?? this.localDeviceId,
    remoteDeviceId: remoteDeviceId ?? this.remoteDeviceId,
    opaqueCryptoStateHandle:
        opaqueCryptoStateHandle ?? this.opaqueCryptoStateHandle,
    stateVersion: stateVersion ?? this.stateVersion,
  );
  PairwiseSession copyWithCompanion(PairwiseSessionsCompanion data) {
    return PairwiseSession(
      localDeviceId: data.localDeviceId.present
          ? data.localDeviceId.value
          : this.localDeviceId,
      remoteDeviceId: data.remoteDeviceId.present
          ? data.remoteDeviceId.value
          : this.remoteDeviceId,
      opaqueCryptoStateHandle: data.opaqueCryptoStateHandle.present
          ? data.opaqueCryptoStateHandle.value
          : this.opaqueCryptoStateHandle,
      stateVersion: data.stateVersion.present
          ? data.stateVersion.value
          : this.stateVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PairwiseSession(')
          ..write('localDeviceId: $localDeviceId, ')
          ..write('remoteDeviceId: $remoteDeviceId, ')
          ..write('opaqueCryptoStateHandle: $opaqueCryptoStateHandle, ')
          ..write('stateVersion: $stateVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localDeviceId,
    remoteDeviceId,
    $driftBlobEquality.hash(opaqueCryptoStateHandle),
    stateVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PairwiseSession &&
          other.localDeviceId == this.localDeviceId &&
          other.remoteDeviceId == this.remoteDeviceId &&
          $driftBlobEquality.equals(
            other.opaqueCryptoStateHandle,
            this.opaqueCryptoStateHandle,
          ) &&
          other.stateVersion == this.stateVersion);
}

class PairwiseSessionsCompanion extends UpdateCompanion<PairwiseSession> {
  final Value<String> localDeviceId;
  final Value<String> remoteDeviceId;
  final Value<Uint8List> opaqueCryptoStateHandle;
  final Value<int> stateVersion;
  final Value<int> rowid;
  const PairwiseSessionsCompanion({
    this.localDeviceId = const Value.absent(),
    this.remoteDeviceId = const Value.absent(),
    this.opaqueCryptoStateHandle = const Value.absent(),
    this.stateVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PairwiseSessionsCompanion.insert({
    required String localDeviceId,
    required String remoteDeviceId,
    required Uint8List opaqueCryptoStateHandle,
    required int stateVersion,
    this.rowid = const Value.absent(),
  }) : localDeviceId = Value(localDeviceId),
       remoteDeviceId = Value(remoteDeviceId),
       opaqueCryptoStateHandle = Value(opaqueCryptoStateHandle),
       stateVersion = Value(stateVersion);
  static Insertable<PairwiseSession> custom({
    Expression<String>? localDeviceId,
    Expression<String>? remoteDeviceId,
    Expression<Uint8List>? opaqueCryptoStateHandle,
    Expression<int>? stateVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localDeviceId != null) 'local_device_id': localDeviceId,
      if (remoteDeviceId != null) 'remote_device_id': remoteDeviceId,
      if (opaqueCryptoStateHandle != null)
        'opaque_crypto_state_handle': opaqueCryptoStateHandle,
      if (stateVersion != null) 'state_version': stateVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PairwiseSessionsCompanion copyWith({
    Value<String>? localDeviceId,
    Value<String>? remoteDeviceId,
    Value<Uint8List>? opaqueCryptoStateHandle,
    Value<int>? stateVersion,
    Value<int>? rowid,
  }) {
    return PairwiseSessionsCompanion(
      localDeviceId: localDeviceId ?? this.localDeviceId,
      remoteDeviceId: remoteDeviceId ?? this.remoteDeviceId,
      opaqueCryptoStateHandle:
          opaqueCryptoStateHandle ?? this.opaqueCryptoStateHandle,
      stateVersion: stateVersion ?? this.stateVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localDeviceId.present) {
      map['local_device_id'] = Variable<String>(localDeviceId.value);
    }
    if (remoteDeviceId.present) {
      map['remote_device_id'] = Variable<String>(remoteDeviceId.value);
    }
    if (opaqueCryptoStateHandle.present) {
      map['opaque_crypto_state_handle'] = Variable<Uint8List>(
        opaqueCryptoStateHandle.value,
      );
    }
    if (stateVersion.present) {
      map['state_version'] = Variable<int>(stateVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PairwiseSessionsCompanion(')
          ..write('localDeviceId: $localDeviceId, ')
          ..write('remoteDeviceId: $remoteDeviceId, ')
          ..write('opaqueCryptoStateHandle: $opaqueCryptoStateHandle, ')
          ..write('stateVersion: $stateVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PrekeysTable extends Prekeys with TableInfo<$PrekeysTable, Prekey> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PrekeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
    'kind',
    aliasedName,
    false,
    check: () => ComparableExpr(kind).isBetweenValues(0, 5),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyIdMeta = const VerificationMeta('keyId');
  @override
  late final GeneratedColumn<int> keyId = GeneratedColumn<int>(
    'key_id',
    aliasedName,
    false,
    check: () => ComparableExpr(keyId).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _privateStateHandleMeta =
      const VerificationMeta('privateStateHandle');
  @override
  late final GeneratedColumn<Uint8List> privateStateHandle =
      GeneratedColumn<Uint8List>(
        'private_state_handle',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _uploadStateMeta = const VerificationMeta(
    'uploadState',
  );
  @override
  late final GeneratedColumn<int> uploadState = GeneratedColumn<int>(
    'upload_state',
    aliasedName,
    false,
    check: () => ComparableExpr(uploadState).isBetweenValues(0, 4),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _useStateMeta = const VerificationMeta(
    'useState',
  );
  @override
  late final GeneratedColumn<int> useState = GeneratedColumn<int>(
    'use_state',
    aliasedName,
    false,
    check: () => ComparableExpr(useState).isBetweenValues(0, 4),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    kind,
    keyId,
    privateStateHandle,
    uploadState,
    useState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'prekeys';
  @override
  VerificationContext validateIntegrity(
    Insertable<Prekey> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('key_id')) {
      context.handle(
        _keyIdMeta,
        keyId.isAcceptableOrUnknown(data['key_id']!, _keyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_keyIdMeta);
    }
    if (data.containsKey('private_state_handle')) {
      context.handle(
        _privateStateHandleMeta,
        privateStateHandle.isAcceptableOrUnknown(
          data['private_state_handle']!,
          _privateStateHandleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_privateStateHandleMeta);
    }
    if (data.containsKey('upload_state')) {
      context.handle(
        _uploadStateMeta,
        uploadState.isAcceptableOrUnknown(
          data['upload_state']!,
          _uploadStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_uploadStateMeta);
    }
    if (data.containsKey('use_state')) {
      context.handle(
        _useStateMeta,
        useState.isAcceptableOrUnknown(data['use_state']!, _useStateMeta),
      );
    } else if (isInserting) {
      context.missing(_useStateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, keyId};
  @override
  Prekey map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Prekey(
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kind'],
      )!,
      keyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}key_id'],
      )!,
      privateStateHandle: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}private_state_handle'],
      )!,
      uploadState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}upload_state'],
      )!,
      useState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}use_state'],
      )!,
    );
  }

  @override
  $PrekeysTable createAlias(String alias) {
    return $PrekeysTable(attachedDatabase, alias);
  }
}

class Prekey extends DataClass implements Insertable<Prekey> {
  final int kind;
  final int keyId;
  final Uint8List privateStateHandle;
  final int uploadState;
  final int useState;
  const Prekey({
    required this.kind,
    required this.keyId,
    required this.privateStateHandle,
    required this.uploadState,
    required this.useState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<int>(kind);
    map['key_id'] = Variable<int>(keyId);
    map['private_state_handle'] = Variable<Uint8List>(privateStateHandle);
    map['upload_state'] = Variable<int>(uploadState);
    map['use_state'] = Variable<int>(useState);
    return map;
  }

  PrekeysCompanion toCompanion(bool nullToAbsent) {
    return PrekeysCompanion(
      kind: Value(kind),
      keyId: Value(keyId),
      privateStateHandle: Value(privateStateHandle),
      uploadState: Value(uploadState),
      useState: Value(useState),
    );
  }

  factory Prekey.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Prekey(
      kind: serializer.fromJson<int>(json['kind']),
      keyId: serializer.fromJson<int>(json['keyId']),
      privateStateHandle: serializer.fromJson<Uint8List>(
        json['privateStateHandle'],
      ),
      uploadState: serializer.fromJson<int>(json['uploadState']),
      useState: serializer.fromJson<int>(json['useState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<int>(kind),
      'keyId': serializer.toJson<int>(keyId),
      'privateStateHandle': serializer.toJson<Uint8List>(privateStateHandle),
      'uploadState': serializer.toJson<int>(uploadState),
      'useState': serializer.toJson<int>(useState),
    };
  }

  Prekey copyWith({
    int? kind,
    int? keyId,
    Uint8List? privateStateHandle,
    int? uploadState,
    int? useState,
  }) => Prekey(
    kind: kind ?? this.kind,
    keyId: keyId ?? this.keyId,
    privateStateHandle: privateStateHandle ?? this.privateStateHandle,
    uploadState: uploadState ?? this.uploadState,
    useState: useState ?? this.useState,
  );
  Prekey copyWithCompanion(PrekeysCompanion data) {
    return Prekey(
      kind: data.kind.present ? data.kind.value : this.kind,
      keyId: data.keyId.present ? data.keyId.value : this.keyId,
      privateStateHandle: data.privateStateHandle.present
          ? data.privateStateHandle.value
          : this.privateStateHandle,
      uploadState: data.uploadState.present
          ? data.uploadState.value
          : this.uploadState,
      useState: data.useState.present ? data.useState.value : this.useState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Prekey(')
          ..write('kind: $kind, ')
          ..write('keyId: $keyId, ')
          ..write('privateStateHandle: $privateStateHandle, ')
          ..write('uploadState: $uploadState, ')
          ..write('useState: $useState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    kind,
    keyId,
    $driftBlobEquality.hash(privateStateHandle),
    uploadState,
    useState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Prekey &&
          other.kind == this.kind &&
          other.keyId == this.keyId &&
          $driftBlobEquality.equals(
            other.privateStateHandle,
            this.privateStateHandle,
          ) &&
          other.uploadState == this.uploadState &&
          other.useState == this.useState);
}

class PrekeysCompanion extends UpdateCompanion<Prekey> {
  final Value<int> kind;
  final Value<int> keyId;
  final Value<Uint8List> privateStateHandle;
  final Value<int> uploadState;
  final Value<int> useState;
  final Value<int> rowid;
  const PrekeysCompanion({
    this.kind = const Value.absent(),
    this.keyId = const Value.absent(),
    this.privateStateHandle = const Value.absent(),
    this.uploadState = const Value.absent(),
    this.useState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PrekeysCompanion.insert({
    required int kind,
    required int keyId,
    required Uint8List privateStateHandle,
    required int uploadState,
    required int useState,
    this.rowid = const Value.absent(),
  }) : kind = Value(kind),
       keyId = Value(keyId),
       privateStateHandle = Value(privateStateHandle),
       uploadState = Value(uploadState),
       useState = Value(useState);
  static Insertable<Prekey> custom({
    Expression<int>? kind,
    Expression<int>? keyId,
    Expression<Uint8List>? privateStateHandle,
    Expression<int>? uploadState,
    Expression<int>? useState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (keyId != null) 'key_id': keyId,
      if (privateStateHandle != null)
        'private_state_handle': privateStateHandle,
      if (uploadState != null) 'upload_state': uploadState,
      if (useState != null) 'use_state': useState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PrekeysCompanion copyWith({
    Value<int>? kind,
    Value<int>? keyId,
    Value<Uint8List>? privateStateHandle,
    Value<int>? uploadState,
    Value<int>? useState,
    Value<int>? rowid,
  }) {
    return PrekeysCompanion(
      kind: kind ?? this.kind,
      keyId: keyId ?? this.keyId,
      privateStateHandle: privateStateHandle ?? this.privateStateHandle,
      uploadState: uploadState ?? this.uploadState,
      useState: useState ?? this.useState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (keyId.present) {
      map['key_id'] = Variable<int>(keyId.value);
    }
    if (privateStateHandle.present) {
      map['private_state_handle'] = Variable<Uint8List>(
        privateStateHandle.value,
      );
    }
    if (uploadState.present) {
      map['upload_state'] = Variable<int>(uploadState.value);
    }
    if (useState.present) {
      map['use_state'] = Variable<int>(useState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PrekeysCompanion(')
          ..write('kind: $kind, ')
          ..write('keyId: $keyId, ')
          ..write('privateStateHandle: $privateStateHandle, ')
          ..write('uploadState: $uploadState, ')
          ..write('useState: $useState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MlsGroupsTable extends MlsGroups
    with TableInfo<$MlsGroupsTable, MlsGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MlsGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opaqueCryptoStateHandleMeta =
      const VerificationMeta('opaqueCryptoStateHandle');
  @override
  late final GeneratedColumn<Uint8List> opaqueCryptoStateHandle =
      GeneratedColumn<Uint8List>(
        'opaque_crypto_state_handle',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _acceptedEpochMeta = const VerificationMeta(
    'acceptedEpoch',
  );
  @override
  late final GeneratedColumn<int> acceptedEpoch = GeneratedColumn<int>(
    'accepted_epoch',
    aliasedName,
    false,
    check: () => ComparableExpr(acceptedEpoch).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateVersionMeta = const VerificationMeta(
    'stateVersion',
  );
  @override
  late final GeneratedColumn<int> stateVersion = GeneratedColumn<int>(
    'state_version',
    aliasedName,
    false,
    check: () => ComparableExpr(stateVersion).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queueGapRecoveryStateMeta =
      const VerificationMeta('queueGapRecoveryState');
  @override
  late final GeneratedColumn<int> queueGapRecoveryState = GeneratedColumn<int>(
    'queue_gap_recovery_state',
    aliasedName,
    false,
    check: () => ComparableExpr(queueGapRecoveryState).isBetweenValues(0, 2),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    opaqueCryptoStateHandle,
    acceptedEpoch,
    stateVersion,
    queueGapRecoveryState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mls_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<MlsGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('opaque_crypto_state_handle')) {
      context.handle(
        _opaqueCryptoStateHandleMeta,
        opaqueCryptoStateHandle.isAcceptableOrUnknown(
          data['opaque_crypto_state_handle']!,
          _opaqueCryptoStateHandleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_opaqueCryptoStateHandleMeta);
    }
    if (data.containsKey('accepted_epoch')) {
      context.handle(
        _acceptedEpochMeta,
        acceptedEpoch.isAcceptableOrUnknown(
          data['accepted_epoch']!,
          _acceptedEpochMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_acceptedEpochMeta);
    }
    if (data.containsKey('state_version')) {
      context.handle(
        _stateVersionMeta,
        stateVersion.isAcceptableOrUnknown(
          data['state_version']!,
          _stateVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_stateVersionMeta);
    }
    if (data.containsKey('queue_gap_recovery_state')) {
      context.handle(
        _queueGapRecoveryStateMeta,
        queueGapRecoveryState.isAcceptableOrUnknown(
          data['queue_gap_recovery_state']!,
          _queueGapRecoveryStateMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId};
  @override
  MlsGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MlsGroup(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      opaqueCryptoStateHandle: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}opaque_crypto_state_handle'],
      )!,
      acceptedEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accepted_epoch'],
      )!,
      stateVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}state_version'],
      )!,
      queueGapRecoveryState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}queue_gap_recovery_state'],
      )!,
    );
  }

  @override
  $MlsGroupsTable createAlias(String alias) {
    return $MlsGroupsTable(attachedDatabase, alias);
  }
}

class MlsGroup extends DataClass implements Insertable<MlsGroup> {
  final String groupId;
  final Uint8List opaqueCryptoStateHandle;
  final int acceptedEpoch;
  final int stateVersion;
  final int queueGapRecoveryState;
  const MlsGroup({
    required this.groupId,
    required this.opaqueCryptoStateHandle,
    required this.acceptedEpoch,
    required this.stateVersion,
    required this.queueGapRecoveryState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['opaque_crypto_state_handle'] = Variable<Uint8List>(
      opaqueCryptoStateHandle,
    );
    map['accepted_epoch'] = Variable<int>(acceptedEpoch);
    map['state_version'] = Variable<int>(stateVersion);
    map['queue_gap_recovery_state'] = Variable<int>(queueGapRecoveryState);
    return map;
  }

  MlsGroupsCompanion toCompanion(bool nullToAbsent) {
    return MlsGroupsCompanion(
      groupId: Value(groupId),
      opaqueCryptoStateHandle: Value(opaqueCryptoStateHandle),
      acceptedEpoch: Value(acceptedEpoch),
      stateVersion: Value(stateVersion),
      queueGapRecoveryState: Value(queueGapRecoveryState),
    );
  }

  factory MlsGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MlsGroup(
      groupId: serializer.fromJson<String>(json['groupId']),
      opaqueCryptoStateHandle: serializer.fromJson<Uint8List>(
        json['opaqueCryptoStateHandle'],
      ),
      acceptedEpoch: serializer.fromJson<int>(json['acceptedEpoch']),
      stateVersion: serializer.fromJson<int>(json['stateVersion']),
      queueGapRecoveryState: serializer.fromJson<int>(
        json['queueGapRecoveryState'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'opaqueCryptoStateHandle': serializer.toJson<Uint8List>(
        opaqueCryptoStateHandle,
      ),
      'acceptedEpoch': serializer.toJson<int>(acceptedEpoch),
      'stateVersion': serializer.toJson<int>(stateVersion),
      'queueGapRecoveryState': serializer.toJson<int>(queueGapRecoveryState),
    };
  }

  MlsGroup copyWith({
    String? groupId,
    Uint8List? opaqueCryptoStateHandle,
    int? acceptedEpoch,
    int? stateVersion,
    int? queueGapRecoveryState,
  }) => MlsGroup(
    groupId: groupId ?? this.groupId,
    opaqueCryptoStateHandle:
        opaqueCryptoStateHandle ?? this.opaqueCryptoStateHandle,
    acceptedEpoch: acceptedEpoch ?? this.acceptedEpoch,
    stateVersion: stateVersion ?? this.stateVersion,
    queueGapRecoveryState: queueGapRecoveryState ?? this.queueGapRecoveryState,
  );
  MlsGroup copyWithCompanion(MlsGroupsCompanion data) {
    return MlsGroup(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      opaqueCryptoStateHandle: data.opaqueCryptoStateHandle.present
          ? data.opaqueCryptoStateHandle.value
          : this.opaqueCryptoStateHandle,
      acceptedEpoch: data.acceptedEpoch.present
          ? data.acceptedEpoch.value
          : this.acceptedEpoch,
      stateVersion: data.stateVersion.present
          ? data.stateVersion.value
          : this.stateVersion,
      queueGapRecoveryState: data.queueGapRecoveryState.present
          ? data.queueGapRecoveryState.value
          : this.queueGapRecoveryState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MlsGroup(')
          ..write('groupId: $groupId, ')
          ..write('opaqueCryptoStateHandle: $opaqueCryptoStateHandle, ')
          ..write('acceptedEpoch: $acceptedEpoch, ')
          ..write('stateVersion: $stateVersion, ')
          ..write('queueGapRecoveryState: $queueGapRecoveryState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    $driftBlobEquality.hash(opaqueCryptoStateHandle),
    acceptedEpoch,
    stateVersion,
    queueGapRecoveryState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MlsGroup &&
          other.groupId == this.groupId &&
          $driftBlobEquality.equals(
            other.opaqueCryptoStateHandle,
            this.opaqueCryptoStateHandle,
          ) &&
          other.acceptedEpoch == this.acceptedEpoch &&
          other.stateVersion == this.stateVersion &&
          other.queueGapRecoveryState == this.queueGapRecoveryState);
}

class MlsGroupsCompanion extends UpdateCompanion<MlsGroup> {
  final Value<String> groupId;
  final Value<Uint8List> opaqueCryptoStateHandle;
  final Value<int> acceptedEpoch;
  final Value<int> stateVersion;
  final Value<int> queueGapRecoveryState;
  final Value<int> rowid;
  const MlsGroupsCompanion({
    this.groupId = const Value.absent(),
    this.opaqueCryptoStateHandle = const Value.absent(),
    this.acceptedEpoch = const Value.absent(),
    this.stateVersion = const Value.absent(),
    this.queueGapRecoveryState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MlsGroupsCompanion.insert({
    required String groupId,
    required Uint8List opaqueCryptoStateHandle,
    required int acceptedEpoch,
    required int stateVersion,
    this.queueGapRecoveryState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       opaqueCryptoStateHandle = Value(opaqueCryptoStateHandle),
       acceptedEpoch = Value(acceptedEpoch),
       stateVersion = Value(stateVersion);
  static Insertable<MlsGroup> custom({
    Expression<String>? groupId,
    Expression<Uint8List>? opaqueCryptoStateHandle,
    Expression<int>? acceptedEpoch,
    Expression<int>? stateVersion,
    Expression<int>? queueGapRecoveryState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (opaqueCryptoStateHandle != null)
        'opaque_crypto_state_handle': opaqueCryptoStateHandle,
      if (acceptedEpoch != null) 'accepted_epoch': acceptedEpoch,
      if (stateVersion != null) 'state_version': stateVersion,
      if (queueGapRecoveryState != null)
        'queue_gap_recovery_state': queueGapRecoveryState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MlsGroupsCompanion copyWith({
    Value<String>? groupId,
    Value<Uint8List>? opaqueCryptoStateHandle,
    Value<int>? acceptedEpoch,
    Value<int>? stateVersion,
    Value<int>? queueGapRecoveryState,
    Value<int>? rowid,
  }) {
    return MlsGroupsCompanion(
      groupId: groupId ?? this.groupId,
      opaqueCryptoStateHandle:
          opaqueCryptoStateHandle ?? this.opaqueCryptoStateHandle,
      acceptedEpoch: acceptedEpoch ?? this.acceptedEpoch,
      stateVersion: stateVersion ?? this.stateVersion,
      queueGapRecoveryState:
          queueGapRecoveryState ?? this.queueGapRecoveryState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (opaqueCryptoStateHandle.present) {
      map['opaque_crypto_state_handle'] = Variable<Uint8List>(
        opaqueCryptoStateHandle.value,
      );
    }
    if (acceptedEpoch.present) {
      map['accepted_epoch'] = Variable<int>(acceptedEpoch.value);
    }
    if (stateVersion.present) {
      map['state_version'] = Variable<int>(stateVersion.value);
    }
    if (queueGapRecoveryState.present) {
      map['queue_gap_recovery_state'] = Variable<int>(
        queueGapRecoveryState.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MlsGroupsCompanion(')
          ..write('groupId: $groupId, ')
          ..write('opaqueCryptoStateHandle: $opaqueCryptoStateHandle, ')
          ..write('acceptedEpoch: $acceptedEpoch, ')
          ..write('stateVersion: $stateVersion, ')
          ..write('queueGapRecoveryState: $queueGapRecoveryState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
    'kind',
    aliasedName,
    false,
    check: () => ComparableExpr(kind).isBetweenValues(0, 2),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _listProjectionCiphertextMeta =
      const VerificationMeta('listProjectionCiphertext');
  @override
  late final GeneratedColumn<Uint8List> listProjectionCiphertext =
      GeneratedColumn<Uint8List>(
        'list_projection_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<int> sortKey = GeneratedColumn<int>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tombstonedMeta = const VerificationMeta(
    'tombstoned',
  );
  @override
  late final GeneratedColumn<bool> tombstoned = GeneratedColumn<bool>(
    'tombstoned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("tombstoned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    conversationId,
    kind,
    listProjectionCiphertext,
    sortKey,
    tombstoned,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('list_projection_ciphertext')) {
      context.handle(
        _listProjectionCiphertextMeta,
        listProjectionCiphertext.isAcceptableOrUnknown(
          data['list_projection_ciphertext']!,
          _listProjectionCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_listProjectionCiphertextMeta);
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sortKeyMeta);
    }
    if (data.containsKey('tombstoned')) {
      context.handle(
        _tombstonedMeta,
        tombstoned.isAcceptableOrUnknown(data['tombstoned']!, _tombstonedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conversationId};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kind'],
      )!,
      listProjectionCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}list_projection_ciphertext'],
      )!,
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_key'],
      )!,
      tombstoned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}tombstoned'],
      )!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final String conversationId;
  final int kind;
  final Uint8List listProjectionCiphertext;
  final int sortKey;
  final bool tombstoned;
  const Conversation({
    required this.conversationId,
    required this.kind,
    required this.listProjectionCiphertext,
    required this.sortKey,
    required this.tombstoned,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<String>(conversationId);
    map['kind'] = Variable<int>(kind);
    map['list_projection_ciphertext'] = Variable<Uint8List>(
      listProjectionCiphertext,
    );
    map['sort_key'] = Variable<int>(sortKey);
    map['tombstoned'] = Variable<bool>(tombstoned);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      conversationId: Value(conversationId),
      kind: Value(kind),
      listProjectionCiphertext: Value(listProjectionCiphertext),
      sortKey: Value(sortKey),
      tombstoned: Value(tombstoned),
    );
  }

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      conversationId: serializer.fromJson<String>(json['conversationId']),
      kind: serializer.fromJson<int>(json['kind']),
      listProjectionCiphertext: serializer.fromJson<Uint8List>(
        json['listProjectionCiphertext'],
      ),
      sortKey: serializer.fromJson<int>(json['sortKey']),
      tombstoned: serializer.fromJson<bool>(json['tombstoned']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<String>(conversationId),
      'kind': serializer.toJson<int>(kind),
      'listProjectionCiphertext': serializer.toJson<Uint8List>(
        listProjectionCiphertext,
      ),
      'sortKey': serializer.toJson<int>(sortKey),
      'tombstoned': serializer.toJson<bool>(tombstoned),
    };
  }

  Conversation copyWith({
    String? conversationId,
    int? kind,
    Uint8List? listProjectionCiphertext,
    int? sortKey,
    bool? tombstoned,
  }) => Conversation(
    conversationId: conversationId ?? this.conversationId,
    kind: kind ?? this.kind,
    listProjectionCiphertext:
        listProjectionCiphertext ?? this.listProjectionCiphertext,
    sortKey: sortKey ?? this.sortKey,
    tombstoned: tombstoned ?? this.tombstoned,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      kind: data.kind.present ? data.kind.value : this.kind,
      listProjectionCiphertext: data.listProjectionCiphertext.present
          ? data.listProjectionCiphertext.value
          : this.listProjectionCiphertext,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      tombstoned: data.tombstoned.present
          ? data.tombstoned.value
          : this.tombstoned,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('conversationId: $conversationId, ')
          ..write('kind: $kind, ')
          ..write('listProjectionCiphertext: $listProjectionCiphertext, ')
          ..write('sortKey: $sortKey, ')
          ..write('tombstoned: $tombstoned')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    conversationId,
    kind,
    $driftBlobEquality.hash(listProjectionCiphertext),
    sortKey,
    tombstoned,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.conversationId == this.conversationId &&
          other.kind == this.kind &&
          $driftBlobEquality.equals(
            other.listProjectionCiphertext,
            this.listProjectionCiphertext,
          ) &&
          other.sortKey == this.sortKey &&
          other.tombstoned == this.tombstoned);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String> conversationId;
  final Value<int> kind;
  final Value<Uint8List> listProjectionCiphertext;
  final Value<int> sortKey;
  final Value<bool> tombstoned;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.conversationId = const Value.absent(),
    this.kind = const Value.absent(),
    this.listProjectionCiphertext = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.tombstoned = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String conversationId,
    required int kind,
    required Uint8List listProjectionCiphertext,
    required int sortKey,
    this.tombstoned = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : conversationId = Value(conversationId),
       kind = Value(kind),
       listProjectionCiphertext = Value(listProjectionCiphertext),
       sortKey = Value(sortKey);
  static Insertable<Conversation> custom({
    Expression<String>? conversationId,
    Expression<int>? kind,
    Expression<Uint8List>? listProjectionCiphertext,
    Expression<int>? sortKey,
    Expression<bool>? tombstoned,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (kind != null) 'kind': kind,
      if (listProjectionCiphertext != null)
        'list_projection_ciphertext': listProjectionCiphertext,
      if (sortKey != null) 'sort_key': sortKey,
      if (tombstoned != null) 'tombstoned': tombstoned,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String>? conversationId,
    Value<int>? kind,
    Value<Uint8List>? listProjectionCiphertext,
    Value<int>? sortKey,
    Value<bool>? tombstoned,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      conversationId: conversationId ?? this.conversationId,
      kind: kind ?? this.kind,
      listProjectionCiphertext:
          listProjectionCiphertext ?? this.listProjectionCiphertext,
      sortKey: sortKey ?? this.sortKey,
      tombstoned: tombstoned ?? this.tombstoned,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (listProjectionCiphertext.present) {
      map['list_projection_ciphertext'] = Variable<Uint8List>(
        listProjectionCiphertext.value,
      );
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<int>(sortKey.value);
    }
    if (tombstoned.present) {
      map['tombstoned'] = Variable<bool>(tombstoned.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('kind: $kind, ')
          ..write('listProjectionCiphertext: $listProjectionCiphertext, ')
          ..write('sortKey: $sortKey, ')
          ..write('tombstoned: $tombstoned, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MembershipsTable extends Memberships
    with TableInfo<$MembershipsTable, Membership> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembershipsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (conversation_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (user_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _rolePolicyProjectionCiphertextMeta =
      const VerificationMeta('rolePolicyProjectionCiphertext');
  @override
  late final GeneratedColumn<Uint8List> rolePolicyProjectionCiphertext =
      GeneratedColumn<Uint8List>(
        'role_policy_projection_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    conversationId,
    userId,
    rolePolicyProjectionCiphertext,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memberships';
  @override
  VerificationContext validateIntegrity(
    Insertable<Membership> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('role_policy_projection_ciphertext')) {
      context.handle(
        _rolePolicyProjectionCiphertextMeta,
        rolePolicyProjectionCiphertext.isAcceptableOrUnknown(
          data['role_policy_projection_ciphertext']!,
          _rolePolicyProjectionCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rolePolicyProjectionCiphertextMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conversationId, userId};
  @override
  Membership map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Membership(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      rolePolicyProjectionCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}role_policy_projection_ciphertext'],
      )!,
    );
  }

  @override
  $MembershipsTable createAlias(String alias) {
    return $MembershipsTable(attachedDatabase, alias);
  }
}

class Membership extends DataClass implements Insertable<Membership> {
  final String conversationId;
  final String userId;
  final Uint8List rolePolicyProjectionCiphertext;
  const Membership({
    required this.conversationId,
    required this.userId,
    required this.rolePolicyProjectionCiphertext,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<String>(conversationId);
    map['user_id'] = Variable<String>(userId);
    map['role_policy_projection_ciphertext'] = Variable<Uint8List>(
      rolePolicyProjectionCiphertext,
    );
    return map;
  }

  MembershipsCompanion toCompanion(bool nullToAbsent) {
    return MembershipsCompanion(
      conversationId: Value(conversationId),
      userId: Value(userId),
      rolePolicyProjectionCiphertext: Value(rolePolicyProjectionCiphertext),
    );
  }

  factory Membership.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Membership(
      conversationId: serializer.fromJson<String>(json['conversationId']),
      userId: serializer.fromJson<String>(json['userId']),
      rolePolicyProjectionCiphertext: serializer.fromJson<Uint8List>(
        json['rolePolicyProjectionCiphertext'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<String>(conversationId),
      'userId': serializer.toJson<String>(userId),
      'rolePolicyProjectionCiphertext': serializer.toJson<Uint8List>(
        rolePolicyProjectionCiphertext,
      ),
    };
  }

  Membership copyWith({
    String? conversationId,
    String? userId,
    Uint8List? rolePolicyProjectionCiphertext,
  }) => Membership(
    conversationId: conversationId ?? this.conversationId,
    userId: userId ?? this.userId,
    rolePolicyProjectionCiphertext:
        rolePolicyProjectionCiphertext ?? this.rolePolicyProjectionCiphertext,
  );
  Membership copyWithCompanion(MembershipsCompanion data) {
    return Membership(
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      userId: data.userId.present ? data.userId.value : this.userId,
      rolePolicyProjectionCiphertext:
          data.rolePolicyProjectionCiphertext.present
          ? data.rolePolicyProjectionCiphertext.value
          : this.rolePolicyProjectionCiphertext,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Membership(')
          ..write('conversationId: $conversationId, ')
          ..write('userId: $userId, ')
          ..write(
            'rolePolicyProjectionCiphertext: $rolePolicyProjectionCiphertext',
          )
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    conversationId,
    userId,
    $driftBlobEquality.hash(rolePolicyProjectionCiphertext),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Membership &&
          other.conversationId == this.conversationId &&
          other.userId == this.userId &&
          $driftBlobEquality.equals(
            other.rolePolicyProjectionCiphertext,
            this.rolePolicyProjectionCiphertext,
          ));
}

class MembershipsCompanion extends UpdateCompanion<Membership> {
  final Value<String> conversationId;
  final Value<String> userId;
  final Value<Uint8List> rolePolicyProjectionCiphertext;
  final Value<int> rowid;
  const MembershipsCompanion({
    this.conversationId = const Value.absent(),
    this.userId = const Value.absent(),
    this.rolePolicyProjectionCiphertext = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MembershipsCompanion.insert({
    required String conversationId,
    required String userId,
    required Uint8List rolePolicyProjectionCiphertext,
    this.rowid = const Value.absent(),
  }) : conversationId = Value(conversationId),
       userId = Value(userId),
       rolePolicyProjectionCiphertext = Value(rolePolicyProjectionCiphertext);
  static Insertable<Membership> custom({
    Expression<String>? conversationId,
    Expression<String>? userId,
    Expression<Uint8List>? rolePolicyProjectionCiphertext,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (userId != null) 'user_id': userId,
      if (rolePolicyProjectionCiphertext != null)
        'role_policy_projection_ciphertext': rolePolicyProjectionCiphertext,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MembershipsCompanion copyWith({
    Value<String>? conversationId,
    Value<String>? userId,
    Value<Uint8List>? rolePolicyProjectionCiphertext,
    Value<int>? rowid,
  }) {
    return MembershipsCompanion(
      conversationId: conversationId ?? this.conversationId,
      userId: userId ?? this.userId,
      rolePolicyProjectionCiphertext:
          rolePolicyProjectionCiphertext ?? this.rolePolicyProjectionCiphertext,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (rolePolicyProjectionCiphertext.present) {
      map['role_policy_projection_ciphertext'] = Variable<Uint8List>(
        rolePolicyProjectionCiphertext.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembershipsCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('userId: $userId, ')
          ..write(
            'rolePolicyProjectionCiphertext: $rolePolicyProjectionCiphertext, ',
          )
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (conversation_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _currentEventIdMeta = const VerificationMeta(
    'currentEventId',
  );
  @override
  late final GeneratedColumn<String> currentEventId = GeneratedColumn<String>(
    'current_event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectionCiphertextMeta =
      const VerificationMeta('projectionCiphertext');
  @override
  late final GeneratedColumn<Uint8List> projectionCiphertext =
      GeneratedColumn<Uint8List>(
        'projection_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    check: () => ComparableExpr(status).isBetweenValues(0, 8),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    check: () => ComparableExpr(revision).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    messageId,
    conversationId,
    currentEventId,
    projectionCiphertext,
    status,
    revision,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('current_event_id')) {
      context.handle(
        _currentEventIdMeta,
        currentEventId.isAcceptableOrUnknown(
          data['current_event_id']!,
          _currentEventIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentEventIdMeta);
    }
    if (data.containsKey('projection_ciphertext')) {
      context.handle(
        _projectionCiphertextMeta,
        projectionCiphertext.isAcceptableOrUnknown(
          data['projection_ciphertext']!,
          _projectionCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_projectionCiphertextMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageId};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      currentEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_event_id'],
      )!,
      projectionCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}projection_ciphertext'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String messageId;
  final String conversationId;
  final String currentEventId;
  final Uint8List projectionCiphertext;
  final int status;
  final int revision;
  final DateTime createdAt;
  const Message({
    required this.messageId,
    required this.conversationId,
    required this.currentEventId,
    required this.projectionCiphertext,
    required this.status,
    required this.revision,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_id'] = Variable<String>(messageId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['current_event_id'] = Variable<String>(currentEventId);
    map['projection_ciphertext'] = Variable<Uint8List>(projectionCiphertext);
    map['status'] = Variable<int>(status);
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      messageId: Value(messageId),
      conversationId: Value(conversationId),
      currentEventId: Value(currentEventId),
      projectionCiphertext: Value(projectionCiphertext),
      status: Value(status),
      revision: Value(revision),
      createdAt: Value(createdAt),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      messageId: serializer.fromJson<String>(json['messageId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      currentEventId: serializer.fromJson<String>(json['currentEventId']),
      projectionCiphertext: serializer.fromJson<Uint8List>(
        json['projectionCiphertext'],
      ),
      status: serializer.fromJson<int>(json['status']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageId': serializer.toJson<String>(messageId),
      'conversationId': serializer.toJson<String>(conversationId),
      'currentEventId': serializer.toJson<String>(currentEventId),
      'projectionCiphertext': serializer.toJson<Uint8List>(
        projectionCiphertext,
      ),
      'status': serializer.toJson<int>(status),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Message copyWith({
    String? messageId,
    String? conversationId,
    String? currentEventId,
    Uint8List? projectionCiphertext,
    int? status,
    int? revision,
    DateTime? createdAt,
  }) => Message(
    messageId: messageId ?? this.messageId,
    conversationId: conversationId ?? this.conversationId,
    currentEventId: currentEventId ?? this.currentEventId,
    projectionCiphertext: projectionCiphertext ?? this.projectionCiphertext,
    status: status ?? this.status,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      currentEventId: data.currentEventId.present
          ? data.currentEventId.value
          : this.currentEventId,
      projectionCiphertext: data.projectionCiphertext.present
          ? data.projectionCiphertext.value
          : this.projectionCiphertext,
      status: data.status.present ? data.status.value : this.status,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('messageId: $messageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('currentEventId: $currentEventId, ')
          ..write('projectionCiphertext: $projectionCiphertext, ')
          ..write('status: $status, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    messageId,
    conversationId,
    currentEventId,
    $driftBlobEquality.hash(projectionCiphertext),
    status,
    revision,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.messageId == this.messageId &&
          other.conversationId == this.conversationId &&
          other.currentEventId == this.currentEventId &&
          $driftBlobEquality.equals(
            other.projectionCiphertext,
            this.projectionCiphertext,
          ) &&
          other.status == this.status &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> messageId;
  final Value<String> conversationId;
  final Value<String> currentEventId;
  final Value<Uint8List> projectionCiphertext;
  final Value<int> status;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const MessagesCompanion({
    this.messageId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.currentEventId = const Value.absent(),
    this.projectionCiphertext = const Value.absent(),
    this.status = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String messageId,
    required String conversationId,
    required String currentEventId,
    required Uint8List projectionCiphertext,
    required int status,
    required int revision,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : messageId = Value(messageId),
       conversationId = Value(conversationId),
       currentEventId = Value(currentEventId),
       projectionCiphertext = Value(projectionCiphertext),
       status = Value(status),
       revision = Value(revision),
       createdAt = Value(createdAt);
  static Insertable<Message> custom({
    Expression<String>? messageId,
    Expression<String>? conversationId,
    Expression<String>? currentEventId,
    Expression<Uint8List>? projectionCiphertext,
    Expression<int>? status,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageId != null) 'message_id': messageId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (currentEventId != null) 'current_event_id': currentEventId,
      if (projectionCiphertext != null)
        'projection_ciphertext': projectionCiphertext,
      if (status != null) 'status': status,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? messageId,
    Value<String>? conversationId,
    Value<String>? currentEventId,
    Value<Uint8List>? projectionCiphertext,
    Value<int>? status,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      currentEventId: currentEventId ?? this.currentEventId,
      projectionCiphertext: projectionCiphertext ?? this.projectionCiphertext,
      status: status ?? this.status,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (currentEventId.present) {
      map['current_event_id'] = Variable<String>(currentEventId.value);
    }
    if (projectionCiphertext.present) {
      map['projection_ciphertext'] = Variable<Uint8List>(
        projectionCiphertext.value,
      );
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('messageId: $messageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('currentEventId: $currentEventId, ')
          ..write('projectionCiphertext: $projectionCiphertext, ')
          ..write('status: $status, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageEventsTable extends MessageEvents
    with TableInfo<$MessageEventsTable, MessageEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (conversation_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _eventKindMeta = const VerificationMeta(
    'eventKind',
  );
  @override
  late final GeneratedColumn<int> eventKind = GeneratedColumn<int>(
    'event_kind',
    aliasedName,
    false,
    check: () => ComparableExpr(eventKind).isBetweenValues(0, 31),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authenticatedCiphertextMeta =
      const VerificationMeta('authenticatedCiphertext');
  @override
  late final GeneratedColumn<Uint8List> authenticatedCiphertext =
      GeneratedColumn<Uint8List>(
        'authenticated_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    eventId,
    messageId,
    conversationId,
    eventKind,
    authenticatedCiphertext,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('event_kind')) {
      context.handle(
        _eventKindMeta,
        eventKind.isAcceptableOrUnknown(data['event_kind']!, _eventKindMeta),
      );
    } else if (isInserting) {
      context.missing(_eventKindMeta);
    }
    if (data.containsKey('authenticated_ciphertext')) {
      context.handle(
        _authenticatedCiphertextMeta,
        authenticatedCiphertext.isAcceptableOrUnknown(
          data['authenticated_ciphertext']!,
          _authenticatedCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authenticatedCiphertextMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId};
  @override
  MessageEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageEvent(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      eventKind: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}event_kind'],
      )!,
      authenticatedCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}authenticated_ciphertext'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MessageEventsTable createAlias(String alias) {
    return $MessageEventsTable(attachedDatabase, alias);
  }
}

class MessageEvent extends DataClass implements Insertable<MessageEvent> {
  final String eventId;
  final String messageId;
  final String conversationId;
  final int eventKind;
  final Uint8List authenticatedCiphertext;
  final DateTime createdAt;
  const MessageEvent({
    required this.eventId,
    required this.messageId,
    required this.conversationId,
    required this.eventKind,
    required this.authenticatedCiphertext,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['message_id'] = Variable<String>(messageId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['event_kind'] = Variable<int>(eventKind);
    map['authenticated_ciphertext'] = Variable<Uint8List>(
      authenticatedCiphertext,
    );
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessageEventsCompanion toCompanion(bool nullToAbsent) {
    return MessageEventsCompanion(
      eventId: Value(eventId),
      messageId: Value(messageId),
      conversationId: Value(conversationId),
      eventKind: Value(eventKind),
      authenticatedCiphertext: Value(authenticatedCiphertext),
      createdAt: Value(createdAt),
    );
  }

  factory MessageEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageEvent(
      eventId: serializer.fromJson<String>(json['eventId']),
      messageId: serializer.fromJson<String>(json['messageId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      eventKind: serializer.fromJson<int>(json['eventKind']),
      authenticatedCiphertext: serializer.fromJson<Uint8List>(
        json['authenticatedCiphertext'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'messageId': serializer.toJson<String>(messageId),
      'conversationId': serializer.toJson<String>(conversationId),
      'eventKind': serializer.toJson<int>(eventKind),
      'authenticatedCiphertext': serializer.toJson<Uint8List>(
        authenticatedCiphertext,
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  MessageEvent copyWith({
    String? eventId,
    String? messageId,
    String? conversationId,
    int? eventKind,
    Uint8List? authenticatedCiphertext,
    DateTime? createdAt,
  }) => MessageEvent(
    eventId: eventId ?? this.eventId,
    messageId: messageId ?? this.messageId,
    conversationId: conversationId ?? this.conversationId,
    eventKind: eventKind ?? this.eventKind,
    authenticatedCiphertext:
        authenticatedCiphertext ?? this.authenticatedCiphertext,
    createdAt: createdAt ?? this.createdAt,
  );
  MessageEvent copyWithCompanion(MessageEventsCompanion data) {
    return MessageEvent(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      eventKind: data.eventKind.present ? data.eventKind.value : this.eventKind,
      authenticatedCiphertext: data.authenticatedCiphertext.present
          ? data.authenticatedCiphertext.value
          : this.authenticatedCiphertext,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageEvent(')
          ..write('eventId: $eventId, ')
          ..write('messageId: $messageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('eventKind: $eventKind, ')
          ..write('authenticatedCiphertext: $authenticatedCiphertext, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    eventId,
    messageId,
    conversationId,
    eventKind,
    $driftBlobEquality.hash(authenticatedCiphertext),
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageEvent &&
          other.eventId == this.eventId &&
          other.messageId == this.messageId &&
          other.conversationId == this.conversationId &&
          other.eventKind == this.eventKind &&
          $driftBlobEquality.equals(
            other.authenticatedCiphertext,
            this.authenticatedCiphertext,
          ) &&
          other.createdAt == this.createdAt);
}

class MessageEventsCompanion extends UpdateCompanion<MessageEvent> {
  final Value<String> eventId;
  final Value<String> messageId;
  final Value<String> conversationId;
  final Value<int> eventKind;
  final Value<Uint8List> authenticatedCiphertext;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const MessageEventsCompanion({
    this.eventId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.eventKind = const Value.absent(),
    this.authenticatedCiphertext = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageEventsCompanion.insert({
    required String eventId,
    required String messageId,
    required String conversationId,
    required int eventKind,
    required Uint8List authenticatedCiphertext,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       messageId = Value(messageId),
       conversationId = Value(conversationId),
       eventKind = Value(eventKind),
       authenticatedCiphertext = Value(authenticatedCiphertext),
       createdAt = Value(createdAt);
  static Insertable<MessageEvent> custom({
    Expression<String>? eventId,
    Expression<String>? messageId,
    Expression<String>? conversationId,
    Expression<int>? eventKind,
    Expression<Uint8List>? authenticatedCiphertext,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (messageId != null) 'message_id': messageId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (eventKind != null) 'event_kind': eventKind,
      if (authenticatedCiphertext != null)
        'authenticated_ciphertext': authenticatedCiphertext,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageEventsCompanion copyWith({
    Value<String>? eventId,
    Value<String>? messageId,
    Value<String>? conversationId,
    Value<int>? eventKind,
    Value<Uint8List>? authenticatedCiphertext,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return MessageEventsCompanion(
      eventId: eventId ?? this.eventId,
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      eventKind: eventKind ?? this.eventKind,
      authenticatedCiphertext:
          authenticatedCiphertext ?? this.authenticatedCiphertext,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (eventKind.present) {
      map['event_kind'] = Variable<int>(eventKind.value);
    }
    if (authenticatedCiphertext.present) {
      map['authenticated_ciphertext'] = Variable<Uint8List>(
        authenticatedCiphertext.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageEventsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('messageId: $messageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('eventKind: $eventKind, ')
          ..write('authenticatedCiphertext: $authenticatedCiphertext, ')
          ..write('createdAt: $createdAt, ')
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
  static const VerificationMeta _attachmentIdMeta = const VerificationMeta(
    'attachmentId',
  );
  @override
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (message_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _encryptedDescriptorMeta =
      const VerificationMeta('encryptedDescriptor');
  @override
  late final GeneratedColumn<Uint8List> encryptedDescriptor =
      GeneratedColumn<Uint8List>(
        'encrypted_descriptor',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _transferStateMeta = const VerificationMeta(
    'transferState',
  );
  @override
  late final GeneratedColumn<int> transferState = GeneratedColumn<int>(
    'transfer_state',
    aliasedName,
    false,
    check: () => ComparableExpr(transferState).isBetweenValues(0, 8),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _boundedCacheHandleCiphertextMeta =
      const VerificationMeta('boundedCacheHandleCiphertext');
  @override
  late final GeneratedColumn<Uint8List> boundedCacheHandleCiphertext =
      GeneratedColumn<Uint8List>(
        'bounded_cache_handle_ciphertext',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _cacheExpiresAtMeta = const VerificationMeta(
    'cacheExpiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> cacheExpiresAt =
      GeneratedColumn<DateTime>(
        'cache_expires_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    attachmentId,
    messageId,
    encryptedDescriptor,
    transferState,
    boundedCacheHandleCiphertext,
    cacheExpiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Attachment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('attachment_id')) {
      context.handle(
        _attachmentIdMeta,
        attachmentId.isAcceptableOrUnknown(
          data['attachment_id']!,
          _attachmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attachmentIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('encrypted_descriptor')) {
      context.handle(
        _encryptedDescriptorMeta,
        encryptedDescriptor.isAcceptableOrUnknown(
          data['encrypted_descriptor']!,
          _encryptedDescriptorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedDescriptorMeta);
    }
    if (data.containsKey('transfer_state')) {
      context.handle(
        _transferStateMeta,
        transferState.isAcceptableOrUnknown(
          data['transfer_state']!,
          _transferStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transferStateMeta);
    }
    if (data.containsKey('bounded_cache_handle_ciphertext')) {
      context.handle(
        _boundedCacheHandleCiphertextMeta,
        boundedCacheHandleCiphertext.isAcceptableOrUnknown(
          data['bounded_cache_handle_ciphertext']!,
          _boundedCacheHandleCiphertextMeta,
        ),
      );
    }
    if (data.containsKey('cache_expires_at')) {
      context.handle(
        _cacheExpiresAtMeta,
        cacheExpiresAt.isAcceptableOrUnknown(
          data['cache_expires_at']!,
          _cacheExpiresAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {attachmentId};
  @override
  Attachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Attachment(
      attachmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachment_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      encryptedDescriptor: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}encrypted_descriptor'],
      )!,
      transferState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transfer_state'],
      )!,
      boundedCacheHandleCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bounded_cache_handle_ciphertext'],
      ),
      cacheExpiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cache_expires_at'],
      ),
    );
  }

  @override
  $AttachmentsTable createAlias(String alias) {
    return $AttachmentsTable(attachedDatabase, alias);
  }
}

class Attachment extends DataClass implements Insertable<Attachment> {
  final String attachmentId;
  final String messageId;
  final Uint8List encryptedDescriptor;
  final int transferState;
  final Uint8List? boundedCacheHandleCiphertext;
  final DateTime? cacheExpiresAt;
  const Attachment({
    required this.attachmentId,
    required this.messageId,
    required this.encryptedDescriptor,
    required this.transferState,
    this.boundedCacheHandleCiphertext,
    this.cacheExpiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['attachment_id'] = Variable<String>(attachmentId);
    map['message_id'] = Variable<String>(messageId);
    map['encrypted_descriptor'] = Variable<Uint8List>(encryptedDescriptor);
    map['transfer_state'] = Variable<int>(transferState);
    if (!nullToAbsent || boundedCacheHandleCiphertext != null) {
      map['bounded_cache_handle_ciphertext'] = Variable<Uint8List>(
        boundedCacheHandleCiphertext,
      );
    }
    if (!nullToAbsent || cacheExpiresAt != null) {
      map['cache_expires_at'] = Variable<DateTime>(cacheExpiresAt);
    }
    return map;
  }

  AttachmentsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentsCompanion(
      attachmentId: Value(attachmentId),
      messageId: Value(messageId),
      encryptedDescriptor: Value(encryptedDescriptor),
      transferState: Value(transferState),
      boundedCacheHandleCiphertext:
          boundedCacheHandleCiphertext == null && nullToAbsent
          ? const Value.absent()
          : Value(boundedCacheHandleCiphertext),
      cacheExpiresAt: cacheExpiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(cacheExpiresAt),
    );
  }

  factory Attachment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Attachment(
      attachmentId: serializer.fromJson<String>(json['attachmentId']),
      messageId: serializer.fromJson<String>(json['messageId']),
      encryptedDescriptor: serializer.fromJson<Uint8List>(
        json['encryptedDescriptor'],
      ),
      transferState: serializer.fromJson<int>(json['transferState']),
      boundedCacheHandleCiphertext: serializer.fromJson<Uint8List?>(
        json['boundedCacheHandleCiphertext'],
      ),
      cacheExpiresAt: serializer.fromJson<DateTime?>(json['cacheExpiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'attachmentId': serializer.toJson<String>(attachmentId),
      'messageId': serializer.toJson<String>(messageId),
      'encryptedDescriptor': serializer.toJson<Uint8List>(encryptedDescriptor),
      'transferState': serializer.toJson<int>(transferState),
      'boundedCacheHandleCiphertext': serializer.toJson<Uint8List?>(
        boundedCacheHandleCiphertext,
      ),
      'cacheExpiresAt': serializer.toJson<DateTime?>(cacheExpiresAt),
    };
  }

  Attachment copyWith({
    String? attachmentId,
    String? messageId,
    Uint8List? encryptedDescriptor,
    int? transferState,
    Value<Uint8List?> boundedCacheHandleCiphertext = const Value.absent(),
    Value<DateTime?> cacheExpiresAt = const Value.absent(),
  }) => Attachment(
    attachmentId: attachmentId ?? this.attachmentId,
    messageId: messageId ?? this.messageId,
    encryptedDescriptor: encryptedDescriptor ?? this.encryptedDescriptor,
    transferState: transferState ?? this.transferState,
    boundedCacheHandleCiphertext: boundedCacheHandleCiphertext.present
        ? boundedCacheHandleCiphertext.value
        : this.boundedCacheHandleCiphertext,
    cacheExpiresAt: cacheExpiresAt.present
        ? cacheExpiresAt.value
        : this.cacheExpiresAt,
  );
  Attachment copyWithCompanion(AttachmentsCompanion data) {
    return Attachment(
      attachmentId: data.attachmentId.present
          ? data.attachmentId.value
          : this.attachmentId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      encryptedDescriptor: data.encryptedDescriptor.present
          ? data.encryptedDescriptor.value
          : this.encryptedDescriptor,
      transferState: data.transferState.present
          ? data.transferState.value
          : this.transferState,
      boundedCacheHandleCiphertext: data.boundedCacheHandleCiphertext.present
          ? data.boundedCacheHandleCiphertext.value
          : this.boundedCacheHandleCiphertext,
      cacheExpiresAt: data.cacheExpiresAt.present
          ? data.cacheExpiresAt.value
          : this.cacheExpiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Attachment(')
          ..write('attachmentId: $attachmentId, ')
          ..write('messageId: $messageId, ')
          ..write('encryptedDescriptor: $encryptedDescriptor, ')
          ..write('transferState: $transferState, ')
          ..write(
            'boundedCacheHandleCiphertext: $boundedCacheHandleCiphertext, ',
          )
          ..write('cacheExpiresAt: $cacheExpiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    attachmentId,
    messageId,
    $driftBlobEquality.hash(encryptedDescriptor),
    transferState,
    $driftBlobEquality.hash(boundedCacheHandleCiphertext),
    cacheExpiresAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Attachment &&
          other.attachmentId == this.attachmentId &&
          other.messageId == this.messageId &&
          $driftBlobEquality.equals(
            other.encryptedDescriptor,
            this.encryptedDescriptor,
          ) &&
          other.transferState == this.transferState &&
          $driftBlobEquality.equals(
            other.boundedCacheHandleCiphertext,
            this.boundedCacheHandleCiphertext,
          ) &&
          other.cacheExpiresAt == this.cacheExpiresAt);
}

class AttachmentsCompanion extends UpdateCompanion<Attachment> {
  final Value<String> attachmentId;
  final Value<String> messageId;
  final Value<Uint8List> encryptedDescriptor;
  final Value<int> transferState;
  final Value<Uint8List?> boundedCacheHandleCiphertext;
  final Value<DateTime?> cacheExpiresAt;
  final Value<int> rowid;
  const AttachmentsCompanion({
    this.attachmentId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.encryptedDescriptor = const Value.absent(),
    this.transferState = const Value.absent(),
    this.boundedCacheHandleCiphertext = const Value.absent(),
    this.cacheExpiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentsCompanion.insert({
    required String attachmentId,
    required String messageId,
    required Uint8List encryptedDescriptor,
    required int transferState,
    this.boundedCacheHandleCiphertext = const Value.absent(),
    this.cacheExpiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : attachmentId = Value(attachmentId),
       messageId = Value(messageId),
       encryptedDescriptor = Value(encryptedDescriptor),
       transferState = Value(transferState);
  static Insertable<Attachment> custom({
    Expression<String>? attachmentId,
    Expression<String>? messageId,
    Expression<Uint8List>? encryptedDescriptor,
    Expression<int>? transferState,
    Expression<Uint8List>? boundedCacheHandleCiphertext,
    Expression<DateTime>? cacheExpiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (attachmentId != null) 'attachment_id': attachmentId,
      if (messageId != null) 'message_id': messageId,
      if (encryptedDescriptor != null)
        'encrypted_descriptor': encryptedDescriptor,
      if (transferState != null) 'transfer_state': transferState,
      if (boundedCacheHandleCiphertext != null)
        'bounded_cache_handle_ciphertext': boundedCacheHandleCiphertext,
      if (cacheExpiresAt != null) 'cache_expires_at': cacheExpiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentsCompanion copyWith({
    Value<String>? attachmentId,
    Value<String>? messageId,
    Value<Uint8List>? encryptedDescriptor,
    Value<int>? transferState,
    Value<Uint8List?>? boundedCacheHandleCiphertext,
    Value<DateTime?>? cacheExpiresAt,
    Value<int>? rowid,
  }) {
    return AttachmentsCompanion(
      attachmentId: attachmentId ?? this.attachmentId,
      messageId: messageId ?? this.messageId,
      encryptedDescriptor: encryptedDescriptor ?? this.encryptedDescriptor,
      transferState: transferState ?? this.transferState,
      boundedCacheHandleCiphertext:
          boundedCacheHandleCiphertext ?? this.boundedCacheHandleCiphertext,
      cacheExpiresAt: cacheExpiresAt ?? this.cacheExpiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (attachmentId.present) {
      map['attachment_id'] = Variable<String>(attachmentId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (encryptedDescriptor.present) {
      map['encrypted_descriptor'] = Variable<Uint8List>(
        encryptedDescriptor.value,
      );
    }
    if (transferState.present) {
      map['transfer_state'] = Variable<int>(transferState.value);
    }
    if (boundedCacheHandleCiphertext.present) {
      map['bounded_cache_handle_ciphertext'] = Variable<Uint8List>(
        boundedCacheHandleCiphertext.value,
      );
    }
    if (cacheExpiresAt.present) {
      map['cache_expires_at'] = Variable<DateTime>(cacheExpiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentsCompanion(')
          ..write('attachmentId: $attachmentId, ')
          ..write('messageId: $messageId, ')
          ..write('encryptedDescriptor: $encryptedDescriptor, ')
          ..write('transferState: $transferState, ')
          ..write(
            'boundedCacheHandleCiphertext: $boundedCacheHandleCiphertext, ',
          )
          ..write('cacheExpiresAt: $cacheExpiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InboxEnvelopesTable extends InboxEnvelopes
    with TableInfo<$InboxEnvelopesTable, InboxEnvelope> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InboxEnvelopesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _envelopeIdMeta = const VerificationMeta(
    'envelopeId',
  );
  @override
  late final GeneratedColumn<String> envelopeId = GeneratedColumn<String>(
    'envelope_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    check: () => ComparableExpr(sequence).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _envelopeCiphertextMeta =
      const VerificationMeta('envelopeCiphertext');
  @override
  late final GeneratedColumn<Uint8List> envelopeCiphertext =
      GeneratedColumn<Uint8List>(
        'envelope_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _processingStateMeta = const VerificationMeta(
    'processingState',
  );
  @override
  late final GeneratedColumn<int> processingState = GeneratedColumn<int>(
    'processing_state',
    aliasedName,
    false,
    check: () => ComparableExpr(processingState).isBetweenValues(0, 5),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readyToAcknowledgeMeta =
      const VerificationMeta('readyToAcknowledge');
  @override
  late final GeneratedColumn<bool> readyToAcknowledge = GeneratedColumn<bool>(
    'ready_to_acknowledge',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("ready_to_acknowledge" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _opaqueEventIdMeta = const VerificationMeta(
    'opaqueEventId',
  );
  @override
  late final GeneratedColumn<String> opaqueEventId = GeneratedColumn<String>(
    'opaque_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dependencyClassMeta = const VerificationMeta(
    'dependencyClass',
  );
  @override
  late final GeneratedColumn<int> dependencyClass = GeneratedColumn<int>(
    'dependency_class',
    aliasedName,
    true,
    check: () =>
        dependencyClass.isNull() |
        ComparableExpr(dependencyClass).isBetweenValues(0, 1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    check: () => ComparableExpr(attemptCount).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    envelopeId,
    sequence,
    envelopeCiphertext,
    processingState,
    readyToAcknowledge,
    opaqueEventId,
    dependencyClass,
    attemptCount,
    nextAttemptAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inbox_envelopes';
  @override
  VerificationContext validateIntegrity(
    Insertable<InboxEnvelope> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('envelope_id')) {
      context.handle(
        _envelopeIdMeta,
        envelopeId.isAcceptableOrUnknown(data['envelope_id']!, _envelopeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_envelopeIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('envelope_ciphertext')) {
      context.handle(
        _envelopeCiphertextMeta,
        envelopeCiphertext.isAcceptableOrUnknown(
          data['envelope_ciphertext']!,
          _envelopeCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_envelopeCiphertextMeta);
    }
    if (data.containsKey('processing_state')) {
      context.handle(
        _processingStateMeta,
        processingState.isAcceptableOrUnknown(
          data['processing_state']!,
          _processingStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_processingStateMeta);
    }
    if (data.containsKey('ready_to_acknowledge')) {
      context.handle(
        _readyToAcknowledgeMeta,
        readyToAcknowledge.isAcceptableOrUnknown(
          data['ready_to_acknowledge']!,
          _readyToAcknowledgeMeta,
        ),
      );
    }
    if (data.containsKey('opaque_event_id')) {
      context.handle(
        _opaqueEventIdMeta,
        opaqueEventId.isAcceptableOrUnknown(
          data['opaque_event_id']!,
          _opaqueEventIdMeta,
        ),
      );
    }
    if (data.containsKey('dependency_class')) {
      context.handle(
        _dependencyClassMeta,
        dependencyClass.isAcceptableOrUnknown(
          data['dependency_class']!,
          _dependencyClassMeta,
        ),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {envelopeId};
  @override
  InboxEnvelope map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InboxEnvelope(
      envelopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}envelope_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      envelopeCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}envelope_ciphertext'],
      )!,
      processingState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}processing_state'],
      )!,
      readyToAcknowledge: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}ready_to_acknowledge'],
      )!,
      opaqueEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opaque_event_id'],
      ),
      dependencyClass: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dependency_class'],
      ),
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
    );
  }

  @override
  $InboxEnvelopesTable createAlias(String alias) {
    return $InboxEnvelopesTable(attachedDatabase, alias);
  }
}

class InboxEnvelope extends DataClass implements Insertable<InboxEnvelope> {
  final String envelopeId;
  final int sequence;
  final Uint8List envelopeCiphertext;
  final int processingState;
  final bool readyToAcknowledge;
  final String? opaqueEventId;
  final int? dependencyClass;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  const InboxEnvelope({
    required this.envelopeId,
    required this.sequence,
    required this.envelopeCiphertext,
    required this.processingState,
    required this.readyToAcknowledge,
    this.opaqueEventId,
    this.dependencyClass,
    required this.attemptCount,
    this.nextAttemptAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['envelope_id'] = Variable<String>(envelopeId);
    map['sequence'] = Variable<int>(sequence);
    map['envelope_ciphertext'] = Variable<Uint8List>(envelopeCiphertext);
    map['processing_state'] = Variable<int>(processingState);
    map['ready_to_acknowledge'] = Variable<bool>(readyToAcknowledge);
    if (!nullToAbsent || opaqueEventId != null) {
      map['opaque_event_id'] = Variable<String>(opaqueEventId);
    }
    if (!nullToAbsent || dependencyClass != null) {
      map['dependency_class'] = Variable<int>(dependencyClass);
    }
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    return map;
  }

  InboxEnvelopesCompanion toCompanion(bool nullToAbsent) {
    return InboxEnvelopesCompanion(
      envelopeId: Value(envelopeId),
      sequence: Value(sequence),
      envelopeCiphertext: Value(envelopeCiphertext),
      processingState: Value(processingState),
      readyToAcknowledge: Value(readyToAcknowledge),
      opaqueEventId: opaqueEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(opaqueEventId),
      dependencyClass: dependencyClass == null && nullToAbsent
          ? const Value.absent()
          : Value(dependencyClass),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
    );
  }

  factory InboxEnvelope.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InboxEnvelope(
      envelopeId: serializer.fromJson<String>(json['envelopeId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      envelopeCiphertext: serializer.fromJson<Uint8List>(
        json['envelopeCiphertext'],
      ),
      processingState: serializer.fromJson<int>(json['processingState']),
      readyToAcknowledge: serializer.fromJson<bool>(json['readyToAcknowledge']),
      opaqueEventId: serializer.fromJson<String?>(json['opaqueEventId']),
      dependencyClass: serializer.fromJson<int?>(json['dependencyClass']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'envelopeId': serializer.toJson<String>(envelopeId),
      'sequence': serializer.toJson<int>(sequence),
      'envelopeCiphertext': serializer.toJson<Uint8List>(envelopeCiphertext),
      'processingState': serializer.toJson<int>(processingState),
      'readyToAcknowledge': serializer.toJson<bool>(readyToAcknowledge),
      'opaqueEventId': serializer.toJson<String?>(opaqueEventId),
      'dependencyClass': serializer.toJson<int?>(dependencyClass),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
    };
  }

  InboxEnvelope copyWith({
    String? envelopeId,
    int? sequence,
    Uint8List? envelopeCiphertext,
    int? processingState,
    bool? readyToAcknowledge,
    Value<String?> opaqueEventId = const Value.absent(),
    Value<int?> dependencyClass = const Value.absent(),
    int? attemptCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
  }) => InboxEnvelope(
    envelopeId: envelopeId ?? this.envelopeId,
    sequence: sequence ?? this.sequence,
    envelopeCiphertext: envelopeCiphertext ?? this.envelopeCiphertext,
    processingState: processingState ?? this.processingState,
    readyToAcknowledge: readyToAcknowledge ?? this.readyToAcknowledge,
    opaqueEventId: opaqueEventId.present
        ? opaqueEventId.value
        : this.opaqueEventId,
    dependencyClass: dependencyClass.present
        ? dependencyClass.value
        : this.dependencyClass,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
  );
  InboxEnvelope copyWithCompanion(InboxEnvelopesCompanion data) {
    return InboxEnvelope(
      envelopeId: data.envelopeId.present
          ? data.envelopeId.value
          : this.envelopeId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      envelopeCiphertext: data.envelopeCiphertext.present
          ? data.envelopeCiphertext.value
          : this.envelopeCiphertext,
      processingState: data.processingState.present
          ? data.processingState.value
          : this.processingState,
      readyToAcknowledge: data.readyToAcknowledge.present
          ? data.readyToAcknowledge.value
          : this.readyToAcknowledge,
      opaqueEventId: data.opaqueEventId.present
          ? data.opaqueEventId.value
          : this.opaqueEventId,
      dependencyClass: data.dependencyClass.present
          ? data.dependencyClass.value
          : this.dependencyClass,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InboxEnvelope(')
          ..write('envelopeId: $envelopeId, ')
          ..write('sequence: $sequence, ')
          ..write('envelopeCiphertext: $envelopeCiphertext, ')
          ..write('processingState: $processingState, ')
          ..write('readyToAcknowledge: $readyToAcknowledge, ')
          ..write('opaqueEventId: $opaqueEventId, ')
          ..write('dependencyClass: $dependencyClass, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    envelopeId,
    sequence,
    $driftBlobEquality.hash(envelopeCiphertext),
    processingState,
    readyToAcknowledge,
    opaqueEventId,
    dependencyClass,
    attemptCount,
    nextAttemptAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InboxEnvelope &&
          other.envelopeId == this.envelopeId &&
          other.sequence == this.sequence &&
          $driftBlobEquality.equals(
            other.envelopeCiphertext,
            this.envelopeCiphertext,
          ) &&
          other.processingState == this.processingState &&
          other.readyToAcknowledge == this.readyToAcknowledge &&
          other.opaqueEventId == this.opaqueEventId &&
          other.dependencyClass == this.dependencyClass &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt);
}

class InboxEnvelopesCompanion extends UpdateCompanion<InboxEnvelope> {
  final Value<String> envelopeId;
  final Value<int> sequence;
  final Value<Uint8List> envelopeCiphertext;
  final Value<int> processingState;
  final Value<bool> readyToAcknowledge;
  final Value<String?> opaqueEventId;
  final Value<int?> dependencyClass;
  final Value<int> attemptCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<int> rowid;
  const InboxEnvelopesCompanion({
    this.envelopeId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.envelopeCiphertext = const Value.absent(),
    this.processingState = const Value.absent(),
    this.readyToAcknowledge = const Value.absent(),
    this.opaqueEventId = const Value.absent(),
    this.dependencyClass = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InboxEnvelopesCompanion.insert({
    required String envelopeId,
    required int sequence,
    required Uint8List envelopeCiphertext,
    required int processingState,
    this.readyToAcknowledge = const Value.absent(),
    this.opaqueEventId = const Value.absent(),
    this.dependencyClass = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : envelopeId = Value(envelopeId),
       sequence = Value(sequence),
       envelopeCiphertext = Value(envelopeCiphertext),
       processingState = Value(processingState);
  static Insertable<InboxEnvelope> custom({
    Expression<String>? envelopeId,
    Expression<int>? sequence,
    Expression<Uint8List>? envelopeCiphertext,
    Expression<int>? processingState,
    Expression<bool>? readyToAcknowledge,
    Expression<String>? opaqueEventId,
    Expression<int>? dependencyClass,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (envelopeId != null) 'envelope_id': envelopeId,
      if (sequence != null) 'sequence': sequence,
      if (envelopeCiphertext != null) 'envelope_ciphertext': envelopeCiphertext,
      if (processingState != null) 'processing_state': processingState,
      if (readyToAcknowledge != null)
        'ready_to_acknowledge': readyToAcknowledge,
      if (opaqueEventId != null) 'opaque_event_id': opaqueEventId,
      if (dependencyClass != null) 'dependency_class': dependencyClass,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InboxEnvelopesCompanion copyWith({
    Value<String>? envelopeId,
    Value<int>? sequence,
    Value<Uint8List>? envelopeCiphertext,
    Value<int>? processingState,
    Value<bool>? readyToAcknowledge,
    Value<String?>? opaqueEventId,
    Value<int?>? dependencyClass,
    Value<int>? attemptCount,
    Value<DateTime?>? nextAttemptAt,
    Value<int>? rowid,
  }) {
    return InboxEnvelopesCompanion(
      envelopeId: envelopeId ?? this.envelopeId,
      sequence: sequence ?? this.sequence,
      envelopeCiphertext: envelopeCiphertext ?? this.envelopeCiphertext,
      processingState: processingState ?? this.processingState,
      readyToAcknowledge: readyToAcknowledge ?? this.readyToAcknowledge,
      opaqueEventId: opaqueEventId ?? this.opaqueEventId,
      dependencyClass: dependencyClass ?? this.dependencyClass,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (envelopeId.present) {
      map['envelope_id'] = Variable<String>(envelopeId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (envelopeCiphertext.present) {
      map['envelope_ciphertext'] = Variable<Uint8List>(
        envelopeCiphertext.value,
      );
    }
    if (processingState.present) {
      map['processing_state'] = Variable<int>(processingState.value);
    }
    if (readyToAcknowledge.present) {
      map['ready_to_acknowledge'] = Variable<bool>(readyToAcknowledge.value);
    }
    if (opaqueEventId.present) {
      map['opaque_event_id'] = Variable<String>(opaqueEventId.value);
    }
    if (dependencyClass.present) {
      map['dependency_class'] = Variable<int>(dependencyClass.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InboxEnvelopesCompanion(')
          ..write('envelopeId: $envelopeId, ')
          ..write('sequence: $sequence, ')
          ..write('envelopeCiphertext: $envelopeCiphertext, ')
          ..write('processingState: $processingState, ')
          ..write('readyToAcknowledge: $readyToAcknowledge, ')
          ..write('opaqueEventId: $opaqueEventId, ')
          ..write('dependencyClass: $dependencyClass, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxOperationsTable extends OutboxOperations
    with TableInfo<$OutboxOperationsTable, OutboxOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recipientDeviceIdMeta = const VerificationMeta(
    'recipientDeviceId',
  );
  @override
  late final GeneratedColumn<String> recipientDeviceId =
      GeneratedColumn<String>(
        'recipient_device_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _recipientUserIdMeta = const VerificationMeta(
    'recipientUserId',
  );
  @override
  late final GeneratedColumn<String> recipientUserId = GeneratedColumn<String>(
    'recipient_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _batchIndexMeta = const VerificationMeta(
    'batchIndex',
  );
  @override
  late final GeneratedColumn<int> batchIndex = GeneratedColumn<int>(
    'batch_index',
    aliasedName,
    false,
    check: () => ComparableExpr(batchIndex).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exactRecipientCiphertextMeta =
      const VerificationMeta('exactRecipientCiphertext');
  @override
  late final GeneratedColumn<Uint8List> exactRecipientCiphertext =
      GeneratedColumn<Uint8List>(
        'exact_recipient_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _attemptStateMeta = const VerificationMeta(
    'attemptState',
  );
  @override
  late final GeneratedColumn<int> attemptState = GeneratedColumn<int>(
    'attempt_state',
    aliasedName,
    false,
    check: () => ComparableExpr(attemptState).isBetweenValues(0, 6),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    check: () => ComparableExpr(attemptCount).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _terminalAtMeta = const VerificationMeta(
    'terminalAt',
  );
  @override
  late final GeneratedColumn<DateTime> terminalAt = GeneratedColumn<DateTime>(
    'terminal_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    eventId,
    recipientDeviceId,
    recipientUserId,
    batchIndex,
    exactRecipientCiphertext,
    attemptState,
    attemptCount,
    nextAttemptAt,
    lastAttemptAt,
    terminalAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('recipient_device_id')) {
      context.handle(
        _recipientDeviceIdMeta,
        recipientDeviceId.isAcceptableOrUnknown(
          data['recipient_device_id']!,
          _recipientDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recipientDeviceIdMeta);
    }
    if (data.containsKey('recipient_user_id')) {
      context.handle(
        _recipientUserIdMeta,
        recipientUserId.isAcceptableOrUnknown(
          data['recipient_user_id']!,
          _recipientUserIdMeta,
        ),
      );
    }
    if (data.containsKey('batch_index')) {
      context.handle(
        _batchIndexMeta,
        batchIndex.isAcceptableOrUnknown(data['batch_index']!, _batchIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIndexMeta);
    }
    if (data.containsKey('exact_recipient_ciphertext')) {
      context.handle(
        _exactRecipientCiphertextMeta,
        exactRecipientCiphertext.isAcceptableOrUnknown(
          data['exact_recipient_ciphertext']!,
          _exactRecipientCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exactRecipientCiphertextMeta);
    }
    if (data.containsKey('attempt_state')) {
      context.handle(
        _attemptStateMeta,
        attemptState.isAcceptableOrUnknown(
          data['attempt_state']!,
          _attemptStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attemptStateMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('terminal_at')) {
      context.handle(
        _terminalAtMeta,
        terminalAt.isAcceptableOrUnknown(data['terminal_at']!, _terminalAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId, recipientDeviceId};
  @override
  OutboxOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxOperation(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      recipientDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient_device_id'],
      )!,
      recipientUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient_user_id'],
      )!,
      batchIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}batch_index'],
      )!,
      exactRecipientCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}exact_recipient_ciphertext'],
      )!,
      attemptState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_state'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
      terminalAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}terminal_at'],
      ),
    );
  }

  @override
  $OutboxOperationsTable createAlias(String alias) {
    return $OutboxOperationsTable(attachedDatabase, alias);
  }
}

class OutboxOperation extends DataClass implements Insertable<OutboxOperation> {
  final String operationId;
  final String eventId;
  final String recipientDeviceId;
  final String recipientUserId;
  final int batchIndex;
  final Uint8List exactRecipientCiphertext;
  final int attemptState;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final DateTime? lastAttemptAt;
  final DateTime? terminalAt;
  const OutboxOperation({
    required this.operationId,
    required this.eventId,
    required this.recipientDeviceId,
    required this.recipientUserId,
    required this.batchIndex,
    required this.exactRecipientCiphertext,
    required this.attemptState,
    required this.attemptCount,
    this.nextAttemptAt,
    this.lastAttemptAt,
    this.terminalAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['event_id'] = Variable<String>(eventId);
    map['recipient_device_id'] = Variable<String>(recipientDeviceId);
    map['recipient_user_id'] = Variable<String>(recipientUserId);
    map['batch_index'] = Variable<int>(batchIndex);
    map['exact_recipient_ciphertext'] = Variable<Uint8List>(
      exactRecipientCiphertext,
    );
    map['attempt_state'] = Variable<int>(attemptState);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || terminalAt != null) {
      map['terminal_at'] = Variable<DateTime>(terminalAt);
    }
    return map;
  }

  OutboxOperationsCompanion toCompanion(bool nullToAbsent) {
    return OutboxOperationsCompanion(
      operationId: Value(operationId),
      eventId: Value(eventId),
      recipientDeviceId: Value(recipientDeviceId),
      recipientUserId: Value(recipientUserId),
      batchIndex: Value(batchIndex),
      exactRecipientCiphertext: Value(exactRecipientCiphertext),
      attemptState: Value(attemptState),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      terminalAt: terminalAt == null && nullToAbsent
          ? const Value.absent()
          : Value(terminalAt),
    );
  }

  factory OutboxOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxOperation(
      operationId: serializer.fromJson<String>(json['operationId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      recipientDeviceId: serializer.fromJson<String>(json['recipientDeviceId']),
      recipientUserId: serializer.fromJson<String>(json['recipientUserId']),
      batchIndex: serializer.fromJson<int>(json['batchIndex']),
      exactRecipientCiphertext: serializer.fromJson<Uint8List>(
        json['exactRecipientCiphertext'],
      ),
      attemptState: serializer.fromJson<int>(json['attemptState']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      terminalAt: serializer.fromJson<DateTime?>(json['terminalAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'eventId': serializer.toJson<String>(eventId),
      'recipientDeviceId': serializer.toJson<String>(recipientDeviceId),
      'recipientUserId': serializer.toJson<String>(recipientUserId),
      'batchIndex': serializer.toJson<int>(batchIndex),
      'exactRecipientCiphertext': serializer.toJson<Uint8List>(
        exactRecipientCiphertext,
      ),
      'attemptState': serializer.toJson<int>(attemptState),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'terminalAt': serializer.toJson<DateTime?>(terminalAt),
    };
  }

  OutboxOperation copyWith({
    String? operationId,
    String? eventId,
    String? recipientDeviceId,
    String? recipientUserId,
    int? batchIndex,
    Uint8List? exactRecipientCiphertext,
    int? attemptState,
    int? attemptCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    Value<DateTime?> terminalAt = const Value.absent(),
  }) => OutboxOperation(
    operationId: operationId ?? this.operationId,
    eventId: eventId ?? this.eventId,
    recipientDeviceId: recipientDeviceId ?? this.recipientDeviceId,
    recipientUserId: recipientUserId ?? this.recipientUserId,
    batchIndex: batchIndex ?? this.batchIndex,
    exactRecipientCiphertext:
        exactRecipientCiphertext ?? this.exactRecipientCiphertext,
    attemptState: attemptState ?? this.attemptState,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    terminalAt: terminalAt.present ? terminalAt.value : this.terminalAt,
  );
  OutboxOperation copyWithCompanion(OutboxOperationsCompanion data) {
    return OutboxOperation(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      recipientDeviceId: data.recipientDeviceId.present
          ? data.recipientDeviceId.value
          : this.recipientDeviceId,
      recipientUserId: data.recipientUserId.present
          ? data.recipientUserId.value
          : this.recipientUserId,
      batchIndex: data.batchIndex.present
          ? data.batchIndex.value
          : this.batchIndex,
      exactRecipientCiphertext: data.exactRecipientCiphertext.present
          ? data.exactRecipientCiphertext.value
          : this.exactRecipientCiphertext,
      attemptState: data.attemptState.present
          ? data.attemptState.value
          : this.attemptState,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      terminalAt: data.terminalAt.present
          ? data.terminalAt.value
          : this.terminalAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxOperation(')
          ..write('operationId: $operationId, ')
          ..write('eventId: $eventId, ')
          ..write('recipientDeviceId: $recipientDeviceId, ')
          ..write('recipientUserId: $recipientUserId, ')
          ..write('batchIndex: $batchIndex, ')
          ..write('exactRecipientCiphertext: $exactRecipientCiphertext, ')
          ..write('attemptState: $attemptState, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('terminalAt: $terminalAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    eventId,
    recipientDeviceId,
    recipientUserId,
    batchIndex,
    $driftBlobEquality.hash(exactRecipientCiphertext),
    attemptState,
    attemptCount,
    nextAttemptAt,
    lastAttemptAt,
    terminalAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxOperation &&
          other.operationId == this.operationId &&
          other.eventId == this.eventId &&
          other.recipientDeviceId == this.recipientDeviceId &&
          other.recipientUserId == this.recipientUserId &&
          other.batchIndex == this.batchIndex &&
          $driftBlobEquality.equals(
            other.exactRecipientCiphertext,
            this.exactRecipientCiphertext,
          ) &&
          other.attemptState == this.attemptState &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.terminalAt == this.terminalAt);
}

class OutboxOperationsCompanion extends UpdateCompanion<OutboxOperation> {
  final Value<String> operationId;
  final Value<String> eventId;
  final Value<String> recipientDeviceId;
  final Value<String> recipientUserId;
  final Value<int> batchIndex;
  final Value<Uint8List> exactRecipientCiphertext;
  final Value<int> attemptState;
  final Value<int> attemptCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<DateTime?> lastAttemptAt;
  final Value<DateTime?> terminalAt;
  final Value<int> rowid;
  const OutboxOperationsCompanion({
    this.operationId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.recipientDeviceId = const Value.absent(),
    this.recipientUserId = const Value.absent(),
    this.batchIndex = const Value.absent(),
    this.exactRecipientCiphertext = const Value.absent(),
    this.attemptState = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.terminalAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxOperationsCompanion.insert({
    required String operationId,
    required String eventId,
    required String recipientDeviceId,
    this.recipientUserId = const Value.absent(),
    required int batchIndex,
    required Uint8List exactRecipientCiphertext,
    required int attemptState,
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.terminalAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       eventId = Value(eventId),
       recipientDeviceId = Value(recipientDeviceId),
       batchIndex = Value(batchIndex),
       exactRecipientCiphertext = Value(exactRecipientCiphertext),
       attemptState = Value(attemptState);
  static Insertable<OutboxOperation> custom({
    Expression<String>? operationId,
    Expression<String>? eventId,
    Expression<String>? recipientDeviceId,
    Expression<String>? recipientUserId,
    Expression<int>? batchIndex,
    Expression<Uint8List>? exactRecipientCiphertext,
    Expression<int>? attemptState,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<DateTime>? lastAttemptAt,
    Expression<DateTime>? terminalAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (eventId != null) 'event_id': eventId,
      if (recipientDeviceId != null) 'recipient_device_id': recipientDeviceId,
      if (recipientUserId != null) 'recipient_user_id': recipientUserId,
      if (batchIndex != null) 'batch_index': batchIndex,
      if (exactRecipientCiphertext != null)
        'exact_recipient_ciphertext': exactRecipientCiphertext,
      if (attemptState != null) 'attempt_state': attemptState,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (terminalAt != null) 'terminal_at': terminalAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxOperationsCompanion copyWith({
    Value<String>? operationId,
    Value<String>? eventId,
    Value<String>? recipientDeviceId,
    Value<String>? recipientUserId,
    Value<int>? batchIndex,
    Value<Uint8List>? exactRecipientCiphertext,
    Value<int>? attemptState,
    Value<int>? attemptCount,
    Value<DateTime?>? nextAttemptAt,
    Value<DateTime?>? lastAttemptAt,
    Value<DateTime?>? terminalAt,
    Value<int>? rowid,
  }) {
    return OutboxOperationsCompanion(
      operationId: operationId ?? this.operationId,
      eventId: eventId ?? this.eventId,
      recipientDeviceId: recipientDeviceId ?? this.recipientDeviceId,
      recipientUserId: recipientUserId ?? this.recipientUserId,
      batchIndex: batchIndex ?? this.batchIndex,
      exactRecipientCiphertext:
          exactRecipientCiphertext ?? this.exactRecipientCiphertext,
      attemptState: attemptState ?? this.attemptState,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      terminalAt: terminalAt ?? this.terminalAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (recipientDeviceId.present) {
      map['recipient_device_id'] = Variable<String>(recipientDeviceId.value);
    }
    if (recipientUserId.present) {
      map['recipient_user_id'] = Variable<String>(recipientUserId.value);
    }
    if (batchIndex.present) {
      map['batch_index'] = Variable<int>(batchIndex.value);
    }
    if (exactRecipientCiphertext.present) {
      map['exact_recipient_ciphertext'] = Variable<Uint8List>(
        exactRecipientCiphertext.value,
      );
    }
    if (attemptState.present) {
      map['attempt_state'] = Variable<int>(attemptState.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (terminalAt.present) {
      map['terminal_at'] = Variable<DateTime>(terminalAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxOperationsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('eventId: $eventId, ')
          ..write('recipientDeviceId: $recipientDeviceId, ')
          ..write('recipientUserId: $recipientUserId, ')
          ..write('batchIndex: $batchIndex, ')
          ..write('exactRecipientCiphertext: $exactRecipientCiphertext, ')
          ..write('attemptState: $attemptState, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('terminalAt: $terminalAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InboxEventDeduplicationsTable extends InboxEventDeduplications
    with TableInfo<$InboxEventDeduplicationsTable, InboxEventDeduplication> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InboxEventDeduplicationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _opaqueEventIdMeta = const VerificationMeta(
    'opaqueEventId',
  );
  @override
  late final GeneratedColumn<String> opaqueEventId = GeneratedColumn<String>(
    'opaque_event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstEnvelopeIdMeta = const VerificationMeta(
    'firstEnvelopeId',
  );
  @override
  late final GeneratedColumn<String> firstEnvelopeId = GeneratedColumn<String>(
    'first_envelope_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dependencyClassMeta = const VerificationMeta(
    'dependencyClass',
  );
  @override
  late final GeneratedColumn<int> dependencyClass = GeneratedColumn<int>(
    'dependency_class',
    aliasedName,
    false,
    check: () => ComparableExpr(dependencyClass).isBetweenValues(0, 1),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _committedAtMeta = const VerificationMeta(
    'committedAt',
  );
  @override
  late final GeneratedColumn<DateTime> committedAt = GeneratedColumn<DateTime>(
    'committed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    opaqueEventId,
    firstEnvelopeId,
    dependencyClass,
    committedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inbox_event_deduplication';
  @override
  VerificationContext validateIntegrity(
    Insertable<InboxEventDeduplication> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('opaque_event_id')) {
      context.handle(
        _opaqueEventIdMeta,
        opaqueEventId.isAcceptableOrUnknown(
          data['opaque_event_id']!,
          _opaqueEventIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_opaqueEventIdMeta);
    }
    if (data.containsKey('first_envelope_id')) {
      context.handle(
        _firstEnvelopeIdMeta,
        firstEnvelopeId.isAcceptableOrUnknown(
          data['first_envelope_id']!,
          _firstEnvelopeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstEnvelopeIdMeta);
    }
    if (data.containsKey('dependency_class')) {
      context.handle(
        _dependencyClassMeta,
        dependencyClass.isAcceptableOrUnknown(
          data['dependency_class']!,
          _dependencyClassMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dependencyClassMeta);
    }
    if (data.containsKey('committed_at')) {
      context.handle(
        _committedAtMeta,
        committedAt.isAcceptableOrUnknown(
          data['committed_at']!,
          _committedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {opaqueEventId};
  @override
  InboxEventDeduplication map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InboxEventDeduplication(
      opaqueEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opaque_event_id'],
      )!,
      firstEnvelopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_envelope_id'],
      )!,
      dependencyClass: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dependency_class'],
      )!,
      committedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}committed_at'],
      )!,
    );
  }

  @override
  $InboxEventDeduplicationsTable createAlias(String alias) {
    return $InboxEventDeduplicationsTable(attachedDatabase, alias);
  }
}

class InboxEventDeduplication extends DataClass
    implements Insertable<InboxEventDeduplication> {
  final String opaqueEventId;
  final String firstEnvelopeId;
  final int dependencyClass;
  final DateTime committedAt;
  const InboxEventDeduplication({
    required this.opaqueEventId,
    required this.firstEnvelopeId,
    required this.dependencyClass,
    required this.committedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['opaque_event_id'] = Variable<String>(opaqueEventId);
    map['first_envelope_id'] = Variable<String>(firstEnvelopeId);
    map['dependency_class'] = Variable<int>(dependencyClass);
    map['committed_at'] = Variable<DateTime>(committedAt);
    return map;
  }

  InboxEventDeduplicationsCompanion toCompanion(bool nullToAbsent) {
    return InboxEventDeduplicationsCompanion(
      opaqueEventId: Value(opaqueEventId),
      firstEnvelopeId: Value(firstEnvelopeId),
      dependencyClass: Value(dependencyClass),
      committedAt: Value(committedAt),
    );
  }

  factory InboxEventDeduplication.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InboxEventDeduplication(
      opaqueEventId: serializer.fromJson<String>(json['opaqueEventId']),
      firstEnvelopeId: serializer.fromJson<String>(json['firstEnvelopeId']),
      dependencyClass: serializer.fromJson<int>(json['dependencyClass']),
      committedAt: serializer.fromJson<DateTime>(json['committedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'opaqueEventId': serializer.toJson<String>(opaqueEventId),
      'firstEnvelopeId': serializer.toJson<String>(firstEnvelopeId),
      'dependencyClass': serializer.toJson<int>(dependencyClass),
      'committedAt': serializer.toJson<DateTime>(committedAt),
    };
  }

  InboxEventDeduplication copyWith({
    String? opaqueEventId,
    String? firstEnvelopeId,
    int? dependencyClass,
    DateTime? committedAt,
  }) => InboxEventDeduplication(
    opaqueEventId: opaqueEventId ?? this.opaqueEventId,
    firstEnvelopeId: firstEnvelopeId ?? this.firstEnvelopeId,
    dependencyClass: dependencyClass ?? this.dependencyClass,
    committedAt: committedAt ?? this.committedAt,
  );
  InboxEventDeduplication copyWithCompanion(
    InboxEventDeduplicationsCompanion data,
  ) {
    return InboxEventDeduplication(
      opaqueEventId: data.opaqueEventId.present
          ? data.opaqueEventId.value
          : this.opaqueEventId,
      firstEnvelopeId: data.firstEnvelopeId.present
          ? data.firstEnvelopeId.value
          : this.firstEnvelopeId,
      dependencyClass: data.dependencyClass.present
          ? data.dependencyClass.value
          : this.dependencyClass,
      committedAt: data.committedAt.present
          ? data.committedAt.value
          : this.committedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InboxEventDeduplication(')
          ..write('opaqueEventId: $opaqueEventId, ')
          ..write('firstEnvelopeId: $firstEnvelopeId, ')
          ..write('dependencyClass: $dependencyClass, ')
          ..write('committedAt: $committedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(opaqueEventId, firstEnvelopeId, dependencyClass, committedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InboxEventDeduplication &&
          other.opaqueEventId == this.opaqueEventId &&
          other.firstEnvelopeId == this.firstEnvelopeId &&
          other.dependencyClass == this.dependencyClass &&
          other.committedAt == this.committedAt);
}

class InboxEventDeduplicationsCompanion
    extends UpdateCompanion<InboxEventDeduplication> {
  final Value<String> opaqueEventId;
  final Value<String> firstEnvelopeId;
  final Value<int> dependencyClass;
  final Value<DateTime> committedAt;
  final Value<int> rowid;
  const InboxEventDeduplicationsCompanion({
    this.opaqueEventId = const Value.absent(),
    this.firstEnvelopeId = const Value.absent(),
    this.dependencyClass = const Value.absent(),
    this.committedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InboxEventDeduplicationsCompanion.insert({
    required String opaqueEventId,
    required String firstEnvelopeId,
    required int dependencyClass,
    this.committedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : opaqueEventId = Value(opaqueEventId),
       firstEnvelopeId = Value(firstEnvelopeId),
       dependencyClass = Value(dependencyClass);
  static Insertable<InboxEventDeduplication> custom({
    Expression<String>? opaqueEventId,
    Expression<String>? firstEnvelopeId,
    Expression<int>? dependencyClass,
    Expression<DateTime>? committedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (opaqueEventId != null) 'opaque_event_id': opaqueEventId,
      if (firstEnvelopeId != null) 'first_envelope_id': firstEnvelopeId,
      if (dependencyClass != null) 'dependency_class': dependencyClass,
      if (committedAt != null) 'committed_at': committedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InboxEventDeduplicationsCompanion copyWith({
    Value<String>? opaqueEventId,
    Value<String>? firstEnvelopeId,
    Value<int>? dependencyClass,
    Value<DateTime>? committedAt,
    Value<int>? rowid,
  }) {
    return InboxEventDeduplicationsCompanion(
      opaqueEventId: opaqueEventId ?? this.opaqueEventId,
      firstEnvelopeId: firstEnvelopeId ?? this.firstEnvelopeId,
      dependencyClass: dependencyClass ?? this.dependencyClass,
      committedAt: committedAt ?? this.committedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (opaqueEventId.present) {
      map['opaque_event_id'] = Variable<String>(opaqueEventId.value);
    }
    if (firstEnvelopeId.present) {
      map['first_envelope_id'] = Variable<String>(firstEnvelopeId.value);
    }
    if (dependencyClass.present) {
      map['dependency_class'] = Variable<int>(dependencyClass.value);
    }
    if (committedAt.present) {
      map['committed_at'] = Variable<DateTime>(committedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InboxEventDeduplicationsCompanion(')
          ..write('opaqueEventId: $opaqueEventId, ')
          ..write('firstEnvelopeId: $firstEnvelopeId, ')
          ..write('dependencyClass: $dependencyClass, ')
          ..write('committedAt: $committedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StaleDeviceRefreshRequestsTable extends StaleDeviceRefreshRequests
    with
        TableInfo<$StaleDeviceRefreshRequestsTable, StaleDeviceRefreshRequest> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StaleDeviceRefreshRequestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _staleDeviceIdMeta = const VerificationMeta(
    'staleDeviceId',
  );
  @override
  late final GeneratedColumn<String> staleDeviceId = GeneratedColumn<String>(
    'stale_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<int> state = GeneratedColumn<int>(
    'state',
    aliasedName,
    false,
    check: () => ComparableExpr(state).isBetweenValues(0, 3),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    check: () => ComparableExpr(attemptCount).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    staleDeviceId,
    state,
    attemptCount,
    nextAttemptAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stale_device_refresh_requests';
  @override
  VerificationContext validateIntegrity(
    Insertable<StaleDeviceRefreshRequest> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('stale_device_id')) {
      context.handle(
        _staleDeviceIdMeta,
        staleDeviceId.isAcceptableOrUnknown(
          data['stale_device_id']!,
          _staleDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_staleDeviceIdMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, staleDeviceId};
  @override
  StaleDeviceRefreshRequest map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StaleDeviceRefreshRequest(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      staleDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stale_device_id'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}state'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
    );
  }

  @override
  $StaleDeviceRefreshRequestsTable createAlias(String alias) {
    return $StaleDeviceRefreshRequestsTable(attachedDatabase, alias);
  }
}

class StaleDeviceRefreshRequest extends DataClass
    implements Insertable<StaleDeviceRefreshRequest> {
  final String userId;
  final String staleDeviceId;
  final int state;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  const StaleDeviceRefreshRequest({
    required this.userId,
    required this.staleDeviceId,
    required this.state,
    required this.attemptCount,
    this.nextAttemptAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['stale_device_id'] = Variable<String>(staleDeviceId);
    map['state'] = Variable<int>(state);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    return map;
  }

  StaleDeviceRefreshRequestsCompanion toCompanion(bool nullToAbsent) {
    return StaleDeviceRefreshRequestsCompanion(
      userId: Value(userId),
      staleDeviceId: Value(staleDeviceId),
      state: Value(state),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
    );
  }

  factory StaleDeviceRefreshRequest.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StaleDeviceRefreshRequest(
      userId: serializer.fromJson<String>(json['userId']),
      staleDeviceId: serializer.fromJson<String>(json['staleDeviceId']),
      state: serializer.fromJson<int>(json['state']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'staleDeviceId': serializer.toJson<String>(staleDeviceId),
      'state': serializer.toJson<int>(state),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
    };
  }

  StaleDeviceRefreshRequest copyWith({
    String? userId,
    String? staleDeviceId,
    int? state,
    int? attemptCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
  }) => StaleDeviceRefreshRequest(
    userId: userId ?? this.userId,
    staleDeviceId: staleDeviceId ?? this.staleDeviceId,
    state: state ?? this.state,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
  );
  StaleDeviceRefreshRequest copyWithCompanion(
    StaleDeviceRefreshRequestsCompanion data,
  ) {
    return StaleDeviceRefreshRequest(
      userId: data.userId.present ? data.userId.value : this.userId,
      staleDeviceId: data.staleDeviceId.present
          ? data.staleDeviceId.value
          : this.staleDeviceId,
      state: data.state.present ? data.state.value : this.state,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StaleDeviceRefreshRequest(')
          ..write('userId: $userId, ')
          ..write('staleDeviceId: $staleDeviceId, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(userId, staleDeviceId, state, attemptCount, nextAttemptAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StaleDeviceRefreshRequest &&
          other.userId == this.userId &&
          other.staleDeviceId == this.staleDeviceId &&
          other.state == this.state &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt);
}

class StaleDeviceRefreshRequestsCompanion
    extends UpdateCompanion<StaleDeviceRefreshRequest> {
  final Value<String> userId;
  final Value<String> staleDeviceId;
  final Value<int> state;
  final Value<int> attemptCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<int> rowid;
  const StaleDeviceRefreshRequestsCompanion({
    this.userId = const Value.absent(),
    this.staleDeviceId = const Value.absent(),
    this.state = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StaleDeviceRefreshRequestsCompanion.insert({
    required String userId,
    required String staleDeviceId,
    this.state = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       staleDeviceId = Value(staleDeviceId);
  static Insertable<StaleDeviceRefreshRequest> custom({
    Expression<String>? userId,
    Expression<String>? staleDeviceId,
    Expression<int>? state,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (staleDeviceId != null) 'stale_device_id': staleDeviceId,
      if (state != null) 'state': state,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StaleDeviceRefreshRequestsCompanion copyWith({
    Value<String>? userId,
    Value<String>? staleDeviceId,
    Value<int>? state,
    Value<int>? attemptCount,
    Value<DateTime?>? nextAttemptAt,
    Value<int>? rowid,
  }) {
    return StaleDeviceRefreshRequestsCompanion(
      userId: userId ?? this.userId,
      staleDeviceId: staleDeviceId ?? this.staleDeviceId,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (staleDeviceId.present) {
      map['stale_device_id'] = Variable<String>(staleDeviceId.value);
    }
    if (state.present) {
      map['state'] = Variable<int>(state.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StaleDeviceRefreshRequestsCompanion(')
          ..write('userId: $userId, ')
          ..write('staleDeviceId: $staleDeviceId, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReceiptsTable extends Receipts with TableInfo<$ReceiptsTable, Receipt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (message_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receiptStateMeta = const VerificationMeta(
    'receiptState',
  );
  @override
  late final GeneratedColumn<int> receiptState = GeneratedColumn<int>(
    'receipt_state',
    aliasedName,
    false,
    check: () => ComparableExpr(receiptState).isBetweenValues(0, 2),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectionCiphertextMeta =
      const VerificationMeta('projectionCiphertext');
  @override
  late final GeneratedColumn<Uint8List> projectionCiphertext =
      GeneratedColumn<Uint8List>(
        'projection_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    messageId,
    userId,
    deviceId,
    receiptState,
    projectionCiphertext,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Receipt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('receipt_state')) {
      context.handle(
        _receiptStateMeta,
        receiptState.isAcceptableOrUnknown(
          data['receipt_state']!,
          _receiptStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receiptStateMeta);
    }
    if (data.containsKey('projection_ciphertext')) {
      context.handle(
        _projectionCiphertextMeta,
        projectionCiphertext.isAcceptableOrUnknown(
          data['projection_ciphertext']!,
          _projectionCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_projectionCiphertextMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageId, userId, deviceId};
  @override
  Receipt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Receipt(
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      receiptState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}receipt_state'],
      )!,
      projectionCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}projection_ciphertext'],
      )!,
    );
  }

  @override
  $ReceiptsTable createAlias(String alias) {
    return $ReceiptsTable(attachedDatabase, alias);
  }
}

class Receipt extends DataClass implements Insertable<Receipt> {
  final String messageId;
  final String userId;
  final String deviceId;
  final int receiptState;
  final Uint8List projectionCiphertext;
  const Receipt({
    required this.messageId,
    required this.userId,
    required this.deviceId,
    required this.receiptState,
    required this.projectionCiphertext,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_id'] = Variable<String>(messageId);
    map['user_id'] = Variable<String>(userId);
    map['device_id'] = Variable<String>(deviceId);
    map['receipt_state'] = Variable<int>(receiptState);
    map['projection_ciphertext'] = Variable<Uint8List>(projectionCiphertext);
    return map;
  }

  ReceiptsCompanion toCompanion(bool nullToAbsent) {
    return ReceiptsCompanion(
      messageId: Value(messageId),
      userId: Value(userId),
      deviceId: Value(deviceId),
      receiptState: Value(receiptState),
      projectionCiphertext: Value(projectionCiphertext),
    );
  }

  factory Receipt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Receipt(
      messageId: serializer.fromJson<String>(json['messageId']),
      userId: serializer.fromJson<String>(json['userId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      receiptState: serializer.fromJson<int>(json['receiptState']),
      projectionCiphertext: serializer.fromJson<Uint8List>(
        json['projectionCiphertext'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageId': serializer.toJson<String>(messageId),
      'userId': serializer.toJson<String>(userId),
      'deviceId': serializer.toJson<String>(deviceId),
      'receiptState': serializer.toJson<int>(receiptState),
      'projectionCiphertext': serializer.toJson<Uint8List>(
        projectionCiphertext,
      ),
    };
  }

  Receipt copyWith({
    String? messageId,
    String? userId,
    String? deviceId,
    int? receiptState,
    Uint8List? projectionCiphertext,
  }) => Receipt(
    messageId: messageId ?? this.messageId,
    userId: userId ?? this.userId,
    deviceId: deviceId ?? this.deviceId,
    receiptState: receiptState ?? this.receiptState,
    projectionCiphertext: projectionCiphertext ?? this.projectionCiphertext,
  );
  Receipt copyWithCompanion(ReceiptsCompanion data) {
    return Receipt(
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      userId: data.userId.present ? data.userId.value : this.userId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      receiptState: data.receiptState.present
          ? data.receiptState.value
          : this.receiptState,
      projectionCiphertext: data.projectionCiphertext.present
          ? data.projectionCiphertext.value
          : this.projectionCiphertext,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Receipt(')
          ..write('messageId: $messageId, ')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId, ')
          ..write('receiptState: $receiptState, ')
          ..write('projectionCiphertext: $projectionCiphertext')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    messageId,
    userId,
    deviceId,
    receiptState,
    $driftBlobEquality.hash(projectionCiphertext),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Receipt &&
          other.messageId == this.messageId &&
          other.userId == this.userId &&
          other.deviceId == this.deviceId &&
          other.receiptState == this.receiptState &&
          $driftBlobEquality.equals(
            other.projectionCiphertext,
            this.projectionCiphertext,
          ));
}

class ReceiptsCompanion extends UpdateCompanion<Receipt> {
  final Value<String> messageId;
  final Value<String> userId;
  final Value<String> deviceId;
  final Value<int> receiptState;
  final Value<Uint8List> projectionCiphertext;
  final Value<int> rowid;
  const ReceiptsCompanion({
    this.messageId = const Value.absent(),
    this.userId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.receiptState = const Value.absent(),
    this.projectionCiphertext = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReceiptsCompanion.insert({
    required String messageId,
    required String userId,
    required String deviceId,
    required int receiptState,
    required Uint8List projectionCiphertext,
    this.rowid = const Value.absent(),
  }) : messageId = Value(messageId),
       userId = Value(userId),
       deviceId = Value(deviceId),
       receiptState = Value(receiptState),
       projectionCiphertext = Value(projectionCiphertext);
  static Insertable<Receipt> custom({
    Expression<String>? messageId,
    Expression<String>? userId,
    Expression<String>? deviceId,
    Expression<int>? receiptState,
    Expression<Uint8List>? projectionCiphertext,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageId != null) 'message_id': messageId,
      if (userId != null) 'user_id': userId,
      if (deviceId != null) 'device_id': deviceId,
      if (receiptState != null) 'receipt_state': receiptState,
      if (projectionCiphertext != null)
        'projection_ciphertext': projectionCiphertext,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReceiptsCompanion copyWith({
    Value<String>? messageId,
    Value<String>? userId,
    Value<String>? deviceId,
    Value<int>? receiptState,
    Value<Uint8List>? projectionCiphertext,
    Value<int>? rowid,
  }) {
    return ReceiptsCompanion(
      messageId: messageId ?? this.messageId,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      receiptState: receiptState ?? this.receiptState,
      projectionCiphertext: projectionCiphertext ?? this.projectionCiphertext,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (receiptState.present) {
      map['receipt_state'] = Variable<int>(receiptState.value);
    }
    if (projectionCiphertext.present) {
      map['projection_ciphertext'] = Variable<Uint8List>(
        projectionCiphertext.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptsCompanion(')
          ..write('messageId: $messageId, ')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId, ')
          ..write('receiptState: $receiptState, ')
          ..write('projectionCiphertext: $projectionCiphertext, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VoiceRoomsTable extends VoiceRooms
    with TableInfo<$VoiceRoomsTable, VoiceRoom> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VoiceRoomsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localRoomIdMeta = const VerificationMeta(
    'localRoomId',
  );
  @override
  late final GeneratedColumn<String> localRoomId = GeneratedColumn<String>(
    'local_room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _capabilityCiphertextMeta =
      const VerificationMeta('capabilityCiphertext');
  @override
  late final GeneratedColumn<Uint8List> capabilityCiphertext =
      GeneratedColumn<Uint8List>(
        'capability_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _metadataCiphertextMeta =
      const VerificationMeta('metadataCiphertext');
  @override
  late final GeneratedColumn<Uint8List> metadataCiphertext =
      GeneratedColumn<Uint8List>(
        'metadata_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _liveStateMeta = const VerificationMeta(
    'liveState',
  );
  @override
  late final GeneratedColumn<int> liveState = GeneratedColumn<int>(
    'live_state',
    aliasedName,
    false,
    check: () => ComparableExpr(liveState).isBetweenValues(0, 4),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localRoomId,
    capabilityCiphertext,
    metadataCiphertext,
    liveState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'voice_rooms';
  @override
  VerificationContext validateIntegrity(
    Insertable<VoiceRoom> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_room_id')) {
      context.handle(
        _localRoomIdMeta,
        localRoomId.isAcceptableOrUnknown(
          data['local_room_id']!,
          _localRoomIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localRoomIdMeta);
    }
    if (data.containsKey('capability_ciphertext')) {
      context.handle(
        _capabilityCiphertextMeta,
        capabilityCiphertext.isAcceptableOrUnknown(
          data['capability_ciphertext']!,
          _capabilityCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_capabilityCiphertextMeta);
    }
    if (data.containsKey('metadata_ciphertext')) {
      context.handle(
        _metadataCiphertextMeta,
        metadataCiphertext.isAcceptableOrUnknown(
          data['metadata_ciphertext']!,
          _metadataCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metadataCiphertextMeta);
    }
    if (data.containsKey('live_state')) {
      context.handle(
        _liveStateMeta,
        liveState.isAcceptableOrUnknown(data['live_state']!, _liveStateMeta),
      );
    } else if (isInserting) {
      context.missing(_liveStateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localRoomId};
  @override
  VoiceRoom map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VoiceRoom(
      localRoomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_room_id'],
      )!,
      capabilityCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}capability_ciphertext'],
      )!,
      metadataCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}metadata_ciphertext'],
      )!,
      liveState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}live_state'],
      )!,
    );
  }

  @override
  $VoiceRoomsTable createAlias(String alias) {
    return $VoiceRoomsTable(attachedDatabase, alias);
  }
}

class VoiceRoom extends DataClass implements Insertable<VoiceRoom> {
  final String localRoomId;
  final Uint8List capabilityCiphertext;
  final Uint8List metadataCiphertext;
  final int liveState;
  const VoiceRoom({
    required this.localRoomId,
    required this.capabilityCiphertext,
    required this.metadataCiphertext,
    required this.liveState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_room_id'] = Variable<String>(localRoomId);
    map['capability_ciphertext'] = Variable<Uint8List>(capabilityCiphertext);
    map['metadata_ciphertext'] = Variable<Uint8List>(metadataCiphertext);
    map['live_state'] = Variable<int>(liveState);
    return map;
  }

  VoiceRoomsCompanion toCompanion(bool nullToAbsent) {
    return VoiceRoomsCompanion(
      localRoomId: Value(localRoomId),
      capabilityCiphertext: Value(capabilityCiphertext),
      metadataCiphertext: Value(metadataCiphertext),
      liveState: Value(liveState),
    );
  }

  factory VoiceRoom.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VoiceRoom(
      localRoomId: serializer.fromJson<String>(json['localRoomId']),
      capabilityCiphertext: serializer.fromJson<Uint8List>(
        json['capabilityCiphertext'],
      ),
      metadataCiphertext: serializer.fromJson<Uint8List>(
        json['metadataCiphertext'],
      ),
      liveState: serializer.fromJson<int>(json['liveState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localRoomId': serializer.toJson<String>(localRoomId),
      'capabilityCiphertext': serializer.toJson<Uint8List>(
        capabilityCiphertext,
      ),
      'metadataCiphertext': serializer.toJson<Uint8List>(metadataCiphertext),
      'liveState': serializer.toJson<int>(liveState),
    };
  }

  VoiceRoom copyWith({
    String? localRoomId,
    Uint8List? capabilityCiphertext,
    Uint8List? metadataCiphertext,
    int? liveState,
  }) => VoiceRoom(
    localRoomId: localRoomId ?? this.localRoomId,
    capabilityCiphertext: capabilityCiphertext ?? this.capabilityCiphertext,
    metadataCiphertext: metadataCiphertext ?? this.metadataCiphertext,
    liveState: liveState ?? this.liveState,
  );
  VoiceRoom copyWithCompanion(VoiceRoomsCompanion data) {
    return VoiceRoom(
      localRoomId: data.localRoomId.present
          ? data.localRoomId.value
          : this.localRoomId,
      capabilityCiphertext: data.capabilityCiphertext.present
          ? data.capabilityCiphertext.value
          : this.capabilityCiphertext,
      metadataCiphertext: data.metadataCiphertext.present
          ? data.metadataCiphertext.value
          : this.metadataCiphertext,
      liveState: data.liveState.present ? data.liveState.value : this.liveState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VoiceRoom(')
          ..write('localRoomId: $localRoomId, ')
          ..write('capabilityCiphertext: $capabilityCiphertext, ')
          ..write('metadataCiphertext: $metadataCiphertext, ')
          ..write('liveState: $liveState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localRoomId,
    $driftBlobEquality.hash(capabilityCiphertext),
    $driftBlobEquality.hash(metadataCiphertext),
    liveState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VoiceRoom &&
          other.localRoomId == this.localRoomId &&
          $driftBlobEquality.equals(
            other.capabilityCiphertext,
            this.capabilityCiphertext,
          ) &&
          $driftBlobEquality.equals(
            other.metadataCiphertext,
            this.metadataCiphertext,
          ) &&
          other.liveState == this.liveState);
}

class VoiceRoomsCompanion extends UpdateCompanion<VoiceRoom> {
  final Value<String> localRoomId;
  final Value<Uint8List> capabilityCiphertext;
  final Value<Uint8List> metadataCiphertext;
  final Value<int> liveState;
  final Value<int> rowid;
  const VoiceRoomsCompanion({
    this.localRoomId = const Value.absent(),
    this.capabilityCiphertext = const Value.absent(),
    this.metadataCiphertext = const Value.absent(),
    this.liveState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VoiceRoomsCompanion.insert({
    required String localRoomId,
    required Uint8List capabilityCiphertext,
    required Uint8List metadataCiphertext,
    required int liveState,
    this.rowid = const Value.absent(),
  }) : localRoomId = Value(localRoomId),
       capabilityCiphertext = Value(capabilityCiphertext),
       metadataCiphertext = Value(metadataCiphertext),
       liveState = Value(liveState);
  static Insertable<VoiceRoom> custom({
    Expression<String>? localRoomId,
    Expression<Uint8List>? capabilityCiphertext,
    Expression<Uint8List>? metadataCiphertext,
    Expression<int>? liveState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localRoomId != null) 'local_room_id': localRoomId,
      if (capabilityCiphertext != null)
        'capability_ciphertext': capabilityCiphertext,
      if (metadataCiphertext != null) 'metadata_ciphertext': metadataCiphertext,
      if (liveState != null) 'live_state': liveState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VoiceRoomsCompanion copyWith({
    Value<String>? localRoomId,
    Value<Uint8List>? capabilityCiphertext,
    Value<Uint8List>? metadataCiphertext,
    Value<int>? liveState,
    Value<int>? rowid,
  }) {
    return VoiceRoomsCompanion(
      localRoomId: localRoomId ?? this.localRoomId,
      capabilityCiphertext: capabilityCiphertext ?? this.capabilityCiphertext,
      metadataCiphertext: metadataCiphertext ?? this.metadataCiphertext,
      liveState: liveState ?? this.liveState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localRoomId.present) {
      map['local_room_id'] = Variable<String>(localRoomId.value);
    }
    if (capabilityCiphertext.present) {
      map['capability_ciphertext'] = Variable<Uint8List>(
        capabilityCiphertext.value,
      );
    }
    if (metadataCiphertext.present) {
      map['metadata_ciphertext'] = Variable<Uint8List>(
        metadataCiphertext.value,
      );
    }
    if (liveState.present) {
      map['live_state'] = Variable<int>(liveState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VoiceRoomsCompanion(')
          ..write('localRoomId: $localRoomId, ')
          ..write('capabilityCiphertext: $capabilityCiphertext, ')
          ..write('metadataCiphertext: $metadataCiphertext, ')
          ..write('liveState: $liveState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HistoryTransfersTable extends HistoryTransfers
    with TableInfo<$HistoryTransfersTable, HistoryTransfer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryTransfersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _transferIdMeta = const VerificationMeta(
    'transferId',
  );
  @override
  late final GeneratedColumn<String> transferId = GeneratedColumn<String>(
    'transfer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manifestCiphertextMeta =
      const VerificationMeta('manifestCiphertext');
  @override
  late final GeneratedColumn<Uint8List> manifestCiphertext =
      GeneratedColumn<Uint8List>(
        'manifest_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _eventProgressMeta = const VerificationMeta(
    'eventProgress',
  );
  @override
  late final GeneratedColumn<int> eventProgress = GeneratedColumn<int>(
    'event_progress',
    aliasedName,
    false,
    check: () => ComparableExpr(eventProgress).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sourceCompletenessMeta =
      const VerificationMeta('sourceCompleteness');
  @override
  late final GeneratedColumn<int> sourceCompleteness = GeneratedColumn<int>(
    'source_completeness',
    aliasedName,
    false,
    check: () => ComparableExpr(sourceCompleteness).isBetweenValues(0, 2),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    transferId,
    manifestCiphertext,
    eventProgress,
    sourceCompleteness,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history_transfers';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryTransfer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('transfer_id')) {
      context.handle(
        _transferIdMeta,
        transferId.isAcceptableOrUnknown(data['transfer_id']!, _transferIdMeta),
      );
    } else if (isInserting) {
      context.missing(_transferIdMeta);
    }
    if (data.containsKey('manifest_ciphertext')) {
      context.handle(
        _manifestCiphertextMeta,
        manifestCiphertext.isAcceptableOrUnknown(
          data['manifest_ciphertext']!,
          _manifestCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manifestCiphertextMeta);
    }
    if (data.containsKey('event_progress')) {
      context.handle(
        _eventProgressMeta,
        eventProgress.isAcceptableOrUnknown(
          data['event_progress']!,
          _eventProgressMeta,
        ),
      );
    }
    if (data.containsKey('source_completeness')) {
      context.handle(
        _sourceCompletenessMeta,
        sourceCompleteness.isAcceptableOrUnknown(
          data['source_completeness']!,
          _sourceCompletenessMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceCompletenessMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {transferId};
  @override
  HistoryTransfer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryTransfer(
      transferId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_id'],
      )!,
      manifestCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}manifest_ciphertext'],
      )!,
      eventProgress: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}event_progress'],
      )!,
      sourceCompleteness: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_completeness'],
      )!,
    );
  }

  @override
  $HistoryTransfersTable createAlias(String alias) {
    return $HistoryTransfersTable(attachedDatabase, alias);
  }
}

class HistoryTransfer extends DataClass implements Insertable<HistoryTransfer> {
  final String transferId;
  final Uint8List manifestCiphertext;
  final int eventProgress;
  final int sourceCompleteness;
  const HistoryTransfer({
    required this.transferId,
    required this.manifestCiphertext,
    required this.eventProgress,
    required this.sourceCompleteness,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['transfer_id'] = Variable<String>(transferId);
    map['manifest_ciphertext'] = Variable<Uint8List>(manifestCiphertext);
    map['event_progress'] = Variable<int>(eventProgress);
    map['source_completeness'] = Variable<int>(sourceCompleteness);
    return map;
  }

  HistoryTransfersCompanion toCompanion(bool nullToAbsent) {
    return HistoryTransfersCompanion(
      transferId: Value(transferId),
      manifestCiphertext: Value(manifestCiphertext),
      eventProgress: Value(eventProgress),
      sourceCompleteness: Value(sourceCompleteness),
    );
  }

  factory HistoryTransfer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryTransfer(
      transferId: serializer.fromJson<String>(json['transferId']),
      manifestCiphertext: serializer.fromJson<Uint8List>(
        json['manifestCiphertext'],
      ),
      eventProgress: serializer.fromJson<int>(json['eventProgress']),
      sourceCompleteness: serializer.fromJson<int>(json['sourceCompleteness']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'transferId': serializer.toJson<String>(transferId),
      'manifestCiphertext': serializer.toJson<Uint8List>(manifestCiphertext),
      'eventProgress': serializer.toJson<int>(eventProgress),
      'sourceCompleteness': serializer.toJson<int>(sourceCompleteness),
    };
  }

  HistoryTransfer copyWith({
    String? transferId,
    Uint8List? manifestCiphertext,
    int? eventProgress,
    int? sourceCompleteness,
  }) => HistoryTransfer(
    transferId: transferId ?? this.transferId,
    manifestCiphertext: manifestCiphertext ?? this.manifestCiphertext,
    eventProgress: eventProgress ?? this.eventProgress,
    sourceCompleteness: sourceCompleteness ?? this.sourceCompleteness,
  );
  HistoryTransfer copyWithCompanion(HistoryTransfersCompanion data) {
    return HistoryTransfer(
      transferId: data.transferId.present
          ? data.transferId.value
          : this.transferId,
      manifestCiphertext: data.manifestCiphertext.present
          ? data.manifestCiphertext.value
          : this.manifestCiphertext,
      eventProgress: data.eventProgress.present
          ? data.eventProgress.value
          : this.eventProgress,
      sourceCompleteness: data.sourceCompleteness.present
          ? data.sourceCompleteness.value
          : this.sourceCompleteness,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryTransfer(')
          ..write('transferId: $transferId, ')
          ..write('manifestCiphertext: $manifestCiphertext, ')
          ..write('eventProgress: $eventProgress, ')
          ..write('sourceCompleteness: $sourceCompleteness')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    transferId,
    $driftBlobEquality.hash(manifestCiphertext),
    eventProgress,
    sourceCompleteness,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryTransfer &&
          other.transferId == this.transferId &&
          $driftBlobEquality.equals(
            other.manifestCiphertext,
            this.manifestCiphertext,
          ) &&
          other.eventProgress == this.eventProgress &&
          other.sourceCompleteness == this.sourceCompleteness);
}

class HistoryTransfersCompanion extends UpdateCompanion<HistoryTransfer> {
  final Value<String> transferId;
  final Value<Uint8List> manifestCiphertext;
  final Value<int> eventProgress;
  final Value<int> sourceCompleteness;
  final Value<int> rowid;
  const HistoryTransfersCompanion({
    this.transferId = const Value.absent(),
    this.manifestCiphertext = const Value.absent(),
    this.eventProgress = const Value.absent(),
    this.sourceCompleteness = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HistoryTransfersCompanion.insert({
    required String transferId,
    required Uint8List manifestCiphertext,
    this.eventProgress = const Value.absent(),
    required int sourceCompleteness,
    this.rowid = const Value.absent(),
  }) : transferId = Value(transferId),
       manifestCiphertext = Value(manifestCiphertext),
       sourceCompleteness = Value(sourceCompleteness);
  static Insertable<HistoryTransfer> custom({
    Expression<String>? transferId,
    Expression<Uint8List>? manifestCiphertext,
    Expression<int>? eventProgress,
    Expression<int>? sourceCompleteness,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (transferId != null) 'transfer_id': transferId,
      if (manifestCiphertext != null) 'manifest_ciphertext': manifestCiphertext,
      if (eventProgress != null) 'event_progress': eventProgress,
      if (sourceCompleteness != null) 'source_completeness': sourceCompleteness,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HistoryTransfersCompanion copyWith({
    Value<String>? transferId,
    Value<Uint8List>? manifestCiphertext,
    Value<int>? eventProgress,
    Value<int>? sourceCompleteness,
    Value<int>? rowid,
  }) {
    return HistoryTransfersCompanion(
      transferId: transferId ?? this.transferId,
      manifestCiphertext: manifestCiphertext ?? this.manifestCiphertext,
      eventProgress: eventProgress ?? this.eventProgress,
      sourceCompleteness: sourceCompleteness ?? this.sourceCompleteness,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (transferId.present) {
      map['transfer_id'] = Variable<String>(transferId.value);
    }
    if (manifestCiphertext.present) {
      map['manifest_ciphertext'] = Variable<Uint8List>(
        manifestCiphertext.value,
      );
    }
    if (eventProgress.present) {
      map['event_progress'] = Variable<int>(eventProgress.value);
    }
    if (sourceCompleteness.present) {
      map['source_completeness'] = Variable<int>(sourceCompleteness.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryTransfersCompanion(')
          ..write('transferId: $transferId, ')
          ..write('manifestCiphertext: $manifestCiphertext, ')
          ..write('eventProgress: $eventProgress, ')
          ..write('sourceCompleteness: $sourceCompleteness, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCheckpointsTable extends SyncCheckpoints
    with TableInfo<$SyncCheckpointsTable, SyncCheckpoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCheckpointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonIdMeta = const VerificationMeta(
    'singletonId',
  );
  @override
  late final GeneratedColumn<int> singletonId = GeneratedColumn<int>(
    'singleton_id',
    aliasedName,
    false,
    check: () => singletonId.equals(1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _highestContiguousAckedSequenceMeta =
      const VerificationMeta('highestContiguousAckedSequence');
  @override
  late final GeneratedColumn<int> highestContiguousAckedSequence =
      GeneratedColumn<int>(
        'highest_contiguous_acked_sequence',
        aliasedName,
        false,
        check: () => ComparableExpr(
          highestContiguousAckedSequence,
        ).isBiggerOrEqualValue(0),
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _prunedThroughMeta = const VerificationMeta(
    'prunedThrough',
  );
  @override
  late final GeneratedColumn<int> prunedThrough = GeneratedColumn<int>(
    'pruned_through',
    aliasedName,
    false,
    check: () => ComparableExpr(prunedThrough).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _etagsCiphertextMeta = const VerificationMeta(
    'etagsCiphertext',
  );
  @override
  late final GeneratedColumn<Uint8List> etagsCiphertext =
      GeneratedColumn<Uint8List>(
        'etags_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _retryStateMeta = const VerificationMeta(
    'retryState',
  );
  @override
  late final GeneratedColumn<int> retryState = GeneratedColumn<int>(
    'retry_state',
    aliasedName,
    false,
    check: () => ComparableExpr(retryState).isBetweenValues(0, 5),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _protocolVersionMeta = const VerificationMeta(
    'protocolVersion',
  );
  @override
  late final GeneratedColumn<int> protocolVersion = GeneratedColumn<int>(
    'protocol_version',
    aliasedName,
    false,
    check: () => ComparableExpr(protocolVersion).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queueGapStateMeta = const VerificationMeta(
    'queueGapState',
  );
  @override
  late final GeneratedColumn<int> queueGapState = GeneratedColumn<int>(
    'queue_gap_state',
    aliasedName,
    false,
    check: () => ComparableExpr(queueGapState).isBetweenValues(0, 1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _drainRequestedMeta = const VerificationMeta(
    'drainRequested',
  );
  @override
  late final GeneratedColumn<bool> drainRequested = GeneratedColumn<bool>(
    'drain_requested',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("drain_requested" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _connectionPhaseMeta = const VerificationMeta(
    'connectionPhase',
  );
  @override
  late final GeneratedColumn<int> connectionPhase = GeneratedColumn<int>(
    'connection_phase',
    aliasedName,
    false,
    check: () => ComparableExpr(connectionPhase).isBetweenValues(0, 9),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _reconnectAttemptMeta = const VerificationMeta(
    'reconnectAttempt',
  );
  @override
  late final GeneratedColumn<int> reconnectAttempt = GeneratedColumn<int>(
    'reconnect_attempt',
    aliasedName,
    false,
    check: () => ComparableExpr(reconnectAttempt).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _reconnectAtMeta = const VerificationMeta(
    'reconnectAt',
  );
  @override
  late final GeneratedColumn<DateTime> reconnectAt = GeneratedColumn<DateTime>(
    'reconnect_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSuccessfulSyncAtMeta =
      const VerificationMeta('lastSuccessfulSyncAt');
  @override
  late final GeneratedColumn<DateTime> lastSuccessfulSyncAt =
      GeneratedColumn<DateTime>(
        'last_successful_sync_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    singletonId,
    highestContiguousAckedSequence,
    prunedThrough,
    etagsCiphertext,
    retryState,
    protocolVersion,
    queueGapState,
    drainRequested,
    connectionPhase,
    reconnectAttempt,
    reconnectAt,
    lastSuccessfulSyncAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_checkpoint';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCheckpoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton_id')) {
      context.handle(
        _singletonIdMeta,
        singletonId.isAcceptableOrUnknown(
          data['singleton_id']!,
          _singletonIdMeta,
        ),
      );
    }
    if (data.containsKey('highest_contiguous_acked_sequence')) {
      context.handle(
        _highestContiguousAckedSequenceMeta,
        highestContiguousAckedSequence.isAcceptableOrUnknown(
          data['highest_contiguous_acked_sequence']!,
          _highestContiguousAckedSequenceMeta,
        ),
      );
    }
    if (data.containsKey('pruned_through')) {
      context.handle(
        _prunedThroughMeta,
        prunedThrough.isAcceptableOrUnknown(
          data['pruned_through']!,
          _prunedThroughMeta,
        ),
      );
    }
    if (data.containsKey('etags_ciphertext')) {
      context.handle(
        _etagsCiphertextMeta,
        etagsCiphertext.isAcceptableOrUnknown(
          data['etags_ciphertext']!,
          _etagsCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_etagsCiphertextMeta);
    }
    if (data.containsKey('retry_state')) {
      context.handle(
        _retryStateMeta,
        retryState.isAcceptableOrUnknown(data['retry_state']!, _retryStateMeta),
      );
    } else if (isInserting) {
      context.missing(_retryStateMeta);
    }
    if (data.containsKey('protocol_version')) {
      context.handle(
        _protocolVersionMeta,
        protocolVersion.isAcceptableOrUnknown(
          data['protocol_version']!,
          _protocolVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_protocolVersionMeta);
    }
    if (data.containsKey('queue_gap_state')) {
      context.handle(
        _queueGapStateMeta,
        queueGapState.isAcceptableOrUnknown(
          data['queue_gap_state']!,
          _queueGapStateMeta,
        ),
      );
    }
    if (data.containsKey('drain_requested')) {
      context.handle(
        _drainRequestedMeta,
        drainRequested.isAcceptableOrUnknown(
          data['drain_requested']!,
          _drainRequestedMeta,
        ),
      );
    }
    if (data.containsKey('connection_phase')) {
      context.handle(
        _connectionPhaseMeta,
        connectionPhase.isAcceptableOrUnknown(
          data['connection_phase']!,
          _connectionPhaseMeta,
        ),
      );
    }
    if (data.containsKey('reconnect_attempt')) {
      context.handle(
        _reconnectAttemptMeta,
        reconnectAttempt.isAcceptableOrUnknown(
          data['reconnect_attempt']!,
          _reconnectAttemptMeta,
        ),
      );
    }
    if (data.containsKey('reconnect_at')) {
      context.handle(
        _reconnectAtMeta,
        reconnectAt.isAcceptableOrUnknown(
          data['reconnect_at']!,
          _reconnectAtMeta,
        ),
      );
    }
    if (data.containsKey('last_successful_sync_at')) {
      context.handle(
        _lastSuccessfulSyncAtMeta,
        lastSuccessfulSyncAt.isAcceptableOrUnknown(
          data['last_successful_sync_at']!,
          _lastSuccessfulSyncAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singletonId};
  @override
  SyncCheckpoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCheckpoint(
      singletonId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton_id'],
      )!,
      highestContiguousAckedSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}highest_contiguous_acked_sequence'],
      )!,
      prunedThrough: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pruned_through'],
      )!,
      etagsCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}etags_ciphertext'],
      )!,
      retryState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_state'],
      )!,
      protocolVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}protocol_version'],
      )!,
      queueGapState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}queue_gap_state'],
      )!,
      drainRequested: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}drain_requested'],
      )!,
      connectionPhase: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}connection_phase'],
      )!,
      reconnectAttempt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reconnect_attempt'],
      )!,
      reconnectAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reconnect_at'],
      ),
      lastSuccessfulSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_successful_sync_at'],
      ),
    );
  }

  @override
  $SyncCheckpointsTable createAlias(String alias) {
    return $SyncCheckpointsTable(attachedDatabase, alias);
  }
}

class SyncCheckpoint extends DataClass implements Insertable<SyncCheckpoint> {
  final int singletonId;
  final int highestContiguousAckedSequence;
  final int prunedThrough;
  final Uint8List etagsCiphertext;
  final int retryState;
  final int protocolVersion;
  final int queueGapState;
  final bool drainRequested;
  final int connectionPhase;
  final int reconnectAttempt;
  final DateTime? reconnectAt;
  final DateTime? lastSuccessfulSyncAt;
  const SyncCheckpoint({
    required this.singletonId,
    required this.highestContiguousAckedSequence,
    required this.prunedThrough,
    required this.etagsCiphertext,
    required this.retryState,
    required this.protocolVersion,
    required this.queueGapState,
    required this.drainRequested,
    required this.connectionPhase,
    required this.reconnectAttempt,
    this.reconnectAt,
    this.lastSuccessfulSyncAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton_id'] = Variable<int>(singletonId);
    map['highest_contiguous_acked_sequence'] = Variable<int>(
      highestContiguousAckedSequence,
    );
    map['pruned_through'] = Variable<int>(prunedThrough);
    map['etags_ciphertext'] = Variable<Uint8List>(etagsCiphertext);
    map['retry_state'] = Variable<int>(retryState);
    map['protocol_version'] = Variable<int>(protocolVersion);
    map['queue_gap_state'] = Variable<int>(queueGapState);
    map['drain_requested'] = Variable<bool>(drainRequested);
    map['connection_phase'] = Variable<int>(connectionPhase);
    map['reconnect_attempt'] = Variable<int>(reconnectAttempt);
    if (!nullToAbsent || reconnectAt != null) {
      map['reconnect_at'] = Variable<DateTime>(reconnectAt);
    }
    if (!nullToAbsent || lastSuccessfulSyncAt != null) {
      map['last_successful_sync_at'] = Variable<DateTime>(lastSuccessfulSyncAt);
    }
    return map;
  }

  SyncCheckpointsCompanion toCompanion(bool nullToAbsent) {
    return SyncCheckpointsCompanion(
      singletonId: Value(singletonId),
      highestContiguousAckedSequence: Value(highestContiguousAckedSequence),
      prunedThrough: Value(prunedThrough),
      etagsCiphertext: Value(etagsCiphertext),
      retryState: Value(retryState),
      protocolVersion: Value(protocolVersion),
      queueGapState: Value(queueGapState),
      drainRequested: Value(drainRequested),
      connectionPhase: Value(connectionPhase),
      reconnectAttempt: Value(reconnectAttempt),
      reconnectAt: reconnectAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reconnectAt),
      lastSuccessfulSyncAt: lastSuccessfulSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSuccessfulSyncAt),
    );
  }

  factory SyncCheckpoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCheckpoint(
      singletonId: serializer.fromJson<int>(json['singletonId']),
      highestContiguousAckedSequence: serializer.fromJson<int>(
        json['highestContiguousAckedSequence'],
      ),
      prunedThrough: serializer.fromJson<int>(json['prunedThrough']),
      etagsCiphertext: serializer.fromJson<Uint8List>(json['etagsCiphertext']),
      retryState: serializer.fromJson<int>(json['retryState']),
      protocolVersion: serializer.fromJson<int>(json['protocolVersion']),
      queueGapState: serializer.fromJson<int>(json['queueGapState']),
      drainRequested: serializer.fromJson<bool>(json['drainRequested']),
      connectionPhase: serializer.fromJson<int>(json['connectionPhase']),
      reconnectAttempt: serializer.fromJson<int>(json['reconnectAttempt']),
      reconnectAt: serializer.fromJson<DateTime?>(json['reconnectAt']),
      lastSuccessfulSyncAt: serializer.fromJson<DateTime?>(
        json['lastSuccessfulSyncAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singletonId': serializer.toJson<int>(singletonId),
      'highestContiguousAckedSequence': serializer.toJson<int>(
        highestContiguousAckedSequence,
      ),
      'prunedThrough': serializer.toJson<int>(prunedThrough),
      'etagsCiphertext': serializer.toJson<Uint8List>(etagsCiphertext),
      'retryState': serializer.toJson<int>(retryState),
      'protocolVersion': serializer.toJson<int>(protocolVersion),
      'queueGapState': serializer.toJson<int>(queueGapState),
      'drainRequested': serializer.toJson<bool>(drainRequested),
      'connectionPhase': serializer.toJson<int>(connectionPhase),
      'reconnectAttempt': serializer.toJson<int>(reconnectAttempt),
      'reconnectAt': serializer.toJson<DateTime?>(reconnectAt),
      'lastSuccessfulSyncAt': serializer.toJson<DateTime?>(
        lastSuccessfulSyncAt,
      ),
    };
  }

  SyncCheckpoint copyWith({
    int? singletonId,
    int? highestContiguousAckedSequence,
    int? prunedThrough,
    Uint8List? etagsCiphertext,
    int? retryState,
    int? protocolVersion,
    int? queueGapState,
    bool? drainRequested,
    int? connectionPhase,
    int? reconnectAttempt,
    Value<DateTime?> reconnectAt = const Value.absent(),
    Value<DateTime?> lastSuccessfulSyncAt = const Value.absent(),
  }) => SyncCheckpoint(
    singletonId: singletonId ?? this.singletonId,
    highestContiguousAckedSequence:
        highestContiguousAckedSequence ?? this.highestContiguousAckedSequence,
    prunedThrough: prunedThrough ?? this.prunedThrough,
    etagsCiphertext: etagsCiphertext ?? this.etagsCiphertext,
    retryState: retryState ?? this.retryState,
    protocolVersion: protocolVersion ?? this.protocolVersion,
    queueGapState: queueGapState ?? this.queueGapState,
    drainRequested: drainRequested ?? this.drainRequested,
    connectionPhase: connectionPhase ?? this.connectionPhase,
    reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    reconnectAt: reconnectAt.present ? reconnectAt.value : this.reconnectAt,
    lastSuccessfulSyncAt: lastSuccessfulSyncAt.present
        ? lastSuccessfulSyncAt.value
        : this.lastSuccessfulSyncAt,
  );
  SyncCheckpoint copyWithCompanion(SyncCheckpointsCompanion data) {
    return SyncCheckpoint(
      singletonId: data.singletonId.present
          ? data.singletonId.value
          : this.singletonId,
      highestContiguousAckedSequence:
          data.highestContiguousAckedSequence.present
          ? data.highestContiguousAckedSequence.value
          : this.highestContiguousAckedSequence,
      prunedThrough: data.prunedThrough.present
          ? data.prunedThrough.value
          : this.prunedThrough,
      etagsCiphertext: data.etagsCiphertext.present
          ? data.etagsCiphertext.value
          : this.etagsCiphertext,
      retryState: data.retryState.present
          ? data.retryState.value
          : this.retryState,
      protocolVersion: data.protocolVersion.present
          ? data.protocolVersion.value
          : this.protocolVersion,
      queueGapState: data.queueGapState.present
          ? data.queueGapState.value
          : this.queueGapState,
      drainRequested: data.drainRequested.present
          ? data.drainRequested.value
          : this.drainRequested,
      connectionPhase: data.connectionPhase.present
          ? data.connectionPhase.value
          : this.connectionPhase,
      reconnectAttempt: data.reconnectAttempt.present
          ? data.reconnectAttempt.value
          : this.reconnectAttempt,
      reconnectAt: data.reconnectAt.present
          ? data.reconnectAt.value
          : this.reconnectAt,
      lastSuccessfulSyncAt: data.lastSuccessfulSyncAt.present
          ? data.lastSuccessfulSyncAt.value
          : this.lastSuccessfulSyncAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCheckpoint(')
          ..write('singletonId: $singletonId, ')
          ..write(
            'highestContiguousAckedSequence: $highestContiguousAckedSequence, ',
          )
          ..write('prunedThrough: $prunedThrough, ')
          ..write('etagsCiphertext: $etagsCiphertext, ')
          ..write('retryState: $retryState, ')
          ..write('protocolVersion: $protocolVersion, ')
          ..write('queueGapState: $queueGapState, ')
          ..write('drainRequested: $drainRequested, ')
          ..write('connectionPhase: $connectionPhase, ')
          ..write('reconnectAttempt: $reconnectAttempt, ')
          ..write('reconnectAt: $reconnectAt, ')
          ..write('lastSuccessfulSyncAt: $lastSuccessfulSyncAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    singletonId,
    highestContiguousAckedSequence,
    prunedThrough,
    $driftBlobEquality.hash(etagsCiphertext),
    retryState,
    protocolVersion,
    queueGapState,
    drainRequested,
    connectionPhase,
    reconnectAttempt,
    reconnectAt,
    lastSuccessfulSyncAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCheckpoint &&
          other.singletonId == this.singletonId &&
          other.highestContiguousAckedSequence ==
              this.highestContiguousAckedSequence &&
          other.prunedThrough == this.prunedThrough &&
          $driftBlobEquality.equals(
            other.etagsCiphertext,
            this.etagsCiphertext,
          ) &&
          other.retryState == this.retryState &&
          other.protocolVersion == this.protocolVersion &&
          other.queueGapState == this.queueGapState &&
          other.drainRequested == this.drainRequested &&
          other.connectionPhase == this.connectionPhase &&
          other.reconnectAttempt == this.reconnectAttempt &&
          other.reconnectAt == this.reconnectAt &&
          other.lastSuccessfulSyncAt == this.lastSuccessfulSyncAt);
}

class SyncCheckpointsCompanion extends UpdateCompanion<SyncCheckpoint> {
  final Value<int> singletonId;
  final Value<int> highestContiguousAckedSequence;
  final Value<int> prunedThrough;
  final Value<Uint8List> etagsCiphertext;
  final Value<int> retryState;
  final Value<int> protocolVersion;
  final Value<int> queueGapState;
  final Value<bool> drainRequested;
  final Value<int> connectionPhase;
  final Value<int> reconnectAttempt;
  final Value<DateTime?> reconnectAt;
  final Value<DateTime?> lastSuccessfulSyncAt;
  const SyncCheckpointsCompanion({
    this.singletonId = const Value.absent(),
    this.highestContiguousAckedSequence = const Value.absent(),
    this.prunedThrough = const Value.absent(),
    this.etagsCiphertext = const Value.absent(),
    this.retryState = const Value.absent(),
    this.protocolVersion = const Value.absent(),
    this.queueGapState = const Value.absent(),
    this.drainRequested = const Value.absent(),
    this.connectionPhase = const Value.absent(),
    this.reconnectAttempt = const Value.absent(),
    this.reconnectAt = const Value.absent(),
    this.lastSuccessfulSyncAt = const Value.absent(),
  });
  SyncCheckpointsCompanion.insert({
    this.singletonId = const Value.absent(),
    this.highestContiguousAckedSequence = const Value.absent(),
    this.prunedThrough = const Value.absent(),
    required Uint8List etagsCiphertext,
    required int retryState,
    required int protocolVersion,
    this.queueGapState = const Value.absent(),
    this.drainRequested = const Value.absent(),
    this.connectionPhase = const Value.absent(),
    this.reconnectAttempt = const Value.absent(),
    this.reconnectAt = const Value.absent(),
    this.lastSuccessfulSyncAt = const Value.absent(),
  }) : etagsCiphertext = Value(etagsCiphertext),
       retryState = Value(retryState),
       protocolVersion = Value(protocolVersion);
  static Insertable<SyncCheckpoint> custom({
    Expression<int>? singletonId,
    Expression<int>? highestContiguousAckedSequence,
    Expression<int>? prunedThrough,
    Expression<Uint8List>? etagsCiphertext,
    Expression<int>? retryState,
    Expression<int>? protocolVersion,
    Expression<int>? queueGapState,
    Expression<bool>? drainRequested,
    Expression<int>? connectionPhase,
    Expression<int>? reconnectAttempt,
    Expression<DateTime>? reconnectAt,
    Expression<DateTime>? lastSuccessfulSyncAt,
  }) {
    return RawValuesInsertable({
      if (singletonId != null) 'singleton_id': singletonId,
      if (highestContiguousAckedSequence != null)
        'highest_contiguous_acked_sequence': highestContiguousAckedSequence,
      if (prunedThrough != null) 'pruned_through': prunedThrough,
      if (etagsCiphertext != null) 'etags_ciphertext': etagsCiphertext,
      if (retryState != null) 'retry_state': retryState,
      if (protocolVersion != null) 'protocol_version': protocolVersion,
      if (queueGapState != null) 'queue_gap_state': queueGapState,
      if (drainRequested != null) 'drain_requested': drainRequested,
      if (connectionPhase != null) 'connection_phase': connectionPhase,
      if (reconnectAttempt != null) 'reconnect_attempt': reconnectAttempt,
      if (reconnectAt != null) 'reconnect_at': reconnectAt,
      if (lastSuccessfulSyncAt != null)
        'last_successful_sync_at': lastSuccessfulSyncAt,
    });
  }

  SyncCheckpointsCompanion copyWith({
    Value<int>? singletonId,
    Value<int>? highestContiguousAckedSequence,
    Value<int>? prunedThrough,
    Value<Uint8List>? etagsCiphertext,
    Value<int>? retryState,
    Value<int>? protocolVersion,
    Value<int>? queueGapState,
    Value<bool>? drainRequested,
    Value<int>? connectionPhase,
    Value<int>? reconnectAttempt,
    Value<DateTime?>? reconnectAt,
    Value<DateTime?>? lastSuccessfulSyncAt,
  }) {
    return SyncCheckpointsCompanion(
      singletonId: singletonId ?? this.singletonId,
      highestContiguousAckedSequence:
          highestContiguousAckedSequence ?? this.highestContiguousAckedSequence,
      prunedThrough: prunedThrough ?? this.prunedThrough,
      etagsCiphertext: etagsCiphertext ?? this.etagsCiphertext,
      retryState: retryState ?? this.retryState,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      queueGapState: queueGapState ?? this.queueGapState,
      drainRequested: drainRequested ?? this.drainRequested,
      connectionPhase: connectionPhase ?? this.connectionPhase,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      reconnectAt: reconnectAt ?? this.reconnectAt,
      lastSuccessfulSyncAt: lastSuccessfulSyncAt ?? this.lastSuccessfulSyncAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singletonId.present) {
      map['singleton_id'] = Variable<int>(singletonId.value);
    }
    if (highestContiguousAckedSequence.present) {
      map['highest_contiguous_acked_sequence'] = Variable<int>(
        highestContiguousAckedSequence.value,
      );
    }
    if (prunedThrough.present) {
      map['pruned_through'] = Variable<int>(prunedThrough.value);
    }
    if (etagsCiphertext.present) {
      map['etags_ciphertext'] = Variable<Uint8List>(etagsCiphertext.value);
    }
    if (retryState.present) {
      map['retry_state'] = Variable<int>(retryState.value);
    }
    if (protocolVersion.present) {
      map['protocol_version'] = Variable<int>(protocolVersion.value);
    }
    if (queueGapState.present) {
      map['queue_gap_state'] = Variable<int>(queueGapState.value);
    }
    if (drainRequested.present) {
      map['drain_requested'] = Variable<bool>(drainRequested.value);
    }
    if (connectionPhase.present) {
      map['connection_phase'] = Variable<int>(connectionPhase.value);
    }
    if (reconnectAttempt.present) {
      map['reconnect_attempt'] = Variable<int>(reconnectAttempt.value);
    }
    if (reconnectAt.present) {
      map['reconnect_at'] = Variable<DateTime>(reconnectAt.value);
    }
    if (lastSuccessfulSyncAt.present) {
      map['last_successful_sync_at'] = Variable<DateTime>(
        lastSuccessfulSyncAt.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCheckpointsCompanion(')
          ..write('singletonId: $singletonId, ')
          ..write(
            'highestContiguousAckedSequence: $highestContiguousAckedSequence, ',
          )
          ..write('prunedThrough: $prunedThrough, ')
          ..write('etagsCiphertext: $etagsCiphertext, ')
          ..write('retryState: $retryState, ')
          ..write('protocolVersion: $protocolVersion, ')
          ..write('queueGapState: $queueGapState, ')
          ..write('drainRequested: $drainRequested, ')
          ..write('connectionPhase: $connectionPhase, ')
          ..write('reconnectAttempt: $reconnectAttempt, ')
          ..write('reconnectAt: $reconnectAt, ')
          ..write('lastSuccessfulSyncAt: $lastSuccessfulSyncAt')
          ..write(')'))
        .toString();
  }
}

class $LocalPreferencesTable extends LocalPreferences
    with TableInfo<$LocalPreferencesTable, LocalPreference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _preferenceKeyMeta = const VerificationMeta(
    'preferenceKey',
  );
  @override
  late final GeneratedColumn<String> preferenceKey = GeneratedColumn<String>(
    'preference_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueCiphertextMeta = const VerificationMeta(
    'valueCiphertext',
  );
  @override
  late final GeneratedColumn<Uint8List> valueCiphertext =
      GeneratedColumn<Uint8List>(
        'value_ciphertext',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _valueVersionMeta = const VerificationMeta(
    'valueVersion',
  );
  @override
  late final GeneratedColumn<int> valueVersion = GeneratedColumn<int>(
    'value_version',
    aliasedName,
    false,
    check: () => ComparableExpr(valueVersion).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    preferenceKey,
    valueCiphertext,
    valueVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalPreference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('preference_key')) {
      context.handle(
        _preferenceKeyMeta,
        preferenceKey.isAcceptableOrUnknown(
          data['preference_key']!,
          _preferenceKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_preferenceKeyMeta);
    }
    if (data.containsKey('value_ciphertext')) {
      context.handle(
        _valueCiphertextMeta,
        valueCiphertext.isAcceptableOrUnknown(
          data['value_ciphertext']!,
          _valueCiphertextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_valueCiphertextMeta);
    }
    if (data.containsKey('value_version')) {
      context.handle(
        _valueVersionMeta,
        valueVersion.isAcceptableOrUnknown(
          data['value_version']!,
          _valueVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_valueVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {preferenceKey};
  @override
  LocalPreference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPreference(
      preferenceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preference_key'],
      )!,
      valueCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}value_ciphertext'],
      )!,
      valueVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value_version'],
      )!,
    );
  }

  @override
  $LocalPreferencesTable createAlias(String alias) {
    return $LocalPreferencesTable(attachedDatabase, alias);
  }
}

class LocalPreference extends DataClass implements Insertable<LocalPreference> {
  final String preferenceKey;
  final Uint8List valueCiphertext;
  final int valueVersion;
  const LocalPreference({
    required this.preferenceKey,
    required this.valueCiphertext,
    required this.valueVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['preference_key'] = Variable<String>(preferenceKey);
    map['value_ciphertext'] = Variable<Uint8List>(valueCiphertext);
    map['value_version'] = Variable<int>(valueVersion);
    return map;
  }

  LocalPreferencesCompanion toCompanion(bool nullToAbsent) {
    return LocalPreferencesCompanion(
      preferenceKey: Value(preferenceKey),
      valueCiphertext: Value(valueCiphertext),
      valueVersion: Value(valueVersion),
    );
  }

  factory LocalPreference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPreference(
      preferenceKey: serializer.fromJson<String>(json['preferenceKey']),
      valueCiphertext: serializer.fromJson<Uint8List>(json['valueCiphertext']),
      valueVersion: serializer.fromJson<int>(json['valueVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'preferenceKey': serializer.toJson<String>(preferenceKey),
      'valueCiphertext': serializer.toJson<Uint8List>(valueCiphertext),
      'valueVersion': serializer.toJson<int>(valueVersion),
    };
  }

  LocalPreference copyWith({
    String? preferenceKey,
    Uint8List? valueCiphertext,
    int? valueVersion,
  }) => LocalPreference(
    preferenceKey: preferenceKey ?? this.preferenceKey,
    valueCiphertext: valueCiphertext ?? this.valueCiphertext,
    valueVersion: valueVersion ?? this.valueVersion,
  );
  LocalPreference copyWithCompanion(LocalPreferencesCompanion data) {
    return LocalPreference(
      preferenceKey: data.preferenceKey.present
          ? data.preferenceKey.value
          : this.preferenceKey,
      valueCiphertext: data.valueCiphertext.present
          ? data.valueCiphertext.value
          : this.valueCiphertext,
      valueVersion: data.valueVersion.present
          ? data.valueVersion.value
          : this.valueVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPreference(')
          ..write('preferenceKey: $preferenceKey, ')
          ..write('valueCiphertext: $valueCiphertext, ')
          ..write('valueVersion: $valueVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    preferenceKey,
    $driftBlobEquality.hash(valueCiphertext),
    valueVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPreference &&
          other.preferenceKey == this.preferenceKey &&
          $driftBlobEquality.equals(
            other.valueCiphertext,
            this.valueCiphertext,
          ) &&
          other.valueVersion == this.valueVersion);
}

class LocalPreferencesCompanion extends UpdateCompanion<LocalPreference> {
  final Value<String> preferenceKey;
  final Value<Uint8List> valueCiphertext;
  final Value<int> valueVersion;
  final Value<int> rowid;
  const LocalPreferencesCompanion({
    this.preferenceKey = const Value.absent(),
    this.valueCiphertext = const Value.absent(),
    this.valueVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalPreferencesCompanion.insert({
    required String preferenceKey,
    required Uint8List valueCiphertext,
    required int valueVersion,
    this.rowid = const Value.absent(),
  }) : preferenceKey = Value(preferenceKey),
       valueCiphertext = Value(valueCiphertext),
       valueVersion = Value(valueVersion);
  static Insertable<LocalPreference> custom({
    Expression<String>? preferenceKey,
    Expression<Uint8List>? valueCiphertext,
    Expression<int>? valueVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (preferenceKey != null) 'preference_key': preferenceKey,
      if (valueCiphertext != null) 'value_ciphertext': valueCiphertext,
      if (valueVersion != null) 'value_version': valueVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalPreferencesCompanion copyWith({
    Value<String>? preferenceKey,
    Value<Uint8List>? valueCiphertext,
    Value<int>? valueVersion,
    Value<int>? rowid,
  }) {
    return LocalPreferencesCompanion(
      preferenceKey: preferenceKey ?? this.preferenceKey,
      valueCiphertext: valueCiphertext ?? this.valueCiphertext,
      valueVersion: valueVersion ?? this.valueVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (preferenceKey.present) {
      map['preference_key'] = Variable<String>(preferenceKey.value);
    }
    if (valueCiphertext.present) {
      map['value_ciphertext'] = Variable<Uint8List>(valueCiphertext.value);
    }
    if (valueVersion.present) {
      map['value_version'] = Variable<int>(valueVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPreferencesCompanion(')
          ..write('preferenceKey: $preferenceKey, ')
          ..write('valueCiphertext: $valueCiphertext, ')
          ..write('valueVersion: $valueVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QuarantineRecordsTable extends QuarantineRecords
    with TableInfo<$QuarantineRecordsTable, QuarantineRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QuarantineRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _reasonCodeMeta = const VerificationMeta(
    'reasonCode',
  );
  @override
  late final GeneratedColumn<int> reasonCode = GeneratedColumn<int>(
    'reason_code',
    aliasedName,
    false,
    check: () => ComparableExpr(reasonCode).isBetweenValues(0, 63),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opaqueDigestMeta = const VerificationMeta(
    'opaqueDigest',
  );
  @override
  late final GeneratedColumn<Uint8List> opaqueDigest =
      GeneratedColumn<Uint8List>(
        'opaque_digest',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
    'received_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    reasonCode,
    opaqueDigest,
    receivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'quarantine';
  @override
  VerificationContext validateIntegrity(
    Insertable<QuarantineRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('reason_code')) {
      context.handle(
        _reasonCodeMeta,
        reasonCode.isAcceptableOrUnknown(data['reason_code']!, _reasonCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonCodeMeta);
    }
    if (data.containsKey('opaque_digest')) {
      context.handle(
        _opaqueDigestMeta,
        opaqueDigest.isAcceptableOrUnknown(
          data['opaque_digest']!,
          _opaqueDigestMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_opaqueDigestMeta);
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QuarantineRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QuarantineRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      reasonCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reason_code'],
      )!,
      opaqueDigest: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}opaque_digest'],
      )!,
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}received_at'],
      )!,
    );
  }

  @override
  $QuarantineRecordsTable createAlias(String alias) {
    return $QuarantineRecordsTable(attachedDatabase, alias);
  }
}

class QuarantineRecord extends DataClass
    implements Insertable<QuarantineRecord> {
  final int id;
  final int reasonCode;
  final Uint8List opaqueDigest;
  final DateTime receivedAt;
  const QuarantineRecord({
    required this.id,
    required this.reasonCode,
    required this.opaqueDigest,
    required this.receivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['reason_code'] = Variable<int>(reasonCode);
    map['opaque_digest'] = Variable<Uint8List>(opaqueDigest);
    map['received_at'] = Variable<DateTime>(receivedAt);
    return map;
  }

  QuarantineRecordsCompanion toCompanion(bool nullToAbsent) {
    return QuarantineRecordsCompanion(
      id: Value(id),
      reasonCode: Value(reasonCode),
      opaqueDigest: Value(opaqueDigest),
      receivedAt: Value(receivedAt),
    );
  }

  factory QuarantineRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QuarantineRecord(
      id: serializer.fromJson<int>(json['id']),
      reasonCode: serializer.fromJson<int>(json['reasonCode']),
      opaqueDigest: serializer.fromJson<Uint8List>(json['opaqueDigest']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'reasonCode': serializer.toJson<int>(reasonCode),
      'opaqueDigest': serializer.toJson<Uint8List>(opaqueDigest),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
    };
  }

  QuarantineRecord copyWith({
    int? id,
    int? reasonCode,
    Uint8List? opaqueDigest,
    DateTime? receivedAt,
  }) => QuarantineRecord(
    id: id ?? this.id,
    reasonCode: reasonCode ?? this.reasonCode,
    opaqueDigest: opaqueDigest ?? this.opaqueDigest,
    receivedAt: receivedAt ?? this.receivedAt,
  );
  QuarantineRecord copyWithCompanion(QuarantineRecordsCompanion data) {
    return QuarantineRecord(
      id: data.id.present ? data.id.value : this.id,
      reasonCode: data.reasonCode.present
          ? data.reasonCode.value
          : this.reasonCode,
      opaqueDigest: data.opaqueDigest.present
          ? data.opaqueDigest.value
          : this.opaqueDigest,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QuarantineRecord(')
          ..write('id: $id, ')
          ..write('reasonCode: $reasonCode, ')
          ..write('opaqueDigest: $opaqueDigest, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    reasonCode,
    $driftBlobEquality.hash(opaqueDigest),
    receivedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QuarantineRecord &&
          other.id == this.id &&
          other.reasonCode == this.reasonCode &&
          $driftBlobEquality.equals(other.opaqueDigest, this.opaqueDigest) &&
          other.receivedAt == this.receivedAt);
}

class QuarantineRecordsCompanion extends UpdateCompanion<QuarantineRecord> {
  final Value<int> id;
  final Value<int> reasonCode;
  final Value<Uint8List> opaqueDigest;
  final Value<DateTime> receivedAt;
  const QuarantineRecordsCompanion({
    this.id = const Value.absent(),
    this.reasonCode = const Value.absent(),
    this.opaqueDigest = const Value.absent(),
    this.receivedAt = const Value.absent(),
  });
  QuarantineRecordsCompanion.insert({
    this.id = const Value.absent(),
    required int reasonCode,
    required Uint8List opaqueDigest,
    this.receivedAt = const Value.absent(),
  }) : reasonCode = Value(reasonCode),
       opaqueDigest = Value(opaqueDigest);
  static Insertable<QuarantineRecord> custom({
    Expression<int>? id,
    Expression<int>? reasonCode,
    Expression<Uint8List>? opaqueDigest,
    Expression<DateTime>? receivedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (reasonCode != null) 'reason_code': reasonCode,
      if (opaqueDigest != null) 'opaque_digest': opaqueDigest,
      if (receivedAt != null) 'received_at': receivedAt,
    });
  }

  QuarantineRecordsCompanion copyWith({
    Value<int>? id,
    Value<int>? reasonCode,
    Value<Uint8List>? opaqueDigest,
    Value<DateTime>? receivedAt,
  }) {
    return QuarantineRecordsCompanion(
      id: id ?? this.id,
      reasonCode: reasonCode ?? this.reasonCode,
      opaqueDigest: opaqueDigest ?? this.opaqueDigest,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (reasonCode.present) {
      map['reason_code'] = Variable<int>(reasonCode.value);
    }
    if (opaqueDigest.present) {
      map['opaque_digest'] = Variable<Uint8List>(opaqueDigest.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QuarantineRecordsCompanion(')
          ..write('id: $id, ')
          ..write('reasonCode: $reasonCode, ')
          ..write('opaqueDigest: $opaqueDigest, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final $AccountSessionsTable accountSessions = $AccountSessionsTable(
    this,
  );
  late final $SecureSecretsTable secureSecrets = $SecureSecretsTable(this);
  late final $AccountIdentitiesTable accountIdentities =
      $AccountIdentitiesTable(this);
  late final $EnrollmentIntentsTable enrollmentIntents =
      $EnrollmentIntentsTable(this);
  late final $UsersTable users = $UsersTable(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $DevicesTable devices = $DevicesTable(this);
  late final $DeviceLogRecordsTable deviceLogRecords = $DeviceLogRecordsTable(
    this,
  );
  late final $PairwiseSessionsTable pairwiseSessions = $PairwiseSessionsTable(
    this,
  );
  late final $PrekeysTable prekeys = $PrekeysTable(this);
  late final $MlsGroupsTable mlsGroups = $MlsGroupsTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MembershipsTable memberships = $MembershipsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $MessageEventsTable messageEvents = $MessageEventsTable(this);
  late final $AttachmentsTable attachments = $AttachmentsTable(this);
  late final $InboxEnvelopesTable inboxEnvelopes = $InboxEnvelopesTable(this);
  late final $OutboxOperationsTable outboxOperations = $OutboxOperationsTable(
    this,
  );
  late final $InboxEventDeduplicationsTable inboxEventDeduplications =
      $InboxEventDeduplicationsTable(this);
  late final $StaleDeviceRefreshRequestsTable staleDeviceRefreshRequests =
      $StaleDeviceRefreshRequestsTable(this);
  late final $ReceiptsTable receipts = $ReceiptsTable(this);
  late final $VoiceRoomsTable voiceRooms = $VoiceRoomsTable(this);
  late final $HistoryTransfersTable historyTransfers = $HistoryTransfersTable(
    this,
  );
  late final $SyncCheckpointsTable syncCheckpoints = $SyncCheckpointsTable(
    this,
  );
  late final $LocalPreferencesTable localPreferences = $LocalPreferencesTable(
    this,
  );
  late final $QuarantineRecordsTable quarantineRecords =
      $QuarantineRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    accountSessions,
    secureSecrets,
    accountIdentities,
    enrollmentIntents,
    users,
    profiles,
    devices,
    deviceLogRecords,
    pairwiseSessions,
    prekeys,
    mlsGroups,
    conversations,
    memberships,
    messages,
    messageEvents,
    attachments,
    inboxEnvelopes,
    outboxOperations,
    inboxEventDeduplications,
    staleDeviceRefreshRequests,
    receipts,
    voiceRooms,
    historyTransfers,
    syncCheckpoints,
    localPreferences,
    quarantineRecords,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'users',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('profiles', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'users',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('devices', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'users',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('device_log', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('memberships', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'users',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('memberships', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('message_events', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('attachments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('receipts', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$AccountSessionsTableCreateCompanionBuilder =
    AccountSessionsCompanion Function({
      Value<int> singletonId,
      required Uint8List userIdCiphertext,
      Value<Uint8List?> deviceIdCiphertext,
      required int scope,
      required Uint8List tokenMetadataCiphertext,
      required Uint8List serverProfileCiphertext,
      Value<DateTime?> expiresAt,
    });
typedef $$AccountSessionsTableUpdateCompanionBuilder =
    AccountSessionsCompanion Function({
      Value<int> singletonId,
      Value<Uint8List> userIdCiphertext,
      Value<Uint8List?> deviceIdCiphertext,
      Value<int> scope,
      Value<Uint8List> tokenMetadataCiphertext,
      Value<Uint8List> serverProfileCiphertext,
      Value<DateTime?> expiresAt,
    });

class $$AccountSessionsTableFilterComposer
    extends Composer<_$LocalDatabase, $AccountSessionsTable> {
  $$AccountSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get userIdCiphertext => $composableBuilder(
    column: $table.userIdCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get deviceIdCiphertext => $composableBuilder(
    column: $table.deviceIdCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get tokenMetadataCiphertext => $composableBuilder(
    column: $table.tokenMetadataCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get serverProfileCiphertext => $composableBuilder(
    column: $table.serverProfileCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountSessionsTableOrderingComposer
    extends Composer<_$LocalDatabase, $AccountSessionsTable> {
  $$AccountSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get userIdCiphertext => $composableBuilder(
    column: $table.userIdCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get deviceIdCiphertext => $composableBuilder(
    column: $table.deviceIdCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get tokenMetadataCiphertext => $composableBuilder(
    column: $table.tokenMetadataCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get serverProfileCiphertext => $composableBuilder(
    column: $table.serverProfileCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountSessionsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $AccountSessionsTable> {
  $$AccountSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get userIdCiphertext => $composableBuilder(
    column: $table.userIdCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get deviceIdCiphertext => $composableBuilder(
    column: $table.deviceIdCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<Uint8List> get tokenMetadataCiphertext => $composableBuilder(
    column: $table.tokenMetadataCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get serverProfileCiphertext => $composableBuilder(
    column: $table.serverProfileCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$AccountSessionsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $AccountSessionsTable,
          AccountSession,
          $$AccountSessionsTableFilterComposer,
          $$AccountSessionsTableOrderingComposer,
          $$AccountSessionsTableAnnotationComposer,
          $$AccountSessionsTableCreateCompanionBuilder,
          $$AccountSessionsTableUpdateCompanionBuilder,
          (
            AccountSession,
            BaseReferences<
              _$LocalDatabase,
              $AccountSessionsTable,
              AccountSession
            >,
          ),
          AccountSession,
          PrefetchHooks Function()
        > {
  $$AccountSessionsTableTableManager(
    _$LocalDatabase db,
    $AccountSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> singletonId = const Value.absent(),
                Value<Uint8List> userIdCiphertext = const Value.absent(),
                Value<Uint8List?> deviceIdCiphertext = const Value.absent(),
                Value<int> scope = const Value.absent(),
                Value<Uint8List> tokenMetadataCiphertext = const Value.absent(),
                Value<Uint8List> serverProfileCiphertext = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
              }) => AccountSessionsCompanion(
                singletonId: singletonId,
                userIdCiphertext: userIdCiphertext,
                deviceIdCiphertext: deviceIdCiphertext,
                scope: scope,
                tokenMetadataCiphertext: tokenMetadataCiphertext,
                serverProfileCiphertext: serverProfileCiphertext,
                expiresAt: expiresAt,
              ),
          createCompanionCallback:
              ({
                Value<int> singletonId = const Value.absent(),
                required Uint8List userIdCiphertext,
                Value<Uint8List?> deviceIdCiphertext = const Value.absent(),
                required int scope,
                required Uint8List tokenMetadataCiphertext,
                required Uint8List serverProfileCiphertext,
                Value<DateTime?> expiresAt = const Value.absent(),
              }) => AccountSessionsCompanion.insert(
                singletonId: singletonId,
                userIdCiphertext: userIdCiphertext,
                deviceIdCiphertext: deviceIdCiphertext,
                scope: scope,
                tokenMetadataCiphertext: tokenMetadataCiphertext,
                serverProfileCiphertext: serverProfileCiphertext,
                expiresAt: expiresAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $AccountSessionsTable,
      AccountSession,
      $$AccountSessionsTableFilterComposer,
      $$AccountSessionsTableOrderingComposer,
      $$AccountSessionsTableAnnotationComposer,
      $$AccountSessionsTableCreateCompanionBuilder,
      $$AccountSessionsTableUpdateCompanionBuilder,
      (
        AccountSession,
        BaseReferences<_$LocalDatabase, $AccountSessionsTable, AccountSession>,
      ),
      AccountSession,
      PrefetchHooks Function()
    >;
typedef $$SecureSecretsTableCreateCompanionBuilder =
    SecureSecretsCompanion Function({
      Value<DateTime> createdAt,
      required String secretId,
      required int kind,
      required Uint8List wrappedCiphertextOrOpaqueHandle,
      required int formatVersion,
      Value<int> rowid,
    });
typedef $$SecureSecretsTableUpdateCompanionBuilder =
    SecureSecretsCompanion Function({
      Value<DateTime> createdAt,
      Value<String> secretId,
      Value<int> kind,
      Value<Uint8List> wrappedCiphertextOrOpaqueHandle,
      Value<int> formatVersion,
      Value<int> rowid,
    });

class $$SecureSecretsTableFilterComposer
    extends Composer<_$LocalDatabase, $SecureSecretsTable> {
  $$SecureSecretsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secretId => $composableBuilder(
    column: $table.secretId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get wrappedCiphertextOrOpaqueHandle =>
      $composableBuilder(
        column: $table.wrappedCiphertextOrOpaqueHandle,
        builder: (column) => ColumnFilters(column),
      );

  ColumnFilters<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SecureSecretsTableOrderingComposer
    extends Composer<_$LocalDatabase, $SecureSecretsTable> {
  $$SecureSecretsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secretId => $composableBuilder(
    column: $table.secretId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get wrappedCiphertextOrOpaqueHandle =>
      $composableBuilder(
        column: $table.wrappedCiphertextOrOpaqueHandle,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SecureSecretsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $SecureSecretsTable> {
  $$SecureSecretsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get secretId =>
      $composableBuilder(column: $table.secretId, builder: (column) => column);

  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<Uint8List> get wrappedCiphertextOrOpaqueHandle =>
      $composableBuilder(
        column: $table.wrappedCiphertextOrOpaqueHandle,
        builder: (column) => column,
      );

  GeneratedColumn<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => column,
  );
}

class $$SecureSecretsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $SecureSecretsTable,
          SecureSecret,
          $$SecureSecretsTableFilterComposer,
          $$SecureSecretsTableOrderingComposer,
          $$SecureSecretsTableAnnotationComposer,
          $$SecureSecretsTableCreateCompanionBuilder,
          $$SecureSecretsTableUpdateCompanionBuilder,
          (
            SecureSecret,
            BaseReferences<_$LocalDatabase, $SecureSecretsTable, SecureSecret>,
          ),
          SecureSecret,
          PrefetchHooks Function()
        > {
  $$SecureSecretsTableTableManager(
    _$LocalDatabase db,
    $SecureSecretsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SecureSecretsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SecureSecretsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SecureSecretsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> secretId = const Value.absent(),
                Value<int> kind = const Value.absent(),
                Value<Uint8List> wrappedCiphertextOrOpaqueHandle =
                    const Value.absent(),
                Value<int> formatVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SecureSecretsCompanion(
                createdAt: createdAt,
                secretId: secretId,
                kind: kind,
                wrappedCiphertextOrOpaqueHandle:
                    wrappedCiphertextOrOpaqueHandle,
                formatVersion: formatVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                required String secretId,
                required int kind,
                required Uint8List wrappedCiphertextOrOpaqueHandle,
                required int formatVersion,
                Value<int> rowid = const Value.absent(),
              }) => SecureSecretsCompanion.insert(
                createdAt: createdAt,
                secretId: secretId,
                kind: kind,
                wrappedCiphertextOrOpaqueHandle:
                    wrappedCiphertextOrOpaqueHandle,
                formatVersion: formatVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SecureSecretsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $SecureSecretsTable,
      SecureSecret,
      $$SecureSecretsTableFilterComposer,
      $$SecureSecretsTableOrderingComposer,
      $$SecureSecretsTableAnnotationComposer,
      $$SecureSecretsTableCreateCompanionBuilder,
      $$SecureSecretsTableUpdateCompanionBuilder,
      (
        SecureSecret,
        BaseReferences<_$LocalDatabase, $SecureSecretsTable, SecureSecret>,
      ),
      SecureSecret,
      PrefetchHooks Function()
    >;
typedef $$AccountIdentitiesTableCreateCompanionBuilder =
    AccountIdentitiesCompanion Function({
      Value<int> singletonId,
      required Uint8List verifiedPublicStateCiphertext,
      Value<int> backupVersion,
      required int recoveryStatus,
    });
typedef $$AccountIdentitiesTableUpdateCompanionBuilder =
    AccountIdentitiesCompanion Function({
      Value<int> singletonId,
      Value<Uint8List> verifiedPublicStateCiphertext,
      Value<int> backupVersion,
      Value<int> recoveryStatus,
    });

class $$AccountIdentitiesTableFilterComposer
    extends Composer<_$LocalDatabase, $AccountIdentitiesTable> {
  $$AccountIdentitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get verifiedPublicStateCiphertext =>
      $composableBuilder(
        column: $table.verifiedPublicStateCiphertext,
        builder: (column) => ColumnFilters(column),
      );

  ColumnFilters<int> get backupVersion => $composableBuilder(
    column: $table.backupVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recoveryStatus => $composableBuilder(
    column: $table.recoveryStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountIdentitiesTableOrderingComposer
    extends Composer<_$LocalDatabase, $AccountIdentitiesTable> {
  $$AccountIdentitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get verifiedPublicStateCiphertext =>
      $composableBuilder(
        column: $table.verifiedPublicStateCiphertext,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<int> get backupVersion => $composableBuilder(
    column: $table.backupVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recoveryStatus => $composableBuilder(
    column: $table.recoveryStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountIdentitiesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $AccountIdentitiesTable> {
  $$AccountIdentitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get verifiedPublicStateCiphertext =>
      $composableBuilder(
        column: $table.verifiedPublicStateCiphertext,
        builder: (column) => column,
      );

  GeneratedColumn<int> get backupVersion => $composableBuilder(
    column: $table.backupVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recoveryStatus => $composableBuilder(
    column: $table.recoveryStatus,
    builder: (column) => column,
  );
}

class $$AccountIdentitiesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $AccountIdentitiesTable,
          AccountIdentity,
          $$AccountIdentitiesTableFilterComposer,
          $$AccountIdentitiesTableOrderingComposer,
          $$AccountIdentitiesTableAnnotationComposer,
          $$AccountIdentitiesTableCreateCompanionBuilder,
          $$AccountIdentitiesTableUpdateCompanionBuilder,
          (
            AccountIdentity,
            BaseReferences<
              _$LocalDatabase,
              $AccountIdentitiesTable,
              AccountIdentity
            >,
          ),
          AccountIdentity,
          PrefetchHooks Function()
        > {
  $$AccountIdentitiesTableTableManager(
    _$LocalDatabase db,
    $AccountIdentitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountIdentitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountIdentitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountIdentitiesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> singletonId = const Value.absent(),
                Value<Uint8List> verifiedPublicStateCiphertext =
                    const Value.absent(),
                Value<int> backupVersion = const Value.absent(),
                Value<int> recoveryStatus = const Value.absent(),
              }) => AccountIdentitiesCompanion(
                singletonId: singletonId,
                verifiedPublicStateCiphertext: verifiedPublicStateCiphertext,
                backupVersion: backupVersion,
                recoveryStatus: recoveryStatus,
              ),
          createCompanionCallback:
              ({
                Value<int> singletonId = const Value.absent(),
                required Uint8List verifiedPublicStateCiphertext,
                Value<int> backupVersion = const Value.absent(),
                required int recoveryStatus,
              }) => AccountIdentitiesCompanion.insert(
                singletonId: singletonId,
                verifiedPublicStateCiphertext: verifiedPublicStateCiphertext,
                backupVersion: backupVersion,
                recoveryStatus: recoveryStatus,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountIdentitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $AccountIdentitiesTable,
      AccountIdentity,
      $$AccountIdentitiesTableFilterComposer,
      $$AccountIdentitiesTableOrderingComposer,
      $$AccountIdentitiesTableAnnotationComposer,
      $$AccountIdentitiesTableCreateCompanionBuilder,
      $$AccountIdentitiesTableUpdateCompanionBuilder,
      (
        AccountIdentity,
        BaseReferences<
          _$LocalDatabase,
          $AccountIdentitiesTable,
          AccountIdentity
        >,
      ),
      AccountIdentity,
      PrefetchHooks Function()
    >;
typedef $$EnrollmentIntentsTableCreateCompanionBuilder =
    EnrollmentIntentsCompanion Function({
      required String userId,
      required int flow,
      required int phase,
      required Uint8List fingerprint,
      required Uint8List deviceState,
      Value<String?> deviceId,
      Value<Uint8List?> identityState,
      Value<Uint8List?> backup,
      Value<int> backupVersion,
      Value<int> identityVersion,
      Value<int?> expectedSequence,
      Value<Uint8List?> previousHash,
      Value<Uint8List?> pendingLogRecord,
      Value<int?> message,
      Value<bool> recoverySecretDisplayed,
      Value<bool> recoveryConfirmed,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$EnrollmentIntentsTableUpdateCompanionBuilder =
    EnrollmentIntentsCompanion Function({
      Value<String> userId,
      Value<int> flow,
      Value<int> phase,
      Value<Uint8List> fingerprint,
      Value<Uint8List> deviceState,
      Value<String?> deviceId,
      Value<Uint8List?> identityState,
      Value<Uint8List?> backup,
      Value<int> backupVersion,
      Value<int> identityVersion,
      Value<int?> expectedSequence,
      Value<Uint8List?> previousHash,
      Value<Uint8List?> pendingLogRecord,
      Value<int?> message,
      Value<bool> recoverySecretDisplayed,
      Value<bool> recoveryConfirmed,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$EnrollmentIntentsTableFilterComposer
    extends Composer<_$LocalDatabase, $EnrollmentIntentsTable> {
  $$EnrollmentIntentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get flow => $composableBuilder(
    column: $table.flow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get deviceState => $composableBuilder(
    column: $table.deviceState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get identityState => $composableBuilder(
    column: $table.identityState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get backup => $composableBuilder(
    column: $table.backup,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get backupVersion => $composableBuilder(
    column: $table.backupVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get identityVersion => $composableBuilder(
    column: $table.identityVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedSequence => $composableBuilder(
    column: $table.expectedSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get previousHash => $composableBuilder(
    column: $table.previousHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get pendingLogRecord => $composableBuilder(
    column: $table.pendingLogRecord,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get recoverySecretDisplayed => $composableBuilder(
    column: $table.recoverySecretDisplayed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get recoveryConfirmed => $composableBuilder(
    column: $table.recoveryConfirmed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EnrollmentIntentsTableOrderingComposer
    extends Composer<_$LocalDatabase, $EnrollmentIntentsTable> {
  $$EnrollmentIntentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get flow => $composableBuilder(
    column: $table.flow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get deviceState => $composableBuilder(
    column: $table.deviceState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get identityState => $composableBuilder(
    column: $table.identityState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get backup => $composableBuilder(
    column: $table.backup,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get backupVersion => $composableBuilder(
    column: $table.backupVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get identityVersion => $composableBuilder(
    column: $table.identityVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedSequence => $composableBuilder(
    column: $table.expectedSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get previousHash => $composableBuilder(
    column: $table.previousHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get pendingLogRecord => $composableBuilder(
    column: $table.pendingLogRecord,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get recoverySecretDisplayed => $composableBuilder(
    column: $table.recoverySecretDisplayed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get recoveryConfirmed => $composableBuilder(
    column: $table.recoveryConfirmed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EnrollmentIntentsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $EnrollmentIntentsTable> {
  $$EnrollmentIntentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get flow =>
      $composableBuilder(column: $table.flow, builder: (column) => column);

  GeneratedColumn<int> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<Uint8List> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get deviceState => $composableBuilder(
    column: $table.deviceState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<Uint8List> get identityState => $composableBuilder(
    column: $table.identityState,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get backup =>
      $composableBuilder(column: $table.backup, builder: (column) => column);

  GeneratedColumn<int> get backupVersion => $composableBuilder(
    column: $table.backupVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get identityVersion => $composableBuilder(
    column: $table.identityVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expectedSequence => $composableBuilder(
    column: $table.expectedSequence,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get previousHash => $composableBuilder(
    column: $table.previousHash,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get pendingLogRecord => $composableBuilder(
    column: $table.pendingLogRecord,
    builder: (column) => column,
  );

  GeneratedColumn<int> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<bool> get recoverySecretDisplayed => $composableBuilder(
    column: $table.recoverySecretDisplayed,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get recoveryConfirmed => $composableBuilder(
    column: $table.recoveryConfirmed,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$EnrollmentIntentsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $EnrollmentIntentsTable,
          EnrollmentIntent,
          $$EnrollmentIntentsTableFilterComposer,
          $$EnrollmentIntentsTableOrderingComposer,
          $$EnrollmentIntentsTableAnnotationComposer,
          $$EnrollmentIntentsTableCreateCompanionBuilder,
          $$EnrollmentIntentsTableUpdateCompanionBuilder,
          (
            EnrollmentIntent,
            BaseReferences<
              _$LocalDatabase,
              $EnrollmentIntentsTable,
              EnrollmentIntent
            >,
          ),
          EnrollmentIntent,
          PrefetchHooks Function()
        > {
  $$EnrollmentIntentsTableTableManager(
    _$LocalDatabase db,
    $EnrollmentIntentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EnrollmentIntentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EnrollmentIntentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EnrollmentIntentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<int> flow = const Value.absent(),
                Value<int> phase = const Value.absent(),
                Value<Uint8List> fingerprint = const Value.absent(),
                Value<Uint8List> deviceState = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<Uint8List?> identityState = const Value.absent(),
                Value<Uint8List?> backup = const Value.absent(),
                Value<int> backupVersion = const Value.absent(),
                Value<int> identityVersion = const Value.absent(),
                Value<int?> expectedSequence = const Value.absent(),
                Value<Uint8List?> previousHash = const Value.absent(),
                Value<Uint8List?> pendingLogRecord = const Value.absent(),
                Value<int?> message = const Value.absent(),
                Value<bool> recoverySecretDisplayed = const Value.absent(),
                Value<bool> recoveryConfirmed = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EnrollmentIntentsCompanion(
                userId: userId,
                flow: flow,
                phase: phase,
                fingerprint: fingerprint,
                deviceState: deviceState,
                deviceId: deviceId,
                identityState: identityState,
                backup: backup,
                backupVersion: backupVersion,
                identityVersion: identityVersion,
                expectedSequence: expectedSequence,
                previousHash: previousHash,
                pendingLogRecord: pendingLogRecord,
                message: message,
                recoverySecretDisplayed: recoverySecretDisplayed,
                recoveryConfirmed: recoveryConfirmed,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required int flow,
                required int phase,
                required Uint8List fingerprint,
                required Uint8List deviceState,
                Value<String?> deviceId = const Value.absent(),
                Value<Uint8List?> identityState = const Value.absent(),
                Value<Uint8List?> backup = const Value.absent(),
                Value<int> backupVersion = const Value.absent(),
                Value<int> identityVersion = const Value.absent(),
                Value<int?> expectedSequence = const Value.absent(),
                Value<Uint8List?> previousHash = const Value.absent(),
                Value<Uint8List?> pendingLogRecord = const Value.absent(),
                Value<int?> message = const Value.absent(),
                Value<bool> recoverySecretDisplayed = const Value.absent(),
                Value<bool> recoveryConfirmed = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EnrollmentIntentsCompanion.insert(
                userId: userId,
                flow: flow,
                phase: phase,
                fingerprint: fingerprint,
                deviceState: deviceState,
                deviceId: deviceId,
                identityState: identityState,
                backup: backup,
                backupVersion: backupVersion,
                identityVersion: identityVersion,
                expectedSequence: expectedSequence,
                previousHash: previousHash,
                pendingLogRecord: pendingLogRecord,
                message: message,
                recoverySecretDisplayed: recoverySecretDisplayed,
                recoveryConfirmed: recoveryConfirmed,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EnrollmentIntentsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $EnrollmentIntentsTable,
      EnrollmentIntent,
      $$EnrollmentIntentsTableFilterComposer,
      $$EnrollmentIntentsTableOrderingComposer,
      $$EnrollmentIntentsTableAnnotationComposer,
      $$EnrollmentIntentsTableCreateCompanionBuilder,
      $$EnrollmentIntentsTableUpdateCompanionBuilder,
      (
        EnrollmentIntent,
        BaseReferences<
          _$LocalDatabase,
          $EnrollmentIntentsTable,
          EnrollmentIntent
        >,
      ),
      EnrollmentIntent,
      PrefetchHooks Function()
    >;
typedef $$UsersTableCreateCompanionBuilder =
    UsersCompanion Function({
      required String userId,
      required bool activated,
      required Uint8List directoryEntryCiphertext,
      required int localState,
      Value<int> rowid,
    });
typedef $$UsersTableUpdateCompanionBuilder =
    UsersCompanion Function({
      Value<String> userId,
      Value<bool> activated,
      Value<Uint8List> directoryEntryCiphertext,
      Value<int> localState,
      Value<int> rowid,
    });

final class $$UsersTableReferences
    extends BaseReferences<_$LocalDatabase, $UsersTable, User> {
  $$UsersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ProfilesTable, List<Profile>> _profilesRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.profiles,
    aliasName: 'users__user_id__profiles__user_id',
  );

  $$ProfilesTableProcessedTableManager get profilesRefs {
    final manager = $$ProfilesTableTableManager($_db, $_db.profiles).filter(
      (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_profilesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DevicesTable, List<Device>> _devicesRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.devices,
    aliasName: 'users__user_id__devices__user_id',
  );

  $$DevicesTableProcessedTableManager get devicesRefs {
    final manager = $$DevicesTableTableManager($_db, $_db.devices).filter(
      (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_devicesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DeviceLogRecordsTable, List<DeviceLogRecord>>
  _deviceLogRecordsRefsTable(_$LocalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.deviceLogRecords,
        aliasName: 'users__user_id__device_log__user_id',
      );

  $$DeviceLogRecordsTableProcessedTableManager get deviceLogRecordsRefs {
    final manager =
        $$DeviceLogRecordsTableTableManager($_db, $_db.deviceLogRecords).filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _deviceLogRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MembershipsTable, List<Membership>>
  _membershipsRefsTable(_$LocalDatabase db) => MultiTypedResultKey.fromTable(
    db.memberships,
    aliasName: 'users__user_id__memberships__user_id',
  );

  $$MembershipsTableProcessedTableManager get membershipsRefs {
    final manager = $$MembershipsTableTableManager($_db, $_db.memberships)
        .filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(_membershipsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UsersTableFilterComposer
    extends Composer<_$LocalDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get activated => $composableBuilder(
    column: $table.activated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get directoryEntryCiphertext => $composableBuilder(
    column: $table.directoryEntryCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localState => $composableBuilder(
    column: $table.localState,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> profilesRefs(
    Expression<bool> Function($$ProfilesTableFilterComposer f) f,
  ) {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> devicesRefs(
    Expression<bool> Function($$DevicesTableFilterComposer f) f,
  ) {
    final $$DevicesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.devices,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DevicesTableFilterComposer(
            $db: $db,
            $table: $db.devices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> deviceLogRecordsRefs(
    Expression<bool> Function($$DeviceLogRecordsTableFilterComposer f) f,
  ) {
    final $$DeviceLogRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.deviceLogRecords,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DeviceLogRecordsTableFilterComposer(
            $db: $db,
            $table: $db.deviceLogRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> membershipsRefs(
    Expression<bool> Function($$MembershipsTableFilterComposer f) f,
  ) {
    final $$MembershipsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.memberships,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipsTableFilterComposer(
            $db: $db,
            $table: $db.memberships,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UsersTableOrderingComposer
    extends Composer<_$LocalDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get activated => $composableBuilder(
    column: $table.activated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get directoryEntryCiphertext => $composableBuilder(
    column: $table.directoryEntryCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localState => $composableBuilder(
    column: $table.localState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsersTableAnnotationComposer
    extends Composer<_$LocalDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<bool> get activated =>
      $composableBuilder(column: $table.activated, builder: (column) => column);

  GeneratedColumn<Uint8List> get directoryEntryCiphertext => $composableBuilder(
    column: $table.directoryEntryCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localState => $composableBuilder(
    column: $table.localState,
    builder: (column) => column,
  );

  Expression<T> profilesRefs<T extends Object>(
    Expression<T> Function($$ProfilesTableAnnotationComposer a) f,
  ) {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> devicesRefs<T extends Object>(
    Expression<T> Function($$DevicesTableAnnotationComposer a) f,
  ) {
    final $$DevicesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.devices,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DevicesTableAnnotationComposer(
            $db: $db,
            $table: $db.devices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> deviceLogRecordsRefs<T extends Object>(
    Expression<T> Function($$DeviceLogRecordsTableAnnotationComposer a) f,
  ) {
    final $$DeviceLogRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.deviceLogRecords,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DeviceLogRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.deviceLogRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> membershipsRefs<T extends Object>(
    Expression<T> Function($$MembershipsTableAnnotationComposer a) f,
  ) {
    final $$MembershipsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.memberships,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipsTableAnnotationComposer(
            $db: $db,
            $table: $db.memberships,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $UsersTable,
          User,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (User, $$UsersTableReferences),
          User,
          PrefetchHooks Function({
            bool profilesRefs,
            bool devicesRefs,
            bool deviceLogRecordsRefs,
            bool membershipsRefs,
          })
        > {
  $$UsersTableTableManager(_$LocalDatabase db, $UsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<bool> activated = const Value.absent(),
                Value<Uint8List> directoryEntryCiphertext =
                    const Value.absent(),
                Value<int> localState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion(
                userId: userId,
                activated: activated,
                directoryEntryCiphertext: directoryEntryCiphertext,
                localState: localState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required bool activated,
                required Uint8List directoryEntryCiphertext,
                required int localState,
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion.insert(
                userId: userId,
                activated: activated,
                directoryEntryCiphertext: directoryEntryCiphertext,
                localState: localState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$UsersTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                profilesRefs = false,
                devicesRefs = false,
                deviceLogRecordsRefs = false,
                membershipsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (profilesRefs) db.profiles,
                    if (devicesRefs) db.devices,
                    if (deviceLogRecordsRefs) db.deviceLogRecords,
                    if (membershipsRefs) db.memberships,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (profilesRefs)
                        await $_getPrefetchedData<User, $UsersTable, Profile>(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._profilesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(
                                db,
                                table,
                                p0,
                              ).profilesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (devicesRefs)
                        await $_getPrefetchedData<User, $UsersTable, Device>(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._devicesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(db, table, p0).devicesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (deviceLogRecordsRefs)
                        await $_getPrefetchedData<
                          User,
                          $UsersTable,
                          DeviceLogRecord
                        >(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._deviceLogRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(
                                db,
                                table,
                                p0,
                              ).deviceLogRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (membershipsRefs)
                        await $_getPrefetchedData<
                          User,
                          $UsersTable,
                          Membership
                        >(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._membershipsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(
                                db,
                                table,
                                p0,
                              ).membershipsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $UsersTable,
      User,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (User, $$UsersTableReferences),
      User,
      PrefetchHooks Function({
        bool profilesRefs,
        bool devicesRefs,
        bool deviceLogRecordsRefs,
        bool membershipsRefs,
      })
    >;
typedef $$ProfilesTableCreateCompanionBuilder =
    ProfilesCompanion Function({
      required String userId,
      required Uint8List profileCiphertext,
      required int version,
      required int verificationState,
      Value<int> rowid,
    });
typedef $$ProfilesTableUpdateCompanionBuilder =
    ProfilesCompanion Function({
      Value<String> userId,
      Value<Uint8List> profileCiphertext,
      Value<int> version,
      Value<int> verificationState,
      Value<int> rowid,
    });

final class $$ProfilesTableReferences
    extends BaseReferences<_$LocalDatabase, $ProfilesTable, Profile> {
  $$ProfilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UsersTable _userIdTable(_$LocalDatabase db) =>
      db.users.createAlias('profiles__user_id__users__user_id');

  $$UsersTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProfilesTableFilterComposer
    extends Composer<_$LocalDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<Uint8List> get profileCiphertext => $composableBuilder(
    column: $table.profileCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get verificationState => $composableBuilder(
    column: $table.verificationState,
    builder: (column) => ColumnFilters(column),
  );

  $$UsersTableFilterComposer get userId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$LocalDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<Uint8List> get profileCiphertext => $composableBuilder(
    column: $table.profileCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get verificationState => $composableBuilder(
    column: $table.verificationState,
    builder: (column) => ColumnOrderings(column),
  );

  $$UsersTableOrderingComposer get userId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<Uint8List> get profileCiphertext => $composableBuilder(
    column: $table.profileCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get verificationState => $composableBuilder(
    column: $table.verificationState,
    builder: (column) => column,
  );

  $$UsersTableAnnotationComposer get userId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfilesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $ProfilesTable,
          Profile,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (Profile, $$ProfilesTableReferences),
          Profile,
          PrefetchHooks Function({bool userId})
        > {
  $$ProfilesTableTableManager(_$LocalDatabase db, $ProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<Uint8List> profileCiphertext = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> verificationState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion(
                userId: userId,
                profileCiphertext: profileCiphertext,
                version: version,
                verificationState: verificationState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required Uint8List profileCiphertext,
                required int version,
                required int verificationState,
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion.insert(
                userId: userId,
                profileCiphertext: profileCiphertext,
                version: version,
                verificationState: verificationState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProfilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable: $$ProfilesTableReferences
                                    ._userIdTable(db),
                                referencedColumn: $$ProfilesTableReferences
                                    ._userIdTable(db)
                                    .userId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $ProfilesTable,
      Profile,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (Profile, $$ProfilesTableReferences),
      Profile,
      PrefetchHooks Function({bool userId})
    >;
typedef $$DevicesTableCreateCompanionBuilder =
    DevicesCompanion Function({
      required String deviceId,
      required String userId,
      required Uint8List publicBundle,
      Value<Uint8List?> etagCiphertext,
      Value<Uint8List?> labelCiphertext,
      required int revocationState,
      Value<int?> bundleVersion,
      Value<int> rowid,
    });
typedef $$DevicesTableUpdateCompanionBuilder =
    DevicesCompanion Function({
      Value<String> deviceId,
      Value<String> userId,
      Value<Uint8List> publicBundle,
      Value<Uint8List?> etagCiphertext,
      Value<Uint8List?> labelCiphertext,
      Value<int> revocationState,
      Value<int?> bundleVersion,
      Value<int> rowid,
    });

final class $$DevicesTableReferences
    extends BaseReferences<_$LocalDatabase, $DevicesTable, Device> {
  $$DevicesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UsersTable _userIdTable(_$LocalDatabase db) =>
      db.users.createAlias('devices__user_id__users__user_id');

  $$UsersTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DevicesTableFilterComposer
    extends Composer<_$LocalDatabase, $DevicesTable> {
  $$DevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get publicBundle => $composableBuilder(
    column: $table.publicBundle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get etagCiphertext => $composableBuilder(
    column: $table.etagCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get labelCiphertext => $composableBuilder(
    column: $table.labelCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revocationState => $composableBuilder(
    column: $table.revocationState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bundleVersion => $composableBuilder(
    column: $table.bundleVersion,
    builder: (column) => ColumnFilters(column),
  );

  $$UsersTableFilterComposer get userId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DevicesTableOrderingComposer
    extends Composer<_$LocalDatabase, $DevicesTable> {
  $$DevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get publicBundle => $composableBuilder(
    column: $table.publicBundle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get etagCiphertext => $composableBuilder(
    column: $table.etagCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get labelCiphertext => $composableBuilder(
    column: $table.labelCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revocationState => $composableBuilder(
    column: $table.revocationState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bundleVersion => $composableBuilder(
    column: $table.bundleVersion,
    builder: (column) => ColumnOrderings(column),
  );

  $$UsersTableOrderingComposer get userId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<Uint8List> get publicBundle => $composableBuilder(
    column: $table.publicBundle,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get etagCiphertext => $composableBuilder(
    column: $table.etagCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get labelCiphertext => $composableBuilder(
    column: $table.labelCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revocationState => $composableBuilder(
    column: $table.revocationState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bundleVersion => $composableBuilder(
    column: $table.bundleVersion,
    builder: (column) => column,
  );

  $$UsersTableAnnotationComposer get userId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DevicesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DevicesTable,
          Device,
          $$DevicesTableFilterComposer,
          $$DevicesTableOrderingComposer,
          $$DevicesTableAnnotationComposer,
          $$DevicesTableCreateCompanionBuilder,
          $$DevicesTableUpdateCompanionBuilder,
          (Device, $$DevicesTableReferences),
          Device,
          PrefetchHooks Function({bool userId})
        > {
  $$DevicesTableTableManager(_$LocalDatabase db, $DevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> deviceId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<Uint8List> publicBundle = const Value.absent(),
                Value<Uint8List?> etagCiphertext = const Value.absent(),
                Value<Uint8List?> labelCiphertext = const Value.absent(),
                Value<int> revocationState = const Value.absent(),
                Value<int?> bundleVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion(
                deviceId: deviceId,
                userId: userId,
                publicBundle: publicBundle,
                etagCiphertext: etagCiphertext,
                labelCiphertext: labelCiphertext,
                revocationState: revocationState,
                bundleVersion: bundleVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deviceId,
                required String userId,
                required Uint8List publicBundle,
                Value<Uint8List?> etagCiphertext = const Value.absent(),
                Value<Uint8List?> labelCiphertext = const Value.absent(),
                required int revocationState,
                Value<int?> bundleVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion.insert(
                deviceId: deviceId,
                userId: userId,
                publicBundle: publicBundle,
                etagCiphertext: etagCiphertext,
                labelCiphertext: labelCiphertext,
                revocationState: revocationState,
                bundleVersion: bundleVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DevicesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable: $$DevicesTableReferences
                                    ._userIdTable(db),
                                referencedColumn: $$DevicesTableReferences
                                    ._userIdTable(db)
                                    .userId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DevicesTable,
      Device,
      $$DevicesTableFilterComposer,
      $$DevicesTableOrderingComposer,
      $$DevicesTableAnnotationComposer,
      $$DevicesTableCreateCompanionBuilder,
      $$DevicesTableUpdateCompanionBuilder,
      (Device, $$DevicesTableReferences),
      Device,
      PrefetchHooks Function({bool userId})
    >;
typedef $$DeviceLogRecordsTableCreateCompanionBuilder =
    DeviceLogRecordsCompanion Function({
      required String userId,
      required int sequence,
      required Uint8List signedOpaqueRecord,
      required Uint8List recordHash,
      required int forkState,
      required int gossipState,
      Value<int> rowid,
    });
typedef $$DeviceLogRecordsTableUpdateCompanionBuilder =
    DeviceLogRecordsCompanion Function({
      Value<String> userId,
      Value<int> sequence,
      Value<Uint8List> signedOpaqueRecord,
      Value<Uint8List> recordHash,
      Value<int> forkState,
      Value<int> gossipState,
      Value<int> rowid,
    });

final class $$DeviceLogRecordsTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DeviceLogRecordsTable,
          DeviceLogRecord
        > {
  $$DeviceLogRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $UsersTable _userIdTable(_$LocalDatabase db) =>
      db.users.createAlias('device_log__user_id__users__user_id');

  $$UsersTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DeviceLogRecordsTableFilterComposer
    extends Composer<_$LocalDatabase, $DeviceLogRecordsTable> {
  $$DeviceLogRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get signedOpaqueRecord => $composableBuilder(
    column: $table.signedOpaqueRecord,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get recordHash => $composableBuilder(
    column: $table.recordHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get forkState => $composableBuilder(
    column: $table.forkState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get gossipState => $composableBuilder(
    column: $table.gossipState,
    builder: (column) => ColumnFilters(column),
  );

  $$UsersTableFilterComposer get userId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceLogRecordsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DeviceLogRecordsTable> {
  $$DeviceLogRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get signedOpaqueRecord => $composableBuilder(
    column: $table.signedOpaqueRecord,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get recordHash => $composableBuilder(
    column: $table.recordHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get forkState => $composableBuilder(
    column: $table.forkState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get gossipState => $composableBuilder(
    column: $table.gossipState,
    builder: (column) => ColumnOrderings(column),
  );

  $$UsersTableOrderingComposer get userId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceLogRecordsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DeviceLogRecordsTable> {
  $$DeviceLogRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<Uint8List> get signedOpaqueRecord => $composableBuilder(
    column: $table.signedOpaqueRecord,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get recordHash => $composableBuilder(
    column: $table.recordHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get forkState =>
      $composableBuilder(column: $table.forkState, builder: (column) => column);

  GeneratedColumn<int> get gossipState => $composableBuilder(
    column: $table.gossipState,
    builder: (column) => column,
  );

  $$UsersTableAnnotationComposer get userId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceLogRecordsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DeviceLogRecordsTable,
          DeviceLogRecord,
          $$DeviceLogRecordsTableFilterComposer,
          $$DeviceLogRecordsTableOrderingComposer,
          $$DeviceLogRecordsTableAnnotationComposer,
          $$DeviceLogRecordsTableCreateCompanionBuilder,
          $$DeviceLogRecordsTableUpdateCompanionBuilder,
          (DeviceLogRecord, $$DeviceLogRecordsTableReferences),
          DeviceLogRecord,
          PrefetchHooks Function({bool userId})
        > {
  $$DeviceLogRecordsTableTableManager(
    _$LocalDatabase db,
    $DeviceLogRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeviceLogRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeviceLogRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeviceLogRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<Uint8List> signedOpaqueRecord = const Value.absent(),
                Value<Uint8List> recordHash = const Value.absent(),
                Value<int> forkState = const Value.absent(),
                Value<int> gossipState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceLogRecordsCompanion(
                userId: userId,
                sequence: sequence,
                signedOpaqueRecord: signedOpaqueRecord,
                recordHash: recordHash,
                forkState: forkState,
                gossipState: gossipState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required int sequence,
                required Uint8List signedOpaqueRecord,
                required Uint8List recordHash,
                required int forkState,
                required int gossipState,
                Value<int> rowid = const Value.absent(),
              }) => DeviceLogRecordsCompanion.insert(
                userId: userId,
                sequence: sequence,
                signedOpaqueRecord: signedOpaqueRecord,
                recordHash: recordHash,
                forkState: forkState,
                gossipState: gossipState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DeviceLogRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable:
                                    $$DeviceLogRecordsTableReferences
                                        ._userIdTable(db),
                                referencedColumn:
                                    $$DeviceLogRecordsTableReferences
                                        ._userIdTable(db)
                                        .userId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DeviceLogRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DeviceLogRecordsTable,
      DeviceLogRecord,
      $$DeviceLogRecordsTableFilterComposer,
      $$DeviceLogRecordsTableOrderingComposer,
      $$DeviceLogRecordsTableAnnotationComposer,
      $$DeviceLogRecordsTableCreateCompanionBuilder,
      $$DeviceLogRecordsTableUpdateCompanionBuilder,
      (DeviceLogRecord, $$DeviceLogRecordsTableReferences),
      DeviceLogRecord,
      PrefetchHooks Function({bool userId})
    >;
typedef $$PairwiseSessionsTableCreateCompanionBuilder =
    PairwiseSessionsCompanion Function({
      required String localDeviceId,
      required String remoteDeviceId,
      required Uint8List opaqueCryptoStateHandle,
      required int stateVersion,
      Value<int> rowid,
    });
typedef $$PairwiseSessionsTableUpdateCompanionBuilder =
    PairwiseSessionsCompanion Function({
      Value<String> localDeviceId,
      Value<String> remoteDeviceId,
      Value<Uint8List> opaqueCryptoStateHandle,
      Value<int> stateVersion,
      Value<int> rowid,
    });

class $$PairwiseSessionsTableFilterComposer
    extends Composer<_$LocalDatabase, $PairwiseSessionsTable> {
  $$PairwiseSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localDeviceId => $composableBuilder(
    column: $table.localDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteDeviceId => $composableBuilder(
    column: $table.remoteDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get opaqueCryptoStateHandle => $composableBuilder(
    column: $table.opaqueCryptoStateHandle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stateVersion => $composableBuilder(
    column: $table.stateVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PairwiseSessionsTableOrderingComposer
    extends Composer<_$LocalDatabase, $PairwiseSessionsTable> {
  $$PairwiseSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localDeviceId => $composableBuilder(
    column: $table.localDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteDeviceId => $composableBuilder(
    column: $table.remoteDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get opaqueCryptoStateHandle => $composableBuilder(
    column: $table.opaqueCryptoStateHandle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stateVersion => $composableBuilder(
    column: $table.stateVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PairwiseSessionsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $PairwiseSessionsTable> {
  $$PairwiseSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localDeviceId => $composableBuilder(
    column: $table.localDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remoteDeviceId => $composableBuilder(
    column: $table.remoteDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get opaqueCryptoStateHandle => $composableBuilder(
    column: $table.opaqueCryptoStateHandle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stateVersion => $composableBuilder(
    column: $table.stateVersion,
    builder: (column) => column,
  );
}

class $$PairwiseSessionsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $PairwiseSessionsTable,
          PairwiseSession,
          $$PairwiseSessionsTableFilterComposer,
          $$PairwiseSessionsTableOrderingComposer,
          $$PairwiseSessionsTableAnnotationComposer,
          $$PairwiseSessionsTableCreateCompanionBuilder,
          $$PairwiseSessionsTableUpdateCompanionBuilder,
          (
            PairwiseSession,
            BaseReferences<
              _$LocalDatabase,
              $PairwiseSessionsTable,
              PairwiseSession
            >,
          ),
          PairwiseSession,
          PrefetchHooks Function()
        > {
  $$PairwiseSessionsTableTableManager(
    _$LocalDatabase db,
    $PairwiseSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PairwiseSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PairwiseSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PairwiseSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localDeviceId = const Value.absent(),
                Value<String> remoteDeviceId = const Value.absent(),
                Value<Uint8List> opaqueCryptoStateHandle = const Value.absent(),
                Value<int> stateVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PairwiseSessionsCompanion(
                localDeviceId: localDeviceId,
                remoteDeviceId: remoteDeviceId,
                opaqueCryptoStateHandle: opaqueCryptoStateHandle,
                stateVersion: stateVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localDeviceId,
                required String remoteDeviceId,
                required Uint8List opaqueCryptoStateHandle,
                required int stateVersion,
                Value<int> rowid = const Value.absent(),
              }) => PairwiseSessionsCompanion.insert(
                localDeviceId: localDeviceId,
                remoteDeviceId: remoteDeviceId,
                opaqueCryptoStateHandle: opaqueCryptoStateHandle,
                stateVersion: stateVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PairwiseSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $PairwiseSessionsTable,
      PairwiseSession,
      $$PairwiseSessionsTableFilterComposer,
      $$PairwiseSessionsTableOrderingComposer,
      $$PairwiseSessionsTableAnnotationComposer,
      $$PairwiseSessionsTableCreateCompanionBuilder,
      $$PairwiseSessionsTableUpdateCompanionBuilder,
      (
        PairwiseSession,
        BaseReferences<
          _$LocalDatabase,
          $PairwiseSessionsTable,
          PairwiseSession
        >,
      ),
      PairwiseSession,
      PrefetchHooks Function()
    >;
typedef $$PrekeysTableCreateCompanionBuilder =
    PrekeysCompanion Function({
      required int kind,
      required int keyId,
      required Uint8List privateStateHandle,
      required int uploadState,
      required int useState,
      Value<int> rowid,
    });
typedef $$PrekeysTableUpdateCompanionBuilder =
    PrekeysCompanion Function({
      Value<int> kind,
      Value<int> keyId,
      Value<Uint8List> privateStateHandle,
      Value<int> uploadState,
      Value<int> useState,
      Value<int> rowid,
    });

class $$PrekeysTableFilterComposer
    extends Composer<_$LocalDatabase, $PrekeysTable> {
  $$PrekeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get privateStateHandle => $composableBuilder(
    column: $table.privateStateHandle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get useState => $composableBuilder(
    column: $table.useState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PrekeysTableOrderingComposer
    extends Composer<_$LocalDatabase, $PrekeysTable> {
  $$PrekeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get privateStateHandle => $composableBuilder(
    column: $table.privateStateHandle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get useState => $composableBuilder(
    column: $table.useState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PrekeysTableAnnotationComposer
    extends Composer<_$LocalDatabase, $PrekeysTable> {
  $$PrekeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get keyId =>
      $composableBuilder(column: $table.keyId, builder: (column) => column);

  GeneratedColumn<Uint8List> get privateStateHandle => $composableBuilder(
    column: $table.privateStateHandle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get useState =>
      $composableBuilder(column: $table.useState, builder: (column) => column);
}

class $$PrekeysTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $PrekeysTable,
          Prekey,
          $$PrekeysTableFilterComposer,
          $$PrekeysTableOrderingComposer,
          $$PrekeysTableAnnotationComposer,
          $$PrekeysTableCreateCompanionBuilder,
          $$PrekeysTableUpdateCompanionBuilder,
          (Prekey, BaseReferences<_$LocalDatabase, $PrekeysTable, Prekey>),
          Prekey,
          PrefetchHooks Function()
        > {
  $$PrekeysTableTableManager(_$LocalDatabase db, $PrekeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PrekeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PrekeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PrekeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> kind = const Value.absent(),
                Value<int> keyId = const Value.absent(),
                Value<Uint8List> privateStateHandle = const Value.absent(),
                Value<int> uploadState = const Value.absent(),
                Value<int> useState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PrekeysCompanion(
                kind: kind,
                keyId: keyId,
                privateStateHandle: privateStateHandle,
                uploadState: uploadState,
                useState: useState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int kind,
                required int keyId,
                required Uint8List privateStateHandle,
                required int uploadState,
                required int useState,
                Value<int> rowid = const Value.absent(),
              }) => PrekeysCompanion.insert(
                kind: kind,
                keyId: keyId,
                privateStateHandle: privateStateHandle,
                uploadState: uploadState,
                useState: useState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PrekeysTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $PrekeysTable,
      Prekey,
      $$PrekeysTableFilterComposer,
      $$PrekeysTableOrderingComposer,
      $$PrekeysTableAnnotationComposer,
      $$PrekeysTableCreateCompanionBuilder,
      $$PrekeysTableUpdateCompanionBuilder,
      (Prekey, BaseReferences<_$LocalDatabase, $PrekeysTable, Prekey>),
      Prekey,
      PrefetchHooks Function()
    >;
typedef $$MlsGroupsTableCreateCompanionBuilder =
    MlsGroupsCompanion Function({
      required String groupId,
      required Uint8List opaqueCryptoStateHandle,
      required int acceptedEpoch,
      required int stateVersion,
      Value<int> queueGapRecoveryState,
      Value<int> rowid,
    });
typedef $$MlsGroupsTableUpdateCompanionBuilder =
    MlsGroupsCompanion Function({
      Value<String> groupId,
      Value<Uint8List> opaqueCryptoStateHandle,
      Value<int> acceptedEpoch,
      Value<int> stateVersion,
      Value<int> queueGapRecoveryState,
      Value<int> rowid,
    });

class $$MlsGroupsTableFilterComposer
    extends Composer<_$LocalDatabase, $MlsGroupsTable> {
  $$MlsGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get opaqueCryptoStateHandle => $composableBuilder(
    column: $table.opaqueCryptoStateHandle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acceptedEpoch => $composableBuilder(
    column: $table.acceptedEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stateVersion => $composableBuilder(
    column: $table.stateVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get queueGapRecoveryState => $composableBuilder(
    column: $table.queueGapRecoveryState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MlsGroupsTableOrderingComposer
    extends Composer<_$LocalDatabase, $MlsGroupsTable> {
  $$MlsGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get opaqueCryptoStateHandle => $composableBuilder(
    column: $table.opaqueCryptoStateHandle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acceptedEpoch => $composableBuilder(
    column: $table.acceptedEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stateVersion => $composableBuilder(
    column: $table.stateVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get queueGapRecoveryState => $composableBuilder(
    column: $table.queueGapRecoveryState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MlsGroupsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $MlsGroupsTable> {
  $$MlsGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<Uint8List> get opaqueCryptoStateHandle => $composableBuilder(
    column: $table.opaqueCryptoStateHandle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acceptedEpoch => $composableBuilder(
    column: $table.acceptedEpoch,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stateVersion => $composableBuilder(
    column: $table.stateVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get queueGapRecoveryState => $composableBuilder(
    column: $table.queueGapRecoveryState,
    builder: (column) => column,
  );
}

class $$MlsGroupsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $MlsGroupsTable,
          MlsGroup,
          $$MlsGroupsTableFilterComposer,
          $$MlsGroupsTableOrderingComposer,
          $$MlsGroupsTableAnnotationComposer,
          $$MlsGroupsTableCreateCompanionBuilder,
          $$MlsGroupsTableUpdateCompanionBuilder,
          (
            MlsGroup,
            BaseReferences<_$LocalDatabase, $MlsGroupsTable, MlsGroup>,
          ),
          MlsGroup,
          PrefetchHooks Function()
        > {
  $$MlsGroupsTableTableManager(_$LocalDatabase db, $MlsGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MlsGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MlsGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MlsGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<Uint8List> opaqueCryptoStateHandle = const Value.absent(),
                Value<int> acceptedEpoch = const Value.absent(),
                Value<int> stateVersion = const Value.absent(),
                Value<int> queueGapRecoveryState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MlsGroupsCompanion(
                groupId: groupId,
                opaqueCryptoStateHandle: opaqueCryptoStateHandle,
                acceptedEpoch: acceptedEpoch,
                stateVersion: stateVersion,
                queueGapRecoveryState: queueGapRecoveryState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required Uint8List opaqueCryptoStateHandle,
                required int acceptedEpoch,
                required int stateVersion,
                Value<int> queueGapRecoveryState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MlsGroupsCompanion.insert(
                groupId: groupId,
                opaqueCryptoStateHandle: opaqueCryptoStateHandle,
                acceptedEpoch: acceptedEpoch,
                stateVersion: stateVersion,
                queueGapRecoveryState: queueGapRecoveryState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MlsGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $MlsGroupsTable,
      MlsGroup,
      $$MlsGroupsTableFilterComposer,
      $$MlsGroupsTableOrderingComposer,
      $$MlsGroupsTableAnnotationComposer,
      $$MlsGroupsTableCreateCompanionBuilder,
      $$MlsGroupsTableUpdateCompanionBuilder,
      (MlsGroup, BaseReferences<_$LocalDatabase, $MlsGroupsTable, MlsGroup>),
      MlsGroup,
      PrefetchHooks Function()
    >;
typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      required String conversationId,
      required int kind,
      required Uint8List listProjectionCiphertext,
      required int sortKey,
      Value<bool> tombstoned,
      Value<int> rowid,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String> conversationId,
      Value<int> kind,
      Value<Uint8List> listProjectionCiphertext,
      Value<int> sortKey,
      Value<bool> tombstoned,
      Value<int> rowid,
    });

final class $$ConversationsTableReferences
    extends BaseReferences<_$LocalDatabase, $ConversationsTable, Conversation> {
  $$ConversationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$MembershipsTable, List<Membership>>
  _membershipsRefsTable(_$LocalDatabase db) => MultiTypedResultKey.fromTable(
    db.memberships,
    aliasName: 'conversations__conversation_id__memberships__conversation_id',
  );

  $$MembershipsTableProcessedTableManager get membershipsRefs {
    final manager = $$MembershipsTableTableManager($_db, $_db.memberships)
        .filter(
          (f) => f.conversationId.conversationId.sqlEquals(
            $_itemColumn<String>('conversation_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(_membershipsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: 'conversations__conversation_id__messages__conversation_id',
  );

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager($_db, $_db.messages).filter(
      (f) => f.conversationId.conversationId.sqlEquals(
        $_itemColumn<String>('conversation_id')!,
      ),
    );

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MessageEventsTable, List<MessageEvent>>
  _messageEventsRefsTable(_$LocalDatabase db) => MultiTypedResultKey.fromTable(
    db.messageEvents,
    aliasName:
        'conversations__conversation_id__message_events__conversation_id',
  );

  $$MessageEventsTableProcessedTableManager get messageEventsRefs {
    final manager = $$MessageEventsTableTableManager($_db, $_db.messageEvents)
        .filter(
          (f) => f.conversationId.conversationId.sqlEquals(
            $_itemColumn<String>('conversation_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(_messageEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ConversationsTableFilterComposer
    extends Composer<_$LocalDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get listProjectionCiphertext => $composableBuilder(
    column: $table.listProjectionCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tombstoned => $composableBuilder(
    column: $table.tombstoned,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> membershipsRefs(
    Expression<bool> Function($$MembershipsTableFilterComposer f) f,
  ) {
    final $$MembershipsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.memberships,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipsTableFilterComposer(
            $db: $db,
            $table: $db.memberships,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> messagesRefs(
    Expression<bool> Function($$MessagesTableFilterComposer f) f,
  ) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> messageEventsRefs(
    Expression<bool> Function($$MessageEventsTableFilterComposer f) f,
  ) {
    final $$MessageEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.messageEvents,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageEventsTableFilterComposer(
            $db: $db,
            $table: $db.messageEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$LocalDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get listProjectionCiphertext => $composableBuilder(
    column: $table.listProjectionCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tombstoned => $composableBuilder(
    column: $table.tombstoned,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<Uint8List> get listProjectionCiphertext => $composableBuilder(
    column: $table.listProjectionCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumn<bool> get tombstoned => $composableBuilder(
    column: $table.tombstoned,
    builder: (column) => column,
  );

  Expression<T> membershipsRefs<T extends Object>(
    Expression<T> Function($$MembershipsTableAnnotationComposer a) f,
  ) {
    final $$MembershipsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.memberships,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipsTableAnnotationComposer(
            $db: $db,
            $table: $db.memberships,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($$MessagesTableAnnotationComposer a) f,
  ) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> messageEventsRefs<T extends Object>(
    Expression<T> Function($$MessageEventsTableAnnotationComposer a) f,
  ) {
    final $$MessageEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.messageEvents,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.messageEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $ConversationsTable,
          Conversation,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (Conversation, $$ConversationsTableReferences),
          Conversation,
          PrefetchHooks Function({
            bool membershipsRefs,
            bool messagesRefs,
            bool messageEventsRefs,
          })
        > {
  $$ConversationsTableTableManager(
    _$LocalDatabase db,
    $ConversationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> conversationId = const Value.absent(),
                Value<int> kind = const Value.absent(),
                Value<Uint8List> listProjectionCiphertext =
                    const Value.absent(),
                Value<int> sortKey = const Value.absent(),
                Value<bool> tombstoned = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                conversationId: conversationId,
                kind: kind,
                listProjectionCiphertext: listProjectionCiphertext,
                sortKey: sortKey,
                tombstoned: tombstoned,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conversationId,
                required int kind,
                required Uint8List listProjectionCiphertext,
                required int sortKey,
                Value<bool> tombstoned = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                conversationId: conversationId,
                kind: kind,
                listProjectionCiphertext: listProjectionCiphertext,
                sortKey: sortKey,
                tombstoned: tombstoned,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ConversationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                membershipsRefs = false,
                messagesRefs = false,
                messageEventsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (membershipsRefs) db.memberships,
                    if (messagesRefs) db.messages,
                    if (messageEventsRefs) db.messageEvents,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (membershipsRefs)
                        await $_getPrefetchedData<
                          Conversation,
                          $ConversationsTable,
                          Membership
                        >(
                          currentTable: table,
                          referencedTable: $$ConversationsTableReferences
                              ._membershipsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConversationsTableReferences(
                                db,
                                table,
                                p0,
                              ).membershipsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.conversationId == item.conversationId,
                              ),
                          typedResults: items,
                        ),
                      if (messagesRefs)
                        await $_getPrefetchedData<
                          Conversation,
                          $ConversationsTable,
                          Message
                        >(
                          currentTable: table,
                          referencedTable: $$ConversationsTableReferences
                              ._messagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConversationsTableReferences(
                                db,
                                table,
                                p0,
                              ).messagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.conversationId == item.conversationId,
                              ),
                          typedResults: items,
                        ),
                      if (messageEventsRefs)
                        await $_getPrefetchedData<
                          Conversation,
                          $ConversationsTable,
                          MessageEvent
                        >(
                          currentTable: table,
                          referencedTable: $$ConversationsTableReferences
                              ._messageEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConversationsTableReferences(
                                db,
                                table,
                                p0,
                              ).messageEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.conversationId == item.conversationId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $ConversationsTable,
      Conversation,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (Conversation, $$ConversationsTableReferences),
      Conversation,
      PrefetchHooks Function({
        bool membershipsRefs,
        bool messagesRefs,
        bool messageEventsRefs,
      })
    >;
typedef $$MembershipsTableCreateCompanionBuilder =
    MembershipsCompanion Function({
      required String conversationId,
      required String userId,
      required Uint8List rolePolicyProjectionCiphertext,
      Value<int> rowid,
    });
typedef $$MembershipsTableUpdateCompanionBuilder =
    MembershipsCompanion Function({
      Value<String> conversationId,
      Value<String> userId,
      Value<Uint8List> rolePolicyProjectionCiphertext,
      Value<int> rowid,
    });

final class $$MembershipsTableReferences
    extends BaseReferences<_$LocalDatabase, $MembershipsTable, Membership> {
  $$MembershipsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ConversationsTable _conversationIdTable(_$LocalDatabase db) =>
      db.conversations.createAlias(
        'memberships__conversation_id__conversations__conversation_id',
      );

  $$ConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<String>('conversation_id')!;

    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.conversationId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $UsersTable _userIdTable(_$LocalDatabase db) =>
      db.users.createAlias('memberships__user_id__users__user_id');

  $$UsersTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MembershipsTableFilterComposer
    extends Composer<_$LocalDatabase, $MembershipsTable> {
  $$MembershipsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<Uint8List> get rolePolicyProjectionCiphertext =>
      $composableBuilder(
        column: $table.rolePolicyProjectionCiphertext,
        builder: (column) => ColumnFilters(column),
      );

  $$ConversationsTableFilterComposer get conversationId {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableFilterComposer get userId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MembershipsTableOrderingComposer
    extends Composer<_$LocalDatabase, $MembershipsTable> {
  $$MembershipsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<Uint8List> get rolePolicyProjectionCiphertext =>
      $composableBuilder(
        column: $table.rolePolicyProjectionCiphertext,
        builder: (column) => ColumnOrderings(column),
      );

  $$ConversationsTableOrderingComposer get conversationId {
    final $$ConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableOrderingComposer get userId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MembershipsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $MembershipsTable> {
  $$MembershipsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<Uint8List> get rolePolicyProjectionCiphertext =>
      $composableBuilder(
        column: $table.rolePolicyProjectionCiphertext,
        builder: (column) => column,
      );

  $$ConversationsTableAnnotationComposer get conversationId {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableAnnotationComposer get userId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MembershipsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $MembershipsTable,
          Membership,
          $$MembershipsTableFilterComposer,
          $$MembershipsTableOrderingComposer,
          $$MembershipsTableAnnotationComposer,
          $$MembershipsTableCreateCompanionBuilder,
          $$MembershipsTableUpdateCompanionBuilder,
          (Membership, $$MembershipsTableReferences),
          Membership,
          PrefetchHooks Function({bool conversationId, bool userId})
        > {
  $$MembershipsTableTableManager(_$LocalDatabase db, $MembershipsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembershipsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembershipsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembershipsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> conversationId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<Uint8List> rolePolicyProjectionCiphertext =
                    const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MembershipsCompanion(
                conversationId: conversationId,
                userId: userId,
                rolePolicyProjectionCiphertext: rolePolicyProjectionCiphertext,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conversationId,
                required String userId,
                required Uint8List rolePolicyProjectionCiphertext,
                Value<int> rowid = const Value.absent(),
              }) => MembershipsCompanion.insert(
                conversationId: conversationId,
                userId: userId,
                rolePolicyProjectionCiphertext: rolePolicyProjectionCiphertext,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MembershipsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conversationId = false, userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conversationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.conversationId,
                                referencedTable: $$MembershipsTableReferences
                                    ._conversationIdTable(db),
                                referencedColumn: $$MembershipsTableReferences
                                    ._conversationIdTable(db)
                                    .conversationId,
                              )
                              as T;
                    }
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable: $$MembershipsTableReferences
                                    ._userIdTable(db),
                                referencedColumn: $$MembershipsTableReferences
                                    ._userIdTable(db)
                                    .userId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MembershipsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $MembershipsTable,
      Membership,
      $$MembershipsTableFilterComposer,
      $$MembershipsTableOrderingComposer,
      $$MembershipsTableAnnotationComposer,
      $$MembershipsTableCreateCompanionBuilder,
      $$MembershipsTableUpdateCompanionBuilder,
      (Membership, $$MembershipsTableReferences),
      Membership,
      PrefetchHooks Function({bool conversationId, bool userId})
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      required String messageId,
      required String conversationId,
      required String currentEventId,
      required Uint8List projectionCiphertext,
      required int status,
      required int revision,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<String> messageId,
      Value<String> conversationId,
      Value<String> currentEventId,
      Value<Uint8List> projectionCiphertext,
      Value<int> status,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$MessagesTableReferences
    extends BaseReferences<_$LocalDatabase, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ConversationsTable _conversationIdTable(_$LocalDatabase db) => db
      .conversations
      .createAlias('messages__conversation_id__conversations__conversation_id');

  $$ConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<String>('conversation_id')!;

    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.conversationId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$AttachmentsTable, List<Attachment>>
  _attachmentsRefsTable(_$LocalDatabase db) => MultiTypedResultKey.fromTable(
    db.attachments,
    aliasName: 'messages__message_id__attachments__message_id',
  );

  $$AttachmentsTableProcessedTableManager get attachmentsRefs {
    final manager = $$AttachmentsTableTableManager($_db, $_db.attachments)
        .filter(
          (f) => f.messageId.messageId.sqlEquals(
            $_itemColumn<String>('message_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(_attachmentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReceiptsTable, List<Receipt>> _receiptsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.receipts,
    aliasName: 'messages__message_id__receipts__message_id',
  );

  $$ReceiptsTableProcessedTableManager get receiptsRefs {
    final manager = $$ReceiptsTableTableManager($_db, $_db.receipts).filter(
      (f) =>
          f.messageId.messageId.sqlEquals($_itemColumn<String>('message_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_receiptsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$LocalDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentEventId => $composableBuilder(
    column: $table.currentEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get projectionCiphertext => $composableBuilder(
    column: $table.projectionCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ConversationsTableFilterComposer get conversationId {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> attachmentsRefs(
    Expression<bool> Function($$AttachmentsTableFilterComposer f) f,
  ) {
    final $$AttachmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.attachments,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachmentsTableFilterComposer(
            $db: $db,
            $table: $db.attachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> receiptsRefs(
    Expression<bool> Function($$ReceiptsTableFilterComposer f) f,
  ) {
    final $$ReceiptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.receipts,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReceiptsTableFilterComposer(
            $db: $db,
            $table: $db.receipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$LocalDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentEventId => $composableBuilder(
    column: $table.currentEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get projectionCiphertext => $composableBuilder(
    column: $table.projectionCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConversationsTableOrderingComposer get conversationId {
    final $$ConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get currentEventId => $composableBuilder(
    column: $table.currentEventId,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get projectionCiphertext => $composableBuilder(
    column: $table.projectionCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ConversationsTableAnnotationComposer get conversationId {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> attachmentsRefs<T extends Object>(
    Expression<T> Function($$AttachmentsTableAnnotationComposer a) f,
  ) {
    final $$AttachmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.attachments,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.attachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> receiptsRefs<T extends Object>(
    Expression<T> Function($$ReceiptsTableAnnotationComposer a) f,
  ) {
    final $$ReceiptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.receipts,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReceiptsTableAnnotationComposer(
            $db: $db,
            $table: $db.receipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, $$MessagesTableReferences),
          Message,
          PrefetchHooks Function({
            bool conversationId,
            bool attachmentsRefs,
            bool receiptsRefs,
          })
        > {
  $$MessagesTableTableManager(_$LocalDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> messageId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> currentEventId = const Value.absent(),
                Value<Uint8List> projectionCiphertext = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                messageId: messageId,
                conversationId: conversationId,
                currentEventId: currentEventId,
                projectionCiphertext: projectionCiphertext,
                status: status,
                revision: revision,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String messageId,
                required String conversationId,
                required String currentEventId,
                required Uint8List projectionCiphertext,
                required int status,
                required int revision,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                messageId: messageId,
                conversationId: conversationId,
                currentEventId: currentEventId,
                projectionCiphertext: projectionCiphertext,
                status: status,
                revision: revision,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                conversationId = false,
                attachmentsRefs = false,
                receiptsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (attachmentsRefs) db.attachments,
                    if (receiptsRefs) db.receipts,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (conversationId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.conversationId,
                                    referencedTable: $$MessagesTableReferences
                                        ._conversationIdTable(db),
                                    referencedColumn: $$MessagesTableReferences
                                        ._conversationIdTable(db)
                                        .conversationId,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (attachmentsRefs)
                        await $_getPrefetchedData<
                          Message,
                          $MessagesTable,
                          Attachment
                        >(
                          currentTable: table,
                          referencedTable: $$MessagesTableReferences
                              ._attachmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MessagesTableReferences(
                                db,
                                table,
                                p0,
                              ).attachmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.messageId == item.messageId,
                              ),
                          typedResults: items,
                        ),
                      if (receiptsRefs)
                        await $_getPrefetchedData<
                          Message,
                          $MessagesTable,
                          Receipt
                        >(
                          currentTable: table,
                          referencedTable: $$MessagesTableReferences
                              ._receiptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MessagesTableReferences(
                                db,
                                table,
                                p0,
                              ).receiptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.messageId == item.messageId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, $$MessagesTableReferences),
      Message,
      PrefetchHooks Function({
        bool conversationId,
        bool attachmentsRefs,
        bool receiptsRefs,
      })
    >;
typedef $$MessageEventsTableCreateCompanionBuilder =
    MessageEventsCompanion Function({
      required String eventId,
      required String messageId,
      required String conversationId,
      required int eventKind,
      required Uint8List authenticatedCiphertext,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$MessageEventsTableUpdateCompanionBuilder =
    MessageEventsCompanion Function({
      Value<String> eventId,
      Value<String> messageId,
      Value<String> conversationId,
      Value<int> eventKind,
      Value<Uint8List> authenticatedCiphertext,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$MessageEventsTableReferences
    extends BaseReferences<_$LocalDatabase, $MessageEventsTable, MessageEvent> {
  $$MessageEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ConversationsTable _conversationIdTable(_$LocalDatabase db) =>
      db.conversations.createAlias(
        'message_events__conversation_id__conversations__conversation_id',
      );

  $$ConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<String>('conversation_id')!;

    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.conversationId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessageEventsTableFilterComposer
    extends Composer<_$LocalDatabase, $MessageEventsTable> {
  $$MessageEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get eventKind => $composableBuilder(
    column: $table.eventKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get authenticatedCiphertext => $composableBuilder(
    column: $table.authenticatedCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ConversationsTableFilterComposer get conversationId {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageEventsTableOrderingComposer
    extends Composer<_$LocalDatabase, $MessageEventsTable> {
  $$MessageEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get eventKind => $composableBuilder(
    column: $table.eventKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get authenticatedCiphertext => $composableBuilder(
    column: $table.authenticatedCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConversationsTableOrderingComposer get conversationId {
    final $$ConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageEventsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $MessageEventsTable> {
  $$MessageEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<int> get eventKind =>
      $composableBuilder(column: $table.eventKind, builder: (column) => column);

  GeneratedColumn<Uint8List> get authenticatedCiphertext => $composableBuilder(
    column: $table.authenticatedCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ConversationsTableAnnotationComposer get conversationId {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageEventsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $MessageEventsTable,
          MessageEvent,
          $$MessageEventsTableFilterComposer,
          $$MessageEventsTableOrderingComposer,
          $$MessageEventsTableAnnotationComposer,
          $$MessageEventsTableCreateCompanionBuilder,
          $$MessageEventsTableUpdateCompanionBuilder,
          (MessageEvent, $$MessageEventsTableReferences),
          MessageEvent,
          PrefetchHooks Function({bool conversationId})
        > {
  $$MessageEventsTableTableManager(
    _$LocalDatabase db,
    $MessageEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<int> eventKind = const Value.absent(),
                Value<Uint8List> authenticatedCiphertext = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageEventsCompanion(
                eventId: eventId,
                messageId: messageId,
                conversationId: conversationId,
                eventKind: eventKind,
                authenticatedCiphertext: authenticatedCiphertext,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required String messageId,
                required String conversationId,
                required int eventKind,
                required Uint8List authenticatedCiphertext,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => MessageEventsCompanion.insert(
                eventId: eventId,
                messageId: messageId,
                conversationId: conversationId,
                eventKind: eventKind,
                authenticatedCiphertext: authenticatedCiphertext,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessageEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conversationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conversationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.conversationId,
                                referencedTable: $$MessageEventsTableReferences
                                    ._conversationIdTable(db),
                                referencedColumn: $$MessageEventsTableReferences
                                    ._conversationIdTable(db)
                                    .conversationId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessageEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $MessageEventsTable,
      MessageEvent,
      $$MessageEventsTableFilterComposer,
      $$MessageEventsTableOrderingComposer,
      $$MessageEventsTableAnnotationComposer,
      $$MessageEventsTableCreateCompanionBuilder,
      $$MessageEventsTableUpdateCompanionBuilder,
      (MessageEvent, $$MessageEventsTableReferences),
      MessageEvent,
      PrefetchHooks Function({bool conversationId})
    >;
typedef $$AttachmentsTableCreateCompanionBuilder =
    AttachmentsCompanion Function({
      required String attachmentId,
      required String messageId,
      required Uint8List encryptedDescriptor,
      required int transferState,
      Value<Uint8List?> boundedCacheHandleCiphertext,
      Value<DateTime?> cacheExpiresAt,
      Value<int> rowid,
    });
typedef $$AttachmentsTableUpdateCompanionBuilder =
    AttachmentsCompanion Function({
      Value<String> attachmentId,
      Value<String> messageId,
      Value<Uint8List> encryptedDescriptor,
      Value<int> transferState,
      Value<Uint8List?> boundedCacheHandleCiphertext,
      Value<DateTime?> cacheExpiresAt,
      Value<int> rowid,
    });

final class $$AttachmentsTableReferences
    extends BaseReferences<_$LocalDatabase, $AttachmentsTable, Attachment> {
  $$AttachmentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MessagesTable _messageIdTable(_$LocalDatabase db) =>
      db.messages.createAlias('attachments__message_id__messages__message_id');

  $$MessagesTableProcessedTableManager get messageId {
    final $_column = $_itemColumn<String>('message_id')!;

    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.messageId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AttachmentsTableFilterComposer
    extends Composer<_$LocalDatabase, $AttachmentsTable> {
  $$AttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get attachmentId => $composableBuilder(
    column: $table.attachmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get encryptedDescriptor => $composableBuilder(
    column: $table.encryptedDescriptor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transferState => $composableBuilder(
    column: $table.transferState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get boundedCacheHandleCiphertext =>
      $composableBuilder(
        column: $table.boundedCacheHandleCiphertext,
        builder: (column) => ColumnFilters(column),
      );

  ColumnFilters<DateTime> get cacheExpiresAt => $composableBuilder(
    column: $table.cacheExpiresAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MessagesTableFilterComposer get messageId {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AttachmentsTableOrderingComposer
    extends Composer<_$LocalDatabase, $AttachmentsTable> {
  $$AttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get attachmentId => $composableBuilder(
    column: $table.attachmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get encryptedDescriptor => $composableBuilder(
    column: $table.encryptedDescriptor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transferState => $composableBuilder(
    column: $table.transferState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get boundedCacheHandleCiphertext =>
      $composableBuilder(
        column: $table.boundedCacheHandleCiphertext,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<DateTime> get cacheExpiresAt => $composableBuilder(
    column: $table.cacheExpiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MessagesTableOrderingComposer get messageId {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableOrderingComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AttachmentsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $AttachmentsTable> {
  $$AttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get attachmentId => $composableBuilder(
    column: $table.attachmentId,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get encryptedDescriptor => $composableBuilder(
    column: $table.encryptedDescriptor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get transferState => $composableBuilder(
    column: $table.transferState,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get boundedCacheHandleCiphertext =>
      $composableBuilder(
        column: $table.boundedCacheHandleCiphertext,
        builder: (column) => column,
      );

  GeneratedColumn<DateTime> get cacheExpiresAt => $composableBuilder(
    column: $table.cacheExpiresAt,
    builder: (column) => column,
  );

  $$MessagesTableAnnotationComposer get messageId {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AttachmentsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $AttachmentsTable,
          Attachment,
          $$AttachmentsTableFilterComposer,
          $$AttachmentsTableOrderingComposer,
          $$AttachmentsTableAnnotationComposer,
          $$AttachmentsTableCreateCompanionBuilder,
          $$AttachmentsTableUpdateCompanionBuilder,
          (Attachment, $$AttachmentsTableReferences),
          Attachment,
          PrefetchHooks Function({bool messageId})
        > {
  $$AttachmentsTableTableManager(_$LocalDatabase db, $AttachmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> attachmentId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<Uint8List> encryptedDescriptor = const Value.absent(),
                Value<int> transferState = const Value.absent(),
                Value<Uint8List?> boundedCacheHandleCiphertext =
                    const Value.absent(),
                Value<DateTime?> cacheExpiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion(
                attachmentId: attachmentId,
                messageId: messageId,
                encryptedDescriptor: encryptedDescriptor,
                transferState: transferState,
                boundedCacheHandleCiphertext: boundedCacheHandleCiphertext,
                cacheExpiresAt: cacheExpiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String attachmentId,
                required String messageId,
                required Uint8List encryptedDescriptor,
                required int transferState,
                Value<Uint8List?> boundedCacheHandleCiphertext =
                    const Value.absent(),
                Value<DateTime?> cacheExpiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion.insert(
                attachmentId: attachmentId,
                messageId: messageId,
                encryptedDescriptor: encryptedDescriptor,
                transferState: transferState,
                boundedCacheHandleCiphertext: boundedCacheHandleCiphertext,
                cacheExpiresAt: cacheExpiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AttachmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (messageId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.messageId,
                                referencedTable: $$AttachmentsTableReferences
                                    ._messageIdTable(db),
                                referencedColumn: $$AttachmentsTableReferences
                                    ._messageIdTable(db)
                                    .messageId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $AttachmentsTable,
      Attachment,
      $$AttachmentsTableFilterComposer,
      $$AttachmentsTableOrderingComposer,
      $$AttachmentsTableAnnotationComposer,
      $$AttachmentsTableCreateCompanionBuilder,
      $$AttachmentsTableUpdateCompanionBuilder,
      (Attachment, $$AttachmentsTableReferences),
      Attachment,
      PrefetchHooks Function({bool messageId})
    >;
typedef $$InboxEnvelopesTableCreateCompanionBuilder =
    InboxEnvelopesCompanion Function({
      required String envelopeId,
      required int sequence,
      required Uint8List envelopeCiphertext,
      required int processingState,
      Value<bool> readyToAcknowledge,
      Value<String?> opaqueEventId,
      Value<int?> dependencyClass,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<int> rowid,
    });
typedef $$InboxEnvelopesTableUpdateCompanionBuilder =
    InboxEnvelopesCompanion Function({
      Value<String> envelopeId,
      Value<int> sequence,
      Value<Uint8List> envelopeCiphertext,
      Value<int> processingState,
      Value<bool> readyToAcknowledge,
      Value<String?> opaqueEventId,
      Value<int?> dependencyClass,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<int> rowid,
    });

class $$InboxEnvelopesTableFilterComposer
    extends Composer<_$LocalDatabase, $InboxEnvelopesTable> {
  $$InboxEnvelopesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get envelopeCiphertext => $composableBuilder(
    column: $table.envelopeCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get processingState => $composableBuilder(
    column: $table.processingState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get readyToAcknowledge => $composableBuilder(
    column: $table.readyToAcknowledge,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get opaqueEventId => $composableBuilder(
    column: $table.opaqueEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dependencyClass => $composableBuilder(
    column: $table.dependencyClass,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InboxEnvelopesTableOrderingComposer
    extends Composer<_$LocalDatabase, $InboxEnvelopesTable> {
  $$InboxEnvelopesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get envelopeCiphertext => $composableBuilder(
    column: $table.envelopeCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get processingState => $composableBuilder(
    column: $table.processingState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get readyToAcknowledge => $composableBuilder(
    column: $table.readyToAcknowledge,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get opaqueEventId => $composableBuilder(
    column: $table.opaqueEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dependencyClass => $composableBuilder(
    column: $table.dependencyClass,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InboxEnvelopesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $InboxEnvelopesTable> {
  $$InboxEnvelopesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<Uint8List> get envelopeCiphertext => $composableBuilder(
    column: $table.envelopeCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get processingState => $composableBuilder(
    column: $table.processingState,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get readyToAcknowledge => $composableBuilder(
    column: $table.readyToAcknowledge,
    builder: (column) => column,
  );

  GeneratedColumn<String> get opaqueEventId => $composableBuilder(
    column: $table.opaqueEventId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dependencyClass => $composableBuilder(
    column: $table.dependencyClass,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );
}

class $$InboxEnvelopesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $InboxEnvelopesTable,
          InboxEnvelope,
          $$InboxEnvelopesTableFilterComposer,
          $$InboxEnvelopesTableOrderingComposer,
          $$InboxEnvelopesTableAnnotationComposer,
          $$InboxEnvelopesTableCreateCompanionBuilder,
          $$InboxEnvelopesTableUpdateCompanionBuilder,
          (
            InboxEnvelope,
            BaseReferences<
              _$LocalDatabase,
              $InboxEnvelopesTable,
              InboxEnvelope
            >,
          ),
          InboxEnvelope,
          PrefetchHooks Function()
        > {
  $$InboxEnvelopesTableTableManager(
    _$LocalDatabase db,
    $InboxEnvelopesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InboxEnvelopesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InboxEnvelopesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InboxEnvelopesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> envelopeId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<Uint8List> envelopeCiphertext = const Value.absent(),
                Value<int> processingState = const Value.absent(),
                Value<bool> readyToAcknowledge = const Value.absent(),
                Value<String?> opaqueEventId = const Value.absent(),
                Value<int?> dependencyClass = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InboxEnvelopesCompanion(
                envelopeId: envelopeId,
                sequence: sequence,
                envelopeCiphertext: envelopeCiphertext,
                processingState: processingState,
                readyToAcknowledge: readyToAcknowledge,
                opaqueEventId: opaqueEventId,
                dependencyClass: dependencyClass,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String envelopeId,
                required int sequence,
                required Uint8List envelopeCiphertext,
                required int processingState,
                Value<bool> readyToAcknowledge = const Value.absent(),
                Value<String?> opaqueEventId = const Value.absent(),
                Value<int?> dependencyClass = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InboxEnvelopesCompanion.insert(
                envelopeId: envelopeId,
                sequence: sequence,
                envelopeCiphertext: envelopeCiphertext,
                processingState: processingState,
                readyToAcknowledge: readyToAcknowledge,
                opaqueEventId: opaqueEventId,
                dependencyClass: dependencyClass,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InboxEnvelopesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $InboxEnvelopesTable,
      InboxEnvelope,
      $$InboxEnvelopesTableFilterComposer,
      $$InboxEnvelopesTableOrderingComposer,
      $$InboxEnvelopesTableAnnotationComposer,
      $$InboxEnvelopesTableCreateCompanionBuilder,
      $$InboxEnvelopesTableUpdateCompanionBuilder,
      (
        InboxEnvelope,
        BaseReferences<_$LocalDatabase, $InboxEnvelopesTable, InboxEnvelope>,
      ),
      InboxEnvelope,
      PrefetchHooks Function()
    >;
typedef $$OutboxOperationsTableCreateCompanionBuilder =
    OutboxOperationsCompanion Function({
      required String operationId,
      required String eventId,
      required String recipientDeviceId,
      Value<String> recipientUserId,
      required int batchIndex,
      required Uint8List exactRecipientCiphertext,
      required int attemptState,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<DateTime?> lastAttemptAt,
      Value<DateTime?> terminalAt,
      Value<int> rowid,
    });
typedef $$OutboxOperationsTableUpdateCompanionBuilder =
    OutboxOperationsCompanion Function({
      Value<String> operationId,
      Value<String> eventId,
      Value<String> recipientDeviceId,
      Value<String> recipientUserId,
      Value<int> batchIndex,
      Value<Uint8List> exactRecipientCiphertext,
      Value<int> attemptState,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<DateTime?> lastAttemptAt,
      Value<DateTime?> terminalAt,
      Value<int> rowid,
    });

class $$OutboxOperationsTableFilterComposer
    extends Composer<_$LocalDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipientDeviceId => $composableBuilder(
    column: $table.recipientDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipientUserId => $composableBuilder(
    column: $table.recipientUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get batchIndex => $composableBuilder(
    column: $table.batchIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get exactRecipientCiphertext => $composableBuilder(
    column: $table.exactRecipientCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptState => $composableBuilder(
    column: $table.attemptState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get terminalAt => $composableBuilder(
    column: $table.terminalAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxOperationsTableOrderingComposer
    extends Composer<_$LocalDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipientDeviceId => $composableBuilder(
    column: $table.recipientDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipientUserId => $composableBuilder(
    column: $table.recipientUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get batchIndex => $composableBuilder(
    column: $table.batchIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get exactRecipientCiphertext => $composableBuilder(
    column: $table.exactRecipientCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptState => $composableBuilder(
    column: $table.attemptState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get terminalAt => $composableBuilder(
    column: $table.terminalAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxOperationsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get recipientDeviceId => $composableBuilder(
    column: $table.recipientDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recipientUserId => $composableBuilder(
    column: $table.recipientUserId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get batchIndex => $composableBuilder(
    column: $table.batchIndex,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get exactRecipientCiphertext => $composableBuilder(
    column: $table.exactRecipientCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptState => $composableBuilder(
    column: $table.attemptState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get terminalAt => $composableBuilder(
    column: $table.terminalAt,
    builder: (column) => column,
  );
}

class $$OutboxOperationsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $OutboxOperationsTable,
          OutboxOperation,
          $$OutboxOperationsTableFilterComposer,
          $$OutboxOperationsTableOrderingComposer,
          $$OutboxOperationsTableAnnotationComposer,
          $$OutboxOperationsTableCreateCompanionBuilder,
          $$OutboxOperationsTableUpdateCompanionBuilder,
          (
            OutboxOperation,
            BaseReferences<
              _$LocalDatabase,
              $OutboxOperationsTable,
              OutboxOperation
            >,
          ),
          OutboxOperation,
          PrefetchHooks Function()
        > {
  $$OutboxOperationsTableTableManager(
    _$LocalDatabase db,
    $OutboxOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> recipientDeviceId = const Value.absent(),
                Value<String> recipientUserId = const Value.absent(),
                Value<int> batchIndex = const Value.absent(),
                Value<Uint8List> exactRecipientCiphertext =
                    const Value.absent(),
                Value<int> attemptState = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<DateTime?> terminalAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxOperationsCompanion(
                operationId: operationId,
                eventId: eventId,
                recipientDeviceId: recipientDeviceId,
                recipientUserId: recipientUserId,
                batchIndex: batchIndex,
                exactRecipientCiphertext: exactRecipientCiphertext,
                attemptState: attemptState,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastAttemptAt: lastAttemptAt,
                terminalAt: terminalAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String eventId,
                required String recipientDeviceId,
                Value<String> recipientUserId = const Value.absent(),
                required int batchIndex,
                required Uint8List exactRecipientCiphertext,
                required int attemptState,
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<DateTime?> terminalAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxOperationsCompanion.insert(
                operationId: operationId,
                eventId: eventId,
                recipientDeviceId: recipientDeviceId,
                recipientUserId: recipientUserId,
                batchIndex: batchIndex,
                exactRecipientCiphertext: exactRecipientCiphertext,
                attemptState: attemptState,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastAttemptAt: lastAttemptAt,
                terminalAt: terminalAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $OutboxOperationsTable,
      OutboxOperation,
      $$OutboxOperationsTableFilterComposer,
      $$OutboxOperationsTableOrderingComposer,
      $$OutboxOperationsTableAnnotationComposer,
      $$OutboxOperationsTableCreateCompanionBuilder,
      $$OutboxOperationsTableUpdateCompanionBuilder,
      (
        OutboxOperation,
        BaseReferences<
          _$LocalDatabase,
          $OutboxOperationsTable,
          OutboxOperation
        >,
      ),
      OutboxOperation,
      PrefetchHooks Function()
    >;
typedef $$InboxEventDeduplicationsTableCreateCompanionBuilder =
    InboxEventDeduplicationsCompanion Function({
      required String opaqueEventId,
      required String firstEnvelopeId,
      required int dependencyClass,
      Value<DateTime> committedAt,
      Value<int> rowid,
    });
typedef $$InboxEventDeduplicationsTableUpdateCompanionBuilder =
    InboxEventDeduplicationsCompanion Function({
      Value<String> opaqueEventId,
      Value<String> firstEnvelopeId,
      Value<int> dependencyClass,
      Value<DateTime> committedAt,
      Value<int> rowid,
    });

class $$InboxEventDeduplicationsTableFilterComposer
    extends Composer<_$LocalDatabase, $InboxEventDeduplicationsTable> {
  $$InboxEventDeduplicationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get opaqueEventId => $composableBuilder(
    column: $table.opaqueEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstEnvelopeId => $composableBuilder(
    column: $table.firstEnvelopeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dependencyClass => $composableBuilder(
    column: $table.dependencyClass,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get committedAt => $composableBuilder(
    column: $table.committedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InboxEventDeduplicationsTableOrderingComposer
    extends Composer<_$LocalDatabase, $InboxEventDeduplicationsTable> {
  $$InboxEventDeduplicationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get opaqueEventId => $composableBuilder(
    column: $table.opaqueEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstEnvelopeId => $composableBuilder(
    column: $table.firstEnvelopeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dependencyClass => $composableBuilder(
    column: $table.dependencyClass,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get committedAt => $composableBuilder(
    column: $table.committedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InboxEventDeduplicationsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $InboxEventDeduplicationsTable> {
  $$InboxEventDeduplicationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get opaqueEventId => $composableBuilder(
    column: $table.opaqueEventId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstEnvelopeId => $composableBuilder(
    column: $table.firstEnvelopeId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dependencyClass => $composableBuilder(
    column: $table.dependencyClass,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get committedAt => $composableBuilder(
    column: $table.committedAt,
    builder: (column) => column,
  );
}

class $$InboxEventDeduplicationsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $InboxEventDeduplicationsTable,
          InboxEventDeduplication,
          $$InboxEventDeduplicationsTableFilterComposer,
          $$InboxEventDeduplicationsTableOrderingComposer,
          $$InboxEventDeduplicationsTableAnnotationComposer,
          $$InboxEventDeduplicationsTableCreateCompanionBuilder,
          $$InboxEventDeduplicationsTableUpdateCompanionBuilder,
          (
            InboxEventDeduplication,
            BaseReferences<
              _$LocalDatabase,
              $InboxEventDeduplicationsTable,
              InboxEventDeduplication
            >,
          ),
          InboxEventDeduplication,
          PrefetchHooks Function()
        > {
  $$InboxEventDeduplicationsTableTableManager(
    _$LocalDatabase db,
    $InboxEventDeduplicationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InboxEventDeduplicationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$InboxEventDeduplicationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$InboxEventDeduplicationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> opaqueEventId = const Value.absent(),
                Value<String> firstEnvelopeId = const Value.absent(),
                Value<int> dependencyClass = const Value.absent(),
                Value<DateTime> committedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InboxEventDeduplicationsCompanion(
                opaqueEventId: opaqueEventId,
                firstEnvelopeId: firstEnvelopeId,
                dependencyClass: dependencyClass,
                committedAt: committedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String opaqueEventId,
                required String firstEnvelopeId,
                required int dependencyClass,
                Value<DateTime> committedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InboxEventDeduplicationsCompanion.insert(
                opaqueEventId: opaqueEventId,
                firstEnvelopeId: firstEnvelopeId,
                dependencyClass: dependencyClass,
                committedAt: committedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InboxEventDeduplicationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $InboxEventDeduplicationsTable,
      InboxEventDeduplication,
      $$InboxEventDeduplicationsTableFilterComposer,
      $$InboxEventDeduplicationsTableOrderingComposer,
      $$InboxEventDeduplicationsTableAnnotationComposer,
      $$InboxEventDeduplicationsTableCreateCompanionBuilder,
      $$InboxEventDeduplicationsTableUpdateCompanionBuilder,
      (
        InboxEventDeduplication,
        BaseReferences<
          _$LocalDatabase,
          $InboxEventDeduplicationsTable,
          InboxEventDeduplication
        >,
      ),
      InboxEventDeduplication,
      PrefetchHooks Function()
    >;
typedef $$StaleDeviceRefreshRequestsTableCreateCompanionBuilder =
    StaleDeviceRefreshRequestsCompanion Function({
      required String userId,
      required String staleDeviceId,
      Value<int> state,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<int> rowid,
    });
typedef $$StaleDeviceRefreshRequestsTableUpdateCompanionBuilder =
    StaleDeviceRefreshRequestsCompanion Function({
      Value<String> userId,
      Value<String> staleDeviceId,
      Value<int> state,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<int> rowid,
    });

class $$StaleDeviceRefreshRequestsTableFilterComposer
    extends Composer<_$LocalDatabase, $StaleDeviceRefreshRequestsTable> {
  $$StaleDeviceRefreshRequestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get staleDeviceId => $composableBuilder(
    column: $table.staleDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StaleDeviceRefreshRequestsTableOrderingComposer
    extends Composer<_$LocalDatabase, $StaleDeviceRefreshRequestsTable> {
  $$StaleDeviceRefreshRequestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get staleDeviceId => $composableBuilder(
    column: $table.staleDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StaleDeviceRefreshRequestsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $StaleDeviceRefreshRequestsTable> {
  $$StaleDeviceRefreshRequestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get staleDeviceId => $composableBuilder(
    column: $table.staleDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );
}

class $$StaleDeviceRefreshRequestsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $StaleDeviceRefreshRequestsTable,
          StaleDeviceRefreshRequest,
          $$StaleDeviceRefreshRequestsTableFilterComposer,
          $$StaleDeviceRefreshRequestsTableOrderingComposer,
          $$StaleDeviceRefreshRequestsTableAnnotationComposer,
          $$StaleDeviceRefreshRequestsTableCreateCompanionBuilder,
          $$StaleDeviceRefreshRequestsTableUpdateCompanionBuilder,
          (
            StaleDeviceRefreshRequest,
            BaseReferences<
              _$LocalDatabase,
              $StaleDeviceRefreshRequestsTable,
              StaleDeviceRefreshRequest
            >,
          ),
          StaleDeviceRefreshRequest,
          PrefetchHooks Function()
        > {
  $$StaleDeviceRefreshRequestsTableTableManager(
    _$LocalDatabase db,
    $StaleDeviceRefreshRequestsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StaleDeviceRefreshRequestsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$StaleDeviceRefreshRequestsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StaleDeviceRefreshRequestsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> staleDeviceId = const Value.absent(),
                Value<int> state = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StaleDeviceRefreshRequestsCompanion(
                userId: userId,
                staleDeviceId: staleDeviceId,
                state: state,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String staleDeviceId,
                Value<int> state = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StaleDeviceRefreshRequestsCompanion.insert(
                userId: userId,
                staleDeviceId: staleDeviceId,
                state: state,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StaleDeviceRefreshRequestsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $StaleDeviceRefreshRequestsTable,
      StaleDeviceRefreshRequest,
      $$StaleDeviceRefreshRequestsTableFilterComposer,
      $$StaleDeviceRefreshRequestsTableOrderingComposer,
      $$StaleDeviceRefreshRequestsTableAnnotationComposer,
      $$StaleDeviceRefreshRequestsTableCreateCompanionBuilder,
      $$StaleDeviceRefreshRequestsTableUpdateCompanionBuilder,
      (
        StaleDeviceRefreshRequest,
        BaseReferences<
          _$LocalDatabase,
          $StaleDeviceRefreshRequestsTable,
          StaleDeviceRefreshRequest
        >,
      ),
      StaleDeviceRefreshRequest,
      PrefetchHooks Function()
    >;
typedef $$ReceiptsTableCreateCompanionBuilder =
    ReceiptsCompanion Function({
      required String messageId,
      required String userId,
      required String deviceId,
      required int receiptState,
      required Uint8List projectionCiphertext,
      Value<int> rowid,
    });
typedef $$ReceiptsTableUpdateCompanionBuilder =
    ReceiptsCompanion Function({
      Value<String> messageId,
      Value<String> userId,
      Value<String> deviceId,
      Value<int> receiptState,
      Value<Uint8List> projectionCiphertext,
      Value<int> rowid,
    });

final class $$ReceiptsTableReferences
    extends BaseReferences<_$LocalDatabase, $ReceiptsTable, Receipt> {
  $$ReceiptsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MessagesTable _messageIdTable(_$LocalDatabase db) =>
      db.messages.createAlias('receipts__message_id__messages__message_id');

  $$MessagesTableProcessedTableManager get messageId {
    final $_column = $_itemColumn<String>('message_id')!;

    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.messageId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReceiptsTableFilterComposer
    extends Composer<_$LocalDatabase, $ReceiptsTable> {
  $$ReceiptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receiptState => $composableBuilder(
    column: $table.receiptState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get projectionCiphertext => $composableBuilder(
    column: $table.projectionCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  $$MessagesTableFilterComposer get messageId {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReceiptsTableOrderingComposer
    extends Composer<_$LocalDatabase, $ReceiptsTable> {
  $$ReceiptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receiptState => $composableBuilder(
    column: $table.receiptState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get projectionCiphertext => $composableBuilder(
    column: $table.projectionCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  $$MessagesTableOrderingComposer get messageId {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableOrderingComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReceiptsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $ReceiptsTable> {
  $$ReceiptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get receiptState => $composableBuilder(
    column: $table.receiptState,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get projectionCiphertext => $composableBuilder(
    column: $table.projectionCiphertext,
    builder: (column) => column,
  );

  $$MessagesTableAnnotationComposer get messageId {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReceiptsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $ReceiptsTable,
          Receipt,
          $$ReceiptsTableFilterComposer,
          $$ReceiptsTableOrderingComposer,
          $$ReceiptsTableAnnotationComposer,
          $$ReceiptsTableCreateCompanionBuilder,
          $$ReceiptsTableUpdateCompanionBuilder,
          (Receipt, $$ReceiptsTableReferences),
          Receipt,
          PrefetchHooks Function({bool messageId})
        > {
  $$ReceiptsTableTableManager(_$LocalDatabase db, $ReceiptsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReceiptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReceiptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReceiptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> messageId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> receiptState = const Value.absent(),
                Value<Uint8List> projectionCiphertext = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReceiptsCompanion(
                messageId: messageId,
                userId: userId,
                deviceId: deviceId,
                receiptState: receiptState,
                projectionCiphertext: projectionCiphertext,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String messageId,
                required String userId,
                required String deviceId,
                required int receiptState,
                required Uint8List projectionCiphertext,
                Value<int> rowid = const Value.absent(),
              }) => ReceiptsCompanion.insert(
                messageId: messageId,
                userId: userId,
                deviceId: deviceId,
                receiptState: receiptState,
                projectionCiphertext: projectionCiphertext,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReceiptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (messageId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.messageId,
                                referencedTable: $$ReceiptsTableReferences
                                    ._messageIdTable(db),
                                referencedColumn: $$ReceiptsTableReferences
                                    ._messageIdTable(db)
                                    .messageId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReceiptsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $ReceiptsTable,
      Receipt,
      $$ReceiptsTableFilterComposer,
      $$ReceiptsTableOrderingComposer,
      $$ReceiptsTableAnnotationComposer,
      $$ReceiptsTableCreateCompanionBuilder,
      $$ReceiptsTableUpdateCompanionBuilder,
      (Receipt, $$ReceiptsTableReferences),
      Receipt,
      PrefetchHooks Function({bool messageId})
    >;
typedef $$VoiceRoomsTableCreateCompanionBuilder =
    VoiceRoomsCompanion Function({
      required String localRoomId,
      required Uint8List capabilityCiphertext,
      required Uint8List metadataCiphertext,
      required int liveState,
      Value<int> rowid,
    });
typedef $$VoiceRoomsTableUpdateCompanionBuilder =
    VoiceRoomsCompanion Function({
      Value<String> localRoomId,
      Value<Uint8List> capabilityCiphertext,
      Value<Uint8List> metadataCiphertext,
      Value<int> liveState,
      Value<int> rowid,
    });

class $$VoiceRoomsTableFilterComposer
    extends Composer<_$LocalDatabase, $VoiceRoomsTable> {
  $$VoiceRoomsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localRoomId => $composableBuilder(
    column: $table.localRoomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get capabilityCiphertext => $composableBuilder(
    column: $table.capabilityCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get metadataCiphertext => $composableBuilder(
    column: $table.metadataCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get liveState => $composableBuilder(
    column: $table.liveState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VoiceRoomsTableOrderingComposer
    extends Composer<_$LocalDatabase, $VoiceRoomsTable> {
  $$VoiceRoomsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localRoomId => $composableBuilder(
    column: $table.localRoomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get capabilityCiphertext => $composableBuilder(
    column: $table.capabilityCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get metadataCiphertext => $composableBuilder(
    column: $table.metadataCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get liveState => $composableBuilder(
    column: $table.liveState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VoiceRoomsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $VoiceRoomsTable> {
  $$VoiceRoomsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localRoomId => $composableBuilder(
    column: $table.localRoomId,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get capabilityCiphertext => $composableBuilder(
    column: $table.capabilityCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get metadataCiphertext => $composableBuilder(
    column: $table.metadataCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get liveState =>
      $composableBuilder(column: $table.liveState, builder: (column) => column);
}

class $$VoiceRoomsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $VoiceRoomsTable,
          VoiceRoom,
          $$VoiceRoomsTableFilterComposer,
          $$VoiceRoomsTableOrderingComposer,
          $$VoiceRoomsTableAnnotationComposer,
          $$VoiceRoomsTableCreateCompanionBuilder,
          $$VoiceRoomsTableUpdateCompanionBuilder,
          (
            VoiceRoom,
            BaseReferences<_$LocalDatabase, $VoiceRoomsTable, VoiceRoom>,
          ),
          VoiceRoom,
          PrefetchHooks Function()
        > {
  $$VoiceRoomsTableTableManager(_$LocalDatabase db, $VoiceRoomsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VoiceRoomsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VoiceRoomsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VoiceRoomsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localRoomId = const Value.absent(),
                Value<Uint8List> capabilityCiphertext = const Value.absent(),
                Value<Uint8List> metadataCiphertext = const Value.absent(),
                Value<int> liveState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VoiceRoomsCompanion(
                localRoomId: localRoomId,
                capabilityCiphertext: capabilityCiphertext,
                metadataCiphertext: metadataCiphertext,
                liveState: liveState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localRoomId,
                required Uint8List capabilityCiphertext,
                required Uint8List metadataCiphertext,
                required int liveState,
                Value<int> rowid = const Value.absent(),
              }) => VoiceRoomsCompanion.insert(
                localRoomId: localRoomId,
                capabilityCiphertext: capabilityCiphertext,
                metadataCiphertext: metadataCiphertext,
                liveState: liveState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VoiceRoomsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $VoiceRoomsTable,
      VoiceRoom,
      $$VoiceRoomsTableFilterComposer,
      $$VoiceRoomsTableOrderingComposer,
      $$VoiceRoomsTableAnnotationComposer,
      $$VoiceRoomsTableCreateCompanionBuilder,
      $$VoiceRoomsTableUpdateCompanionBuilder,
      (VoiceRoom, BaseReferences<_$LocalDatabase, $VoiceRoomsTable, VoiceRoom>),
      VoiceRoom,
      PrefetchHooks Function()
    >;
typedef $$HistoryTransfersTableCreateCompanionBuilder =
    HistoryTransfersCompanion Function({
      required String transferId,
      required Uint8List manifestCiphertext,
      Value<int> eventProgress,
      required int sourceCompleteness,
      Value<int> rowid,
    });
typedef $$HistoryTransfersTableUpdateCompanionBuilder =
    HistoryTransfersCompanion Function({
      Value<String> transferId,
      Value<Uint8List> manifestCiphertext,
      Value<int> eventProgress,
      Value<int> sourceCompleteness,
      Value<int> rowid,
    });

class $$HistoryTransfersTableFilterComposer
    extends Composer<_$LocalDatabase, $HistoryTransfersTable> {
  $$HistoryTransfersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get manifestCiphertext => $composableBuilder(
    column: $table.manifestCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get eventProgress => $composableBuilder(
    column: $table.eventProgress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceCompleteness => $composableBuilder(
    column: $table.sourceCompleteness,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HistoryTransfersTableOrderingComposer
    extends Composer<_$LocalDatabase, $HistoryTransfersTable> {
  $$HistoryTransfersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get manifestCiphertext => $composableBuilder(
    column: $table.manifestCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get eventProgress => $composableBuilder(
    column: $table.eventProgress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceCompleteness => $composableBuilder(
    column: $table.sourceCompleteness,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoryTransfersTableAnnotationComposer
    extends Composer<_$LocalDatabase, $HistoryTransfersTable> {
  $$HistoryTransfersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get manifestCiphertext => $composableBuilder(
    column: $table.manifestCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get eventProgress => $composableBuilder(
    column: $table.eventProgress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceCompleteness => $composableBuilder(
    column: $table.sourceCompleteness,
    builder: (column) => column,
  );
}

class $$HistoryTransfersTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $HistoryTransfersTable,
          HistoryTransfer,
          $$HistoryTransfersTableFilterComposer,
          $$HistoryTransfersTableOrderingComposer,
          $$HistoryTransfersTableAnnotationComposer,
          $$HistoryTransfersTableCreateCompanionBuilder,
          $$HistoryTransfersTableUpdateCompanionBuilder,
          (
            HistoryTransfer,
            BaseReferences<
              _$LocalDatabase,
              $HistoryTransfersTable,
              HistoryTransfer
            >,
          ),
          HistoryTransfer,
          PrefetchHooks Function()
        > {
  $$HistoryTransfersTableTableManager(
    _$LocalDatabase db,
    $HistoryTransfersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryTransfersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryTransfersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryTransfersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> transferId = const Value.absent(),
                Value<Uint8List> manifestCiphertext = const Value.absent(),
                Value<int> eventProgress = const Value.absent(),
                Value<int> sourceCompleteness = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryTransfersCompanion(
                transferId: transferId,
                manifestCiphertext: manifestCiphertext,
                eventProgress: eventProgress,
                sourceCompleteness: sourceCompleteness,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String transferId,
                required Uint8List manifestCiphertext,
                Value<int> eventProgress = const Value.absent(),
                required int sourceCompleteness,
                Value<int> rowid = const Value.absent(),
              }) => HistoryTransfersCompanion.insert(
                transferId: transferId,
                manifestCiphertext: manifestCiphertext,
                eventProgress: eventProgress,
                sourceCompleteness: sourceCompleteness,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HistoryTransfersTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $HistoryTransfersTable,
      HistoryTransfer,
      $$HistoryTransfersTableFilterComposer,
      $$HistoryTransfersTableOrderingComposer,
      $$HistoryTransfersTableAnnotationComposer,
      $$HistoryTransfersTableCreateCompanionBuilder,
      $$HistoryTransfersTableUpdateCompanionBuilder,
      (
        HistoryTransfer,
        BaseReferences<
          _$LocalDatabase,
          $HistoryTransfersTable,
          HistoryTransfer
        >,
      ),
      HistoryTransfer,
      PrefetchHooks Function()
    >;
typedef $$SyncCheckpointsTableCreateCompanionBuilder =
    SyncCheckpointsCompanion Function({
      Value<int> singletonId,
      Value<int> highestContiguousAckedSequence,
      Value<int> prunedThrough,
      required Uint8List etagsCiphertext,
      required int retryState,
      required int protocolVersion,
      Value<int> queueGapState,
      Value<bool> drainRequested,
      Value<int> connectionPhase,
      Value<int> reconnectAttempt,
      Value<DateTime?> reconnectAt,
      Value<DateTime?> lastSuccessfulSyncAt,
    });
typedef $$SyncCheckpointsTableUpdateCompanionBuilder =
    SyncCheckpointsCompanion Function({
      Value<int> singletonId,
      Value<int> highestContiguousAckedSequence,
      Value<int> prunedThrough,
      Value<Uint8List> etagsCiphertext,
      Value<int> retryState,
      Value<int> protocolVersion,
      Value<int> queueGapState,
      Value<bool> drainRequested,
      Value<int> connectionPhase,
      Value<int> reconnectAttempt,
      Value<DateTime?> reconnectAt,
      Value<DateTime?> lastSuccessfulSyncAt,
    });

class $$SyncCheckpointsTableFilterComposer
    extends Composer<_$LocalDatabase, $SyncCheckpointsTable> {
  $$SyncCheckpointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get highestContiguousAckedSequence => $composableBuilder(
    column: $table.highestContiguousAckedSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get prunedThrough => $composableBuilder(
    column: $table.prunedThrough,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get etagsCiphertext => $composableBuilder(
    column: $table.etagsCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryState => $composableBuilder(
    column: $table.retryState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get queueGapState => $composableBuilder(
    column: $table.queueGapState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get drainRequested => $composableBuilder(
    column: $table.drainRequested,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get connectionPhase => $composableBuilder(
    column: $table.connectionPhase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reconnectAttempt => $composableBuilder(
    column: $table.reconnectAttempt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get reconnectAt => $composableBuilder(
    column: $table.reconnectAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSuccessfulSyncAt => $composableBuilder(
    column: $table.lastSuccessfulSyncAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCheckpointsTableOrderingComposer
    extends Composer<_$LocalDatabase, $SyncCheckpointsTable> {
  $$SyncCheckpointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get highestContiguousAckedSequence => $composableBuilder(
    column: $table.highestContiguousAckedSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get prunedThrough => $composableBuilder(
    column: $table.prunedThrough,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get etagsCiphertext => $composableBuilder(
    column: $table.etagsCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryState => $composableBuilder(
    column: $table.retryState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get queueGapState => $composableBuilder(
    column: $table.queueGapState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get drainRequested => $composableBuilder(
    column: $table.drainRequested,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get connectionPhase => $composableBuilder(
    column: $table.connectionPhase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reconnectAttempt => $composableBuilder(
    column: $table.reconnectAttempt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get reconnectAt => $composableBuilder(
    column: $table.reconnectAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSuccessfulSyncAt => $composableBuilder(
    column: $table.lastSuccessfulSyncAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCheckpointsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $SyncCheckpointsTable> {
  $$SyncCheckpointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get highestContiguousAckedSequence => $composableBuilder(
    column: $table.highestContiguousAckedSequence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get prunedThrough => $composableBuilder(
    column: $table.prunedThrough,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get etagsCiphertext => $composableBuilder(
    column: $table.etagsCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retryState => $composableBuilder(
    column: $table.retryState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get queueGapState => $composableBuilder(
    column: $table.queueGapState,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get drainRequested => $composableBuilder(
    column: $table.drainRequested,
    builder: (column) => column,
  );

  GeneratedColumn<int> get connectionPhase => $composableBuilder(
    column: $table.connectionPhase,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reconnectAttempt => $composableBuilder(
    column: $table.reconnectAttempt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get reconnectAt => $composableBuilder(
    column: $table.reconnectAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSuccessfulSyncAt => $composableBuilder(
    column: $table.lastSuccessfulSyncAt,
    builder: (column) => column,
  );
}

class $$SyncCheckpointsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $SyncCheckpointsTable,
          SyncCheckpoint,
          $$SyncCheckpointsTableFilterComposer,
          $$SyncCheckpointsTableOrderingComposer,
          $$SyncCheckpointsTableAnnotationComposer,
          $$SyncCheckpointsTableCreateCompanionBuilder,
          $$SyncCheckpointsTableUpdateCompanionBuilder,
          (
            SyncCheckpoint,
            BaseReferences<
              _$LocalDatabase,
              $SyncCheckpointsTable,
              SyncCheckpoint
            >,
          ),
          SyncCheckpoint,
          PrefetchHooks Function()
        > {
  $$SyncCheckpointsTableTableManager(
    _$LocalDatabase db,
    $SyncCheckpointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCheckpointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCheckpointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCheckpointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> singletonId = const Value.absent(),
                Value<int> highestContiguousAckedSequence =
                    const Value.absent(),
                Value<int> prunedThrough = const Value.absent(),
                Value<Uint8List> etagsCiphertext = const Value.absent(),
                Value<int> retryState = const Value.absent(),
                Value<int> protocolVersion = const Value.absent(),
                Value<int> queueGapState = const Value.absent(),
                Value<bool> drainRequested = const Value.absent(),
                Value<int> connectionPhase = const Value.absent(),
                Value<int> reconnectAttempt = const Value.absent(),
                Value<DateTime?> reconnectAt = const Value.absent(),
                Value<DateTime?> lastSuccessfulSyncAt = const Value.absent(),
              }) => SyncCheckpointsCompanion(
                singletonId: singletonId,
                highestContiguousAckedSequence: highestContiguousAckedSequence,
                prunedThrough: prunedThrough,
                etagsCiphertext: etagsCiphertext,
                retryState: retryState,
                protocolVersion: protocolVersion,
                queueGapState: queueGapState,
                drainRequested: drainRequested,
                connectionPhase: connectionPhase,
                reconnectAttempt: reconnectAttempt,
                reconnectAt: reconnectAt,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
              ),
          createCompanionCallback:
              ({
                Value<int> singletonId = const Value.absent(),
                Value<int> highestContiguousAckedSequence =
                    const Value.absent(),
                Value<int> prunedThrough = const Value.absent(),
                required Uint8List etagsCiphertext,
                required int retryState,
                required int protocolVersion,
                Value<int> queueGapState = const Value.absent(),
                Value<bool> drainRequested = const Value.absent(),
                Value<int> connectionPhase = const Value.absent(),
                Value<int> reconnectAttempt = const Value.absent(),
                Value<DateTime?> reconnectAt = const Value.absent(),
                Value<DateTime?> lastSuccessfulSyncAt = const Value.absent(),
              }) => SyncCheckpointsCompanion.insert(
                singletonId: singletonId,
                highestContiguousAckedSequence: highestContiguousAckedSequence,
                prunedThrough: prunedThrough,
                etagsCiphertext: etagsCiphertext,
                retryState: retryState,
                protocolVersion: protocolVersion,
                queueGapState: queueGapState,
                drainRequested: drainRequested,
                connectionPhase: connectionPhase,
                reconnectAttempt: reconnectAttempt,
                reconnectAt: reconnectAt,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCheckpointsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $SyncCheckpointsTable,
      SyncCheckpoint,
      $$SyncCheckpointsTableFilterComposer,
      $$SyncCheckpointsTableOrderingComposer,
      $$SyncCheckpointsTableAnnotationComposer,
      $$SyncCheckpointsTableCreateCompanionBuilder,
      $$SyncCheckpointsTableUpdateCompanionBuilder,
      (
        SyncCheckpoint,
        BaseReferences<_$LocalDatabase, $SyncCheckpointsTable, SyncCheckpoint>,
      ),
      SyncCheckpoint,
      PrefetchHooks Function()
    >;
typedef $$LocalPreferencesTableCreateCompanionBuilder =
    LocalPreferencesCompanion Function({
      required String preferenceKey,
      required Uint8List valueCiphertext,
      required int valueVersion,
      Value<int> rowid,
    });
typedef $$LocalPreferencesTableUpdateCompanionBuilder =
    LocalPreferencesCompanion Function({
      Value<String> preferenceKey,
      Value<Uint8List> valueCiphertext,
      Value<int> valueVersion,
      Value<int> rowid,
    });

class $$LocalPreferencesTableFilterComposer
    extends Composer<_$LocalDatabase, $LocalPreferencesTable> {
  $$LocalPreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get preferenceKey => $composableBuilder(
    column: $table.preferenceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get valueCiphertext => $composableBuilder(
    column: $table.valueCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get valueVersion => $composableBuilder(
    column: $table.valueVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalPreferencesTableOrderingComposer
    extends Composer<_$LocalDatabase, $LocalPreferencesTable> {
  $$LocalPreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get preferenceKey => $composableBuilder(
    column: $table.preferenceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get valueCiphertext => $composableBuilder(
    column: $table.valueCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get valueVersion => $composableBuilder(
    column: $table.valueVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalPreferencesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $LocalPreferencesTable> {
  $$LocalPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get preferenceKey => $composableBuilder(
    column: $table.preferenceKey,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get valueCiphertext => $composableBuilder(
    column: $table.valueCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get valueVersion => $composableBuilder(
    column: $table.valueVersion,
    builder: (column) => column,
  );
}

class $$LocalPreferencesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $LocalPreferencesTable,
          LocalPreference,
          $$LocalPreferencesTableFilterComposer,
          $$LocalPreferencesTableOrderingComposer,
          $$LocalPreferencesTableAnnotationComposer,
          $$LocalPreferencesTableCreateCompanionBuilder,
          $$LocalPreferencesTableUpdateCompanionBuilder,
          (
            LocalPreference,
            BaseReferences<
              _$LocalDatabase,
              $LocalPreferencesTable,
              LocalPreference
            >,
          ),
          LocalPreference,
          PrefetchHooks Function()
        > {
  $$LocalPreferencesTableTableManager(
    _$LocalDatabase db,
    $LocalPreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalPreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> preferenceKey = const Value.absent(),
                Value<Uint8List> valueCiphertext = const Value.absent(),
                Value<int> valueVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalPreferencesCompanion(
                preferenceKey: preferenceKey,
                valueCiphertext: valueCiphertext,
                valueVersion: valueVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String preferenceKey,
                required Uint8List valueCiphertext,
                required int valueVersion,
                Value<int> rowid = const Value.absent(),
              }) => LocalPreferencesCompanion.insert(
                preferenceKey: preferenceKey,
                valueCiphertext: valueCiphertext,
                valueVersion: valueVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalPreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $LocalPreferencesTable,
      LocalPreference,
      $$LocalPreferencesTableFilterComposer,
      $$LocalPreferencesTableOrderingComposer,
      $$LocalPreferencesTableAnnotationComposer,
      $$LocalPreferencesTableCreateCompanionBuilder,
      $$LocalPreferencesTableUpdateCompanionBuilder,
      (
        LocalPreference,
        BaseReferences<
          _$LocalDatabase,
          $LocalPreferencesTable,
          LocalPreference
        >,
      ),
      LocalPreference,
      PrefetchHooks Function()
    >;
typedef $$QuarantineRecordsTableCreateCompanionBuilder =
    QuarantineRecordsCompanion Function({
      Value<int> id,
      required int reasonCode,
      required Uint8List opaqueDigest,
      Value<DateTime> receivedAt,
    });
typedef $$QuarantineRecordsTableUpdateCompanionBuilder =
    QuarantineRecordsCompanion Function({
      Value<int> id,
      Value<int> reasonCode,
      Value<Uint8List> opaqueDigest,
      Value<DateTime> receivedAt,
    });

class $$QuarantineRecordsTableFilterComposer
    extends Composer<_$LocalDatabase, $QuarantineRecordsTable> {
  $$QuarantineRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reasonCode => $composableBuilder(
    column: $table.reasonCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get opaqueDigest => $composableBuilder(
    column: $table.opaqueDigest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QuarantineRecordsTableOrderingComposer
    extends Composer<_$LocalDatabase, $QuarantineRecordsTable> {
  $$QuarantineRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reasonCode => $composableBuilder(
    column: $table.reasonCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get opaqueDigest => $composableBuilder(
    column: $table.opaqueDigest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QuarantineRecordsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $QuarantineRecordsTable> {
  $$QuarantineRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get reasonCode => $composableBuilder(
    column: $table.reasonCode,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get opaqueDigest => $composableBuilder(
    column: $table.opaqueDigest,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => column,
  );
}

class $$QuarantineRecordsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $QuarantineRecordsTable,
          QuarantineRecord,
          $$QuarantineRecordsTableFilterComposer,
          $$QuarantineRecordsTableOrderingComposer,
          $$QuarantineRecordsTableAnnotationComposer,
          $$QuarantineRecordsTableCreateCompanionBuilder,
          $$QuarantineRecordsTableUpdateCompanionBuilder,
          (
            QuarantineRecord,
            BaseReferences<
              _$LocalDatabase,
              $QuarantineRecordsTable,
              QuarantineRecord
            >,
          ),
          QuarantineRecord,
          PrefetchHooks Function()
        > {
  $$QuarantineRecordsTableTableManager(
    _$LocalDatabase db,
    $QuarantineRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QuarantineRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QuarantineRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QuarantineRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> reasonCode = const Value.absent(),
                Value<Uint8List> opaqueDigest = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
              }) => QuarantineRecordsCompanion(
                id: id,
                reasonCode: reasonCode,
                opaqueDigest: opaqueDigest,
                receivedAt: receivedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int reasonCode,
                required Uint8List opaqueDigest,
                Value<DateTime> receivedAt = const Value.absent(),
              }) => QuarantineRecordsCompanion.insert(
                id: id,
                reasonCode: reasonCode,
                opaqueDigest: opaqueDigest,
                receivedAt: receivedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QuarantineRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $QuarantineRecordsTable,
      QuarantineRecord,
      $$QuarantineRecordsTableFilterComposer,
      $$QuarantineRecordsTableOrderingComposer,
      $$QuarantineRecordsTableAnnotationComposer,
      $$QuarantineRecordsTableCreateCompanionBuilder,
      $$QuarantineRecordsTableUpdateCompanionBuilder,
      (
        QuarantineRecord,
        BaseReferences<
          _$LocalDatabase,
          $QuarantineRecordsTable,
          QuarantineRecord
        >,
      ),
      QuarantineRecord,
      PrefetchHooks Function()
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $$AccountSessionsTableTableManager get accountSessions =>
      $$AccountSessionsTableTableManager(_db, _db.accountSessions);
  $$SecureSecretsTableTableManager get secureSecrets =>
      $$SecureSecretsTableTableManager(_db, _db.secureSecrets);
  $$AccountIdentitiesTableTableManager get accountIdentities =>
      $$AccountIdentitiesTableTableManager(_db, _db.accountIdentities);
  $$EnrollmentIntentsTableTableManager get enrollmentIntents =>
      $$EnrollmentIntentsTableTableManager(_db, _db.enrollmentIntents);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
  $$DeviceLogRecordsTableTableManager get deviceLogRecords =>
      $$DeviceLogRecordsTableTableManager(_db, _db.deviceLogRecords);
  $$PairwiseSessionsTableTableManager get pairwiseSessions =>
      $$PairwiseSessionsTableTableManager(_db, _db.pairwiseSessions);
  $$PrekeysTableTableManager get prekeys =>
      $$PrekeysTableTableManager(_db, _db.prekeys);
  $$MlsGroupsTableTableManager get mlsGroups =>
      $$MlsGroupsTableTableManager(_db, _db.mlsGroups);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$MembershipsTableTableManager get memberships =>
      $$MembershipsTableTableManager(_db, _db.memberships);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$MessageEventsTableTableManager get messageEvents =>
      $$MessageEventsTableTableManager(_db, _db.messageEvents);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db, _db.attachments);
  $$InboxEnvelopesTableTableManager get inboxEnvelopes =>
      $$InboxEnvelopesTableTableManager(_db, _db.inboxEnvelopes);
  $$OutboxOperationsTableTableManager get outboxOperations =>
      $$OutboxOperationsTableTableManager(_db, _db.outboxOperations);
  $$InboxEventDeduplicationsTableTableManager get inboxEventDeduplications =>
      $$InboxEventDeduplicationsTableTableManager(
        _db,
        _db.inboxEventDeduplications,
      );
  $$StaleDeviceRefreshRequestsTableTableManager
  get staleDeviceRefreshRequests =>
      $$StaleDeviceRefreshRequestsTableTableManager(
        _db,
        _db.staleDeviceRefreshRequests,
      );
  $$ReceiptsTableTableManager get receipts =>
      $$ReceiptsTableTableManager(_db, _db.receipts);
  $$VoiceRoomsTableTableManager get voiceRooms =>
      $$VoiceRoomsTableTableManager(_db, _db.voiceRooms);
  $$HistoryTransfersTableTableManager get historyTransfers =>
      $$HistoryTransfersTableTableManager(_db, _db.historyTransfers);
  $$SyncCheckpointsTableTableManager get syncCheckpoints =>
      $$SyncCheckpointsTableTableManager(_db, _db.syncCheckpoints);
  $$LocalPreferencesTableTableManager get localPreferences =>
      $$LocalPreferencesTableTableManager(_db, _db.localPreferences);
  $$QuarantineRecordsTableTableManager get quarantineRecords =>
      $$QuarantineRecordsTableTableManager(_db, _db.quarantineRecords);
}
