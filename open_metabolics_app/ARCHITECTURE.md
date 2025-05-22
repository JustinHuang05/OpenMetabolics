# OpenMetabolics System Architecture

This diagram shows the current architecture of the OpenMetabolics backend and frontend, including all major AWS resources, Lambda functions, SQS queues, and Fargate services.

- The frontend (Flutter app) communicates with AWS Lambda functions via API Gateway.
- User authentication is handled by Cognito.
- Sensor data, user profiles, session results, and survey responses are stored in DynamoDB tables.
- Energy expenditure processing is handled by a Fargate API service and a Fargate worker, with jobs queued in SQS.
- Survey and session management is handled by dedicated Lambda functions.
- SES is used for email verification.

```mermaid
flowchart LR
%% Frontend
subgraph Frontend
subgraph AuthPages["Authentication Pages"]
A0["Login Page"]
A5["Sign Up Page"]
A6["Verification Page"]
end
A1["Home Page (SensorScreen)"]
A2["Past Sessions Page"]
A3["User Profile Page"]
A4["Session Details Page"]
end

    %% AWS Cloud
    subgraph AWS Cloud
        subgraph API Gateway
            B1(["Lambda: Save Raw Sensor Data"])
            B2(["Lambda: Manage User Profile"])
            B3(["Lambda: Get User Profile"])
            B4(["Lambda: Get Past Sessions"])
            B5(["Lambda: Get Past Sessions Summary"])
            B6(["Lambda: Get Session Details"])
            B7(["Lambda: Save Survey Response"])
            B8(["Lambda: Get Survey Response"])
            B9(["Lambda: Check Survey Responses"])
        end

        subgraph Cognito
            C1(User Authentication)
        end

        subgraph DynamoDB
            D1(Raw Sensor Data)
            D2(Energy Expenditure Results)
            D3(User Profiles)
            D4(User Survey Responses)
            D5(Processing Status)
        end

        subgraph SQS
            Q1(Processing Queue)
            Q2(Processing DLQ)
        end

        subgraph Fargate
            E1(API Service)
            E2(Worker Service)
        end

        F1(SES: Email Verification)
    end

    %% Frontend to Lambda (API Gateway) connections
    A1-->|Upload Sensor Data|B1
    A1-->|Process Energy Expenditure|E1
    A3-->|Save Profile|B2
    A3-->|Fetch Profile|B3
    A2-->|Fetch Past Sessions|B4
    A2-->|Fetch Session Summaries|B5
    A4-->|Fetch Session Details|B6
    A4-->|Survey Response|B7
    A4-->|Get Survey Response|B8
    A2-->|Check Survey Responses|B9

    %% Auth pages to Cognito
    A0-->|Login|C1
    A5-->|Sign Up|C1
    A6-->|Verify Email|C1

    %% Lambda to DB and other services
    B1-->|Writes|D1
    B2-->|Writes|D3
    B3-->|Reads|D3
    B4-->|Reads|D2
    B5-->|Reads|D2
    B6-->|Reads|D2
    B7-->|Writes|D4
    B8-->|Reads|D4
    B9-->|Reads|D4

    %% Fargate (API Service and Worker)
    E1-->|Receives jobs|Q1
    E2-->|Processes jobs|Q1
    E2-->|Reads|D1
    E2-->|Reads|D3
    E2-->|Writes|D2
    E2-->|Updates|D5

    Q1-->|Failed jobs|Q2

    B2-->|Uses|C1
    B3-->|Uses|C1
    C1-->|Sends|F1

%% Data Flow Description
%% 1. Past Sessions Page (A2) fetches only session summaries (timestamp, ID, measurement count)
%% 2. Session Details Page (A4) loads full session data when viewing a specific session
%% 3. This optimizes initial load time and reduces data transfer
```
