DROP procedure IF EXISTS `PlaceBetBonusCashExchanageFromExternal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceBetBonusCashExchanageFromExternal`(clientStatID BIGINT, bonusID VARCHAR(20), bonusAmount DECIMAL(18,5), paymentTransactionTypeID BIGINT, OUT gamePlayID BIGINT)
root: BEGIN

  DECLARE exchangeRate DECIMAL(18,5) DEFAULT 0;
  DECLARE transactionID BIGINT DEFAULT NULL;

  SELECT exchange_rate into exchangeRate 
  FROM gaming_client_stats
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
  WHERE gaming_client_stats.client_stat_id=clientStatID
  LIMIT 1;
    
  UPDATE gaming_client_stats   
  SET
    current_real_balance=current_real_balance+bonusAmount, 
    total_bonus_transferred=total_bonus_transferred+0, total_bonus_win_locked_transferred=total_bonus_win_locked_transferred+bonusAmount, 
    total_bonus_transferred_base=total_bonus_transferred_base+ROUND(bonusAmount/exchangeRate, 5)
  WHERE client_stat_id=clientStatID;

  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT paymentTransactionTypeID, bonusAmount, ROUND(bonusAmount/exchangeRate, 5), gaming_client_stats.currency_id, exchangeRate, bonusAmount, 0, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, bonusID, NULL, gaming_client_stats.pending_bets_real, gaming_client_stats.pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)  
  FROM gaming_client_stats  
  WHERE client_stat_id=clientStatID; 
  
  SET transactionID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, bonus_lost, bonus_win_locked_lost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, 0, 0, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
  FROM gaming_transactions
  WHERE transaction_id=transactionID;

  SET gamePlayID=LAST_INSERT_ID();

  CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);  

END root$$

DELIMITER ;

