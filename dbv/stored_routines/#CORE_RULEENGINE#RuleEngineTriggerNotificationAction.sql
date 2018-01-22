DROP procedure IF EXISTS `RuleEngineTriggerNotificationAction`;
DELIMITER $$

CREATE PROCEDURE `RuleEngineTriggerNotificationAction` ()
BEGIN

DECLARE notificationEnabled TINYINT(1) DEFAULT 0;

	SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';

	IF (1 = notificationEnabled) THEN 
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
		SELECT 623, gaming_rules_instances.rule_instance_id , value, 0
	FROM gaming_rule_action_vars
    JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id = gaming_rule_action_vars.rule_action_type_var_id
    JOIN gaming_rule_action_types ON gaming_rule_action_types.rule_action_type_id = gaming_rule_action_types_var_types.rule_action_type_id
    JOIN gaming_rule_actions ON gaming_rule_action_vars.rule_action_id = gaming_rule_actions.rule_action_id
    JOIN gaming_rules_instances ON gaming_rules_instances.rule_id = gaming_rule_actions.rule_id
    JOIN gaming_rules_to_award ON gaming_rules_to_award.rule_instance_id = gaming_rules_instances.rule_instance_id  AND awarded_state=2
    WHERE gaming_rule_action_types.name='Notification' GROUP BY gaming_rules_instances.rule_instance_id,value;
    END IF;


END $$
DELIMITER ;