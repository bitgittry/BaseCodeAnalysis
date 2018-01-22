DROP procedure IF EXISTS `PromotionAwardPrizeToPlayers`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionAwardPrizeToPlayers`(promotionID BIGINT, recurrenceID BIGINT, sessionID BIGINT, selectedOnly TINYINT(1), OUT statusCode INT)
root: BEGIN
   -- Using actually the cost per round and only if not specified the default of 100 cents is used.
  -- Removed limit 1 when awarding free rounds 
  
  DECLARE promotionIDCheck, bonusRuleAwardCounterID, bonusRuleID, numAwardedInOccurrence, awardNumPerOccurrence, 
	playerSelectionID, CWFreeRoundCounterID, bonusRuleIDCheck, freeRoundProfileID BIGINT DEFAULT -1;
  DECLARE numPlayersAwarded, awardNumPlayers, randomlySelectStatusCode INT DEFAULT 0;
  DECLARE prizeType VARCHAR(80) DEFAULT NULL;
  DECLARE achievementEndDate, recurrence_end_date DATETIME;
  DECLARE hasGivenReward, achievedDisabled, isFreeRounds, bonusPreAuth TINYINT(1) DEFAULT 0;
  
  SELECT promotion_id, achievement_end_date, award_num_players, num_players_awarded, gaming_promotions_prize_types.name AS prize_type, 
  has_given_reward, prize_bonus_rule_id, achieved_disabled, award_num_players_per_occurence 
  INTO promotionIDCheck, achievementEndDate, awardNumPlayers, numPlayersAwarded, prizeType, 
	hasGivenReward, bonusRuleID, achievedDisabled, awardNumPerOccurrence
  FROM gaming_promotions 
  JOIN gaming_promotions_prize_types ON gaming_promotions.promotion_prize_type_id=gaming_promotions_prize_types.promotion_prize_type_id
  WHERE gaming_promotions.promotion_id=promotionID AND gaming_promotions.is_active=1
  FOR UPDATE;
  
  IF (promotionIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  IF (recurrenceID = 0 AND NOW() < achievementEndDate) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

  SELECT COUNT(*) INTO numAwardedInOccurrence 
  FROM gaming_promotions_player_statuses
  WHERE promotion_recurrence_date_id = recurrenceID AND has_awarded_bonus = 1;
  
  IF (hasGivenReward=1 OR (awardNumPlayers != 0 AND numPlayersAwarded>=awardNumPlayers) OR IFNULL(numAwardedInOccurrence,-1) > IFNULL(awardNumPerOccurrence,0)) THEN
     SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (prizeType='OUTPUT_ONLY') THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  IF (selectedOnly=0) THEN 
    SET randomlySelectStatusCode=0;
    CALL PromotionRandomlySelectPlayersToAward(promotionID, recurrenceID, sessionID, randomlySelectStatusCode);
  END IF;

  IF (randomlySelectStatusCode<>0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;
  
  SELECT end_date INTO recurrence_end_date
  FROM gaming_promotions_recurrence_dates
  WHERE gaming_promotions_recurrence_dates.promotion_id = promotionIDCheck AND promotion_recurrence_date_id = recurrenceID;
  
  IF (NOW() < recurrence_end_date) THEN
    SET statusCode=7;
    LEAVE root;
  END IF;
  
  SET @awardNum=numPlayersAwarded;
  SET @prizeAmount=0;

  CASE prizeType
    WHEN 'CASH' THEN
      BEGIN
        
        INSERT INTO gaming_transaction_counter (date_created) VALUES (NOW());
        SET @transactionCounterID=LAST_INSERT_ID();
        
        INSERT INTO gaming_transaction_counter_amounts(transaction_counter_id, client_stat_id, amount)
        SELECT @transactionCounterID, client_stat_id, ROUND(prize_amount, 0)
        FROM  
        (
          SELECT @awardNum:=@awardNum+1 AS award_number, gaming_promotions.award_num_players, gaming_client_stats.client_stat_id, 
            IFNULL(IF(gaming_promotions.is_percentage && gaming_promotions.player_net_loss_capping_enabled, gaming_promotions.award_percentage * LEAST(pps.achieved_amount, IFNULL(prize_amounts.max_cap,100000000*100), IF(depositsWithdrawals.deposits - depositsWithdrawals.withdrawals < 0, 0, depositsWithdrawals.deposits - depositsWithdrawals.withdrawals)),
			IF(gaming_promotions.is_percentage, gaming_promotions.award_percentage*LEAST(pps.achieved_amount, IFNULL(prize_amounts.max_cap,100000000*100)), prize_amounts.prize_amount)),0) AS prize_amount,  IFNULL(gaming_promotions.award_num_players_per_occurence, 0) AS num_occurences
          FROM gaming_promotions  
          JOIN gaming_promotions_player_statuses AS pps ON gaming_promotions.promotion_id=promotionID AND gaming_promotions.promotion_id=pps.promotion_id  
          JOIN gaming_client_stats ON pps.client_stat_id=gaming_client_stats.client_stat_id 
          LEFT JOIN gaming_promotions_prize_amounts AS prize_amounts ON prize_amounts.promotion_id=gaming_promotions.promotion_id AND gaming_client_stats.currency_id=prize_amounts.currency_id
          LEFT JOIN
		  (
				SELECT pps.promotion_recurrence_date_id, pps.promotion_player_status_id, pps.client_stat_id, IFNULL(SUM(IF(payment_transaction_type_id = 1, amount_real, 0)),0) AS deposits, IFNULL(SUM(IF(payment_transaction_type_id = 2, amount_real*-1, 0)),0) AS withdrawals 
				FROM gaming_promotions 
				JOIN gaming_promotions_player_statuses AS pps ON gaming_promotions.promotion_id=promotionID AND gaming_promotions.promotion_id=pps.promotion_id  
				LEFT JOIN gaming_promotions_recurrence_dates AS recurrences ON recurrences.promotion_recurrence_date_id = recurrenceID
				LEFT JOIN gaming_transactions ON pps.client_stat_id = gaming_transactions.client_stat_id AND gaming_transactions.timestamp BETWEEN IFNULL(recurrences.start_date, gaming_promotions.achievement_start_date) AND IFNULL(recurrences.end_date, gaming_promotions.achievement_end_date)					
				WHERE gaming_promotions.promotion_id = promotionID AND pps.promotion_recurrence_date_id = recurrenceID
				GROUP BY pps.promotion_player_status_id
		  ) depositsWithdrawals ON depositsWithdrawals.promotion_player_status_id = pps.promotion_player_status_id AND gaming_promotions.is_percentage && gaming_promotions.player_net_loss_capping_enabled
		 WHERE ((gaming_promotions.achieved_disabled=1 AND pps.achieved_amount>=IFNULL(prize_amounts.min_cap,0) ) OR requirement_achieved=1) AND pps.is_active=1 AND pps.selected_for_bonus=1 AND pps.has_awarded_bonus=0  
				AND (pps.promotion_recurrence_date_id = recurrenceID OR recurrenceID=0)
        ) AS PB 
        WHERE (PB.award_num_players = 0 OR PB.award_number <=PB.award_num_players) AND (PB.award_number <= PB.num_occurences OR PB.num_occurences = 0);
        
        SET @rowCount=ROW_COUNT();
        IF (@rowCount > 0) THEN
          CALL TransactionAdjustRealMoneyMultiple(@transactionCounterID, 'PromotionWinnings', promotionID);
        
          UPDATE gaming_promotions_player_statuses
          JOIN gaming_transaction_counter_amounts AS counter_amounts ON 
            counter_amounts.transaction_counter_id=@transactionCounterID AND
            (gaming_promotions_player_statuses.client_stat_id=counter_amounts.client_stat_id AND
            gaming_promotions_player_statuses.promotion_id=promotionID AND gaming_promotions_player_statuses.is_active AND gaming_promotions_player_statuses.is_current)
			AND (gaming_promotions_player_statuses.promotion_recurrence_date_id = recurrenceID OR recurrenceID=0)
          SET gaming_promotions_player_statuses.has_awarded_bonus=1, gaming_promotions_player_statuses.session_id=sessionID, 
			  gaming_promotions_player_statuses.requirement_achieved=1, 
			  gaming_promotions_player_statuses.requirement_achieved_date=IFNULL(gaming_promotions_player_statuses.requirement_achieved_date, NOW());
	

          DELETE FROM gaming_transaction_counter_amounts WHERE transaction_counter_id=@transactionCounterID;
        END IF;
        
      END;
    WHEN 'BONUS' THEN
      BEGIN
      
        IF (bonusRuleID=-1 OR bonusRuleID IS NULL) THEN
          SET statusCode=6;
          LEAVE root;
        END IF;

		SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';

		SELECT gaming_bonus_rules.bonus_rule_id, gaming_bonus_rules.is_free_rounds, gaming_bonus_rules.player_selection_id
		INTO bonusRuleIDCheck, isFreeRounds, playerSelectionID
		FROM gaming_bonus_rules 
		WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleID AND gaming_bonus_rules.allow_awarding_bonuses=1 
			AND (
			gaming_bonus_rules.activation_start_date<=DATE_ADD(NOW(), INTERVAL 5 MINUTE));

		IF (bonusRuleIDCheck <> bonusRuleID) THEN
			LEAVE root;
		END IF;
        
        SELECT bonus_free_round_profile_id INTO freeRoundProfileID FROM gaming_bonus_rule_free_round_profiles WHERE bonus_rule_id=bonusRuleID LIMIT 1;

		IF (isFreeRounds=1) THEN

			INSERT INTO gaming_cw_free_round_counter (timestamp) VALUES (NOW());
			SET CWFreeRoundCounterID = LAST_INSERT_ID();

			INSERT INTO gaming_cw_free_rounds
				(client_stat_id, cw_free_round_status_id, date_created, cost_per_round, free_rounds_awarded, free_rounds_remaining, win_total, 
                game_manufacturer_id, bonus_rule_id, expiry_date, cw_free_round_counter_id, wager_requirement_multiplier)
			SELECT client_stat_id, cw_free_round_status_id, date_created, cost_per_round, free_rounds_awarded, free_rounds_awarded, win_total, 
                 game_manufacturer_id, bonus_rule_id, expiry_date, cw_free_round_counter_id, wager_requirement_multiplier
            FROM
            (
				SELECT @awardNum:=@awardNum+1 AS award_number, IFNULL(gaming_promotions.award_num_players_per_occurence, 0) AS num_occurences,
					pps.client_stat_id, gaming_cw_free_round_statuses.cw_free_round_status_id, NOW() AS date_created, gaming_bonus_free_round_profiles_amounts.cost_per_round, 
					IF(gaming_promotions.is_percentage = 1, ROUND(gaming_promotions.award_percentage_free_rounds*LEAST(pps.achieved_amount, IFNULL(prize_amounts.max_cap,10000000000))/IFNULL(gaming_bonus_free_round_profiles_amounts.cost_per_round, 1*100)), IFNULL(gaming_promotions.award_num_free_rounds, gaming_bonus_free_round_profiles.num_rounds)) AS free_rounds_awarded,
					0 AS win_total, gaming_bonus_free_round_profiles.game_manufacturer_id, gaming_bonus_rules.bonus_rule_id,
					IFNULL(LEAST(free_round_expiry_date, gaming_bonus_free_round_profiles.end_date), LEAST(DATE_ADD(NOW(), INTERVAL free_round_expiry_days DAY),gaming_bonus_free_round_profiles.end_date)) AS expiry_date, 
					CWFreeRoundCounterID AS cw_free_round_counter_id, wager_requirement_multiplier
				FROM gaming_bonus_rules
				JOIN gaming_promotions ON gaming_bonus_rules.bonus_rule_id = gaming_promotions.prize_bonus_rule_id
				JOIN gaming_promotions_player_statuses AS pps ON gaming_promotions.promotion_id=pps.promotion_id
				JOIN gaming_bonus_free_round_profiles ON gaming_bonus_free_round_profiles.bonus_free_round_profile_id = freeRoundProfileID
				JOIN gaming_bonus_free_round_profiles_amounts ON gaming_bonus_free_round_profiles_amounts.bonus_free_round_profile_id = gaming_bonus_free_round_profiles.bonus_free_round_profile_id
					AND gaming_bonus_free_round_profiles_amounts.currency_id = pps.currency_id
				JOIN gaming_cw_free_round_statuses ON gaming_cw_free_round_statuses.name = IF(bonusPreAuth,'OnAwardedAwaitingPreAuth','OnAwarded')
				LEFT JOIN gaming_promotions_prize_amounts AS prize_amounts ON prize_amounts.promotion_id=gaming_promotions.promotion_id AND pps.currency_id=prize_amounts.currency_id
				WHERE 
					gaming_bonus_rules.bonus_rule_id=bonusRuleID 
					AND is_free_rounds = 1
					AND gaming_promotions.promotion_id = promotionID 
					AND (
					-- check requirement achieved for percentage
					(gaming_promotions.achieved_disabled = 1 AND pps.achieved_amount >= IFNULL(prize_amounts.min_cap, 0)) 
					-- check requirement achieved on amount
					OR requirement_achieved = 1)
					AND pps.has_awarded_bonus = 0 
					AND (pps.promotion_recurrence_date_id = recurrenceID OR recurrenceID=0)
			) AS PB
			WHERE (PB.award_number<=awardNumPlayers OR awardNumPlayers = 0) AND 
				(PB.award_number <= PB.num_occurences OR PB.num_occurences = 0);

			SET @awardNum=numPlayersAwarded;

		END IF;
        
        INSERT INTO gaming_bonus_rule_award_counter(bonus_rule_id, date_created)
        SELECT bonusRuleID, NOW();
        
        SET bonusRuleAwardCounterID=LAST_INSERT_ID();
        
        INSERT INTO gaming_bonus_instances 
          (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, extra_id, bonus_rule_award_counter_id, transfer_every_x, transfer_every_amount, award_selector, cw_free_round_id, is_free_rounds, is_free_rounds_mode)
        SELECT priority, bonus_amount, bonus_amount, bonus_amount*wager_requirement_multiplier, bonus_amount*wager_requirement_multiplier, NOW(), expiry_date, bonus_rule_id, client_stat_id, promotionID, bonusRuleAwardCounterID, transfer_every_x, transfer_every_amount, 'p', cw_free_round_id, IF(cw_free_round_id IS NULL, 0, 1), IF(cw_free_round_id IS NULL, 0, 1)
        FROM 
        (
         SELECT @awardNum:=@awardNum+1 AS award_number, gaming_promotions.award_num_players, 
            gaming_bonus_rules.priority, 
			@prizeAmount:= IF(isFreeRounds = 1, 0, ROUND(IF(gaming_promotions.is_percentage && gaming_promotions.player_net_loss_capping_enabled, gaming_promotions.award_percentage * LEAST(pps.achieved_amount, IFNULL(prize_amounts.max_cap,100000000*100), IF(depositsWithdrawals.deposits - depositsWithdrawals.withdrawals < 0, 0, depositsWithdrawals.deposits - depositsWithdrawals.withdrawals)),
							IF(gaming_promotions.is_percentage, gaming_promotions.award_percentage*LEAST(pps.achieved_amount, IFNULL(prize_amounts.max_cap,100000000*100)), IFNULL(prize_amounts.prize_amount, gaming_bonus_rules_for_promotions_amounts.amount))), 0)) AS bonus_amount,
            IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
            gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id,
            CASE gaming_bonus_types_release.name
              WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
              WHEN 'EveryReleaseAmount' THEN ROUND(gaming_bonus_rules.wager_requirement_multiplier/(@prizeAmount/wager_restrictions.release_every_amount),2)
              ELSE NULL
            END AS transfer_every_x, 
            CASE gaming_bonus_types_release.name
              WHEN 'EveryXWager' THEN ROUND(@prizeAmount/(gaming_bonus_rules.wager_requirement_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
              WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
              ELSE NULL
            END AS transfer_every_amount, IFNULL(gaming_promotions.award_num_players_per_occurence, 0) AS num_occurences,
			cw_free_round_id
          FROM gaming_bonus_rules
          JOIN gaming_promotions ON gaming_promotions.promotion_id=promotionID AND gaming_bonus_rules.bonus_rule_id=gaming_promotions.prize_bonus_rule_id
          JOIN gaming_promotions_player_statuses AS pps ON gaming_promotions.promotion_id=pps.promotion_id AND (pps.promotion_recurrence_date_id = recurrenceID OR recurrenceID = 0)
          JOIN gaming_client_stats ON pps.client_stat_id=gaming_client_stats.client_stat_id 
          JOIN gaming_bonus_rules_for_promotions ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_for_promotions.bonus_rule_id
          JOIN gaming_bonus_rules_for_promotions_amounts ON 
            gaming_bonus_rules_for_promotions.bonus_rule_id=gaming_bonus_rules_for_promotions_amounts.bonus_rule_id AND
            gaming_client_stats.currency_id=gaming_bonus_rules_for_promotions_amounts.currency_id 
          LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
          LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
          LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
          LEFT JOIN gaming_promotions_prize_amounts AS prize_amounts ON prize_amounts.promotion_id=gaming_promotions.promotion_id AND gaming_client_stats.currency_id=prize_amounts.currency_id
		  LEFT JOIN gaming_cw_free_rounds ON gaming_cw_free_rounds.client_stat_id = pps.client_stat_id AND gaming_cw_free_rounds.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND cw_free_round_counter_id=CWFreeRoundCounterID
		  LEFT JOIN
		  (
				SELECT pps.promotion_recurrence_date_id, pps.promotion_player_status_id, pps.client_stat_id, IFNULL(SUM(IF(payment_transaction_type_id = 1, amount_real, 0)),0) AS deposits, IFNULL(SUM(IF(payment_transaction_type_id = 2, amount_real, 0)),0) AS withdrawals 
				FROM gaming_promotions 
				JOIN gaming_promotions_player_statuses AS pps ON gaming_promotions.promotion_id=promotionID AND gaming_promotions.promotion_id=pps.promotion_id  
				LEFT JOIN gaming_promotions_recurrence_dates AS recurrences ON recurrences.promotion_recurrence_date_id = recurrenceID
				LEFT JOIN gaming_transactions ON pps.client_stat_id = gaming_transactions.client_stat_id AND gaming_transactions.timestamp BETWEEN IFNULL(recurrences.start_date, gaming_promotions.achievement_start_date) AND IFNULL(recurrences.end_date, gaming_promotions.achievement_end_date)					
				WHERE gaming_promotions.promotion_id = promotionID AND pps.promotion_recurrence_date_id = recurrenceID
				GROUP BY pps.promotion_player_status_id
		  ) depositsWithdrawals ON depositsWithdrawals.promotion_player_status_id = pps.promotion_player_status_id AND gaming_promotions.is_percentage && gaming_promotions.player_net_loss_capping_enabled 
          WHERE ((gaming_promotions.achieved_disabled=1 AND pps.achieved_amount>=IFNULL(prize_amounts.min_cap,0)) OR requirement_achieved=1) AND pps.selected_for_bonus=1 AND pps.has_awarded_bonus=0  
			AND (isFreeRounds = 0 OR gaming_cw_free_rounds.cw_free_round_id IS NOT NULL)
        ) AS PB 
        WHERE (PB.award_num_players = 0 OR PB.award_number <=PB.award_num_players) 
			AND (IFNULL(bonus_amount,0)>0 OR (cw_free_round_id IS NOT NULL))
			AND (PB.award_number <= PB.num_occurences OR PB.num_occurences = 0);
        
        SET @rowCount=ROW_COUNT();
        
        IF (@rowCount > 0) THEN
          
          
          INSERT INTO gaming_bonus_rule_award_counter_client_stats(bonus_rule_award_counter_id, bonus_instance_id, client_stat_id)
          SELECT bonusRuleAwardCounterID, gaming_bonus_instances.bonus_instance_id, gaming_client_stats.client_stat_id
          FROM gaming_bonus_instances 
          JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
          WHERE gaming_bonus_instances.bonus_rule_award_counter_id=bonusRuleAwardCounterID
          FOR UPDATE;
            
          CALL BonusOnAwardedUpdateStatsMultipleBonuses(bonusRuleAwardCounterID, 0);
          
          UPDATE gaming_promotions_player_statuses
          JOIN gaming_bonus_rule_award_counter_client_stats AS award_counter_client_stat ON 
            award_counter_client_stat.bonus_rule_award_counter_id=bonusRuleAwardCounterID AND
            (gaming_promotions_player_statuses.client_stat_id=award_counter_client_stat.client_stat_id AND
            gaming_promotions_player_statuses.promotion_id=promotionID AND gaming_promotions_player_statuses.is_active AND gaming_promotions_player_statuses.is_current)
			AND (gaming_promotions_player_statuses.promotion_recurrence_date_id = recurrenceID OR recurrenceID=0)
          SET gaming_promotions_player_statuses.has_awarded_bonus=1, gaming_promotions_player_statuses.session_id=sessionID,
			  gaming_promotions_player_statuses.requirement_achieved=1, 
              gaming_promotions_player_statuses.requirement_achieved_date=IFNULL(gaming_promotions_player_statuses.requirement_achieved_date, NOW());
      
          
          DELETE FROM gaming_bonus_rule_award_counter_client_stats
          WHERE bonus_rule_award_counter_id=bonusRuleAwardCounterID;
    
        END IF;
      END; 
    
  END CASE;
  
	  UPDATE gaming_promotions_players_opted_in
	  JOIN
	  (
		 SELECT COUNT(pps.has_awarded_bonus) AS num_awarded_prize, pps.client_stat_id
		 FROM gaming_promotions_player_statuses AS pps 
		 WHERE pps.promotion_id = promotionID AND pps.has_awarded_bonus = 1 AND pps.requirement_achieved=1
		 GROUP BY pps.client_stat_id
	  ) AS AwardedPrize ON AwardedPrize.client_stat_id = gaming_promotions_players_opted_in.client_stat_id AND gaming_promotions_players_opted_in.promotion_id = promotionID
	 SET gaming_promotions_players_opted_in.awarded_prize_count = AwardedPrize.num_awarded_prize;

	UPDATE gaming_promotions_recurrence_dates
	 JOIN
	 (
	   SELECT COUNT(pps.client_stat_id) AS NumAwared, pps.promotion_recurrence_date_id
	   FROM gaming_promotions_player_statuses AS pps 
	   WHERE  pps.promotion_id=promotionID AND pps.requirement_achieved=1 AND pps.has_awarded_bonus=1
	   GROUP BY pps.promotion_recurrence_date_id
	 )AS RP ON RP.promotion_recurrence_date_id = gaming_promotions_recurrence_dates.promotion_recurrence_date_id AND gaming_promotions_recurrence_dates.promotion_id = promotionID
	  SET gaming_promotions_recurrence_dates.awarded_prize_count = RP.NumAwared;

  UPDATE gaming_promotions
	  JOIN
	  (
		SELECT COUNT(promotion_player_status_id) AS num_players_awarded
		FROM gaming_promotions_player_statuses
		WHERE promotion_id=promotionID AND has_awarded_bonus=1
	  ) AS AwardedPrize ON 1=1
	  SET
		has_given_reward=1,
		gaming_promotions.num_players_awarded=AwardedPrize.num_players_awarded
	  WHERE promotion_id=promotionID
	  AND AwardedPrize.num_players_awarded>0;

  IF(recurrenceID != 0) THEN 
	  UPDATE gaming_promotions_recurrence_dates
	  JOIN
	  (
		SELECT COUNT(promotion_player_status_id) AS num_players_awarded
		FROM gaming_promotions_player_statuses
		WHERE promotion_id=promotionID AND has_awarded_bonus=1 AND promotion_recurrence_date_id = recurrenceID
	  ) AS AwardedPrize ON 1=1
	  SET
		gaming_promotions_recurrence_dates.awarded_prize_count=AwardedPrize.num_players_awarded
	  WHERE promotion_id=promotionID AND promotion_recurrence_date_id = recurrenceID
	  AND AwardedPrize.num_players_awarded>0;
	END IF;
	   
  SET statusCode=0;
END root$$

DELIMITER ;

