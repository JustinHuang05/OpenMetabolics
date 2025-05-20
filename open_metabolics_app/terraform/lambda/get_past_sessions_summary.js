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

        // Get unique sessions with their timestamps and count measurements
        const uniqueSessions = new Map();
        let lastEvaluatedKey = undefined;
        let hasMoreItems = true;

        // Keep querying until we have enough unique sessions or no more items
        while (hasMoreItems) {
            const sessionQueryParams = {
                TableName: process.env.RESULTS_TABLE,
                IndexName: 'UserEmailIndex',
                KeyConditionExpression: 'UserEmail = :email',
                ExpressionAttributeValues: {
                    ':email': { S: user_email }
                },
                ProjectionExpression: 'SessionId, #ts',
                ExpressionAttributeNames: {
                    '#ts': 'Timestamp'
                },
                ScanIndexForward: false, // Sort by timestamp in descending order
                Limit: 1000 // Get a reasonable batch size
            };

            if (lastEvaluatedKey) {
                sessionQueryParams.ExclusiveStartKey = lastEvaluatedKey;
            }

            const sessionCommand = new QueryCommand(sessionQueryParams);
            const sessionResult = await dynamodb.send(sessionCommand);

            if (!sessionResult.Items || sessionResult.Items.length === 0) {
                break;
            }

            // Process items and count measurements
            sessionResult.Items.forEach(item => {
                const unmarshalledItem = unmarshall(item);
                const sessionId = unmarshalledItem.SessionId;
                if (!uniqueSessions.has(sessionId)) {
                    uniqueSessions.set(sessionId, {
                        timestamp: unmarshalledItem.Timestamp,
                        count: 1
                    });
                } else {
                    const session = uniqueSessions.get(sessionId);
                    session.count++;
                    uniqueSessions.set(sessionId, session);
                }
            });

            // Check if we have more items to fetch
            lastEvaluatedKey = sessionResult.LastEvaluatedKey;
            hasMoreItems = !!lastEvaluatedKey;

            // If we have enough unique sessions for the current page, we can stop
            if (uniqueSessions.size >= page * limit) {
                break;
            }
        }

        if (uniqueSessions.size === 0) {
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

        // Convert to array and sort by timestamp
        const sortedSessions = Array.from(uniqueSessions.entries())
            .map(([sessionId, data]) => ({
                sessionId,
                timestamp: data.timestamp,
                measurementCount: data.count
            }))
            .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

        // Calculate pagination
        const totalSessions = sortedSessions.length;
        const startIndex = (page - 1) * limit;
        const endIndex = Math.min(startIndex + limit, totalSessions);
        const hasNextPage = endIndex < totalSessions;

        // Get the sessions for the current page
        const pageSessions = sortedSessions.slice(startIndex, endIndex);

        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({
                sessions: pageSessions,
                currentPage: page,
                hasNextPage: hasNextPage,
                totalSessions: totalSessions
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