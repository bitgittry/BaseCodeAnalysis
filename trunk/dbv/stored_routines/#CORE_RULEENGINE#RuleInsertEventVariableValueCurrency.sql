DROP procedure IF EXISTS `RuleInsertEventVariableValueCurrency`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleInsertEventVariableValueCurrency`(ruleEventVarID BIGINT,currencyID BIGINT,currencyAmount DECIMAL,OUT statusCode INT )
root: BEGIN
  DECLARE currencyCheck BIGINT DEFAULT 0;
  DECLARE ruleEventCheck BIGINT DEFAULT 0;
  DECLARE isCurrency TINYINT DEFAULT 0;
  
  SET statusCode = 0;
 
  SELECT currency_id INTO currencyCheck FROM gaming_currency WHERE currency_id=currencyID;
  IF (currencyCheck=0) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  SELECT rule_events_var_id INTO ruleEventCheck FROM gaming_rule_events_vars WHERE rule_events_var_id=ruleEventVarID;
  IF (ruleEventCheck=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SELECT is_currency INTO isCurrency FROM gaming_events_var_types
  JOIN gaming_events_vars ON gaming_events_var_types.event_var_type_id = gaming_events_vars.event_var_type_id
  JOIN gaming_rule_events_vars ON gaming_events_vars.event_var_id = gaming_rule_events_vars.event_var_id
  WHERE rule_events_var_id = ruleEventVarID;
  
  INSERT INTO gaming_rule_events_vars_currency_value (currency_id,rule_events_var_id,value)
  VALUES (currencyCheck,ruleEventCheck,currencyAmount)
  ON DUPLICATE KEY UPDATE value=VALUES(value);
	
END$$

DELIMITER ;