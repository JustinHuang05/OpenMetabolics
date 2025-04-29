import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  // Base URL for the API Gateway
  static String get baseUrl => dotenv.env['API_GATEWAY_BASE_URL'] ?? '';

  // User Profile Endpoints
  static String get getUserProfile => '$baseUrl/get-user-profile';
  static String get manageUserProfile => '$baseUrl/manage-user-profile';

  // Sensor Data Endpoints
  static String get saveRawSensorData => '$baseUrl/save-raw-sensor-data';
  static String get processEnergyExpenditure =>
      '$baseUrl/process-energy-expenditure';

  // Fargate service URL
  static String get energyExpenditureServiceUrl =>
      dotenv.env['FARGATE_SERVICE_URL'] ?? '';

  // Session Endpoints
  static String get getPastSessionsSummary =>
      '$baseUrl/get-past-sessions-summary';
  static String get getSessionDetails => '$baseUrl/get-session-details';
  static String get getPastSessions =>
      '$baseUrl/get-past-sessions'; // Legacy endpoint
}
