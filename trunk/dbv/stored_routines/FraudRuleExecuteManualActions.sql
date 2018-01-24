DROP procedure IF EXISTS `FraudRuleExecuteManualActions`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRuleExecuteManualActions`(fraudRuleTriggeredID BIGINT, userID BIGINT, sessionID BIGINT, OUT statusCode INT)
root: BEGIN
 
DECLARE fraudPoints INT DEFAULT NULL;
DECLARE alterFraudPoints, isTestPlayer, isRuleInTestMode, modifyTestPlayers TINYINT(1) DEFAULT 0;
DECLARE clientStatID BIGINT DEFAULT 0;
DECLARE fraudRuleMainID INT DEFAULT 0;
DECLARE clientID BIGINT(20) DEFAULT -1;

SELECT gaming_fraud_rule_main.alter_fraud_points, gaming_fraud_rules_triggered.client_stat_id, gaming_fraud_rules_triggered.fraud_rule_main_id, gaming_fraud_rules_triggered.test_mode, modify_test_users
INTO alterFraudPoints, clientStatID, fraudRuleMainID, isRuleInTestMode, modifyTestPlayers
FROM gaming_fraud_rule_main
JOIN gaming_fraud_rules_triggered ON gaming_fraud_rules_triggered.fraud_rule_main_id = gaming_fraud_rule_main.fraud_rule_main_id
WHERE gaming_fraud_rules_triggered.fraud_rule_triggered_id = fraudRuleTriggeredID;

SELECT gaming_client_stats.client_id, gaming_clients.is_test_player INTO clientID, isTestPlayer 
FROM gaming_client_stats 
JOIN gaming_clients ON gaming_client_stats.client_id = gaming_clients.client_id
WHERE client_stat_id = clientStatID;

 IF (clientID = -1) THEN
	SET statusCode = 2;
    LEAVE root;
 END IF;
-- We can not execute the actions if:
-- Fraud is in test mode and is for real player
-- Fraud is in test mode, test player but allow modifications on test player is set to false
-- Fraud is in enabled mode, test player and allow modifications on test player is set to false
IF ((isRuleInTestMode = 1 AND (isTestPlayer = 0 OR (isTestPlayer = 1 AND modifyTestPlayers = 0)) ) OR (isRuleInTestMode = 0 AND isTestPlayer = 1 AND modifyTestPlayers = 0 )) THEN
	SET statusCode = 3;
    LEAVE root;
END IF;

INSERT INTO gaming_fraud_rule_actions_triggered(fraud_rule_triggered_id, automatic, fraud_rule_action_id, input_value)
SELECT  gaming_fraud_rules_triggered.fraud_rule_triggered_id, 0, main_actions.fraud_rule_action_id, main_actions.input_value
FROM gaming_fraud_rule_actions AS actions
JOIN gaming_fraud_rule_main_actions AS main_actions ON main_actions.action_id = actions.action_id
JOIN gaming_fraud_rules_triggered ON gaming_fraud_rules_triggered.fraud_rule_main_id = main_actions.fraud_rule_main_id
WHERE gaming_fraud_rules_triggered.fraud_rule_triggered_id = fraudRuleTriggeredID AND main_actions.execution = 2 AND main_actions.is_active = 1 AND actions.is_active = 1; 

-- update the fraud client settings table
SET @actionName = (SELECT GROUP_CONCAT(DISTINCT(CONCAT(actions.name, '= 1'))) AS action_name
FROM gaming_fraud_rules_triggered AS rule_triggered
JOIN gaming_fraud_rule_actions_triggered AS triggered_actions ON triggered_actions.fraud_rule_triggered_id = rule_triggered.fraud_rule_triggered_id
JOIN gaming_fraud_rule_main_actions AS main_actions ON main_actions.fraud_rule_action_id = triggered_actions.fraud_rule_action_id
JOIN gaming_fraud_rule_actions AS actions ON actions.action_id = main_actions.action_id
WHERE triggered_actions.fraud_rule_triggered_id = fraudRuleTriggeredID AND triggered_actions.automatic = 0); 

IF (@actionName IS NOT NULL AND @actionName !='') THEN
    SET @sql = (SELECT CONCAT('UPDATE gaming_fraud_rule_client_settings SET ', @actionName,' WHERE client_id = ', clientID));

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
	DEALLOCATE PREPARE stmt;
END IF;

-- they were not saved when the trigger was hit
IF (alterFraudPoints = 1) THEN

   SELECT segment_points.points INTO fraudPoints 
   FROM gaming_fraud_rules_client_segments_points AS segment_points
   JOIN gaming_clients ON gaming_clients.client_segment_id = segment_points.client_segment_id
   JOIN gaming_client_stats ON gaming_client_stats.client_id = gaming_clients.client_id
   WHERE gaming_client_stats.client_stat_id = clientStatID AND segment_points.fraud_rule_id = fraudRuleMainID;

   IF (fraudPoints IS NULL)  THEN
		SET statusCode=1;
		LEAVE root;
   END IF;

 -- update the hit result table(gaming_fraud_rules_triggered) with the fraud points
	UPDATE gaming_fraud_rules_triggered SET fraud_points = fraudPoints WHERE fraud_rule_triggered_id = fraudRuleTriggeredID;
	
	-- inserts the fraud rule points for that client
	INSERT INTO gaming_fraud_rules_client_overrides (client_id, fraud_rule_id, points, session_id) 
	SELECT gaming_client_stats.client_id, fraudRuleMainID, fraudPoints, sessionID   
	FROM gaming_client_stats WHERE gaming_client_stats.client_id = clientStatID
	ON DUPLICATE KEY UPDATE points = (points + VALUES(points));
END IF;

-- update the hit result record for that client_id
UPDATE gaming_fraud_rules_triggered
SET user_trigger_date = NOW(), triggered_by_user_id = userID
WHERE fraud_rule_triggered_id = fraudRuleTriggeredID;

 -- save into the dynamic fraud rule clients
CALL FraudRuleSaveDynamicSettings(fraudRuleTriggeredID, clientID, 0, statusCode);
	
SET statusCode = 0;   
END root$$

DELIMITER ;

