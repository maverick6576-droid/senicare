import 'package:cloud_firestore/cloud_firestore.dart';

/// Rol dentro de una cuenta familiar compartida (`clients/{familyId}`).
enum FamilyRole {
  admin,
  collaborator;

  String get firestoreValue =>
      this == FamilyRole.admin ? 'admin' : 'collaborator';

  String get displayLabel =>
      this == FamilyRole.admin ? 'Administrador' : 'Familiar colaborador';

  String get shortLabel =>
      this == FamilyRole.admin ? 'Admin' : 'Colaborador';

  String get permissionsSummary => this == FamilyRole.admin
      ? 'Pagos, reservas, ofertas, miembros y edición del perfil familiar'
      : 'Ver reservas, PIN/QR, Diario del Cuidado y chatear con cuidadores';

  bool get canManagePayments => this == FamilyRole.admin;
  bool get canManageMembers => this == FamilyRole.admin;
  bool get canManageCareDetails => this == FamilyRole.admin;
  bool get canViewBookings => true;
  bool get canViewCareDiary => true;
  bool get canChat => true;

  static FamilyRole fromString(dynamic raw) {
    final normalized = (raw ?? '').toString().trim().toLowerCase();
    if (normalized == 'admin' || normalized == 'administrador') {
      return FamilyRole.admin;
    }
    return FamilyRole.collaborator;
  }
}

/// Representa a un familiar conectado a una cuenta compartida (`clients/{familyId}`).
class FamilyMember {
  final String uid;
  final String email;
  final String displayName;
  final FamilyRole role;
  final DateTime? joinedAt;
  final String? joinedVia; // 'owner' | 'email' | 'code'
  final bool isOwner;

  const FamilyMember({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.joinedAt,
    this.joinedVia,
    this.isOwner = false,
  });

  String get effectiveName {
    final cleanName = displayName.trim();
    if (cleanName.isNotEmpty) return cleanName;
    final cleanEmail = email.trim();
    if (cleanEmail.contains('@')) return cleanEmail.split('@').first;
    return 'Familiar';
  }

  FamilyMember copyWith({
    String? email,
    String? displayName,
    FamilyRole? role,
    DateTime? joinedAt,
    String? joinedVia,
    bool? isOwner,
  }) {
    return FamilyMember(
      uid: uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      joinedVia: joinedVia ?? this.joinedVia,
      isOwner: isOwner ?? this.isOwner,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'role': role.firestoreValue,
      if (joinedAt != null) 'joinedAt': joinedAt!.toIso8601String(),
      if (joinedVia != null) 'joinedVia': joinedVia,
      'isOwner': isOwner,
    };
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  factory FamilyMember.fromMap(String uidKey, Map<String, dynamic> map) {
    final resolvedUid = (map['uid'] as String?)?.trim().isNotEmpty == true
        ? (map['uid'] as String).trim()
        : uidKey;
    return FamilyMember(
      uid: resolvedUid,
      email: (map['email'] ?? '').toString(),
      displayName: (map['displayName'] ?? map['name'] ?? '').toString(),
      role: FamilyRole.fromString(map['role']),
      joinedAt: _parseDate(map['joinedAt']),
      joinedVia: map['joinedVia']?.toString(),
      isOwner: map['isOwner'] == true,
    );
  }
}

/// Invitación activa por código/enlace para unirse a una cuenta familiar.
class FamilyInvite {
  static const String shareBaseUrl = 'https://senicare.app/join';

  final String code;
  final String familyId;
  final String familyName;
  final FamilyRole role;
  final String? invitedEmail;
  final String createdByUid;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int maxUses;
  final int usedCount;
  final bool revoked;

  const FamilyInvite({
    required this.code,
    required this.familyId,
    required this.familyName,
    required this.role,
    this.invitedEmail,
    required this.createdByUid,
    required this.createdAt,
    required this.expiresAt,
    this.maxUses = 5,
    this.usedCount = 0,
    this.revoked = false,
  });

