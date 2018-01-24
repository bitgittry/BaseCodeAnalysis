DROP procedure IF EXISTS `BonusGetAllBonusesFilterByDateType`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetAllBonusesFilterByDateType`(bonusFilterDateType VARCHAR(80), currencyID BIGINT, operatorGameIDFilter BIGINT, nonHiddenOnly TINYINT(1), returnManualBonus TINYINT(1))
BEGIN
   
  DECLARE bonusRuleGetCounterID BIGINT DEFAULT -1;
  DECLARE isFunctionalSystem TINYINT(1) DEFAULT 0;
	
  SELECT value_bool INTO isFunctionalSystem FROM gaming_settings WHERE `name`='IS_FUNCTIONAL_BONUS_SYSTEM';

  IF (isFunctionalSystem) THEN
	SET operatorGameIDFilter=-1;
  END IF;
    
  INSERT INTO gaming_bonus_rule_get_counter (date_added) VALUES (NOW());
  SET bonusRuleGetCounterID=LAST_INSERT_ID();
  
  SET @curDate = NOW();
  CASE bonusFilterDateType 
    WHEN 'ALL' THEN
        INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id) 
        SELECT bonusRuleGetCounterID, bonus_rule_id 
        FROM gaming_bonus_rules
        WHERE (nonHiddenOnly=0 OR gaming_bonus_rules.is_hidden=0); 
    WHEN 'CURRENT' THEN 
      INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id) 
      SELECT bonusRuleGetCounterID, bonus_rule_id 
      FROM gaming_bonus_rules 
      WHERE activation_start_date <= @curDate AND activation_end_date >= @curDate AND (nonHiddenOnly=0 OR gaming_bonus_rules.is_hidden=0); 
    WHEN 'CURRENT+FUTURE' THEN 
      INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id) 
      SELECT bonusRuleGetCounterID, bonus_rule_id 
      FROM gaming_bonus_rules 
      WHERE activation_end_date >= @curDate AND (nonHiddenOnly=0 OR gaming_bonus_rules.is_hidden=0); 
    WHEN 'FUTURE' THEN 
      INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id) 
      SELECT bonusRuleGetCounterID, bonus_rule_id 
      FROM gaming_bonus_rules 
      WHERE activation_start_date >= @curDate AND (nonHiddenOnly=0 OR gaming_bonus_rules.is_hidden=0); 
    WHEN 'PAST' THEN 
      INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id) 
      SELECT bonusRuleGetCounterID, bonus_rule_id 
      FROM gaming_bonus_rules 
      WHERE activation_end_date <= @curDate AND (nonHiddenOnly=0 OR gaming_bonus_rules.is_hidden=0); 
  END CASE;
  
  CALL BonusGetAllBonusesByRuleCounterIDAndCurrencyID(bonusRuleGetCounterID, currencyID, operatorGameIDFilter, returnManualBonus);
  
END$$

DELIMITER ;

