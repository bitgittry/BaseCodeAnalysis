DROP procedure IF EXISTS `TransactionChargeDeferredTaxInactiveAccounts`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionChargeDeferredTaxInactiveAccounts`()
root: BEGIN

  DECLARE ActiveOnBets, ActiveOnWithdrawals, ActiveOnLogins, ActiveOnDeposits,TaxEnabled TINYINT(1) DEFAULT 0;
  DECLARE InactivityDaysInital,InactivityDaysReccuring INT;
  DECLARE AccountClosureType VARCHAR(80) DEFAULT 'closed';
	DECLARE CounterID BIGINT;
	DECLARE CurTimeStamp DATETIME;

  -- Get Game Settings
  SELECT 
    gsTaxOnGameplayEnabled.value_bool as vbInactivityFee, 
    gsDormantAccountType.value_string as vbDormantAccountType
  INTO 
    TaxEnabled, 
    AccountClosureType
	FROM gaming_settings AS gsTaxOnGameplayEnabled 
	JOIN gaming_settings AS gsDormantAccountType 
    ON (gsDormantAccountType.name = 'DORMANT_ACCOUNT_CLOSURE_TYPE')
	WHERE gsTaxOnGameplayEnabled.name = 'TAX_ON_GAMEPLAY_ENABLED';

  IF TaxEnabled = 0 THEN
		LEAVE root;
  END IF;
  
  -- Get Dormant Account Management Settings
  SELECT 
    active_on_deposits,
    active_on_logins,
    active_on_withdrawals,
    active_on_bets
	INTO  
    ActiveOnDeposits,
    ActiveOnLogins,
    ActiveOnWithdrawals,
    ActiveOnBets
	FROM gaming_dormant_account_settings 
  WHERE dormant_account_setting_type = 'DeferredTax'
  LIMIT 1;

  SET CurTimeStamp = NOW();

	INSERT INTO gaming_transaction_counter (date_created) VALUES (CurTimeStamp);
	SET CounterID = LAST_INSERT_ID();

  INSERT INTO gaming_transaction_counter_amounts (transaction_counter_id,client_stat_id,amount)
  SELECT CounterID, gaming_tax_cycles.client_stat_id, LEAST(current_real_balance,deferred_tax)* -1 AS fee 
  FROM gaming_clients
  JOIN gaming_client_stats ON gaming_client_stats.client_id = gaming_clients.client_id AND current_real_balance > 0
  JOIN gaming_tax_cycles ON gaming_tax_cycles.client_stat_id = gaming_client_stats.client_stat_id AND gaming_tax_cycles.is_active = 1
  JOIN gaming_country_tax ON gaming_tax_cycles.country_tax_id = gaming_country_tax.country_tax_id AND gaming_country_tax.on_end_of_tax_cycle = 1
  AND (IF(AccountClosureType='closed',gaming_clients.is_account_closed =0,1=1) AND IF(AccountClosureType='inactive',gaming_clients.is_active = 1 ,1=1))
  JOIN gaming_clients_login_attempts_totals ON gaming_clients_login_attempts_totals.client_id = gaming_clients.client_id
  WHERE 
    (ActiveOnDeposits = 0 OR TIMESTAMPDIFF(DAY, IFNULL(last_deposited_date, sign_up_date), NOW()) >= inactivity_days)
    AND (ActiveOnWithdrawals = 0 OR TIMESTAMPDIFF(DAY, IFNULL(last_withdrawn_date, sign_up_date), NOW()) >= inactivity_days)
    AND (ActiveOnLogins = 0 OR TIMESTAMPDIFF(DAY, IFNULL(gaming_clients_login_attempts_totals.last_success, sign_up_date), NOW()) >= inactivity_days)
    AND (ActiveOnBets = 0 OR TIMESTAMPDIFF(DAY, IFNULL(last_played_date, sign_up_date), NOW()) >= inactivity_days)
		AND TIMESTAMPDIFF(DAY, IFNULL(sign_up_date, NOW()), NOW()) >= inactivity_days;
  #AND LEAST(current_real_balance,deferred_tax) > 0;
  
  UPDATE gaming_client_stats
  JOIN gaming_transaction_counter_amounts ON gaming_client_stats.client_stat_id = gaming_transaction_counter_amounts.client_stat_id AND transaction_counter_id = CounterID
  SET current_real_balance = current_real_balance + gaming_transaction_counter_amounts.amount,
      total_tax_paid = total_tax_paid - gaming_transaction_counter_amounts.amount
  WHERE gaming_transaction_counter_amounts.amount < 0;
  
  UPDATE gaming_client_stats
  JOIN gaming_transaction_counter_amounts ON gaming_client_stats.client_stat_id = gaming_transaction_counter_amounts.client_stat_id AND transaction_counter_id = CounterID
  SET deferred_tax = 0;
      
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, reason, pending_bet_real, pending_bet_bonus,transaction_counter_id,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, gaming_transaction_counter_amounts.amount, ROUND(gaming_transaction_counter_amounts.amount/exchange_rate,5), gaming_client_stats.currency_id, exchange_rate, gaming_transaction_counter_amounts.amount, 0, 0, 0, CurTimeStamp, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, 0, 0, 'Deferred Tax', pending_bets_real, pending_bets_bonus,CounterID,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_transaction_counter_amounts
  JOIN gaming_client_stats ON gaming_transaction_counter_amounts.client_stat_id = gaming_client_stats.client_stat_id
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = 'DeferredTaxInactivity '
  JOIN gaming_operators ON is_main_operator
  JOIN gaming_operator_currency ON gaming_operator_currency.operator_id = gaming_operators.operator_id AND gaming_operator_currency.currency_id = gaming_client_stats.currency_id
  WHERE transaction_counter_id = CounterID AND gaming_transaction_counter_amounts.amount < 0;
  
  SET @BeforeInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays); 
  
  INSERT INTO gaming_game_plays (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,sign_mult,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, gaming_transactions.client_id, gaming_transactions.client_stat_id, gaming_transactions.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,1,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
  FROM gaming_transactions
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id AND gaming_payment_transaction_type.name = 'DeferredTaxInactivity' AND gaming_transactions.transaction_counter_id = CounterID
  JOIN gaming_transaction_counter_amounts ON gaming_transactions.client_stat_id =gaming_transaction_counter_amounts.client_stat_id AND gaming_transaction_counter_amounts.transaction_counter_id = CounterID
  WHERE gaming_transaction_counter_amounts.amount < 0;
  
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
    
  UPDATE gaming_tax_cycles
  JOIN gaming_transaction_counter_amounts ON gaming_transaction_counter_amounts.transaction_counter_id = CounterID AND gaming_tax_cycles.client_stat_id = gaming_transaction_counter_amounts.client_stat_id
  SET cycle_end_date = NOW(), is_active = 0, deferred_tax_amount = gaming_transaction_counter_amounts.amount, cycle_closed_on = 'Inactivity'
  WHERE gaming_tax_cycles.is_active = 1;
    
  /*INSERT INTO gaming_tax_cycles (country_tax_id, client_stat_id, deferred_tax_amount, cycle_start_date, cycle_end_date, is_active, cycle_client_counter)
  SELECT gaming_country_tax.country_tax_id, gaming_client_stats.client_stat_id, 0, NOW(), '3000-01-01 00:00:00', 1, (SELECT COUNT(tax_cycle_id)+1 FROM gaming_tax_cycles WHERE client_stat_id = gaming_client_stats.client_stat_id)
  FROM gaming_country_tax 
  JOIN gaming_transaction_counter_amounts ON gaming_transaction_counter_amounts.transaction_counter_id = CounterID
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_transaction_counter_amounts.client_stat_id
  JOIN clients_locations on gaming_country_tax.country_id = clients_locations.country_id AND clients_locations.client_id = gaming_client_stats.client_id
  AND gaming_country_tax.is_current = 1
  AND gaming_country_tax.is_active = 1
  AND NOW() BETWEEN gaming_country_tax.date_start AND gaming_country_tax.date_end;*/

  DELETE FROM gaming_transaction_counter_amounts WHERE transaction_counter_id = CounterID;
    
END root$$

DELIMITER ;

