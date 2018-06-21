/*
name: ORACLE_TO_JIRA.sql
created: 8/17/2016
DESCRIPTION - This creates a list of all the relevant JIRA tickets and their linked issues from different projects. It is meant to be used in unison with GenerateTerminationReport.sql which uses this info to pull all relevant tasks into Oracle for reporting.

url to use when prompted: jira.xyz.com/rest/api/2/search?jql=project=xyz%20and%20issuetype=xyz&fields=id,key,issuelinks%20%20&maxResults=2000
*/

/*

TRUNCATE TABLE JIRAlist;
DROP TABLE JIRAlist;

CREATE TABLE JIRAlist
  (id RAW (16) NOT NULL,
   date_loaded TIMESTAMP(6) WITH TIME ZONE,
   term_document CLOB CHECK (term_document IS JSON));
*/

--start with a clean slate every time
TRUNCATE TABLE JIRAlist; 

--this PL/SQL will put the JSON returned by the url, which collects a list of all JIRA issues keys needed for reporting.
--the list of JIRA keys are saved in table JIRAlist (of the current schema)
--/
DECLARE 
 l_http_request   UTL_HTTP.req;
 l_http_response  UTL_HTTP.resp;
 l_clob           CLOB;                 --this will be the full JSON returned by the API
 l_text           VARCHAR2(32767);      --these are the segments of JSON that will be stitched into l_clob
BEGIN
 -- Initialize the CLOB. This function creates a space for the l_text chunks to go into
 DBMS_LOB.createtemporary(l_clob, FALSE);

 -- You need this to make it out into the world.
 UTL_HTTP.set_wallet('file:/file/path/here', 'xyz'); 
--this sends out the request and collects its contents
l_http_request  := UTL_HTTP.begin_request('&url');
UTL_HTTP.set_authentication(l_http_request, '&AD_username', '&AD_pwd');
 l_http_response := UTL_HTTP.get_response(l_http_request);

 -- Copy the response to the URL into the CLOB, it is JSON text as returned by JIRA
 BEGIN
   LOOP
     UTL_HTTP.read_text(l_http_response, l_text, 32767);
     DBMS_LOB.writeappend (l_clob, LENGTH(l_text), l_text);
   END LOOP;
 EXCEPTION
   WHEN UTL_HTTP.end_of_body THEN
     UTL_HTTP.end_response(l_http_response);
 END;

--this saves the clob/full JSON response into the table as a CLOB
 INSERT INTO JIRAlist VALUES (
SYS_GUID(),
SYSTIMESTAMP,
l_clob
);

 
EXCEPTION
 WHEN OTHERS THEN
   --ends request: there cannot be too many open or you will receive errors (these clear out naturally if they do occur)
   UTL_HTTP.end_response(l_http_response);
   -- Relase the resources associated with the temporary LOB.
   DBMS_LOB.freetemporary(l_clob);
   RAISE;
END load_html_from_url;
/

--this merely displays the table literally, double click the clob to read it as JSON if desired
SELECT * FROM JIRAlist;

--better displays the JIRA tickets and their linked issues, used in second file Generate_JIRA_Report.sql
--this preserves the links between tasks for easy viewing, tweaked when used in second file
SELECT tl.it_ticket, otherkey
FROM JIRAlist,
JSON_TABLE(term_document, '$.issues[*]'
COLUMNS
  (it_ticket VARCHAR2(100) PATH '$.key'
  ,NESTED PATH '$.fields.issuelinks[*]'
  COLUMNS ( otherkey PATH '$.inwardIssue.key' )
  )
  ) AS tl;
