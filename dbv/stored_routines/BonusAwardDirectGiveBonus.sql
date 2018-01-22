DROP procedure IF EXISTS `BonusAwardDirectGiveBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusAwardDirectGiveBonus`(bonusRuleID BIGINT, ignoreAwardingDate TINYINT(1), OUT statusCode INT)
root:BEGIN
  
  -- Optimized for not locking the players, insert in batches of 10000 or my setting if exits.  
  -- Removed temporary table but rather use the standard gaming_player_selection_counter_players.
  -- Made also for BONUS_PRE_AUTH in batches
  -- Added STRAIGHT JOIN when joining players  
  -- Fixed bug that if bonus is disactivated while awarding bonuses it was not quiting. Also deleting gaming_player_selection_counter_players before existing
  -- Super Optimized by removing inserts of player from player selection but simply joining with the cache.

 DECLARE bonusRuleAwardCounterID BIGINT DEFAULT -1;
  DECLARE CWFreeRoundCounterID BIGINT DEFAULT -1;
  DECLARE bonusEnabledFlag, bonusFreeGiveEnabledFlag, bonusPreAuth, allowAwardingBonuses, isFreeRounds TINYINT DEFAULT 0;
  DECLARE bonusRuleIDCheck, playerSelectionID BIGINT DEFAULT -1;
  DECLARE bonusAmount DECIMAL(18, 5); 
  DECLARE batchSize INT DEFAULT 10000;
  DECLARE numPlayerSelected INT DEFAULT 0;
  DECLARE numToAward, awardedTimes INT DEFAULT 0;  
  DECLARE awardedTimesThreshold INT DEFAULT NULL;

  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  SELECT value_bool INTO bonusFreeGiveEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_FREE_GIVE_ENABLED';
  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
  SELECT value_int  INTO batchSize FROM gaming_settings WHERE name='BONUS_BULK_BATCH_SIZE';  

	IF NOT (bonusEnabledFlag AND bonusFreeGiveEnabledFlag) THEN
    SET statusCode=0;
    LEAVE root;
  END IF;
  
  SELECT gaming_bonus_rules.bonus_rule_id, gaming_bonus_rules.player_selection_id, rule_amounts.amount, gaming_bonus_rules.awarded_times, gaming_bonus_rules.awarded_times_threshold, gaming_bonus_rules.is_free_rounds
  INTO bonusRuleIDCheck, playerSelectionID, bonusAmount, awardedTimes, awardedTimesThreshold, isFreeRounds
  FROM gaming_bonus_rules 
  JOIN gaming_bonus_rules_direct_gvs AS direct_gvs ON gaming_bonus_rules.bonus_rule_id=direct_gvs.bonus_rule_id 
  JOIN gaming_operators ON gaming_operators.is_main_operator
  JOIN gaming_bonus_rules_direct_gvs_amounts AS rule_amounts ON direct_gvs.bonus_rule_id=rule_amounts.bonus_rule_id AND gaming_operators.currency_id=rule_amounts.currency_id
  WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleID AND gaming_bonus_rules.allow_awarding_bonuses=1 AND (ignoreAwardingDate OR gaming_bonus_rules.activation_start_date<=DATE_ADD(NOW(), INTERVAL 5 MINUTE));
  
  IF (bonusRuleIDCheck <> bonusRuleID) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

   IF (awardedTimesThreshold IS NOT NULL) THEN
	  SELECT COUNT(CS.client_stat_id) INTO numToAward    
	  FROM gaming_player_selections_player_cache AS CS
	  LEFT JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_rule_id=bonusRuleID AND CS.client_stat_id=gaming_bonus_instances.client_stat_id
	  LEFT JOIN gaming_bonus_instances_pre ON gaming_bonus_instances_pre.bonus_rule_id=bonusRuleID AND CS.client_stat_id=gaming_bonus_instances_pre.client_stat_id
	  WHERE (CS.player_selection_id=playerSelectionID AND CS.player_in_selection=1) AND (gaming_bonus_instances.client_stat_id IS NULL AND gaming_bonus_instances_pre.client_stat_id IS NULL);

	  IF (numToAward > (awardedTimesThreshold - awardedTimes)) THEN
		UPDATE gaming_bonus_rules SET allow_awarding_bonuses=0 WHERE bonus_rule_id=bonusRuleID;

		SET statusCode=2;
		LEAVE root;
	  END IF;
  END IF;

  COMMIT;

  SET statusCode=0;

	REPEAT
        SET allowAwardingBonuses=0;
		SELECT 1 INTO allowAwardingBonuses FROM gaming_bonus_rules WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleID AND gaming_bonus_rules.allow_awarding_bonuses=1;
        IF (allowAwardingBonuses = 0) THEN 
			LEAVE root; 
		END IF;

        START TRANSACTION;  

		IF (isFreeRounds=1) THEN

			INSERT INTO gaming_cw_free_round_counter (timestamp) VALUES (NOW());
			SET CWFreeRoundCounterID = LAST_INSERT_ID();

			INSERT INTO gaming_cw_free_rounds
				(client_stat_id,cw_free_round_status_id,date_created,cost_per_round,free_rounds_awarded,free_rounds_remaining,win_total,game_manufacturer_id,bonus_rule_id,expiry_date,cw_free_round_counter_id,wager_requirement_multiplier)
			SELECT gaming_client_stats.client_stat_id,cw_free_round_status_id,NOW(),cost_per_round,IFNULL(gaming_bonus_rules.num_free_rounds,gaming_bonus_free_round_profiles.num_rounds),
				IFNULL(gaming_bonus_rules.num_free_rounds,gaming_bonus_free_round_profiles.num_rounds),0,gaming_bonus_free_round_profiles.game_manufacturer_id,gaming_bonus_rules.bonus_rule_id,
				IFNULL(LEAST(free_round_expiry_date, gaming_bonus_free_round_profiles.end_date),LEAST(DATE_ADD(NOW(), INTERVAL free_round_expiry_days DAY),gaming_bonus_free_round_profiles.end_date)),CWFreeRoundCounterID,wager_requirement_multiplier
			FROM gaming_bonus_rules
			JOIN gaming_bonus_rules_direct_gvs ON 
				gaming_bonus_rules.bonus_rule_id=bonusRuleID AND 
				gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_direct_gvs.bonus_rule_id 
			 STRAIGHT_JOIN  
			  (
				  SELECT CS.client_stat_id
				  FROM gaming_player_selections_player_cache AS CS
				  LEFT JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_rule_id=bonusRuleID AND CS.client_stat_id=gaming_bonus_instances.client_stat_id
				  LEFT JOIN gaming_bonus_instances_pre ON gaming_bonus_instances_pre.bonus_rule_id=bonusRuleID AND CS.client_stat_id=gaming_bonus_instances_pre.client_stat_id
				  WHERE (CS.player_selection_id=playerSelectionID AND CS.player_in_selection=1) AND (gaming_bonus_instances.client_stat_id IS NULL AND gaming_bonus_instances_pre.client_stat_id IS NULL)
				  LIMIT batchSize	
			  ) AS selected_players ON 1=1
			STRAIGHT_JOIN gaming_client_stats ON selected_players.client_stat_id=gaming_client_stats.client_stat_id 
            JOIN gaming_bonus_rule_free_round_profiles ON gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id = 
				 (
					SELECT bonus_free_round_profile_id 
					FROM gaming_bonus_rule_free_round_profiles 
					WHERE gaming_bonus_rule_free_round_profiles.bonus_rule_id = bonusRuleID
					LIMIT 1  #If bonus rule is linked to multiple profiles, only 1 will be used. (All of them must have same cost per spin and number of free rounds)
				  ) AND gaming_bonus_rule_free_round_profiles.bonus_rule_id = bonusRuleID
			JOIN gaming_bonus_free_round_profiles ON gaming_bonus_free_round_profiles.bonus_free_round_profile_id = gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id
			JOIN gaming_bonus_free_round_profiles_amounts ON gaming_bonus_free_round_profiles_amounts.bonus_free_round_profile_id = gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id
				AND gaming_bonus_free_round_profiles_amounts.currency_id = gaming_client_stats.currency_id
			JOIN gaming_cw_free_round_statuses ON gaming_cw_free_round_statuses.name = IF(bonusPreAuth,'OnAwardedAwaitingPreAuth','OnAwarded')
			WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleID AND is_free_rounds = 1
			LIMIT batchSize;
		  
		END IF;
		IF (bonusPreAuth=0) THEN
			INSERT INTO gaming_bonus_rule_award_counter(bonus_rule_id, date_created)
			SELECT bonusRuleID, NOW();
		  
			SET bonusRuleAwardCounterID=LAST_INSERT_ID();	

			INSERT INTO gaming_bonus_instances (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, bonus_rule_award_counter_id, transfer_every_x, transfer_every_amount,cw_free_round_id,is_free_rounds,is_free_rounds_mode) 
			SELECT priority, bonus_amount, bonus_amount, bonus_amount*wager_requirement_multiplier, bonus_amount*wager_requirement_multiplier, NOW(), expiry_date, bonus_rule_id, client_stat_id, bonusRuleAwardCounterID, transfer_every_x, transfer_every_amount,cw_free_round_id,IF(cw_free_round_id IS NULL,0,1),IF(cw_free_round_id IS NULL,0,1)
			FROM
			(
				SELECT priority, bonus_amount, wager_requirement_multiplier, expiry_date, bonus_rule_id, client_stat_id, transfer_every_x, transfer_every_amount ,cw_free_round_id
				FROM
				(
				  SELECT gaming_bonus_rules.priority, IF(gaming_bonus_rules.is_free_rounds=0,gaming_bonus_rules_direct_gvs_amounts.amount,0) AS bonus_amount, 
					IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
					gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, selected_players.client_stat_id,
					CASE gaming_bonus_types_release.name
					  WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
					  WHEN 'EveryReleaseAmount' THEN ROUND(gaming_bonus_rules.wager_requirement_multiplier/(IF(gaming_bonus_rules.is_free_rounds=0,gaming_bonus_rules_direct_gvs_amounts.amount,0)/wager_restrictions.release_every_amount),2)
					  ELSE NULL
					END AS transfer_every_x, 
					CASE gaming_bonus_types_release.name
					  WHEN 'EveryXWager' THEN ROUND(IF(gaming_bonus_rules.is_free_rounds=0,gaming_bonus_rules_direct_gvs_amounts.amount,0)/(gaming_bonus_rules.wager_requirement_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
					  WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
					  ELSE NULL
					END AS transfer_every_amount,
					cw_free_round_id
				  FROM gaming_bonus_rules 
				  JOIN gaming_bonus_rules_direct_gvs ON 
					gaming_bonus_rules.bonus_rule_id=bonusRuleID AND 
					gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_direct_gvs.bonus_rule_id 
			  STRAIGHT_JOIN  
			  (
				  SELECT CS.client_stat_id
				  FROM gaming_player_selections_player_cache AS CS
				  LEFT JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_rule_id=bonusRuleID AND CS.client_stat_id=gaming_bonus_instances.client_stat_id
				  LEFT JOIN gaming_bonus_instances_pre ON gaming_bonus_instances_pre.bonus_rule_id=bonusRuleID AND CS.client_stat_id=gaming_bonus_instances_pre.client_stat_id
				  WHERE (CS.player_selection_id=playerSelectionID AND CS.player_in_selection=1) AND (gaming_bonus_instances.client_stat_id IS NULL AND gaming_bonus_instances_pre.client_stat_id IS NULL)
				  LIMIT batchSize	
			  ) AS selected_players ON 1=1
				  STRAIGHT_JOIN gaming_client_stats ON selected_players.client_stat_id=gaming_client_stats.client_stat_id 
				  JOIN gaming_bonus_rules_direct_gvs_amounts ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_direct_gvs_amounts.bonus_rule_id AND gaming_bonus_rules_direct_gvs_amounts.currency_id=gaming_client_stats.currency_id 
				  LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
				  LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
				  LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
				  LEFT JOIN gaming_cw_free_rounds ON gaming_cw_free_rounds.client_stat_id = gaming_client_stats.client_stat_id AND gaming_cw_free_rounds.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND cw_free_round_counter_id=CWFreeRoundCounterID
				  WHERE is_free_rounds = 0 OR gaming_cw_free_rounds.cw_free_round_id IS NOT NULL
				) AS CB
			) AS XX;
		   
			SET numPlayerSelected=ROW_COUNT();

			IF (numPlayerSelected > 0) THEN
			  SELECT COUNT(*) INTO @numPlayers
			  FROM gaming_bonus_instances FORCE INDEX (bonus_rule_award_counter_id)
			  JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
			  WHERE gaming_bonus_instances.bonus_rule_award_counter_id=bonusRuleAwardCounterID 
			  FOR UPDATE; 

			  CALL BonusOnAwardedUpdateStatsMultipleBonuses(bonusRuleAwardCounterID, 1);		  
			END IF;

			COMMIT;
		ELSE 
			SET allowAwardingBonuses=0;
			SELECT 1 INTO allowAwardingBonuses FROM gaming_bonus_rules WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleID AND gaming_bonus_rules.allow_awarding_bonuses=1;
			IF (allowAwardingBonuses=0) THEN 
				DELETE FROM gaming_player_selection_counter_players WHERE player_selection_counter_id=playerSelectionCounterID;
				LEAVE root;
			END IF;

			START TRANSACTION; 

			INSERT INTO gaming_bonus_instances_pre 
				(bonus_rule_id, client_stat_id, priority, bonus_amount, wager_requirement_multiplier, wager_requirement, expiry_date_fixed, expiry_days_from_awarding, extra_id, session_id, date_created, pre_expiry_date,cw_free_round_id)
			SELECT CB.bonus_rule_id, CB.client_stat_id, CB.priority, bonus_amount, wager_requirement_multiplier, CB.bonus_amount*wager_requirement_multiplier AS wager_requirement, 
			  expiry_date_fixed, expiry_days_from_awarding, NULL, NULL, NOW(), pre_expiry_date, cw_free_round_id
			FROM 
			(
			  SELECT gaming_bonus_rules.priority, IF(gaming_bonus_rules.is_free_rounds=0,gaming_bonus_rules_direct_gvs_amounts.amount,0) AS bonus_amount, expiry_date_fixed, expiry_days_from_awarding, gaming_bonus_rules.wager_requirement_multiplier, 
				gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id, gaming_client_stats.currency_id, date_add(now(), interval pre_expiry_days day) as pre_expiry_date,cw_free_round_id
			  FROM gaming_bonus_rules 
			  JOIN gaming_bonus_rules_direct_gvs ON 
				gaming_bonus_rules.bonus_rule_id=bonusRuleID AND 
				gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_direct_gvs.bonus_rule_id 
		  STRAIGHT_JOIN  
		  (
			  SELECT CS.client_stat_id
			  FROM gaming_player_selections_player_cache AS CS
			  LEFT JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_rule_id=bonusRuleID AND CS.client_stat_id=gaming_bonus_instances.client_stat_id
			  LEFT JOIN gaming_bonus_instances_pre ON gaming_bonus_instances_pre.bonus_rule_id=bonusRuleID AND CS.client_stat_id=gaming_bonus_instances_pre.client_stat_id
			  WHERE (CS.player_selection_id=playerSelectionID AND CS.player_in_selection=1) AND (gaming_bonus_instances.client_stat_id IS NULL AND gaming_bonus_instances_pre.client_stat_id IS NULL)
			  LIMIT batchSize	
		  ) AS selected_players ON 1=1 
			  STRAIGHT_JOIN gaming_client_stats ON selected_players.client_stat_id=gaming_client_stats.client_stat_id 
			  JOIN gaming_bonus_rules_direct_gvs_amounts ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_direct_gvs_amounts.bonus_rule_id AND gaming_bonus_rules_direct_gvs_amounts.currency_id=gaming_client_stats.currency_id 
			  LEFT JOIN gaming_cw_free_rounds ON gaming_cw_free_rounds.client_stat_id = gaming_client_stats.client_stat_id AND gaming_cw_free_rounds.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND cw_free_round_counter_id=CWFreeRoundCounterID
			  WHERE is_free_rounds = 0 OR gaming_cw_free_rounds.cw_free_round_id IS NOT NULL
			) AS CB 
			LIMIT batchSize;	
			
			SET numPlayerSelected=ROW_COUNT();
			
			COMMIT;
	  END IF;
	UNTIL numPlayerSelected < batchSize END REPEAT;

  
  UPDATE gaming_bonus_rules SET 
	allow_awarding_bonuses=(auto_re_enable AND is_active AND gaming_bonus_rules.activation_start_date<=NOW())
  WHERE bonus_rule_id=bonusRuleID;
  
  SET statusCode=0;

END root$$

DELIMITER ;

