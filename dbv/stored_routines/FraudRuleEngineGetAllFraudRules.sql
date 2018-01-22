DROP procedure IF EXISTS `FraudRuleEngineGetAllFraudRules`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRuleEngineGetAllFraudRules`(fraudRuleID INT)
root: BEGIN

	SELECT gaming_fraud_rule_main.fraud_rule_main_id, gaming_fraud_rule_main.name, description, status_id, fraud_level_id, notification_method_id, fraud_category_id, 
	trigger_id, occurrence_id,   last_modified_date, last_modified_user_id, last_modified_user.username AS 'last_modified_user', create_date, create_user_id, 
	create_user.username AS 'create_user', test_successful, test_approved_by_user_id, test_approved_by_user.username AS 'test_approved_by_user', enabled_date, 
	enabled_by_user_id, enabled_by_user.username AS 'enabled_by_user', disabled_date, disabled_by_user_id, disabled_by_user.username AS 'disabled_by_user', 
	total_fraud_rule_checks, total_hits, is_hidden, major_version, sub_version, rule_json, start_date, end_date, alter_fraud_points, modify_test_users, start_test 
	FROM gaming_fraud_rule_main

	LEFT JOIN users_main last_modified_user
	ON gaming_fraud_rule_main.last_modified_user_id = last_modified_user.user_id

	LEFT JOIN users_main create_user
	ON gaming_fraud_rule_main.create_user_id = create_user.user_id

	LEFT JOIN users_main test_approved_by_user
	ON gaming_fraud_rule_main.test_approved_by_user_id = test_approved_by_user.user_id

	LEFT JOIN users_main enabled_by_user
	ON gaming_fraud_rule_main.enabled_by_user_id = enabled_by_user.user_id

	LEFT JOIN users_main disabled_by_user
	ON gaming_fraud_rule_main.disabled_by_user_id = disabled_by_user.user_id

	JOIN gaming_fraud_rule_main_sql ON gaming_fraud_rule_main.fraud_rule_main_id = gaming_fraud_rule_main_sql.fraud_rule_main_id
	WHERE (fraudRuleID=0 OR fraudRuleID=gaming_fraud_rule_main.fraud_rule_main_id) AND is_hidden = 0;

	SELECT fraud_rule_action_id, actions.action_id, gaming_fraud_rule_main_actions.fraud_rule_main_id, gaming_fraud_rule_main_actions.execution, actions.is_active, gaming_fraud_rule_main_actions.input_value
	FROM gaming_fraud_rule_main_actions 
    JOIN gaming_fraud_rule_actions AS actions ON actions.action_id = gaming_fraud_rule_main_actions.action_id
	WHERE (fraudRuleID = 0 OR fraudRuleID=gaming_fraud_rule_main_actions.fraud_rule_main_id) AND gaming_fraud_rule_main_actions.is_active = 1;

	SELECT fraud_rule_id, client_segment_id, points
	FROM gaming_fraud_rules_client_segments_points
	WHERE fraudRuleID = 0 OR fraudRuleID=fraud_rule_id;

END root$$

DELIMITER ;

