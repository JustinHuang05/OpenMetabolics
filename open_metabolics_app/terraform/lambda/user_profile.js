const { DynamoDBClient, PutItemCommand, GetItemCommand } = require("@aws-sdk/client-dynamodb");

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

        if (!body.user_email) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: "Missing required field: user_email" }),
            };
        }

        // Validate required fields
        const requiredFields = ['weight', 'height', 'gender', 'age'];
        const missingFields = requiredFields.filter(field => !body[field]);
        
        if (missingFields.length > 0) {
            return {
                statusCode: 400,
                body: JSON.stringify({ 
                    error: "Missing required fields", 
                    fields: missingFields 
                }),
            };
        }

        // Validate data types and ranges
        const weight = parseFloat(body.weight);
        const height = parseFloat(body.height);
        const age = parseInt(body.age);
        
        if (isNaN(weight) || weight <= 0 || weight > 500) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: "Invalid weight value" }),
            };
        }

        if (isNaN(height) || height <= 0 || height > 300) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: "Invalid height value" }),
            };
        }

        if (isNaN(age) || age <= 0 || age > 120) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: "Invalid age value" }),
            };
        }

        if (!['male', 'female', 'other'].includes(body.gender.toLowerCase())) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: "Invalid gender value" }),
            };
        }

        // Create the item to store in DynamoDB
        const item = {
            TableName: process.env.USER_PROFILES_TABLE,
            Item: {
                UserEmail: { S: body.user_email.toLowerCase() },
                Weight: { N: weight.toString() },
                Height: { N: height.toString() },
                Gender: { S: body.gender.toLowerCase() },
                Age: { N: age.toString() },
                LastUpdated: { S: new Date().toISOString() }
            }
        };

        // Save to DynamoDB
        await client.send(new PutItemCommand(item));

        return {
            statusCode: 200,
            body: JSON.stringify({ 
                message: "User profile updated successfully",
                user_email: body.user_email,
                weight: weight,
                height: height,
                gender: body.gender,
                age: age
            }),
        };

    } catch (error) {
        console.error("Error updating user profile:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message }),
        };
    }
}; 