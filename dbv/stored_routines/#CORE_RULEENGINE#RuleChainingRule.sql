DROP procedure IF EXISTS `RuleChainingRule`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleChainingRule`(initialRuleId BIGINT, chainingRuleId BIGINT,continueFromLastEvent TINYINT, OUT statusCode INT)
root:BEGIN
  DECLARE validID BIGINT DEFAULT 0;
  SET statusCode=0;
  
  SELECT rule_id INTO validID FROM gaming_rules WHERE rule_id = initialRuleId;
  
  IF validID=0 THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  SET validID=0;
  
  SELECT rule_id INTO validID FROM gaming_rules WHERE rule_id = chainingRuleId;
  
  IF validID=0 THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  INSERT INTO gaming_rules_relations (current_rule_id,next_rule_id,continue_from_last_event) VALUES
  (initialRuleId,chainingRuleId,continueFromLastEvent);
  
  UPDATE gaming_rules SET has_prerequisite =1 WHERE rule_id = chainingRuleId;
	
END$$

DELIMITER ;