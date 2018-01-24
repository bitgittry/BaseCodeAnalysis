DROP procedure IF EXISTS `PlaceWinFreeRoundBonusCashExchange`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceWinFreeRoundBonusCashExchange`(clientStatID BIGINT, bonusFreeRoundRuleID BIGINT, gamePlayID BIGINT, sessionID BIGINT, transactionType VARCHAR(20), exchangeRate DECIMAL(18,5), bonusTransferedTotal DECIMAL(18,5), bonusTransfered DECIMAL(18,5), bonusWinLockedTransfered DECIMAL(18,5), bonusTransferedLost DECIMAL(18,5), bonusWinLockedTransferedLost DECIMAL(18,5))
root:BEGIN  
  
  
  SET @bonusTransferedTotal=bonusTransferedTotal;
  SET @bonusTransfered=bonusTransfered;
  SET @bonusWinLockedTransfered=bonusWinLockedTransfered;
  SET @bonusTransferedLost=bonusTransferedLost;
  SET @bonusWinLockedTransferedLost=bonusWinLockedTransferedLost;
  
  
  UPDATE gaming_client_stats   
  SET
    current_real_balance=current_real_balance+@bonusTransferedTotal, 
    total_bonus_transferred=total_bonus_transferred+@bonusTransfered, 
    total_bonus_win_locked_transferred=total_bonus_win_locked_transferred+@bonusWinLockedTransfered,
    total_bonus_transferred_base=total_bonus_transferred_base+ROUND(@bonusTransferedTotal/exchangeRate, 5)
  WHERE client_stat_id=clientStatID;
  
  
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, @bonusTransferedTotal, ROUND(@bonusTransferedTotal/exchangeRate, 5), gaming_client_stats.currency_id, exchangeRate, @bonusTransferedTotal, @bonusTransfered*-1, @bonusWinLockedTransfered*-1, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, gamePlayID, sessionID,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`) 
  FROM gaming_client_stats  
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=transactionType
  WHERE client_stat_id=clientStatID; 
  
  SET @transactionID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, bonus_lost, bonus_win_locked_lost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, @bonusTransferedLost, @bonusWinLockedTransferedLost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
  FROM gaming_transactions
  WHERE transaction_id=@transactionID;

  CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());
        
  INSERT INTO gaming_bonus_free_round_transfers (bonus_rule_id, bonus_transfered)
  VALUES (bonusFreeRoundRuleID, ROUND(@bonusTransferedTotal/exchangeRate, 5));

END root$$

DELIMITER ;

