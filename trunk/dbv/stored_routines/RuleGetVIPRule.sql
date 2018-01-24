DROP procedure IF EXISTS `RuleGetVIPRule`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleGetVIPRule`()
BEGIN
	DECLARE vipRuleID BIGINT;
	SELECT rule_id INTO vipRuleID FROM gaming_rules WHERE is_vip_rule ORDER BY rule_id DESC LIMIT 1;
	CALL RuleGetRule(vipRuleID);
END$$

DELIMITER ;