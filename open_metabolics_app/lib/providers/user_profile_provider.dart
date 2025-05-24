import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:amplify_flutter/amplify_flutter.dart' show NetworkException;
import '../auth/auth_service.dart';
import '../config/api_config.dart';

class UserProfileProvider with ChangeNotifier {
  UserProfile? _userProfile;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isNetworkError = false;

  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasProfile => _userProfile != null;
  bool get isNetworkError => _isNetworkError;

  Future<void> fetchUserProfile() async {
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    _isNetworkError = false;
    notifyListeners();

    try {
      final userEmail = await AuthService().getCurrentUserEmail();
      if (userEmail == null) {
        throw Exception('User not logged in');
      }

      final response = await http.post(
        Uri.parse(ApiConfig.getUserProfile),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null) {
          _userProfile = UserProfile.fromJson(data);
        } else {
          _userProfile = null;
        }
      } else if (response.statusCode == 404) {
        _userProfile = null;
      } else {
        throw Exception('Failed to fetch profile: ${response.body}');
      }
    } on SocketException catch (e) {
      _isNetworkError = true;
      _errorMessage = 'No internet connection';
      _userProfile = null;
    } on NetworkException catch (e) {
      _isNetworkError = true;
      _errorMessage = 'No internet connection';
      _userProfile = null;
    } catch (e) {
      _errorMessage = e.toString();
      _userProfile = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateProfile(UserProfile profile) async {
    if (profile == null) {
      _errorMessage = 'Profile cannot be null';
      notifyListeners();
      return;
    }

    try {
      final userEmail = await AuthService().getCurrentUserEmail();
      if (userEmail == null) {
        throw Exception('User not logged in');
      }

      final response = await http.post(
        Uri.parse(ApiConfig.manageUserProfile),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
          'weight': profile.weight,
          'height': profile.height,
          'age': profile.age,
          'gender': profile.gender,
        }),
      );

      if (response.statusCode == 200) {
        _userProfile = profile;
        _errorMessage = null;
      } else {
        throw Exception('Failed to update profile: ${response.body}');
      }
    } on SocketException catch (e) {
      _isNetworkError = true;
      _errorMessage = 'No internet connection';
    } on NetworkException catch (e) {
      _isNetworkError = true;
      _errorMessage = 'No internet connection';
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      notifyListeners();
    }
  }
}
