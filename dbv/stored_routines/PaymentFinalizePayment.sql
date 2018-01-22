DROP procedure IF EXISTS `PaymentFinalizePayment`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PaymentFinalizePayment`(paymentPurchaseID BIGINT, paymentType VARCHAR(20), paymentStatus VARCHAR(20), clientRef VARCHAR(80), clientEmail VARCHAR(255), varAmount DECIMAL, currencyCode VARCHAR(3), merchantAmount DECIMAL, merchantCurrencyCode VARCHAR(3), 
  gatewayPaymentRef VARCHAR(80), accountReference VARCHAR(80), cardType VARCHAR(80), cardholderName VARCHAR(80), cvcOK TINYINT(1), expiryDate DATETIME, gatewayTimestamp DATETIME, gatewayExchangeRate DECIMAL, gatewayFees DECIMAL, canReject TINYINT(1), bonusCode VARCHAR(80), varAcquirer VARCHAR(80),
  varComment TEXT, errorCode VARCHAR(45), errorMessage VARCHAR(250), playerToken VARCHAR(80), gatewayAuthCode VARCHAR(80), OUT statusCode INT)
root:BEGIN
  -- Saving token in payment_purchases  
  -- Saving gateway_auth_code in payment_purchases

  DECLARE paymentPurchaseIDCheck, clientStatID, paymentID, paymentMethodID, currencyID, chargeSettingID BIGINT DEFAULT -1;
  DECLARE purchasePaymentStatus INT DEFAULT 0;
  DECLARE accountReferencePurchase VARCHAR(80);
  DECLARE calculatedAmount, chargeAmount DECIMAL(10,0);
  DECLARE overAmount TINYINT(1) DEFAULT 0;
  
  SELECT payment_purchase_id, client_stat_id, payment_method_id, currency_id   
  INTO paymentPurchaseIDCheck, clientStatID, paymentMethodID, currencyID
  FROM payment_purchases 
  LEFT JOIN gaming_currency ON gaming_currency.currency_code = payment_purchases.currency_code
  WHERE payment_purchase_id=paymentPurchaseID;
  
  IF (paymentPurchaseIDCheck=-1 OR clientStatID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats  WHERE client_stat_id=clientStatID FOR UPDATE; 
  
  CALL PaymentCalculateCharge(paymentType, paymentMethodID, currencyID, varAmount, 1, chargeSettingID, calculatedAmount, chargeAmount, overAmount);
  
  SELECT payment_id INTO paymentID FROM payments WHERE payment_purchase_id=paymentPurchaseID; 
  IF (paymentID=-1) THEN
    
    INSERT INTO payments (payment_type_id, payment_gateway_id, payment_key, client_id, client_ref, client_email, amount, charge_amount, currency_code, merchant_amount, merchant_currency_code, gateway_payment_ref, 
      account_reference, card_type, cardholder_name, cvc_ok, payment_status_id, payment_purchase_id, timestamp, expiry_date, gateway_timestamp, gateway_exchange_rate, gateway_fees, can_reject, 
	  bonus_code, acquirer, comment, gateway_error_code, gateway_error_message, player_token, payment_charge_setting_id) 
    SELECT payment_types.payment_type_id, payment_profiles.payment_gateway_id, payment_purchases.payment_key, payment_purchases.client_id, clientRef, clientEmail, calculatedAmount, chargeAmount, currencyCode, merchantAmount, merchantCurrencyCode, gatewayPaymentRef, 
      IFNULL(accountReference, payment_purchases.account_reference), cardType, cardholderName, cvcOK, payment_statuses.payment_status_id, payment_purchases.payment_purchase_id, NOW(), expiryDate, gatewayTimestamp, gatewayExchangeRate, gatewayFees, canReject,
	  bonusCode, varAcquirer, varComment, errorCode, errorMessage, playerToken,  chargeSettingID
    FROM payment_types
    JOIN payment_statuses ON payment_types.name=paymentType AND payment_statuses.name=paymentStatus
    JOIN payment_purchases ON payment_purchases.payment_purchase_id=paymentPurchaseID
    JOIN payment_profiles ON payment_purchases.payment_profile_id=payment_profiles.payment_profile_id;
    
    IF (ROW_COUNT() = 0) THEN
      SET statusCode=2;
      LEAVE root;
    END IF;
    
    SET paymentID=LAST_INSERT_ID();
  ELSE
    UPDATE payments 
    JOIN payment_statuses ON payments.payment_id=paymentID AND payment_statuses.name=paymentStatus
    SET 
      payments.amount=IFNULL(calculatedAmount, payments.amount), payments.currency_code=IFNULL(currencyCode, payments.currency_code), payments.card_type=IFNULL(cardType, payments.card_type), payments.cardholder_name=IFNULL(cardholderName, payments.cardholder_name), 
	  payments.cvc_ok=IFNULL(cvcOK, payments.cvc_ok), payments.expiry_date=IFNULL(expiryDate, payments.expiry_date),  
      payments.account_reference=IFNULL(accountReference, payments.account_reference), payments.gateway_payment_ref=IFNULL(gatewayPaymentRef, payments.gateway_payment_ref),
	  payments.gateway_timestamp=IFNULL(gatewayTimestamp, payments.gateway_timestamp), payments.payment_status_id=payment_statuses.payment_status_id,
	  payments.acquirer=IFNULL(varAcquirer, payments.acquirer), payments.gateway_error_code = errorCode, payments.gateway_error_message = errorMessage, 
	  payments.player_token=IFNULL(playerToken, payments.player_token), comment = varComment, gateway_fees = gatewayFees,
	  payments.charge_amount = chargeAmount, payments.payment_charge_setting_id =  chargeSettingID;
    
  END IF;
  
  INSERT INTO payments_history (payment_id, amount, charge_amount, currency_code, account_reference, card_type, cardholder_name, cvc_ok, payment_status_id, comment, `gateway_error_code`, `gateway_error_message`, timestamp, history_timestamp, gateway_payment_ref, gateway_fees, payment_charge_setting_id)
  SELECT payment_id, amount, charge_amount, currency_code, account_reference, card_type, cardholder_name, cvc_ok, payment_status_id, comment, errorCode, errorMessage, timestamp, NOW(),gateway_payment_ref, gatewayFees,payment_charge_setting_id
  FROM payments WHERE payments.payment_id=paymentID;
  SET purchasePaymentStatus=IF(paymentStatus IN ('ACCEPTED','AUTHORIZED_PENDING','WITHDRAW_PENDING'), 2, 3);
  
  UPDATE payment_purchases 
  JOIN payment_purchase_statuses ON payment_purchase_id=paymentPurchaseID AND payment_purchase_statuses.name='payment_gateway_returned' 
  SET client_ref=IFNULL(clientRef, client_ref), transaction_ref=IFNULL(gatewayPaymentRef, transaction_ref), account_reference=IFNULL(accountReference, account_reference), 
	  payment_purchases.token=IFNULL(playerToken, payment_purchases.token), payment_purchases.gateway_auth_code=IFNULL(gatewayAuthCode, payment_purchases.gateway_auth_code),
      allow_deposit=0, purchase_payment_status=purchasePaymentStatus, payment_purchases.payment_purchase_status_id=payment_purchase_statuses.payment_purchase_status_id, payment_purchases.comments = varComment;
  
  SELECT paymentID AS payment_id;
  SET statusCode=0;
END root$$

DELIMITER ;

