# open_metabolics_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Environment Setup

This application uses environment variables to manage sensitive configuration. Follow these steps to set up your development environment:

1. Copy the `.env.example` file to create a new `.env` file:

```bash
cp .env.example .env
```

2. Fill in the environment variables in `.env` with your AWS configuration values:

- `AWS_COGNITO_POOL_ID`: Your Cognito User Pool ID
- `AWS_COGNITO_CLIENT_ID`: Your Cognito App Client ID
- `AWS_COGNITO_REGION`: Your AWS region (e.g., us-east-1)
- `API_GATEWAY_BASE_URL`: Your API Gateway base URL
- `FARGATE_SERVICE_URL`: Your Fargate service URL

3. **Important**: After making any changes to the `.env` file, you need to:
   - Stop the app if it's running
   - Run `flutter clean`
   - Run `flutter pub get`
   - Restart the app

This is necessary because the `.env` file is bundled with the app's assets.

**Security Note**: Never commit the `.env` file to version control. It contains sensitive information and is already added to `.gitignore`.

## Development Setup

1. Install dependencies:

```bash
flutter pub get
```

2. Run the app:

```bash
flutter run
```

The app will automatically load the environment variables from your `.env` file during startup.
