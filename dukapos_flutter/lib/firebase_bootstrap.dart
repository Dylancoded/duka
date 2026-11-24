import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseBootstrap {
  static bool initialized = false;
  static String? error;

  static Future<bool> initialize() async {
    try {
      await Firebase.initializeApp();
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      initialized = true;
      error = null;
      return true;
    } catch (exception) {
      initialized = false;
      error = exception.toString();
      return false;
    }
  }

  static User? get user =>
      initialized ? FirebaseAuth.instance.currentUser : null;
}
