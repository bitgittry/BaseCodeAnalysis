DROP procedure IF EXISTS `RuleInsertNewEvent`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleInsertNewEvent`(event_type VARCHAR(255),event_name VARCHAR(255), description VARCHAR(255),priority INT,tableName VARCHAR(80), OUT statusCode INT,
                                                 is_continous TINYINT(1), OUT eventId BIGINT(20))
root: BEGIN
  
  
  
  DECLARE eventTypeTemp BIGINT DEFAULT 0;
  DECLARE eventTableTemp BIGINT DEFAULT 0;
  DECLARE nameExistsId BIGINT DEFAULT 0;
  SET statusCode=0;
  
  SELECT event_type_id INTO eventTypeTemp FROM gaming_event_types WHERE name=event_type;
  IF (eventTypeTemp=0) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  SELECT event_table_id INTO eventTableTemp FROM gaming_event_tables WHERE table_name=tableName;
  IF (eventTypeTemp=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SELECT event_id INTO nameExistsId FROM gaming_events WHERE gaming_events.name=event_name;
  IF (nameExistsId!=0) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  
	INSERT INTO gaming_events (event_type_id,name,description,priority,event_table_id,is_continous)
  VALUES (eventTypeTemp,event_name,description,priority,eventTableTemp,is_continous);
  
  SET eventId = LAST_INSERT_ID();
  
END$$

DELIMITER ;
