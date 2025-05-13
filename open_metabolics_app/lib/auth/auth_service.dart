// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'dart:io' show SocketException;

class AuthService {
  // Remove Firebase-related code
  // final FirebaseAuth _auth = FirebaseAuth.instance;
  String loginErrorCode = '';
  String signupErrorCode = '';

  // Simplified auth methods for now
  Future<bool> signIn(String email, String password) async {
    try {
      print('Attempting to sign in user: ${email.toLowerCase()}');

      final result = await Amplify.Auth.signIn(
        username: email.toLowerCase(),
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
      print('Starting signup process for email: ${email.toLowerCase()}');

      final userAttributes = <CognitoUserAttributeKey, String>{
        CognitoUserAttributeKey.email: email.toLowerCase(),
        CognitoUserAttributeKey.givenName: firstName,
        CognitoUserAttributeKey.familyName: lastName,
      };

      final result = await Amplify.Auth.signUp(
        username: email.toLowerCase(),
        password: password,
        options: CognitoSignUpOptions(
          userAttributes: userAttributes,
        ),
      );

      print('Signup result: ${result.isSignUpComplete}');
      print('Next step: ${result.nextStep}');
      print('SignUpStep: ${result.nextStep.signUpStep}');

      // Store password for later use
      _tempPassword = password;

      // Check for AuthSignUpStep.confirmSignUp instead of string comparison
      if (result.nextStep.signUpStep == AuthSignUpStep.confirmSignUp) {
        print('Signup successful, verification code sent');
        return true;
      } else {
        print(
            'Signup failed, unexpected next step: ${result.nextStep.signUpStep}');
        return false;
      }
    } catch (e) {
      print('Detailed signup error: $e');
      return false;
    }
  }

  // Add new method for verification
  Future<bool> verifyEmail(String email, String code) async {
    try {
      print(
          'Starting verification for email: ${email.toLowerCase()} with code: $code');

      //just for testing basically:
      await Amplify.Auth.signOut();

      final result = await Amplify.Auth.confirmSignUp(
        username: email.toLowerCase(),
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
          username: email.toLowerCase(),
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

  // Get current user's email
  Future<String?> getCurrentUserEmail() async {
    try {
      final currentUser = await Amplify.Auth.getCurrentUser();
      final attributes = await Amplify.Auth.fetchUserAttributes();
      final emailAttribute = attributes.firstWhere(
        (element) => element.userAttributeKey == CognitoUserAttributeKey.email,
      );
      return emailAttribute.value;
    } on SocketException catch (e) {
      print('Network error getting user email: $e');
      rethrow; // Rethrow network errors
    } on NetworkException catch (e) {
      print('Amplify network error getting user email: $e');
      rethrow; // Rethrow Amplify network errors
    } catch (e) {
      print('Error getting user email: $e');
      return null; // Return null only for non-network errors
    }
  }

  // Check if user is currently signed in
  Future<bool> isSignedIn() async {
    try {
      final currentUser = await Amplify.Auth.getCurrentUser();
      return currentUser != null;
    } catch (e) {
      print('Error checking sign in status: $e');
      return false;
    }
  }
}
