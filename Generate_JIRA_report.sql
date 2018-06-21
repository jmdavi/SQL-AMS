/*
name: Generate_JIRA_Report.sql
created: 8/17/2016
DESCRIPTION - This is used AFTER ORACLE_to_JIRA.sql. It pulls all of the task information about JIRA tickets and then reports off of it.
*/

/*

TRUNCATE TABLE JIRAjson;
DROP TABLE JIRAlist;

CREATE TABLE JIRAjson
  (id RAW (16) NOT NULL,
   date_loaded TIMESTAMP(6) WITH TIME ZONE,
   asdf_document CLOB CHECK (asdf_document IS JSON));
*/

--start with a clean slate every time
TRUNCATE TABLE JIRAjson;

--this PL/SQL uses the JIRA issue keys in table JIRAlist (originally collected by ORACLE_to_JIRA.sql) to gather all of the detailed task information, for use in the report
--/
BEGIN
--this FOR loop is the big change from ORACLE_to_JIRA, basically recycling the code for collecting the JSON into CLOBS
FOR ticket IN (
WITH baseline AS (
SELECT tl.it_ticket, otherkey
FROM JIRAlist,
JSON_TABLE(asdf_document, '$.issues[*]'
COLUMNS
  (it_ticket VARCHAR2(100) PATH '$.key'
  ,NESTED PATH '$.fields.issuelinks[*]'
  COLUMNS ( otherkey PATH '$.inwardIssue.key' )
  )
  ) AS tl
)
SELECT DISTINCT it_ticket AS key
FROM baseline
WHERE otherkey IS NOT NULL
UNION
SELECT DISTINCT otherkey AS key
FROM baseline
WHERE otherkey IS NOT NULL
)

LOOP
--this can be commented out, but checks what url I'm requesting
dbms_output.put_line('https://jira.xyz.net/rest/api/2/issue/'||ticket.key||'?expand=transitions');
--this is all the same from ORACLE_to_JIRA.sql
DECLARE
 l_http_request   UTL_HTTP.req;
 l_http_response  UTL_HTTP.resp;
 l_clob           CLOB;
 l_text           VARCHAR2(32767);
BEGIN
 -- Initialize the CLOB.
 DBMS_LOB.createtemporary(l_clob, FALSE);

 -- Make a HTTP request and get the response.
 UTL_HTTP.set_wallet('file:/file/path/here/', 'xyz');

l_http_request  := UTL_HTTP.begin_request('https://jira.xyz.net/rest/api/2/issue/'||ticket.key||'?expand=transitions');
UTL_HTTP.set_authentication(l_http_request, '&username', '&password');
 l_http_response := UTL_HTTP.get_response(l_http_request);

 -- Copy the response into the CLOB.
 BEGIN
   LOOP
     UTL_HTTP.read_text(l_http_response, l_text, 32767);
     DBMS_LOB.writeappend (l_clob, LENGTH(l_text), l_text);
   END LOOP;
 EXCEPTION
   WHEN UTL_HTTP.end_of_body THEN
     UTL_HTTP.end_response(l_http_response);
 END;

--note that the table it inserts into has been changed, this is because the JSON format differs
 INSERT INTO JIRAjson VALUES (
SYS_GUID(),
SYSTIMESTAMP,
l_clob
);


EXCEPTION
 WHEN OTHERS THEN
   UTL_HTTP.end_response(l_http_response);
   -- Relase the resources associated with the temporary LOB.
   DBMS_LOB.freetemporary(l_clob);
   RAISE;
END load_html_from_url;
--dbms_output.put_line('done with https://jira.xyz.net/rest/api/2/issue/'||ticket.key||'?expand=transitions');

--This additional end loop required
END LOOP;
END;
/

--check to see that the clobs are populated
--SELECT * FROM JIRAjson;

--this is a way to get AD info each week, based on a table populated by DBAs
DROP TABLE ad_info_JIRA;

