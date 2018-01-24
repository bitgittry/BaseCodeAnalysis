DROP procedure IF EXISTS `TransactionRefundWithdrawal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionRefundWithdrawal`(balanceWithdrawalRequestID BIGINT, isCashback TINYINT(1), balanceHistoryErrorCode INT, varReason TEXT,  alreadyAccepted TINYINT(1), transactionType VARCHAR(80))
root:BEGIN
  
	DECLARE balanceWithdrawalRequestIDCheck, balanceAccountID, clientStatID, balanceHistoryID, paymentMethodID BIGINT DEFAULT -1;
	DECLARE varAmount, ReleasedLockedFunds, chargeAmount DECIMAL(18, 5) DEFAULT 0;
	DECLARE varTransactionType VARCHAR(80);

	SELECT balance_withdrawal_request_id, withdrawal_request.balance_account_id, withdrawal_request.client_stat_id, withdrawal_request.amount, withdrawal_request.balance_history_id, gaming_balance_history.payment_method_id, withdrawal_request.charge_amount 
	INTO balanceWithdrawalRequestIDCheck, balanceAccountID, clientStatID, varAmount, balanceHistoryID, paymentMethodID, chargeAmount
	FROM gaming_balance_withdrawal_requests AS withdrawal_request
	JOIN gaming_balance_history ON withdrawal_request.balance_history_id=gaming_balance_history.balance_history_id
	WHERE balance_withdrawal_request_id=balanceWithdrawalRequestID AND (withdrawal_request.is_processed=0 OR alreadyAccepted);

	IF (balanceWithdrawalRequestIDCheck=-1) THEN 
		LEAVE root;
	END IF;

	SELECT released_locked_funds INTO ReleasedLockedFunds
	FROM gaming_transactions
	JOIN gaming_game_plays ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id
	WHERE gaming_transactions.payment_transaction_type_id = 21 AND gaming_transactions.balance_history_id = balanceHistoryID;
    
    SET ReleasedLockedFunds = IFNULL(ReleasedLockedFunds,0);

	SELECT client_stat_id INTO clientStatID 
	FROM gaming_client_stats
	WHERE client_stat_id=clientStatID
	FOR UPDATE;

	UPDATE gaming_client_stats 
	SET current_real_balance=current_real_balance+varAmount + IF(alreadyAccepted,0,chargeAmount),
		withdrawal_pending_amount=withdrawal_pending_amount-IF(alreadyAccepted,0,varAmount), 
		withdrawn_amount=withdrawn_amount-IF(alreadyAccepted,varAmount,0), 		
		num_withdrawals=IF(num_withdrawals>0,num_withdrawals-1,0), 
		first_withdrawn_date=IF(num_withdrawals=0,NULL,first_withdrawn_date),
        locked_real_funds = locked_real_funds + ReleasedLockedFunds,
		withdrawn_pending_charge_amount=withdrawn_pending_charge_amount-IF(alreadyAccepted,0,chargeAmount)
	WHERE gaming_client_stats.client_stat_id=clientStatID;

	UPDATE gaming_balance_accounts
	SET withdrawal_pending_amount=withdrawal_pending_amount-IF(alreadyAccepted,0,varAmount),
		withdrawn_amount=withdrawn_amount-IF(alreadyAccepted,varAmount,0),
		withdrawn_pending_charge_amount=withdrawn_pending_charge_amount-IF(alreadyAccepted,0,chargeAmount)
	WHERE balance_account_id=balanceAccountID;

	IF (transactionType IS NULL) THEN
		IF (isCashback=0) THEN
			SET varTransactionType='WithdrawalCancelled';
		ELSE
			SET varTransactionType='CashbackCancelled';
		END IF;
	ELSE 
		SET varTransactionType = transactionType;
	END IF;

	SET @timestamp=NOW();
	INSERT INTO gaming_transactions
		(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_cashback, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, balance_history_id, reason, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT gaming_payment_transaction_type.payment_transaction_type_id, varAmount, varAmount/gaming_operator_currency.exchange_rate, gaming_client_stats.currency_id, gaming_operator_currency.exchange_rate, varAmount, 0, 0, 0, 0, @timestamp, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, paymentMethodID, balanceHistoryID, varReason , pending_bets_real, pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`) 
	FROM gaming_client_stats 
	JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
	JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=varTransactionType
	WHERE gaming_client_stats.client_stat_id=clientStatID; 

	SET @transactionID=LAST_INSERT_ID();

	INSERT INTO gaming_game_plays 
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus,released_locked_funds) 
	SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus,-ReleasedLockedFunds
	FROM gaming_transactions
	WHERE transaction_id=@transactionID;

	CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());

	UPDATE gaming_balance_history
	JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name =
		CASE 
			WHEN varTransactionType = 'WithdrawalReversed' THEN 'Reversed'
			ELSE 'Rejected'
		END
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
	LEFT JOIN gaming_balance_history_error_codes ON gaming_balance_history_error_codes.error_code=balanceHistoryErrorCode
	SET 
		gaming_balance_history.client_stat_balance_refunded=1,
		gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id, 
		gaming_balance_history.timestamp=@timestamp,
		gaming_balance_history.balance_real_after=current_real_balance,
		gaming_balance_history.balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance,
		gaming_balance_history.balance_history_error_code_id=gaming_balance_history_error_codes.balance_history_error_code_id,
		description=gaming_balance_history_error_codes.message,
		custom_message=varReason
	WHERE gaming_balance_history.balance_history_id=balanceHistoryID;
  
  
END root$$

DELIMITER ;

