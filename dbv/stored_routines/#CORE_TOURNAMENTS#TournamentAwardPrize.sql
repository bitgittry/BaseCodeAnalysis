DROP procedure IF EXISTS `TournamentAwardPrize`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentAwardPrize`(tournamentID BIGINT, OUT statusCode INT)
root:BEGIN

  -- Updating gaming_tournament_player_statuses.awarded_prize_amount so that in the leaderboard can return the amount awarded
  -- Converting stake amount using the exchange rate since the tournament profit is kept in the base currency
  
  DECLARE tournamentIDCheck, bonusRuleAwardCounterID, lockID, operatorID BIGINT DEFAULT -1;
  DECLARE prizesAwarded TINYINT(1) DEFAULT 0;
  DECLARE prizeType VARCHAR(20) DEFAULT NULL;
    
  SELECT operator_id INTO operatorID FROM gaming_operators WHERE is_main_operator LIMIT 1;

  SELECT tournament_id, prizes_awarded, prize_type INTO tournamentIDCheck, prizesAwarded, prizeType
  FROM gaming_tournaments 
  WHERE tournament_id=tournamentID AND gaming_tournaments.ranked=1 FOR UPDATE;
  
  IF (tournamentIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (prizesAwarded=1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  CASE prizeType
    WHEN 'CASH' THEN
      BEGIN
        
        INSERT INTO gaming_transaction_counter (date_created) VALUES (NOW());
        SET @transactionCounterID=LAST_INSERT_ID();
        
        INSERT INTO gaming_transaction_counter_amounts (transaction_counter_id, client_stat_id, amount)
        SELECT
          @transactionCounterID, gaming_tournament_player_statuses.client_stat_id, 
          (IFNULL(prize_amounts.amount,0) + (IF(tournament_profit<0,0,tournament_profit)*IFNULL(stake_profit_percentage,0)*IFNULL(percentage,0)*IFNULL(IFNULL(gaming_tournament_currencies.exchange_rate, gaming_operator_currency.exchange_rate),0)) + IFNULL(gaming_tournament_player_statuses.additional_prize,0)) AS prize_amount
        FROM gaming_tournaments 
        JOIN gaming_tournament_player_statuses ON gaming_tournaments.tournament_id = gaming_tournament_player_statuses.tournament_id
        LEFT JOIN gaming_tournament_prizes ON gaming_tournaments.tournament_id = gaming_tournament_prizes.tournament_id AND gaming_tournament_prizes.prize_position=gaming_tournament_player_statuses.rank
        LEFT JOIN gaming_tournament_prize_amounts AS prize_amounts ON prize_amounts.tournament_prize_id = gaming_tournament_prizes.tournament_prize_id AND prize_amounts.currency_id=gaming_tournament_player_statuses.currency_id
        LEFT JOIN gaming_tournament_share_place_percentage ON gaming_tournament_share_place_percentage.tournament_id = gaming_tournaments.tournament_id AND
              gaming_tournament_share_place_percentage.place=gaming_tournament_player_statuses.rank
		LEFT JOIN gaming_tournament_currencies ON gaming_tournament_currencies.tournament_id=gaming_tournaments.tournament_id AND gaming_tournament_player_statuses.currency_id=gaming_tournament_currencies.currency_id
        LEFT JOIN gaming_operator_currency ON gaming_tournament_player_statuses.currency_id=gaming_operator_currency.currency_id AND gaming_operator_currency.operator_id=operatorID
		WHERE (gaming_tournaments.tournament_id=tournamentID AND gaming_tournament_player_statuses.has_awarded_prize=0) AND 
          (prize_amounts.amount IS NOT NULL OR gaming_tournament_share_place_percentage.place IS NOT NULL OR 
            (gaming_tournament_player_statuses.additional_prize IS NOT NULL AND gaming_tournament_player_statuses.additional_prize!=0)) AND
          (IFNULL(prize_amounts.amount,0) + (IF(tournament_profit<0,0,tournament_profit)*IFNULL(stake_profit_percentage,0)*IFNULL(percentage,0)) + IFNULL(gaming_tournament_player_statuses.additional_prize,0))>0;
        
        SET @rowCount=ROW_COUNT();
        IF (@rowCount > 0) THEN
          CALL TransactionAdjustRealMoneyMultiple(@transactionCounterID, 'TournamentWin', tournamentID);
        
          UPDATE gaming_tournament_player_statuses
          JOIN gaming_transaction_counter_amounts AS counter_amounts ON 
            counter_amounts.transaction_counter_id=@transactionCounterID AND
            gaming_tournament_player_statuses.client_stat_id=counter_amounts.client_stat_id AND
			gaming_tournament_player_statuses.tournament_id=tournamentID AND gaming_tournament_player_statuses.is_active
          SET gaming_tournament_player_statuses.has_awarded_prize=1, gaming_tournament_player_statuses.awarded_prize_amount=counter_amounts.amount;
        
          DELETE FROM gaming_transaction_counter_amounts WHERE transaction_counter_id=@transactionCounterID;
        END IF;
        
      END;
    WHEN 'BONUS' THEN
      BEGIN
        INSERT INTO gaming_bonus_rule_award_counter(date_created)
        SELECT NOW();
  
        SET bonusRuleAwardCounterID=LAST_INSERT_ID();
        
        INSERT INTO gaming_bonus_instances 
          (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, bonus_rule_award_counter_id, award_selector, extra_id, transfer_every_x, transfer_every_amount)
        SELECT XX.priority, bonus_amount, bonus_amount, bonus_amount*XX.wager_requirement_multiplier, bonus_amount*XX.wager_requirement_multiplier, NOW(), XX.expiry_date, XX.bonus_rule_id, XX.client_stat_id, bonusRuleAwardCounterID, 't', tournamentID,
          CASE gaming_bonus_types_release.name
            WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
            WHEN 'EveryReleaseAmount' THEN ROUND(XX.wager_requirement_multiplier/(XX.bonus_amount/wager_restrictions.release_every_amount),2)
            ELSE NULL
          END,
          CASE gaming_bonus_types_release.name
            WHEN 'EveryXWager' THEN ROUND(XX.bonus_amount/(XX.wager_requirement_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
            WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
            ELSE NULL
          END
        FROM
        (
          SELECT
            gaming_bonus_rules.priority, (IFNULL(prize_amounts.amount,0) + (IF(tournament_profit<0,0,tournament_profit)*IFNULL(stake_profit_percentage,0)*IFNULL(percentage,0)*IFNULL(IFNULL(gaming_tournament_currencies.exchange_rate, gaming_operator_currency.exchange_rate),0)) + IFNULL(gaming_tournament_player_statuses.additional_prize,0)) AS bonus_amount, 
            IFNULL(gaming_tournament_prizes.wager_requirement_multiplier, gaming_bonus_rules.wager_requirement_multiplier) AS wager_requirement_multiplier,
            IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, gaming_bonus_rules.bonus_rule_id, gaming_tournament_player_statuses.client_stat_id,
            gaming_tournament_player_statuses.currency_id
          FROM gaming_tournaments 
          JOIN gaming_bonus_rules ON gaming_tournaments.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
          JOIN gaming_tournament_player_statuses ON gaming_tournaments.tournament_id = gaming_tournament_player_statuses.tournament_id
          LEFT JOIN gaming_tournament_prizes ON gaming_tournaments.tournament_id = gaming_tournament_prizes.tournament_id AND gaming_tournament_prizes.prize_position=gaming_tournament_player_statuses.rank
          LEFT JOIN gaming_tournament_prize_amounts AS prize_amounts ON prize_amounts.tournament_prize_id = gaming_tournament_prizes.tournament_prize_id AND 
                  prize_amounts.currency_id=gaming_tournament_player_statuses.currency_id
          LEFT JOIN gaming_tournament_share_place_percentage ON gaming_tournament_share_place_percentage.tournament_id = gaming_tournaments.tournament_id AND
                gaming_tournament_share_place_percentage.place=gaming_tournament_player_statuses.rank
          LEFT JOIN gaming_tournament_currencies ON gaming_tournament_currencies.tournament_id=gaming_tournaments.tournament_id AND gaming_tournament_player_statuses.currency_id=gaming_tournament_currencies.currency_id
          LEFT JOIN gaming_operator_currency ON gaming_tournament_player_statuses.currency_id=gaming_operator_currency.currency_id AND gaming_operator_currency.operator_id=operatorID
		  WHERE (gaming_tournaments.tournament_id=tournamentID AND gaming_tournament_player_statuses.has_awarded_prize=0) AND 
            (prize_amounts.amount IS NOT NULL OR gaming_tournament_share_place_percentage.place IS NOT NULL OR 
              (gaming_tournament_player_statuses.additional_prize IS NOT NULL AND gaming_tournament_player_statuses.additional_prize!=0))
        ) AS XX
        JOIN gaming_bonus_rules ON XX.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
        LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
        LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=XX.currency_id
        WHERE XX.bonus_amount>0;
        
        IF (ROW_COUNT() > 0) THEN
          
          INSERT INTO gaming_bonus_rule_award_counter_client_stats(bonus_rule_award_counter_id, bonus_instance_id, client_stat_id)
          SELECT bonusRuleAwardCounterID, gaming_bonus_instances.bonus_instance_id, gaming_client_stats.client_stat_id
          FROM gaming_client_stats 
          JOIN gaming_bonus_instances ON 
            gaming_bonus_instances.bonus_rule_award_counter_id=bonusRuleAwardCounterID AND 
            gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
          FOR UPDATE;
            
          CALL BonusOnAwardedUpdateStatsMultipleBonuses(bonusRuleAwardCounterID, 0);
          
          
          UPDATE gaming_tournament_player_statuses
          JOIN gaming_bonus_rule_award_counter_client_stats AS award_counter_client_stat ON 
            award_counter_client_stat.bonus_rule_award_counter_id=bonusRuleAwardCounterID AND
            gaming_tournament_player_statuses.client_stat_id=award_counter_client_stat.client_stat_id AND
			gaming_tournament_player_statuses.tournament_id=tournamentID AND gaming_tournament_player_statuses.is_active
		  JOIN gaming_bonus_instances ON award_counter_client_stat.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
          SET gaming_tournament_player_statuses.has_awarded_prize=1, 
			  gaming_tournament_player_statuses.awarded_prize_amount=gaming_bonus_instances.bonus_amount_given;
          
          DELETE FROM gaming_bonus_rule_award_counter_client_stats
          WHERE bonus_rule_award_counter_id=bonusRuleAwardCounterID;
          
        END IF; 
      END;
    
    WHEN 'OUTPUT_ONLY' THEN
		BEGIN
        
        END;
    
  END CASE;
  
  UPDATE gaming_tournaments SET prizes_awarded=1 WHERE tournament_id=tournamentID;
  SET statusCode=0;
END root$$

DELIMITER ;

