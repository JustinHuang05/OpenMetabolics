const { DynamoDBClient, PutItemCommand, GetItemCommand, QueryCommand } = require("@aws-sdk/client-dynamodb");
const { marshall, unmarshall } = require("@aws-sdk/util-dynamodb");

const client = new DynamoDBClient({ region: "us-east-1" });

exports.handler = async (event) => {
  console.log('Received event:', JSON.stringify(event, null, 2));

  try {
    const body = JSON.parse(event.body);
    const { user_email, session_id, responses, questions } = body;

    if (!user_email || !session_id || !responses || !questions) {
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
          details: "user_email, session_id, responses, and questions are required",
        }),
      };
    }

    // First, query to get the existing response for this session
    const queryParams = {
      TableName: process.env.SURVEY_TABLE,
      KeyConditionExpression: "SessionId = :sessionId",
      ExpressionAttributeValues: marshall({
        ":sessionId": session_id,
      }),
      Limit: 1,
    };

    console.log('Querying for existing response:', JSON.stringify(queryParams, null, 2));
    const { Items } = await client.send(new QueryCommand(queryParams));

    // Use the existing timestamp if found, otherwise use current time
    const timestamp = Items && Items.length > 0 ? unmarshall(Items[0]).Timestamp : new Date().toISOString();

    // Prepare the item to save
    const item = {
      SessionId: session_id,
      Timestamp: timestamp,
      UserEmail: user_email,
      Responses: responses,
      Questions: questions,
    };

    const params = {
      TableName: process.env.SURVEY_TABLE,
      Item: marshall(item),
    };

    console.log('Saving survey response with params:', JSON.stringify(params, null, 2));

    await client.send(new PutItemCommand(params));

    return {
      statusCode: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "OPTIONS,POST",
      },
      body: JSON.stringify({
        message: "Survey response saved successfully",
        sessionId: session_id,
        timestamp: timestamp,
      }),
    };
  } catch (error) {
    console.error('Error:', error);
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
        details: error.message,
      }),
    };
  }
};
