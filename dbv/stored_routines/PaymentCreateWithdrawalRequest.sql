DROP procedure IF EXISTS `PaymentCreateWithdrawalRequest`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PaymentCreateWithdrawalRequest`(clientStatID BIGINT, varAmount DECIMAL(14,0), purchasePaymentKey VARCHAR(80), balanceAccountID BIGINT, paymentKey VARCHAR(40), gatewayPaymentKey VARCHAR(40), gatewayPaymentOrderKey VARCHAR(40), OUT statusCode INT)
root: BEGIN
  -- Added paymentKey as parameter
  -- Added gatewayPaymentKey 
  -- Added gatewayPaymentOrderKey
  DECLARE paymentPurchaseID, paymentID, paymentProfileID, paymentMethodID, paymentProfileIDCheck, paymentMethodIDCheck, paymentRequestID, chargeSettingID, currencyID BIGINT DEFAULT -1;
  DECLARE paymentStatus VARCHAR(80);
  DECLARE chargeAmount, calculatedAmount DECIMAL(18,5);
  DECLARE overAmount TINYINT(1) DEFAULT 0;
  
  IF (paymentKey IS NULL) THEN

	  SELECT payment_purchases.payment_purchase_id, payments.payment_id, payment_purchases.payment_profile_id, payment_purchases.payment_method_id, payment_statuses.name AS payment_status,  gaming_currency.currency_id
	  INTO paymentPurchaseID, paymentID, paymentProfileID, paymentMethodID, paymentStatus, currencyID
	  FROM payment_purchases 
      LEFT JOIN gaming_currency ON payment_purchases.currency_code = gaming_currency.currency_code
	  JOIN payments ON payment_purchases.payment_key=purchasePaymentKey AND payments.payment_purchase_id=payment_purchases.payment_purchase_id
	  JOIN payment_statuses ON payments.payment_status_id=payment_statuses.payment_status_id;
	  
	  IF (paymentPurchaseID=-1) THEN 
		SET statusCode=1;
		LEAVE root;
	  END IF;
	  
	  IF (paymentStatus NOT IN ('ACCEPTED','AUTHORIZED_COMPLETE')) THEN
		SET statusCode=2;
		LEAVE root;
	  END IF;

  ELSE

	SELECT payment_purchases.payment_purchase_id, payment_purchases.payment_profile_id, payment_purchases.payment_method_id, gaming_currency.currency_id
	INTO paymentPurchaseID, paymentProfileID, paymentMethodID, currencyID
	FROM payment_purchases
	LEFT JOIN gaming_currency ON payment_purchases.currency_code = gaming_currency.currency_code
	WHERE payment_key=paymentKey;
	  
  END IF;
  
  SELECT payment_profile_id INTO paymentProfileIDCheck 
  FROM payment_profiles
  WHERE payment_profile_id=paymentProfileID;
  
  SELECT payment_method_id INTO paymentMethodIDCheck
  FROM payment_methods
  WHERE payment_method_id=paymentMethodID;
  
  IF (paymentProfileIDCheck=-1) THEN 
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (paymentMethodIDCheck=-1) THEN 
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  IF (paymentKey IS NULL) THEN
    SET paymentKey=PaymentGetPaymentKey(paymentMethodID);
  ELSE
	  IF (gatewayPaymentKey IS NOT NULL) THEN
		UPDATE gaming_balance_history SET payment_gateway_transaction_key=gatewayPaymentKey WHERE unique_transaction_id=paymentKey;
      END IF;
  END IF; 
 
 CALL PaymentCalculateCharge('Withdrawal', paymentMethodID, currencyID, varAmount, 0, chargeSettingID, calculatedAmount, chargeAmount, overAmount);
 
  INSERT INTO payment_requests (payment_key, payment_type_id, client_id, client_stat_id, client_ref, currency_code, amount, date_created, 
    payment_profile_id, payment_method_id, payment_status_id, parent_payment_id, parent_payment_purchase_id, 
    balance_account_id, gateway_payment_key, gateway_payment_order_key, charge_amount, payment_charge_setting_id)
  SELECT paymentKey, payment_types.payment_type_id, payment_purchases.client_id, payment_purchases.client_stat_id, payment_purchases.client_ref, payment_purchases.currency_code, calculatedAmount, NOW(),
    payment_purchases.payment_profile_id, payment_purchases.payment_method_id, payment_statuses.payment_status_id, payments.payment_id, payment_purchases.payment_purchase_id, 
    balanceAccountID, gatewayPaymentKey, gatewayPaymentOrderKey, chargeAmount, chargeSettingID
  FROM payment_types 
  JOIN payment_statuses ON payment_types.name='Withdrawal' AND payment_statuses.name='NOT_SET'
  JOIN payment_purchases ON payment_purchases.payment_purchase_id=paymentPurchaseID
  LEFT JOIN payments ON payments.payment_id=paymentID;
  
  IF (ROW_COUNT()=0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;
  
  SET paymentRequestID=LAST_INSERT_ID();
  SELECT paymentRequestID AS payment_request_id, paymentKey AS payment_key; 
  
  SET statusCode=0;
END root$$

DELIMITER ;