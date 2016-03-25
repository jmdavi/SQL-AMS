--returns tables recently updated in database
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SELECT OBJECT_NAME(OBJECT_ID) AS TableName, last_user_update,*
FROM sys.dm_db_index_usage_stats s
WHERE database_id = DB_ID()
AND last_user_update>DATEADD(MINUTE, -5,SYSDATETIME())
--alternative dateparts listed at https://msdn.microsoft.com/en-us/library/ms186819.aspx
ORDER BY s.last_user_update DESC
