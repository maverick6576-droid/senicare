import 'package:flutter/material.dart';

class ConfigNotifier extends ChangeNotifier {
  bool seniorMode = false;
  bool pendingCaregiverTutorial = false;
  bool pendingClientTutorial = false;

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

  /// Requests [MainLayout] to open the client (family) interactive tutorial.
  void triggerClientTutorial() {
    pendingClientTutorial = true;
    notifyListeners();
  }

  void consumeClientTutorialRequest() {
    pendingClientTutorial = false;
  }
}
