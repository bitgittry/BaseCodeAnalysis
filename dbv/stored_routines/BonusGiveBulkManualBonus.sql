DROP procedure IF EXISTS `BonusGiveBulkManualBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGiveBulkManualBonus`(bonusBulkCounterID BIGINT, sessionID BIGINT, OUT statusCode INT)
root: BEGIN
  
  DECLARE bonusEnabledFlag,bonusBulkAuthorization TINYINT(1) DEFAULT 0;
  DECLARE bonusRuleIDCheck, clientStatIDCheck, CounterID, playerSelectionID,bonusRuleAwardCounterID BIGINT DEFAULT -1;
  DECLARE minAmount, maxAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE playerInSelection, validWagerReq, validDaysFromAwarding, validDateFixed, validAmount, bonusPreAuth,isFreeBonus TINYINT(1) DEFAULT 0;
  DECLARE numToAward, awardedTimes INT DEFAULT 0;
  DECLARE awardedTimesThreshold INT DEFAULT NULL;
  
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  SELECT value_bool INTO bonusBulkAuthorization FROM gaming_settings WHERE name='BONUS_BULK_GIVE_AUTHORIZATION';
  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
  
  IF NOT (bonusEnabledFlag) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  SELECT gaming_bonus_rules.bonus_rule_id,player_selection_id,is_free_bonus INTO bonusRuleIDCheck,playerSelectionID, isFreeBonus
  FROM gaming_bonus_bulk_counter
  JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id= gaming_bonus_bulk_counter.bonus_rule_id
  JOIN gaming_bonus_rules_manuals ON gaming_bonus_rules_manuals.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
  WHERE bonus_bulk_counter_id = bonusBulkCounterID;

  IF (bonusRuleIDCheck = -1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

	SELECT gaming_bonus_rules.awarded_times, gaming_bonus_rules.awarded_times_threshold 
	INTO awardedTimes, awardedTimesThreshold
	FROM gaming_bonus_rules 
	WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleIDCheck;
 
	IF (awardedTimesThreshold IS NOT NULL) THEN

		SELECT COUNT(*) INTO numToAward FROM gaming_bonus_bulk_players WHERE bonus_bulk_counter_id = bonusBulkCounterID;
		IF (numToAward > (awardedTimesThreshold - awardedTimes)) THEN
			SET statusCode = 3;
			LEAVE root;
		END IF;
	END IF;

	UPDATE gaming_bonus_bulk_players
	JOIN gaming_client_stats ON gaming_bonus_bulk_players.client_stat_id = gaming_client_stats.client_stat_id
	JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = bonusRuleIDCheck
	JOIN gaming_bonus_rules_manuals ON gaming_bonus_rules_manuals.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	JOIN gaming_bonus_rules_manuals_amounts ON gaming_bonus_rules_manuals.bonus_rule_id = gaming_bonus_rules_manuals_amounts.bonus_rule_id AND gaming_client_stats.currency_id = gaming_bonus_rules_manuals_amounts.currency_id
	JOIN gaming_player_selections_player_cache AS CS ON CS.player_selection_id=gaming_bonus_rules.player_selection_id AND CS.player_in_selection=1 AND CS.client_stat_id = gaming_client_stats.client_stat_id
	LEFT JOIN(
		SELECT COUNT(1) AS num_times_awarded, gaming_bonus_instances.client_stat_id
		FROM gaming_bonus_instances
		WHERE gaming_bonus_instances.bonus_rule_id = bonusRuleIDCheck
		GROUP BY client_stat_id
	) AS count_bonuses ON count_bonuses.client_stat_id = gaming_client_stats.client_stat_id
		SET is_invalid = 0
	WHERE bonus_bulk_counter_id = bonusBulkCounterID AND is_given=0
    AND gaming_bonus_bulk_players.wagering_requirment_multiplier BETWEEN gaming_bonus_rules_manuals.min_wager_requirement_multiplier AND gaming_bonus_rules_manuals.max_wager_requirement_multiplier
	AND gaming_bonus_bulk_players.amount BETWEEN gaming_bonus_rules_manuals_amounts.min_amount AND gaming_bonus_rules_manuals_amounts.max_amount
	AND (
		   (gaming_bonus_bulk_players.expirey_days_from_awarding IS NOT NULL AND 
			 IF(gaming_bonus_rules_manuals.min_expiry_days_from_awarding IS NOT NULL,
					gaming_bonus_bulk_players.expirey_days_from_awarding BETWEEN gaming_bonus_rules_manuals.min_expiry_days_from_awarding AND gaming_bonus_rules_manuals.max_expiry_days_from_awarding,
					DATE_ADD(NOW(), INTERVAL gaming_bonus_bulk_players.expirey_days_from_awarding DAY) BETWEEN gaming_bonus_rules_manuals.min_expiry_date_fixed AND gaming_bonus_rules_manuals.max_expiry_date_fixed
				)
		   ) 
		OR (
			gaming_bonus_bulk_players.expirey_date IS NOT NULL AND
			IF(gaming_bonus_rules_manuals.min_expiry_date_fixed IS NOT NULL,
				gaming_bonus_bulk_players.expirey_date BETWEEN gaming_bonus_rules_manuals.min_expiry_date_fixed AND gaming_bonus_rules_manuals.max_expiry_date_fixed,
				DATEDIFF(gaming_bonus_bulk_players.expirey_date ,NOW()) BETWEEN gaming_bonus_rules_manuals.min_expiry_days_from_awarding AND gaming_bonus_rules_manuals.max_expiry_days_from_awarding
			   )
			) 
		)
	AND
		IF (award_bonus_max = 0 OR award_bonus_max > IFNULL(num_times_awarded,0),1,0);


  INSERT INTO gaming_bonus_rule_award_counter(bonus_rule_id, date_created)
  SELECT bonusRuleIDCheck, NOW();
  
  SET bonusRuleAwardCounterID=LAST_INSERT_ID();
  
	IF (bonusPreAuth=0) THEN
		INSERT INTO gaming_bonus_instances 
			(priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, extra_id, reason, transfer_every_x, transfer_every_amount,bonus_rule_award_counter_id)
		SELECT 
			priority, gbbp.amount, gbbp.amount, IF(isFreeBonus,0,gbbp.amount*gbbp.wagering_requirment_multiplier),IF(isFreeBonus,0, gbbp.amount*gbbp.wagering_requirment_multiplier), NOW(),
			IFNULL(gbbp.expirey_date, DATE_ADD(NOW(), INTERVAL gbbp.expirey_days_from_awarding DAY)) AS expiry_date, gaming_bonus_rules.bonus_rule_id, gbbp.client_stat_id , sessionID, gbbp.reason,
			CASE gaming_bonus_types_release.name
				WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
				WHEN 'EveryReleaseAmount' THEN ROUND(gbbp.wagering_requirment_multiplier/(gbbp.amount/wager_restrictions.release_every_amount),2)
				ELSE NULL
			END,
			CASE gaming_bonus_types_release.name
				WHEN 'EveryXWager' THEN ROUND(gbbp.amount/(gbbp.wagering_requirment_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
				WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
				ELSE NULL
			END,
			bonusRuleAwardCounterID
		FROM gaming_bonus_rules 
		LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
		LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
		JOIN gaming_bonus_bulk_players AS gbbp ON gbbp.bonus_bulk_counter_id = bonusBulkCounterID AND is_invalid =0 AND (is_authorized || bonusBulkAuthorization =0) AND is_given =0
		JOIN gaming_client_stats ON gbbp.client_stat_id = gaming_client_stats.client_stat_id
		LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
		WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleIDCheck;
		 
		UPDATE gaming_bonus_bulk_players
		SET is_given=1  
		WHERE bonus_bulk_counter_id = bonusBulkCounterID AND is_invalid =0  AND (is_authorized || bonusBulkAuthorization =0) AND is_given=0;


		IF (ROW_COUNT() > 0) THEN

			INSERT INTO gaming_bonus_rule_award_counter_client_stats(bonus_rule_award_counter_id, bonus_instance_id, client_stat_id)
			SELECT bonusRuleAwardCounterID, gaming_bonus_instances.bonus_instance_id, gaming_client_stats.client_stat_id
			FROM gaming_client_stats 
			JOIN gaming_bonus_instances ON 
			gaming_bonus_instances.bonus_rule_award_counter_id=bonusRuleAwardCounterID AND 
			gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
			FOR UPDATE;

			CALL BonusOnAwardedUpdateStatsMultipleBonuses(bonusRuleAwardCounterID, 1);

			DELETE FROM gaming_bonus_rule_award_counter_client_stats
			WHERE bonus_rule_award_counter_id=bonusRuleAwardCounterID;

			COMMIT;
		END IF;
	ELSE
		INSERT INTO gaming_bonus_instances_pre 
		  (bonus_rule_id, client_stat_id, priority, bonus_amount, wager_requirement_multiplier, wager_requirement, expiry_date_fixed, expiry_days_from_awarding, extra_id, session_id, reason, date_created, pre_expiry_date)
		SELECT gaming_bonus_rules.bonus_rule_id, gbbp.client_stat_id, gaming_bonus_rules.priority, gbbp.amount, gbbp.wagering_requirment_multiplier , gbbp.amount*gbbp.wagering_requirment_multiplier AS wager_requirement,
		  gbbp.expirey_date, gbbp.expirey_days_from_awarding, sessionID, sessionID, gbbp.reason, NOW(), date_add(now(), interval pre_expiry_days day) as pre_expiry_date
		FROM gaming_bonus_rules 
		JOIN gaming_bonus_bulk_players AS gbbp ON bonus_bulk_counter_id = bonusBulkCounterID AND is_invalid =0 AND (is_authorized || bonusBulkAuthorization =0) AND is_given=0
		WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleIDCheck;

		UPDATE gaming_bonus_bulk_players
		SET is_given=1  
		WHERE bonus_bulk_counter_id = bonusBulkCounterID AND is_invalid =0  AND (is_authorized || bonusBulkAuthorization =0) AND is_given=0;
    
	END IF;

  COMMIT;
  SET statusCode=0;

END root$$

DELIMITER ;

