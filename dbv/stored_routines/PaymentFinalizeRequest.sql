-- varamoutn include the charge 
DROP procedure IF EXISTS `PaymentFinalizeRequest`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PaymentFinalizeRequest`(paymentRequestID BIGINT, paymentType VARCHAR(20), paymentStatus VARCHAR(20), clientRef VARCHAR(80), clientEmail VARCHAR(255), varAmount DECIMAL, currencyCode VARCHAR(3), merchantAmount DECIMAL, merchantCurrencyCode VARCHAR(3), 
  gatewayPaymentRef VARCHAR(80), accountReference VARCHAR(80), cardType VARCHAR(80), cardholderName VARCHAR(80), cvcOK TINYINT(1), expiryDate DATETIME, gatewayTimestamp DATETIME, gatewayExchangeRate DECIMAL, gatewayFees DECIMAL, 
  varComment TEXT, errorCode VARCHAR(45), errorMessage VARCHAR(1024), OUT statusCode INT)
root:BEGIN
  
  
  DECLARE paymentRequestIDCheck, clientStatID, paymentID, chargeSettingID, currencyID, paymentMethodID BIGINT DEFAULT -1;
  DECLARE purchasePaymentStatus INT DEFAULT 0;
  DECLARE calculatedAmount, chargeAmount DECIMAL(18,5);
  DECLARE overAmount TINYINT(1) DEFAULT 0;
  
  SELECT payment_request_id, client_stat_id, currency_id, payment_method_id
  INTO paymentRequestIDCheck, clientStatID, currencyID, paymentMethodID
  FROM payment_requests
  LEFT JOIN gaming_currency ON gaming_currency.currency_code = payment_requests.currency_code
  WHERE payment_request_id=paymentRequestID;
  
  IF (paymentRequestIDCheck=-1 OR clientStatID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  
  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats  WHERE client_stat_id=clientStatID FOR UPDATE;
  CALL PaymentCalculateCharge(paymentType, paymentMethodID, currencyID, varAmount, 1, chargeSettingID, calculatedAmount, chargeAmount, overAmount);
  
  SELECT payment_id INTO paymentID FROM payments WHERE payment_request_id=paymentRequestID; 
  IF (paymentID=-1) THEN
    
	
    INSERT INTO payments (payment_type_id, payment_gateway_id, payment_key, client_id, client_ref, client_email, amount, currency_code, merchant_amount, merchant_currency_code, gateway_payment_ref, 
      account_reference, card_type, cardholder_name, cvc_ok, payment_status_id, payment_request_id, timestamp, expiry_date, gateway_timestamp, gateway_exchange_rate, gateway_fees, comment, gateway_error_code, gateway_error_message, charge_amount, payment_charge_setting_id) 
    SELECT payment_types.payment_type_id, payment_profiles.payment_gateway_id, payment_requests.payment_key, payment_requests.client_id, clientRef, clientEmail, calculatedAmount, currencyCode, merchantAmount, merchantCurrencyCode, gatewayPaymentRef, 
      accountReference, cardType, cardholderName, cvcOK, payment_statuses.payment_status_id, payment_requests.payment_request_id, NOW(), expiryDate, gatewayTimestamp, gatewayExchangeRate, gatewayFees, varComment, errorCode, errorMessage , chargeAmount, chargeSettingID
    FROM payment_types
    JOIN payment_statuses ON payment_types.name=paymentType AND payment_statuses.name=paymentStatus
    JOIN payment_requests ON payment_requests.payment_request_id=paymentRequestID
    JOIN payment_profiles ON payment_requests.payment_profile_id=payment_profiles.payment_profile_id;
    
    IF (ROW_COUNT() = 0) THEN
      SET statusCode=2;
      LEAVE root;
    END IF;
    
    SET paymentID=LAST_INSERT_ID();
  ELSE
    
    UPDATE payments 
    JOIN payment_statuses ON payments.payment_id=paymentID AND payment_statuses.name=paymentStatus
    SET 
      amount=calculatedAmount, currency_code=currencyCode, card_type=cardType, cardholder_name=cardholderName, cvc_ok=cvcOK, 
      gateway_timestamp=gatewayTimestamp, payments.payment_status_id=payment_statuses.payment_status_id, 
      payments.gateway_error_code = errorCode,
	  payments.gateway_error_message = errorMessage,
	  charge_amount = chargeAmount,
	  payment_charge_setting_id = chargeSettingID;

  END IF;
  
  INSERT INTO payments_history (payment_id, amount, currency_code, account_reference, card_type, cardholder_name, cvc_ok, payment_status_id, comment, timestamp, history_timestamp, charge_amount, payment_charge_setting_id)
  SELECT payment_id, amount, currency_code, account_reference, card_type, cardholder_name, cvc_ok, payment_status_id, comment, timestamp, NOW(), chargeAmount, chargeSettingID
  FROM payments WHERE payments.payment_id=paymentID;
  
  UPDATE payment_requests
  JOIN payment_statuses ON payment_request_id=paymentRequestID AND payment_statuses.name=paymentStatus
  SET payment_requests.payment_status_id=payment_statuses.payment_status_id, payment_requests.is_active=0;
  SELECT paymentID AS payment_id;
  SET statusCode=0;
END root$$

DELIMITER ;

