DROP procedure IF EXISTS `PlaceBetBonusCashExchangeSB`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceBetBonusCashExchangeSB`(clientStatID BIGINT, sbBetID BIGINT, gamePlayID BIGINT, sessionID BIGINT, transactionType VARCHAR(20), exchangeRate DECIMAL(18,5), bonusTransferedTotal DECIMAL(18,5), bonusTransfered DECIMAL(18,5), bonusWinLockedTransfered DECIMAL(18,5), bonusTransferedLost DECIMAL(18,5), bonusWinLockedTransferedLost DECIMAL(18,5))
root:BEGIN  
  
  DECLARE lockID BIGINT DEFAULT -1;
  
  SET @bonusTransferedTotal=bonusTransferedTotal;
  SET @bonusTransfered=bonusTransfered;
  SET @bonusWinLockedTransfered=bonusWinLockedTransfered;
  SET @bonusTransferedLost=bonusTransferedLost;
  SET @bonusWinLockedTransferedLost=bonusWinLockedTransferedLost;
  
  
  UPDATE gaming_client_stats   
  SET
    current_real_balance=current_real_balance+@bonusTransferedTotal, 
    total_bonus_transferred=total_bonus_transferred+@bonusTransfered, current_bonus_balance=current_bonus_balance-(@bonusTransfered+@bonusTransferedLost), 
    total_bonus_win_locked_transferred=total_bonus_win_locked_transferred+@bonusWinLockedTransfered, current_bonus_win_locked_balance=current_bonus_win_locked_balance-(@bonusWinLockedTransfered+@bonusWinLockedTransferedLost),
    total_bonus_transferred_base=total_bonus_transferred_base+ROUND(@bonusTransferedTotal/exchangeRate, 5)
  WHERE client_stat_id=clientStatID;
  
  
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, @bonusTransferedTotal, ROUND(@bonusTransferedTotal/exchangeRate, 5), gaming_client_stats.currency_id, exchangeRate, @bonusTransferedTotal, @bonusTransfered*-1, @bonusWinLockedTransfered*-1, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, gamePlayID, sessionID, gaming_client_stats.pending_bets_real, gaming_client_stats.pending_bets_bonus, withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)  
  FROM gaming_client_stats  
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=transactionType
  WHERE client_stat_id=clientStatID; 
  
  SET @transactionID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, bonus_lost, bonus_win_locked_lost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, @bonusTransferedLost, @bonusWinLockedTransferedLost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
  FROM gaming_transactions
  WHERE transaction_id=@transactionID;

  CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());  
        
  SELECT lock_id INTO lockID FROM gaming_locks WHERE name='wager_req_met_lock' FOR UPDATE;
        
  
  UPDATE gaming_bonus_rules
  JOIN gaming_game_plays_bonus_instances AS ggpbi ON ggpbi.sb_bet_id=sbBetID AND ggpbi.now_wager_requirement_met
  JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id AND gaming_bonus_rules.bonus_rule_id=gaming_bonus_instances.bonus_rule_id   
  SET 
    added_to_real_money_total=added_to_real_money_total+IFNULL(ROUND(ggpbi.bonus_transfered_total/exchangeRate, 0),0),
    allow_awarding_bonuses=IF(program_cost_threshold=0,allow_awarding_bonuses,(added_to_real_money_total+IFNULL(ROUND(ggpbi.bonus_transfered_total/exchangeRate, 0),0))<program_cost_threshold);  
    
END root$$

DELIMITER ;

