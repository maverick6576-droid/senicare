abstract class AuthRepository {
  Stream<String?> get onAuthStateChanged;
  Future<void> signInAnonymously();
  Future<void> signInWithCustomToken(String token);
  Future<void> signUpWithEmail(String email, String password, String role, [Map<String, dynamic>? extraData]);
  Future<void> signInWithEmail(String email, String password);
  Future<void> signInWithGoogle(String role, {bool isLogin = true});
  Future<void> signInWithApple(String role, {bool isLogin = true});
  Future<void> signOut();
  Future<void> deleteAccount();
  String? get currentUserId;
  Future<String?> getUserRole(String uid);
  Future<void> updateFCMToken(String token);
  Future<void> sendPasswordResetEmail(String email);
}
