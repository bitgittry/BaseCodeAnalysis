DROP procedure IF EXISTS `TransactionCreateManualWithdrawal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionCreateManualWithdrawal`(
  clientStatID BIGINT, paymentMethodID BIGINT, balanceAccountID BIGINT, varAmount DECIMAL(18, 5), transactionDate DATETIME, 
  isCashback TINYINT(1), externalReference VARCHAR(80), varReason VARCHAR(1024), varNotes TEXT, platformType VARCHAR(20), 
  userID BIGINT, sessionID BIGINT, usePendingWinnings TINYINT(1), OUT balanceManualTransactionID BIGINT,uniqueTransactionKey VARCHAR(80), 
  issueWithdrawalType VARCHAR(20), forceIgnoreNotification TINYINT(1), isChargeEnabled TINYINT(1), OUT statusCode INT)
root: BEGIN
/*
 1 - 
 2 -
 3 - 
 4 -
 5 - 
 6 -
 10 - Payment Method Restricted
 11 - Payment Amount not within limit
 12 - Insufficient player funds. Withdrawal amount exceeds the Provisional Real Money Balance.
*/

  --  added notifications
  --  Payment Key using the Bit8 function instead of UUID().
  -- Added issueWithdrawalType management - CPREQ-36 
  
  DECLARE operatorID, clientID, clientStatIDCheck, currencyID, currencyIDCheck, paymentGatewayID, balanceAccountIDCheck, 
	subPaymentMethodID, orderRef, balanceHistoryID, chargeSettingID, creatorTypeID, creatorID BIGINT DEFAULT -1;
  DECLARE paymentGatewayRef, transactionAuthorizedStatusCode INT DEFAULT 0;
  DECLARE currencyCode, paymentGatewayTransactionKey, accountReference, cardHolderName, methodSubType, uniqueTransactionID, transactionType VARCHAR(255) DEFAULT NULL;
  DECLARE isSuspicious, isTestPlayer, testPlayerAllowTransfers, isCaptureIntervalEnabled, manualDepositRequireAccount, notificationEnabled, isTaxEnabled, overAmount TINYINT(1) DEFAULT 0;
  DECLARE currentRealBalance, currentPendingWinnings , exchangeRate, deferredTaxAmount, chargeAmount DECIMAL(18, 5) DEFAULT 0;
  SET balanceManualTransactionID=-1;
  
	SELECT value_bool INTO isTaxEnabled
	FROM gaming_settings 
	WHERE name= 'TAX_ON_GAMEPLAY_ENABLED';
  
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  
  SELECT operator_id INTO operatorID FROM gaming_operators WHERE is_main_operator=1;
  SELECT gaming_clients.client_id, gaming_client_stats.client_stat_id, is_suspicious, is_test_player, test_player_allow_transfers, current_real_balance, gaming_client_stats.currency_id, pending_winning_real, deferred_tax
  INTO clientID, clientStatIDCheck, isSuspicious, isTestPlayer, testPlayerAllowTransfers, currentRealBalance, currencyID, currentPendingWinnings, deferredTaxAmount
  FROM gaming_client_stats 
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id 
  JOIN gaming_clients ON 
    client_stat_id=clientStatID AND gaming_client_stats.is_active=1 AND 
    gaming_client_stats.client_id=gaming_clients.client_id 
  JOIN gaming_payment_amounts ON gaming_client_stats.currency_id=gaming_payment_amounts.currency_id
  WHERE gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL);
  
  IF (varAmount < 1.0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;
  
  IF (clientStatIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (isSuspicious=1 OR (isTestPlayer=1 AND testPlayerAllowTransfers=0)) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

  SELECT currency_id, exchange_rate INTO currencyIDCheck, exchangeRate
  FROM gaming_operator_currency 
  WHERE gaming_operator_currency.operator_id=operatorID AND gaming_operator_currency.currency_id=currencyID;
  
  IF (currencyIDCheck=-1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (isCashback=0) THEN
	IF(usePendingWinnings=0) THEN
		IF (currentRealBalance<varAmount) THEN
		  SET statusCode=4;
		  LEAVE root;
		END IF; 
	ELSE
		IF (currentPendingWinnings<varAmount) THEN
		  SET statusCode=4;
		  LEAVE root;
		END IF;
	END IF;	
	
  END IF;
  
  IF (isChargeEnabled=1) THEN
	CALL PaymentCalculateCharge('Withdrawal', paymentMethodID, currencyID, varAmount, 0, chargeSettingID, varAmount, chargeAmount, overAmount);
  END IF;
  
  SELECT balance_account_id, payment_method_id
  INTO balanceAccountIDCheck, paymentMethodID
  FROM gaming_balance_accounts
  JOIN gaming_client_stats ON gaming_balance_accounts.client_stat_id=gaming_client_stats.client_stat_id
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  WHERE gaming_balance_accounts.balance_account_id=balanceAccountID AND gaming_balance_accounts.is_active=1;
  
  IF (balanceAccountIDCheck=-1) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;
    
  SELECT payment_gateway_id, payment_gateway_ref 
  INTO paymentGatewayID, paymentGatewayRef
  FROM gaming_payment_gateways WHERE NAME='Internal';
  
  IF (paymentGatewayID=-1) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;
  
  
  -- for POS/external withdrawal do not checl the limit
  IF (paymentMethodID NOT IN (250, 251, 290)) THEN
	SELECT TransactionCheckWithdrawAmountWithinLimit(clientStatID, paymentMethodID, varAmount, balanceAccountID) INTO @withdrawCheckLimitStatus;
  ELSE
	SET @withdrawCheckLimitStatus=0;
  END IF;

  IF (@withdrawCheckLimitStatus!=0) THEN
	  IF (@withdrawCheckLimitStatus=1) THEN
		SET statusCode=10;
		LEAVE root;
	  END IF;
  END IF;
  
	IF(isTaxEnabled = 1 and deferredTaxAmount > 0) THEN
		IF((currentRealBalance - deferredTaxAmount) < varAmount) THEN
			SET statusCode=12;
            LEAVE root;
		END IF;
	END IF;

  SET transactionDate=IFNULL(transactionDate,NOW());  

  UPDATE gaming_client_stats 
  SET current_real_balance=IF(usePendingWinnings=0,current_real_balance-varAmount,current_real_balance), withdrawn_amount=withdrawn_amount+varAmount, withdrawn_amount_base=withdrawn_amount_base+ROUND(varAmount/exchangeRate, 5),last_withdrawal_processed_date = IF(last_withdrawal_processed_date IS NOT NULL,IF(transactionDate>last_withdrawal_processed_date,transactionDate,last_withdrawal_processed_date),transactionDate),num_withdrawals = num_withdrawals+1,
        locked_real_funds = locked_real_funds -  (@UnlockedNWFunds := (IF (current_real_balance<locked_real_funds,locked_real_funds - current_real_balance, 0))),
  withdrawn_charge_amount=withdrawn_charge_amount+chargeAmount, withdrawn_pending_charge_amount=withdrawn_pending_charge_amount+ROUND(chargeAmount/exchangeRate,5)
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  UPDATE gaming_balance_accounts
  SET 
	withdrawn_amount=withdrawn_amount+varAmount, 
	date_last_used=NOW(),
	withdrawn_charge_amount = withdrawn_charge_amount + chargeAmount, 
	withdrawn_pending_charge_amount = withdrawn_pending_charge_amount + ROUND(chargeAmount/exchangeRate,5)
  WHERE balance_account_id=balanceAccountID;
  
  SET transactionType=IF(isCashback=0,'Withdrawal','Cashback');
  SET @timestamp=NOW();  

  IF (uniqueTransactionKey IS NULL) THEN
	-- SET uniqueTransactionID = UUID(); -- before
	SET uniqueTransactionID = PaymentGetPaymentKeyFromBit8PaymentMethodID(paymentMethodID);
  ELSE
    SET uniqueTransactionID = uniqueTransactionKey;
  END IF;
    
  SELECT CASE 
		WHEN giwt.issue_withdrawal_type_id = 2 /* Operator */  AND s.user_id > 1 THEN 2 /* User type */
		WHEN giwt.issue_withdrawal_type_id = 3 /* Player */ THEN 1 /* Player type */
		ELSE 3 /* System type*/
	END,
  CASE 
		WHEN giwt.issue_withdrawal_type_id = 2 /* Operator */ AND s.user_id > 1 THEN s.user_id
		WHEN giwt.issue_withdrawal_type_id = 3 /* Player */ THEN IFNULL(s.extra_id, clientID) /* client_id */
		ELSE 1 /* user_id of system */
	END
  INTO creatorTypeID, creatorID
  FROM gaming_issue_withdrawal_types AS giwt
  LEFT JOIN sessions_main AS s ON s.session_id = sessionID
  WHERE giwt.`name` = issueWithdrawalType LIMIT 1;
  
  INSERT INTO gaming_balance_manual_transactions (
    client_id, client_stat_id, payment_transaction_type_id, payment_method_id, balance_account_id, 
    amount, charge_amount, payment_charge_setting_id, transaction_date, external_reference, 
    reason, notes, user_id, session_id, 
	created_date, request_creator_type_id, request_creator_id, transaction_reconcilation_status_id)
  SELECT clientID, clientStatID, payment_transaction_type_id, paymentMethodID, balanceAccountID, 
    varAmount, chargeAmount, chargeSettingID, transactionDate, externalReference, 
    varReason, varNotes, userID, IFNULL(sessionID,-1),
    @timestamp, creatorTypeID, creatorID, 6
  FROM gaming_payment_transaction_type
  WHERE gaming_payment_transaction_type.name=transactionType;
  
  SET balanceManualTransactionID=LAST_INSERT_ID();
  SET paymentGatewayTransactionKey=externalReference;
  SET orderRef=NULL;
  
  INSERT INTO gaming_balance_history(
    client_id, client_stat_id, currency_id, amount_prior_charges, amount_prior_charges_base, amount, amount_base, exchange_rate, charge_amount, 
    balance_real_after, balance_bonus_after, balance_account_id, account_reference, unique_transaction_id, payment_method_id, sub_payment_method_id, payment_charge_setting_id, 
    payment_transaction_type_id, payment_transaction_status_id, payment_gateway_id, payment_gateway_transaction_key,
    pending_request, request_timestamp, TIMESTAMP, session_id, custom_message, client_stat_balance_updated, is_processed, processed_datetime, is_manual_transaction, balance_manual_transaction_id, platform_type_id, issue_withdrawal_type_id)
  SELECT 
    gaming_client_stats.client_id, clientStatID, currencyID, varAmount, varAmount/exchangeRate, varAmount, varAmount/exchangeRate, exchangeRate, chargeAmount,
    current_real_balance AS balance_real_after, current_bonus_balance+current_bonus_win_locked_balance AS balance_bonus_after, balanceAccountID, 
	gaming_balance_accounts.account_reference, uniqueTransactionID, gaming_balance_accounts.payment_method_id, gaming_balance_accounts.sub_payment_method_id, chargeSettingID,
    gaming_payment_transaction_type.payment_transaction_type_id, gaming_payment_transaction_status.payment_transaction_status_id, paymentGatewayID, paymentGatewayTransactionKey,
    0, @timestamp , @timestamp, IFNULL(sessionID,-1), varReason, 1, 1, @timestamp, 1, balanceManualTransactionID, gaming_platform_types.platform_type_id,
	(SELECT issue_withdrawal_type_id FROM gaming_issue_withdrawal_types WHERE `name` = issueWithdrawalType)    
  FROM gaming_balance_accounts  
  JOIN gaming_payment_transaction_type ON 
    gaming_balance_accounts.balance_account_id=balanceAccountID AND  
   gaming_payment_transaction_type.name=transactionType
  JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name='Accepted'
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  LEFT JOIN gaming_platform_types ON gaming_platform_types.platform_type=platformType;

  SET balanceHistoryID=LAST_INSERT_ID();

  IF (select value_bool from gaming_settings where name='RULE_ENGINE_ENABLED')=1 THEN
      INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 2, balanceHistoryID;
  END IF;
  
  INSERT INTO gaming_transactions
    (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, TIMESTAMP, client_id, 
	 client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, balance_history_id, reason, pending_bet_real, 
	 pending_bet_bonus, platform_type_id,withdrawal_pending_after,loyalty_points,loyalty_points_bonus,loyalty_points_after_bonus, pending_winning_real, pending_winning_real_after) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, varAmount*-1, varAmount*-1/exchangeRate, gaming_client_stats.currency_id, exchangeRate, IF(usePendingWinnings = 0,varAmount*-1,0) , 0, 0, @timestamp, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, 
		 current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, paymentMethodID, balanceHistoryID, varReason , pending_bets_real, 
		 pending_bets_bonus, gaming_platform_types.platform_type_id,withdrawal_pending_amount,0,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`), IF(usePendingWinnings = 1,varAmount*-1,0), pending_winning_real-varAmount
  FROM gaming_client_stats 
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=transactionType
  LEFT JOIN gaming_platform_types ON gaming_platform_types.platform_type=platformType
  WHERE gaming_client_stats.client_stat_id=clientStatID;  
  
  SET @transactionID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, TIMESTAMP, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus,pending_winning_real, pending_winning_bonus, released_locked_funds) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, TIMESTAMP, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, pending_winning_real, 0, @UnlockedNWFunds
  FROM gaming_transactions
  WHERE transaction_id=@transactionID;

  CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());
 
  CALL BonusCheckLossOnWithdraw(balanceHistoryID, clientStatID);
  
  UPDATE gaming_balance_history
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET
    balance_real_after=current_real_balance,
    balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance
  WHERE gaming_balance_history.balance_history_id=balanceHistoryID;

  SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';
  IF (notificationEnabled AND forceIgnoreNotification = 0) THEN
	INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
	VALUES (513, balanceHistoryID, clientID, 0) 
	ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
  END IF;
  
  -- Check deferred tax cycle on withdrawal    
	IF (isTaxEnabled) THEN  
		SELECT LEAST(current_real_balance,deferred_tax)* -1 AS deferredTax 
        INTO deferredTaxAmount
		FROM gaming_clients 
		JOIN gaming_client_stats ON gaming_client_stats.client_id = gaming_clients.client_id AND current_real_balance >= 0
		JOIN gaming_tax_cycles ON gaming_tax_cycles.client_stat_id = gaming_client_stats.client_stat_id AND gaming_tax_cycles.is_active = 1
		JOIN gaming_country_tax ON gaming_tax_cycles.country_tax_id = gaming_country_tax.country_tax_id AND gaming_country_tax.on_withdrawal = 1 AND gaming_country_tax.is_active = 1 AND gaming_country_tax.is_current = 1
		WHERE gaming_client_stats.client_stat_id = clientStatID;
		
		IF(deferredTaxAmount < 0) THEN
			-- Update gaming_client_stats with deferred tax
			UPDATE gaming_client_stats
			SET current_real_balance = current_real_balance + deferredTaxAmount,
				total_tax_paid = total_tax_paid - deferredTaxAmount,
				deferred_tax = 0
			WHERE gaming_client_stats.client_stat_id = clientStatID;
			
			INSERT INTO gaming_transactions
				(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, reason, pending_bet_real, pending_bet_bonus,transaction_counter_id,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
			SELECT gaming_payment_transaction_type.payment_transaction_type_id, deferredTaxAmount, ROUND(deferredTaxAmount/exchange_rate,5), gaming_client_stats.currency_id, exchange_rate, deferredTaxAmount, 0, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, 0, 0, 'Deferred Tax', pending_bets_real, pending_bets_bonus,0,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
			FROM gaming_client_stats
			JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = 'DeferredTaxWithdrawal'
			JOIN gaming_operators ON is_main_operator
			JOIN gaming_operator_currency ON gaming_operator_currency.operator_id = gaming_operators.operator_id AND gaming_operator_currency.currency_id = gaming_client_stats.currency_id
			WHERE gaming_client_stats.client_stat_id = clientStatID;
			
			SET @taxTransactionID=LAST_INSERT_ID();
			
			INSERT INTO gaming_game_plays (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,sign_mult,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
			SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, gaming_transactions.client_id, gaming_transactions.client_stat_id, gaming_transactions.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,1,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
			FROM gaming_transactions
			JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id AND gaming_payment_transaction_type.name = 'DeferredTaxWithdrawal'
			WHERE gaming_transactions.transaction_id = @taxTransactionID;
			
			SET @taxGamePlayID=LAST_INSERT_ID();
			
			INSERT INTO gaming_game_play_ring_fenced 
				(game_play_id,ring_fenced_sb_after,ring_fenced_casino_after,ring_fenced_poker_after,ring_fenced_pb_after)
			SELECT game_play_id, current_ring_fenced_sb, current_ring_fenced_casino, current_ring_fenced_poker, 0
			FROM gaming_client_stats
			JOIN gaming_game_plays ON gaming_client_stats.client_stat_id = gaming_game_plays.client_stat_id
			AND game_play_id = @taxGamePlayID
			ON DUPLICATE KEY UPDATE   
			`ring_fenced_sb_after`=values(`ring_fenced_sb_after`), 
			`ring_fenced_casino_after`=values(`ring_fenced_casino_after`),  
			`ring_fenced_poker_after`=values(`ring_fenced_poker_after`), 
			`ring_fenced_pb_after`=values(`ring_fenced_pb_after`);
			
			UPDATE gaming_tax_cycles
			SET cycle_end_date = NOW(), is_active = 0, deferred_tax_amount = deferredTaxAmount, cycle_closed_on = 'Withdrawal'
			WHERE gaming_tax_cycles.is_active = 1 AND gaming_tax_cycles.client_stat_id = clientStatID;
			
			/*INSERT INTO gaming_tax_cycles (country_tax_id, client_stat_id, deferred_tax_amount, cycle_start_date, cycle_end_date, is_active, cycle_client_counter)
			SELECT gaming_country_tax.country_tax_id, clientStatID, 0, NOW(), '3000-01-01 00:00:00', 1, (SELECT COUNT(tax_cycle_id)+1 FROM gaming_tax_cycles WHERE client_stat_id = clientStatID)
			FROM gaming_country_tax 
			JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = clientStatID
			JOIN clients_locations ON gaming_country_tax.country_id = clients_locations.country_id 
			AND clients_locations.client_id = gaming_client_stats.client_id
			AND gaming_country_tax.is_current = 1
			AND gaming_country_tax.is_active = 1
			AND NOW() BETWEEN gaming_country_tax.date_start AND gaming_country_tax.date_end;*/
		ELSE
			UPDATE gaming_client_stats
			SET deferred_tax = 0
			WHERE gaming_client_stats.client_stat_id = clientStatID;
            
            UPDATE gaming_tax_cycles
			SET cycle_end_date = NOW(), is_active = 0, deferred_tax_amount = deferredTaxAmount, cycle_closed_on = 'Withdrawal'
			WHERE gaming_tax_cycles.is_active = 1 AND gaming_tax_cycles.client_stat_id = clientStatID;
			
			/*INSERT INTO gaming_tax_cycles (country_tax_id, client_stat_id, deferred_tax_amount, cycle_start_date, cycle_end_date, is_active, cycle_client_counter)
			SELECT gaming_country_tax.country_tax_id, clientStatID, 0, NOW(), '3000-01-01 00:00:00', 1, (SELECT COUNT(tax_cycle_id)+1 FROM gaming_tax_cycles WHERE client_stat_id = clientStatID)
			FROM gaming_country_tax 
			JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = clientStatID
			JOIN clients_locations ON gaming_country_tax.country_id = clients_locations.country_id 
			AND clients_locations.client_id = gaming_client_stats.client_id
			AND gaming_country_tax.is_current = 1
			AND gaming_country_tax.is_active = 1
			AND NOW() BETWEEN gaming_country_tax.date_start AND gaming_country_tax.date_end;*/
		END IF;                
	END IF;

  SET statusCode=0;
  
END root$$

DELIMITER ;

