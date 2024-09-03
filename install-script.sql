-- Set the warehouse to be used to run the setup scripts
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
USE DATABASE IDENTIFIER($LANGAI_APP_DB);
CREATE SCHEMA IF NOT EXISTS CONFIGURATION;
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

-------------------
-- CONFIGURE LLM --
-------------------
-- OpenAI configuration is required for app functionality, even if not used.
-- Llama configuration is optional and only needed if you want to use it.
-- If both are configured, OpenAI will be used preferentially by the app.

-- OpenAI Configuration (Required)
SET OPENAI_TOKEN = '<YOUR_OPENAI_TOKEN>'; -- Leave empty if not using OpenAI
SET OPENAI_URL = 'api.openai.com'; -- Use 'not-used' if not using OpenAI

-- Create a secret for OpenAI API calls
CREATE OR REPLACE SECRET OPENAI_TOKEN
    TYPE = GENERIC_STRING
    SECRET_STRING = $OPENAI_TOKEN;

-- Set up network rule to allow access to OpenAI API
CREATE OR REPLACE NETWORK RULE OPENAI_EXTERNAL_ACCESS_NETWORK_RULE
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ($OPENAI_URL);

-- Create external access integration for OpenAI
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION OPENAI_EXTERNAL_ACCESS_INTEGRATION
    ALLOWED_NETWORK_RULES = (OPENAI_EXTERNAL_ACCESS_NETWORK_RULE)
    ALLOWED_AUTHENTICATION_SECRETS=(OPENAI_TOKEN)
    ENABLED = true;

-- Llama Configuration (Optional)
-- Necessary for the app to access to snowflake cortex
-- https://medium.com/snowflake/unlocking-the-power-of-snowflake-native-app-and-cortex-llm-building-applications-with-ease-61ef0d3b5296
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);

-----------------------------------
-- Create application references --
-----------------------------------
-- These references are necessary to allow the Snowflake Native App to access existing objects in the consumer account
-- They enable the app to interact with specific tables, views, or other objects that exist outside the APPLICATION object
-- References provide a secure way for the app to access consumer data without knowing the exact schema and object names
-- https://docs.snowflake.com/en/developer-guide/native-apps/requesting-refs

-- Set reference to OpenAI token
SET OPENAI_TOKEN_REFERENCE = (SELECT SYSTEM$REFERENCE('SECRET', CONCAT($LANGAI_APP_DB, '.CONFIGURATION.OPENAI_TOKEN'), 'PERSISTENT', 'READ', 'USAGE'));
CALL LANGAI_APP.CONFIG.REGISTER_SINGLE_REFERENCE('OPENAI_TOKEN', 'ADD', $OPENAI_TOKEN_REFERENCE);

-- Set reference to OpenAI external access integration
SET OPENAI_EXTERNAL_ACCESS_REFERENCE = (SELECT SYSTEM$REFERENCE('EXTERNAL_ACCESS_INTEGRATION', 'OPENAI_EXTERNAL_ACCESS_INTEGRATION', 'PERSISTENT', 'USAGE'));
CALL LANGAI_APP.CONFIG.REGISTER_SINGLE_REFERENCE('OPENAI_EXTERNAL_ACCESS', 'ADD', $OPENAI_EXTERNAL_ACCESS_REFERENCE);

-- Set reference to Slack external access integration
SET SLACK_EXTERNAL_ACCESS_REFERENCE = (SELECT SYSTEM$REFERENCE('EXTERNAL_ACCESS_INTEGRATION', 'SLACK_EXTERNAL_ACCESS_INTEGRATION', 'PERSISTENT', 'USAGE'));
CALL LANGAI_APP.CONFIG.REGISTER_SINGLE_REFERENCE('SLACK_EXTERNAL_ACCESS', 'ADD', $SLACK_EXTERNAL_ACCESS_REFERENCE);

-- Set reference to the view containing user interactions
-- It allows the app to access and read user interactions for insight generation
-- IMPORTANT: USE FULLY QUALIFIED NAME
SET VIEW_NAME = '<YOUR_DB.YOUR_SCHEMA.YOUR_VIEW>';
SET VIEW_REFERENCE = (SELECT SYSTEM$REFERENCE('VIEW', $VIEW_NAME, 'PERSISTENT', 'SELECT'));
CALL LANGAI_APP.CONFIG.REGISTER_SINGLE_REFERENCE('UNSTRUCTURED_DATA_VIEW', 'ADD', $VIEW_REFERENCE);

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
    INSTANCE_FAMILY = HIGHMEM_X64_S
    AUTO_RESUME = true;

-- Grant usage of the compute pool to the app
GRANT USAGE ON COMPUTE POOL LANGAI_APP_COMPUTE_POOL TO APPLICATION IDENTIFIER($LANGAI_APP_NAME);

-- Initiate the app installation process
-- Note: This operation may take several minutes to complete
CALL LANGAI_APP.APP_PUBLIC.MANUAL_START_APP();

-- OPTIONAL: Create a specific role for app access
-- This step allows for more granular control over who can use the app
-- Create a new role for LangAI app users if it doesn't already exist
CREATE ROLE IF NOT EXISTS LANGAI_APP_USER_ROLE;
-- Grant the app-specific user role to the newly created role
SET LANGAI_APP_USER = CONCAT($LANGAI_APP_NAME, '.APP_USER');
GRANT APPLICATION ROLE IDENTIFIER($LANGAI_APP_USER) TO ROLE LANGAI_APP_USER_ROLE;
-- Assign the new role to a ROLE or USER
GRANT ROLE LANGAI_APP_USER_ROLE TO USER|ROLE <YOUR_USER|YOUR_ROLE>;


