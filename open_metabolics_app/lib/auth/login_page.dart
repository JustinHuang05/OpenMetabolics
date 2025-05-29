import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import '../widgets/login_tf.dart';
import 'signup_page.dart';
import '../pages/home_page.dart';

class LoginPage extends StatefulWidget {
  static const pageRoute = '/login_page';

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  void switchPage(BuildContext context) {
    Navigator.pushNamed(context, '/signUp_page');
  }

  var emailCont = TextEditingController();
  var passCont = TextEditingController();

  bool emailError = false;
  bool passError = false;

  String emailErrorText = 'User does not exist';
  String passErrorText = 'Incorrect password';

  bool buttonActivated = false;

  @override
  Widget build(BuildContext context) {
    var mediaQuery = MediaQuery.of(context);

    return GestureDetector(
      onTap: () {
        FocusScopeNode currentFocus = FocusScope.of(context);
        if (!currentFocus.hasPrimaryFocus) {
          currentFocus.unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        extendBody: true,
        resizeToAvoidBottomInset: false,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(100.0),
          child: Container(
            height: mediaQuery.size.height * 0.13,
            child: CupertinoNavigationBar(
              backgroundColor: Colors.white,
              middle: Text(
                'OpenMetabolics',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color.fromRGBO(147, 112, 219, 1),
                ),
              ),
              border: Border(
                bottom: BorderSide(color: Colors.transparent),
              ),
            ),
          ),
        ),
        body: SingleChildScrollView(
          reverse: true,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                height:
                    mediaQuery.size.height - (mediaQuery.size.height * 0.26),
                width: double.infinity,
                margin: EdgeInsets.only(left: 35, right: 35),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Login',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        fontSize: 56,
                        color: Color.fromRGBO(66, 66, 66, 1),
                      ),
                    ),
                    SizedBox(height: 23),
                    LoginTf(' Email', 'Enter email...', emailCont, emailError,
                        emailErrorText, true),
                    LoginTf(' Password', 'Enter password...', passCont,
                        passError, passErrorText, false),
                    SizedBox(height: 10),
                    SizedBox(
                      width: mediaQuery.size.width * 0.54,
                      height: 60,
                      child: ElevatedButton(
                        style: ButtonStyle(
                          elevation: MaterialStateProperty.all(0),
                          backgroundColor: MaterialStateProperty.all(
                            Color.fromRGBO(216, 194, 251, 1),
                          ),
                          shape:
                              MaterialStateProperty.all<RoundedRectangleBorder>(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        onPressed: handleLogin,
                        child: Text(
                          'Login',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: Color.fromRGBO(66, 66, 66, 1),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: EdgeInsets.only(top: mediaQuery.size.height * 0.035),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account yet? ",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.normal,
                        fontSize: 13,
                        color: Color.fromRGBO(66, 66, 66, 1),
                      ),
                    ),
                    GestureDetector(
                      child: Text(
                        'Sign Up',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.normal,
                          decoration: TextDecoration.underline,
                          fontSize: 13,
                          color: Color.fromRGBO(147, 112, 219, 1),
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          emailCont.text = '';
                          passCont.text = '';
                          emailError = false;
                          passError = false;
                        });
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => SignUpPage()),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  bottom: mediaQuery.viewInsets.bottom * 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> handleLogin() async {
    setState(() {
      emailError = false;
      passError = false;
    });

    if (emailCont.text != '' && passCont.text != '') {
      final authService = Provider.of<AuthService>(context, listen: false);
      try {
        final success = await authService.signIn(
          emailCont.text,
          passCont.text,
        );

        if (success) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => SensorScreen()),
            (Route<dynamic> route) => false,
          );
        }
      } catch (e) {
        print('Login error caught: $e');
        if (e.toString().contains('UserNotFoundException')) {
          setState(() {
            emailError = true;
            passError = false;
            emailErrorText = 'User does not exist';
          });
        } else if (e.toString().contains('NotAuthorizedException')) {
          setState(() {
            emailError = false;
            passError = true;
            passErrorText = 'Incorrect password';
          });
        } else if (e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'No internet connection. Please check your network and try again.'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      setState(() {
        if (emailCont.text.isEmpty) {
          emailError = true;
          emailErrorText = 'Email is required';
        }
        if (passCont.text.isEmpty) {
          passError = true;
          passErrorText = 'Password is required';
        }
      });
    }
  }
}
