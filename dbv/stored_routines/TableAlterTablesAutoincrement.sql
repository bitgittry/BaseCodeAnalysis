DROP procedure IF EXISTS `TableAlterTablesAutoincrement`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TableAlterTablesAutoincrement`(dbName VARCHAR(128))
BEGIN

    -- Keep only in DBV

	DECLARE tableName, dataType, dbName VARCHAR(128);
	DECLARE autoIncrementCurrent, autoIncrementNew, numericPrecision BIGINT;
	DECLARE noMoreRecords, isValidAutoInc, isValidPK TINYINT(1) DEFAULT 0;
	
	DECLARE tablesCursor CURSOR FOR 
		SELECT `table_name` FROM gaming_table_group_tables WHERE table_group_id=1 AND is_processed=0;
	  DECLARE CONTINUE HANDLER FOR NOT FOUND
		SET noMoreRecords = 1;
    
    SET dbName = IFNULL(dbName, DATABASE());

	OPEN tablesCursor;
	tablesLabel: LOOP 
    
		SET noMoreRecords=0;
		FETCH tablesCursor INTO tableName;
		IF (noMoreRecords) THEN
		  LEAVE tablesLabel;
		END IF;
        
        SELECT 1, AUTO_INCREMENT 
        INTO isValidAutoInc, autoIncrementCurrent 
        FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_SCHEMA=dbName AND TABLE_NAME=tableName;

		SELECT 1, DATA_TYPE, NUMERIC_PRECISION 
        INTO isValidPK, dataType, numericPrecision
        FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_SCHEMA=dbName AND TABLE_NAME=tableName AND COLUMN_KEY='PRI' AND EXTRA='auto_increment';

		IF (isValidAutoInc AND isValidPK) THEN

			SET autoIncrementNew=POW(10, FLOOR(numericPrecision/2.0)+1)+1;

			IF (autoIncrementNew>autoIncrementCurrent) THEN 

				SET @alterStatement=CONCAT('ALTER TABLE ', dbName, '.', tableName, ' AUTO_INCREMENT=', autoIncrementNew, ';');
				
				PREPARE stmt1 FROM @alterStatement;
				EXECUTE stmt1;
				DEALLOCATE PREPARE stmt1;

				UPDATE gaming_table_group_tables SET is_processed=1 WHERE table_group_id=1 AND `table_name`=tableName;

            END IF;
            
		END IF;

	END LOOP tablesLabel;
	CLOSE tablesCursor;

END$$

DELIMITER ;

