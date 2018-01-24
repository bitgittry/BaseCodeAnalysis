DROP procedure IF EXISTS `BonusCheckBulkManualBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusCheckBulkManualBonus`(bonusBulkCounterID BIGINT, sessionID BIGINT, OUT statusCode INT)
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

  SELECT gaming_bonus_rules.bonus_rule_id,player_selection_id,is_free_bonus 
  INTO bonusRuleIDCheck,playerSelectionID, isFreeBonus
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
	SET is_invalid =1
	WHERE bonus_bulk_counter_id = bonusBulkCounterID AND is_given=0;
	
	UPDATE gaming_bonus_bulk_players
	LEFT JOIN gaming_client_stats ON gaming_bonus_bulk_players.client_stat_id = gaming_client_stats.client_stat_id
	LEFT JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = bonusRuleIDCheck
	LEFT JOIN gaming_bonus_rules_manuals ON gaming_bonus_rules_manuals.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	LEFT JOIN gaming_bonus_rules_manuals_amounts ON gaming_bonus_rules_manuals.bonus_rule_id = gaming_bonus_rules_manuals_amounts.bonus_rule_id AND gaming_client_stats.currency_id = gaming_bonus_rules_manuals_amounts.currency_id
	LEFT JOIN gaming_player_selections_player_cache AS CS ON CS.player_selection_id=gaming_bonus_rules.player_selection_id AND CS.player_in_selection=1 AND CS.client_stat_id = gaming_client_stats.client_stat_id
	LEFT JOIN(
		SELECT COUNT(1) AS num_times_awarded, gaming_bonus_instances.client_stat_id 
		FROM gaming_bonus_instances
		WHERE bonus_rule_id = bonusRuleIDCheck
		GROUP BY client_stat_id
	) AS count_bonuses ON count_bonuses.client_stat_id = gaming_client_stats.client_stat_id
		SET 
		invalid_wager = IF (gaming_bonus_bulk_players.wagering_requirment_multiplier BETWEEN gaming_bonus_rules_manuals.min_wager_requirement_multiplier AND gaming_bonus_rules_manuals.max_wager_requirement_multiplier,0,1),
		invalid_amount = IF (gaming_bonus_bulk_players.amount BETWEEN gaming_bonus_rules_manuals_amounts.min_amount AND gaming_bonus_rules_manuals_amounts.max_amount,0,1),
		invalid_expiry = IF (
				(
					(
						gaming_bonus_bulk_players.expirey_days_from_awarding IS NOT NULL AND 
						 IF(gaming_bonus_rules_manuals.min_expiry_days_from_awarding IS NOT NULL,
								gaming_bonus_bulk_players.expirey_days_from_awarding BETWEEN gaming_bonus_rules_manuals.min_expiry_days_from_awarding AND gaming_bonus_rules_manuals.max_expiry_days_from_awarding,
								DATE_ADD(NOW(), INTERVAL gaming_bonus_bulk_players.expirey_days_from_awarding DAY) BETWEEN gaming_bonus_rules_manuals.min_expiry_date_fixed AND gaming_bonus_rules_manuals.max_expiry_date_fixed
							)
					) 
					OR 
					(
						gaming_bonus_bulk_players.expirey_date IS NOT NULL AND
						IF(gaming_bonus_rules_manuals.min_expiry_date_fixed IS NOT NULL,
							gaming_bonus_bulk_players.expirey_date BETWEEN gaming_bonus_rules_manuals.min_expiry_date_fixed AND gaming_bonus_rules_manuals.max_expiry_date_fixed,
							DATEDIFF(gaming_bonus_bulk_players.expirey_date ,NOW()) BETWEEN gaming_bonus_rules_manuals.min_expiry_days_from_awarding AND gaming_bonus_rules_manuals.max_expiry_days_from_awarding
						   )
					)
				) ,0,1),
		invalid_client = IF (gaming_client_stats.client_stat_id IS NULL,1,0),
		not_in_bonus_selection = IF (CS.client_stat_id IS NULL,1,0),
		limit_awarded_reached =  IF (award_bonus_max > 0  AND award_bonus_max <= IFNULL(num_times_awarded,0),1,0)
	WHERE bonus_bulk_counter_id = bonusBulkCounterID AND is_given=0;

	UPDATE gaming_bonus_bulk_players
	SET is_invalid =0
	WHERE bonus_bulk_counter_id = bonusBulkCounterID AND not_in_bonus_selection=0 AND invalid_client=0 AND invalid_expiry=0 AND invalid_amount = 0 AND invalid_wager =0 AND limit_awarded_reached = 0;

  SET statusCode=0;
END root$$

DELIMITER ;

