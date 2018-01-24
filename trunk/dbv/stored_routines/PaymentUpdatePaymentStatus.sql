DROP procedure IF EXISTS `PaymentUpdatePaymentStatus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PaymentUpdatePaymentStatus`(paymentPurchaseID BIGINT, paymentStatus VARCHAR(20), ovverideTransactionKey TINYINT(1), transactionKey VARCHAR(80), errorCode VARCHAR(80), errorMessage VARCHAR(255), varComment TEXT, playerToken VARCHAR(80))
root: BEGIN
  -- Added playerToken to payment_purchases
  DECLARE paymentPurchaseIDCheck, clientStatID, paymentID BIGINT DEFAULT -1;
  
  SELECT payment_id INTO paymentID 
  FROM payments 
  WHERE payment_purchase_id=paymentPurchaseID;

  IF (paymentID=-1) THEN
    LEAVE root;
  END IF;

  IF (paymentStatus!='NOT_SET') THEN
	 UPDATE payments 
	 JOIN payment_statuses ON payments.payment_id=paymentID AND payment_statuses.name=paymentStatus
	 SET payments.payment_status_id=payment_statuses.payment_status_id, 
		 player_token=IF(transactionKey IS NOT NULL AND ovverideTransactionKey, transactionKey, player_token); 
  END IF;
      
  INSERT INTO payments_history (payment_id, amount, currency_code, account_reference, card_type, cardholder_name, cvc_ok, payment_status_id, comment, timestamp, history_timestamp, gateway_payment_ref, gateway_error_code, gateway_error_message)
  SELECT payment_id, amount, currency_code, account_reference, card_type, cardholder_name, cvc_ok, payment_status_id, varComment, timestamp, NOW(), transactionKey, errorCode, errorMessage
  FROM payments WHERE payments.payment_id=paymentID;    
  
  IF (ovverideTransactionKey) THEN
    UPDATE payment_purchases
    SET transaction_ref=IFNULL(transactionKey, transaction_ref), token=IFNULL(playerToken, token)
    WHERE payment_purchase_id=paymentPurchaseID;
  END IF;
      
END root$$

DELIMITER ;

