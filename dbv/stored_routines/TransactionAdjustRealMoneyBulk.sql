DROP procedure IF EXISTS `TransactionAdjustRealMoneyBulk`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionAdjustRealMoneyBulk`(sessionID BIGINT, transactionCounterID BIGINT, varDescription TEXT, transactionType VARCHAR(40), transactionRef VARCHAR(80), OUT statusCode INT)
root: BEGIN

  
  DECLARE currentRealBalance, exchangeRate DECIMAL(18, 5) DEFAULT 0;
  DECLARE clientStatIDCheck, transactionID, currencyID BIGINT DEFAULT -1;
  DECLARE isValidTransactionType TINYINT(1) DEFAULT 0;
  DECLARE adjustmentSelector CHAR(1);
    
  SELECT 1,adjustment_selector INTO isValidTransactionType,adjustmentSelector
  FROM gaming_payment_transaction_type
  WHERE name=transactionType AND is_user_adjustment_type=1;
  IF (isValidTransactionType!=1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;

  
  UPDATE gaming_client_stats  
  JOIN gaming_transaction_counter_amounts AS amounts ON gaming_client_stats.client_stat_id=amounts.client_stat_id
  JOIN gaming_operator_currency AS rates ON gaming_client_stats.currency_id=rates.currency_id
  JOIN gaming_operators ON gaming_operators.is_main_operator AND rates.operator_id=gaming_operators.operator_id
  SET current_real_balance=ROUND(current_real_balance+amounts.amount,0), total_adjustments=ROUND(total_adjustments+amounts.amount,0), total_adjustments_base=total_adjustments_base+ROUND(amounts.amount/rates.exchange_rate,5) 
  WHERE amounts.transaction_counter_id=transactionCounterID;
  
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, reason, pending_bet_real, pending_bet_bonus, transaction_counter_id,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, amounts.amount, ROUND(amounts.amount/rates.exchange_rate,5), gaming_client_stats.currency_id, rates.exchange_rate, amounts.amount, 0, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, sessionID, sessionID, varDescription, pending_bets_real, pending_bets_bonus, transactionCounterID,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`) 
  FROM gaming_client_stats 
  JOIN gaming_transaction_counter_amounts AS amounts ON gaming_client_stats.client_stat_id=amounts.client_stat_id
  JOIN gaming_operator_currency AS rates ON gaming_client_stats.currency_id=rates.currency_id
  JOIN gaming_operators ON gaming_operators.is_main_operator AND rates.operator_id=gaming_operators.operator_id
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=transactionType
  WHERE amounts.transaction_counter_id=transactionCounterID; 
  
  SET @BeforeInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays); 

  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
  FROM gaming_transactions
  WHERE transaction_counter_id=transactionCounterID;

  SET @AfterInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays);
   
  INSERT INTO 	gaming_game_play_ring_fenced 
				(game_play_id,ring_fenced_sb_after,ring_fenced_casino_after,ring_fenced_poker_after,ring_fenced_pb_after)
  SELECT 		game_play_id, current_ring_fenced_sb, current_ring_fenced_casino, current_ring_fenced_poker, 0
  FROM			gaming_client_stats
				JOIN gaming_game_plays ON gaming_client_stats.client_stat_id = gaming_game_plays.client_stat_id
					AND game_play_id BETWEEN @BeforeInsert AND @AfterInsert
  ON DUPLICATE KEY UPDATE   
		`ring_fenced_sb_after`=values(`ring_fenced_sb_after`), 
		`ring_fenced_casino_after`=values(`ring_fenced_casino_after`),  
		`ring_fenced_poker_after`=values(`ring_fenced_poker_after`), 
		`ring_fenced_pb_after`=values(`ring_fenced_pb_after`);
  
  SELECT transaction_id, gaming_payment_transaction_type.payment_transaction_type_id AS transaction_type_id, gaming_payment_transaction_type.name AS transaction_type_name, 
    gaming_transactions.amount_total, gaming_transactions.amount_total_base, gaming_transactions.amount_real, gaming_transactions.amount_bonus, gaming_transactions.amount_bonus_win_locked, amount_cashback, loyalty_points, 
    gaming_transactions.timestamp, gaming_transactions.exchange_rate, gaming_transactions.client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, gaming_transactions.reason,
    gaming_currency.currency_code, gaming_transactions.balance_history_id
  FROM gaming_transactions
  JOIN gaming_payment_transaction_type ON gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
  JOIN gaming_currency ON gaming_transactions.currency_id=gaming_currency.currency_id
  WHERE gaming_transactions.transaction_counter_id=transactionCounterID;
  
  SET statusCode=0;

END root$$

DELIMITER ;

