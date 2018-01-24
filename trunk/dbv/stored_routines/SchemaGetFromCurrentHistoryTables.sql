DROP procedure IF EXISTS `SchemaGetFromCurrentHistoryTables`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SchemaGetFromCurrentHistoryTables`(
  databaseName VARCHAR(64), sessionID BIGINT)
BEGIN

  -- Reimported procedure

  SET @databaseName = databaseName;
  SET @sessionID = sessionID;
  INSERT INTO gaming_schema_table_runs(date_created, session_id) VALUES (NOW(), @sessionID);
  SET @schemaTableRunID=LAST_INSERT_ID();
  
  INSERT INTO gaming_schema_table_runs_tables_temp (schema_table_run_id, table_name)
  SELECT @schemaTableRunID, schema_tables.TABLE_NAME
  FROM INFORMATION_SCHEMA.TABLES AS schema_tables 
  WHERE schema_tables.TABLE_SCHEMA=@databaseName AND schema_tables.TABLE_NAME LIKE 'history_%';
  
  CALL SchemaGetBySchemaTableRunID(@databaseName, @schemaTableRunID);

END$$

DELIMITER ;

