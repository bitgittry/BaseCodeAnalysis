DROP procedure IF EXISTS `cleanDuplicateClientAccessChangeTypes`;
DROP procedure IF EXISTS `CleanDuplicateClientAccessChangeTypes`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CleanDuplicateClientAccessChangeTypes`()
BEGIN

	DECLARE v_changeTypeID BIGINT DEFAULT 0;
	DECLARE v_finished INT DEFAULT 0;
  
	DECLARE v_clientAccessCursor CURSOR FOR 
		SELECT client_access_change_type_id 
		FROM gaming_client_access_change_types
		WHERE description IN (SELECT description FROM gaming_client_access_change_types 
			GROUP BY description 
			HAVING count(description) > 1 AND MIN(client_access_change_type_id) <> client_access_change_type_id);

	DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_finished = 1;

	OPEN v_clientAccessCursor;

	delete_change_type: LOOP
    SET v_finished = 0;
		FETCH v_clientAccessCursor INTO v_changeTypeID;

		IF (v_finished = 1) THEN
			LEAVE delete_change_type;
		END IF;

		DELETE FROM gaming_client_access_change_types
		WHERE client_access_change_type_id = v_changeTypeID;

	END LOOP delete_change_type;

	CLOSE v_clientAccessCursor;

END$$

DELIMITER ;

CALL CleanDuplicateClientAccessChangeTypes;
