import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";

const client = new DynamoDBClient({ region: "us-east-1" });

export const handler = async (event) => {
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

        if (!body.csv_data) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: "Missing csv_data field" }),
            };
        }

        // Split CSV into rows
        const rows = body.csv_data.split("\\n");
        const headers = rows[0].split(",");

        // Process each row and insert into DynamoDB
        for (let i = 1; i < rows.length; i++) {
            const values = rows[i].split(",");
            if (values.length !== headers.length) continue; // Skip invalid rows

            const item = {
                TableName: "RawSensorData",
                Item: {
                    Timestamp: { S: values[0] },
                    Accelerometer_X: { N: values[1] },
                    Accelerometer_Y: { N: values[2] },
                    Accelerometer_Z: { N: values[3] },
                    Gyroscope_X: { N: values[4] },
                    Gyroscope_Y: { N: values[5] },
                    Gyroscope_Z: { N: values[6] },
                    Gyro_L2_Norm: { N: values[7] },
                },
            };

            await client.send(new PutItemCommand(item));
        }

        return {
            statusCode: 200,
            body: JSON.stringify({ message: "CSV data successfully saved to DynamoDB!" }),
        };

    } catch (error) {
        console.error("Error saving data:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message }),
        };
    }
};
