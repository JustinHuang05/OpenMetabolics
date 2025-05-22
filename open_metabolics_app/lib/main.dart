import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth/auth_service.dart';
import 'auth/auth_wrapper.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'auth/amplify_config.dart';
import 'providers/user_profile_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  // Load environment variables
  await dotenv.load(fileName: ".env");

  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('session_summaries');
  await Hive.openBox('user_preferences');

  // Configure Amplify
  try {
    final auth = AmplifyAuthCognito();
    await Amplify.addPlugin(auth);
    await Amplify.configure(getAmplifyConfig());
    print('Successfully configured Amplify');
  } catch (e) {
    print('Error configuring Amplify: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProfileProvider()),
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
    ),
  );
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
