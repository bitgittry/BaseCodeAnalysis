DROP procedure IF EXISTS `PromotionAwardPrizeForSingle`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionAwardPrizeForSingle`(promotionID BIGINT, promotionRecurrenceID BIGINT)
root: BEGIN
  -- Added cost per round instead of the default 1 EUR

  DECLARE promotionIDCheck, bonusRuleAwardCounterID, bonusRuleID, playerSelectionID, CWFreeRoundCounterID, bonusRuleIDCheck BIGINT DEFAULT -1;
  DECLARE numPlayersAwarded, numPlayersAwardedPerOccurence INT DEFAULT 0;
  DECLARE singlePromotionsEnabled, isFreeRounds, bonusPreAuth TINYINT(1) DEFAULT 0;
  DECLARE prizeType VARCHAR(80) DEFAULT NULL;
  
  SELECT value_bool INTO singlePromotionsEnabled FROM gaming_settings WHERE name='PROMOTION_SINGLE_PROMOS_ENABLED';
	
  IF (singlePromotionsEnabled=0) THEN
	LEAVE root;
  END IF;

  SELECT promotion_id, num_players_awarded, prize_bonus_rule_id INTO promotionIDCheck, numPlayersAwarded, bonusRuleID
  FROM gaming_promotions 
  WHERE gaming_promotions.promotion_id=promotionID AND gaming_promotions.is_active=1 AND gaming_promotions.is_single=1 
	AND (gaming_promotions.award_prize_on_achievement = 1 OR gaming_promotions.award_prize_timing_type IN (1,2)) AND (award_num_players = 0 OR num_players_awarded<=award_num_players) 
  FOR UPDATE;

  SELECT gaming_promotions_prize_types.name INTO prizeType
  FROM gaming_promotions 
  JOIN gaming_promotions_prize_types ON gaming_promotions.promotion_prize_type_id=gaming_promotions_prize_types.promotion_prize_type_id
  WHERE promotion_id=promotionID;

  SELECT awarded_prize_count INTO numPlayersAwardedPerOccurence
  FROM gaming_promotions_recurrence_dates dates FORCE INDEX (PRIMARY)
  WHERE dates.promotion_recurrence_date_id = promotionRecurrenceID AND dates.promotion_id=promotionID AND dates.is_active = 1
  FOR UPDATE;  
 
  IF (promotionIDCheck=-1) THEN
    LEAVE root;
  END IF;
 
  SET @awardNum=numPlayersAwarded;
  SET @awardNumOccurence = numPlayersAwardedPerOccurence;

  CASE prizeType
    WHEN 'CASH' THEN
      BEGIN
        
        INSERT INTO gaming_transaction_counter (date_created) VALUES (NOW());
        SET @transactionCounterID=LAST_INSERT_ID();

        INSERT INTO gaming_transaction_counter_amounts(transaction_counter_id, client_stat_id, amount)
        SELECT @transactionCounterID, client_stat_id, prize_amount
        FROM 
        (
          SELECT @awardNum:= IF(pps.has_awarded_bonus, @awardNum, @awardNum+1) AS award_number, @awardNumOccurence:= IF(pps.has_awarded_bonus, @awardNumOccurence, @awardNumOccurence+1) AS occurence_award_number, gaming_promotions.award_num_players, gaming_client_stats.client_stat_id, 
           gaming_promotions.award_percentage * LEAST((pps.achieved_amount-single_achieved_amount_awarded), 
           prize_amounts.max_cap*(LEAST(gaming_promotions.single_repeat_for, pps.single_achieved_num-single_awarded_num))) AS prize_amount,
          IFNULL(gaming_promotions.award_num_players_per_occurence, 0) num_occurences
          FROM gaming_promotions  
          JOIN gaming_promotions_player_statuses AS pps ON gaming_promotions.promotion_id=promotionID AND gaming_promotions.promotion_id=pps.promotion_id  
          JOIN gaming_client_stats ON pps.client_stat_id=gaming_client_stats.client_stat_id 
          LEFT JOIN gaming_promotions_prize_amounts AS prize_amounts ON prize_amounts.promotion_id=gaming_promotions.promotion_id AND gaming_client_stats.currency_id=prize_amounts.currency_id
          WHERE (pps.achieved_amount-pps.single_achieved_amount_awarded)>0 
			AND (gaming_promotions.single_prize_per_transaction OR (pps.requirement_achieved=1 AND pps.has_awarded_bonus=0)) AND (pps.promotion_recurrence_date_id = promotionRecurrenceID OR promotionRecurrenceID=0)
        ) AS PB 
        WHERE (PB.award_num_players = 0 OR (PB.award_number <=PB.award_num_players)) AND IFNULL(prize_amount,0)>0 AND (PB.occurence_award_number <= PB.num_occurences OR PB.num_occurences = 0);
        
		
        SET @rowCount=ROW_COUNT();
     
        IF (@rowCount > 0) THEN
          CALL TransactionAdjustRealMoneyMultiple(@transactionCounterID, 'PromotionWinnings', promotionID);
          
          
          UPDATE gaming_promotions_player_statuses AS pps
          JOIN gaming_transaction_counter_amounts AS counter_amounts ON 
            counter_amounts.transaction_counter_id=@transactionCounterID AND
            pps.client_stat_id=counter_amounts.client_stat_id AND pps.promotion_id=promotionID AND
            (pps.promotion_recurrence_date_id = promotionRecurrenceID OR promotionRecurrenceID = 0)
          SET pps.has_awarded_bonus=1, pps.single_awarded_num=pps.single_achieved_num, pps.single_achieved_amount_awarded=pps.achieved_amount;
          
          DELETE FROM gaming_transaction_counter_amounts WHERE transaction_counter_id=@transactionCounterID;
        END IF;
      END;
    WHEN 'BONUS' THEN  
      BEGIN
        IF (bonusRuleID=-1 OR bonusRuleID IS NULL) THEN
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

		IF (isFreeRounds=1) THEN

			INSERT INTO gaming_cw_free_round_counter (timestamp) VALUES (NOW());
			SET CWFreeRoundCounterID = LAST_INSERT_ID();

			INSERT INTO gaming_cw_free_rounds
				(client_stat_id, cw_free_round_status_id, date_created, cost_per_round, free_rounds_awarded, free_rounds_remaining, win_total, game_manufacturer_id, bonus_rule_id,expiry_date, cw_free_round_counter_id, wager_requirement_multiplier)
			SELECT pps.client_stat_id, cw_free_round_status_id, NOW(), cost_per_round, 
				IF(gaming_promotions.is_percentage = 1, ROUND(gaming_promotions.award_percentage_free_rounds*LEAST(pps.achieved_amount, IFNULL(prize_amounts.max_cap,10000000000))/IFNULL(gaming_bonus_free_round_profiles_amounts.cost_per_round, 1*100)), IFNULL(gaming_promotions.award_num_free_rounds, gaming_bonus_free_round_profiles.num_rounds)),
				IF(gaming_promotions.is_percentage = 1, ROUND(gaming_promotions.award_percentage_free_rounds*LEAST(pps.achieved_amount, IFNULL(prize_amounts.max_cap,10000000000))/IFNULL(gaming_bonus_free_round_profiles_amounts.cost_per_round, 1*100)), IFNULL(gaming_promotions.award_num_free_rounds, gaming_bonus_free_round_profiles.num_rounds)), 
				0, gaming_bonus_free_round_profiles.game_manufacturer_id, gaming_bonus_rules.bonus_rule_id,
				IFNULL(LEAST(free_round_expiry_date, gaming_bonus_free_round_profiles.end_date), LEAST(DATE_ADD(NOW(), INTERVAL free_round_expiry_days DAY), gaming_bonus_free_round_profiles.end_date)), CWFreeRoundCounterID, wager_requirement_multiplier
			FROM gaming_bonus_rules
			JOIN gaming_promotions ON gaming_bonus_rules.bonus_rule_id = gaming_promotions.prize_bonus_rule_id
			JOIN gaming_promotions_player_statuses AS pps ON gaming_promotions.promotion_id=pps.promotion_id
            JOIN gaming_bonus_rule_free_round_profiles AS gbrfrp ON gbrfrp.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
			JOIN gaming_bonus_free_round_profiles ON gaming_bonus_free_round_profiles.bonus_free_round_profile_id = gbrfrp.bonus_free_round_profile_id
			JOIN gaming_bonus_free_round_profiles_amounts ON gaming_bonus_free_round_profiles_amounts.bonus_free_round_profile_id = gaming_bonus_free_round_profiles.bonus_free_round_profile_id
				AND gaming_bonus_free_round_profiles_amounts.currency_id = pps.currency_id
			JOIN gaming_cw_free_round_statuses ON gaming_cw_free_round_statuses.name = IF(bonusPreAuth,'OnAwardedAwaitingPreAuth','OnAwarded')
			LEFT JOIN gaming_promotions_prize_amounts AS prize_amounts ON prize_amounts.promotion_id=gaming_promotions.promotion_id AND pps.currency_id=prize_amounts.currency_id
			WHERE 
					gaming_bonus_rules.bonus_rule_id=bonusRuleID 
					AND is_free_rounds = 1
					AND gaming_promotions.promotion_id=promotionID 
					AND (
					
					(gaming_promotions.achieved_disabled = 1 AND pps.achieved_amount >= IFNULL(prize_amounts.min_cap, 0)) 
					
					OR requirement_achieved = 1)
					AND pps.has_awarded_bonus = 0 
					AND (pps.promotion_recurrence_date_id = promotionRecurrenceID OR promotionRecurrenceID=0)
			LIMIT 1;

		END IF;
      
        INSERT INTO gaming_bonus_rule_award_counter(bonus_rule_id, date_created)
        SELECT bonusRuleID, NOW();
        
        SET bonusRuleAwardCounterID=LAST_INSERT_ID();
        

        INSERT INTO gaming_bonus_instances 
          (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, extra_id, bonus_rule_award_counter_id, transfer_every_x, transfer_every_amount, award_selector, cw_free_round_id, is_free_rounds, is_free_rounds_mode)
        SELECT priority, bonus_amount, bonus_amount, bonus_amount*wager_requirement_multiplier, bonus_amount*wager_requirement_multiplier, NOW(), expiry_date, bonus_rule_id, client_stat_id, promotionID, bonusRuleAwardCounterID, transfer_every_x, transfer_every_amount, 'p', cw_free_round_id, IF(cw_free_round_id IS NULL,0,1), IF(cw_free_round_id IS NULL,0,1)
        FROM 
        (
          SELECT @awardNum:= IF(pps.has_awarded_bonus, @awardNum, @awardNum+1) AS award_number, @awardNumOccurence:= IF(pps.has_awarded_bonus, @awardNumOccurence, @awardNumOccurence+1) AS occurence_award_number,  gaming_promotions.award_num_players, gaming_bonus_rules.priority, 
			IF(isFreeRounds = 1, 0, gaming_promotions.award_percentage * LEAST((pps.achieved_amount-pps.single_achieved_amount_awarded), prize_amounts.max_cap*(LEAST(gaming_promotions.single_repeat_for, pps.single_achieved_num-single_awarded_num)))) AS bonus_amount,
            IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
            gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, pps.client_stat_id,
            IFNULL(gaming_promotions.award_num_players_per_occurence, 0) num_occurences,
            CASE gaming_bonus_types_release.name
              WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
              WHEN 'EveryReleaseAmount' THEN ROUND(gaming_bonus_rules.wager_requirement_multiplier/(gaming_bonus_rules_for_promotions_amounts.amount/wager_restrictions.release_every_amount),2)
              ELSE NULL
            END AS transfer_every_x, 
            CASE gaming_bonus_types_release.name
              WHEN 'EveryXWager' THEN ROUND(gaming_bonus_rules_for_promotions_amounts.amount/(gaming_bonus_rules.wager_requirement_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
              WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
              ELSE NULL
            END AS transfer_every_amount,
			cw_free_round_id
          FROM gaming_bonus_rules
          JOIN gaming_promotions ON gaming_bonus_rules.bonus_rule_id=gaming_promotions.prize_bonus_rule_id
          JOIN gaming_promotions_player_statuses AS pps ON gaming_promotions.promotion_id=pps.promotion_id  
          JOIN gaming_bonus_rules_for_promotions ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_for_promotions.bonus_rule_id
          JOIN gaming_bonus_rules_for_promotions_amounts ON 
            gaming_bonus_rules_for_promotions.bonus_rule_id=gaming_bonus_rules_for_promotions_amounts.bonus_rule_id AND
            pps.currency_id=gaming_bonus_rules_for_promotions_amounts.currency_id 
          LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
          LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
          LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=pps.currency_id
		  LEFT JOIN gaming_cw_free_rounds ON gaming_cw_free_rounds.client_stat_id = pps.client_stat_id AND gaming_cw_free_rounds.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND cw_free_round_counter_id=CWFreeRoundCounterID
		  JOIN gaming_promotions_prize_amounts AS prize_amounts ON prize_amounts.promotion_id=gaming_promotions.promotion_id AND pps.currency_id=prize_amounts.currency_id
          WHERE gaming_promotions.promotion_id=promotionID AND (pps.achieved_amount-pps.single_achieved_amount_awarded)>0 
			AND (gaming_promotions.single_prize_per_transaction OR (pps.requirement_achieved=1 AND pps.has_awarded_bonus=0)) AND (pps.promotion_recurrence_date_id = promotionRecurrenceID OR promotionRecurrenceID=0) 
		  AND (isFreeRounds = 0 OR gaming_cw_free_rounds.cw_free_round_id IS NOT NULL)
        ) AS PB
        WHERE (PB.award_num_players = 0 OR (PB.award_number <=PB.award_num_players)) 
			AND (IFNULL(bonus_amount,0)>0 OR (cw_free_round_id IS NOT NULL))
			AND (PB.occurence_award_number <= PB.num_occurences OR PB.num_occurences = 0);
          
        SET @rowCount=ROW_COUNT();
         
        IF (@rowCount > 0) THEN
          
          
          INSERT INTO gaming_bonus_rule_award_counter_client_stats(bonus_rule_award_counter_id, bonus_instance_id, client_stat_id)
          SELECT bonusRuleAwardCounterID, gaming_bonus_instances.bonus_instance_id, gaming_client_stats.client_stat_id
          FROM gaming_bonus_instances 
          JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
          WHERE gaming_bonus_instances.bonus_rule_award_counter_id=bonusRuleAwardCounterID
          FOR UPDATE;
            
          
          CALL BonusOnAwardedUpdateStatsMultipleBonuses(bonusRuleAwardCounterID, 1);
          
          
          UPDATE gaming_promotions_player_statuses AS pps
          JOIN gaming_bonus_rule_award_counter_client_stats AS award_counter_client_stat ON 
            award_counter_client_stat.bonus_rule_award_counter_id=bonusRuleAwardCounterID AND
            pps.client_stat_id=award_counter_client_stat.client_stat_id AND pps.promotion_id=promotionID AND
			 (pps.promotion_recurrence_date_id = promotionRecurrenceID OR promotionRecurrenceID = 0)
          SET pps.has_awarded_bonus=1, pps.single_awarded_num=pps.single_achieved_num, pps.single_achieved_amount_awarded=pps.achieved_amount;
          
          
          DELETE FROM gaming_bonus_rule_award_counter_client_stats WHERE bonus_rule_award_counter_id=bonusRuleAwardCounterID;
          
        END IF;
      END;  
	WHEN 'OUTPUT_ONLY' THEN
		BEGIN 
		END;
  END CASE;

  UPDATE gaming_promotions
  JOIN
  (
    SELECT COUNT(promotion_player_status_id) AS num_players_awarded
    FROM gaming_promotions_player_statuses
    WHERE promotion_id=promotionID AND has_awarded_bonus=1
  ) AS AwardedPrize ON 1=1
  SET gaming_promotions.num_players_awarded=AwardedPrize.num_players_awarded
  WHERE promotion_id=promotionID;


  UPDATE gaming_promotions_players_opted_in
  JOIN
  (
	SELECT COUNT(pps.has_awarded_bonus) AS num_awarded_prize, pps.client_stat_id
	FROM gaming_promotions_player_statuses AS pps 
    JOIN gaming_promotions ON gaming_promotions.promotion_id = pps.promotion_id
	WHERE pps.promotion_id = promotionID AND ((gaming_promotions.single_prize_per_transaction OR pps.requirement_achieved=1) AND pps.has_awarded_bonus=1)
    GROUP BY pps.client_stat_id
  ) AS AwardedPrize ON AwardedPrize.client_stat_id = gaming_promotions_players_opted_in.client_stat_id AND gaming_promotions_players_opted_in.promotion_id = promotionID
	SET gaming_promotions_players_opted_in.awarded_prize_count = AwardedPrize.num_awarded_prize;
	

	UPDATE gaming_promotions_recurrence_dates
	JOIN
	(
	  SELECT COUNT(pps.client_stat_id) AS NumAwared, pps.promotion_recurrence_date_id
	  FROM gaming_promotions_player_statuses AS pps
      JOIN gaming_promotions ON gaming_promotions.promotion_id = pps.promotion_id 
	  WHERE pps.promotion_id = promotionID AND ((gaming_promotions.single_prize_per_transaction OR pps.requirement_achieved=1) AND pps.has_awarded_bonus=1)
	  GROUP BY pps.promotion_recurrence_date_id
	)AS RP ON RP.promotion_recurrence_date_id = gaming_promotions_recurrence_dates.promotion_recurrence_date_id AND gaming_promotions_recurrence_dates.promotion_id = promotionID
	SET gaming_promotions_recurrence_dates.awarded_prize_count = RP.NumAwared;


END root$$

DELIMITER ;

