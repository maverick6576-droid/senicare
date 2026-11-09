import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:senicare/firebase_options.dart';

void main() {
  test('Check production caregivers', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    
    final qs = await FirebaseFirestore.instance.collection('caregivers').get();
    print('Found ${qs.docs.length} caregivers in production database.');
    for (var doc in qs.docs) {
      print('- ${doc.data()['name']}');
    }
  });
}
