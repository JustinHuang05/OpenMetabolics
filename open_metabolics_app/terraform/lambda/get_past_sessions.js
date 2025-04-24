const { DynamoDBClient, QueryCommand } = require("@aws-sdk/client-dynamodb");
const { unmarshall } = require("@aws-sdk/util-dynamodb");

const dynamodb = new DynamoDBClient();

exports.handler = async (event) => {
    try {
        const { user_email } = JSON.parse(event.body);

        if (!user_email) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: 'User email is required' })
            };
        }

        // Query the energy expenditure results table for all sessions of this user
        const queryParams = {
            TableName: process.env.RESULTS_TABLE,
            IndexName: 'UserEmailIndex',
            KeyConditionExpression: 'UserEmail = :email',
            ExpressionAttributeValues: {
                ':email': { S: user_email }
            },
            ScanIndexForward: false // Sort by timestamp in descending order
        };

        console.log('Querying DynamoDB with params:', JSON.stringify(queryParams));

        const command = new QueryCommand(queryParams);
        const result = await dynamodb.send(command);
        console.log('DynamoDB query result:', JSON.stringify(result));

        if (!result.Items || result.Items.length === 0) {
            return {
                statusCode: 200,
                body: JSON.stringify({ sessions: [] })
            };
        }

        // Group results by session ID
        const sessions = {};
        result.Items.forEach(item => {
            const unmarshalledItem = unmarshall(item);
            const sessionId = unmarshalledItem.SessionId;
            if (!sessions[sessionId]) {
                sessions[sessionId] = {
                    sessionId,
                    timestamp: unmarshalledItem.Timestamp,
                    basalMetabolicRate: unmarshalledItem.BasalMetabolicRate, // Include BMR in session details
                    results: []
                };
            }
            sessions[sessionId].results.push({
                timestamp: unmarshalledItem.Timestamp,
                energyExpenditure: unmarshalledItem.EnergyExpenditure,
                windowIndex: unmarshalledItem.WindowIndex,
                gaitCycleIndex: unmarshalledItem.GaitCycleIndex
            });
        });

        // Sort results within each session from least recent to most recent
        Object.values(sessions).forEach(session => {
            session.results.sort((a, b) => 
                new Date(a.timestamp) - new Date(b.timestamp)
            );
        });

        // Convert sessions object to array and sort by timestamp (most recent first)
        const sessionsArray = Object.values(sessions).sort((a, b) => 
            new Date(b.timestamp) - new Date(a.timestamp)
        );

        console.log('Processed sessions:', JSON.stringify(sessionsArray));

        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({
                sessions: sessionsArray
            })
        };
    } catch (error) {
        console.error('Error fetching past sessions:', error);
        return {
            statusCode: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({ 
                error: 'Failed to fetch past sessions',
                details: error.message 
            })
        };
    }
};