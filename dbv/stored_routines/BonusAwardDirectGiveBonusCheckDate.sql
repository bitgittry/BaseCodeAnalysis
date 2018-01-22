DROP procedure IF EXISTS `BonusAwardDirectGiveBonusCheckDate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusAwardDirectGiveBonusCheckDate`()
BEGIN
  
  DECLARE noMoreRecords, ignoreAwardingDate TINYINT(1) DEFAULT 0; 
  DECLARE bonusRuleID BIGINT DEFAULT -1;
  DECLARE giveStatusCode INT DEFAULT 0;
  
  DECLARE directGiveBonusesCursor CURSOR FOR 
    SELECT gaming_bonus_rules.bonus_rule_id 
    FROM gaming_bonus_rules 
    JOIN gaming_bonus_rules_direct_gvs ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_direct_gvs.bonus_rule_id 
    WHERE gaming_bonus_rules.activation_start_date<=NOW() AND gaming_bonus_rules.allow_awarding_bonuses=1 AND gaming_bonus_rules.is_active=1 AND gaming_bonus_rules.activation_end_date>=NOW() 
      AND gaming_bonus_rules.restrict_by_voucher_code=0 AND (gaming_bonus_rules.awarded_times_threshold IS NULL OR gaming_bonus_rules.awarded_times < gaming_bonus_rules.awarded_times_threshold);
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
  SET @timeStart=NOW();
  SET ignoreAwardingDate=0;
  
  OPEN directGiveBonusesCursor;
  allDirectBonusesLabel: LOOP 
    
    SET noMoreRecords=0;
    FETCH directGiveBonusesCursor INTO bonusRuleID;
    IF (noMoreRecords) THEN
      LEAVE allDirectBonusesLabel;
    END IF;
  
    SET giveStatusCode=0;
    CALL BonusAwardDirectGiveBonus(bonusRuleID, ignoreAwardingDate, giveStatusCode);
	COMMIT AND CHAIN;
  END LOOP allDirectBonusesLabel;
  CLOSE directGiveBonusesCursor;
  COMMIT;  
  
  
END$$

DELIMITER ;