CREATE TABLE ad_info_JIRA AS (
SELECT 
AD_SAM_ACCOUNT_NAME, AD_NAME, AD_MANAGER
, AD_USERACCOUNTCONTROL
, CASE WHEN AD_USERACCOUNTCONTROL ='514' THEN 'Y' ELSE 'Not marked Disabled' END AS OU_Disabled
FROM entitlement_review.ad_info
WHERE CAST(CREATED_DATE AS DATE) = CAST((SELECT MAX(CREATED_DATE) FROM entitlement_review.ad_info) AS DATE)
AND AD_SAM_ACCOUNT_NAME NOT LIKE '%-adm'
)
;

--essentially splits into four temp tables based on each type of ticket
WITH PROJECTW as (
SELECT
trim(regexp_replace(json_value(asdf_document,'$.fields.summary'),'search( for )?','',1,0,'i')) as Name
--,json_value(asdf_document,'$.fields.issuetype.name') AS typeofticket
,TO_DATE(json_value(asdf_document,'$.fields.customfield_10734'),'YYYY-MM-DD') AS date
,json_value(asdf_document,'$.key') as ticket
,TO_DATE(regexp_replace(json_value(asdf_document,'$.fields.created'),'T.*',''),'YYYY-MM-DD') as ticketcreated
,json_value(asdf_document,'$.fields.status.name') AS PROJECTWstatus
,TO_DATE(regexp_replace(json_value(asdf_document,'$.fields.resolutiondate'),'T.*',''),'YYYY-MM-DD') as ticketresolved
--calculation for the difference in days is handled in SELECT statement
,CASE WHEN regexp_like(json_query(asdf_document,'$.fields.comment.comments[*].body' WITH ARRAY WRAPPER),'revo[kc]|disable|expiration set','i') THEN 'Probably Yes' END AS AD_review_comments
,json_value(asdf_document,'$.fields.status.name') as JIRA_status
--,json_query(asdf_document,'$.fields.issuelinks') as issuelinks
--,json_query(asdf_document,'$.fields.issuelinks[0].inwardIssue') as firstissue
,json_value(asdf_document,'$.fields.issuelinks[0].inwardIssue.key') as key1
,json_value(asdf_document,'$.fields.issuelinks[0].inwardIssue.fields.status.name') as status1
,json_value(asdf_document,'$.fields.issuelinks[1].inwardIssue.key') as key2
,json_value(asdf_document,'$.fields.issuelinks[1].inwardIssue.fields.status.name') as status2
,json_value(asdf_document,'$.fields.issuelinks[2].inwardIssue.key') as key3
,json_value(asdf_document,'$.fields.issuelinks[2].inwardIssue.fields.status.name') as status3
,json_value(asdf_document,'$.fields.issuelinks[3].inwardIssue.key') as key4
,json_value(asdf_document,'$.fields.issuelinks[3].inwardIssue.fields.status.name') as status4
,json_value(asdf_document,'$.fields.issuelinks[4].inwardIssue.key') as key5
,json_value(asdf_document,'$.fields.issuelinks[4].inwardIssue.fields.status.name') as status5
FROM JIRAjson
WHERE
json_value(asdf_document,'$.fields.issuetype.name')='PROJECTW'
ORDER BY json_value(asdf_document,'$.fields.customfield_10734') DESC
)
,PROJECTX AS (
SELECT json_value(asdf_document,'$.key') as ticket
,json_value(asdf_document,'$.fields.summary') as summarytitle
,json_value(asdf_document,'$.fields.status.name') AS PROJECTXstatus
,TO_DATE(regexp_replace(json_value(asdf_document,'$.fields.resolutiondate'),'T.*',''),'YYYY-MM-DD') as ticketresolved
,json_query(asdf_document,'$.fields.comment.comments[*].body' WITH ARRAY WRAPPER) AS comm
,CASE WHEN regexp_like(json_query(asdf_document,'$.fields.comment.comments[*].body' WITH ARRAY WRAPPER),'drop|removed|whatever|close|(no|does not have).*(account|username|db)','i') THEN 'Probably Yes' END AS review_comments
FROM JIRAjson
WHERE
json_value(asdf_document,'$.key') LIKE 'PROJECTX-%'
)
,PROJECTY AS (
SELECT json_value(asdf_document,'$.key') as ticket
,json_value(asdf_document,'$.fields.summary') as summarytitle
,json_value(asdf_document,'$.fields.status.name') AS PROJECTYstatus
,TO_DATE(regexp_replace(json_value(asdf_document,'$.fields.resolutiondate'),'T.*',''),'YYYY-MM-DD') as ticketresolved
,json_query(asdf_document,'$.fields.comment.comments[*].body' WITH ARRAY WRAPPER) AS comm
,CASE WHEN regexp_like(json_query(asdf_document,'$.fields.comment.comments[*].body' WITH ARRAY WRAPPER),'drop|removed|whatever|close|(no|does not have).*(account|username|db)','i') THEN 'Probably Yes' END AS review_comments2
FROM JIRAjson
WHERE
json_value(asdf_document,'$.key') LIKE 'PROJECTY-%'
)
,PROJECTZ AS (
SELECT json_value(asdf_document,'$.key') as ticket
,json_value(asdf_document,'$.fields.summary') as summarytitle
,TO_DATE(regexp_replace(json_value(asdf_document,'$.fields.resolutiondate'),'T.*',''),'YYYY-MM-DD') as ticketresolved
FROM JIRAjson
WHERE
json_value(asdf_document,'$.key') LIKE 'PROJECTZ-%'
)
SELECT
nvl(ad.ad_name,PROJECTW.name) AS "Name of Employee", ad.ad_sam_account_name, PROJECTW.date AS "Date from Originating Ticket", PROJECTW.ticket AS "PROJECTW ticket number", PROJECTW.itstatus
, PROJECTW.ticketcreated AS "Date PROJECTW ticket created", PROJECTW.ticketresolved AS "Date PROJECTW ticket resolved", PROJECTW.ticketresolved-PROJECTW.date AS "Difference in Days"
, PROJECTX.ticket AS "Project X ticket",PROJECTX.PROJECTXStatus AS "Project X Ticket Status", PROJECTX.ticketresolved AS "Date Project X ticket resolved"
, PROJECTY.ticket AS "Project Y Removal ticket",PROJECTY.PROJECTYStatus AS "Project Y Ticket Status", PROJECTY.ticketresolved AS "Date Project Y ticket resolved"
, PROJECTZ.ticket AS "Project Z Ticket Name", PROJECTZ.ticketresolved AS "Date Project Z ticket resolved"
FROM PROJECTW
FULL JOIN PROJECTX on PROJECTW.KEY1=PROJECTX.ticket OR PROJECTW.KEY2=PROJECTX.ticket OR PROJECTW.KEY3=PROJECTX.ticket OR PROJECTW.KEY4=PROJECTX.ticket OR PROJECTW.KEY5=PROJECTX.ticket
FULL JOIN PROJECTY on PROJECTW.KEY1=PROJECTY.ticket OR PROJECTW.KEY2=PROJECTY.ticket OR PROJECTW.KEY3=PROJECTY.ticket OR PROJECTW.KEY4=PROJECTY.ticket OR PROJECTW.KEY5=PROJECTY.ticket
FULL JOIN PROJECTZ on PROJECTW.KEY1=PROJECTZ.ticket OR PROJECTW.KEY2=PROJECTZ.ticket OR PROJECTW.KEY3=PROJECTZ.ticket OR PROJECTW.KEY4=PROJECTZ.ticket OR PROJECTW.KEY5=PROJECTZ.ticket
LEFT JOIN ad_info_JIRA ad on ad.ad_name LIKE '%'||PROJECTW.name||'%' --note this table is populated independently above this statement
WHERE PROJECTW.ticket IS NOT NULL
ORDER BY PROJECTW.ticket DESC;
