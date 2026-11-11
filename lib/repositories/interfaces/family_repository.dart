import 'package:senicare/models/models.dart';

/// Repositorio para la gestión de cuentas familiares compartidas,
/// invitaciones por email o código/enlace y permisos por miembro.
abstract class FamilyRepository {
  /// Resuelve el `familyId` (`clients/{familyId}`) activo para [uid].
  /// 1. Si `users/{uid}.activeFamilyId` apunta a una familia válida donde sigue siendo miembro, lo devuelve.
  /// 2. Si existe `clients/{uid}`, devuelve [uid].
  /// 3. Si [email] coincide con una invitación pendiente (y [emailVerified] es true),
  ///    lo vincula automáticamente con el rol configurado y devuelve ese `familyId`.
  /// 4. En caso contrario devuelve `null` (familia nueva sin onboarding / sin unión).
  Future<String?> resolveActiveFamilyId({
    required String uid,
    String? email,
    String? displayName,
    bool emailVerified = false,
  });

  /// Crea una invitación compartible (código corto + URL) para unirse a [familyId].
  Future<FamilyInvite> createInvite({
    required String familyId,
    required String familyName,
    required FamilyRole role,
    String? invitedEmail,
    int maxUses = 5,
    Duration validFor = const Duration(days: 7),
  });

  /// Lista las invitaciones activas (no revocadas ni caducadas) de [familyId].
  Future<List<FamilyInvite>> getActiveInvites(String familyId);

  /// Revoca una invitación activa por código.
  Future<void> revokeInvite({
    required String familyId,
    required String code,
  });

  /// Añade o actualiza la autorización automática por email con un rol específico.
  Future<void> inviteByEmail({
    required String familyId,
    required String email,
    required FamilyRole role,
  });

  /// Elimina una invitación pendiente por email.
  Future<void> removeEmailInvite({
    required String familyId,
    required String email,
  });

  /// Une al usuario autenticado usando un código (`SN4K8P2M`) o enlace compartible.
  Future<FamilyJoinResult> joinWithCode({
    required String uid,
    required String codeOrUrl,
    String? email,
    String? displayName,
  });

  /// Actualiza el rol (`admin` / `collaborator`) de un familiar conectado.
  Future<void> updateMemberRole({
    required String familyId,
    required String memberUid,
    required FamilyRole newRole,
  });

  /// Expulsa a un familiar conectado de [familyId].
  Future<void> removeMember({
    required String familyId,
    required String memberUid,
  });

  /// El usuario actual [uid] abandona la cuenta familiar [familyId].
  Future<void> leaveFamily({
    required String familyId,
    required String uid,
  });

  /// Carga el perfil actualizado desde fuente remota/memoria (sin caché obsoleto).
  Future<ClientProfile?> fetchFreshFamilyProfile(String familyId);

  /// Devuelve y persiste si [uid] completó ya el tutorial en esta cuenta.
  Future<bool> hasSeenMemberTutorial(String uid);
  Future<void> markMemberTutorialSeen(String uid, {bool seen = true});
}
