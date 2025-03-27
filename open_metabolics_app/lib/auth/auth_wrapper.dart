import 'package:flutter/material.dart';
import 'package:open_metabolics_app/auth/login_page.dart';
import 'package:provider/provider.dart';
import 'user_model.dart';
import '../pages/home_page.dart';
import '../auth/login_page.dart';
import 'auth_service.dart';

class AuthWrapper extends StatefulWidget {
  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isSignedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isSignedIn = await authService.isSignedIn();

    setState(() {
      _isSignedIn = isSignedIn;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return _isSignedIn ? SensorScreen() : LoginPage();
  }
}
