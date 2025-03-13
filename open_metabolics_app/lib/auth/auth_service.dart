// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

class AuthService {
  // Remove Firebase-related code
  // final FirebaseAuth _auth = FirebaseAuth.instance;
  String loginErrorCode = '';
  String signupErrorCode = '';

  // Create user object based on FirebaseUser
  theUser? _userFromFirebaseUser(dynamic user) {
    return user != null ? theUser(uid: "dummy-uid") : null;
  }

  // Auth change user stream
  Stream<theUser?> get user {
    // return _auth.authStateChanges().map(_userFromFirebaseUser);
    return Stream.value(null); // Always return not authenticated for now
  }

  // Simplified auth methods for now
  Future<bool> signIn(String email, String password) async {
    try {
      print('Attempting to sign in user: $email');

      final result = await Amplify.Auth.signIn(
        username: email,
        password: password,
      );

      print('Sign in result: ${result.isSignedIn}');
      return result.isSignedIn;
    } on AuthException catch (e) {
      print('Sign in error: $e');

      // Convert Amplify errors to our own format
      if (e.message.contains('User does not exist')) {
        throw Exception('UserNotFoundException');
      } else if (e.message.contains('Incorrect username or password')) {
        throw Exception('NotAuthorizedException');
      }

      // Rethrow any other auth errors
      throw e;
    }
  }

  Future<bool> createUser(
      String email, String password, String firstName, String lastName) async {
    // Temporary mock user creation
    await Future.delayed(Duration(seconds: 1));
    return true; // Always succeed for now
  }

  // Sign out
  Future<void> signOut() async {
    try {
      print('Attempting to sign out'); // Debug log
      await Amplify.Auth.signOut();
      print('Sign out successful'); // Debug log
    } catch (e) {
      print('Error signing out: $e');
      throw e;
    }
  }

  Future<bool> signUp(
      String email, String password, String firstName, String lastName) async {
    try {
      print('Starting signup process for email: $email'); // Debug log

      final userAttributes = <CognitoUserAttributeKey, String>{
        CognitoUserAttributeKey.email: email,
        CognitoUserAttributeKey.givenName: firstName,
        CognitoUserAttributeKey.familyName: lastName,
      };

      final result = await Amplify.Auth.signUp(
        username: email,
        password: password,
        options: CognitoSignUpOptions(
          userAttributes: userAttributes,
        ),
      );

      print('Signup result: ${result.isSignUpComplete}'); // Debug log
      print('Next step: ${result.nextStep}'); // Debug log

      // Store password for later use
      _tempPassword = password;

      // If signup is successful, navigate to verification regardless of isSignUpComplete
      return true; // Changed to always return true if we reach this point
    } catch (e) {
      print('Detailed signup error: $e'); // Debug log
      return false;
    }
  }

  // Add new method for verification
  Future<bool> verifyEmail(String email, String code) async {
    try {
      print('Starting verification for email: $email with code: $code');

      final result = await Amplify.Auth.confirmSignUp(
        username: email,
        confirmationCode: code,
      );

      print('Verification result: ${result.isSignUpComplete}');

      if (result.isSignUpComplete) {
        print('Verification successful, signing out first');

        print('Attempting sign in');
        final password = _tempPassword;
        if (password == null) {
          print('Error: No stored password found');
          return false;
        }

        final signInResult = await Amplify.Auth.signIn(
          username: email,
          password: password,
        );

        print('Sign in result: ${signInResult.isSignedIn}');
        return signInResult.isSignedIn;
      }
      return false;
    } catch (e) {
      print('Detailed verification error: $e');
      return false;
    }
  }

  // Add this to store password temporarily
  static String? _tempPassword;
}
