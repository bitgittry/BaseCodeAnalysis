DROP procedure IF EXISTS `FraudRuleExecuteAlteredManualData`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRuleExecuteAlteredManualData`(fraudRuleTriggeredID BIGINT, userID BIGINT, executeReason NVARCHAR(255), fraudPoints INT, sessionID BIGINT, OUT statusCode INT)
root: BEGIN

DECLARE alterFraudPoints, isTestPlayer, isRuleInTestMode, modifyTestPlayers TINYINT(1) DEFAULT 0;

SELECT gaming_fraud_rule_main.alter_fraud_points, gaming_fraud_rules_triggered.test_mode, gaming_clients.is_test_player, modify_test_users
INTO alterFraudPoints, isRuleInTestMode, isTestPlayer, modifyTestPlayers
FROM gaming_fraud_rule_main
JOIN gaming_fraud_rules_triggered ON gaming_fraud_rules_triggered.fraud_rule_main_id = gaming_fraud_rule_main.fraud_rule_main_id
JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_fraud_rules_triggered.client_stat_id
JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id
WHERE gaming_fraud_rules_triggered.fraud_rule_triggered_id = fraudRuleTriggeredID;

-- We can not execute the manual actions if:
-- The Fraud is in test mode and is for real player
-- The Fraud is in test mode, test player but allow modifications on test player is set to false
-- The Fraud is in enabled mode, test player and allow modifications on test player is set to false
IF ((isRuleInTestMode = 1 AND (isTestPlayer = 0 OR (isTestPlayer = 1 AND modifyTestPlayers = 0)) ) OR (isRuleInTestMode = 0 AND isTestPlayer = 1 AND modifyTestPlayers = 0 )) THEN
	
	SET statusCode = 3;
    LEAVE root;
END IF;

-- update the hit result table with the new results 
UPDATE gaming_fraud_rules_triggered
SET user_trigger_date = NOW(), triggered_by_user_id = userID, reason = executeReason, fraud_points = IF(alterFraudPoints = 1, fraudPoints, fraud_points) 
WHERE fraud_rule_triggered_id = fraudRuleTriggeredID;

IF (alterFraudPoints = 1) THEN

-- update the client_overrides(fraud points)	
INSERT INTO gaming_fraud_rules_client_overrides (client_id, fraud_rule_id, points, session_id) 
SELECT gaming_client_stats.client_id, gaming_fraud_rules_triggered.fraud_rule_main_id, fraudPoints, sessionID
FROM gaming_fraud_rules_triggered
JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_fraud_rules_triggered.client_stat_id
WHERE gaming_fraud_rules_triggered.fraud_rule_triggered_id = fraudRuleTriggeredID
ON DUPLICATE KEY UPDATE points = (points + VALUES(points));

END IF;

SET statusCode = 0;   
END root$$

DELIMITER ;

