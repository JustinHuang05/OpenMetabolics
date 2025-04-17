class ApiConfig {
  // Base URL for the API Gateway
  static const String baseUrl =
      'https://vv3v6jilz9.execute-api.us-east-1.amazonaws.com/dev';

  // User Profile Endpoints
  static const String getUserProfile = '$baseUrl/get-user-profile';
  static const String manageUserProfile = '$baseUrl/manage-user-profile';

  // Sensor Data Endpoints
  static const String saveRawSensorData = '$baseUrl/save-raw-sensor-data';
  static const String processEnergyExpenditure =
      '$baseUrl/process-energy-expenditure';

  // Fargate service URL
  static const String energyExpenditureServiceUrl =
      'http://open-metabolics-ee-lb-1961894695.us-east-1.elb.amazonaws.com/process';
}
