const { DynamoDBClient, QueryCommand } = require("@aws-sdk/client-dynamodb");
const { unmarshall } = require("@aws-sdk/util-dynamodb");

const dynamodb = new DynamoDBClient();
const RESULTS_TABLE = process.env.RESULTS_TABLE;
const SURVEY_TABLE = process.env.SURVEY_TABLE || "user_survey_responses";

// Optimized function to get all surveys for a user in one query
async function getUserSurveys(userEmail, maxExecutionTime = 25000) { // Leave 5 seconds buffer for Lambda timeout
  const surveySessionIds = new Set();
  let lastKey = null;
  let batchCount = 0;
  const startTime = Date.now();
  
  try {
    do {
      // Check if we're approaching timeout
      if (Date.now() - startTime > maxExecutionTime) {
        console.warn(`Approaching timeout after ${batchCount} batches. Stopping survey fetch early.`);
        break;
      }

      const params = {
        TableName: SURVEY_TABLE,
        IndexName: 'UserEmailIndex',
        KeyConditionExpression: 'UserEmail = :email',
        ExpressionAttributeValues: { ':email': { S: userEmail } },
        ProjectionExpression: 'SessionId',
        ExclusiveStartKey: lastKey,
        Limit: 1000 // Process in batches of 1000 items
      };
      
      const command = new QueryCommand(params);
      const result = await dynamodb.send(command);
      batchCount++;
      
      if (result.Items) {
        result.Items.forEach(item => {
          const sessionId = item.SessionId?.S;
          if (sessionId) {
            surveySessionIds.add(sessionId);
          }
        });
      }
      
      // Log progress for very large datasets
      if (batchCount % 10 === 0) {
        console.log(`Processed ${batchCount} survey batches, found ${surveySessionIds.size} unique surveys`);
      }
      
      lastKey = result.LastEvaluatedKey;
      
      // Safety check for memory usage (rough estimate: each sessionId ~50 bytes)
      if (surveySessionIds.size > 500000) { // Stop at 500k surveys (~25MB)
        console.warn(`Reached survey limit of 500k surveys. Stopping early for memory safety.`);
        break;
      }
      
    } while (lastKey);
    
    console.log(`Survey fetch completed: ${batchCount} batches, ${surveySessionIds.size} surveys, ${Date.now() - startTime}ms`);
  } catch (error) {
    console.error('Error fetching user surveys:', error);
    // Return partial data if we have some surveys rather than failing completely
  }
  
  return surveySessionIds;
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
    // First, get all survey session IDs for this user in one efficient query
    console.log(`Fetching all surveys for user ${user_email}`);
    const surveySessionIds = await getUserSurveys(user_email);
    console.log(`Found ${surveySessionIds.size} sessions with surveys`);

    // Then get all session data
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

    // Convert to array, sort by timestamp, and add survey status efficiently
    const sortedSessions = Array.from(sessionCounts.entries())
      .map(([sessionId, data]) => ({
        sessionId,
        timestamp: data.timestamp,
        measurementCount: data.count,
        hasSurveyResponse: surveySessionIds.has(sessionId) // O(1) lookup instead of async query
      }))
      .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

    const response = {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify(sortedSessions)
    };
    
    console.log(`Returning ${sortedSessions.length} session summaries`);
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
