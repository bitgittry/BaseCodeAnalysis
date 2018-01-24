DROP procedure IF EXISTS `TransactionGetPaymentTransaction`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionGetPaymentTransaction`(balanceHistoryID BIGINT, clientStatID BIGINT, uniqueTransactionID VARCHAR(80))
BEGIN  
 
  -- Optimized

  IF (IFNULL(balanceHistoryID, 0) = 0) THEN
  
	IF (uniqueTransactionID IS NOT NULL) THEN
    
		SELECT balance_history_id
        INTO balanceHistoryID 
        FROM gaming_balance_history FORCE INDEX (unique_transaction_id)
		WHERE unique_transaction_id=uniqueTransactionID
			AND (clientStatID = 0 OR gaming_balance_history.client_stat_id=clientStatID);
        
	ELSE -- should never arrive here since in this case we only have the clientStatID but we use it as a fallback
    
		SELECT balance_history_id
        INTO balanceHistoryID 
        FROM gaming_balance_history FORCE INDEX (client_stat_id)
		WHERE gaming_balance_history.client_stat_id=clientStatID
        ORDER BY balance_history_id DESC 
        LIMIT 1;
            
    END IF;
  
  
  END IF;

  -- Added gateway_error_code & payments.gateway_error_message
  SELECT gaming_balance_history.balance_history_id, gaming_balance_history.client_id, gaming_balance_history.client_stat_id, gaming_currency.currency_code, gaming_currency.name AS currency_name, 
        gaming_balance_history.amount_prior_charges, gaming_balance_history.amount AS Amount, gaming_balance_history.amount_base, gaming_balance_history.charge_amount, gaming_balance_history.account_reference, gaming_balance_history.unique_transaction_id, gaming_payment_transaction_type.payment_transaction_type_id AS TransactionTypeID,
        gaming_payment_transaction_status.payment_transaction_status_id AS TransactionStatusID, gaming_payment_transaction_type.name AS TransactionTypeName, 
        gaming_payment_method.payment_method_id AS PaymentMethodID, gaming_payment_method.name AS PaymentMethodName, gaming_payment_method.display_name AS PaymentMethod, 
        sub_payment_method.payment_method_id AS SubPaymentMethodID, sub_payment_method.name AS SubPaymentMethodName, sub_payment_method.display_name AS SubPaymentMethod, 
        gaming_payment_transaction_status.name AS TransactionStatusName, gaming_balance_history.timestamp, gaming_balance_history.description,
        gaming_balance_history.balance_account_id, gaming_balance_history.payment_gateway_transaction_key, gaming_balance_history.payment_gateway_id, gaming_payment_gateways.name AS payment_gateway_name, gaming_balance_history.balance_real_after, gaming_balance_history.balance_bonus_after, gaming_balance_history.extra_id, 
        gaming_balance_history.client_stat_balance_updated, gaming_balance_history.client_stat_balance_refunded, gaming_balance_history.is_processed, gaming_balance_history.process_at_datetime, 
        gaming_balance_history.on_hold,  gaming_balance_history.authorize_now,  gaming_balance_history.cancel_now,  gaming_balance_history.num_failed, gaming_balance_history.is_failed,  gaming_balance_history.is_manual_transaction,  gaming_balance_history.balance_manual_transaction_id,
        error_codes.error_code, error_codes.message AS error_message, gaming_balance_history.occurrence_num,
        IF(gaming_payment_transaction_type.name='Withdrawal' AND gaming_payment_transaction_status.name='Pending', 1, 0) AS cancel_withdraw,
		gaming_balance_history.ip_address,
		payments.gateway_error_code, payments.gateway_error_message,
		um.username, payments.comment
    FROM gaming_balance_history FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN gaming_currency ON gaming_currency.currency_id=gaming_balance_history.currency_id
    STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.payment_transaction_type_id=gaming_balance_history.payment_transaction_type_id
	STRAIGHT_JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.payment_transaction_status_id = gaming_balance_history.payment_transaction_status_id     
	STRAIGHT_JOIN gaming_balance_history_error_codes AS error_codes ON gaming_balance_history.balance_history_error_code_id=error_codes.balance_history_error_code_id 
    LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id
	LEFT JOIN sessions_main sm ON gaming_balance_history.session_id = sm.session_id
	LEFT JOIN users_main um ON sm.user_id = um.user_id
    LEFT JOIN gaming_payment_method AS sub_payment_method ON sub_payment_method.payment_method_id = gaming_balance_history.sub_payment_method_id
    LEFT JOIN gaming_payment_gateways ON gaming_balance_history.payment_gateway_id=gaming_payment_gateways.payment_gateway_id
    LEFT JOIN payments ON gaming_balance_history.unique_transaction_id=payments.payment_key 
	WHERE gaming_balance_history.balance_history_id=balanceHistoryID;
    
END$$

DELIMITER ;

