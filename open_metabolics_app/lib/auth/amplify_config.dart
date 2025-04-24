import 'package:flutter_dotenv/flutter_dotenv.dart';

String getAmplifyConfig() {
  return '''{
    "UserAgent": "aws-amplify-cli/2.0",
    "Version": "1.0",
    "auth": {
        "plugins": {
            "awsCognitoAuthPlugin": {
                "UserAgent": "aws-amplify/cli",
                "Version": "1.0",
                "IdentityManager": {
                    "Default": {}
                },
                "CognitoUserPool": {
                    "Default": {
                        "PoolId": "${dotenv.env['AWS_COGNITO_POOL_ID']}",
                        "AppClientId": "${dotenv.env['AWS_COGNITO_CLIENT_ID']}",
                        "Region": "${dotenv.env['AWS_COGNITO_REGION']}"
                    }
                }
            }
        }
    }
}''';
}
