DROP procedure IF EXISTS `FraudRuleSaveHitResultForClient`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRuleSaveHitResultForClient`(fraudRuleMainID INT, clientStatID BIGINT, sessionID BIGINT, OUT statusCode INT)
root: BEGIN
 
DECLARE fraudPoints INT DEFAULT NULL;
DECLARE alterFraudPoints, modifyTestPlayers, isTestPlayer TINYINT(1) DEFAULT 0;
DECLARE clientID BIGINT(20) DEFAULT -1;
DECLARE fraudStatus TINYINT(4) DEFAULT -1;

-- fraudStatus : 
-- -1 - Expired 
--  0 - Enabled
--  1 - Testing

SELECT gaming_clients.client_id, is_test_player INTO clientID, isTestPlayer 
FROM gaming_client_stats
JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id
 WHERE client_stat_id = clientStatID;

SELECT alter_fraud_points, modify_test_users, IF(gaming_fraud_rules_statuses.status ='Enabled', 0, IF(start_test = 1 AND NOW()<=end_date, 1, -1))
INTO alterFraudPoints, modifyTestPlayers, fraudStatus  
FROM gaming_fraud_rule_main 
JOIN gaming_fraud_rules_statuses ON gaming_fraud_rules_statuses.fraud_rule_status_id = gaming_fraud_rule_main.status_id
WHERE fraud_rule_main_id = fraudRuleMainID;


IF (clientID = -1) THEN
	SET statusCode = 2;
    LEAVE root;
 END IF;

-- Don't trigger the fraud rule if it is in a testing expired.
IF (fraudStatus =-1) THEN
	SET statusCode = 0;
   LEAVE root;
END IF;

-- Don't trigger the fraud rule for test players when "Allow Modification on test players" is set to false.
IF (modifyTestPlayers = 0 AND isTestPlayer = 1) THEN
    SET statusCode = 0;
    LEAVE root;
END IF;

-- insert into the hit result table
INSERT INTO gaming_fraud_rules_triggered (fraud_rule_main_id, client_stat_id, trigger_date, test_mode) VALUES(fraudRuleMainID, clientStatID, NOW(), fraudStatus); 
SET @fraudRuleTriggeredID =  last_insert_id();

-- AUTOMATIC FRAUD POINTS (No need to alter the fraud points later only if):
-- 1. alterFraudPoints = 0;
-- 2.If the rule is in enabled mode
-- 3.If the rule is in testing mode, the player needs to be only test player 
IF (alterFraudPoints = 0 AND (fraudStatus = 0 OR (fraudStatus = 1 AND isTestPlayer = 1)))THEN

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
	UPDATE gaming_fraud_rules_triggered SET fraud_points = fraudPoints WHERE fraud_rule_triggered_id = @fraudRuleTriggeredID;
	
	-- inserts the fraud rule points for that client
	INSERT INTO gaming_fraud_rules_client_overrides (client_id, fraud_rule_id, points, session_id) 
	SELECT gaming_client_stats.client_id, fraudRuleMainID, fraudPoints, sessionID   
	FROM gaming_client_stats WHERE gaming_client_stats.client_id = clientStatID
	ON DUPLICATE KEY UPDATE points = (points + VALUES(points));

END IF;

UPDATE gaming_fraud_rule_main SET total_hits = (total_hits + 1) WHERE fraud_rule_main_id = fraudRuleMainID;


SET statusCode = 0; 
-- execute the automatic actions only if:
-- 1.If the rule is in enabled mode, the player needs to be real or the player is test player and allow modification to test is true
-- 2.If the rule is in testing mode, the player needs to be only test player and allow modifications to test player is true.
IF (fraudStatus = 0 OR (fraudStatus = 1 AND isTestPlayer = 1))THEN

	-- execute the automatic actions
	INSERT INTO gaming_fraud_rule_actions_triggered(fraud_rule_triggered_id, automatic, fraud_rule_action_id, input_value)
	SELECT  gaming_fraud_rules_triggered.fraud_rule_triggered_id, 1, main_actions.fraud_rule_action_id, main_actions.input_value
	FROM gaming_fraud_rule_actions AS actions
	JOIN gaming_fraud_rule_main_actions AS main_actions ON main_actions.action_id = actions.action_id
	JOIN gaming_fraud_rules_triggered ON gaming_fraud_rules_triggered.fraud_rule_main_id = main_actions.fraud_rule_main_id
	WHERE main_actions.is_active AND actions.is_active AND gaming_fraud_rules_triggered.fraud_rule_triggered_id = @fraudRuleTriggeredID AND main_actions.execution = 1; 

	-- save the automatic action into the client settings table for the fraud

	SET @actionName = (SELECT GROUP_CONCAT(DISTINCT(CONCAT(actions.name, '= 1'))) AS action_name
	FROM gaming_fraud_rules_triggered AS rule_triggered
	JOIN gaming_fraud_rule_actions_triggered AS triggered_actions ON triggered_actions.fraud_rule_triggered_id = rule_triggered.fraud_rule_triggered_id
	JOIN gaming_fraud_rule_main_actions AS main_actions ON main_actions.fraud_rule_action_id = triggered_actions.fraud_rule_action_id
	JOIN gaming_fraud_rule_actions AS actions ON actions.action_id = main_actions.action_id
	WHERE triggered_actions.fraud_rule_triggered_id = @fraudRuleTriggeredID); 

	IF (@actionName IS NULL OR @actionName='') THEN
		LEAVE root;
	END IF;

	SET @sql = (SELECT CONCAT('UPDATE gaming_fraud_rule_client_settings SET ', @actionName,' WHERE client_id = ', clientID));

	PREPARE stmt FROM @sql;
	EXECUTE stmt;
	DEALLOCATE PREPARE stmt;
	
	-- save into the dynamic fraud rule clients
	CALL FraudRuleSaveDynamicSettings(@fraudRuleTriggeredID, clientID, 1, statusCode);
END IF;

END root$$

DELIMITER ;

