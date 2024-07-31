-- Create the table
CREATE TABLE IF NOT EXISTS lang_zoom_cancellations (
    ID STRING,
    Cancellation_Reason STRING,
    Date DATE,
    User_ID STRING
);

CREATE TABLE IF NOT EXISTS lang_zoom_users (
    ID STRING,
    Email STRING,
    Plan_Type STRING
);

-- Create a stage to host the files
CREATE STAGE IF NOT EXISTS lang_zoom_stage;

-- Upload the file to the stage
PUT file://zoom_cancellations_synthetic.csv @lang_zoom_stage;
PUT file://zoom_users.csv @lang_zoom_stage;

-- Load data from the staged file into the table
COPY INTO zoom_cancellations
FROM @lang_zoom_stage/zoom_cancellations_synthetic.csv
FILE_FORMAT = (TYPE = 'CSV', FIELD_OPTIONALLY_ENCLOSED_BY = '"', SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

COPY INTO zoom_users
FROM @lang_zoom_stage/zoom_users.csv
FILE_FORMAT = (TYPE = 'CSV', FIELD_OPTIONALLY_ENCLOSED_BY = '"', SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

-- Create a sample view to correlate the reviews with each user plan type
-- This view follows the column naming convention required by the agents. Learn more here: https://help.lang.ai/en/articles/9584876-setting-up-the-snowflake-native-app
CREATE VIEW LANG_ZOOM_VIEW AS
SELECT m.ID, m.CANCELLATION_REASON as TEXT, m.DATE as CREATION_DATE, m.USER_ID as USER_ID, u.PLAN_TYPE as PLAN_TYPE
FROM LOCAL_LANGAI_APP_DATABASE.PUBLIC.ZOOM_CANCELLATIONS m
JOIN LOCAL_LANGAI_APP_DATABASE.PUBLIC.ZOOM_USERS u where u.ID = m.USER_ID;
