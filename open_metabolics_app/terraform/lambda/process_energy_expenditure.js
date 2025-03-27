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

        // Initialize variables for pagination
        let lastEvaluatedKey = undefined;
        let allSensorData = [];
        let totalProcessed = 0;

        // Query all sensor data for this session with pagination
        do {
            const queryParams = {
                TableName: process.env.RAW_SENSOR_TABLE,
                KeyConditionExpression: "SessionId = :sessionId",
                ExpressionAttributeValues: {
                    ":sessionId": { S: body.session_id }
                },
                Limit: 1000, // Maximum items per query
                ExclusiveStartKey: lastEvaluatedKey
            };

            console.log(`Querying data with lastEvaluatedKey: ${JSON.stringify(lastEvaluatedKey)}`);
            const queryResult = await client.send(new QueryCommand(queryParams));
            
            if (queryResult.Items) {
                allSensorData = allSensorData.concat(queryResult.Items);
                totalProcessed += queryResult.Items.length;
                console.log(`Processed ${totalProcessed} items so far`);
            }

            lastEvaluatedKey = queryResult.LastEvaluatedKey;
        } while (lastEvaluatedKey);

        if (!allSensorData || allSensorData.length === 0) {
            return {
                statusCode: 404,
                body: JSON.stringify({ error: "No sensor data found for this session" }),
            };
        }

        console.log(`Total items to process: ${allSensorData.length}`);

        // Process the data in windows (4 seconds at 50Hz = 200 samples)
        const windowSize = 200;
        const results = [];

        // Process each window
        for (let i = 0; i < allSensorData.length; i += windowSize) {
            const window = allSensorData.slice(i, i + windowSize);
            console.log(`\nProcessing window ${i / windowSize + 1}:`);
            console.log(`Window size: ${window.length}`);
            console.log(`Window start time: ${window[0].Timestamp.S}`);
            console.log(`Window end time: ${window[window.length - 1].Timestamp.S}`);

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

            console.log(`Window ${i / windowSize + 1} data points:`, {
                gyroDataPoints: gyroData.length,
                accDataPoints: accData.length
            });

            // Calculate energy expenditure for this window
            const eeValues = calculateEnergyExpenditure(gyroData, accData);
            console.log(`Window ${i / windowSize + 1} EE values:`, eeValues);

            // Store each result (eeValues is now an array of values, one for each gait cycle)
            for (let j = 0; j < eeValues.length; j++) {

                // Calculate timestamp for this gait cycle
                // THIS IS HARDCODED FOR TESTING AND FINDS 
                // EVEN TIME INTERVALS FOR THE AMOUNT OF EE VALUES FOR THE WINDOW.
                // WILL CHANGE FOR MAIN>PY IMPLEMENTATION
                const windowStartTime = new Date(window[0].Timestamp.S);
                const windowEndTime = new Date(window[window.length - 1].Timestamp.S);
                const timePerGaitCycle = (windowEndTime - windowStartTime) / eeValues.length;
                const gaitCycleTimestamp = new Date(windowStartTime.getTime() + (j * timePerGaitCycle));

                console.log(`Window ${i / windowSize + 1}, Gait Cycle ${j + 1}:`, {
                    windowStart: windowStartTime.toISOString(),
                    windowEnd: windowEndTime.toISOString(),
                    timePerCycle: timePerGaitCycle,
                    timestamp: gaitCycleTimestamp.toISOString(),
                    eeValue: eeValues[j]
                });

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
                    energyExpenditure: eeValues[j],
                    windowIndex: i / windowSize,
                    gaitCycleIndex: j
                });
            }
        }

        console.log('\nFinal Results Summary:');
        console.log(`Total windows processed: ${allSensorData.length / windowSize}`);
        console.log(`Total results: ${results.length}`);
        console.log('Results:', JSON.stringify(results, null, 2));

        return {
            statusCode: 200,
            body: JSON.stringify({ 
                message: "Energy expenditure calculation completed",
                session_id: body.session_id,
                total_windows_processed: results.length,
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
    // For now, return placeholder values for 3 gait cycles per window
    console.log(`calculateEnergyExpenditure called with ${gyroData.length} data points`);
    const values = [100.0, 95.0, 105.0, 373.42];  // Example: returns multiple values per window
    console.log(`Returning ${values.length} values: ${values.join(', ')}`);
    return values;
} 