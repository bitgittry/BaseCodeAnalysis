DROP procedure IF EXISTS `PaymentCreateDummyPurchaseForWithdrawal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PaymentCreateDummyPurchaseForWithdrawal`(balanceAccountID BIGINT, transactionRef VARCHAR(255), OUT statusCode INT)
root:BEGIN
 
  DECLARE clientStatID, clientID, paymentMethodID, paymentProfileID, paymentPurchaseID, bit8PaymentGatewayID BIGINT DEFAULT -1;
  DECLARE accountReference, uniqueTransactionIDLast, paymentKey VARCHAR(80) DEFAULT NULL;
  DECLARE currencyCode VARCHAR(3) DEFAULT NULL;
  
  SELECT gaming_balance_accounts.client_stat_id, gaming_client_stats.client_id, payment_methods.payment_method_id, 
	IFNULL(all_overrides.payment_profile_id, IFNULL(country_overrides.payment_profile_id, IFNULL(currency_overrides.payment_profile_id, payment_methods.payment_profile_id))) AS payment_profile_id, 
    gaming_balance_accounts.account_reference, gaming_balance_accounts.unique_transaction_id_last, gaming_currency.currency_code 
  INTO clientStatID, clientID, paymentMethodID, paymentProfileID, accountReference, uniqueTransactionIDLast, currencyCode 
  FROM gaming_balance_accounts 
  JOIN gaming_client_stats ON gaming_balance_accounts.client_stat_id=gaming_client_stats.client_stat_id
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
  LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
  LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
  LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = IFNULL(gaming_balance_accounts.payment_method_id, gaming_balance_accounts.sub_payment_method_id)  
  LEFT JOIN payment_methods ON gaming_payment_method.payment_gateway_method_name=payment_methods.name AND 
	 ((gaming_payment_method.payment_gateway_method_sub_name IS NULL AND payment_methods.sub_name IS NULL) OR 
		gaming_payment_method.payment_gateway_method_sub_name=payment_methods.sub_name)
  LEFT JOIN payment_methods_currency_overrides AS currency_overrides ON payment_methods.payment_method_id=currency_overrides.payment_method_id AND currency_overrides.currency_code=gaming_currency.currency_code
  LEFT JOIN payment_methods_country_overrides AS country_overrides ON payment_methods.payment_method_id=country_overrides.payment_method_id AND country_overrides.country_code=gaming_countries.country_code
  LEFT JOIN payment_methods_all_overrides AS all_overrides ON payment_methods.payment_method_id=all_overrides.payment_method_id AND all_overrides.currency_code=gaming_currency.currency_code AND all_overrides.country_code=gaming_countries.country_code
  WHERE gaming_balance_accounts.balance_account_id=balanceAccountID;
  
  IF (clientStatID = -1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (uniqueTransactionIDLast IS NOT NULL) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  IF (paymentProfileID IS NOT NULL) THEN
	SELECT gaming_payment_gateways.payment_gateway_id INTO bit8PaymentGatewayID
    FROM payment_profiles
    JOIN payment_gateways ON payment_profiles.payment_gateway_id=payment_gateways.payment_gateway_id
    JOIN gaming_payment_gateways ON gaming_payment_gateways.payment_gateway_ref=payment_gateways.payment_gateway_id
    WHERE payment_profiles.payment_profile_id=paymentProfileID;
  END IF;
  
  SET paymentKey=PaymentGetPaymentKey(paymentMethodID);
  
  INSERT INTO payment_purchases(
    payment_key, currency_code, language_code, client_id, client_stat_id, client_email, restrict_account, use_preauth, items_total, amount_total, custom_data, 
    payment_url, callback_url, return_url, return_failure_url, site_type, date_created, date_expiry, payment_profile_id, payment_method_id, payment_purchase_status_id, session_id, is_test, client_ref, account_reference, transaction_ref)
  SELECT paymentKey, gaming_currency.currency_code, gaming_languages.language_code, gaming_clients.client_id, gaming_client_stats.client_stat_id, IFNULL(gaming_clients.email,''), 0, payment_methods.use_preauth, 0, 0, NULL, 
    'dummy', NULL, NULL, NULL, 'web', NOW(), NOW(), paymentProfileID, paymentMethodID, payment_purchase_statuses.payment_purchase_status_id, 0, payment_profiles.is_test, accountReference, accountReference, transactionRef
  FROM payment_methods
  JOIN payment_profiles ON payment_methods.payment_method_id=paymentMethodID AND payment_profiles.payment_profile_id=paymentProfileID
  JOIN payment_purchase_statuses ON payment_purchase_statuses.name='purchase_requested'
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id;

  SET paymentPurchaseID=LAST_INSERT_ID();

  INSERT INTO payments (payment_gateway_id, payment_type_id, payment_key, client_id, amount, currency_code, cvc_ok, payment_status_id, timestamp, payment_purchase_id)
  SELECT payment_profiles.payment_gateway_id, 1, paymentKey, clientID, 0, currencyCode, 0, 1, NOW(), paymentPurchaseID 
  FROM payment_profiles 
  WHERE payment_profile_id=paymentProfileID;
    
  UPDATE gaming_balance_accounts 
  SET unique_transaction_id_last=paymentKey, can_withdraw=1, payment_gateway_id=IFNULL(payment_gateway_id, bit8PaymentGatewayID)
  WHERE balance_account_id=balanceAccountID AND unique_transaction_id_last IS NULL;
  
  SET statusCode=0;
END root$$

DELIMITER ;

