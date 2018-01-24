DROP procedure IF EXISTS `RuleUpdateEvent`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleUpdateEvent`(eventId BIGINT,event_type VARCHAR(255),event_name VARCHAR(255),sql_data TEXT, description VARCHAR(255),priority INT,
                                            tableName VARCHAR(150), is_continous TINYINT(1), OUT statusCode INT)
root:BEGIN
  
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
  IF (eventTableTemp=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SELECT event_id INTO nameExistsId FROM gaming_events WHERE gaming_events.name=event_name AND event_id!=eventId;
  IF (nameExistsId!=0) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  UPDATE gaming_events SET name = event_name, sql_data = sql_data, description = description ,
  event_type_id = eventTypeTemp, priority=priority, table_name = tableName, is_continous = is_continous
  WHERE event_id=eventId;
END$$

DELIMITER ;
