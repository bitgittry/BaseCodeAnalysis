DROP procedure IF EXISTS `FraudRuleCheckFraudRuleLimit`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRuleCheckFraudRuleLimit`(fraudRuleID INT, clientStatID BIGINT, OUT limitReach INT)
root:BEGIN

-- this have to change according what kind of trigger it is. For now it is checking only for triggers that don't involved payment methods and balance account

  DECLARE occurrenceID TINYINT(4) DEFAULT 0;
  SET limitReach= 0;

  SELECT occurrence_id INTO occurrenceID FROM gaming_fraud_rule_main WHERE fraud_rule_main_id = fraudRuleID;
  IF (occurrenceID = 1) THEN
	SELECT limitReach;
	LEAVE root;
  END IF;

SELECT IF(COUNT(gaming_fraud_rules_triggered.fraud_rule_triggered_id) > 0 , 1, 0) AS triggerLimit INTO limitReach
FROM gaming_fraud_rules_triggered
JOIN gaming_fraud_rule_main ON gaming_fraud_rule_main.fraud_rule_main_id = gaming_fraud_rules_triggered.fraud_rule_main_id
JOIN gaming_fraud_rules_statuses ON gaming_fraud_rules_statuses.fraud_rule_status_id = gaming_fraud_rule_main.status_id
WHERE gaming_fraud_rules_triggered.fraud_rule_main_id = fraudRuleID AND gaming_fraud_rules_triggered.client_stat_id = clientStatID AND 
IF(gaming_fraud_rules_statuses.status = 'Enabled', gaming_fraud_rules_triggered.test_mode = 0, gaming_fraud_rules_triggered.test_mode = 1)
GROUP BY gaming_fraud_rules_triggered.client_stat_id;

END root$$

DELIMITER ;

