const { DynamoDBClient, GetItemCommand, QueryCommand } = require("@aws-sdk/client-dynamodb");
const { marshall, unmarshall } = require("@aws-sdk/util-dynamodb");

const client = new DynamoDBClient({ region: "us-east-1" });

exports.handler = async (event) => {
  console.log('Received event:', JSON.stringify(event, null, 2));

  try {
    const body = JSON.parse(event.body);
    const { user_email, session_id } = body;

    if (!user_email || !session_id) {
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
          details: "user_email and session_id are required",
        }),
      };
    }

    // First, query to get the timestamp for this session
    const queryParams = {
      TableName: process.env.SURVEY_TABLE,
      KeyConditionExpression: "SessionId = :sessionId",
      ExpressionAttributeValues: marshall({
        ":sessionId": session_id,
      }),
      Limit: 1,
    };

    console.log('Querying for session timestamp:', JSON.stringify(queryParams, null, 2));
    const { Items } = await client.send(new QueryCommand(queryParams));

    if (!Items || Items.length === 0) {
      return {
        statusCode: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Headers": "Content-Type",
          "Access-Control-Allow-Methods": "OPTIONS,POST",
        },
        body: JSON.stringify({
          hasResponse: false,
          response: null,
        }),
      };
    }

    const timestamp = unmarshall(Items[0]).Timestamp;

    // Now get the full response using both SessionId and Timestamp
    const getParams = {
      TableName: process.env.SURVEY_TABLE,
      Key: marshall({
        SessionId: session_id,
        Timestamp: timestamp,
      }),
    };

    console.log('Getting survey response with params:', JSON.stringify(getParams, null, 2));
    const { Item } = await client.send(new GetItemCommand(getParams));
    console.log('Response:', JSON.stringify(Item, null, 2));

    const response = unmarshall(Item);
    console.log('Unmarshalled response:', JSON.stringify(response, null, 2));

    return {
      statusCode: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "OPTIONS,POST",
      },
      body: JSON.stringify({
        hasResponse: true,
        response: response,
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