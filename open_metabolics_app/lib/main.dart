import 'package:flutter/material.dart';
import 'pages/home_page.dart'; // Import the home page with sensor tracking

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SensorScreen(), // Set SensorScreen as the home widget
    );
  }
}
