import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import 'package:open_metabolics_app/pages/home_page.dart';

class VerificationPage extends StatefulWidget {
  final String email;
  final String password;

  VerificationPage({required this.email, required this.password});

  @override
  _VerificationPageState createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final _verificationController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Verify Email',
          style: TextStyle(color: Color.fromRGBO(66, 66, 66, 1)),
        ),
        backgroundColor: Color.fromRGBO(216, 194, 251, 1),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Verify Your Email',
              style: TextStyle(
                color: Color.fromRGBO(66, 66, 66, 1),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Please enter the verification code sent to:\n${widget.email}',
              style: TextStyle(
                color: Color.fromRGBO(66, 66, 66, 1),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            TextField(
              controller: _verificationController,
              style: TextStyle(color: Color.fromRGBO(66, 66, 66, 1)),
              decoration: InputDecoration(
                hintText: 'Enter verification code',
                hintStyle: TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Color.fromRGBO(216, 194, 251, 1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Color.fromRGBO(216, 194, 251, 1),
                  ),
                ),
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      setState(() {
                        _isLoading = true;
                      });

                      try {
                        final success = await authService.verifyEmail(
                          widget.email,
                          _verificationController.text,
                        );

                        setState(() {
                          _isLoading = false;
                        });

                        if (success) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => SensorScreen(),
                            ),
                            (Route<dynamic> route) => false,
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Verification failed. Please try again.'),
                            ),
                          );
                        }
                      } catch (e) {
                        setState(() {
                          _isLoading = false;
                        });

                        if (e.toString().contains('SocketException') ||
                            e.toString().contains('Failed host lookup')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'No internet connection. Please check your network and try again.'),
                              duration: Duration(seconds: 3),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Verification failed. Please try again.'),
                              duration: Duration(seconds: 3),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromRGBO(216, 194, 251, 1),
                foregroundColor: Color.fromRGBO(66, 66, 66, 1),
                padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
              ),
              child: _isLoading
                  ? CircularProgressIndicator(
                      color: Color.fromRGBO(66, 66, 66, 1))
                  : Text(
                      'Verify',
                      style: TextStyle(
                        color: Color.fromRGBO(66, 66, 66, 1),
                        fontSize: 18,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
