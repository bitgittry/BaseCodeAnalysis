DROP procedure IF EXISTS `FraudRuleSetFraudClientSettings`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRuleSetFraudClientSettings`(fraudRuleTriggeredID BIGINT, OUT statusCode INT)
root: BEGIN
 
DECLARE clientID BIGINT(20) DEFAULT -1;

SET statusCode = 0; 

SELECT gaming_client_stats.client_id INTO clientID 
FROM gaming_fraud_rules_triggered 
JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_fraud_rules_triggered.client_stat_id
WHERE gaming_fraud_rules_triggered.fraud_rule_triggered_id = fraudRuleTriggeredID;


 IF (clientID = -1) THEN
	SET statusCode = 1;
    LEAVE root;
 END IF;

-- update the fraud client settings table
SET @actionName = (SELECT GROUP_CONCAT(DISTINCT(CONCAT(actions.name, '= 1'))) AS action_name
FROM gaming_fraud_rules_triggered AS rule_triggered
JOIN gaming_fraud_rule_actions_triggered AS triggered_actions ON triggered_actions.fraud_rule_triggered_id = rule_triggered.fraud_rule_triggered_id
JOIN gaming_fraud_rule_main_actions AS main_actions ON main_actions.fraud_rule_action_id = triggered_actions.fraud_rule_action_id
JOIN gaming_fraud_rule_actions AS actions ON actions.action_id = main_actions.action_id
WHERE triggered_actions.fraud_rule_triggered_id = fraudRuleTriggeredID AND triggered_actions.automatic = 0); 

IF (@actionName IS NOT NULL AND @actionName !='') THEN
    SET @sql = (SELECT CONCAT('UPDATE gaming_fraud_rule_client_settings SET ', @actionName,' WHERE client_id = ', 
	(SELECT client_id FROM gaming_client_stats
	JOIN gaming_fraud_rules_triggered ON gaming_fraud_rules_triggered.client_stat_id = gaming_client_stats.client_stat_id
	WHERE gaming_fraud_rules_triggered.fraud_rule_triggered_id = fraudRuleTriggeredID)));

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
	DEALLOCATE PREPARE stmt;
END IF;
 

-- update the dynamic client settings tables
CALL FraudRuleSaveDynamicSettings(fraudRuleTriggeredID, clientID, 0, statusCode);

 

END root$$

DELIMITER ;

