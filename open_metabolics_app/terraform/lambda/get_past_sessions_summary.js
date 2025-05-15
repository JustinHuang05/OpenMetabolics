const { DynamoDBClient, QueryCommand } = require("@aws-sdk/client-dynamodb");
const { unmarshall } = require("@aws-sdk/util-dynamodb");

const dynamodb = new DynamoDBClient();

exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);
        const { user_email } = body;
        const page = parseInt(body.page) || 1;
        const limit = parseInt(body.limit) || 10;

        if (!user_email) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: 'User email is required' })
            };
        }

        let allItems = [];
        let lastEvaluatedKey = undefined;
        const baseQueryParams = {
            TableName: process.env.RESULTS_TABLE,
            IndexName: 'UserEmailIndex',
            KeyConditionExpression: 'UserEmail = :email',
            ExpressionAttributeValues: {
                ':email': { S: user_email }
            },
            ScanIndexForward: false // Sort by timestamp in descending order
        };

        console.log('Fetching all measurements for user:', user_email, 'Page:', page, 'Limit:', limit);

        do {
            const queryParams = { ...baseQueryParams };
            if (lastEvaluatedKey) {
                queryParams.ExclusiveStartKey = lastEvaluatedKey;
            }

            // console.log('Querying DynamoDB with params:', JSON.stringify(queryParams)); // Verbose
            const command = new QueryCommand(queryParams);
            const result = await dynamodb.send(command);
            // console.log('DynamoDB query batch result items count:', result.Items ? result.Items.length : 0); // Verbose

            if (result.Items) {
                allItems.push(...result.Items);
            }
            lastEvaluatedKey = result.LastEvaluatedKey;

        } while (lastEvaluatedKey);

        console.log(`Fetched a total of ${allItems.length} measurement items for user ${user_email}.`);

        if (allItems.length === 0) {
            return {
                statusCode: 200,
                headers: {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                body: JSON.stringify({ 
                    sessions: [],
                    currentPage: page,
                    hasNextPage: false,
                    totalSessions: 0
                })
            };
        }

        // Group results by session ID and count measurements
        const sessionSummaries = {};
        allItems.forEach(item => {
            const unmarshalledItem = unmarshall(item);
            const sessionId = unmarshalledItem.SessionId;
            if (!sessionSummaries[sessionId]) {
                sessionSummaries[sessionId] = {
                    sessionId,
                    // Use the timestamp of the first encountered measurement for that session
                    // Since query is ScanIndexForward: false, this will be the latest timestamp for the session
                    timestamp: unmarshalledItem.Timestamp, 
                    measurementCount: 0 // Initialize, will be incremented below
                };
            }
            // Increment count for every measurement item belonging to this session
            sessionSummaries[sessionId].measurementCount++;
        });
        
        // Convert sessions object to array and sort by timestamp (most recent first)
        const summariesArray = Object.values(sessionSummaries).sort((a, b) => 
            new Date(b.timestamp) - new Date(a.timestamp)
        );

        console.log(`Processed ${summariesArray.length} total session summaries for user ${user_email}.`);

        const startIndex = (page - 1) * limit;
        const endIndex = page * limit;
        const paginatedSummaries = summariesArray.slice(startIndex, endIndex);
        const totalSessions = summariesArray.length;
        const hasNextPage = endIndex < totalSessions;

        console.log(`Returning page ${page} for user ${user_email} with ${paginatedSummaries.length} sessions. HasNextPage: ${hasNextPage}. Total sessions: ${totalSessions}`);

        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({
                sessions: paginatedSummaries,
                currentPage: page,
                hasNextPage: hasNextPage,
                totalSessions: totalSessions // Useful for client-side display if needed
            })
        };
    } catch (error) {
        console.error('Error fetching past session summaries:', error);
        return {
            statusCode: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({ 
                error: 'Failed to fetch past session summaries',
                details: error.message 
            })
        };
    }
}; 