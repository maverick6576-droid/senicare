import 'package:flutter/material.dart';

class ConfigNotifier extends ChangeNotifier {
  bool seniorMode = false;

  void toggleSeniorMode(bool value) {
    seniorMode = value;
    notifyListeners();
  }
}
