DROP procedure IF EXISTS `SchemaGetBySchemaTableRunID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SchemaGetBySchemaTableRunID`(databaseName VARCHAR(64), schemaTableRunID BIGINT)
BEGIN
  -- Reimported procedure
  -- Added procs retrieval

  SET @databaseName=databaseName;
  SET @schemaTableRunID=schemaTableRunID;
	
  SELECT CATALOG_NAME, SCHEMA_NAME, DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME, SQL_PATH 
  FROM INFORMATION_SCHEMA.SCHEMATA 
  WHERE INFORMATION_SCHEMA.SCHEMATA.SCHEMA_NAME=@databaseName;
  
  SELECT schema_tables.TABLE_NAME, ENGINE, ROW_FORMAT, AUTO_INCREMENT, TABLE_COLLATION
  FROM INFORMATION_SCHEMA.TABLES AS schema_tables 
  JOIN gaming_schema_table_runs_tables_temp AS tables_temp ON
    tables_temp.schema_table_run_id=@schemaTableRunID AND schema_tables.TABLE_NAME=tables_temp.table_name
  WHERE schema_tables.TABLE_SCHEMA=@databaseName;
  
  SELECT schema_columns.TABLE_NAME, COLUMN_NAME, ORDINAL_POSITION, COLUMN_DEFAULT, IS_NULLABLE, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, COLUMN_TYPE, COLUMN_KEY, EXTRA, COLUMN_COMMENT
  FROM INFORMATION_SCHEMA.COLUMNS AS schema_columns
  JOIN gaming_schema_table_runs_tables_temp AS tables_temp ON
    tables_temp.schema_table_run_id=@schemaTableRunID AND schema_columns.TABLE_NAME=tables_temp.table_name
  WHERE schema_columns.TABLE_SCHEMA=@databaseName;
  
  SELECT schema_statistics.TABLE_NAME, NON_UNIQUE, INDEX_NAME, SEQ_IN_INDEX, COLUMN_NAME, SUB_PART, NULLABLE, INDEX_TYPE, INDEX_COMMENT
  FROM INFORMATION_SCHEMA.STATISTICS AS schema_statistics
  JOIN gaming_schema_table_runs_tables_temp AS tables_temp ON
    tables_temp.schema_table_run_id=@schemaTableRunID AND schema_statistics.TABLE_NAME=tables_temp.table_name
  WHERE schema_statistics.TABLE_SCHEMA=@databaseName;

  SELECT name, type, CONVERT(body USING utf8) AS body, CONVERT(param_list USING utf8) AS param_list
  FROM mysql.proc 
  WHERE db=@databaseName;

END$$

DELIMITER ;

