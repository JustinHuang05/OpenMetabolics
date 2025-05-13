import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show SocketException;
import '../auth/auth_service.dart';
import '../models/user_profile.dart';
import '../config/api_config.dart';
import 'package:amplify_flutter/amplify_flutter.dart' as amplify;

class UserProfilePage extends StatefulWidget {
  final Function(UserProfile) onProfileUpdated;

  const UserProfilePage({
    Key? key,
    required this.onProfileUpdated,
  }) : super(key: key);

  @override
  _UserProfilePageState createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  // Form controllers
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _ageController = TextEditingController();
  String _selectedGender = 'male';

  bool _isLoading = false;
  bool _isInitialLoading = true;
  String? _errorMessage;
  bool _isNetworkError = false;
  UserProfile? _userProfile;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    setState(() {
      _isInitialLoading = true;
      _errorMessage = null;
      _isNetworkError = false;
    });

    try {
      // First try to get user email - this will throw SocketException if no network
      final userEmail = await _authService.getCurrentUserEmail();

      // If we get here, we have network connection, now check if user is logged in
      if (userEmail == null) {
        // Check if user is actually signed in
        final isSignedIn = await _authService.isSignedIn();
        if (!isSignedIn) {
          throw Exception('User not logged in');
        }
        // If we get here, user is signed in but we couldn't get their email
        throw Exception('Unable to get user information');
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
        setState(() {
          _userProfile = UserProfile.fromJson(data);
          // Initialize form fields with profile data
          _weightController.text = _userProfile!.weight.toString();
          _heightController.text = _userProfile!.height.toString();
          _ageController.text = _userProfile!.age.toString();
          _selectedGender = _userProfile!.gender;
        });
      } else if (response.statusCode == 404) {
        // Profile not found, this is okay
        setState(() {
          _userProfile = null;
        });
      } else {
        throw Exception('Failed to fetch profile: ${response.body}');
      }
    } on SocketException catch (e) {
      setState(() {
        _isNetworkError = true;
        _errorMessage = 'No internet connection';
      });
    } on amplify.NetworkException catch (e) {
      setState(() {
        _isNetworkError = true;
        _errorMessage = 'No internet connection';
      });
    } catch (e) {
      setState(() {
        if (e.toString().contains('User not logged in')) {
          _errorMessage = 'Please log in to view your profile';
        } else if (e.toString().contains('Unable to get user information')) {
          _errorMessage = 'Unable to get user information. Please try again.';
        } else {
          _errorMessage = e.toString();
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isNetworkError = false;
    });

    try {
      // First try to get user email - this will throw SocketException if no network
      final userEmail = await _authService.getCurrentUserEmail();

      // If we get here, we have network connection, now check if user is logged in
      if (userEmail == null) {
        throw Exception('User not logged in');
      }

      // Parse form values with proper error handling
      final weight = double.tryParse(_weightController.text);
      final height = double.tryParse(_heightController.text);
      final age = int.tryParse(_ageController.text);

      if (weight == null || height == null || age == null) {
        throw Exception('Invalid form values');
      }

      final response = await http.post(
        Uri.parse(ApiConfig.manageUserProfile),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
          'weight': weight,
          'height': height,
          'age': age,
          'gender': _selectedGender,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final updatedProfile = UserProfile.fromJson(data);
        widget.onProfileUpdated(updatedProfile);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile saved successfully!')),
          );
        }
      } else {
        throw Exception('Failed to save profile: ${response.body}');
      }
    } on SocketException catch (e) {
      setState(() {
        _isNetworkError = true;
        _errorMessage = 'No internet connection';
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color lightPurple = Color.fromRGBO(216, 194, 251, 1);
    final Color textGray = Color.fromRGBO(66, 66, 66, 1);

    if (_isInitialLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isNetworkError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.grey[600],
                  size: 64,
                ),
                SizedBox(height: 16),
                Text(
                  'No Internet Connection',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Please check your connection and try again',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _fetchUserProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lightPurple,
                    foregroundColor: textGray,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Biometric information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),

              // Weight input
              TextFormField(
                controller: _weightController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Weight (kg)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.monitor_weight),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your weight';
                  }
                  final weight = double.tryParse(value);
                  if (weight == null || weight <= 0 || weight > 500) {
                    return 'Please enter a valid weight (0-500 kg)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Height input
              TextFormField(
                controller: _heightController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Height (m)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.height),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your height';
                  }
                  final height = double.tryParse(value);
                  if (height == null || height <= 0 || height > 3) {
                    return 'Please enter a valid height (0.00-3.00 m)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Age input
              TextFormField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Age',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.cake),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your age';
                  }
                  final age = int.tryParse(value);
                  if (age == null || age <= 0 || age > 120) {
                    return 'Please enter a valid age (0-120)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Gender selection
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gender',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textGray,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildGenderOption(
                              'Male', 'male', lightPurple, textGray),
                          _buildGenderOption(
                              'Female', 'female', lightPurple, textGray),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Error message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Save button
              ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: lightPurple,
                  foregroundColor: textGray,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? CircularProgressIndicator(color: textGray)
                    : Text(
                        'Save Profile',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderOption(
      String label, String value, Color lightPurple, Color textGray) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedGender = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _selectedGender == value ? lightPurple : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: _selectedGender == value ? textGray : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
