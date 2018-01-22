DROP procedure IF EXISTS `TransactionWithdrawalRequestUpdateByUser`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionWithdrawalRequestUpdateByUser`(balanceWithdrawalRequestID BIGINT, withdrawalRequestStatus VARCHAR(80), processAtDatetime DATETIME, payNow TINYINT(1), varReason TEXT, sessionID BIGINT, OUT statusCode INT)
root:BEGIN

  -- added notifications
  -- added support for updating the withdrawl status when already cancelled
  -- added gatweySendWithdrawalOnCancel allowing not to set the withdrawal to processed if the gateway requires us to send the withdrawal cancellation
  DECLARE balanceWithdrawalRequestIDCheck, clientID, clientStatID, balanceHistoryID BIGINT DEFAULT -1;
  DECLARE requestDatetime DATETIME;
  DECLARE transactionType VARCHAR(80);
  DECLARE isCashback, canWithdraw, isCancelled, isCancelledByPlayer, notificationEnabled, gatweySendWithdrawalOnCancel, isReasonMandatory, isSemiAutomatedWithdrawal, isApproved TINYINT(1) DEFAULT 0;
  DECLARE expirationHoursAfterApproval SMALLINT UNSIGNED DEFAULT 0;
  
  SELECT value_bool INTO isReasonMandatory FROM gaming_settings WHERE `name`='MANDATORY_PAYMENT_STATUS_CHANGE_DESCRIPTION';

  IF (isReasonMandatory = 1 AND TRIM(IFNULL(varReason,'')) = '' AND withdrawalRequestStatus != 'WaitingToBeProcessed')  THEN
	SET statusCode = 5;
    LEAVE root;	
  END IF;

  IF (withdrawalRequestStatus IS NOT NULL AND withdrawalRequestStatus='CancelledByPlayer') THEN
    SET withdrawalRequestStatus='Cancelled';
    SET isCancelledByPlayer = 1;
  END IF;
    
  -- Lock Player
  SELECT balance_withdrawal_request_id, gaming_client_stats.client_id, gaming_client_stats.client_stat_id 
  INTO balanceWithdrawalRequestIDCheck, clientID, clientStatID
  FROM gaming_balance_withdrawal_requests
  JOIN gaming_client_stats ON gaming_balance_withdrawal_requests.client_stat_id=gaming_client_stats.client_stat_id
  WHERE balance_withdrawal_request_id=balanceWithdrawalRequestID
  FOR UPDATE;

  SELECT balance_withdrawal_request_id, request_datetime, gaming_payment_transaction_type.name AS transaction_type, 
	gaming_balance_accounts.can_withdraw, gaming_balance_withdrawal_requests.balance_history_id, IFNULL(gaming_payment_gateways.send_withdrawal_on_cancel, 0), is_semi_automated_withdrawal,
	gaming_payment_method.expiration_hours_after_approval
  INTO balanceWithdrawalRequestIDCheck, requestDatetime, transactionType, canWithdraw, balanceHistoryID, gatweySendWithdrawalOnCancel, isSemiAutomatedWithdrawal,
	expirationHoursAfterApproval
  FROM gaming_balance_withdrawal_requests 
  JOIN gaming_balance_withdrawal_request_statuses ON gaming_balance_withdrawal_requests.balance_withdrawal_request_status_id=gaming_balance_withdrawal_request_statuses.balance_withdrawal_request_status_id
  JOIN gaming_payment_transaction_type ON gaming_balance_withdrawal_requests.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
  JOIN gaming_balance_accounts ON gaming_balance_withdrawal_requests.balance_account_id=gaming_balance_accounts.balance_account_id
  JOIN gaming_payment_method ON gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id
  LEFT JOIN gaming_payment_gateways ON gaming_balance_accounts.payment_gateway_id=gaming_payment_gateways.payment_gateway_id
  WHERE gaming_balance_withdrawal_requests.balance_withdrawal_request_id=balanceWithdrawalRequestID AND gaming_balance_withdrawal_requests.is_processed=0 AND gaming_balance_withdrawal_request_statuses.name IN ('WaitingToBeProcessed','ManuallyBlocked');

  IF (balanceWithdrawalRequestIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
    
  IF (withdrawalRequestStatus IS NOT NULL AND withdrawalRequestStatus NOT IN ('WaitingToBeProcessed','ManuallyBlocked','Cancelled','PendingVerification')) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  IF (payNow=1) THEN
    IF (canWithdraw=0) THEN
      SET statusCode=3;
      LEAVE root;
    END IF;
  
    SET processAtDatetime=NOW();
    SET processAtDatetime=IF (processAtDatetime < requestDatetime, requestDatetime, processAtDatetime);
    
    UPDATE gaming_balance_withdrawal_requests SET process_at_datetime=processAtDatetime
    WHERE balance_withdrawal_request_id=balanceWithdrawalRequestID;
  END IF;
  
  IF (processAtDatetime IS NOT NULL AND processAtDatetime < requestDatetime) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  SET isCancelled=IF(withdrawalRequestStatus IS NOT NULL AND withdrawalRequestStatus='Cancelled', 1, 0);
    
  IF (isCancelled) THEN

    SET isCashback=IF(transactionType='Cashback',1,0);
    SET @balanceHistoryErrorCode=IF(isCancelledByPlayer, 16, 1);  
    CALL TransactionRefundWithdrawal(balanceWithdrawalRequestID, isCashback, @balanceHistoryErrorCode, varReason, 0, NULL);

    SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';

	IF (notificationEnabled) THEN
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
		VALUES (514, balanceHistoryID, clientID, 0) 
		ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
	END IF;
  END IF;
  
  IF (withdrawalRequestStatus IS NOT NULL AND withdrawalRequestStatus='WaitingToBeProcessed') THEN 
	SET isApproved = 1;
	
	IF(isSemiAutomatedWithdrawal) THEN
		CALL NotificationEventCreate(803, balanceHistoryID, clientStatID, 0);
	END IF;
  END IF;
  
  UPDATE gaming_balance_withdrawal_requests 
  LEFT JOIN gaming_balance_withdrawal_request_statuses ON gaming_balance_withdrawal_request_statuses.name=withdrawalRequestStatus
  SET 
    gaming_balance_withdrawal_requests.balance_withdrawal_request_status_id=IFNULL(gaming_balance_withdrawal_request_statuses.balance_withdrawal_request_status_id,gaming_balance_withdrawal_requests.balance_withdrawal_request_status_id),
    process_at_datetime=IFNULL(processAtDatetime,process_at_datetime), 
    is_processed=IF(withdrawalRequestStatus='Cancelled' AND gatweySendWithdrawalOnCancel=0, 1, is_processed),
    pay_now=IF(pay_now=1, pay_now, payNow OR gatweySendWithdrawalOnCancel),
    notes=varReason,
    session_id=IFNULL(sessionID,0),
    gaming_balance_withdrawal_requests.approved_on_datetime = IF(isApproved AND gaming_balance_withdrawal_requests.approved_on_datetime IS NULL, NOW(), gaming_balance_withdrawal_requests.approved_on_datetime),
	gaming_balance_withdrawal_requests.expiration_hours_after_approval = IF(isApproved AND isSemiAutomatedWithdrawal, expirationHoursAfterApproval, gaming_balance_withdrawal_requests.expiration_hours_after_approval)
  WHERE balance_withdrawal_request_id=balanceWithdrawalRequestID AND is_processed=0;
  
  SET statusCode=0;
END root$$

DELIMITER ;
