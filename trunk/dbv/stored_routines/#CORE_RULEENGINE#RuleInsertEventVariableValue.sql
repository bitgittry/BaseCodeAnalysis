DROP procedure IF EXISTS `RuleInsertEventVariableValue`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleInsertEventVariableValue`(ruleEventID BIGINT, eventVarId BIGINT, value VARCHAR(255), OUT rule_events_var_id INT, OUT statusCode INT)
root: BEGIN
  DECLARE ruleEventIDCheck, eventVarIDCheck BIGINT DEFAULT -1;
  DECLARE existsCheck BIGINT DEFAULT 0;
  SET statusCode =0;
  SELECT rule_event_id INTO ruleEventIDCheck FROM gaming_rules_events WHERE rule_event_id=ruleEventID;
  IF (ruleEventIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  SELECT event_var_id INTO eventVarIDCheck FROM gaming_events_vars WHERE event_var_id=eventVarID;
  IF (eventVarIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  INSERT INTO gaming_rule_events_vars (rule_event_id, event_var_id, value) 
  VALUES (ruleEventID, eventVarId, value)
  ON DUPLICATE KEY UPDATE value=VALUES(value);
  
  SET rule_events_var_id = LAST_INSERT_ID();
	
END$$

DELIMITER ;
