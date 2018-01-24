DROP procedure IF EXISTS `CommonWalletNTEAdjustRealMoney`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletNTEAdjustRealMoney`(clientStatID BIGINT, varAmount DECIMAL(18, 5), varDescription TEXT, transactionType VARCHAR(40), gameManufacturerName VARCHAR(80), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root: BEGIN
  
  DECLARE currentRealBalance, exchangeRate DECIMAL(18, 5) DEFAULT 0;
  DECLARE clientStatIDCheck, transactionID, currencyID, manufacturerId BIGINT DEFAULT -1;
  DECLARE adjustmentSelector CHAR(1);
  
  SET @clientStatID = clientStatID;
  SET @varAmount = varAmount;
  SET @description = varDescription; 
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
  
  UPDATE gaming_client_stats  
  SET current_real_balance=ROUND(current_real_balance+@varAmount,0), total_adjustments=ROUND(total_adjustments+@varAmount,0), total_adjustments_base=total_adjustments_base+ROUND(@varAmount/exchangeRate,5) 
  WHERE client_stat_id=@clientStatID;
  
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, reason, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, @varAmount, ROUND(@varAmount/exchangeRate,5), gaming_client_stats.currency_id, exchangeRate, @varAmount, 0, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, NULL, NULL, @description, pending_bets_real, pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`) 
  FROM gaming_client_stats 
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=transactionType
  WHERE gaming_client_stats.client_stat_id=@clientStatID;  
  
  IF (ROW_COUNT()=0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;
  SET transactionID=LAST_INSERT_ID();
  
  SELECT game_manufacturer_id 
  INTO manufacturerId
  FROM gaming_game_manufacturers where `name` = gameManufacturerName;

  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, game_manufacturer_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, manufacturerId,gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
  FROM gaming_transactions
  WHERE transaction_id=transactionID;

  SET gamePlayIDReturned = LAST_INSERT_ID();

  CALL GameUpdateRingFencedBalances(@clientStatID,gamePlayIDReturned);  
  
  SET statusCode=0;
END root$$

DELIMITER ;

