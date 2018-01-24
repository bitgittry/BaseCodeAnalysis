DROP procedure IF EXISTS `PlayerRegisterPlayerValidate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerRegisterPlayerValidate`(countryCode VARCHAR(3), currencyCode VARCHAR(3), languageCode VARCHAR(10), varEmail VARCHAR(80), extClientID VARCHAR(80), varUsername VARCHAR(45), varNickname VARCHAR(60), clientSecretQuestionID BIGINT, varMob VARCHAR(45), 
  countryIDFromIP BIGINT, countryRegionIDFromIP BIGINT, affiliateExternalID VARCHAR(80), affiliateSystemName VARCHAR(80), affiliateCouponCode VARCHAR(80), bonusCouponCode VARCHAR(80), excludeClientId BIGINT)
BEGIN

  DECLARE usernameCaseSensitive, allowUsernameOrEmailLogin TINYINT(1) DEFAULT 0;
  SET @affiliateID= NULL;
  SET @affiliateSystemIDFromAffiliate = NULL;
  SET @bonusCouponID=NULL;
  SET @affiliateID=NULL;
  SET @affiliateCouponID=NULL;
  SET @affiliateSystemID=NULL;
  SET @numEmailUsername = 0;
  SET @numUsernameEmail = 0;
  
  SELECT gs1.value_bool, gs2.value_bool
  INTO usernameCaseSensitive, allowUsernameOrEmailLogin
  FROM gaming_settings AS gs1
  STRAIGHT_JOIN gaming_settings AS gs2 ON gs2.name='ALLOW_USERNAME_OR_EMAIL_LOGIN'
  WHERE gs1.name='USERNAME_CASE_SENSITIVE';

  SELECT lock_id INTO @lockID FROM gaming_locks WHERE name='player_registration' FOR UPDATE;
  
  SELECT COUNT(*) INTO @numCountries FROM gaming_countries WHERE country_code=countryCode;
  SELECT COUNT(*) INTO @numCurrencies
  FROM gaming_operator_currency 
    JOIN gaming_currency ON gaming_currency.currency_code=currencyCode AND gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_operator_currency.is_active
    JOIN gaming_operators ON gaming_operators.is_main_operator=1 AND gaming_operator_currency.operator_id=gaming_operators.operator_id;
  SELECT COUNT(*) INTO @numLanguages FROM gaming_languages WHERE language_code=languageCode;
 
  SELECT COUNT(*) INTO @numEmail FROM gaming_clients FORCE INDEX (email) WHERE email=varEmail AND is_account_closed=0 AND (excludeClientId = 0 OR client_id != excludeClientId); 
  SELECT COUNT(*) INTO @numEmailUsername FROM gaming_clients FORCE INDEX (username) WHERE username=varEmail AND is_account_closed=0 AND (excludeClientId = 0 OR client_id != excludeClientId) AND allowUsernameOrEmailLogin; 
  
  SELECT COUNT(*) INTO @numUsername FROM gaming_clients FORCE INDEX (username) 
  WHERE gaming_clients.username=varUsername AND IF (usernameCaseSensitive=1, BINARY gaming_clients.username = varUsername, LOWER(username) = BINARY LOWER(varUsername)) AND is_account_closed=0 AND (excludeClientId = 0 OR client_id != excludeClientId);

  SELECT COUNT(*) INTO @numUsernameEmail FROM gaming_clients FORCE INDEX (email) WHERE (gaming_clients.email=varUsername AND IF (usernameCaseSensitive=1, BINARY gaming_clients.username = varUsername,1)) AND is_account_closed=0 AND (excludeClientId = 0 OR client_id != excludeClientId) AND allowUsernameOrEmailLogin; 
  SELECT COUNT(*) INTO @numNickname FROM gaming_clients FORCE INDEX (nickname) WHERE nickname=varNickname AND is_account_closed=0 AND (excludeClientId = 0 OR client_id != excludeClientId); 
  SELECT COUNT(*) INTO @numExtClientID FROM gaming_clients FORCE INDEX (ext_client_id) WHERE ext_client_id=extClientID AND (excludeClientId = 0 OR client_id != excludeClientId); 
  SELECT COUNT(*) INTO @numMob FROM gaming_clients FORCE INDEX (mob) WHERE mob=varMob AND is_account_closed=0; 
  
  SELECT COUNT(*) INTO @numSecretQuestion FROM gaming_client_secret_questions WHERE client_secret_question_id=clientSecretQuestionID;                    
  
  SELECT COUNT(*) INTO @numBannedCountriesIP FROM gaming_fraud_banned_countries_from_ips WHERE (country_id=countryIDFromIP AND country_region_id = 0 AND disallow_register=1) OR (country_id=countryIDFromIP AND country_region_id =countryRegionIDFromIP AND disallow_register=1); 
  
  SELECT affiliate_id, affiliate_system_id, COUNT(*) 
  INTO @affiliateID, @affiliateSystemIDFromAffiliate, @numAffiliates 
  FROM gaming_affiliates FORCE INDEX (external_id) WHERE external_id=affiliateExternalID AND is_active=1;

  SELECT affiliate_system_id, COUNT(*) INTO @affiliateSystemID, @numAffiliateSystems FROM gaming_affiliate_systems WHERE name=affiliateSystemName AND is_active=1;
  SELECT affiliate_coupon_id, affiliate_id, COUNT(*) INTO @affiliateCouponID, @affiliateIDFromCoupon, @numAffiliateCoupons FROM gaming_affiliate_coupons FORCE INDEX (coupon_code) WHERE coupon_code=affiliateCouponCode AND (NOW() BETWEEN validity_start_date AND validity_end_date) AND is_active=1;
  
  SELECT bonus_coupon_id, COUNT(*) INTO @bonusCouponID, @numBonusCoupons 
  FROM gaming_bonus_coupons FORCE INDEX (coupon_code)
  WHERE coupon_code=bonusCouponCode AND (NOW() BETWEEN validity_start_date AND validity_end_date) AND is_active=1 AND is_hidden=0;
  
  SELECT bonus_coupon_id INTO @defaultBonusCouponID 
  FROM gaming_bonus_coupons FORCE INDEX (default_registration_coupon)
  WHERE default_registration_coupon=1 
  LIMIT 1;
  
  SELECT @numCountries, @numCurrencies, @numLanguages, @numEmail + @numEmailUsername  AS `@numEmail`, @numExtClientID, 
		 @numUsername + @numUsernameEmail AS `@numUsername`, @numNickname, @numMob, @numBannedCountriesIP, @numSecretQuestion,
         @affiliateID, @affiliateSystemIDFromAffiliate, @numAffiliates, @affiliateSystemID, @numAffiliateSystems, 
         @affiliateCouponID, @affiliateIDFromCoupon, @numAffiliateCoupons, @bonusCouponID, @numBonusCoupons, @defaultBonusCouponID; 
         
END$$

DELIMITER ;

