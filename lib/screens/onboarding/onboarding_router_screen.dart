import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'client_onboarding_screen.dart';
import 'caregiver_onboarding_screen.dart';

class OnboardingRouterScreen extends StatelessWidget {
  const OnboardingRouterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthNotifier>().currentRole;
    if (role == 'client') {
      return const ClientOnboardingScreen();
    } else {
      return const CaregiverOnboardingScreen();
    }
  }
}
