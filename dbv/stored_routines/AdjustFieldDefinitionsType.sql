DROP procedure IF EXISTS `AdjustFieldDefinitionsType`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `AdjustFieldDefinitionsType`()
BEGIN
-- Committing to DBV
	DECLARE v_fieldName VARCHAR(80);
	DECLARE v_finished INT DEFAULT 0;

	DECLARE v_fieldDefinitionsCursor CURSOR FOR 
		SELECT field_name 
		FROM gaming_field_definitions;

	DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_finished = 1;

	OPEN v_fieldDefinitionsCursor;

	add_all_definitions: LOOP
    SET v_finished = 0;
		FETCH v_fieldDefinitionsCursor INTO v_fieldName;

		IF (v_finished = 1) THEN
			LEAVE add_all_definitions;
		END IF;

		INSERT INTO gaming_field_definitions (field_definition_type_id, field_name, is_unique, is_required, is_enabled)
		SELECT definition_types.field_definition_type_id, v_fieldName, 0, 0, 0
		FROM gaming_field_definition_types AS definition_types
		WHERE definition_types.field_definition_type_id NOT IN
			(SELECT gaming_field_definitions.field_definition_type_id 
				FROM gaming_field_definitions 
				WHERE gaming_field_definitions.field_name = v_fieldName);

	END LOOP add_all_definitions;

	CLOSE v_fieldDefinitionsCursor;

END$$

DELIMITER ;
