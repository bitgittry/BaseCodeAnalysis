DROP procedure IF EXISTS `PlaceBetBonusCashExchange`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceBetBonusCashExchange`(clientStatID BIGINT, gamePlayID BIGINT, sessionID BIGINT, transactionType VARCHAR(45), exchangeRate DECIMAL(18,5), bonusTransferedTotal DECIMAL(18,5), bonusTransfered DECIMAL(18,5), bonusWinLockedTransfered DECIMAL(18,5), bonusTransferedLost DECIMAL(18,5), bonusWinLockedTransferedLost DECIMAL(18,5),
		bonusInstanceID BIGINT,RingFencedAmount DECIMAL(18,5),RingFencedAmountSB DECIMAL(18,5),RingFencedAmountCasino DECIMAL(18,5),RingFencedAmountPoker DECIMAL(18,5), uniqueTransactionRef VARCHAR(45))
root:BEGIN  
    
DECLARE bonusTransferedLostTotal,FreeBonusAmount DECIMAL(18,5) DEFAULT 0;

UPDATE gaming_client_stats
        LEFT JOIN
    gaming_bonus_instances ON bonus_instance_id = bonusInstanceID
        LEFT JOIN
    (SELECT 
        COUNT(1) AS numBonuses
    FROM
        gaming_bonus_instances
    WHERE
        gaming_bonus_instances.client_stat_id = clientStatID
            AND is_active
            AND is_freebet_phase = 0
    GROUP BY client_stat_id) AS activeBonuses ON 1 = 1 
SET 
    current_real_balance = current_real_balance + bonusTransferedTotal,
    total_bonus_transferred = total_bonus_transferred + bonusTransfered,
    current_bonus_balance = current_bonus_balance - (bonusTransfered + bonusTransferedLost),
    total_bonus_win_locked_transferred = total_bonus_win_locked_transferred + bonusWinLockedTransfered,
    current_bonus_win_locked_balance = current_bonus_win_locked_balance - (bonusWinLockedTransfered + bonusWinLockedTransferedLost),
    total_bonus_transferred_base = total_bonus_transferred_base + ROUND(bonusTransferedTotal / exchangeRate, 5),
    gaming_client_stats.bet_from_real = IF(transactionType = 'RedeemBonus',
        IF(IFNULL(numBonuses, 0) = 0,
            0,
            IFNULL(gaming_client_stats.bet_from_real - gaming_bonus_instances.deposited_amount,
                    0)),
        IF(transactionType = 'BonusTurnedReal',
            IF(IFNULL(numBonuses, 0) = 0,
                0,
                gaming_client_stats.bet_from_real),
            gaming_client_stats.bet_from_real)),
    gaming_client_stats.current_ring_fenced_sb = current_ring_fenced_sb - RingFencedAmountSB,
    gaming_client_stats.current_ring_fenced_casino = current_ring_fenced_casino - RingFencedAmountCasino,
    gaming_client_stats.current_ring_fenced_poker = current_ring_fenced_poker - RingFencedAmountPoker,
    gaming_client_stats.current_ring_fenced_amount = gaming_client_stats.current_ring_fenced_amount - RingFencedAmount
WHERE
    gaming_client_stats.client_stat_id = clientStatID;
  
  
  SET bonusTransferedLostTotal = bonusTransferedLost+bonusWinLockedTransferedLost;
  IF (bonusTransferedLostTotal>0 AND transactionType != 'RedeemBonus') THEN
    INSERT INTO gaming_transactions
    (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, pending_bet_real, pending_bet_bonus, unique_transaction_ref) 
    SELECT gaming_payment_transaction_type.payment_transaction_type_id, bonusTransferedLostTotal*-1, ROUND(bonusTransferedLostTotal/exchangeRate, 5)*-1, gaming_client_stats.currency_id, exchangeRate, 0, bonusTransferedLost*-1, bonusWinLockedTransferedLost*-1, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance-bonusTransferedTotal, current_bonus_balance+bonusTransfered, current_bonus_win_locked_balance+bonusWinLockedTransfered, current_loyalty_points, gamePlayID, sessionID, gaming_client_stats.pending_bets_real, gaming_client_stats.pending_bets_bonus,  uniqueTransactionRef
    FROM gaming_client_stats  
    JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='BonusCap'
    WHERE client_stat_id=clientStatID; 
  END IF;


 
SELECT 
    SUM(win_bonus) - SUM(lost_win_bonus) + SUM(win_bonus_win_locked - lost_win_bonus_win_locked)
INTO FreeBonusAmount FROM
    gaming_game_plays_bonus_instances_wins
        JOIN
    gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_game_plays_bonus_instances_wins.bonus_instance_id
        JOIN
    gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
        JOIN
    gaming_game_plays_win_counter_bets ON gaming_game_plays_win_counter_bets.game_play_win_counter_id = gaming_game_plays_bonus_instances_wins.game_play_win_counter_id
        JOIN
    gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id = gaming_bonus_types_awarding.bonus_type_awarding_id
WHERE
    gaming_game_plays_win_counter_bets.win_game_play_id = gamePlayID
        AND (gaming_bonus_instances.is_secured
        OR is_free_bonus)
        AND (gaming_bonus_types_awarding.name = 'FreeBet'
        OR is_free_bonus = 1);

IF (FreeBonusAmount IS NULL AND transactionType = 'CashBonus') THEN
 -- if the bonus is cachBonus and there is no wagering (is_free_bonus = 1), the bonus was credited to FreeBet and now needs to be debit from FreeBet too.
	SELECT bonusTransfered INTO FreeBonusAmount
    FROM gaming_bonus_instances
    JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
    WHERE gaming_bonus_instances.bonus_instance_id = bonusInstanceID AND is_free_bonus = 1;
    
 END IF;
 
 IF (FreeBonusAmount IS NULL AND transactionType = 'RedeemBonus') THEN
 -- if the bonus is RedeemBonus, the bonus was credited to FreeBet and now needs to be debit from FreeBet too.
	SELECT bonusTransfered INTO FreeBonusAmount
    FROM gaming_bonus_instances
    JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id    
	JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
    WHERE gaming_bonus_instances.bonus_instance_id = bonusInstanceID  and gaming_bonus_types_awarding.name='FreeBet'
	AND gaming_bonus_instances.is_free_rounds_mode=0;    
 END IF;

IF (bonusTransferedTotal>0 || transactionType = 'RedeemBonus' || transactionType = 'CashBonus') THEN



	IF (transactionType = 'BonusRequirementMet') THEN 
		INSERT INTO gaming_transactions
		(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id,extra2_id, session_id, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus, unique_transaction_ref) 
		SELECT gaming_payment_transaction_type.payment_transaction_type_id, IFNULL(bonus_transfered,0)+IFNULL(bonus_win_locked_transfered,0), ROUND(IFNULL(bonus_transfered/exchangeRate,0)+IFNULL(bonus_win_locked_transfered/exchangeRate,0), 5), gaming_client_stats.currency_id, exchangeRate, IFNULL(bonus_transfered,0)+IFNULL(bonus_win_locked_transfered,0), IFNULL(bonus_transfered,0)*-1, IFNULL(bonus_win_locked_transfered,0)*-1, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points,
		 gamePlayID,gbi.bonus_instance_id, sessionID, gaming_client_stats.pending_bets_real, gaming_client_stats.pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`),uniqueTransactionRef
		FROM gaming_game_plays_bonus_instances AS ggpbi
		JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id = ggpbi.bonus_instance_id 
		JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gbi.bonus_rule_id
		JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gbi.client_stat_id
		JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=transactionType
		WHERE ggpbi.game_play_id=gamePlayID AND (gbi.is_secured OR gbi.is_freebet_phase) AND IFNULL(bonus_transfered,0)+IFNULL(bonus_win_locked_transfered,0) > 0;	

		INSERT INTO gaming_game_plays 
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_free_bet ,bonus_lost, bonus_win_locked_lost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
		SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, IFNULL(-FreeBonusAmount,0),bonusTransferedLost, bonusWinLockedTransferedLost, timestamp, client_id, client_stat_id, gaming_payment_transaction_type.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
		FROM gaming_transactions
		JOIN gaming_payment_transaction_type ON gaming_transactions.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id AND  gaming_payment_transaction_type.name=transactionType
		WHERE extra_id=gamePlayID;

		CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());  

	ELSEIF (transactionType = 'BonusTurnedReal') THEN
		INSERT INTO gaming_transactions
		(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, 
		 amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, 
		 client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, 
		 loyalty_points_after, extra_id,extra2_id, session_id, pending_bet_real, 
		 pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus, loyalty_points_after_bonus, unique_transaction_ref)
		SELECT  gaming_payment_transaction_type.payment_transaction_type_id, SUM(ROUND(ggpbi.win_real)), SUM(ROUND(ggpbi.win_real/exchangeRate, 5)), gaming_client_stats.currency_id, exchangeRate,
			    SUM(ROUND(ggpbi.win_real)) ,IF(gbi.is_freebet_phase OR gaming_bonus_rules.is_free_bonus,0,SUM((ggpbi.win_bonus-ggpbi.lost_win_bonus)) *-1), SUM((ggpbi.win_bonus_win_locked - ggpbi.lost_win_bonus_win_locked)) *-1, 0, NOW(), 
			    gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, 
				current_loyalty_points,gamePlayID,gbi.bonus_instance_id, sessionID, gaming_client_stats.pending_bets_real, 
				gaming_client_stats.pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)	, uniqueTransactionRef	 
		FROM gaming_game_plays_bonus_instances_wins AS ggpbi
		JOIN gaming_game_plays_bonus_instances ON gaming_game_plays_bonus_instances.game_play_bonus_instance_id = ggpbi.game_play_bonus_instance_id 
		JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id = ggpbi.bonus_instance_id 
		JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gbi.bonus_rule_id
		JOIN gaming_game_plays_win_counter_bets ON gaming_game_plays_win_counter_bets.game_play_win_counter_id = ggpbi.game_play_win_counter_id
					AND gaming_game_plays_bonus_instances.game_play_id=gaming_game_plays_win_counter_bets.game_play_id
		JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gbi.client_stat_id
		JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=transactionType
		WHERE gaming_game_plays_win_counter_bets.win_game_play_id=gamePlayID AND (gbi.is_secured OR is_free_bonus OR gbi.is_freebet_phase)
		GROUP BY gbi.bonus_instance_id;

		INSERT INTO gaming_game_plays 
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, bonus_lost, bonus_win_locked_lost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,bet_from_real,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
		SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,IFNULL(-FreeBonusAmount,0), bonusTransferedLost, bonusWinLockedTransferedLost, timestamp, gaming_transactions.client_id, gaming_transactions.client_stat_id, gaming_payment_transaction_type.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, gaming_transactions.currency_id, gaming_transactions.session_id, gaming_transactions.transaction_id, gaming_transactions.pending_bet_real, gaming_transactions.pending_bet_bonus,bet_from_real,gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
		FROM gaming_transactions
		JOIN gaming_payment_transaction_type ON gaming_transactions.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id AND gaming_payment_transaction_type.name=transactionType
		JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_transactions.client_stat_id
		WHERE extra_id=gamePlayID;
		
		CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());  

	ELSE
		INSERT INTO gaming_transactions
		(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id,extra2_id, session_id, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus,unique_transaction_ref) 
		SELECT gaming_payment_transaction_type.payment_transaction_type_id, bonusTransferedTotal, ROUND(bonusTransferedTotal/exchangeRate, 5), gaming_client_stats.currency_id, exchangeRate, bonusTransferedTotal, bonusTransfered*-1, bonusWinLockedTransfered*-1, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, gamePlayID,bonusInstanceID, sessionID, gaming_client_stats.pending_bets_real, gaming_client_stats.pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`),uniqueTransactionRef
		FROM gaming_client_stats  
		JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=transactionType
		WHERE client_stat_id=clientStatID; 

		SET @transactionID=LAST_INSERT_ID();
        
		INSERT INTO gaming_game_plays 
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, bonus_lost, bonus_win_locked_lost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
		SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,IFNULL(-FreeBonusAmount,0), bonusTransferedLost, bonusWinLockedTransferedLost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
		FROM gaming_transactions
		WHERE transaction_id=@transactionID;
		
		CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());  
	END IF;


	IF    (IFNULL(gamePlayID,'') <> '')       THEN
		INSERT INTO gaming_bonus_rules_rec_met (bonus_rule_id,bonus_transfered)
		SELECT gaming_bonus_rules.bonus_rule_id,IFNULL(ROUND(ggpbi.bonus_transfered_total/exchangeRate, 0),0) FROM gaming_bonus_rules
				JOIN gaming_game_plays_bonus_instances AS ggpbi ON ggpbi.game_play_id=gamePlayID AND ggpbi.now_wager_requirement_met
				JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id AND gaming_bonus_rules.bonus_rule_id=gaming_bonus_instances.bonus_rule_id;   
	ELSE
		INSERT INTO gaming_bonus_rules_rec_met (bonus_rule_id,bonus_transfered)
		SELECT 		gbi.bonus_rule_id,IFNULL(ROUND(bonusTransfered/exchangeRate, 0),0) 
		FROM 		gaming_bonus_rules gbr
					JOIN gaming_bonus_instances gbi 
						ON gbi.bonus_instance_id =  bonusInstanceID 
						AND gbr.bonus_rule_id = gbi.bonus_rule_id;  
	END IF;

  END IF; 

  IF (transactionType = 'BonusRequirementMet') THEN 
        
      -- update parent bonus rule's selection (flag and number of included players) when it is part of chained bonuses (prerequisites)  
      UPDATE gaming_game_plays_bonus_instances AS inst
      JOIN gaming_bonus_rules_pre_rules AS pre ON inst.bonus_rule_id  = pre.pre_bonus_rule_id
      JOIN gaming_bonus_rules_pre_rules AS parent ON pre.bonus_rule_id  = parent.bonus_rule_id
      JOIN gaming_bonus_rules AS rule ON parent.bonus_rule_id = rule.bonus_rule_id AND rule.linking_type = 'REDEEMED'
      JOIN gaming_player_selections AS sel ON rule.player_selection_id=sel.player_selection_id
      SET sel.selected_players = 1, sel.num_players = sel.num_players + 1
      WHERE inst.game_play_id = gamePlayID AND rule.num_prerequisites_or IS NOT NULL AND rule.empty_selection = 1;
  
	  INSERT INTO gaming_player_selections_selected_players (player_selection_id, client_stat_id, include_flag, exclude_flag) 
	  SELECT player_selection_id,client_stat_id,1,0
	  FROM (
		  SELECT bonuses.bonus_rule_id,SUM(IF(achieved = 1, 1, 0)) AS achieved, client_stat_id,player_selection_id, bonuses.num_prerequisites_or AS num_prerequisites_or
		  FROM (
			  SELECT parentRule.bonus_rule_id,IF(bonusChildren.bonus_rule_id IS NULL,0,1) AS achieved,ggpbi.client_stat_id,player_selection_id, num_prerequisites_or
			  FROM gaming_game_plays_bonus_instances AS ggpbi
			  JOIN gaming_bonus_rules_pre_rules gbrpr ON ggpbi.bonus_rule_id  = gbrpr.pre_bonus_rule_id
			  JOIN gaming_bonus_rules_pre_rules parentRule ON gbrpr.bonus_rule_id = parentRule.bonus_rule_id
			  JOIN gaming_bonus_rules ON parentRule.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND linking_type = 'REDEEMED'
			  LEFT JOIN gaming_bonus_instances bonusChildren ON parentRule.pre_bonus_rule_id = bonusChildren.bonus_rule_id AND bonusChildren.client_stat_id = ggpbi.client_stat_id AND bonusChildren.is_secured
			  WHERE ggpbi.game_play_id = gamePlayID
		  ) AS bonuses
		  GROUP BY bonuses.bonus_rule_id
		  HAVING (num_prerequisites_or IS NOT NULL AND achieved >= num_prerequisites_or)
	  ) AS players
	  ON DUPLICATE KEY UPDATE include_flag=1;
	
	  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date)
	  SELECT player_selection_id, client_stat_id, 1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = players.player_selection_id)  MINUTE) 
	  FROM (
		  SELECT bonuses.bonus_rule_id,SUM(IF(achieved = 1, 1, 0)) AS achieved,client_stat_id,player_selection_id, bonuses.num_prerequisites_or AS num_prerequisites_or
		  FROM (
			  SELECT parentRule.bonus_rule_id,IF(bonusChildren.bonus_rule_id IS NULL,0,1) AS achieved,ggpbi.client_stat_id,player_selection_id, num_prerequisites_or
			  FROM gaming_game_plays_bonus_instances AS ggpbi
			  JOIN gaming_bonus_rules_pre_rules gbrpr ON ggpbi.bonus_rule_id  = gbrpr.pre_bonus_rule_id
			  JOIN gaming_bonus_rules_pre_rules parentRule ON gbrpr.bonus_rule_id = parentRule.bonus_rule_id
			  JOIN gaming_bonus_rules ON parentRule.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND linking_type = 'REDEEMED'
			  LEFT JOIN gaming_bonus_instances bonusChildren ON parentRule.pre_bonus_rule_id = bonusChildren.bonus_rule_id AND bonusChildren.client_stat_id = ggpbi.client_stat_id AND bonusChildren.is_secured
			  WHERE ggpbi.game_play_id = gamePlayID
		  ) AS bonuses
		  GROUP BY bonuses.bonus_rule_id
		  HAVING (num_prerequisites_or IS NOT NULL AND achieved >= num_prerequisites_or)
	  ) AS players
		  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND gaming_player_selections_player_cache.expiry_date IS NULL, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
								  gaming_player_selections_player_cache.player_in_selection=IF(VALUES(player_in_selection), IF(gaming_player_selections_player_cache.expiry_date<NOW(),0,1), 0),
								  gaming_player_selections_player_cache.last_updated=NOW();

  ELSEIF (transactionType = 'RedeemBonus') THEN
        
      -- update parent bonus rule's selection (flag and number of included players) when it is part of chained bonuses (prerequisites)  
      UPDATE gaming_bonus_instances AS inst
      JOIN gaming_bonus_rules_pre_rules AS pre ON inst.bonus_rule_id  = pre.pre_bonus_rule_id
      JOIN gaming_bonus_rules_pre_rules AS parent ON pre.bonus_rule_id  = parent.bonus_rule_id
      JOIN gaming_bonus_rules AS rule ON parent.bonus_rule_id = rule.bonus_rule_id AND rule.linking_type = 'REDEEMED'
      JOIN gaming_player_selections AS sel ON rule.player_selection_id=sel.player_selection_id
      SET sel.selected_players = 1, sel.num_players = sel.num_players + 1
      WHERE inst.bonus_instance_id = bonusInstanceID AND rule.num_prerequisites_or IS NOT NULL AND rule.empty_selection = 1;

	  INSERT INTO gaming_player_selections_selected_players (player_selection_id, client_stat_id, include_flag, exclude_flag) 
	  SELECT players.player_selection_id,players.client_stat_id,1,0
	  FROM (
		  SELECT bonuses.bonus_rule_id, SUM(IF(achieved = 1, 1, 0)) AS achieved,client_stat_id,player_selection_id, bonuses.num_prerequisites_or AS num_prerequisites_or
		  FROM (
			  SELECT parentRule.bonus_rule_id,IF(bonusChildren.bonus_rule_id IS NULL,0,1) AS achieved,gbi.client_stat_id,player_selection_id, num_prerequisites_or
			  FROM gaming_bonus_instances gbi
			  JOIN gaming_bonus_rules_pre_rules gbrpr ON gbi.bonus_rule_id  = gbrpr.pre_bonus_rule_id
			  JOIN gaming_bonus_rules_pre_rules parentRule ON gbrpr.bonus_rule_id = parentRule.bonus_rule_id
			  JOIN gaming_bonus_rules ON parentRule.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND linking_type = 'REDEEMED'
			  LEFT JOIN gaming_bonus_instances bonusChildren ON parentRule.pre_bonus_rule_id = bonusChildren.bonus_rule_id AND bonusChildren.client_stat_id = gbi.client_stat_id AND bonusChildren.is_secured
			  WHERE gbi.bonus_instance_id  = bonusInstanceID
		  ) AS bonuses
		  GROUP BY bonuses.bonus_rule_id
		  HAVING (num_prerequisites_or IS NOT NULL AND achieved >= num_prerequisites_or)
	  ) AS players
	  ON DUPLICATE KEY UPDATE include_flag=1;

	  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date)
	  SELECT players.player_selection_id, players.client_stat_id, 1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = players.player_selection_id)  MINUTE) 
	  FROM (
		  SELECT bonuses.bonus_rule_id,SUM(IF(achieved = 1, 1, 0)) AS achieved,client_stat_id,player_selection_id, bonuses.num_prerequisites_or AS num_prerequisites_or
		  FROM (
			  SELECT parentRule.bonus_rule_id,IF(bonusChildren.bonus_rule_id IS NULL,0,1) AS achieved,gbi.client_stat_id,player_selection_id, num_prerequisites_or
			  FROM gaming_bonus_instances gbi
			  JOIN gaming_bonus_rules_pre_rules gbrpr ON gbi.bonus_rule_id  = gbrpr.pre_bonus_rule_id
			  JOIN gaming_bonus_rules_pre_rules parentRule ON gbrpr.bonus_rule_id = parentRule.bonus_rule_id
			  JOIN gaming_bonus_rules ON parentRule.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND linking_type = 'REDEEMED'
			  LEFT JOIN gaming_bonus_instances bonusChildren ON parentRule.pre_bonus_rule_id = bonusChildren.bonus_rule_id AND bonusChildren.client_stat_id = gbi.client_stat_id AND bonusChildren.is_secured
			  WHERE gbi.bonus_instance_id  = bonusInstanceID
		  ) AS bonuses
		  GROUP BY bonuses.bonus_rule_id
		  HAVING (num_prerequisites_or IS NOT NULL AND achieved >= num_prerequisites_or)
	  ) AS players
		  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND gaming_player_selections_player_cache.expiry_date IS NULL, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
								  gaming_player_selections_player_cache.player_in_selection=IF(VALUES(player_in_selection), IF(gaming_player_selections_player_cache.expiry_date<NOW(),0,1), 0),
								  gaming_player_selections_player_cache.last_updated=NOW();
  END IF;

END root$$

DELIMITER ;

