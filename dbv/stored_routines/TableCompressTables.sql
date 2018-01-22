DROP procedure IF EXISTS `TableCompressTables`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TableCompressTables`(dbName VARCHAR(128))
BEGIN

    -- Keep only in DBV

	DECLARE tableName, rowFormat, dbName VARCHAR(128);
	DECLARE blockSizeCurrent, blockSizeNew INT;
    DECLARE tableFullPath VARCHAR(256);
	DECLARE noMoreRecords TINYINT(1) DEFAULT 0;
	
	DECLARE tablesCursor CURSOR FOR 
		SELECT `table_name`, block_size FROM gaming_table_for_compression WHERE is_compressed=0;
	  DECLARE CONTINUE HANDLER FOR NOT FOUND
		SET noMoreRecords = 1;
    
    SET dbName = IFNULL(dbName, DATABASE());

	OPEN tablesCursor;
	tablesLabel: LOOP 
    
		SET noMoreRecords=0;
		FETCH tablesCursor INTO tableName, blockSizeNew;
		IF (noMoreRecords) THEN
		  LEAVE tablesLabel;
		END IF;
	  
      
		SET tableFullPath=CONCAT(dbName, '/', tableName);

		SELECT ROW_FORMAT, ZIP_PAGE_SIZE/1024 
		INTO rowFormat, blockSizeCurrent
		FROM INFORMATION_SCHEMA.INNODB_SYS_TABLES 
		WHERE NAME=tableFullPath; 

		IF (rowFormat!='Compressed' OR blockSizeNew!=blockSizeCurrent) THEN

			SET @alterStatement=CONCAT('ALTER TABLE ', dbName, '.', tableName, ' ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=', blockSizeNew, ', ALGORITHM=INPLACE, LOCK = NONE;');
			
            PREPARE stmt1 FROM @alterStatement;
			EXECUTE stmt1;
			DEALLOCATE PREPARE stmt1;

		END IF;

		UPDATE gaming_table_for_compression SET is_compressed=1 WHERE `table_name`=tableName;

	END LOOP tablesLabel;
	CLOSE tablesCursor;

END$$

DELIMITER ;

