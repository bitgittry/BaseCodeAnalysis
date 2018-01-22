DROP procedure IF EXISTS `RuleInsertActionVariable`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleInsertActionVariable`(ruleActionId BIGINT, action_var_name VARCHAR(80),value TEXT,OUT statusCode INT,OUT ruleVarActionId BIGINT )
root: BEGIN
	
	-- 3 Rule_Invalid_Is_Not_FreeRound
	-- 4 Rule_Invalid_Is_FreeRound
	
  DECLARE actionVarTypeId BIGINT DEFAULT 0;
  DECLARE actionId BIGINT DEFAULT 0;
  DECLARE ruleActionVarType, ruleActionType VARCHAR(40);
  SET statusCode = 0;
  
  SELECT gaming_rule_action_types_var_types.rule_action_type_var_id, gaming_rule_action_types_var_types.name,
	gaming_rule_actions.rule_action_id, gaming_rule_action_types.name
  INTO actionVarTypeId, ruleActionVarType, actionId, ruleActionType
  FROM gaming_rule_actions
  STRAIGHT_JOIN gaming_rule_action_types ON gaming_rule_actions.rule_action_type_id=gaming_rule_action_types.rule_action_type_id
  STRAIGHT_JOIN gaming_rule_action_types_var_types ON 
	gaming_rule_action_types_var_types.rule_action_type_id = gaming_rule_actions.rule_action_type_id
      AND gaming_rule_action_types_var_types.rule_action_type_var_id NOT IN 
          (SELECT gaming_rule_action_types_var_types.rule_action_type_var_id 
			FROM gaming_rule_action_types_var_types
            STRAIGHT_JOIN gaming_rule_action_vars ON gaming_rule_action_vars.rule_action_type_var_id = gaming_rule_action_types_var_types.rule_action_type_var_id
            STRAIGHT_JOIN gaming_rule_actions ON gaming_rule_actions.rule_action_id = gaming_rule_action_vars.rule_action_id
            WHERE gaming_rule_actions.rule_action_id=ruleActionId)
  WHERE gaming_rule_actions.rule_action_id = ruleActionId AND gaming_rule_action_types_var_types.name=action_var_name;
  
  IF (actionVarTypeId=0) THEN
    SET statusCode=1;
    LEAVE root;
  ELSEIF (actionId=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  IF (ruleActionVarType='BonusRuleID') THEN
  
	  -- 2. check if action name is FreeRound
		IF (ruleActionType='FreeRound') THEN
			-- check that bonus rule is indeed a trigger Free round bonus, if its not return statuscode 2	
			IF ((SELECT IFNULL(is_free_rounds, 0) FROM gaming_bonus_rules WHERE bonus_rule_id = CAST(value AS SIGNED INTEGER)) = 0) THEN
				SET statusCode=3;
				LEAVE root;
			END IF;
			
		ELSEIF (ruleActionType='BONUS') THEN
			-- check that bonus rule is not a trigger Free round bonus, if it is return status code 3
			IF ((SELECT IFNULL(is_free_rounds, 0) FROM gaming_bonus_rules WHERE bonus_rule_id = CAST(value AS SIGNED INTEGER)) = 1) THEN
				SET statusCode=4;
				LEAVE root;
			END IF;

		END IF;	
        
  END IF;
  
  INSERT INTO gaming_rule_action_vars (rule_action_id,rule_action_type_var_id,value) VALUES (actionId,actionVarTypeId,value);
  SET ruleVarActionId = LAST_INSERT_ID();
END root$$

DELIMITER ;

