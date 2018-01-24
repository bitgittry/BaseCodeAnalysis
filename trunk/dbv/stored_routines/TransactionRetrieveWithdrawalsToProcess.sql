DROP procedure IF EXISTS `TransactionRetrieveWithdrawalsToProcess`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionRetrieveWithdrawalsToProcess`(balanceWithdrawalRequestID BIGINT, ignoreProcessAtDatetime TINYINT(1))
BEGIN
  -- Processing also withdrawals which are in the Awaitin  -- Processing also withdrawals which are in the AwaitingResponse state. 
  -- Added support for sending withdrawals to CANCEL
  -- Counter to be able to link the withdrawals to process
  -- Optimized
  
  INSERT INTO gaming_balance_withdrawal_process_counter (date_created) VALUES (NOW());
  SET @balance_withdrawal_process_counter_id=LAST_INSERT_ID();
  
  -- Update withdrawals which are stuck to 'Waiting To Be Processed'
  UPDATE gaming_balance_withdrawal_request_statuses AS current_status 
  STRAIGHT_JOIN gaming_balance_withdrawal_requests ON 
	current_status.name IN ('Processing','AwaitingResponse') AND 
    gaming_balance_withdrawal_requests.balance_withdrawal_request_status_id=current_status.balance_withdrawal_request_status_id
  STRAIGHT_JOIN gaming_balance_withdrawal_request_statuses AS new_status ON new_status.name='WaitingToBeProcessed'
  SET 
    gaming_balance_withdrawal_requests.balance_withdrawal_request_status_id=new_status.balance_withdrawal_request_status_id;
  
  -- Update withdrawals which are marked as auto approved
  UPDATE gaming_balance_withdrawal_requests AS req
  STRAIGHT_JOIN gaming_balance_withdrawal_request_statuses AS curst ON 
    curst.name = 'ManuallyBlocked' AND 
    req.balance_withdrawal_request_status_id=curst.balance_withdrawal_request_status_id
  STRAIGHT_JOIN gaming_balance_withdrawal_request_statuses AS newst ON newst.name='WaitingToBeProcessed'
  STRAIGHT_JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = req.balance_history_id
  STRAIGHT_JOIN gaming_payment_method ON gaming_balance_history.payment_method_id = gaming_payment_method.payment_method_id
  LEFT JOIN users_main AS usr ON usr.name = 'system'
  SET 
    req.balance_withdrawal_request_status_id=newst.balance_withdrawal_request_status_id,
	req.notes = CONCAT('Auto Approved on ', DATE_FORMAT(NOW(), '%Y-%m-%d %T')),
	req.finalized_user_id = usr.user_id,
	req.finalized_reason = 'Auto Approved',
    req.approved_on_datetime = NOW(),
    req.expiration_hours_after_approval = IF(req.is_semi_automated_withdrawal, 
		gaming_payment_method.expiration_hours_after_approval, req.expiration_hours_after_approval)
  WHERE req.is_auto_approved = 1 AND req.is_processed=0;
 
  -- Insert withdrawals which need to be processed
  INSERT INTO gaming_balance_withdrawal_process_counter_withdrawals (balance_withdrawal_process_counter_id, balance_withdrawal_request_id)
  SELECT @balance_withdrawal_process_counter_id, gbwr.balance_withdrawal_request_id
  FROM gaming_balance_withdrawal_requests gbwr
  STRAIGHT_JOIN gaming_balance_withdrawal_request_statuses ON 
	gbwr.balance_withdrawal_request_status_id=gaming_balance_withdrawal_request_statuses.balance_withdrawal_request_status_id AND
    ((gaming_balance_withdrawal_request_statuses.name='WaitingToBeProcessed' AND 
		((gbwr.is_semi_automated_withdrawal = 0 OR (gbwr.is_semi_automated_withdrawal = 1 AND 
			gbwr.approved_on_datetime IS NOT NULL AND DATE_ADD(gbwr.approved_on_datetime, INTERVAL gbwr.expiration_hours_after_approval HOUR) <= NOW()))) OR gbwr.pay_now = 1) OR
		(gaming_balance_withdrawal_request_statuses.name='Cancelled' AND gbwr.is_processed=0))
  STRAIGHT_JOIN gaming_balance_accounts ON gbwr.balance_account_id=gaming_balance_accounts.balance_account_id
  STRAIGHT_JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = gbwr.balance_history_id
  STRAIGHT_JOIN gaming_payment_method ON gaming_balance_history.payment_method_id = gaming_payment_method.payment_method_id
  STRAIGHT_JOIN gaming_payment_method_integration_types pmit ON pmit.payment_method_integration_type_id = gaming_payment_method.payment_method_integration_type_id
  WHERE (balanceWithdrawalRequestID=0 OR gbwr.balance_withdrawal_request_id=balanceWithdrawalRequestID) 
    AND gbwr.is_processed=0 AND pmit.name != 'manual'
    AND (gaming_balance_withdrawal_request_statuses.name='Cancelled' OR (
		gbwr.is_waiting_kyc=0 AND ((ignoreProcessAtDatetime=1 OR gbwr.is_semi_automated_withdrawal = 1) OR NOW()>=gbwr.process_at_datetime))) 
    AND (gaming_balance_accounts.can_withdraw=1 AND gaming_balance_accounts.unique_transaction_id_last IS NOT NULL); 
  
  -- Change status to processing
  UPDATE  gaming_balance_withdrawal_process_counter_withdrawals AS counter_withdrawals
  STRAIGHT_JOIN gaming_balance_withdrawal_requests ON 
    gaming_balance_withdrawal_requests.balance_withdrawal_request_id=counter_withdrawals.balance_withdrawal_request_id
  STRAIGHT_JOIN gaming_balance_withdrawal_request_statuses ON 
	gaming_balance_withdrawal_request_statuses.name='Processing'
  STRAIGHT_JOIN gaming_balance_accounts ON 
	gaming_balance_withdrawal_requests.balance_account_id=gaming_balance_accounts.balance_account_id
  SET 
    deposit_session_key=gaming_balance_accounts.unique_transaction_id_last,
    gaming_balance_withdrawal_requests.balance_withdrawal_request_status_id=gaming_balance_withdrawal_request_statuses.balance_withdrawal_request_status_id,
    gaming_balance_withdrawal_requests.balance_withdrawal_process_counter_id=@balance_withdrawal_process_counter_id
  WHERE counter_withdrawals.balance_withdrawal_process_counter_id=@balance_withdrawal_process_counter_id;
  
  -- Return counter id
  SELECT @balance_withdrawal_process_counter_id AS balance_withdrawal_process_counter_id;
  
  -- Return withdrawals to process
  SELECT gaming_balance_withdrawal_requests.balance_withdrawal_request_id, client_stat_id, balance_account_id, balance_history_id, 
	deposit_session_key, withdrawal_session_key, amount, charge_amount
  FROM gaming_balance_withdrawal_process_counter_withdrawals AS counter_withdrawals 
  STRAIGHT_JOIN gaming_balance_withdrawal_requests ON 
    gaming_balance_withdrawal_requests.balance_withdrawal_request_id=counter_withdrawals.balance_withdrawal_request_id
  WHERE counter_withdrawals.balance_withdrawal_process_counter_id=@balance_withdrawal_process_counter_id;
    
END$$

DELIMITER ;

