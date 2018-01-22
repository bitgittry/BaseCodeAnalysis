DROP procedure IF EXISTS `TransactionAdjustRealMoney`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionAdjustRealMoney`(sessionID BIGINT, clientStatID BIGINT, varAmount DECIMAL(18, 5), varDescription TEXT, transactionType VARCHAR(40), transactionKey VARCHAR(80), returnData TINYINT(1), allowAmountBelowBalance TINYINT(1), platformType VARCHAR(80), OUT statusCode INT)
root: BEGIN
  -- Added returnData parameter in which case 0 is passed then data won't be returned. To be used by other stored procedures 
  -- Removed session variables
  -- Doing some checks before locking the player

  DECLARE currentRealBalance, exchangeRate DECIMAL(18, 5) DEFAULT 0;
  DECLARE clientStatIDCheck, transactionID, currencyID, gamePlayID, paymentTransactionTypeID BIGINT DEFAULT -1;
  DECLARE isValidTransactionType TINYINT(1) DEFAULT 0;
  DECLARE adjustmentSelector CHAR(1);
  DECLARE platformTypeID TINYINT(4) DEFAULT -1;
    
  -- checks prior to lock the player  
  SELECT payment_transaction_type_id, 1, adjustment_selector 
  INTO paymentTransactionTypeID, isValidTransactionType, adjustmentSelector
  FROM gaming_payment_transaction_type
  WHERE name=transactionType AND is_user_adjustment_type=1;

  IF (isValidTransactionType!=1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (varAmount<0 AND adjustmentSelector NOT IN ('B','R')) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  
 IF (varAmount>0 AND adjustmentSelector NOT IN ('B','G')) THEN
    SET statusCode=6;
    LEAVE root;
  END IF;

	IF (platformType IS NOT NULL) THEN
		SELECT platform_type_id INTO platformTypeID
		FROM gaming_platform_types
		WHERE platform_type = platformType;
    
		IF (platformTypeID = -1) THEN
			SET statusCode=7;
			LEAVE root;
		END IF;
    END IF;
  
  -- lock player
  SELECT client_stat_id, current_real_balance, currency_id INTO clientStatIDCheck, currentRealBalance, currencyID
  FROM gaming_client_stats
  WHERE client_stat_id=clientStatID and is_active=1 
  FOR UPDATE; 
  
  SELECT exchange_rate INTO exchangeRate
  FROM gaming_operator_currency 
  JOIN gaming_operators ON gaming_operators.is_main_operator AND gaming_operator_currency.operator_id=gaming_operators.operator_id
  WHERE gaming_operator_currency.currency_id=currencyID;
  
  IF (clientStatIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (varAmount<0 AND currentRealBalance+varAmount < 0 AND allowAmountBelowBalance=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
 
  UPDATE gaming_client_stats  
  SET current_real_balance=ROUND(current_real_balance+varAmount,0), total_adjustments=ROUND(total_adjustments+varAmount,0), total_adjustments_base=total_adjustments_base+ROUND(varAmount/exchangeRate,5) ,
	locked_real_funds = GREATEST(0,ROUND(locked_real_funds + varAmount,0))
  WHERE client_stat_id=clientStatID;
  
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, 
   balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, reason, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,
   loyalty_points_bonus,loyalty_points_after_bonus, platform_type_id) 
  SELECT paymentTransactionTypeID, varAmount, ROUND(varAmount/exchangeRate,5), gaming_client_stats.currency_id, exchangeRate, varAmount, 0, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, 
   current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, sessionID, sessionID, varDescription, pending_bets_real, pending_bets_bonus,withdrawal_pending_amount,
   0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`) , IF(platformTypeID=-1,NULL,platformTypeID)
  FROM gaming_client_stats 
  WHERE gaming_client_stats.client_stat_id=clientStatID;  
  
  IF (ROW_COUNT()=0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;

  SET transactionID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, platform_type_id) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus,platform_type_id
  FROM gaming_transactions
  WHERE transaction_id=transactionID;

  SET gamePlayID=LAST_INSERT_ID();
  CALL GameUpdateRingFencedBalances(clientStatID, gamePlayID);
  
  IF (returnData) THEN
	  SELECT transaction_id, gaming_payment_transaction_type.payment_transaction_type_id AS transaction_type_id, gaming_payment_transaction_type.name AS transaction_type_name, 
		gaming_transactions.amount_total, gaming_transactions.amount_total_base, gaming_transactions.amount_real, gaming_transactions.amount_bonus, gaming_transactions.amount_bonus_win_locked, amount_cashback, loyalty_points, 
		gaming_transactions.timestamp, gaming_transactions.exchange_rate, gaming_transactions.client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, gaming_transactions.reason,
		gaming_currency.currency_code, gaming_transactions.balance_history_id
	  FROM gaming_transactions
	  JOIN gaming_payment_transaction_type ON gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
	  JOIN gaming_currency ON gaming_transactions.currency_id=gaming_currency.currency_id
	  WHERE gaming_transactions.transaction_id=transactionID;
  END IF;

  SET statusCode=0;
  
END root$$

DELIMITER ;

