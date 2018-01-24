DROP procedure IF EXISTS `PaymentCreatePurchase`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PaymentCreatePurchase`(clientStatID BIGINT, transactionType VARCHAR(20), paymentMethod VARCHAR(80), paymentMethodSub VARCHAR(80), bit8PaymentMethod VARCHAR(80), itemsTotal DECIMAL(14,0), customData VARCHAR(1024), successURL VARCHAR(512), failureURL VARCHAR(512), pendingURL VARCHAR(512), siteType VARCHAR(20), styleURL VARCHAR(512), varBrowser VARCHAR(20), languageCode VARCHAR(10), paymentProfile VARCHAR(40), sessionID BIGINT, ipAddress VARCHAR(80), cardId varchar(80), balanceAccountID BIGINT, OUT statusCode INT)
root:BEGIN
    
    -- Use Preauth: in payment_methods OR payment_gateway_methods
   -- Added balanceAccountID for withdrawals
   -- Limit 1 when inserting in payment_purchases: just in case we have multiple mappings for the same payment method as it is with Myriad 
   -- If subMethod is provided the payment_method_id of the sub method will be retrieved. This allows specifying different routing per credit card sub method. 
 
  DECLARE paymentMethodID, paymentProfileID, paymentPurchaseID, chargeSettingID, currencyID BIGINT DEFAULT -1;
  DECLARE dateExpiry DATETIME;
  DECLARE paymentKey VARCHAR(50);
  DECLARE paymentURL, withdrawalURL VARCHAR(1024);  
  DECLARE restrictAccount, subPaymentMethodFound, overAmount TINYINT(1) DEFAULT 0;
  DECLARE purchaseExpiryMinutes INT DEFAULT 10;
  DECLARE calculatedAmount, chargeAmount DECIMAL(14,0);
                  
  IF (paymentMethod IS NULL AND bit8PaymentMethod IS NOT NULL) THEN
	SELECT payment_gateway_method_name INTO paymentMethod FROM gaming_payment_method WHERE `name`=bit8PaymentMethod LIMIT 1;
  END IF;
  
  -- if sub name is specified get the sub payment method ID because for Wirecard need to specify which card provider
  IF (paymentMethodSub IS NOT NULL) THEN
	SELECT payment_method_id INTO paymentMethodID
    FROM payment_methods
    WHERE name=paymentMethod AND sub_name=paymentMethodSub AND payment_profile_id IS NOT NULL
	LIMIT 1;
  END IF;

  IF (paymentMethodID IS NULL OR paymentMethodID=-1) THEN
	SELECT payment_method_id INTO paymentMethodID
	FROM payment_methods
	WHERE payment_methods.name=paymentMethod AND is_sub_method=0
    LIMIT 1;
  ELSE
	SET subPaymentMethodFound=1;
  END IF;

  SELECT payment_profiles.payment_profile_id, gaming_currency.currency_id
  INTO paymentProfileID, currencyID
  FROM payment_methods
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
  LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
  LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
  LEFT JOIN payment_methods_currency_overrides AS currency_overrides ON payment_methods.payment_method_id=currency_overrides.payment_method_id AND currency_overrides.currency_code=gaming_currency.currency_code
  LEFT JOIN payment_methods_country_overrides AS country_overrides ON payment_methods.payment_method_id=country_overrides.payment_method_id AND country_overrides.country_code=gaming_countries.country_code
  LEFT JOIN payment_methods_all_overrides AS all_overrides ON payment_methods.payment_method_id=all_overrides.payment_method_id AND all_overrides.currency_code=gaming_currency.currency_code AND all_overrides.country_code=gaming_countries.country_code
  JOIN payment_profiles ON 
	((paymentProfile IS NULL OR payment_profiles.name=paymentProfile) AND
	(paymentProfile IS NOT NULL OR IFNULL(all_overrides.payment_profile_id, IFNULL(country_overrides.payment_profile_id, IFNULL(currency_overrides.payment_profile_id, payment_methods.payment_profile_id)))=payment_profiles.payment_profile_id
	))
	AND 
   payment_profiles.is_active=1 
  WHERE payment_methods.payment_method_id=paymentMethodID;

  IF (paymentProfileID IS NULL OR paymentProfileID=-1) THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;
    
  -- IF a sub method name is provided and the sub payment method was not set previously becuase no payment profile was found try again without the profile restriction
  IF (paymentMethodSub IS NOT NULL AND subPaymentMethodFound=0) THEN
	SELECT payment_method_id INTO paymentMethodID
    FROM payment_methods
    WHERE name=paymentMethod AND sub_name=paymentMethodSub
	LIMIT 1;
  END IF;

  SELECT payment_url, withdrawal_url, purchase_expiry, default_currency_code, default_language_code 
  INTO paymentURL, withdrawalURL, purchaseExpiryMinutes, @defaultCurrencyCode, @defaultLanguageCode
  FROM  payment_profiles WHERE payment_profile_id = paymentProfileID;
  
  SET paymentKey=PaymentGetPaymentKey(paymentMethodID);
  SET dateExpiry=DATE_ADD(NOW(), INTERVAL purchaseExpiryMinutes MINUTE);
  SET paymentURL=CONCAT(IFNULL(IF(transactionType='withdrawal', withdrawalURL, paymentURL),'www.bit8.com'),'/',paymentKey);
  SELECT value_bool INTO restrictAccount FROM gaming_settings WHERE name='TRANSFER_RESTRICT_ACCOUNT_TO_PLAYER';
  
  CALL PaymentCalculateCharge(transactionType, paymentMethodID, currencyID, itemsTotal, 0, chargeSettingID, calculatedAmount, chargeAmount, overAmount);

  INSERT INTO payment_purchases(
    payment_key, currency_code, language_code, client_id, client_stat_id, client_email, restrict_account, use_preauth, 
    items_total, charge_amount ,amount_total, custom_data, 
    payment_url, callback_url, return_url, return_failure_url, return_pending_url, site_type, style_url, browser, date_created, date_expiry, payment_profile_id, payment_method_id, payment_purchase_status_id, session_id, is_test, ip_address, card_id, transaction_type, balance_account_id, payment_charge_setting_id)
  SELECT paymentKey, gaming_currency.currency_code, IFNULL(languageCode, IFNULL(gaming_languages.language_code, payment_profiles.default_language_code)), gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.email, restrictAccount, IF(payment_methods.use_preauth OR IFNULL(payment_gateway_methods.use_preauth, 0), 1, 0), 
	chargeAmount + calculatedAmount, chargeAmount , chargeAmount + calculatedAmount, customData,  
	paymentURL, NULL, successURL, failureURL, pendingURL, siteType, styleURL, varBrowser, NOW(), dateExpiry, paymentProfileID, paymentMethodID, payment_purchase_statuses.payment_purchase_status_id, sessionID, payment_profiles.is_test, IFNULL(ipAddress, IFNULL(login_totals.last_ip_v4, gaming_clients.registration_ipaddress_v4)), cardId, transactionType, balanceAccountID, chargeSettingID
  FROM payment_methods
  JOIN payment_profiles ON payment_methods.payment_method_id=paymentMethodID AND payment_profiles.payment_profile_id=paymentProfileID
  JOIN payment_purchase_statuses ON payment_purchase_statuses.name='purchase_requested'
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  LEFT JOIN gaming_clients_login_attempts_totals AS login_totals ON login_totals.client_id=gaming_clients.client_id
  LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
  LEFT JOIN payment_gateway_methods ON payment_gateway_methods.payment_gateway_id=payment_profiles.payment_gateway_id AND payment_gateway_methods.payment_method_id=payment_methods.payment_method_id AND payment_gateway_methods.country_code IS NULL
  ORDER BY IFNULL(payment_gateway_methods.is_active, 1) DESC
  LIMIT 1; -- just in case we have multiple mappings for the same payment method as it is with Myriad 
  
  IF (ROW_COUNT()=0) THEN
	SET statusCode=2;
    LEAVE root;
  END IF;

  SET paymentPurchaseID=LAST_INSERT_ID();
  SELECT paymentPurchaseID AS payment_purchase_id, paymentKey AS payment_key, paymentURL AS payment_url;
  
  SET statusCode=0;
  LEAVE root;

END root$$

DELIMITER ;