  String get shareUrl => '$shareBaseUrl?code=${Uri.encodeComponent(code)}';

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get isExhausted => usedCount >= maxUses;

  bool get isActive => !revoked && !isExpired && !isExhausted;

  /// Extrae un código alfanumérico de invitación tanto de texto directo
  /// (`SN4K8P2M` / `SN4K-8P2M`) como de enlaces (`https://senicare.app/join?code=SN4K8P2M`).
  static String? extractInviteCode(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;

    // 1. Si viene como URI con query param `code=` o path final
    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.hasScheme || trimmed.contains('code='))) {
      final codeParam = uri.queryParameters['code'];
      if (codeParam != null && codeParam.trim().isNotEmpty) {
        final cleaned = _normalizeCode(codeParam);
        if (cleaned.length >= 6 && cleaned.length <= 16) return cleaned;
      }
      if (uri.pathSegments.isNotEmpty) {
        final last = _normalizeCode(uri.pathSegments.last);
        if (last.length >= 6 && last.length <= 16 && last != 'JOIN') {
          return last;
        }
      }
    }

    // 2. Fallback regex para mensajes pegados desde WhatsApp ("... code=SN4K8P2M ..." o código aislado)
    final paramMatch = RegExp(r'code=([A-Za-z0-9\-]{6,20})').firstMatch(trimmed);
    if (paramMatch != null) {
      final cleaned = _normalizeCode(paramMatch.group(1)!);
      if (cleaned.length >= 6 && cleaned.length <= 16) return cleaned;
    }

    final normalized = _normalizeCode(trimmed);
    if (RegExp(r'^[A-Z0-9]{6,16}$').hasMatch(normalized)) {
      return normalized;
    }

    final tokenMatch = RegExp(r'\b([A-Za-z0-9]{6,12})\b').firstMatch(trimmed);
    if (tokenMatch != null) {
      return _normalizeCode(tokenMatch.group(1)!);
    }

    return null;
  }

  static String _normalizeCode(String value) =>
      value.replaceAll(RegExp(r'[\s\-_]'), '').toUpperCase();

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'familyId': familyId,
      'familyName': familyName,
      'role': role.firestoreValue,
      if (invitedEmail != null && invitedEmail!.isNotEmpty)
        'invitedEmail': invitedEmail,
      'createdByUid': createdByUid,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'maxUses': maxUses,
      'usedCount': usedCount,
      'revoked': revoked,
    };
  }

  factory FamilyInvite.fromMap(String id, Map<String, dynamic> map) {
    final now = DateTime.now();
    return FamilyInvite(
      code: (map['code'] ?? id).toString().toUpperCase(),
      familyId: (map['familyId'] ?? '').toString(),
      familyName: (map['familyName'] ?? 'Familia SeniCare').toString(),
      role: FamilyRole.fromString(map['role']),
      invitedEmail: map['invitedEmail']?.toString(),
      createdByUid: (map['createdByUid'] ?? '').toString(),
      createdAt: FamilyMember._parseDate(map['createdAt']) ?? now,
      expiresAt: FamilyMember._parseDate(map['expiresAt']) ??
          now.add(const Duration(days: 7)),
      maxUses: (map['maxUses'] as num?)?.toInt() ?? 5,
      usedCount: (map['usedCount'] as num?)?.toInt() ?? 0,
      revoked: map['revoked'] == true,
    );
  }
}

/// Resultado al unir un usuario a una cuenta familiar.
class FamilyJoinResult {
  final String familyId;
  final String familyName;
  final FamilyRole role;
  final String joinedVia; // 'code' | 'email'
  final bool alreadyMember;

  const FamilyJoinResult({
    required this.familyId,
    required this.familyName,
    required this.role,
    required this.joinedVia,
    this.alreadyMember = false,
  });
}
