DROP procedure IF EXISTS `TransactionAfterWithdrawalUpdateStatus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionAfterWithdrawalUpdateStatus`(balanceWithdrawalRequestID BIGINT, transactionStatus VARCHAR(20), paymentGatewayRef INT, paymentGatewayName VARCHAR(80), paymentGatewayTransactionKey VARCHAR(80), hasErrorOccurred TINYINT(1), ignoreProcessing TINYINT(1), paymentMethod VARCHAR(40), accountReference VARCHAR(80), userID BIGINT, finalizedReason VARCHAR(256), isManual TINYINT(1), markAsFailed TINYINT(1), OUT statusCode INT)
root:BEGIN
  -- Even if PENDING add to the num_failed  
  -- added markAsFailed to fail the withrawal immediately rather than have to wait for the number of retries
  -- added notifications 
  -- Added new flow of status from Accepted to Rejected for Trustly - new status code 5 if transactionStatus is Rejected and status is already Rejected

  DECLARE balanceWithdrawalRequestIDCheck, balanceAccountID, balanceAccountIDNew, clientStatID, clientID, paymentTransactionStatusID, balanceHistoryID, currencyID, paymentMethodID BIGINT DEFAULT -1;
  DECLARE varAmount, exchangeRate, deferredTaxAmount, chargeAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE isWithdrawalSuccessful, isCashback, isPending, notificationEnabled, isFailedBefore, isFailedAfter, isTaxEnabled, alreadyAccepted, isSemiAutomaticWithdrawal TINYINT(1) DEFAULT 0;
  DECLARE withdrawalStatus, withdrawalStatusAfter, transactionType, transactionStatusBefore VARCHAR(80) DEFAULT NULL;
  DECLARE numTries INT DEFAULT -1;
  DECLARE paymentGatewayID BIGINT DEFAULT NULL;
  
  -- Get Player
  SELECT client_stat_id INTO clientStatID  
  FROM gaming_balance_withdrawal_requests AS withdrawal_request 
  WHERE withdrawal_request.balance_withdrawal_request_id=balanceWithdrawalRequestID;

  -- Lock Player
  SELECT client_stat_id, client_id, currency_id INTO clientStatID, clientID, currencyID
  FROM gaming_client_stats
  WHERE client_stat_id=clientStatID
  FOR UPDATE;
  
  -- Get Exchange Rate
  SELECT exchange_rate INTO exchangeRate
  FROM gaming_operator_currency 
  JOIN gaming_operators ON gaming_operators.is_main_operator AND gaming_operator_currency.operator_id=gaming_operators.operator_id
  WHERE gaming_operator_currency.currency_id=currencyID;

  -- Get Withdrawal Details
  SELECT withdrawal_request.balance_withdrawal_request_id, withdrawal_request.balance_account_id, withdrawal_request.client_stat_id, withdrawal_request.amount, 
	gaming_balance_withdrawal_request_statuses.name AS withdrawal_request_status, withdrawal_request.is_failed,
    withdrawal_request.balance_history_id, gaming_payment_transaction_type.name AS transaction_type, 
    gaming_balance_accounts.payment_gateway_id, gaming_payment_method.payment_method_id, gaming_payment_transaction_status.name AS transaction_status, withdrawal_request.charge_amount,
    withdrawal_request.is_semi_automated_withdrawal
  INTO balanceWithdrawalRequestIDCheck, balanceAccountID, clientStatID, varAmount, 
    withdrawalStatus, isFailedBefore,
    balanceHistoryID, transactionType, paymentGatewayID, paymentMethodID, transactionStatusBefore, chargeAmount, isSemiAutomaticWithdrawal
  FROM gaming_balance_withdrawal_requests AS withdrawal_request
  JOIN gaming_balance_withdrawal_request_statuses ON withdrawal_request.balance_withdrawal_request_status_id=gaming_balance_withdrawal_request_statuses.balance_withdrawal_request_status_id
  JOIN gaming_payment_transaction_type ON withdrawal_request.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
  JOIN gaming_balance_history ON withdrawal_request.balance_history_id=gaming_balance_history.balance_history_id
  JOIN gaming_payment_transaction_status ON gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id
  JOIN gaming_balance_accounts ON withdrawal_request.balance_account_id=gaming_balance_accounts.balance_account_id
  LEFT JOIN gaming_payment_method ON gaming_payment_method.name=paymentMethod
  WHERE withdrawal_request.balance_withdrawal_request_id=balanceWithdrawalRequestID; 
  
	-- IF (isManual = 1 AND transactionStatus IN ('Accepted','Rejected') AND withdrawalStatus NOT IN ('Processing','AwaitingResponse') AND NOT ignoreProcessing) THEN
		 -- SET statusCode=6;
		 -- LEAVE root;	  
	-- END IF;
   
  IF (isManual=0 AND paymentGatewayRef IS NOT NULL) THEN
	  SELECT payment_gateway_id INTO paymentGatewayID
	  FROM gaming_payment_gateways 
	  WHERE payment_gateway_ref=paymentGatewayRef;
  END IF;

  IF (isManual=1 AND paymentGatewayName IS NOT NULL) THEN
	  SELECT payment_gateway_id INTO paymentGatewayID
	  FROM gaming_payment_gateways 
	  WHERE name=paymentGatewayName;
  END IF;

  -- This is so that if a withdrawal was requested with a balance account but processed with another, the withdrawal statas are changed 
  IF (paymentMethod IS NOT NULL AND accountReference IS NOT NULL) THEN

	SELECT balance_account_id INTO balanceAccountIDNew 
	FROM gaming_balance_accounts 
	JOIN gaming_payment_method ON gaming_payment_method.name=paymentMethod AND gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id AND gaming_payment_method.is_sub_method=0
	WHERE gaming_balance_accounts.client_stat_id=clientStatID AND gaming_balance_accounts.account_reference=accountReference ORDER BY balance_account_id DESC LIMIT 1;

	IF (balanceAccountIDNew IS NOT NULL AND balanceAccountID!=balanceAccountIDNew) THEN
		UPDATE gaming_balance_accounts
		SET withdrawal_pending_amount=withdrawal_pending_amount-varAmount,
		withdrawn_pending_charge_amount=withdrawn_pending_charge_amount-chargeAmount
		WHERE balance_account_id=balanceAccountID;

		UPDATE gaming_balance_accounts
		SET withdrawal_pending_amount=withdrawal_pending_amount+varAmount,
		withdrawn_pending_charge_amount=withdrawn_pending_charge_amount+chargeAmount
		WHERE balance_account_id=balanceAccountIDNew;

		SET balanceAccountID=balanceAccountIDNew;
	END IF;
  END IF;


  IF (balanceWithdrawalRequestIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
   IF (withdrawalStatus NOT IN ('Processing','AwaitingResponse','PendingVerification') AND NOT ignoreProcessing) THEN
     IF (NOT (isManual AND withdrawalStatus IN ('ManuallyBlocked','WaitingToBeProcessed'))) THEN
	   #Check added since Trustly will send a notification only for Rejected withdrawals (We have to assume that all are accepted unless rejected)
	   IF(transactionStatus = 'Rejected' AND transactionStatusBefore != 'Accepted') THEN
	     SET statusCode=5;
	     LEAVE root;
	   ELSE 
		   IF (transactionStatus != 'Rejected') THEN
			 SET statusCode=2;
			 LEAVE root;
		   ELSE
			 SET alreadyAccepted = 1;
		   END IF;
	   END IF;
     END IF;
   END IF;
  
  SET isCashback=IF(transactionType='Cashback',1,0);
  
  IF (hasErrorOccurred=1) THEN
    SET transactionStatus='Authorized_Pending';
  END IF;
  
  SET transactionStatus=UPPER(transactionStatus);
   
  SELECT payment_transaction_status_id, name INTO paymentTransactionStatusID, transactionStatus
  FROM gaming_payment_transaction_status
  WHERE UPPER(name)=transactionStatus;
  
  IF (paymentTransactionStatusID=-1) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;

  IF (withdrawalStatus!='PendingVerification') THEN
  SET @withdrawalStatus=NULL;
  SET isWithdrawalSuccessful=IF(transactionStatus='Accepted',1,0);
  SET isPending=IF(transactionStatus='Pending',1,0);
  IF (isPending) THEN
    SET @withdrawalStatus='AwaitingResponse';
  ELSE
    SET @withdrawalStatus=IF(isWithdrawalSuccessful,'WithdrawalPassed','WithdrawalFailed');  
  END IF;
  END IF;
  
  IF (hasErrorOccurred=0 AND isPending=0 AND transactionStatusBefore!='Rejected') THEN
  
    IF (isWithdrawalSuccessful=0) THEN

		IF (paymentGatewayID!=-1) THEN
			SET @balanceHistoryErrorCode=2;  
		ELSE 
			SET @balanceHistoryErrorCode=23;  
		END IF;

      SET @varReason=NULL; 
      CALL TransactionRefundWithdrawal(balanceWithdrawalRequestID, isCashback, @balanceHistoryErrorCode, @varReason, alreadyAccepted, NULL);
    
    ELSE
    
      UPDATE gaming_client_stats 
      SET withdrawal_pending_amount=withdrawal_pending_amount-varAmount, withdrawn_amount=withdrawn_amount+varAmount, withdrawn_amount_base=withdrawn_amount_base+ROUND(varAmount/exchangeRate, 5), last_withdrawal_processed_date=NOW(),
	  withdrawn_pending_charge_amount=withdrawn_pending_charge_amount-chargeAmount,
	  withdrawn_charge_amount=withdrawn_charge_amount+chargeAmount
      WHERE gaming_client_stats.client_stat_id=clientStatID;
      
      UPDATE gaming_balance_accounts
      SET withdrawal_pending_amount=withdrawal_pending_amount-varAmount, 
	  withdrawn_amount=withdrawn_amount+varAmount,
	  withdrawn_pending_charge_amount=withdrawn_pending_charge_amount-chargeAmount,
	  withdrawn_charge_amount=withdrawn_charge_amount+chargeAmount
      WHERE balance_account_id=balanceAccountID;
    
      UPDATE gaming_balance_history
      JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name=transactionStatus
      SET 
        gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id, 
        gaming_balance_history.timestamp=NOW(),
		balance_account_id=balanceAccountID,
        payment_gateway_id = IFNULL(payment_gateway_id, paymentGatewayID),
        payment_gateway_transaction_key = IFNULL(payment_gateway_transaction_key, paymentGatewayTransactionKey)
      WHERE gaming_balance_history.balance_history_id=balanceHistoryID;
    
    END IF;
  END IF;

  IF (hasErrorOccurred=0) THEN
    IF (isPending=0) THEN
    
      UPDATE gaming_balance_withdrawal_requests AS withdrawal_requests
      JOIN gaming_balance_withdrawal_request_statuses AS withdrawal_statuses ON withdrawal_statuses.name=@withdrawalStatus
      JOIN gaming_balance_accounts ON gaming_balance_accounts.balance_account_id=balanceAccountID
      SET 
        withdrawal_requests.is_processed=1, withdrawal_requests.processed_datetime=NOW(), withdrawal_requests.is_failed=0,
        withdrawal_requests.balance_withdrawal_request_status_id=withdrawal_statuses.balance_withdrawal_request_status_id,
        withdrawal_requests.balance_account_id=balanceAccountID,
		gaming_balance_accounts.last_successful_withdrawal_date=IF(isWithdrawalSuccessful,NOW(),gaming_balance_accounts.last_successful_withdrawal_date),
		withdrawal_requests.finalized_timestamp = NOW(), 
        withdrawal_requests.finalized_reason = IFNULL(finalizedReason, withdrawal_requests.finalized_reason), withdrawal_requests.finalized_user_id = IFNULL(userID, withdrawal_requests.finalized_user_id)
      WHERE withdrawal_requests.balance_withdrawal_request_id=balanceWithdrawalRequestID;
      
      
      IF (isWithdrawalSuccessful) THEN 
         /*   SET @newPaymentTransactionTypeID=(SELECT payment_transaction_type_id FROM gaming_payment_transaction_type WHERE name='Withdrawal'); 
        
			UPDATE gaming_transactions
			JOIN gaming_client_stats ON 
			  gaming_transactions.balance_history_id=balance_history_id AND gaming_client_stats.client_stat_id=clientStatID AND 
			  gaming_transactions.client_stat_id=gaming_client_stats.client_stat_id 
			JOIN gaming_payment_transaction_type AS transaction_type ON transaction_type.name='WithdrawalRequest' AND gaming_transactions.payment_transaction_type_id=transaction_type.payment_transaction_type_id
			JOIN gaming_balance_history ON gaming_transactions.balance_history_id=gaming_balance_history.balance_history_id
			JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name='Accepted' AND gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id
			SET gaming_transactions.payment_transaction_type_id=@newPaymentTransactionTypeID; */

			INSERT INTO gaming_transactions
				(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, balance_history_id, pending_bet_real, pending_bet_bonus, withdrawal_pending_after) 
			SELECT gaming_payment_transaction_type.payment_transaction_type_id, 0, 0, gaming_client_stats.currency_id, exchangeRate, 0, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, 
				paymentMethodID, balanceHistoryID, pending_bets_real, pending_bets_bonus, withdrawal_pending_amount
			FROM gaming_client_stats 
			JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='WithdrawalAccepted'
			WHERE gaming_client_stats.client_stat_id=clientStatID;  

			SET @transactionID=LAST_INSERT_ID();

			INSERT INTO gaming_game_plays 
				(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, platform_type_id) 
			SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, platform_type_id
			FROM gaming_transactions
			WHERE transaction_id=@transactionID;

	-- Check if deferred tax needs to be charged
            SELECT value_bool INTO isTaxEnabled
			FROM gaming_settings 
			WHERE name= 'TAX_ON_GAMEPLAY_ENABLED';
            
			IF (isTaxEnabled) THEN
				SELECT LEAST(current_real_balance,deferred_tax)* -1 AS deferredTax 
				INTO deferredTaxAmount
				FROM gaming_clients
				JOIN gaming_client_stats ON gaming_client_stats.client_id = gaming_clients.client_id AND current_real_balance >= 0
				JOIN gaming_tax_cycles ON gaming_tax_cycles.client_stat_id = gaming_client_stats.client_stat_id AND gaming_tax_cycles.is_active = 1
				JOIN gaming_country_tax ON gaming_tax_cycles.country_tax_id = gaming_country_tax.country_tax_id AND gaming_country_tax.on_withdrawal = 1 AND gaming_country_tax.is_active = 1 AND gaming_country_tax.is_current = 1
				WHERE gaming_client_stats.client_stat_id = clientStatID;
                
                IF(deferredTaxAmount < 0) 
                THEN
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
					JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id AND gaming_payment_transaction_type.name = 'DeferredTax'
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
      END IF;  

    ELSE 
	  SELECT value_int INTO numTries FROM gaming_settings WHERE name='TRANSFER_WITHDRAWAL_NUM_TRIES';	
      
      UPDATE gaming_balance_withdrawal_requests AS withdrawal_requests
      JOIN gaming_balance_withdrawal_request_statuses AS withdrawal_statuses ON withdrawal_statuses.name=@withdrawalStatus
      SET 
		num_failed=IF(withdrawalStatus!='PendingVerification',num_failed+1,num_failed), is_failed=IF(num_failed>=numTries OR markAsFailed, 1, is_failed),
        is_processed=IF(is_failed,1,is_processed), processed_datetime=IF(is_failed,NOW(),processed_datetime),
        withdrawal_requests.balance_withdrawal_request_status_id=withdrawal_statuses.balance_withdrawal_request_status_id,
		withdrawal_requests.balance_account_id=balanceAccountID
      WHERE withdrawal_requests.balance_withdrawal_request_id=balanceWithdrawalRequestID;
      
	  UPDATE gaming_balance_history
      JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name=transactionStatus
      SET 
        gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id, 
        balance_account_id=balanceAccountID,
        payment_gateway_id = IFNULL(payment_gateway_id, paymentGatewayID),
        payment_gateway_transaction_key = IFNULL(payment_gateway_transaction_key, paymentGatewayTransactionKey)
      WHERE gaming_balance_history.balance_history_id=balanceHistoryID;

    END IF;
  ELSE

    SELECT value_int INTO numTries FROM gaming_settings WHERE name='TRANSFER_WITHDRAWAL_NUM_TRIES';
    UPDATE gaming_balance_withdrawal_requests
    JOIN gaming_balance_withdrawal_request_statuses AS failed_status ON failed_status.name='WithdrawalFailed'
    JOIN gaming_balance_withdrawal_request_statuses AS waiting_process_status ON waiting_process_status.name='WaitingToBeProcessed'
    SET  
      num_failed=IF(withdrawalStatus!='PendingVerification',num_failed+1,num_failed), is_failed=IF(num_failed>=numTries OR markAsFailed, 1, is_failed),
      is_processed=IF(is_failed,1,is_processed), processed_datetime=IF(is_failed,NOW(),processed_datetime),
      gaming_balance_withdrawal_requests.balance_withdrawal_request_status_id=IF(is_failed,failed_status.balance_withdrawal_request_status_id, waiting_process_status.balance_withdrawal_request_status_id)
    WHERE gaming_balance_withdrawal_requests.balance_withdrawal_request_id=balanceWithdrawalRequestID;
  END IF;

  SELECT gaming_balance_withdrawal_request_statuses.name AS withdrawal_request_status, withdrawal_request.is_failed
  INTO withdrawalStatusAfter, isFailedAfter
  FROM gaming_balance_withdrawal_requests AS withdrawal_request
  JOIN gaming_balance_withdrawal_request_statuses ON withdrawal_request.balance_withdrawal_request_status_id=gaming_balance_withdrawal_request_statuses.balance_withdrawal_request_status_id
  WHERE withdrawal_request.balance_withdrawal_request_id=balanceWithdrawalRequestID;
  
  IF (hasErrorOccurred = 0 AND isPending = 0 AND transactionStatus = 'Rejected' AND isSemiAutomaticWithdrawal = 1) THEN
	  UPDATE gaming_balance_history
      SET is_expired_transaction = 1
      WHERE gaming_balance_history.balance_history_id = balanceHistoryID;
  END IF;

  IF (withdrawalStatus!=withdrawalStatusAfter AND (withdrawalStatusAfter IN ('WithdrawalPassed','WithdrawalFailed') OR isFailedBefore!=isFailedAfter)) THEN

	  SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';

	  IF (notificationEnabled) THEN
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
		VALUES (IF(withdrawalStatusAfter='WithdrawalPassed', 513, IF(isFailedAfter, 515, 514)), balanceHistoryID, clientID, 0) 
		ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
	  END IF;
  END IF;

  SET statusCode=0;
  
END root$$

DELIMITER ;

