DROP procedure IF EXISTS `BonusGiveDepositBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGiveDepositBonus`(bonusRuleID BIGINT, clientStatID BIGINT,depositAmount DECIMAL(18, 5),balanceHistoryID BIGINT, filterStartDate DATETIME)
BEGIN

	DECLARE bonusPreAuth,isFreeRounds,useRingFenced TINYINT(1);
	DECLARE awardingType VARCHAR(80);
	DECLARE freeRoundExpiryDate,expiryDateFixed DATETIME;
	DECLARE freeRoundExpiryDays,expiryDaysFromAwarding,wagerRequirementMultiplier,numFreeRounds INT;
	DECLARE bonusInstanceID BIGINT;
    DECLARE numberFreeRoundsFromRange INT;

	SET @depositOccurenceNumCur=0;
	SET @wagerRequirement=0;
	
    SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
    
    SELECT ranges.number_free_rounds INTO numberFreeRoundsFromRange 
    FROM gaming_bonus_rules_deposits_ranges ranges 
    JOIN gaming_client_stats ON gaming_client_stats.currency_id = ranges.currency_id
    WHERE gaming_client_stats.client_stat_id = clientStatID AND bonus_rule_id = bonusRuleID AND (depositAmount BETWEEN ranges.min_deposit AND ranges.max_deposit);

	SELECT is_free_rounds,free_round_expiry_date,free_round_expiry_days, expiry_date_fixed, expiry_days_from_awarding,wager_requirement_multiplier, IF(numberFreeRoundsFromRange=0, IFNULL(gaming_bonus_rules.num_free_rounds,num_rounds), numberFreeRoundsFromRange),
    IF(ring_fenced_by_bonus_rules OR ring_fenced_by_license_type >0,1,0) AS useRingFenced
	INTO isFreeRounds,freeRoundExpiryDate,freeRoundExpiryDays,expiryDateFixed,expiryDaysFromAwarding,wagerRequirementMultiplier,numFreeRounds,useRingFenced
	FROM gaming_bonus_rules 
	JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules.bonus_rule_id = gaming_bonus_rules_deposits.bonus_rule_id
    LEFT JOIN gaming_bonus_rule_free_round_profiles ON gaming_bonus_rule_free_round_profiles.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
	LEFT JOIN gaming_bonus_free_round_profiles ON gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id = gaming_bonus_free_round_profiles.bonus_free_round_profile_id
	WHERE gaming_bonus_rules.bonus_rule_id = bonusRuleID
	LIMIT 1; #if multuple profiles are linked to the bonus rule => only one will be selected

	SELECT COUNT(gaming_transactions.transaction_id) INTO @depositOccurenceNumCur  
	FROM gaming_transactions
	JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id 
	WHERE gaming_transactions.client_stat_id=clientStatID AND gaming_transactions.timestamp >= filterStartDate;

	IF (isFreeRounds = 0) THEN 
		IF (bonusPreAuth=0) THEN
			INSERT INTO gaming_bonus_instances 
				(priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date,bonus_rule_id, client_stat_id, extra_id, transfer_every_x, transfer_every_amount,ring_fenced_amount_given,current_ring_fenced_amount,deposited_amount)
			SELECT BD.priority, bonus_amount, bonus_amount, 
				@wagerRequirement:=IF(wager_req_include_deposit_amount, (IF(is_percentage=1, bonus_amount/percentage, bonus_amount)+bonus_amount)*wager_requirement_multiplier, BD.bonus_amount*wager_requirement_multiplier), 
				@wagerRequirement, 
				NOW(), expiry_date, BD.bonus_rule_id, BD.client_stat_id, balanceHistoryID,
				CASE gaming_bonus_types_release.name
				  WHEN 'EveryXWager' THEN BD.transfer_every_x_wager
				  WHEN 'EveryReleaseAmount' THEN ROUND(wager_requirement_multiplier/(bonus_amount/wager_restrictions.release_every_amount),2)
				  ELSE NULL
				END AS transfer_every_x, 
				CASE gaming_bonus_types_release.name
				  WHEN 'EveryXWager' THEN ROUND(bonus_amount/(wager_requirement_multiplier/BD.transfer_every_x_wager), 0)
				  WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
				  ELSE NULL
				END AS transfer_every_amount ,IF(useRingFence,depositAmount,0),IF(useRingFence,depositAmount,0),depositAmount
			FROM 
			(
				SELECT gaming_bonus_rules.priority, gaming_bonus_rules_deposits.is_percentage, IFNULL(IFNULL(deposit_ranges.percentage, gaming_bonus_rules_deposits_percentages.percentage), gaming_bonus_rules_deposits.percentage) AS percentage,
				  ROUND(IF(is_percentage, MathSaturate(depositAmount*IFNULL(IFNULL(deposit_ranges.percentage, gaming_bonus_rules_deposits_percentages.percentage), gaming_bonus_rules_deposits.percentage), percentage_max_amount), IFNULL(deposit_ranges.amount, fixed_amount)),0) AS bonus_amount,
				  IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, wager_req_include_deposit_amount,
				  gaming_bonus_rules.wager_requirement_multiplier, 
				  gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id, occurrence_num_min, occurrence_num_max, 
				  gaming_bonus_rules.bonus_type_transfer_id, gaming_bonus_rules.bonus_type_release_id, gaming_client_stats.currency_id, gaming_bonus_rules.transfer_every_x_wager,
				  IF(ring_fenced_by_bonus_rules OR ring_fenced_by_license_type >0,1,0) AS useRingFence
				FROM gaming_bonus_rules 
				JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules.bonus_rule_id=bonusRuleID AND gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id
				JOIN gaming_bonus_rules_deposits_amounts ON gaming_bonus_rules_deposits.bonus_rule_id=gaming_bonus_rules_deposits_amounts.bonus_rule_id 
				LEFT JOIN gaming_bonus_rules_deposits_percentages ON gaming_bonus_rules_deposits.bonus_rule_id=gaming_bonus_rules_deposits_percentages.bonus_rule_id AND gaming_bonus_rules_deposits_percentages.deposit_occurrence_num=@depositOccurenceNumCur
				JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gaming_bonus_rules_deposits_amounts.currency_id=gaming_client_stats.currency_id 
				LEFT JOIN gaming_bonus_rules_deposits_ranges AS deposit_ranges ON gaming_bonus_rules_deposits.bonus_rule_id=deposit_ranges.bonus_rule_id AND deposit_ranges.currency_id=gaming_client_stats.currency_id AND (depositAmount BETWEEN deposit_ranges.min_deposit AND deposit_ranges.max_deposit)
				WHERE (gaming_bonus_rules.awarded_times_threshold IS NULL OR gaming_bonus_rules.awarded_times < gaming_bonus_rules.awarded_times_threshold)
				LIMIT 1 
			) AS BD 
			LEFT JOIN gaming_bonus_types_transfers ON BD.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
			LEFT JOIN gaming_bonus_types_release ON BD.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
			LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=BD.bonus_rule_id AND wager_restrictions.currency_id=BD.currency_id
			LIMIT 1;

			SET @rowCount=ROW_COUNT();
			SET @bonusInstanceID=LAST_INSERT_ID();

			
			IF (@rowCount>0) THEN
				CALL BonusOnAwardedUpdateStats(@bonusInstanceID);

				SELECT gaming_bonus_types_awarding.name INTO awardingType
				FROM gaming_bonus_rules 
				JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
				WHERE gaming_bonus_rules.bonus_rule_id = bonusRuleID;

				IF (awardingType='CashBonus') THEN
					CALL BonusRedeemAllBonus(@bonusInstanceID, 0, -1, 'CashBonus','CashBonus', NULL);
				END IF;
			END IF;
		ELSE 
			INSERT INTO gaming_bonus_instances_pre 
				(bonus_rule_id, client_stat_id, priority, bonus_amount, wager_requirement_multiplier, wager_requirement, expiry_date_fixed, expiry_days_from_awarding, extra_id, session_id,
				date_created, pre_expiry_date,ring_fenced_amount_given,current_ring_fenced_amount,deposited_amount)
			SELECT BD.bonus_rule_id, BD.client_stat_id, BD.priority, bonus_amount, wager_requirement_multiplier, 
				IF(wager_req_include_deposit_amount, (IF(is_percentage=1, bonus_amount/percentage, bonus_amount)+bonus_amount)*wager_requirement_multiplier, BD.bonus_amount*wager_requirement_multiplier) AS wager_requirement, 
				expiry_date_fixed, expiry_days_from_awarding, balanceHistoryID, NULL, NOW(), pre_expiry_date,IF(useRingFence,depositAmount,0),IF(useRingFence,depositAmount,0),depositAmount
			FROM 
			(
				SELECT gaming_bonus_rules.priority, gaming_bonus_rules_deposits.is_percentage, IFNULL(IFNULL(deposit_ranges.percentage, gaming_bonus_rules_deposits_percentages.percentage), gaming_bonus_rules_deposits.percentage) AS percentage,
				  ROUND(IF(is_percentage, MathSaturate(depositAmount*IFNULL(IFNULL(deposit_ranges.percentage, gaming_bonus_rules_deposits_percentages.percentage), gaming_bonus_rules_deposits.percentage), percentage_max_amount), IFNULL(deposit_ranges.amount, fixed_amount)),0) AS bonus_amount,
				  expiry_date_fixed, expiry_days_from_awarding, wager_req_include_deposit_amount,
				  gaming_bonus_rules.wager_requirement_multiplier, 
				  gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id, occurrence_num_min, occurrence_num_max, 
				  gaming_bonus_rules.bonus_type_transfer_id, gaming_bonus_rules.bonus_type_release_id, gaming_client_stats.currency_id, gaming_bonus_rules.transfer_every_x_wager,
				  date_add(now(), interval pre_expiry_days day) as pre_expiry_date,IF(ring_fenced_by_bonus_rules OR ring_fenced_by_license_type >0,1,0) AS useRingFence
				FROM gaming_bonus_rules 
				JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules.bonus_rule_id=bonusRuleID AND gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id
				JOIN gaming_bonus_rules_deposits_amounts ON gaming_bonus_rules_deposits.bonus_rule_id=gaming_bonus_rules_deposits_amounts.bonus_rule_id 
				LEFT JOIN gaming_bonus_rules_deposits_percentages ON gaming_bonus_rules_deposits.bonus_rule_id=gaming_bonus_rules_deposits_percentages.bonus_rule_id AND gaming_bonus_rules_deposits_percentages.deposit_occurrence_num=@depositOccurenceNumCur
				JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gaming_bonus_rules_deposits_amounts.currency_id=gaming_client_stats.currency_id 
				LEFT JOIN gaming_bonus_rules_deposits_ranges AS deposit_ranges ON gaming_bonus_rules_deposits.bonus_rule_id=deposit_ranges.bonus_rule_id AND deposit_ranges.currency_id=gaming_client_stats.currency_id AND (depositAmount BETWEEN deposit_ranges.min_deposit AND deposit_ranges.max_deposit)
				WHERE (gaming_bonus_rules.awarded_times_threshold IS NULL OR gaming_bonus_rules.awarded_times < gaming_bonus_rules.awarded_times_threshold)	
				LIMIT 1 
			) AS BD 
			LIMIT 1;
		END IF;
	ELSE
		CALL BonusAwardCWFreeRoundBonus (bonusRuleID, clientStatID, 0,IFNULL(freeRoundExpiryDate,DATE_ADD(NOW(), INTERVAL freeRoundExpiryDays DAY)),IFNULL(expiryDateFixed, DATE_ADD(NOW(), INTERVAL expiryDaysFromAwarding DAY)),  
			wagerRequirementMultiplier,numFreeRounds, balanceHistoryID, NULL, IF(useRingFenced,depositAmount,0),IF(useRingFenced,depositAmount,0), depositAmount,0, @b, @s);
	END IF;

END$$

DELIMITER ;

