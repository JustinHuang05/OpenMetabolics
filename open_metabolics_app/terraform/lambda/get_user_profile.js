const { DynamoDBClient, GetItemCommand } = require("@aws-sdk/client-dynamodb");

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

        console.log("Parsed body:", JSON.stringify(body, null, 2));

        if (!body.user_email) {
            console.error("Missing user_email in request");
            return {
                statusCode: 400,
                body: JSON.stringify({ error: "Missing required field: user_email" }),
            };
        }

        // Get item from DynamoDB
        const params = {
            TableName: process.env.USER_PROFILES_TABLE,
            Key: {
                UserEmail: { S: body.user_email.toLowerCase() }
            }
        };

        console.log("DynamoDB params:", JSON.stringify(params, null, 2));

        const result = await client.send(new GetItemCommand(params));
        console.log("DynamoDB result:", JSON.stringify(result, null, 2));

        if (!result.Item) {
            console.log("No profile found for user:", body.user_email);
            return {
                statusCode: 404,
                body: JSON.stringify({ error: "User profile not found" }),
            };
        }

        // Convert DynamoDB item to regular JSON
        const profile = {
            user_email: result.Item.UserEmail.S,
            weight: parseFloat(result.Item.Weight.N),
            height: parseFloat(result.Item.Height.N),
            age: parseInt(result.Item.Age.N),
            gender: result.Item.Gender.S,
            last_updated: result.Item.LastUpdated.S
        };

        console.log("Returning profile:", JSON.stringify(profile, null, 2));

        return {
            statusCode: 200,
            body: JSON.stringify(profile),
        };

    } catch (error) {
        console.error("Error fetching user profile:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message }),
        };
    }
}; 