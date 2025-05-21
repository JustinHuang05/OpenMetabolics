const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);
const RESULTS_TABLE = process.env.RESULTS_TABLE;

exports.handler = async (event) => {
  let user_email;
  try {
    user_email = JSON.parse(event.body).user_email;
    console.log('Processing request for user:', user_email);
  } catch (e) {
    console.error('Error parsing request:', e);
    return { 
      statusCode: 400, 
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({ error: 'Missing or invalid user_email' })
    };
  }

  let items = [];
  let lastKey = undefined;
  let queryCount = 0;
  
  try {
    do {
      queryCount++;
      console.log(`Executing query ${queryCount} for user ${user_email}`);
      
      const params = {
        TableName: RESULTS_TABLE,
        IndexName: 'UserEmailIndex',
        KeyConditionExpression: 'UserEmail = :email',
        ExpressionAttributeValues: { ':email': user_email },
        ProjectionExpression: 'SessionId, #ts',
        ExpressionAttributeNames: {
          '#ts': 'Timestamp'
        },
        ExclusiveStartKey: lastKey,
      };
      
      console.log('Query params:', JSON.stringify(params));
      const command = new QueryCommand(params);
      const result = await docClient.send(command);
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

    // Return as a list of { sessionId, timestamp } with lowercase field names
    const response = {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify(
        items.map(item => ({
          sessionId: item.SessionId,
          timestamp: item.Timestamp,
        }))
      ),
    };
    
    console.log(`Returning ${items.length} session summaries`);
    console.log('First few summaries in response:', JSON.stringify(items.slice(0, 3).map(item => ({
      sessionId: item.SessionId,
      timestamp: item.Timestamp,
    }))));
    return response;
  } catch (error) {
    console.error('Error querying DynamoDB:', error);
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({ 
        error: 'Internal Server Error',
        details: error.message
      })
    };
  }
};
