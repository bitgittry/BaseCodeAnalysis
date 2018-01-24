DROP procedure IF EXISTS `TransactionWithdrawalRequestCancelByPlayer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionWithdrawalRequestCancelByPlayer`(clientStatID BIGINT, balanceHistoryID BIGINT, varReason TEXT, sessionID BIGINT, OUT statusCode INT)
BEGIN
 -- formatting  

  DECLARE balanceWithdrawalRequestID BIGINT DEFAULT -1;
  DECLARE transactionType, transactionStatus VARCHAR(80);

  SELECT gaming_balance_history.balance_history_id, gaming_balance_history.client_stat_id, gaming_payment_transaction_type.name AS transaction_type, gaming_payment_transaction_status.name AS transaction_status, gaming_balance_withdrawal_requests.balance_withdrawal_request_id
  INTO @balanceHistoryIDCheck, @clientStatIDCheck, transactionType, transactionStatus, balanceWithdrawalRequestID
  FROM gaming_balance_history 
  JOIN gaming_payment_transaction_type ON 
    gaming_balance_history.balance_history_id=balanceHistoryID AND gaming_balance_history.client_stat_id=clientStatID AND
    gaming_payment_transaction_type.name='Withdrawal' AND gaming_payment_transaction_type.payment_transaction_type_id=gaming_balance_history.payment_transaction_type_id
  JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name='Pending' AND 
    gaming_payment_transaction_status.payment_transaction_status_id = gaming_balance_history.payment_transaction_status_id             
  JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id
  JOIN gaming_balance_withdrawal_requests ON gaming_balance_history.balance_history_id=gaming_balance_withdrawal_requests.balance_history_id;
  
  IF (balanceWithdrawalRequestID=-1) THEN
    SET statusCode=1;
  END IF;
  
  SET varReason = IF(varReason IS NOT NULL, CONCAT('Client: ',varReason), NULL);

  CALL TransactionWithdrawalRequestUpdateByUser(balanceWithdrawalRequestID, 'CancelledByPlayer', NULL, 0, varReason, sessionID, statusCode);
  
END$$

DELIMITER ;

