# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep your application classes
-keep class com.example.open_metabolics_app.** { *; }

# Keep AWS Amplify and Cognito related classes
-keep class com.amazonaws.** { *; }
-keep class com.amplifyframework.** { *; }
-keep class com.amplifyframework.core.** { *; }
-keep class com.amplifyframework.auth.** { *; }
-keep class com.amplifyframework.auth.cognito.** { *; }

# Keep OkHttp and related classes
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep Retrofit and related classes
-keep class retrofit2.** { *; }
-keep interface retrofit2.** { *; }
-dontwarn retrofit2.**

# Keep Gson and related classes
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.** { *; }

# Keep your app's model classes
-keep class com.openmetabolics.app.models.** { *; }
-keep class com.openmetabolics.app.auth.** { *; }

# Keep Flutter related classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; } 