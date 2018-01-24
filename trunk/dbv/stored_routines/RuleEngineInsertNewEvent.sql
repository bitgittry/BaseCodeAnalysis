DROP procedure IF EXISTS `RuleEngineInsertNewEvent`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleEngineInsertNewEvent`(eventTypeId INT, eventName VARCHAR(255), description VARCHAR(2048), ruleId BIGINT, json MEDIUMTEXT, OUT statusCode INT, OUT eventId BIGINT(20))
root: BEGIN
  
  DECLARE eventTypeTemp BIGINT DEFAULT 0;
  DECLARE eventTableTemp BIGINT DEFAULT 0;
  DECLARE nameExistsId BIGINT DEFAULT 0;
  SET statusCode=0;
  
  SELECT event_type_id, event_table_id INTO eventTypeTemp, eventTableTemp FROM gaming_event_types WHERE event_type_id = eventTypeId;
  IF (eventTypeTemp=0) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (eventTableTemp=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  INSERT INTO gaming_events (event_type_id, name, description, priority, event_table_id, is_continous, rule_id, json)
  VALUES (eventTypeTemp, eventName, description, 1, eventTableTemp, 1, ruleId, json);
  
  SET eventId = LAST_INSERT_ID();
  
END$$

DELIMITER ;

