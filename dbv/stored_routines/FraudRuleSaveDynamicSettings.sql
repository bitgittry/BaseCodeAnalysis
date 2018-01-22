
DROP procedure IF EXISTS `FraudRuleSaveDynamicSettings`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRuleSaveDynamicSettings`(fraudRuleTriggeredID BIGINT, clientID BIGINT, automatic TINYINT(1), OUT statusCode INT)
root: BEGIN

DECLARE disableLogin, disablePMGroup, disablePM, disablePromo TINYINT(1) DEFAULT 0;

SELECT disable_login, disable_pm_group, disable_pm, disable_promo_contact INTO disableLogin, disablePMGroup, disablePM, disablePromo
FROM gaming_fraud_rule_client_settings WHERE client_id = clientID;

SET statusCode = 0; 
IF (disableLogin = 1) THEN

	INSERT INTO gaming_fraud_rule_disable_login_settings(client_id, platform_type_id, setting_value)
	SELECT clientID, actions.extra_id, 1
	FROM gaming_fraud_rules_triggered AS rule_triggered
	JOIN gaming_fraud_rule_actions_triggered AS triggered_actions ON triggered_actions.fraud_rule_triggered_id = rule_triggered.fraud_rule_triggered_id
	JOIN gaming_fraud_rule_main_actions AS main_actions ON main_actions.fraud_rule_action_id = triggered_actions.fraud_rule_action_id
	JOIN gaming_fraud_rule_actions AS actions ON actions.action_id = main_actions.action_id
	JOIN gaming_fraud_rule_dynamic_action_types AS actionTypes ON actionTypes.dynamic_action_type_id = actions.dynamic_action_type_id
	WHERE triggered_actions.fraud_rule_triggered_id = fraudRuleTriggeredID AND actionTypes.table_name = 'gaming_platform_types' AND triggered_actions.automatic = automatic
	ON DUPLICATE KEY UPDATE setting_value = 1; 

END IF;

IF (disablePMGroup = 1) THEN

	INSERT INTO gaming_fraud_rule_disable_pmgroup_settings(client_id, payment_method_group_id, setting_value)
	SELECT clientID, actions.extra_id, 1
	FROM gaming_fraud_rules_triggered AS rule_triggered
	JOIN gaming_fraud_rule_actions_triggered AS triggered_actions ON triggered_actions.fraud_rule_triggered_id = rule_triggered.fraud_rule_triggered_id
	JOIN gaming_fraud_rule_main_actions AS main_actions ON main_actions.fraud_rule_action_id = triggered_actions.fraud_rule_action_id
	JOIN gaming_fraud_rule_actions AS actions ON actions.action_id = main_actions.action_id
	JOIN gaming_fraud_rule_dynamic_action_types AS actionTypes ON actionTypes.dynamic_action_type_id = actions.dynamic_action_type_id
	WHERE triggered_actions.fraud_rule_triggered_id = fraudRuleTriggeredID AND actionTypes.table_name = 'gaming_payment_method_groups' AND triggered_actions.automatic = automatic
	ON DUPLICATE KEY UPDATE setting_value = 1; 

END IF;

IF (disablePM = 1) THEN

	INSERT INTO gaming_fraud_rule_disable_pm_settings(client_id, payment_method_id, setting_value)
	SELECT clientID, actions.extra_id, 1
	FROM gaming_fraud_rules_triggered AS rule_triggered
	JOIN gaming_fraud_rule_actions_triggered AS triggered_actions ON triggered_actions.fraud_rule_triggered_id = rule_triggered.fraud_rule_triggered_id
	JOIN gaming_fraud_rule_main_actions AS main_actions ON main_actions.fraud_rule_action_id = triggered_actions.fraud_rule_action_id
	JOIN gaming_fraud_rule_actions AS actions ON actions.action_id = main_actions.action_id
	JOIN gaming_fraud_rule_dynamic_action_types AS actionTypes ON actionTypes.dynamic_action_type_id = actions.dynamic_action_type_id
	WHERE triggered_actions.fraud_rule_triggered_id = fraudRuleTriggeredID AND actionTypes.table_name = 'gaming_payment_method' AND triggered_actions.automatic = automatic
	ON DUPLICATE KEY UPDATE setting_value = 1; 

END IF;

IF (disablePromo = 1) THEN

	INSERT INTO gaming_fraud_rule_disable_promo_settings(client_id, communication_type_id, setting_value)
	SELECT clientID, actions.extra_id, 1
	FROM gaming_fraud_rules_triggered AS rule_triggered
	JOIN gaming_fraud_rule_actions_triggered AS triggered_actions ON triggered_actions.fraud_rule_triggered_id = rule_triggered.fraud_rule_triggered_id
	JOIN gaming_fraud_rule_main_actions AS main_actions ON main_actions.fraud_rule_action_id = triggered_actions.fraud_rule_action_id
	JOIN gaming_fraud_rule_actions AS actions ON actions.action_id = main_actions.action_id
	JOIN gaming_fraud_rule_dynamic_action_types AS actionTypes ON actionTypes.dynamic_action_type_id = actions.dynamic_action_type_id
	WHERE triggered_actions.fraud_rule_triggered_id = fraudRuleTriggeredID AND actionTypes.table_name = 'gaming_communication_types' AND triggered_actions.automatic = automatic
	ON DUPLICATE KEY UPDATE setting_value = 1; 

END IF;

END root$$

DELIMITER ;

