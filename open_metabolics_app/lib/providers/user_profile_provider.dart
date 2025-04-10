import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../auth/auth_service.dart';

class UserProfileProvider with ChangeNotifier {
  UserProfile? _userProfile;
  bool _isLoading = false;
  String? _errorMessage;

  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasProfile => _userProfile != null;

  Future<void> fetchUserProfile() async {
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final userEmail = await AuthService().getCurrentUserEmail();
      if (userEmail == null) {
        throw Exception('User not logged in');
      }

      final response = await http.post(
        Uri.parse(
            'https://b8e3dexk76.execute-api.us-east-1.amazonaws.com/dev/get-user-profile'),
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
        Uri.parse(
            'https://b8e3dexk76.execute-api.us-east-1.amazonaws.com/dev/manage-user-profile'),
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
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      notifyListeners();
    }
  }
}
