DROP procedure IF EXISTS `BonusAwardDirectGiveBonusByBonusCode`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusAwardDirectGiveBonusByBonusCode`(clientStatID BIGINT, bonusCode VARCHAR(80), OUT statusCode INT)
root: BEGIN

	DECLARE clientStatIDCheck, bonusRuleID BIGINT DEFAULT -1; 
	DECLARE validDateRange, bonusPreAuth, alreadyGivenBonus TINYINT(1) DEFAULT 0;
	DECLARE noMoreRecords TINYINT(1) DEFAULT 0;		

	-- DECLARE Cursor
	DECLARE bonusRuleIdCursor CURSOR FOR 
		SELECT 		bonus_rule_id		
		FROM		gaming_bonus_rules
		WHERE		voucher_code=bonusCode 
					AND	allow_awarding_bonuses=1
					AND is_active=1
					AND restrict_by_voucher_code=1;
	DECLARE CONTINUE HANDLER FOR NOT FOUND
		SET noMoreRecords = 1; 
			
	
	SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID AND is_active=1 FOR UPDATE;
	SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
	
	IF (clientStatIDCheck=-1) THEN
	  SET statusCode=1;
	  LEAVE root;
    END IF;

	
	OPEN bonusRuleIdCursor;
		allCalls: LOOP 
		SET noMoreRecords=0;
		FETCH bonusRuleIdCursor INTO bonusRuleID;
		IF (noMoreRecords) THEN
			LEAVE allCalls;
		END IF;	
			
		SELECT 		(gaming_bonus_rules.activation_start_date<=NOW() AND gaming_bonus_rules.activation_end_date>=NOW()) 
		INTO 		validDateRange
		FROM 		gaming_bonus_rules
		WHERE 		bonus_rule_id = bonusRuleID 
					AND gaming_bonus_rules.bonus_type_id=1 
					AND gaming_bonus_rules.allow_awarding_bonuses=1 
					AND gaming_bonus_rules.is_active=1 
					AND gaming_bonus_rules.restrict_by_voucher_code=1
		ORDER BY 	bonus_rule_id DESC LIMIT 1;

		IF (bonusRuleID=-1) THEN
			SET statusCode=2;
			LEAVE root;
		END IF;

		IF (validDateRange=0) THEN
			SET statusCode=3;
			LEAVE root;
		END IF;
	
		IF (bonusPreAuth=0) THEN
			SELECT 1 INTO alreadyGivenBonus FROM gaming_bonus_instances WHERE client_stat_id=clientStatID AND bonus_rule_id=bonusRuleID ORDER BY bonus_instance_id DESC LIMIT 1;
		ELSE
			SELECT 1 INTO alreadyGivenBonus FROM gaming_bonus_instances_pre WHERE client_stat_id=clientStatID AND bonus_rule_id=bonusRuleID ORDER BY bonus_instance_pre_id DESC LIMIT 1;
		END IF;

		IF (alreadyGivenBonus) THEN
			SET statusCode=4;
			LEAVE root;
		END IF;

		CALL BonusGiveDirectGiveBonus(bonusRuleID, clientStatID, -1);
		
		
		END LOOP allCalls; 
		CLOSE bonusRuleIdCursor;	

	SET statusCode=0;

END root$$

DELIMITER ;

