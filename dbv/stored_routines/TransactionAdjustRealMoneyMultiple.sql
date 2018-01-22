DROP procedure IF EXISTS `TransactionAdjustRealMoneyMultiple`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionAdjustRealMoneyMultiple`(transactionCounterID BIGINT, tranType VARCHAR(40), extraID BIGINT)
BEGIN

  

  DECLARE notificationEnabled, notificationEventTypeID INT DEFAULT 0;

  SET @transactionCounterID=transactionCounterID;
  
  UPDATE gaming_client_stats 
  JOIN gaming_transaction_counter_amounts AS counter_amounts ON 
    counter_amounts.transaction_counter_id=@transactionCounterID AND
    gaming_client_stats.client_stat_id=counter_amounts.client_stat_id 
  SET 
    gaming_client_stats.current_real_balance=current_real_balance+counter_amounts.amount;
  
  
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, extra2_id, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, counter_amounts.amount, ROUND(counter_amounts.amount/gaming_operator_currency.exchange_rate, 5), gaming_client_stats.currency_id, gaming_operator_currency.exchange_rate, counter_amounts.amount, 0, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, @transactionCounterID, extraID, pending_bets_real, pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_transaction_counter_amounts AS counter_amounts
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=tranType
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=counter_amounts.client_stat_id 
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
  WHERE counter_amounts.transaction_counter_id=@transactionCounterID; 
  
  SET @BeforeInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays);   	

  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_transactions.amount_total, gaming_transactions.amount_total_base, gaming_transactions.exchange_rate, gaming_transactions.amount_real, gaming_transactions.amount_bonus, gaming_transactions.amount_bonus_win_locked, gaming_transactions.timestamp, gaming_transactions.client_id, gaming_transactions.client_stat_id, gaming_transactions.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, gaming_transactions.currency_id, gaming_transactions.session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
  FROM gaming_transactions
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=tranType AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
  WHERE gaming_transactions.extra_id=@transactionCounterID;

  SET @AfterInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays);

		INSERT INTO 	gaming_game_play_ring_fenced 
						(game_play_id,ring_fenced_sb_after,ring_fenced_casino_after,ring_fenced_poker_after,ring_fenced_pb_after)
		SELECT 			game_play_id, current_ring_fenced_sb, current_ring_fenced_casino, current_ring_fenced_poker, 0
		FROM			gaming_client_stats
						JOIN gaming_game_plays ON gaming_client_stats.client_stat_id = gaming_game_plays.client_stat_id
							AND game_play_id BETWEEN @BeforeInsert AND @AfterInsert
		ON DUPLICATE KEY UPDATE   
		`ring_fenced_sb_after`=values(`ring_fenced_sb_after`), 
		`ring_fenced_casino_after`=values(`ring_fenced_casino_after`),  
		`ring_fenced_poker_after`=values(`ring_fenced_poker_after`), 
		`ring_fenced_pb_after`=values(`ring_fenced_pb_after`);
  
  SELECT value_bool INTO notificationEnabled FROM gaming_settings WHERE name='NOTIFICATION_ENABLED';
  IF (notificationEnabled) THEN
	SELECT notification_event_type_id INTO notificationEventTypeID FROM notifications_event_types WHERE event_name=tranType AND is_active=1;
	
	IF (notificationEventTypeID!=0) THEN
	  INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id)
	  SELECT notificationEventTypeID, gaming_transactions.transaction_id, extraID
	  FROM gaming_transactions
	  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=tranType AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
	  WHERE gaming_transactions.extra_id=@transactionCounterID;
	END IF;
  END IF;

END$$

DELIMITER ;

