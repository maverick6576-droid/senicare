import 'package:flutter/material.dart';

class ConfigNotifier extends ChangeNotifier {
  bool seniorMode = false;
  bool pendingCaregiverTutorial = false;

  void toggleSeniorMode(bool value) {
    seniorMode = value;
    notifyListeners();
  }

  /// Requests [MainLayout] to open the caregiver interactive tutorial.
  void triggerCaregiverTutorial() {
    pendingCaregiverTutorial = true;
    notifyListeners();
  }

  void consumeCaregiverTutorialRequest() {
    pendingCaregiverTutorial = false;
  }
}
