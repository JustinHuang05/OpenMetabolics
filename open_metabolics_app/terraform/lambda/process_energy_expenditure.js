const { DynamoDBClient, QueryCommand, PutItemCommand } = require("@aws-sdk/client-dynamodb");

const client = new DynamoDBClient({ region: "us-east-1" });

exports.handler = async (event) => {
    try {
        console.log("Received event:", event);

        // Handle both API Gateway events (HTTP) and direct Lambda test events
        let body = event.body ? event.body : event; 

        if (typeof body === "string") {
            try {
                body = JSON.parse(body);
            } catch (error) {
                console.error("JSON Parsing Error:", error);
                return {
                    statusCode: 400,
                    body: JSON.stringify({ error: "Invalid JSON format" }),
                };
            }
        }

        if (!body.session_id || !body.user_email) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: "Missing required fields (session_id or user_email)" }),
            };
        }

        // Query all sensor data for this session
        const queryParams = {
            TableName: process.env.RAW_SENSOR_TABLE,
            KeyConditionExpression: "SessionId = :sessionId",
            ExpressionAttributeValues: {
                ":sessionId": { S: body.session_id }
            }
        };

        const queryResult = await client.send(new QueryCommand(queryParams));
        const sensorData = queryResult.Items;

        if (!sensorData || sensorData.length === 0) {
            return {
                statusCode: 404,
                body: JSON.stringify({ error: "No sensor data found for this session" }),
            };
        }

        // Process the data in windows (4 seconds at 50Hz = 200 samples)
        const windowSize = 200;
        const results = [];

        for (let i = 0; i < sensorData.length; i += windowSize) {
            const window = sensorData.slice(i, i + windowSize);
            
            // Extract gyroscope and accelerometer data
            const gyroData = window.map(item => ({
                x: parseFloat(item.Gyroscope_X.N),
                y: parseFloat(item.Gyroscope_Y.N),
                z: parseFloat(item.Gyroscope_Z.N)
            }));

            const accData = window.map(item => ({
                x: parseFloat(item.Accelerometer_X.N),
                y: parseFloat(item.Accelerometer_Y.N),
                z: parseFloat(item.Accelerometer_Z.N)
            }));

            // Calculate energy expenditure for this window
            const ee = calculateEnergyExpenditure(gyroData, accData);

            // Store the result
            const resultItem = {
                TableName: process.env.RESULTS_TABLE,
                Item: {
                    SessionId: { S: body.session_id },
                    Timestamp: { S: window[0].Timestamp.S },
                    UserEmail: { S: body.user_email },
                    EnergyExpenditure: { N: ee.toString() }
                }
            };

            await client.send(new PutItemCommand(resultItem));
            results.push({
                timestamp: window[0].Timestamp.S,
                energyExpenditure: ee
            });
        }

        return {
            statusCode: 200,
            body: JSON.stringify({ 
                message: "Energy expenditure calculation completed",
                session_id: body.session_id,
                results: results
            }),
        };

    } catch (error) {
        console.error("Error processing energy expenditure:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message }),
        };
    }
};

function calculateEnergyExpenditure(gyroData, accData) {
    // TODO: Implement the actual energy expenditure calculation
    // This should use the same logic as in main.py
    // For now, return a placeholder value
    return 100.0;
} 