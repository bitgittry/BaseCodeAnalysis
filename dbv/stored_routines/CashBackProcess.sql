DROP procedure IF EXISTS `CashBackProcess`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CashBackProcess`(transactionRef VARCHAR(63), varAmount DECIMAL(18,5),varReason TEXT,isReturn TINYINT(1), PAN VARCHAR(23), OUT statusCode INT)
root: BEGIN
   
  DECLARE operatorID, clientStatIDCheck, clientID,clientStatID, currencyID, currencyIDCheck,BalanceAccountID BIGINT DEFAULT -1;
  DECLARE currentRealBalance,exchangeRate DECIMAL(18, 5) DEFAULT 0;
  
  DECLARE multiplier INT DEFAULT 1;
  
  SET statusCode=0;
  
  SELECT client_stat_id INTO clientStatID 
  FROM payments 
  JOIN gaming_client_stats ON gaming_client_stats.client_id = payments.client_id
  WHERE transactionRef=payment_key;
  
  SELECT balance_account_id INTO BalanceAccountID 
  FROM gaming_balance_accounts
  WHERE client_stat_id = clientStatID AND account_reference = PAN;
  
  SELECT client_stat_id, gaming_clients.client_id, current_real_balance, gaming_client_stats.currency_id
  INTO clientStatIDCheck, clientID, currentRealBalance, currencyID 
  FROM gaming_client_stats 
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  WHERE gaming_client_stats.client_stat_id=clientStatID
  FOR UPDATE;
  
  
  IF (clientStatIDCheck=-1 OR clientID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  
  SELECT operator_id INTO operatorID FROM gaming_operators WHERE is_main_operator=1;
  
  SELECT currency_id, exchange_rate INTO currencyIDCheck, exchangeRate
  FROM gaming_operator_currency 
  WHERE gaming_operator_currency.operator_id=operatorID AND gaming_operator_currency.currency_id=currencyID;
  
  IF (currencyIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

  SET multiplier = IF(isReturn=0,-1,1);
    
  UPDATE gaming_client_stats 
  SET current_real_balance=current_real_balance+varAmount*multiplier
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SET @transactionType=IF(isReturn=0,'ChargeBack','ChargeBackReturn');

  INSERT INTO gaming_transactions
    (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_cashback, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, reason, pending_bet_real, pending_bet_bonus,transaction_ref,extra_id,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, varAmount*multiplier, ROUND((varAmount*multiplier)/exchangeRate, 5), gaming_client_stats.currency_id, exchangeRate, varAmount*multiplier, 0, 0, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, varReason , pending_bets_real, pending_bets_bonus,transactionRef ,BalanceAccountID,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_client_stats 
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=@transactionType
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SET @transactionID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
  FROM gaming_transactions
  WHERE transaction_id=@transactionID;

  CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());  
  
END$$

DELIMITER ;

