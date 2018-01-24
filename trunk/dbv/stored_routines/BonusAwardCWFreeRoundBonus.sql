DROP procedure IF EXISTS `BonusAwardCWFreeRoundBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusAwardCWFreeRoundBonus`(bonusRuleID BIGINT, clientStatID BIGINT, sessionID BIGINT, freeRoundExpiryDateFixed DATETIME,  bonusExpiryDate DATETIME,
	wagerRequirementMultiplier  DECIMAL(18,5), numFreeRounds INT, extraID BIGINT,/*Only used for manual Bonuses*/ varReason VARCHAR(1024), /*Only used for deposit Bonuses*/ ringFencedAmountGiven DECIMAL(18,5),
	/*Only used for deposit Bonuses*/ currentRingFencedAmount DECIMAL(18,5), /*Only used for deposit Bonuses*/ depositedAmount DECIMAL(18,5), skipPreAuth TINYINT(1), OUT bonusInstanceID BIGINT, OUT statusCode INT)
root:BEGIN
    -- Direct Give bonus does not neeed to be active only not hidden/deleted
 
	DECLARE bonusRuleIDCheck,CWFreeRoundID,numFreeRoundsToAward,gameManufacturerID,currencyID BIGINT DEFAULT -1;
	DECLARE bonusPreAuth TINYINT(1);
	DECLARE currentDate, ProfileEndDate DATETIME;
	DECLARE costPerRound DECIMAL(18,5);
	DECLARE awardingType VARCHAR(80);

	SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
  
	SELECT gaming_bonus_rules.bonus_rule_id,IFNULL(numFreeRounds,IFNULL(gaming_bonus_rules.num_free_rounds,gaming_bonus_free_round_profiles.num_rounds)),cost_per_round,game_manufacturer_id,gaming_client_stats.currency_id, gaming_bonus_free_round_profiles.end_date
	INTO bonusRuleIDCheck, numFreeRoundsToAward, costPerRound, gameManufacturerID, currencyID, ProfileEndDate
	FROM gaming_bonus_rules 
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = clientStatID
    JOIN gaming_bonus_rule_free_round_profiles ON gaming_bonus_rule_free_round_profiles.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
	JOIN gaming_bonus_free_round_profiles ON gaming_bonus_free_round_profiles.bonus_free_round_profile_id = gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id
	JOIN gaming_bonus_free_round_profiles_amounts ON gaming_bonus_free_round_profiles_amounts.bonus_free_round_profile_id = gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id AND gaming_bonus_free_round_profiles_amounts.currency_id = gaming_client_stats.currency_id
	WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleID AND (gaming_bonus_rules.allow_awarding_bonuses=1 OR (gaming_bonus_rules.bonus_type_id=1 AND gaming_bonus_rules.is_hidden=0)) AND 
		NOW() BETWEEN gaming_bonus_rules.activation_start_date AND gaming_bonus_rules.activation_end_date AND is_free_rounds = 1
	LIMIT 1 # Profiles of the free round bonus rule are with same settings (cost per spin and number of rounds)
	FOR UPDATE;

	IF (bonusRuleIDCheck <> bonusRuleID)  THEN
		SET statusCode=1;
		LEAVE root;
	END IF;

	SET currentDate = NOW();

	INSERT INTO gaming_cw_free_rounds
	(client_stat_id,cw_free_round_status_id,date_created,cost_per_round,free_rounds_awarded,free_rounds_remaining,win_total,game_manufacturer_id,bonus_rule_id,expiry_date,wager_requirement_multiplier)
	SELECT clientStatID,cw_free_round_status_id,currentDate,costPerRound,numFreeRoundsToAward,numFreeRoundsToAward,0,gameManufacturerID,bonusRuleID, LEAST(freeRoundExpiryDateFixed,ProfileEndDate), wagerRequirementMultiplier
	FROM gaming_cw_free_round_statuses 
	WHERE gaming_cw_free_round_statuses.name = IF(bonusPreAuth,'OnAwardedAwaitingPreAuth','OnAwarded');

	SET CWFreeRoundID = LAST_INSERT_ID();

	IF (bonusPreAuth AND !skipPreAuth) THEN

		INSERT INTO gaming_bonus_instances_pre 
			(bonus_rule_id, client_stat_id, priority, bonus_amount, wager_requirement_multiplier, wager_requirement, expiry_date_fixed,
			extra_id, session_id, reason, date_created, pre_expiry_date,ring_fenced_amount_given,current_ring_fenced_amount,deposited_amount,
			cw_free_round_id)
		SELECT gaming_bonus_rules.bonus_rule_id, clientStatID, gaming_bonus_rules.priority, 0, wagerRequirementMultiplier, 0 AS wager_requirement,
			bonusExpiryDate, sessionID, sessionID, varReason, currentDate, date_add(now(), interval pre_expiry_days day) as pre_expiry_date,
			ringFencedAmountGiven ,currentRingFencedAmount ,depositedAmount,CWFreeRoundID
		FROM gaming_bonus_rules 
		WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleID;

		SET bonusInstanceID = LAST_INSERT_ID();

	ELSE

		INSERT INTO gaming_bonus_instances 
			(priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date,bonus_rule_id, client_stat_id, extra_id,
			transfer_every_x, transfer_every_amount,ring_fenced_amount_given,current_ring_fenced_amount,deposited_amount,is_free_rounds,is_free_rounds_mode,cw_free_round_id)
		SELECT priority, 0, 0, 0, 0,currentDate,bonusExpiryDate,bonusRuleID,clientStatID,extraID, 	
			CASE gaming_bonus_types_release.name
				WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
				WHEN 'EveryReleaseAmount' THEN 0 -- to be updated once we have the bonus amount to be awarded
				ELSE NULL
			END AS transfer_every_x, 
			CASE gaming_bonus_types_release.name
				WHEN 'EveryXWager' THEN 0 -- to be updated once we have the bonus amount to be awarded
				WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
				ELSE NULL
			END AS transfer_every_amount ,
			ringFencedAmountGiven ,currentRingFencedAmount ,depositedAmount,1,1,CWFreeRoundID
		FROM gaming_bonus_rules
		LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
		LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
		LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=currencyID
		WHERE gaming_bonus_rules.bonus_rule_id = bonusRuleID
		LIMIT 1;

		SET bonusInstanceID = LAST_INSERT_ID();

		IF (ROW_COUNT() > 0) THEN
			CALL BonusOnAwardedUpdateStats(bonusInstanceID);
		END IF;
	END IF;
   
  SET statusCode=0;

END root$$

DELIMITER ;

