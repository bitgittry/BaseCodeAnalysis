DROP procedure IF EXISTS `RuleInsertEventVariable`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleInsertEventVariable`(eventId BIGINT,event_var_name VARCHAR(80), var_reference VARCHAR(20),default_value VARCHAR(255),non_editable TINYINT(1), OUT statusCode INT)
root: BEGIN
  DECLARE varTypeId BIGINT DEFAULT 0;
  SET statusCode = 0;
  
  SELECT event_var_type_id INTO varTypeId FROM gaming_events_var_types 
  WHERE gaming_events_var_types.name = event_var_name;
  IF (varTypeId=0) THEN
    SET statusCode = 1;
    LEAVE root;
  END IF;
  
  INSERT INTO gaming_events_vars (event_id, event_var_type_id, var_reference, default_value, non_editable)
  VALUES (eventId,varTypeId,var_reference,default_value, non_editable);
	
END$$

DELIMITER ;
