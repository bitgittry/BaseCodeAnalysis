DROP procedure IF EXISTS `BonusGivePlayerManualBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGivePlayerManualBonus`(sessionID BIGINT, clientStatID BIGINT, bonusAmount DECIMAL(18, 5), wagerRequirementMultiplier DECIMAL(18, 5), expiryDaysFromAwarding INT, expiryDateFixed DATETIME, varReason TEXT, OUT statusCode INT)
root: BEGIN

  DECLARE bonusRuleID BIGINT DEFAULT 0;
  
  SELECT bonus_rule_id INTO bonusRuleID FROM gaming_bonus_rules WHERE name='Manual_Bonus';
  CALL BonusGivePlayerManualBonusByRuleID(bonusRuleID, sessionID, clientStatID, bonusAmount, wagerRequirementMultiplier, expiryDaysFromAwarding, expiryDateFixed,NULL,NULL,NULL,varReason, statusCode);
  
END root$$

DELIMITER ;

