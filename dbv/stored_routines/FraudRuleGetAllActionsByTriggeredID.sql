DROP procedure IF EXISTS `FraudRuleGetAllActionsByTriggeredID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRuleGetAllActionsByTriggeredID`(fraudRuleTriggeredID BIGINT, OUT statusCode INT)
root: BEGIN
  
DECLARE ExecutionFinished, modifyTestPlayers, IsTestPlayer TINYINT(1) DEFAULT 0;
DECLARE FraudRuleID, numManualActions INT DEFAULT 0;
DECLARE fraudStatus TINYINT(4) DEFAULT -1;

-- get the fraud rule id
SELECT fraud_rule_main_id,  gaming_clients.is_test_player INTO FraudRuleID, IsTestPlayer
FROM gaming_fraud_rules_triggered
JOIN gaming_client_stats ON gaming_fraud_rules_triggered.client_stat_id =gaming_client_stats.client_stat_id
JOIN gaming_clients ON gaming_client_stats.client_id = gaming_clients.client_id
WHERE fraud_rule_triggered_id =  fraudRuleTriggeredID;

-- fraudStatus : 
-- -1 - Expired 
--  0 - Enabled
--  1 - Testing

SELECT modify_test_users, IF(gaming_fraud_rules_statuses.status ='Enabled', 0, IF(start_test = 1 AND NOW()<=end_date, 1, -1))
INTO modifyTestPlayers, fraudStatus  
FROM gaming_fraud_rule_main 
JOIN gaming_fraud_rules_statuses ON gaming_fraud_rules_statuses.fraud_rule_status_id = gaming_fraud_rule_main.status_id
WHERE fraud_rule_main_id = FraudRuleID;

-- IF allow modification of test players is set to false and the player is test player, the fraud rule should not be triggered and not actions/fraud points should be executed.
IF (modifyTestPlayers = 0 AND IsTestPlayer = 1) THEN
	SET statusCode = 0;
    LEAVE root;
END IF;

-- get if there are any actions that are manual.
SELECT COUNT(action_id) AS manualActions INTO numManualActions
FROM gaming_fraud_rule_main_actions WHERE fraud_rule_main_id = FraudRuleID  AND execution = 2 AND is_active = 1;

-- if the triggered_by_user_id IS NOT NULL that means that the manual actions have been executed and there are no more actions to be executed.
-- else if there are no manual actions that means that all actions have been executed(only automatic)
SELECT IF(triggered_by_user_id IS NOT NULL, 1, IF(numManualActions > 0, 0, 1)) AS actionExecuted INTO ExecutionFinished
FROM gaming_fraud_rules_triggered
WHERE fraud_rule_triggered_id =  fraudRuleTriggeredID;

IF(FraudRuleID = 0) THEN 
SET statusCode=1;
 LEAVE root;
END IF;


-- get the reason and the fraud points
SELECT fraud_rule_triggered_id, reason, alter_fraud_points, IFNULL(gaming_fraud_rules_triggered.fraud_points, segment_points.points) AS fraudPoints
FROM gaming_fraud_rule_main  
JOIN  gaming_fraud_rules_triggered ON gaming_fraud_rules_triggered.fraud_rule_main_id = gaming_fraud_rule_main.fraud_rule_main_id
JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_fraud_rules_triggered.client_stat_id
JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id
JOIN gaming_fraud_rules_client_segments_points AS segment_points ON segment_points.client_segment_id = gaming_clients.client_segment_id AND segment_points.fraud_rule_id = FraudRuleID
WHERE gaming_fraud_rules_triggered.fraud_rule_triggered_id =  fraudRuleTriggeredID;


-- If the rule is in test mode and the player is real no actions should be executed, so all actions should be returned as not executed
IF (fraudStatus = 1 AND IsTestPlayer = 0)THEN
  SELECT main_actions.fraud_rule_action_id, actions.action_id, actions.display_name, IF(main_actions.execution = 2, 0, 1) AS is_automatic,  
  0 AS action_has_been_executed, main_actions.input_value, actions.is_active 
  FROM gaming_fraud_rule_actions AS actions
  JOIN gaming_fraud_rule_main_actions AS main_actions ON main_actions.action_id = actions.action_id AND main_actions.is_active = 1
  WHERE main_actions.fraud_rule_main_id = FraudRuleID;
ELSE 
-- -----------------------------------------------------------------------
--
-- IF(action_triggered.action_id IS NUll, IF(main_actions.execution = 2, IF(ExecutionFinished = 1, 0, 1), main_actions.execution), 1)AS action_has_been_executed 
--
-- ------------------------------------------------------------------------
-- if the trigger action is null that means either the actions has not been executed yet(pending manual actions) or all actions are automatic. 
-- 	 If the execution is manual 
--        if execution finished then
--                               0(NO- because it is not in the table 'gaming_fraud_rule_actions_triggered' and that means the user press NO to execute)
--        else 1(YES - since it's still pending we return 1 as the default/suggested value)	
--   else if it is not manual display the execution of the automatic action
-- else it is executed because it is in the table 'gaming_fraud_rule_actions_triggered' which contains only executed actions

SELECT main_actions.fraud_rule_action_id, actions.action_id, actions.display_name, IF(main_actions.execution = 2, 0, 1) AS is_automatic,  
IF(action_triggered.fraud_rule_action_id IS NUll, IF(main_actions.execution = 2, IF(ExecutionFinished = 1, 0, 1), main_actions.execution), 1)AS action_has_been_executed,
IF(action_triggered.fraud_rule_action_id IS NUll, main_actions.input_value, action_triggered.input_value) AS input_value, actions.is_active 
FROM gaming_fraud_rule_actions AS actions
JOIN gaming_fraud_rule_main_actions AS main_actions ON main_actions.action_id = actions.action_id AND main_actions.is_active = 1
LEFT JOIN gaming_fraud_rule_actions_triggered AS action_triggered ON action_triggered.fraud_rule_action_id = main_actions.fraud_rule_action_id AND action_triggered.fraud_rule_triggered_id = fraudRuleTriggeredID
WHERE main_actions.fraud_rule_main_id = FraudRuleID;
END IF;
 
SET statusCode = 0;

END root$$

DELIMITER ;

