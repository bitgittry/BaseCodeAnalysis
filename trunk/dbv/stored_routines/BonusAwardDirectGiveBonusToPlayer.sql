DROP procedure IF EXISTS `BonusAwardDirectGiveBonusToPlayer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusAwardDirectGiveBonusToPlayer`(bonusRuleID BIGINT, ignoreAwardingDate TINYINT(1), clientStatID BIGINT, bonusCode VARCHAR(45), OUT statusCode INT)
root:BEGIN
  -- Changed so that a direct give bonus needs to be deleted for not allowing players to redeem the bonus with the Bonus\Voucher code
  
  DECLARE bonusEnabledFlag, bonusFreeGiveEnabledFlag, restrictByBonusCode, validDateRange, bonusPreAuth, alreadyGivenBonus TINYINT DEFAULT 0;
  DECLARE bonusRuleIDCheck, playerSelectionID, bonusInstanceGenID BIGINT DEFAULT -1;
  DECLARE bonusAmount, programCostThreshold, addedToRealMoney DECIMAL(18, 5); 
  DECLARE bonusCodeCheck VARCHAR (45);
  DECLARE noMoreRecords TINYINT(1) DEFAULT 0;  
  
  DECLARE bonusRuleIdCursor CURSOR FOR 
    SELECT 		bonus_rule_id 
	FROM 		gaming_bonus_rules 
	WHERE 		((IFNULL(bonusCode,'') != '' AND voucher_code=bonusCode) OR (bonus_rule_id = bonusRuleID))
				AND ((gaming_bonus_rules.allow_awarding_bonuses=1 AND gaming_bonus_rules.is_active=1)
						OR (gaming_bonus_rules.is_hidden=0 AND gaming_bonus_rules.bonus_type_id=1))
	ORDER BY 	bonus_rule_id DESC;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
  
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  SELECT value_bool INTO bonusFreeGiveEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_FREE_GIVE_ENABLED';
  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH'; 
	
  IF NOT (bonusEnabledFlag AND bonusFreeGiveEnabledFlag) THEN
    SET statusCode=7;
    LEAVE root;
  END IF;
  
	OPEN bonusRuleIdCursor;
		allCalls: LOOP 
      
    SET noMoreRecords=0;
    FETCH bonusRuleIdCursor INTO bonusRuleID;
    IF (noMoreRecords) THEN
        LEAVE allCalls;
    END IF;	
	
	-- IF(bonusCode IS NOT NULL AND (bonusRuleID IS NULL OR bonusRuleID=0)) THEN
    -- 		SELECT bonus_rule_id INTO bonusRuleID FROM gaming_bonus_rules WHERE voucher_code=bonusCode AND gaming_bonus_rules.allow_awarding_bonuses=1 AND gaming_bonus_rules.is_active=1 ORDER BY bonus_rule_id DESC LIMIT 1;
	-- END IF;  
  
	SELECT 	gaming_bonus_rules.bonus_rule_id, gaming_bonus_rules.player_selection_id, gaming_bonus_rules.program_cost_threshold, gaming_bonus_rules.added_to_real_money_total, rule_amounts.amount, 
			gaming_bonus_rules.restrict_by_voucher_code, gaming_bonus_rules.voucher_code,  (gaming_bonus_rules.activation_start_date<=NOW() AND gaming_bonus_rules.activation_end_date>=NOW()) 
	INTO 	bonusRuleIDCheck, playerSelectionID, programCostThreshold, addedToRealMoney, bonusAmount, restrictByBonusCode, bonusCodeCheck, validDateRange
	FROM 	gaming_bonus_rules 
			JOIN gaming_bonus_rules_direct_gvs AS direct_gvs ON gaming_bonus_rules.bonus_rule_id=direct_gvs.bonus_rule_id 
			JOIN gaming_operators ON gaming_operators.is_main_operator
			JOIN gaming_bonus_rules_direct_gvs_amounts AS rule_amounts ON direct_gvs.bonus_rule_id=rule_amounts.bonus_rule_id AND gaming_operators.currency_id=rule_amounts.currency_id
	WHERE 	gaming_bonus_rules.bonus_rule_id=bonusRuleID AND gaming_bonus_rules.is_hidden=0;
  
	IF (bonusRuleIDCheck <> bonusRuleID) THEN
		SET statusCode=1;
		LEAVE root;
	END IF;

	IF (programCostThreshold != 0 AND (bonusAmount+addedToRealMoney > programCostThreshold)) THEN
		SET statusCode=2;
		LEAVE root;
	END IF;

	IF (restrictByBonusCode=1 AND (bonusCode IS NULL OR bonusCode<>bonusCodeCheck)) THEN
		SET statusCode=3;
		LEAVE root;
	END IF;

	IF (ignoreAwardingDate=0 AND validDateRange=0) THEN
		SET statusCode=5;
		LEAVE root;
	END IF;
	
	IF (!PlayerSelectionIsPlayerInSelection(playerSelectionID, clientStatID)) THEN
		SET statusCode=4;
		LEAVE root;
	END IF;

	IF (bonusPreAuth=0) THEN
		SELECT 1 INTO alreadyGivenBonus FROM gaming_bonus_instances WHERE client_stat_id=clientStatID AND bonus_rule_id=bonusRuleID ORDER BY bonus_instance_id DESC LIMIT 1;
	ELSE
		SELECT 1 INTO alreadyGivenBonus FROM gaming_bonus_instances_pre WHERE client_stat_id=clientStatID AND bonus_rule_id=bonusRuleID ORDER BY bonus_instance_pre_id DESC LIMIT 1;
	END IF;

	IF (alreadyGivenBonus=1) THEN
		SET statusCode=6;
		LEAVE root;
	END IF;

	CALL BonusGiveDirectGiveBonus(bonusRuleID, clientStatID, 0, bonusInstanceGenID);
  END LOOP allCalls; 
  CLOSE bonusRuleIdCursor;

  IF (bonusInstanceGenID=-1) THEN
	SET statusCode=1;
	LEAVE root;
  ELSE
	SELECT bonusInstanceGenID AS bonus_instance_gen_id;	  
    SET statusCode=0;
  END IF;
		
END root$$

DELIMITER ;

