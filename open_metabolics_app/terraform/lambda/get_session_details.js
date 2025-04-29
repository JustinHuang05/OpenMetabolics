const { DynamoDBClient, QueryCommand } = require("@aws-sdk/client-dynamodb");
const { unmarshall } = require("@aws-sdk/util-dynamodb");

const dynamodb = new DynamoDBClient();

exports.handler = async (event) => {
    try {
        const { user_email, session_id } = JSON.parse(event.body);

        if (!user_email || !session_id) {
            return {
                statusCode: 400,
                body: JSON.stringify({ 
                    error: 'Both user email and session ID are required' 
                })
            };
        }

        // Query the energy expenditure results table for all measurements of this session
        const queryParams = {
            TableName: process.env.RESULTS_TABLE,
            KeyConditionExpression: 'SessionId = :sessionId',
            FilterExpression: 'UserEmail = :email',
            ExpressionAttributeValues: {
                ':sessionId': { S: session_id },
                ':email': { S: user_email }
            }
        };

        console.log('Querying DynamoDB with params:', JSON.stringify(queryParams));

        const command = new QueryCommand(queryParams);
        const result = await dynamodb.send(command);
        console.log('DynamoDB query result:', JSON.stringify(result));

        if (!result.Items || result.Items.length === 0) {
            return {
                statusCode: 404,
                body: JSON.stringify({ 
                    error: 'Session not found or unauthorized access' 
                })
            };
        }

        // Process session data
        const sessionData = {
            sessionId: session_id,
            timestamp: '',
            basalMetabolicRate: null,
            results: []
        };

        result.Items.forEach(item => {
            const unmarshalledItem = unmarshall(item);
            
            // Set session-level data from the first item
            if (!sessionData.timestamp) {
                sessionData.timestamp = unmarshalledItem.Timestamp;
                sessionData.basalMetabolicRate = unmarshalledItem.BasalMetabolicRate;
            }

            sessionData.results.push({
                timestamp: unmarshalledItem.Timestamp,
                energyExpenditure: unmarshalledItem.EnergyExpenditure,
                windowIndex: unmarshalledItem.WindowIndex,
                gaitCycleIndex: unmarshalledItem.GaitCycleIndex
            });
        });

        // Sort results by timestamp
        sessionData.results.sort((a, b) => 
            new Date(a.timestamp) - new Date(b.timestamp)
        );

        console.log('Processed session data:', JSON.stringify(sessionData));

        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({
                session: sessionData
            })
        };
    } catch (error) {
        console.error('Error fetching session details:', error);
        return {
            statusCode: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({ 
                error: 'Failed to fetch session details',
                details: error.message 
            })
        };
    }
}; 