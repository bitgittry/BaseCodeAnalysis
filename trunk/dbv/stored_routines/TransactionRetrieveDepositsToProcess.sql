DROP procedure IF EXISTS `TransactionRetrieveDepositsToProcess`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionRetrieveDepositsToProcess`(balanceHistoryID BIGINT, ignoreProcessAtDatetime TINYINT(1))
BEGIN
  
  INSERT INTO gaming_balance_deposit_process_counter (date_created) VALUES (NOW());
  SET @balance_deposit_process_counter_id=LAST_INSERT_ID();
  
  UPDATE gaming_balance_history SET is_processing=0 WHERE is_processing=1;
  
  INSERT INTO gaming_balance_deposit_process_counter_deposits (balance_deposit_process_counter_id, balance_history_id)
  SELECT @balance_deposit_process_counter_id, gaming_balance_history.balance_history_id
  FROM gaming_balance_history 
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND gaming_payment_transaction_type.payment_transaction_type_id=gaming_balance_history.payment_transaction_type_id
  JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name='Authorized_Pending' AND gaming_payment_transaction_status.payment_transaction_status_id=gaming_balance_history.payment_transaction_status_id             
  WHERE (balanceHistoryID=0 OR gaming_balance_history.balance_history_id=balanceHistoryID)
    AND gaming_balance_history.is_processed=0 AND gaming_balance_history.is_processing=0 AND gaming_balance_history.is_failed=0 AND gaming_balance_history.on_hold=0 AND (authorize_now=1 OR cancel_now=1 OR (process_at_datetime <= NOW() OR ignoreProcessAtDatetime=1)) 
  ; 
  
  
  UPDATE gaming_balance_history
  JOIN gaming_balance_deposit_process_counter_deposits AS counter_deposits ON 
    counter_deposits.balance_deposit_process_counter_id=@balance_deposit_process_counter_id AND
    gaming_balance_history.balance_history_id=counter_deposits.balance_history_id
  SET  
    gaming_balance_history.is_processing=1,
    gaming_balance_history.balance_deposit_process_counter_id=@balance_deposit_process_counter_id;
    
  
  SELECT @balance_deposit_process_counter_id AS balance_deposit_process_counter_id;
  
  SELECT gaming_balance_history.balance_history_id, gaming_balance_history.client_id, gaming_balance_history.client_stat_id, currency_code, gaming_currency.name AS currency_name, amount_prior_charges, amount AS Amount, amount_base, account_reference, unique_transaction_id, gaming_payment_transaction_type.payment_transaction_type_id AS TransactionTypeID,
    gaming_payment_transaction_status.payment_transaction_status_id AS TransactionStatusID, gaming_payment_transaction_type.name AS TransactionTypeName, 
    gaming_payment_method.payment_method_id AS PaymentMethodID, gaming_payment_method.name AS PaymentMethodName, gaming_payment_method.display_name AS PaymentMethod, 
    sub_payment_method.payment_method_id AS SubPaymentMethodID, sub_payment_method.name AS SubPaymentMethodName, sub_payment_method.display_name AS SubPaymentMethod, 
    gaming_payment_transaction_status.name AS TransactionStatusName, timestamp, description,
    gaming_balance_history.balance_account_id, payment_gateway_transaction_key, gaming_balance_history.payment_gateway_id, gaming_payment_gateways.name AS payment_gateway_name, balance_real_after, balance_bonus_after, gaming_balance_history.extra_id, 
    client_stat_balance_updated, client_stat_balance_refunded, gaming_balance_history.is_processed, gaming_balance_history.process_at_datetime, on_hold, authorize_now, cancel_now, num_failed, is_failed, is_manual_transaction, balance_manual_transaction_id,
    error_codes.error_code, error_codes.message AS error_message, 0 AS cancel_withdraw, gaming_clients.username, gaming_balance_history.charge_amount
  FROM gaming_balance_history 
  JOIN gaming_currency ON gaming_currency.currency_id=gaming_balance_history.currency_id
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.payment_transaction_type_id=gaming_balance_history.payment_transaction_type_id
  JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id
  JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.payment_transaction_status_id = gaming_balance_history.payment_transaction_status_id             
  JOIN gaming_clients ON gaming_balance_history.client_id = gaming_clients.client_id
  LEFT JOIN gaming_payment_method AS sub_payment_method ON sub_payment_method.payment_method_id = gaming_balance_history.sub_payment_method_id
  LEFT JOIN gaming_payment_gateways ON gaming_balance_history.payment_gateway_id=gaming_payment_gateways.payment_gateway_id
  JOIN gaming_balance_history_error_codes AS error_codes ON gaming_balance_history.balance_history_error_code_id=error_codes.balance_history_error_code_id
  JOIN gaming_balance_deposit_process_counter_deposits AS counter_deposits ON 
    counter_deposits.balance_deposit_process_counter_id=@balance_deposit_process_counter_id AND
    gaming_balance_history.balance_history_id=counter_deposits.balance_history_id;
    
END$$

DELIMITER ;

