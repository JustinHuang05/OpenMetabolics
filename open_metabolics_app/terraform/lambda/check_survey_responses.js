const { DynamoDBClient, QueryCommand } = require("@aws-sdk/client-dynamodb");
const { marshall, unmarshall } = require("@aws-sdk/util-dynamodb");

const client = new DynamoDBClient({ region: "us-east-1" });

exports.handler = async (event) => {
  console.log('Received event:', JSON.stringify(event, null, 2));

  try {
    if (!process.env.SURVEY_TABLE) {
      console.error('SURVEY_TABLE environment variable is not set');
      throw new Error('Lambda configuration error: SURVEY_TABLE environment variable is not set');
    }

    if (!event.body) {
      console.error('No body in event');
      throw new Error('Request body is missing');
    }

    const body = JSON.parse(event.body);
    console.log('Parsed body:', JSON.stringify(body, null, 2));
    
    const { user_email, session_ids } = body;

    if (!user_email || !session_ids || !Array.isArray(session_ids)) {
      console.error('Missing required fields:', { user_email, session_ids });
      return {
        statusCode: 400,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Headers": "Content-Type",
          "Access-Control-Allow-Methods": "OPTIONS,POST",
        },
        body: JSON.stringify({
          error: "Missing required fields",
          details: "user_email and session_ids array are required",
        }),
      };
    }

    // Create a map of session IDs to their response status
    const surveyResponses = {};
    session_ids.forEach(sessionId => {
      surveyResponses[sessionId] = false; // Default to false
    });

    // Query for each session ID
    for (const sessionId of session_ids) {
      try {
        const params = {
          TableName: process.env.SURVEY_TABLE,
          KeyConditionExpression: "SessionId = :sessionId",
          ExpressionAttributeValues: {
            ":sessionId": { S: sessionId }
          },
          ProjectionExpression: "SessionId"
        };

        console.log('Querying for session:', sessionId, 'with params:', JSON.stringify(params, null, 2));
        const response = await client.send(new QueryCommand(params));
        console.log('Query response for session:', sessionId, ':', JSON.stringify(response, null, 2));
        
        if (response && response.Items && response.Items.length > 0) {
          surveyResponses[sessionId] = true;
        }
      } catch (queryError) {
        console.error('Error querying session:', sessionId, ':', queryError);
        // Continue with other sessions even if one fails
        continue;
      }
    }

    console.log('Final survey responses:', JSON.stringify(surveyResponses, null, 2));

    return {
      statusCode: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "OPTIONS,POST",
      },
      body: JSON.stringify({
        surveyResponses: surveyResponses
      }),
    };
  } catch (error) {
    console.error('Error in handler:', error);
    console.error('Error stack:', error.stack);
    return {
      statusCode: 500,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "OPTIONS,POST",
      },
      body: JSON.stringify({
        error: "Internal server error",
        details: error.message || 'Unknown error occurred',
        stack: error.stack
      }),
    };
  }
}; 