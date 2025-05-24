import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:open_metabolics_app/pages/home_page.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import '../widgets/signup_tf.dart';
import '../widgets/name_tf.dart';
import '../auth/verification_page.dart';

class SignUpPage extends StatefulWidget {
  static const pageRoute = '/signUp_page';

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  var fnameCont = TextEditingController();
  var lnameCont = TextEditingController();
  var emailCont = TextEditingController();
  var passCont = TextEditingController();
  var passContConf = TextEditingController();

  bool emailError = false;
  bool passError = false;
  bool passConfError = false;

  String emailErrorText = '';
  String passErrorText =
      'Use 8 or more characters with a mix of letters, numbers, and symbols';
  String passConfErrorText = 'Password does not match';

  bool buttonActivated = false;

  void popToLogin(BuildContext context) {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    var mediaQuery = MediaQuery.of(context);

    emailErrorCheck() {
      emailError = false;
    }

    passErrorCheck() {
      if (passCont.text.length >= 8 &&
          passCont.text.contains(new RegExp(r'[a-zA-Z]')) &&
          passCont.text.contains(new RegExp(r'[0-9]')) &&
          passCont.text.contains(new RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
        setState(() {
          passError = false;
          if (passCont.text != passContConf.text) {
            passConfError = true;
          } else {
            passConfError = false;
          }
        });
      } else {
        setState(() {
          passError = true;
          if (passCont.text != passContConf.text) {
            passConfError = true;
          } else {
            passConfError = false;
          }
        });
      }
    }

    passConfErrorCheck() {
      if (passContConf.text == passCont.text) {
        setState(() {
          passConfError = false;
        });
      } else {
        setState(() {
          passConfError = true;
        });
      }
    }

    return GestureDetector(
      onTap: () {
        FocusScopeNode currentFocus = FocusScope.of(context);
        if (!currentFocus.hasPrimaryFocus) {
          currentFocus.unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: Color.fromRGBO(66, 66, 66, 1),
        extendBody: true,
        resizeToAvoidBottomInset: false,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(100.0),
          child: Container(
            height: mediaQuery.size.height * 0.13,
            child: CupertinoNavigationBar(
              backgroundColor: Color.fromRGBO(66, 66, 66, 1),
              leading: GestureDetector(
                child: Align(
                  alignment: Alignment(-0.9, 0),
                  child: Icon(
                    Icons.arrow_back_ios,
                    size: 25,
                    color: Color.fromRGBO(216, 194, 251, 1),
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              middle: Text(
                'OpenMetabolics',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color.fromRGBO(216, 194, 251, 1),
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
                margin: EdgeInsets.only(left: 27, right: 27),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Sign Up',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        fontSize: 50,
                        color: Color.fromRGBO(255, 255, 255, 1),
                      ),
                    ),
                    SizedBox(height: 23),
                    Row(
                      children: [
                        Flexible(
                          child: NameTf(
                              ' *First Name', 'Enter first name...', fnameCont),
                          flex: 5,
                        ),
                        SizedBox(width: 12),
                        Flexible(
                          child: NameTf(
                              ' *Last Name', 'Enter last name...', lnameCont),
                          flex: 5,
                        ),
                      ],
                    ),
                    SignUpTf(
                      ' *Email',
                      'Enter email...',
                      emailCont,
                      emailError,
                      emailErrorText,
                      Colors.transparent,
                      emailErrorCheck,
                      true,
                    ),
                    SignUpTf(
                      ' *Password',
                      'Enter password...',
                      passCont,
                      passError,
                      passErrorText,
                      Color.fromRGBO(158, 158, 158, 1),
                      passErrorCheck,
                      false,
                    ),
                    SignUpTf(
                      ' *Confirm Password',
                      'Re-enter password...',
                      passContConf,
                      passConfError,
                      passConfErrorText,
                      Colors.transparent,
                      passConfErrorCheck,
                      false,
                    ),
                    Flexible(child: Container(), flex: 1),
                    Flexible(
                      flex: 7,
                      child: SizedBox(
                        width: mediaQuery.size.width * 0.54,
                        height: 60,
                        child: ElevatedButton(
                          style: ButtonStyle(
                            elevation: MaterialStateProperty.all(0),
                            backgroundColor: MaterialStateProperty.all(
                              Color.fromRGBO(216, 194, 251, 1),
                            ),
                            shape: MaterialStateProperty.all<
                                RoundedRectangleBorder>(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                          onPressed: () async {
                            if (fnameCont.text != '' &&
                                lnameCont.text != '' &&
                                emailCont.text != '' &&
                                passCont.text != '' &&
                                passContConf.text != '' &&
                                !passError &&
                                !passConfError) {
                              // Show loading indicator
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Signing up...')),
                              );

                              print('Starting signup process...'); // Debug log

                              try {
                                final success = await authService.signUp(
                                  emailCont.text,
                                  passCont.text,
                                  fnameCont.text,
                                  lnameCont.text,
                                );

                                // Clear the "Signing up..." message
                                ScaffoldMessenger.of(context).clearSnackBars();

                                print('Signup result: $success'); // Debug log

                                if (success) {
                                  // Show success message and navigate to verification
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Signup successful! Please check your email for verification code.'),
                                      duration: Duration(seconds: 3),
                                    ),
                                  );

                                  print(
                                      'Navigating to verification page...'); // Debug log
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VerificationPage(
                                        email: emailCont.text.toLowerCase(),
                                        password: passCont.text,
                                      ),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Sign up failed. Please try again.'),
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                }
                              } catch (e) {
                                // Clear the "Signing up..." message
                                ScaffoldMessenger.of(context).clearSnackBars();

                                if (e.toString().contains('SocketException') ||
                                    e
                                        .toString()
                                        .contains('Failed host lookup')) {
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
                                          'Sign up failed. Please try again.'),
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          child: Text(
                            'Sign Up',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: Color.fromRGBO(66, 66, 66, 1),
                            ),
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
                      'Already have an account? ',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.normal,
                        fontSize: 13,
                        color: Color.fromRGBO(224, 224, 224, 1),
                      ),
                    ),
                    GestureDetector(
                      child: Text(
                        'Login',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.normal,
                          decoration: TextDecoration.underline,
                          fontSize: 13,
                          color: Color.fromRGBO(171, 210, 255, 1),
                        ),
                      ),
                      onTap: () => popToLogin(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  bottom: mediaQuery.viewInsets.bottom * 0.60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
