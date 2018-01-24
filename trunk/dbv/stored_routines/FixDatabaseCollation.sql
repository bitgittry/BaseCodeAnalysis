DROP PROCEDURE IF EXISTS FixDatabaseCollation;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE FixDatabaseCollation(db_Schema varchar(100))
BEGIN

  DECLARE varDone TINYINT(1) DEFAULT 0;
  DECLARE tablename varchar(100);
  DECLARE stmnt varchar(500);
  DECLARE stmntCursor CURSOR FOR
    SELECT DISTINCT A.TABLE_NAME FROM (
          SELECT  t.TABLE_NAME 
            FROM information_schema.TABLES t WHERE t.TABLE_SCHEMA = db_Schema AND t.TABLE_TYPE='BASE TABLE' AND t.TABLE_COLLATION <> 'utf8_general_ci'
      UNION ALL
          select c.TABLE_NAME from information_schema.COLUMNS c WHERE ((c.CHARACTER_SET_NAME IS NOT NULL AND c.CHARACTER_SET_NAME <>'utf8') 
         ) AND c.TABLE_SCHEMA = db_Schema
      ) A;


  DECLARE CONTINUE HANDLER FOR NOT FOUND SET varDone = TRUE; 
 	OPEN stmntCursor;
  	cursor_loop: LOOP
		SET varDone=0;

		FETCH stmntCursor INTO tablename;		
		IF varDone THEN
		  LEAVE cursor_loop;
		END IF;
    SET @stmnt =CONCAT('ALTER TABLE ', tablename, ' CONVERT TO CHARACTER SET utf8 COLLATE utf8_general_ci;');
 
    PREPARE stmt1 FROM @stmnt ;

    EXECUTE stmt1;

    DEALLOCATE PREPARE stmt1;
	

	  END LOOP;
    CLOSE stmntCursor;

END
$$

DELIMITER ;