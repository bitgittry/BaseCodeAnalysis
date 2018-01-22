DROP procedure IF EXISTS `PlayerRegisterPlayer`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerRegisterPlayer`(varTitle VARCHAR(10), firstName VARCHAR(80), middleName VARCHAR(40), lastName VARCHAR(80), secondLastName VARCHAR(80), varDob DATETIME, varGender CHAR(1), varEmail VARCHAR(255), varMob VARCHAR(45), priTelephone VARCHAR(45), secTelephone VARCHAR(45), languageCode VARCHAR(10), varUsername VARCHAR(45), varPassword VARCHAR(250), varSalt VARCHAR(60), varNickname VARCHAR(60), varPin VARCHAR(30),
  receivePromotional TINYINT(1), receivePromotionalByEmail TINYINT(1), receivePromotionalByPost TINYINT(1), receivePromotionalBySMS TINYINT(1), receivePromotionalByPhone TINYINT(1), receivePromotionalByMobile TINYINT(1), receivePromotionalByThirdParty TINYINT(1),
  contactByEmail TINYINT(1), contactBySMS TINYINT(1), contactByPost TINYINT(1), contactByPhone TINYINT(1), contactByMobile TINYINT(1), contactByThirdParty TINYINT(1), activationCode VARCHAR(80), accountActivated TINYINT(1), isTestPlayer TINYINT(1), registrationIpAddress VARCHAR(40), registrationIpAddressV4 VARCHAR(20), countryIDFromIP BIGINT, affiliateID BIGINT, affiliateCouponID BIGINT, affiliateRegistrationCode VARCHAR(255),
  bonusCouponID BIGINT, originalAffiliateCouponCode VARCHAR(80), originalReferralCode VARCHAR(80), originalBonusCouponCode VARCHAR(80), affiliateCampaignID BIGINT, affiliateSystemID BIGINT, acquisitionType VARCHAR(80),
  varAddress_1 VARCHAR(255), varAddress_2 VARCHAR(255), varCity VARCHAR(80), postCode VARCHAR(80), countryCode VARCHAR(3), currencyCode VARCHAR(3), extClientID VARCHAR(80), CommitAndChain TINYINT(1), 
  HashingFunction VARCHAR(80), bypassCheck TINYINT(1), BetFactor DECIMAL(22,9), macAddress VARCHAR(40), downloadClientID VARCHAR(40), platformType VARCHAR(20), stateID BIGINT, riskScore DECIMAL(22,9), vipLevel INT(11), canContact TINYINT(1), 
  uaBrandName VARCHAR(60), uaModelName VARCHAR(60), uaOSName VARCHAR(60), uaOSVersionName VARCHAR(60), uaBrowserName VARCHAR(60), uaBrowserVersionName VARCHAR(60), uaEngineName VARCHAR(60), uaEngineVersionName VARCHAR(60), testPlayerAllowTransfer TINYINT(1), bonusSeeker TINYINT(1), bonusDontWant TINYINT(1), 
  authenticationPIN VARCHAR(250), registrationType VARCHAR(5), isManuallyRegistered TINYINT(1), stateName VARCHAR(128), townName VARCHAR(128), streetNumber VARCHAR(45), streetType VARCHAR(80), streetName VARCHAR(255), houseName VARCHAR(80), houseNumber VARCHAR(45), flatNumber VARCHAR(45), poBoxName VARCHAR(80), suburbName VARCHAR(40), registeredByUserID BIGINT, fieldDefinitionType VARCHAR(80), 
  clientRiskCategoryId INT, varToken VARCHAR(30), retailerID VARCHAR(20), agentID VARCHAR(20),  OUT statusCode INT)
root:BEGIN

  DECLARE accountActivationPolicy, downloadClientEnabled, playerSetClientIDAsExternalID, ruleEngineEnabled, preKYCRestriction, 
	enhancedKycCheckedStatusesEnabled, taxOnGamePlay, uaAgentEnabled TINYINT(1) DEFAULT 0; 
  DECLARE langaugeID, currencyID, paymentClientSegmentID, riskClientSegmentID, paymentClientSegemntGroupID, riskClientSegmentGroupID, 
	defaultCurrencyID, defaultLanguageID, cityID, townID, postcodeID, streetTypeID, streetID, suburbID, clientLocationID BIGINT DEFAULT NULL;
  DECLARE HashTypeID INT DEFAULT 0;
  DECLARE clientSegmentRiskName VARCHAR(40);
  DECLARE operatorID, platformTypeID, defaultKYCCheckedStatusID INT DEFAULT NULL;
  DECLARE clientID, clientStatID, exclientIDCheck BIGINT;
  DECLARE countryID BIGINT DEFAULT -1;
  DECLARE defaultCountryCode CHAR(2);
  DECLARE uaBrandID, uaModelID, uaOSID, uaOSVersionID, uaBrowserID, 
	uaBrowserVersionID, uaEngineID, uaEngineVersionID, fieldDefinitionTypeID BIGINT(20) DEFAULT NULL; 

  SELECT gs1.value_bool, IFNULL(gs2.value_string, 'risk_categories'), IFNULL(gs3.value_bool, 0), IFNULL(gs4.value_bool, 0), 
  IFNULL(gs5.value_bool, 0), IFNULL(gs6.value_bool, 0), IFNULL(gs7.value_bool, 0), IFNULL(gs8.value_bool, 0), IFNULL(gs9.value_bool, 0)
  INTO accountActivationPolicy, clientSegmentRiskName, downloadClientEnabled, playerSetClientIDAsExternalID, 
	ruleEngineEnabled, preKYCRestriction, enhancedKycCheckedStatusesEnabled, taxOnGamePlay, uaAgentEnabled
  FROM gaming_settings AS gs1
  LEFT JOIN gaming_settings AS gs2 ON gs2.name='PLAYER_CLIENT_SEGMENT_RISK_NAME'
  LEFT JOIN gaming_settings AS gs3 ON gs3.name='DOWNLOAD_CLIENT_AVAILABLE'
  LEFT JOIN gaming_settings AS gs4 ON gs4.name='PLAYER_SET_CLIENT_ID_AS_EXTERNAL_ID'
  LEFT JOIN gaming_settings AS gs5 ON gs5.name='RULE_ENGINE_ENABLED'
  LEFT JOIN gaming_settings AS gs6 ON gs6.name='REGISTRATION_ACCOUNT_PRE_KYC_RESTRICTION_ENABLED'
  LEFT JOIN gaming_settings AS gs7 ON gs7.name='ENHANCED_KYC_CHECKED_STATUSES'
  LEFT JOIN gaming_settings AS gs8 ON gs8.name='TAX_ON_GAMEPLAY_ENABLED'
  LEFT JOIN gaming_settings AS gs9 ON gs9.name='UA_AGENT_ENABLED'
  WHERE gs1.name='REGISTRATION_ACCOUNT_ACTIVATION_POLICY_ENABLED';

  SELECT gaming_operators.operator_id, gaming_operators.currency_id, gaming_operators.language_id, IFNULL(gaming_operators.country_code,'MT')
  INTO operatorID, defaultCurrencyID, defaultLanguageID, defaultCountryCode
  FROM gaming_operators 
  WHERE gaming_operators.is_main_operator=1 LIMIT 1;
  
  SET countryCode = IF(IFNULL(countryCode, '') = '', defaultCountryCode, countryCode);

  SET statusCode = 0;

  SELECT pass_hash_type_id INTO HashTypeID FROM gaming_clients_pass_hash_type WHERE name= HashingFunction;
  IF (HashTypeID = 0) THEN
    SET statusCode = 1;
    LEAVE root;
  END IF;

  IF (fieldDefinitionType IS NOT NULL AND fieldDefinitionType <> '') THEN
	SELECT field_definition_type_id	INTO fieldDefinitionTypeID FROM gaming_field_definition_types WHERE `name` = fieldDefinitionType LIMIT 1;
  END IF;

  IF (downloadClientEnabled=0) THEN
    SET platformTypeID = 0;
  ELSE
    SELECT platform_type_id INTO platformTypeID FROM gaming_platform_types WHERE platform_type=platformType;
    IF (platformTypeID IS NULL) THEN
      SELECT platform_type_id INTO platformTypeID FROM gaming_platform_types WHERE is_default=1 LIMIT 1;
    END IF;
  END IF;

  SELECT language_id INTO langaugeID FROM gaming_languages WHERE gaming_languages.language_code=languageCode;
  
  SELECT gaming_client_segment_groups.client_segment_group_id, gaming_client_segments.client_segment_id 
  INTO paymentClientSegemntGroupID, paymentClientSegmentID 
  FROM gaming_client_segment_groups 
  JOIN gaming_client_segments ON gaming_client_segment_groups.is_payment_group=1 
	AND gaming_client_segment_groups.client_segment_group_id=gaming_client_segments.client_segment_group_id 
    AND gaming_client_segments.is_default=1 
  LIMIT 1;
  
  SELECT gaming_client_segment_groups.client_segment_group_id, gaming_client_segments.client_segment_id 
  INTO riskClientSegmentGroupID, riskClientSegmentID 
  FROM gaming_client_segment_groups 
  JOIN gaming_client_segments ON gaming_client_segment_groups.name=clientSegmentRiskName 
	AND  gaming_client_segment_groups.client_segment_group_id=gaming_client_segments.client_segment_group_id 
    AND gaming_client_segments.is_default=1 
  LIMIT 1;

  IF (playerSetClientIDAsExternalID AND IFNULL((SELECT extClientID REGEXP '^-?[0-9]{1,19}$'), 0)) THEN
	SET exclientIDCheck=extClientID;
    SELECT 0 INTO playerSetClientIDAsExternalID FROM gaming_clients WHERE client_id=exclientIDCheck;
    SELECT 0 INTO playerSetClientIDAsExternalID FROM gaming_client_stats WHERE client_stat_id=exclientIDCheck;
  ELSE
	SET playerSetClientIDAsExternalID=0;
  END IF;
  
  IF (enhancedKycCheckedStatusesEnabled) THEN
	-- Enhanced KYC - Get default state
		SELECT kyc_checked_status_id INTO defaultKYCCheckedStatusID FROM gaming_kyc_checked_statuses WHERE is_default=1 AND is_hidden = 0 LIMIT 1;
  END IF;

  IF (playerSetClientIDAsExternalID) THEN
	  INSERT INTO gaming_clients (client_id, title, name, middle_name, surname, sec_surname, dob, gender, email, mob, pri_telephone, sec_telephone, language_id, username, password, salt, nickname, PIN1, 
		  receive_promotional_by_email, receive_promotional_by_sms, receive_promotional_by_post, receive_promotional_by_phone, receive_promotional_by_mobile, receive_promotional_by_third_party, 
		  contact_by_email, contact_by_sms, contact_by_post, contact_by_phone, contact_by_mobile, contact_by_third_party, sign_up_date, client_segment_id, activation_code, 
		  account_activated, is_test_player, registration_ipaddress, registration_ipaddress_v4, country_id_from_ip, affiliate_id, affiliate_coupon_id, affiliate_registration_code, affiliate_campaign_id ,
		  bonus_coupon_id, original_affiliate_coupon_code, original_referral_code, original_bonus_coupon_code, test_player_allow_transfers, client_acquisition_type_id, affiliate_system_id, is_active, 
		  fraud_similar_details, ext_client_id, referral_client_id, last_updated, pass_hash_type, bet_factor, risk_client_segment_id, mac_address, download_client_id, platform_type_id, 
		  risk_score, bonus_seeker, bonus_dont_want, last_password_change_date, num_password_changes, failed_consecutive_PIN_code_attempts, failed_total_PIN_code_attempts,
		  authentication_pin, num_pin_changes,vip_level, day_of_year_dob, day_of_year_sign_up, is_manually_registered, registered_by_user_id, field_definition_type_id, kyc_checked_status_id, client_risk_category_id, PIN2, retailer_id, agent_id) 
	  SELECT extClientID, varTitle, firstName, middleName, lastName, secondLastName, varDob, varGender, varEmail, varMob, priTelephone, secTelephone, IFNULL(langaugeID, defaultLanguageID), varUsername, varPassword, varSalt, varNickname, varPin, 
		  IF(receivePromotional, IFNULL(receivePromotionalByEmail, receivePromotional), 0), 
          IF(receivePromotional, IFNULL(receivePromotionalBySMS, receivePromotional), 0), 
		  IF(receivePromotional, IFNULL(receivePromotionalByPost, receivePromotional), 0), 
		  IF(receivePromotional, IFNULL(receivePromotionalByPhone, receivePromotional), 0), 
          IF(receivePromotional, IFNULL(receivePromotionalByMobile, receivePromotional), 0),
          IF(receivePromotional, IFNULL(receivePromotionalByThirdParty, receivePromotional), 0), contactByEmail, contactBySMS, contactByPost, contactByPhone, contactByMobile, contactByThirdParty, NOW(), gaming_client_segments.client_segment_id, activationCode, 
		  accountActivated, isTestPlayer, registrationIpAddress, registrationIpAddressV4, countryIDFromIP, affiliateID, affiliateCouponID, affiliateRegistrationCode, affiliateCampaignID,
		  bonusCouponID, originalAffiliateCouponCode, originalReferralCode, originalBonusCouponCode, testPlayerAllowTransfer, gaming_client_acquisition_types.client_acquisition_type_id, affiliateSystemID, 1,
		  SPLIT_EMAIL_IN_WORDS(varEmail, 5, ' '),
          extClientID, referral_client.client_id, NOW(), HashTypeID, 
		  BetFactor, riskClientSegmentID, macAddress, downloadClientID, platformTypeID, riskScore, bonusSeeker, bonusDontWant, NOW(), 1, 0, 0, authenticationPIN,
		  IF(authenticationPIN IS NOT NULL AND authenticationPIN <> '', 1, 0), vipLevel, IF(varDob IS NULL, 0, DAYOFYEAR(varDob)), DAYOFYEAR(NOW()), isManuallyRegistered, registeredByUserID, fieldDefinitionTypeID, defaultKYCCheckedStatusID, clientRiskCategoryId, varToken, retailerID, agentID
	  FROM gaming_client_segments
	  LEFT JOIN gaming_client_acquisition_types ON 
		(acquisitionType IS NULL AND gaming_client_acquisition_types.is_default=1) 
        OR gaming_client_acquisition_types.name=acquisitionType
	  LEFT JOIN gaming_clients AS referral_client FORCE INDEX (referral_code) ON referral_code=originalReferralCode
	  WHERE gaming_client_segments.client_segment_id=paymentClientSegmentID
	  LIMIT 1; 
	  SET clientID=extClientID;
  ELSE
	  INSERT INTO gaming_clients (title, name, middle_name, surname, sec_surname, dob, gender, email, mob, pri_telephone, sec_telephone, language_id, username, password, salt, nickname, PIN1, 
		  receive_promotional_by_email, receive_promotional_by_sms, receive_promotional_by_post, receive_promotional_by_phone, receive_promotional_by_mobile, receive_promotional_by_third_party,
		  contact_by_email, contact_by_sms, contact_by_post, contact_by_phone, contact_by_mobile, contact_by_third_party, sign_up_date, client_segment_id, activation_code, 
		  account_activated, is_test_player, registration_ipaddress, registration_ipaddress_v4, country_id_from_ip, affiliate_id, affiliate_coupon_id, affiliate_registration_code, affiliate_campaign_id ,
		  bonus_coupon_id, original_affiliate_coupon_code, original_referral_code, original_bonus_coupon_code, test_player_allow_transfers, client_acquisition_type_id, affiliate_system_id, is_active, 
		  fraud_similar_details, ext_client_id, referral_client_id, last_updated, pass_hash_type, bet_factor, risk_client_segment_id, mac_address, download_client_id, platform_type_id, 
		  risk_score, bonus_seeker, bonus_dont_want, last_password_change_date, num_password_changes, failed_consecutive_PIN_code_attempts, failed_total_PIN_code_attempts,
		  authentication_pin, num_pin_changes, vip_level, day_of_year_dob, day_of_year_sign_up, is_manually_registered, registered_by_user_id, field_definition_type_id, kyc_checked_status_id, client_risk_category_id, PIN2, retailer_id, agent_id) 
	  SELECT varTitle, firstName, middleName, lastName, secondLastName, varDob, varGender, varEmail, varMob, priTelephone, secTelephone, IFNULL(langaugeID, defaultLanguageID), varUsername, varPassword, varSalt, varNickname, varPin, 
		  IF(receivePromotional, IFNULL(receivePromotionalByEmail, receivePromotional), 0), 
          IF(receivePromotional, IFNULL(receivePromotionalBySMS, receivePromotional), 0), 
		  IF(receivePromotional, IFNULL(receivePromotionalByPost, receivePromotional), 0), 
		  IF(receivePromotional, IFNULL(receivePromotionalByPhone, receivePromotional), 0), 
          IF(receivePromotional, IFNULL(receivePromotionalByMobile, receivePromotional), 0),
          IF(receivePromotional, IFNULL(receivePromotionalByThirdParty, receivePromotional), 0), contactByEmail, contactBySMS, contactByPost, contactByPhone, contactByMobile, contactByThirdParty, NOW(), gaming_client_segments.client_segment_id, activationCode, 
		  accountActivated, isTestPlayer, registrationIpAddress, registrationIpAddressV4, countryIDFromIP, affiliateID, affiliateCouponID, affiliateRegistrationCode, affiliateCampaignID,
		  bonusCouponID, originalAffiliateCouponCode, originalReferralCode, originalBonusCouponCode, testPlayerAllowTransfer, gaming_client_acquisition_types.client_acquisition_type_id, affiliateSystemID, 1,
		  SPLIT_EMAIL_IN_WORDS(varEmail, 5, ' '),
          extClientID, referral_client.client_id, NOW(), HashTypeID, 
		  BetFactor, riskClientSegmentID, macAddress, downloadClientID, platformTypeID, riskScore, bonusSeeker, bonusDontWant, NOW(), 1, 0, 0, authenticationPIN,
		  IF(authenticationPIN IS NOT NULL AND authenticationPIN <> '', 1, 0), vipLevel, IF(varDob IS NULL, 0, DAYOFYEAR(varDob)), DAYOFYEAR(NOW()), isManuallyRegistered, registeredByUserID, fieldDefinitionTypeID, defaultKYCCheckedStatusID, clientRiskCategoryId, varToken, retailerID, agentID
	  FROM gaming_client_segments
	  LEFT JOIN gaming_client_acquisition_types ON 
		(acquisitionType IS NULL AND gaming_client_acquisition_types.is_default=1) 
        OR gaming_client_acquisition_types.name=acquisitionType
	  LEFT JOIN gaming_clients AS referral_client FORCE INDEX (referral_code) ON referral_code=originalReferralCode
	  WHERE gaming_client_segments.client_segment_id=paymentClientSegmentID
	  LIMIT 1; 
	  
	  SET clientID=LAST_INSERT_ID();
  END IF;

  IF (authenticationPIN IS NOT NULL AND authenticationPIN <> '') THEN
	INSERT INTO gaming_clients_pin_changes (client_id, change_num, hashed_pin, salt)
	VALUES (clientID, 1, authenticationPIN, varSalt);
  END IF;

  SELECT country_id INTO countryID FROM gaming_countries WHERE country_code = countryCode;
   
  SELECT countries_municipality_id INTO cityID FROM gaming_countries_municipalities 
	JOIN gaming_municipalities_types ON gaming_countries_municipalities.municipality_type_id = gaming_municipalities_types.municipality_type_id
	AND gaming_municipalities_types.name = 'City' AND country_id=countryID
  WHERE gaming_countries_municipalities.countries_municipality_name=varCity AND is_active=1;

  SELECT countries_municipality_id INTO townID FROM gaming_countries_municipalities 
	JOIN gaming_municipalities_types ON gaming_countries_municipalities.municipality_type_id = gaming_municipalities_types.municipality_type_id
	AND gaming_municipalities_types.name = 'Town' AND country_id=countryID
  WHERE gaming_countries_municipalities.countries_municipality_name=townName AND is_active=1;
 
  SELECT state_id INTO stateID FROM gaming_countries_states WHERE `name`=stateName AND country_id=countryID AND is_active=1;
  SELECT street_type_id INTO streetTypeID FROM gaming_countries_street_types WHERE street_type_description=streetType AND is_active=1;
  SELECT countries_street_id INTO streetID FROM gaming_countries_streets WHERE countries_street_description=streetName AND country_id=countryID AND is_active=1;
  SELECT countries_post_code_id INTO postcodeID FROM gaming_countries_post_codes WHERE country_post_code_name=postcode AND country_id=countryID AND is_active=1;
  SELECT suburb_id INTO suburbID FROM gaming_countries_suburbs WHERE suburb_name=suburbName AND country_id=countryID AND is_active=1;

  INSERT INTO clients_locations (client_id, address_1, address_2, city, country_id, postcode, is_active, state_id,
	city_id, state_name, town_name, town_id, postcode_id, street_type_desc, street_type_id, street_name, street_id, 
    house_name, house_number, flat_number, po_box_name, suburb, suburb_id, street_number) 
  SELECT clientID, varAddress_1, varAddress_2, varCity, gaming_countries.country_id, postCode, 1, stateID,
	cityID, stateName, townName, townID, postcodeID, streetType, streetTypeID, streetName, streetID,
    houseName, houseNumber, flatNumber, poBoxName, suburbName, suburbID, streetNumber
  FROM gaming_clients 
  LEFT JOIN gaming_countries ON gaming_countries.country_code=countryCode
  WHERE gaming_clients.client_id=clientID; 
  
  SET clientLocationID=LAST_INSERT_ID();

  INSERT INTO gaming_clients_external_checks (client_id)
  SELECT clientID;
  
  IF (varPassword IS NOT NULL) THEN 
	  INSERT INTO gaming_clients_password_changes (client_id, change_num, hashed_password, salt)
	  VALUES (clientID, 1, varPassword, varSalt);
  END IF;
  
  SELECT currency_id INTO currencyID FROM gaming_currency WHERE currency_code = currencyCode;

  IF (playerSetClientIDAsExternalID) THEN
 	  INSERT INTO gaming_client_stats (client_stat_id, client_id, currency_id, active_date, is_active) 
	  VALUES (extClientID, clientID, IFNULL(currencyID, defaultCurrencyID), NOW(), 1); 
      SET clientStatID=extClientID;      
  ELSE
	  INSERT INTO gaming_client_stats (client_id, currency_id, active_date, is_active) 
	  VALUES (clientID, IFNULL(currencyID, defaultCurrencyID), NOW(), 1);
      SET clientStatID=LAST_INSERT_ID();      
  END IF;

  /*IF (taxOnGamePlay = 1) THEN
		-- create a tax cycle per licence type id (casino, sportbook, etc) ONLY IF: 
		--   	- player have a country defined
		-- 		- 'Deferred' tax rule is defined for player country
		INSERT INTO gaming_tax_cycles (country_tax_id, client_stat_id, deferred_tax_amount, cycle_start_date, cycle_end_date, is_active)
		SELECT gaming_country_tax.country_tax_id, clientStatID, 0, NOW(), '3000-01-01 00:00:00', 1
		FROM gaming_country_tax JOIN clients_locations on gaming_country_tax.country_id = clients_locations.country_id
		WHERE clients_locations.client_location_id = clientLocationID
		AND gaming_country_tax.is_current = 1
		AND gaming_country_tax.is_active = 1
		AND gaming_country_tax.applied_on = 'Deferred'
		AND NOW() BETWEEN gaming_country_tax.date_start AND gaming_country_tax.date_end;
		-- gaming_tax_cycles.cycle_end_date will be updated at the time of closing tax cycle.
  END IF;*/

  UPDATE gaming_client_stats 
  SET max_player_balance_threshold = (SELECT max_player_balance_threshold FROM gaming_countries WHERE gaming_countries.country_code = countryCode)
  WHERE client_stat_id = clientStatID;

   CALL PlayerUpdateVIPLevel(clientStatID,0);

  INSERT INTO gaming_client_stats_no_lock(client_stat_id, client_id, currency_id, is_active) 
  SELECT clientStatID, clientID, currency_id, 1 
  FROM gaming_client_stats 
  WHERE client_stat_id=clientStatID; 

  INSERT INTO gaming_client_wager_stats (client_stat_id, client_wager_type_id)
  SELECT clientStatID, client_wager_type_id
  FROM gaming_client_wager_types
  WHERE is_active=1;

  INSERT INTO gaming_clients_login_attempts_totals(client_id) 
  VALUES (clientID);
  
  INSERT INTO gaming_fraud_rule_client_settings (client_id) 
  VALUES (clientID);
  
  IF (ruleEngineEnabled) THEN
	INSERT INTO gaming_event_rows (event_table_id, elem_id, rule_engine_state) SELECT 5, clientID, 0 ON DUPLICATE KEY UPDATE elem_id=clientID;
  END IF;
  
  IF CommitAndChain THEN
    COMMIT AND CHAIN;
  END IF;

  SELECT clientID AS client_id, clientStatID AS client_stat_id;
  
  CALL PlayerUpdateUniquePin(clientID, bypassCheck, @pinStatusCode);
  CALL PlayerUpdateUniqueToken(clientID, bypassCheck, @tokenStatusCode);
  
  CALL PlayerUpdateUniqueReferralCode(clientID, bypassCheck, @referralStatusCode);
  
  IF (accountActivated=0 AND accountActivationPolicy) THEN
    CALL PlayerRestrictionAddRestriction(clientID, clientStatID, 'account_activation_policy', 1, NULL, NULL, NULL, NULL, 0, NULL, 'Registration', 1, @activationResStatusCode);
  ELSE

    SELECT 0 AS player_restriction_id;
    SELECT NULL;

  END IF;

	IF (preKYCRestriction = 1) THEN
    CALL PlayerRestrictionAddRestriction(clientID, clientStatID, 'pre_kyc_restriction', 1, NULL, NULL, NULL, NULL, 0, NULL, 'Non KYC-ed', 1, @activationResStatusCode);
  ELSE

    SELECT 0 AS player_restriction_id;
    SELECT NULL;

  END IF;

  IF (paymentClientSegmentID IS NOT NULL) THEN 
    INSERT INTO gaming_client_segments_players (client_segment_group_id, client_id, client_segment_id, date_from, date_to, is_current)
    SELECT paymentClientSegemntGroupID, clientID, paymentClientSegmentID, NOW(), NULL, 1
    ON DUPLICATE KEY UPDATE date_to=NULL, is_current=1;
  END IF;
  IF (riskClientSegmentID IS NOT NULL) THEN
    INSERT INTO gaming_client_segments_players (client_segment_group_id, client_id, client_segment_id, date_from, date_to, is_current)
    SELECT riskClientSegmentGroupID, clientID, riskClientSegmentID, NOW(), NULL, 1
    ON DUPLICATE KEY UPDATE date_to=NULL, is_current=1;
  END IF;
  
  INSERT INTO gaming_client_segments_players (client_segment_group_id, client_id, client_segment_id, date_from, date_to, is_current)
  SELECT gcs.client_segment_group_id, clientID, gcs.client_segment_id, NOW(), NULL, 1
  FROM gaming_client_segment_groups AS gcsg
  JOIN gaming_client_segments AS gcs ON gcsg.is_active AND gcsg.client_segment_group_id=gcs.client_segment_group_id AND gcs.is_active AND gcs.is_default
  WHERE gcsg.client_segment_group_id NOT IN (IFNULL(paymentClientSegemntGroupID,0), IFNULL(riskClientSegmentGroupID,0))	
  ON DUPLICATE KEY UPDATE date_to=NULL, is_current=1;
  
  IF (uaAgentEnabled) THEN
	  
	  IF (uaBrandName IS NOT NULL) THEN
		SELECT ua_brand_id INTO uaBrandID
		FROM gaming_ua_brands 
		WHERE gaming_ua_brands.name = uaBrandName;

		IF (uaBrandID IS NULL) THEN
			INSERT INTO gaming_ua_brands (name)
			VALUES (uaBrandName);
			SET uaBrandID=LAST_INSERT_ID();     
		END IF;
	  END IF;

	  IF (uaModelName IS NOT NULL) THEN 	
		SELECT ua_model_id INTO uaModelID
		FROM gaming_ua_models 
		WHERE gaming_ua_models.name = uaModelName;

		IF (uaModelID IS NULL) THEN
			INSERT INTO gaming_ua_models (ua_model_type_id, ua_brand_id, name)
			VALUES (1, uaBrandID, uaModelName);
			SET uaModelID=LAST_INSERT_ID();
		END IF;
	  END IF;

	  IF (uaOSName IS NOT NULL) THEN
		SELECT ua_os_id INTO uaOSID
		FROM gaming_ua_os
		WHERE gaming_ua_os.name = uaOSName;

		IF (uaOSID IS NULL) THEN
			INSERT INTO gaming_ua_os (name)
			VALUES (uaOSName);
			SET uaOSID=LAST_INSERT_ID();          
		END IF;              
	  END IF;

	  IF (uaOSVersionName IS NOT NULL) THEN 	
		SELECT ua_os_version_id INTO uaOSVersionID
		FROM gaming_ua_os_versions 
		WHERE gaming_ua_os_versions.name = uaOSVersionName;

		IF (uaOSVersionID IS NULL) THEN
			INSERT INTO gaming_ua_os_versions (ua_os_id, name)
			VALUES (uaOSID, uaOSVersionName);
			SET uaOSVersionID=LAST_INSERT_ID();       
		END IF;                 
	  END IF;

	  IF (uaBrowserName IS NOT NULL) THEN 
		SELECT ua_browser_id INTO uaBrowserID
		FROM gaming_ua_browsers
		WHERE gaming_ua_browsers.name = uaBrowserName;

		IF (uaBrowserID IS NULL) THEN
			INSERT INTO gaming_ua_browsers (name)
			VALUES (uaBrowserName);
			SET uaBrowserID=LAST_INSERT_ID();         
		END IF;               
	  END IF;

	  IF (uaBrowserVersionName IS NOT NULL) THEN 
		SELECT ua_browser_version_id INTO uaBrowserVersionID
		FROM gaming_ua_browser_versions
		WHERE gaming_ua_browser_versions.name = uaBrowserVersionName;	

		IF (uaBrowserVersionID IS NULL) THEN
			INSERT INTO gaming_ua_browser_versions (ua_browser_id, name)
			VALUES (uaBrowserID, uaBrowserVersionName);
			SET uaBrowserVersionID=LAST_INSERT_ID();     
		END IF;                   
	  END IF;

	  IF (uaEngineName IS NOT NULL) THEN 	
		SELECT ua_engine_id INTO uaEngineID
		FROM gaming_ua_engines 
		WHERE gaming_ua_engines.name = uaEngineName;

		IF (uaEngineID IS NULL) THEN
			INSERT INTO gaming_ua_engines (name)
			VALUES (uaEngineName);
			SET uaEngineID=LAST_INSERT_ID();          
		END IF;              
	  END IF;

	  IF (uaEngineVersionName IS NOT NULL) THEN 	
		SELECT ua_engine_version_id INTO uaEngineVersionID
		FROM gaming_ua_engine_versions 
		WHERE gaming_ua_engine_versions.name = uaEngineVersionName;

		IF (uaEngineVersionID IS NULL) THEN
			INSERT INTO gaming_ua_engine_versions (ua_engine_id, name)
			VALUES (uaEngineID, uaEngineVersionName);
			SET uaEngineVersionID=LAST_INSERT_ID();      
		END IF;                  
	  END IF;

	  INSERT INTO gaming_client_ua_registrations (
		client_id, ua_brand_id, ua_model_id, ua_os_id, ua_os_version_id, ua_browser_id, 
		ua_browser_version_id, ua_engine_id, ua_engine_version_id)
	  VALUES (clientID, uaBrandID, uaModelID, uaOSID, uaOSVersionID, uaBrowserID, uaBrowserVersionID, uaEngineID, uaEngineVersionID);
	  
  END IF;
  
  SELECT channel_type_id INTO @channelTypeID FROM gaming_channels_platform_types WHERE platform_type_id = platformTypeID;

  INSERT INTO gaming_client_registrations
  (
    client_id,
    client_registration_type_id,
    is_current,
    created_date,
    ipaddress_v6,
    ipaddress_v4,
    country_id_from_ip,
    platform_type_id,
    channel_type_id
  )
    SELECT 
		  clientID,
		  client_registration_type_id,
		  1,
		  NOW(),
		  registrationIpAddress,
		  registrationIpAddressV4,
		  countryIDFromIP,
		  platformTypeID,
		  @channelTypeID
	FROM gaming_client_registration_types 
	WHERE registration_code = registrationType
	ON DUPLICATE KEY UPDATE is_current = 1;

	CALL NotificationEventCreate(1, clientID, NULL, 0);

  IF CommitAndChain THEN
    COMMIT AND CHAIN;
  END IF;

  SELECT @pinStatusCode, @activationResStatusCode, @tokenStatusCode; 

END$$

DELIMITER ;

