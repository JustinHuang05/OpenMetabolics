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
            B4(["Lambda: Get Past Sessions Summary"])
            B5(["Lambda: Get Session Details"])
        end

        subgraph Cognito
            C1(User Authentication)
        end

        subgraph DynamoDB
            D1(Raw Sensor Data)
            D2(Energy Expenditure Results)
            D3(User Profiles)
        end

        subgraph Fargate
            E1(Energy Expenditure Processing)
        end

        F1(SES: Email Verification)
    end

    %% Frontend to Lambda (API Gateway) connections
    A1-->|Upload Sensor Data|B1
    A1-->|Process Energy Expenditure|E1
    A3-->|Save Profile|B2
    A3-->|Fetch Profile|B3
    A2-->|Fetch Session Summaries|B4
    A4-->|Fetch Session Details|B5

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

    %% Fargate (Energy Expenditure Processing)
    E1-->|Reads|D1
    E1-->|Reads|D3
    E1-->|Writes|D2

    B2-->|Uses|C1
    B3-->|Uses|C1
    C1-->|Sends|F1

%% Data Flow Description
%% 1. Past Sessions Page (A2) fetches only session summaries (timestamp, ID, measurement count)
%% 2. Session Details Page (A4) loads full session data when viewing a specific session
%% 3. This optimizes initial load time and reduces data transfer
