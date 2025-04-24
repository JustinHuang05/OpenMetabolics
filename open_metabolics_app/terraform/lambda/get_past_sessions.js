const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB();

exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);
        const userEmail = body.user_email;

        if (!userEmail) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: 'Missing user_email' })
            };
        }

        // Query the results table for all sessions by this user
        const queryParams = {
            TableName: process.env.RESULTS_TABLE,
            IndexName: 'UserEmailIndex',
            KeyConditionExpression: 'UserEmail = :email',
            ExpressionAttributeValues: {
                ':email': { S: userEmail }
            },
            ScanIndexForward: false // Sort by timestamp in descending order
        };

        const response = await dynamodb.query(queryParams).promise();
        
        if (!response.Items || response.Items.length === 0) {
            return {
                statusCode: 200,
                body: JSON.stringify({ sessions: [] })
            };
        }

        // Group results by session
        const sessions = {};
        for (const item of response.Items) {
            const sessionId = item.SessionId.S;
            if (!sessions[sessionId]) {
                sessions[sessionId] = {
                    session_id: sessionId,
                    timestamp: item.Timestamp.S,
                    results: [],
                    total_windows_processed: 0,
                    basal_metabolic_rate: parseFloat(item.BasalMetabolicRate.N),
                    gait_cycles: 0
                };
            }
            
            // Add result to session
            sessions[sessionId].results.push({
                timestamp: item.Timestamp.S,
                energyExpenditure: parseFloat(item.EnergyExpenditure.N),
                windowIndex: parseInt(item.WindowIndex.N),
                gaitCycleIndex: parseInt(item.GaitCycleIndex.N)
            });
        }

        // Process each session to calculate totals
        for (const session of Object.values(sessions)) {
            session.total_windows_processed = new Set(session.results.map(r => r.windowIndex)).size;
            session.gait_cycles = session.results.filter(r => r.energyExpenditure > session.basal_metabolic_rate).length;
        }

        return {
            statusCode: 200,
            body: JSON.stringify({
                sessions: Object.values(sessions)
            })
        };

    } catch (error) {
        console.error('Error getting past sessions:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message })
        };
    }
};