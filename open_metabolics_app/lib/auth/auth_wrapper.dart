import 'package:flutter/material.dart';
import 'package:open_metabolics_app/auth/login_page.dart';
import 'package:provider/provider.dart';
import 'user_model.dart';
import '../pages/home_page.dart';
import '../auth/login_page.dart';

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<theUser?>(context);

    // Return either Home or Login widget
    if (user == null) {
      return LoginPage();
    } else {
      return SensorScreen();
    }
  }
}
