const { DynamoDBClient, PutItemCommand, GetItemCommand, QueryCommand, BatchWriteItemCommand } = require("@aws-sdk/client-dynamodb");

const client = new DynamoDBClient({ region: "us-east-1" });

exports.handler = async (event) => {
    try {
        console.log("Received event:", event);

        // Handle both API Gateway events (HTTP) and direct Lambda test events
        let body = event.body ? event.body : event; 

        if (typeof body === "string") {
            try {
                body = JSON.parse(body); // Parse if it's a string
            } catch (error) {
                console.error("JSON Parsing Error:", error);
                return {
                    statusCode: 400,
                    body: JSON.stringify({ error: "Invalid JSON format" }),
                };
            }
        }

        if (!body.csv_data || !body.user_email || !body.session_id) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: "Missing required fields (csv_data, user_email, or session_id)" }),
            };
        }

        // Split CSV into rows
        const rows = body.csv_data.split("\n");
        const headers = rows[0].split(",");

        // Prepare batch write items
        const batchItems = [];
        const maxBatchSize = 25; // DynamoDB batch write limit
        
        // Track timestamps to ensure uniqueness
        const timestampCounts = new Map();

        // Process each row and prepare for batch insert
        for (let i = 1; i < rows.length; i++) {
            const values = rows[i].split(",");
            if (values.length !== headers.length) continue; // Skip invalid rows

            // Convert the timestamp to ISO string format
            // The timestamp from the CSV is in seconds (milliseconds/1000)
            const timestampValue = parseFloat(values[0]) * 1000;
            const date = new Date(timestampValue);
            
            // Ensure we get a valid ISO string - manually construct if needed
            let originalTimestamp;
            try {
                originalTimestamp = date.toISOString();
                // Validate the format - should be YYYY-MM-DDTHH:MM:SS.sssZ
                if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(originalTimestamp)) {
                    throw new Error('Invalid ISO format');
                }
            } catch (error) {
                // Fallback: manually construct ISO string
                const year = date.getUTCFullYear();
                const month = String(date.getUTCMonth() + 1).padStart(2, '0');
                const day = String(date.getUTCDate()).padStart(2, '0');
                const hours = String(date.getUTCHours()).padStart(2, '0');
                const minutes = String(date.getUTCMinutes()).padStart(2, '0');
                const seconds = String(date.getUTCSeconds()).padStart(2, '0');
                const milliseconds = String(date.getUTCMilliseconds()).padStart(3, '0');
                originalTimestamp = `${year}-${month}-${day}T${hours}:${minutes}:${seconds}.${milliseconds}Z`;
            }
            
            // Create a unique identifier by tracking sequence numbers for each timestamp
            let sequenceNumber = timestampCounts.get(originalTimestamp) || 0;
            timestampCounts.set(originalTimestamp, sequenceNumber + 1);
            
            // Create unique timestamp with sequence number (6 digits, zero-padded)
            const uniqueTimestamp = `${originalTimestamp}_${sequenceNumber.toString().padStart(6, '0')}`;

            const item = {
                PutRequest: {
                    Item: {
                        SessionId: { S: body.session_id },
                        Timestamp: { S: uniqueTimestamp },
                        UserEmail: { S: body.user_email.toLowerCase() },
                        OriginalTimestamp: { S: originalTimestamp }, // Keep original timestamp for queries
                        SequenceNumber: { N: sequenceNumber.toString() }, // Add sequence number as separate field
                        Accelerometer_X: { N: values[1] },
                        Accelerometer_Y: { N: values[2] },
                        Accelerometer_Z: { N: values[3] },
                        Gyroscope_X: { N: values[4] },
                        Gyroscope_Y: { N: values[5] },
                        Gyroscope_Z: { N: values[6] },
                        Gyro_L2_Norm: { N: values[7] }
                    }
                }
            };

            batchItems.push(item);
        }

        console.log(`Processing ${batchItems.length} items in batches of ${maxBatchSize}`);

        // Process items in batches of 25 (DynamoDB limit)
        for (let i = 0; i < batchItems.length; i += maxBatchSize) {
            const batch = batchItems.slice(i, i + maxBatchSize);
            
            const batchWriteParams = {
                RequestItems: {
                    [process.env.DYNAMODB_TABLE]: batch
                }
            };

            let retryCount = 0;
            const maxRetries = 3;
            
            while (retryCount < maxRetries) {
                try {
                    const result = await client.send(new BatchWriteItemCommand(batchWriteParams));
                    
                    // Handle unprocessed items
                    if (result.UnprocessedItems && Object.keys(result.UnprocessedItems).length > 0) {
                        console.log(`Retrying ${Object.keys(result.UnprocessedItems).length} unprocessed items`);
                        batchWriteParams.RequestItems = result.UnprocessedItems;
                        retryCount++;
                        
                        // Exponential backoff
                        await new Promise(resolve => setTimeout(resolve, Math.pow(2, retryCount) * 100));
                        continue;
                    }
                    
                    console.log(`Successfully processed batch ${Math.floor(i/maxBatchSize) + 1}/${Math.ceil(batchItems.length/maxBatchSize)}`);
                    break; // Success, exit retry loop
                } catch (error) {
                    // Handle specific duplicate key errors
                    if (error.message && error.message.includes('duplicates')) {
                        console.error(`Duplicate key error in batch ${Math.floor(i/maxBatchSize) + 1}:`, error.message);
                        // Log the problematic items for debugging
                        console.log('Problematic batch items:', JSON.stringify(batch.map(item => ({
                            SessionId: item.PutRequest.Item.SessionId.S,
                            Timestamp: item.PutRequest.Item.Timestamp.S,
                            OriginalTimestamp: item.PutRequest.Item.OriginalTimestamp.S
                        })), null, 2));
                        throw new Error(`Duplicate key error: ${error.message}`);
                    }
                    
                    retryCount++;
                    if (retryCount >= maxRetries) {
                        throw error;
                    }
                    
                    console.log(`Batch write failed, retrying (${retryCount}/${maxRetries}):`, error.message);
                    await new Promise(resolve => setTimeout(resolve, Math.pow(2, retryCount) * 100));
                }
            }
        }

        return {
            statusCode: 200,
            body: JSON.stringify({ 
                message: "CSV data successfully saved to DynamoDB!",
                session_id: body.session_id,
                rows_processed: batchItems.length,
                unique_timestamps: timestampCounts.size
            }),
        };

    } catch (error) {
        console.error("Error saving data:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message }),
        };
    }
}; 