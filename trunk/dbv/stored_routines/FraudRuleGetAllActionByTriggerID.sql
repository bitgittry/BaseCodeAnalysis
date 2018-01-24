DROP procedure IF EXISTS `FraudRuleGetAllActionByTriggerID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRuleGetAllActionByTriggerID`(triggerID INT(11))
BEGIN
  
SELECT actions.action_id, actions.name, actions.display_name, actions.dynamic_action_type_id, 
actions.has_input, actions.input_type, actions.input_sql, gaming_fraud_rule_trigger_actions.is_automatic, actions.extra_id, actions.is_active
FROM gaming_fraud_rule_actions AS actions
JOIN gaming_fraud_rule_trigger_actions ON gaming_fraud_rule_trigger_actions.action_id = actions.action_id
WHERE gaming_fraud_rule_trigger_actions.trigger_id = triggerID
ORDER BY actions.action_id;
  
END$$

DELIMITER ;

