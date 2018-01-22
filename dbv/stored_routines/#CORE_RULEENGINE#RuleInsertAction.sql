DROP procedure IF EXISTS `RuleInsertAction`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleInsertAction`(ruleId BIGINT, action_name VARCHAR(80),awardReferral TINYINT(1),OUT actionID BIGINT ,OUT statusCode INT )
root: BEGIN
  DECLARE actionTypeId BIGINT DEFAULT 0;
  SET statusCode = 0;
  
  -- 1. get action ID from table by name
  SELECT rule_action_type_id INTO actionTypeId FROM gaming_rule_action_types WHERE name = action_name;
  
  IF (actionTypeId=0) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  -- 2. valid and insert action rule
  INSERT INTO gaming_rule_actions (rule_id,rule_action_type_id,award_referral) VALUES (ruleID,actionTypeId,awardReferral);
  
  SET actionID = LAST_INSERT_ID();
	
END root$$

DELIMITER ;