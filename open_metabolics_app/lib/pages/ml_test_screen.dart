// // pages/ml_test_screen.dart

// import 'package:flutter/material.dart';
// import 'package:tflite/tflite.dart';

// class MLTestScreen extends StatefulWidget {
//   @override
//   _MLTestScreenState createState() => _MLTestScreenState();
// }

// class _MLTestScreenState extends State<MLTestScreen> {
//   String _modelOutput = "Model output will appear here";

//   @override
//   void initState() {
//     super.initState();
//     loadModel();
//   }

//   // Function to load the TFLite model
//   Future<void> loadModel() async {
//     String? res = await Tflite.loadModel(
//       model:
//           "assets/ml_models/lin_reg_model/pocket_motion_lr_model.tflite", // Path to your TFLite model in assets
//     );
//     print("Model loaded: $res");
//   }

//   // Function to run inference using the loaded TFLite model
//   Future<void> runInference() async {
//     var input = List.filled(108,
//         0.5); // Dummy input, adjust based on your model’s expected input shape

//     var output = await Tflite.runModelOnBinary(
//       binary: input,
//       numResults: 1, // Number of results to return
//       threshold: 0.5, // Confidence threshold (for classification models)
//     );

//     setState(() {
//       _modelOutput =
//           output != null ? output.toString() : "No output from model";
//     });
//   }

//   @override
//   void dispose() {
//     Tflite.close(); // Free resources when the screen is disposed
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text("ML Test Screen")),
//       body: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Text(_modelOutput, style: TextStyle(fontSize: 20)),
//             SizedBox(height: 20),
//             ElevatedButton(
//               onPressed: runInference,
//               child: Text("Run Model"),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
