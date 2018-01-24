DROP procedure IF EXISTS `RuleAddEventToRule`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleAddEventToRule`(ruleId BIGINT, eventId BIGINT, OUT statusCode INT, OUT ruleEventId BIGINT)
root: BEGIN
  DECLARE ruleIDCheck BIGINT DEFAULT 0;
  DECLARE eventIDCheck BIGINT DEFAULT 0;
  DECLARE existsInRule BIGINT DEFAULT 0;
  SET statusCode=0;
  SELECT rule_id INTO ruleIDCheck FROM gaming_rules WHERE rule_id = ruleId;
  IF (ruleIDCheck=0) THEN
    SET statusCode =1;
    LEAVE root;
  END IF;
  SELECT event_id INTO eventIDCheck FROM gaming_events WHERE event_id = eventId;
  IF (eventIDCheck=0) THEN
    SET statusCode =2;
    LEAVE root;
  END IF;

 
  
  
 
  INSERT INTO gaming_rules_events (rule_id,event_id) VALUES (ruleId, eventId);
  SET ruleEventId=LAST_INSERT_ID();
END$$

DELIMITER ;