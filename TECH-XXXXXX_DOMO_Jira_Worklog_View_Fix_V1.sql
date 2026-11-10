/*
================================================================================
SCRIPT NAME:    TECH-XXXXXX_DOMO_Jira_Worklog_View_Fix_V1.sql
TICKET ID:      TECH-XXXXXX
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-10
MODIFIED:       2026-11-10
VERSION:        v1.0

PURPOSE:
    Replacement for the DOMO data view on dataset d5af8e09-b647-4dda-9654-2e20d2ac6320
    (Jira issues + worklog). The old view listed ~600 columns explicitly. It fails to
    open with "Unable to find column: base.New Department Code_id" (and many similar)
    because Jira custom fields were dropped from the dataset at the last refresh
    (schema drift, see TECH-211719), and the view still references them.

SOURCE SYSTEM:  DOMO dataset d5af8e09-b647-4dda-9654-2e20d2ac6320 (Jira issues + worklog)
TARGET SYSTEM:  DOMO data view (DOMO SQL / MySQL dialect)

BUSINESS LOGIC:
    - Option A (recommended): pass through every column. Cannot break on schema drift.
    - Option B: fixed core worklog subset, for when a stable column set is needed.
      Uses only core Jira/worklog columns, not custom fields. Confirm each column
      exists in the dataset schema before saving.

CHANGE LOG:
    2026-11-10 - J.Cook - TECH-XXXXXX - Replace hard-coded 600-column view with SELECT *

DEPENDENCIES:
    - DOMO dataset d5af8e09-b647-4dda-9654-2e20d2ac6320

NOTES:
    - Use Option A OR Option B in the view editor, not both
    - Cards/Beast Modes using dropped custom fields (e.g. New Department Code_value)
      will still break until those fields reappear in the dataset
================================================================================
*/

-- ============================ OPTION A (recommended) ===========================
SELECT *
FROM `d5af8e09-b647-4dda-9654-2e20d2ac6320`


-- ============================ OPTION B (core subset) ===========================
-- Uncomment this block and remove Option A to use it.
/*
SELECT `base`.`issue_id`                AS issue_id,
       `base`.`issue_key`               AS issue_key,
       `base`.`project_key`             AS project_key,
       `base`.`project_name`            AS project_name,
       `base`.`status_name`             AS status_name,
       `base`.`priority_name`           AS priority_name,
       `base`.`assignee_displayName`    AS assignee_displayName,
       `base`.`reporter_displayName`    AS reporter_displayName,
       `base`.`Summary`                 AS Summary,
       `base`.`Created`                 AS Created,
       `base`.`Updated`                 AS Updated,
       `base`.`Resolved`                AS Resolved,
       `base`.`Due Date`                AS `Due Date`,
       `base`.`Labels`                  AS Labels,
       `base`.`author_displayName`      AS author_displayName,
       `base`.`started`                 AS started,
       `base`.`timeSpentSeconds`        AS timeSpentSeconds,
       `base`.`TimeWorked_Hrs`          AS TimeWorked_Hrs,
       `base`.`Time Spent`              AS `Time Spent`,
       `base`.`RAW_Jira_WorkLog-created` AS `RAW_Jira_WorkLog-created`,
       `base`.`RAW_Jira_WorkLog-updated` AS `RAW_Jira_WorkLog-updated`,
       `base`.`Worklog-createdMonthName` AS `Worklog-createdMonthName`,
       `base`.`WorkLog-createdMonthNumber` AS `WorkLog-createdMonthNumber`,
       `base`.`parent_key`              AS parent_key
FROM `d5af8e09-b647-4dda-9654-2e20d2ac6320` AS base
*/
