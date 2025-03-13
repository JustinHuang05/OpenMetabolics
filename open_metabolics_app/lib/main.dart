import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth/auth_service.dart';
import 'auth/auth_wrapper.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'auth/amplify_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure Amplify
  try {
    final auth = AmplifyAuthCognito();
    await Amplify.addPlugin(auth);
    await Amplify.configure(amplifyconfig);
    print('Amplify configured successfully');
  } catch (e) {
    print('Error configuring Amplify: $e');
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(
          create: (_) => AuthService(),
        ),
        // Comment out StreamProvider since it uses Firebase
        // StreamProvider(
        //   create: (context) => context.read<AuthService>().user,
        //   initialData: null,
        // ),
      ],
      child: MaterialApp(
        title: 'OpenMetabolics',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: AuthWrapper(),
      ),
    );
  }
}
