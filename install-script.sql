-- Set the warehouse to be used for the App setup
SET USER_WAREHOUSE = '<YOUR_WAREHOUSE>';

-- Set the name of the LangAI application
-- IMPORTANT: Ensure this matches the exact name used during installation
SET LANGAI_APP_NAME = 'LANGAI_APP';

-- Use the same role that installed the application with the appropriate privileges.
-- https://other-docs.snowflake.com/en/native-apps/consumer-installing#set-up-required-privileges
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($USER_WAREHOUSE);


--------------------------------------------------
-- Grant necessary privileges to the LangAI app --
--------------------------------------------------
-- Grant BIND SERVICE ENDPOINT privilege to the LangAI application to enable
-- network ingress and access to the LangAI UI.
-- Details of the privilege can be found here
-- https://other-docs.snowflake.com/LIMITEDACCESS/native-apps/na-spcs-consumer#set-up-access-to-network-objects
GRANT BIND SERVICE ENDPOINT ON ACCOUNT TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);

-- Grant EXECUTE TASK privilege to enable automatic generation of insights
GRANT EXECUTE TASK ON ACCOUNT TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);


------------------------------------------------------
-- Create database and schema to save configuration --
------------------------------------------------------
-- Database and schema to hold network rules for the LangAI application along
-- with usage for the LangAI application.
SET LANGAI_APP_DB = CONCAT($LANGAI_APP_NAME, '_APP_DATA');
CREATE DATABASE IF NOT EXISTS IDENTIFIER($LANGAI_APP_DB);
GRANT USAGE ON DATABASE IDENTIFIER($LANGAI_APP_DB) TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);
USE DATABASE IDENTIFIER($LANGAI_APP_DB);
CREATE SCHEMA IF NOT EXISTS CONFIGURATION;
GRANT USAGE ON SCHEMA CONFIGURATION TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);
USE SCHEMA CONFIGURATION;


-----------------------------------------
-- Create external access integrations --
-----------------------------------------
-- These integrations are necessary to allow the App to make requests to resources outside of Snowflake
-- They enable secure connections to external services and APIs required for the App's functionality
-- https://docs.snowflake.com/en/developer-guide/external-network-access/external-network-access-overview

-- Set up network rule to allow access to Slack
CREATE OR REPLACE NETWORK RULE SLACK_EXTERNAL_ACCESS_NETWORK_RULE
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('slack.com');
-- Create external access integration for Slack
-- This enables the app to send insights via Slack
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION SLACK_EXTERNAL_ACCESS_INTEGRATION
    ALLOWED_NETWORK_RULES = (SLACK_EXTERNAL_ACCESS_NETWORK_RULE)
    ENABLED = true;

-- Grant USAGE privilege on the external access integration to the app
GRANT USAGE ON INTEGRATION SLACK_EXTERNAL_ACCESS_INTEGRATION TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);


-------------------
-- CONFIGURE LLM --
-------------------
-- Llama Configuration
-- Necessary for the app to access to snowflake cortex
-- https://medium.com/snowflake/unlocking-the-power-of-snowflake-native-app-and-cortex-llm-building-applications-with-ease-61ef0d3b5296
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);


------------------------------
-- Grant access to the view --
------------------------------
-- These steps require a view to be created. You may complete this step after installing and launching the application.
-- Learn more here: https://help.lang.ai/en/articles/9914672-creating-an-sql-view-for-your-ai-agent
GRANT USAGE ON DATABASE "YOUR_DATABASE" TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);
GRANT USAGE ON SCHEMA "YOUR_SCHEMA" TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);
GRANT SELECT ON VIEW "YOUR_VIEW" TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);


------------------------
-- Installing the app --
------------------------
-- Create and configure necessary objects for the app installation

-- Create a warehouse for the app to execute queries
CREATE WAREHOUSE IF NOT EXISTS LANGAI_APP_WAREHOUSE
    WAREHOUSE_SIZE = 'X-SMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 30
    AUTO_RESUME = true
    INITIALLY_SUSPENDED = true
    COMMENT = 'Langai app warehouse';

-- Grant usage of the warehouse to the app
GRANT USAGE ON WAREHOUSE LANGAI_APP_WAREHOUSE TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);

-- Create a compute pool for the app service
CREATE COMPUTE POOL IF NOT EXISTS LANGAI_APP_COMPUTE_POOL
    FOR APPLICATION IDENTIFIER($LANGAI_APP_NAME)
    MIN_NODES = 1
    MAX_NODES = 1
    AUTO_SUSPEND_SECS = 60
    INSTANCE_FAMILY = CPU_X64_XS
    AUTO_RESUME = true;

-- Grant usage of the compute pool to the app
GRANT USAGE ON COMPUTE POOL LANGAI_APP_COMPUTE_POOL TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);

-- Create a compute pool for calculating insights
CREATE COMPUTE POOL IF NOT EXISTS LANGAI_APP_INSIGHTS_COMPUTE_POOL
    FOR APPLICATION IDENTIFIER($LANGAI_APP_NAME)
    MIN_NODES = 1
    MAX_NODES = 1
    AUTO_SUSPEND_SECS = 60
    INSTANCE_FAMILY = HIGHMEM_X64_S
    AUTO_RESUME = true
    INITIALLY_SUSPENDED = true;

-- Grant usage of the compute pool to the app
GRANT USAGE ON COMPUTE POOL LANGAI_APP_INSIGHTS_COMPUTE_POOL TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);

-- Initiate the app installation process
-- Note: This operation may take several minutes to complete
SET START_APP_PROCEDURE = CONCAT($LANGAI_APP_NAME, '.APP_PUBLIC.MANUAL_START_APP');
CALL IDENTIFIER($START_APP_PROCEDURE)();


---------------------------
-- Enable event sharing  --
---------------------------
-- Optional: Allows LangAI to receive system logs to help diagnose application issues
ALTER APPLICATION IDENTIFIER($LANGAI_APP_NAME) SET AUTHORIZE_TELEMETRY_EVENT_SHARING=true;


-- Optional: Create a specific role for app access
-- This step allows for more granular control over who can use the app
-- Create a new role for LangAI app users if it doesn't already exist
CREATE ROLE IF NOT EXISTS LANGAI_APP_USER_ROLE;
-- Grant the app-specific user role to the newly created role
SET LANGAI_APP_USER = CONCAT($LANGAI_APP_NAME, '.APP_USER');
GRANT APPLICATION ROLE IDENTIFIER($LANGAI_APP_USER) TO ROLE LANGAI_APP_USER_ROLE;
-- Assign the new role to a ROLE or USER
GRANT ROLE LANGAI_APP_USER_ROLE TO USER|ROLE <YOUR_USER|YOUR_ROLE>;
