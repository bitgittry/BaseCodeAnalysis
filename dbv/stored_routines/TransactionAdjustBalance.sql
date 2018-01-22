DROP procedure IF EXISTS `TransactionAdjustBalance`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionAdjustBalance`(sessionID BIGINT, clientStatID BIGINT, varAmount DECIMAL(18, 5), varDescription TEXT, transactionType VARCHAR(20), paymentMethod VARCHAR(40), selectedBonusID BIGINT, issueWithdrawalType VARCHAR(20), OUT statusCode INT)
root: BEGIN
  
  -- Added issueWithdrawalType management - CPREQ-36
  
  DECLARE currentRealBalance, exchangeRate DECIMAL(18, 5) DEFAULT 0;
  DECLARE clientStatIDCheck, transactionID, currencyID, paymentMethodID BIGINT DEFAULT -1;
  DECLARE isValidTransactionType TINYINT(1) DEFAULT 0;
  DECLARE adjustmentSelector CHAR DEFAULT 'B';

  SET @sessionID = sessionID;
  SET @clientStatID = clientStatID;
  SET @varAmount = varAmount;
  SET @description = varDescription; 
  SET @transactionType = transactionType; 
  SET @uniqueTransactionID = UUID();
  SET @varAmountForBalanceHistory = ABS(varAmount);
    
  IF @transactionType='Withdrawal' THEN 
    SET varAmount = ABS(varAmount) * -1;
  END IF;

  SET @varAmount = ROUND(varAmount,0); 
  SELECT client_stat_id, current_real_balance, currency_id INTO clientStatIDCheck, currentRealBalance, currencyID
  FROM gaming_client_stats
  WHERE client_stat_id=@clientStatID and is_active=1 
  FOR UPDATE; 

  SELECT exchange_rate INTO exchangeRate
  FROM gaming_operator_currency 
  JOIN gaming_operators ON gaming_operators.is_main_operator AND gaming_operator_currency.operator_id=gaming_operators.operator_id
  WHERE gaming_operator_currency.currency_id=currencyID;

  
  IF (clientStatIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (currentRealBalance+varAmount < 0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SELECT 1, adjustment_selector INTO isValidTransactionType, adjustmentSelector 
  FROM gaming_payment_transaction_type
  WHERE name=@transactionType;
  IF (isValidTransactionType!=1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (@varAmount<0 AND @transactionType<>'Withdrawal' AND adjustmentSelector NOT IN ('B','R')) THEN 
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  
  UPDATE gaming_client_stats  
  SET current_real_balance=ROUND(current_real_balance+@varAmount,0), total_adjustments=total_adjustments+@varAmount, total_adjustments_base=total_adjustments_base+ROUND(@varAmount/exchangeRate,5) 
  WHERE client_stat_id=@clientStatID;
  
  
  IF (@transactionType IN ('Deposit','Withdrawal')) THEN
	SET paymentMethodID=1;
	SELECT payment_method_id INTO paymentMethodID FROM gaming_payment_method WHERE `name`=paymentMethod LIMIT 1;

    INSERT INTO gaming_balance_history(client_id, client_stat_id, currency_id, amount_prior_charges, amount_prior_charges_base, amount,
      amount_base, balance_real_after, balance_bonus_after, unique_transaction_id, pending_request, selected_bonus_rule_id, request_timestamp,
      is_processed, session_id, payment_method_id, sub_payment_method_id, payment_transaction_type_id, payment_transaction_status_id, client_stat_balance_updated,gaming_balance_history.timestamp, issue_withdrawal_type_id)
    SELECT client_id, client_stat_id, gaming_client_stats.currency_id, @varAmountForBalanceHistory, ROUND( @varAmountForBalanceHistory/exchangeRate,5), 
      @varAmountForBalanceHistory, ROUND(@varAmountForBalanceHistory/exchangeRate,5), current_real_balance, current_bonus_balance, @uniqueTransactionID, 0,
      IFNULL(selectedBonusID,-1), NOW(), 1, sessionID, paymentMethodID, paymentMethodID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 1, NOW(), 
      (SELECT issue_withdrawal_type_id FROM gaming_issue_withdrawal_types WHERE `name` = issueWithdrawalType)
    FROM gaming_client_stats 
    JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=@transactionType
    AND client_stat_id = @clientStatID;
    
    SET @balanceHistoryID = LAST_INSERT_ID();
  END IF; 
  
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, reason,balance_history_id, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, @varAmount, ROUND(@varAmount/exchangeRate), gaming_client_stats.currency_id, exchangeRate, @varAmount, 0, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, sessionID, @description,@balanceHistoryID, pending_bets_real, pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_client_stats 
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=@transactionType
  WHERE gaming_client_stats.client_stat_id=@clientStatID;  
  
  IF (ROW_COUNT()=0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;

  SET transactionID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
  FROM gaming_transactions
  WHERE transaction_id=transactionID;

  CALL GameUpdateRingFencedBalances(@clientStatID,LAST_INSERT_ID());
  
  
  IF @transactionType = 'Deposit' THEN
    CALL BonusCheckAwardingOnDeposit(@balanceHistoryID, clientStatID);
  ELSEIF @transactionType = 'Withdrawal' THEN
    CALL BonusCheckLossOnWithdraw(@balanceHistoryID, clientStatID);
  END IF;
  
  SELECT transaction_id, gaming_payment_transaction_type.payment_transaction_type_id AS transaction_type_id, gaming_payment_transaction_type.name AS transaction_type_name, 
    amount_total, amount_total_base, amount_real, amount_bonus, amount_bonus_win_locked, amount_cashback, loyalty_points, 
    gaming_transactions.timestamp, gaming_transactions.exchange_rate, gaming_transactions.client_stat_id, gaming_transactions.balance_real_after, gaming_transactions.balance_bonus_after,
    gaming_transactions.balance_bonus_win_locked_after, gaming_transactions.loyalty_points_after, reason, gaming_currency.currency_code, gaming_transactions.balance_history_id 
  FROM gaming_transactions
  JOIN gaming_payment_transaction_type ON gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
  JOIN gaming_currency ON gaming_transactions.currency_id=gaming_currency.currency_id
  WHERE gaming_transactions.transaction_id=transactionID;
  
  SET statusCode=0;
END root$$

DELIMITER ;

