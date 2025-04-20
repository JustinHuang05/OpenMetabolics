const { DynamoDBClient, QueryCommand, PutItemCommand } = require("@aws-sdk/client-dynamodb");
const axios = require('axios');

const client = new DynamoDBClient({ region: "us-east-1" });

exports.handler = async (event) => {
    try {
        console.log("Received event:", JSON.stringify(event, null, 2));

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
                body: JSON.stringify({ error: "Missing required fields: session_id and user_email" }),
            };
        }

        // Query raw sensor data for this session
        const queryParams = {
            TableName: process.env.RAW_SENSOR_DATA_TABLE,
            KeyConditionExpression: "SessionId = :sessionId",
            ExpressionAttributeValues: {
                ":sessionId": { S: body.session_id }
            }
        };

        console.log("Querying raw sensor data with params:", JSON.stringify(queryParams, null, 2));
        const queryResult = await client.send(new QueryCommand(queryParams));
        console.log("Query result:", JSON.stringify(queryResult, null, 2));

        if (!queryResult.Items || queryResult.Items.length === 0) {
            return {
                statusCode: 404,
                body: JSON.stringify({ error: "No sensor data found for this session" }),
            };
        }

        // Process data in windows
        const windowSize = 200; // 4 seconds at 50Hz
        const allSensorData = queryResult.Items;
        const results = [];

        for (let i = 0; i < allSensorData.length; i += windowSize) {
            const window = allSensorData.slice(i, i + windowSize);
            
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

            const windowTime = window.map(item => parseFloat(item.Timestamp.S));

            // Call Fargate service to calculate energy expenditure
            const fargateResponse = await axios.post(process.env.FARGATE_SERVICE_URL, {
                gyro_data: gyroData,
                acc_data: accData,
                window_time: windowTime,
                user_email: body.user_email
            });

            const eeValues = fargateResponse.data.results.map(r => r.energyExpenditure);

            // Store each result
            for (let j = 0; j < eeValues.length; j++) {
                const windowStartTime = new Date(window[0].Timestamp.S);
                const windowEndTime = new Date(window[window.length - 1].Timestamp.S);
                const timePerGaitCycle = (windowEndTime - windowStartTime) / eeValues.length;
                const gaitCycleTimestamp = new Date(windowStartTime.getTime() + (j * timePerGaitCycle));

                const resultItem = {
                    TableName: process.env.RESULTS_TABLE,
                    Item: {
                        SessionId: { S: body.session_id },
                        Timestamp: { S: gaitCycleTimestamp.toISOString() },
                        UserEmail: { S: body.user_email },
                        EnergyExpenditure: { N: eeValues[j].toString() },
                        WindowIndex: { N: (i / windowSize).toString() },
                        GaitCycleIndex: { N: j.toString() }
                    }
                };

                await client.send(new PutItemCommand(resultItem));
                results.push({
                    timestamp: gaitCycleTimestamp.toISOString(),
                    energyExpenditure: eeValues[j]
                });
            }
        }

        return {
            statusCode: 200,
            body: JSON.stringify({ results }),
        };

    } catch (error) {
        console.error("Error processing energy expenditure:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message }),
        };
    }
}; 