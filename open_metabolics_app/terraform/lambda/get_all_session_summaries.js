const { DynamoDBClient, QueryCommand } = require("@aws-sdk/client-dynamodb");
const { unmarshall } = require("@aws-sdk/util-dynamodb");

const dynamodb = new DynamoDBClient();
const RESULTS_TABLE = process.env.RESULTS_TABLE;
const SURVEY_TABLE = process.env.SURVEY_TABLE || "user_survey_responses";

// Helper to check if a survey exists for a session
async function checkSurveyExists(sessionId) {
  const params = {
    TableName: SURVEY_TABLE,
    KeyConditionExpression: 'SessionId = :sid',
    ExpressionAttributeValues: { ':sid': { S: sessionId } },
    Limit: 1
  };
  const command = new QueryCommand(params);
  const result = await dynamodb.send(command);
  return result.Items && result.Items.length > 0;
}

exports.handler = async (event) => {
  let user_email;
  try {
    const body = JSON.parse(event.body);
    user_email = body.user_email;
  } catch (e) {
    return {
      statusCode: 400,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({ error: 'Invalid request body' })
    };
  }

  if (!user_email) {
    return {
      statusCode: 400,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({ error: 'User email is required' })
    };
  }

  let items = [];
  let lastKey = null;
  let queryCount = 0;
  
  try {
    do {
      queryCount++;
      console.log(`Executing query ${queryCount} for user ${user_email}`);
      
      const params = {
        TableName: RESULTS_TABLE,
        IndexName: 'UserEmailIndex',
        KeyConditionExpression: 'UserEmail = :email',
        ExpressionAttributeValues: { ':email': { S: user_email } },
        ProjectionExpression: 'SessionId, #ts',
        ExpressionAttributeNames: {
          '#ts': 'Timestamp'
        },
        ExclusiveStartKey: lastKey,
        Limit: 1000 // Process in batches of 1000 items
      };
      
      console.log('Query params:', JSON.stringify(params));
      const command = new QueryCommand(params);
      const result = await dynamodb.send(command);
      console.log(`Query ${queryCount} returned ${result.Items.length} items`);
      
      if (result.Items.length > 0) {
        console.log('First few items:', JSON.stringify(result.Items.slice(0, 3)));
      }
      
      // Filter out items with null SessionId
      const validItems = result.Items.filter(item => item.SessionId != null);
      console.log(`Filtered out ${result.Items.length - validItems.length} items with null SessionId`);
      
      items = items.concat(validItems);
      lastKey = result.LastEvaluatedKey;
      
      if (lastKey) {
        console.log('More items to fetch, continuing with next query');
      }
    } while (lastKey);

    console.log(`Total valid items found: ${items.length}`);
    if (items.length > 0) {
      console.log('First few items:', JSON.stringify(items.slice(0, 3)));
    }

    // Count measurements for each session
    const sessionCounts = new Map();
    items.forEach(item => {
      const sessionId = item.SessionId.S;
      const timestamp = item.Timestamp.S;
      
      if (!sessionCounts.has(sessionId)) {
        sessionCounts.set(sessionId, {
          timestamp: timestamp,
          count: 1
        });
      } else {
        const session = sessionCounts.get(sessionId);
        // Update timestamp if this one is earlier
        if (new Date(timestamp) < new Date(session.timestamp)) {
          session.timestamp = timestamp;
        }
        session.count++;
        sessionCounts.set(sessionId, session);
      }
    });

    // Convert to array and sort by timestamp
    const sortedSessions = Array.from(sessionCounts.entries())
      .map(([sessionId, data]) => ({
        sessionId,
        timestamp: data.timestamp,
        measurementCount: data.count
      }))
      .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

    // Add hasSurveyResponse to each session
    const sessionsWithSurveyStatus = await Promise.all(
      sortedSessions.map(async (session) => {
        const hasSurvey = await checkSurveyExists(session.sessionId);
        return { ...session, hasSurveyResponse: hasSurvey };
      })
    );

    const response = {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify(sessionsWithSurveyStatus)
    };
    
    console.log(`Returning ${sessionsWithSurveyStatus.length} session summaries`);
    return response;
  } catch (error) {
    console.error('Error:', error);
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({ error: 'Internal server error' })
    };
  }
};
