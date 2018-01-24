DROP procedure IF EXISTS `FraudRuleCheckPlayer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRuleCheckPlayer`(fraudRuleMainID INT, clientID BIGINT)
root: BEGIN

DECLARE fraudStatus TINYINT(4) DEFAULT -1;

-- fraudStatus : 
-- -1 - Expired 
--  0 - Enabled
--  1 - Testing


SELECT IF(gaming_fraud_rules_statuses.status ='Enabled', 0, IF(start_test = 1 AND NOW()<=end_date, 1, -1))
INTO fraudStatus
FROM gaming_fraud_rule_main
JOIN gaming_fraud_rules_statuses ON gaming_fraud_rules_statuses.fraud_rule_status_id = gaming_fraud_rule_main.status_id 
WHERE gaming_fraud_rule_main.fraud_rule_main_id = fraudRuleMainID;


SELECT IF(fraudStatus<0, 0, 1);

END root$$

DELIMITER ;

