DROP procedure IF EXISTS `PlayerRegisterPlayerForImportation`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerRegisterPlayerForImportation`(varTitle VARCHAR(10), firstName VARCHAR(80), middleName VARCHAR(40), lastName VARCHAR(80), secondLastName VARCHAR(80), varDob DATETIME, varGender CHAR(1), varEmail VARCHAR(255), varMob VARCHAR(45), priTelephone VARCHAR(45), secTelephone VARCHAR(45), languageCode VARCHAR(3), varUsername VARCHAR(45), varPassword VARCHAR(250), varSalt VARCHAR(60), varNickname VARCHAR(60), varPin VARCHAR(30),
  receivePromotional TINYINT(1), activationCode VARCHAR(80), accountActivated TINYINT(1), registrationIpAddress VARCHAR(40), registrationIpAddressV4 VARCHAR(20), countryIDFromIP BIGINT, affiliateID BIGINT, affiliateCouponID BIGINT, affiliateRegistrationCode VARCHAR(255),
  bonusCouponID BIGINT, originalAffiliateCouponCode VARCHAR(80), originalReferralCode VARCHAR(80), originalBonusCouponCode VARCHAR(80), affiliateCampaignID BIGINT, affiliateSystemID BIGINT, acquisitionType VARCHAR(80),
  varAddress_1 VARCHAR(255), varAddress_2 VARCHAR(255), varCity VARCHAR(80), postCode VARCHAR(80), countryCode VARCHAR(3), currencyCode VARCHAR(3), extClientID VARCHAR(80), CommitAndChain TINYINT(1), 
  HashingFunction VARCHAR(80), bypassCheck TINYINT(1), BetFactor DECIMAL(13,5), macAddress VARCHAR(40), downloadClientID VARCHAR(40), platformType VARCHAR(20),varClientID BIGINT, lastLogin DATETIME,
  riskScore DECIMAL(18,5), clientRiskCategoryId INT, varToken VARCHAR(30), OUT statusCode INT)
root:BEGIN

	  

	  DECLARE accountActivationPolicy, downloadClientEnabled, preKYCRestriction TINYINT(1) DEFAULT 0;
	  DECLARE langaugeID, paymentClientSegmentID, riskClientSegmentID, paymentClientSegemntGroupID, riskClientSegmentGroupID, defaultCurrencyID BIGINT DEFAULT null;
	  DECLARE HashTypeID INT DEFAULT 0;
	  DECLARE clientSegmentRiskName VARCHAR(40);
	  DECLARE defaultCountryCode CHAR(2);
	  DECLARE operatorID, platformTypeID INT DEFAULT NULL;
	  DECLARE clientID,clientStatID BIGINT;



	SET statusCode = 0;
	
	SET @pinStatusCode = 0;

	IF ((SELECT count(client_id) FROM gaming_clients where ext_client_id=extClientID) = 0) THEN


	  SELECT IFNULL(gs1.value_bool, 0), IFNULL(gs2.value_string, 'risk_catogaries'), IFNULL(gs3.value_bool, 0), IFNULL(gs4.value_bool, 0)
	  INTO accountActivationPolicy, clientSegmentRiskName, downloadClientEnabled, preKYCRestriction
	  FROM gaming_settings AS gs1
	  LEFT JOIN gaming_settings AS gs2 ON gs2.name='PLAYER_CLIENT_SEGMENT_RISK_NAME'
	  LEFT JOIN gaming_settings AS gs3 ON gs3.name='DOWNLOAD_CLIENT_AVAILABLE'
	  LEFT JOIN gaming_settings AS gs4 ON gs4.name='REGISTRATION_ACCOUNT_PRE_KYC_RESTRICTION_ENABLED'
	  WHERE gs1.name='REGISTRATION_ACCOUNT_ACTIVATION_POLICY_ENABLED';

	  SELECT gaming_operators.operator_id, gaming_operators.currency_id, IFNULL(gaming_operators.country_code,'MT')
	  INTO operatorID, defaultCurrencyID, defaultCountryCode
	  FROM gaming_operators 
	  WHERE gaming_operators.is_main_operator=1 LIMIT 1;
	  
	  SET clientID = 0;

	  SELECT pass_hash_type_id INTO HashTypeID FROM gaming_clients_pass_hash_type WHERE name= HashingFunction;
	  IF (HashTypeID = 0) THEN
		SET statusCode = 1;
		LEAVE root;
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
	  
	  SELECT gaming_client_segment_groups.client_segment_group_id, gaming_client_segments.client_segment_id INTO paymentClientSegemntGroupID, paymentClientSegmentID FROM gaming_client_segment_groups JOIN gaming_client_segments ON gaming_client_segment_groups.is_payment_group=1 AND gaming_client_segment_groups.client_segment_group_id=gaming_client_segments.client_segment_group_id AND gaming_client_segments.is_default=1 LIMIT 1;
	  
	  SELECT gaming_client_segment_groups.client_segment_group_id, gaming_client_segments.client_segment_id INTO riskClientSegmentGroupID, riskClientSegmentID FROM gaming_client_segment_groups JOIN gaming_client_segments ON gaming_client_segment_groups.name=clientSegmentRiskName AND gaming_client_segment_groups.client_segment_group_id=gaming_client_segments.client_segment_group_id AND gaming_client_segments.is_default=1 LIMIT 1;

	  INSERT INTO gaming_clients (title, name, middle_name, surname, dob, gender, email, mob, pri_telephone, sec_telephone, language_id, username, password, salt, nickname, PIN1, 
		  receive_promotional_by_email, receive_promotional_by_sms, receive_promotional_by_post, sign_up_date, client_segment_id, activation_code, 
		  account_activated, registration_ipaddress, registration_ipaddress_v4, country_id_from_ip, affiliate_id, affiliate_coupon_id, affiliate_registration_code, affiliate_campaign_id ,
		  bonus_coupon_id, original_affiliate_coupon_code, original_referral_code, original_bonus_coupon_code, client_acquisition_type_id, affiliate_system_id, is_active, 
		  fraud_similar_name, fraud_similar_details, ext_client_id, referral_client_id, last_updated, pass_hash_type, bet_factor, risk_client_segment_id, mac_address, download_client_id, platform_type_id, is_account_closed,
		  is_play_allowed, risk_score, client_risk_category_id, PIN2) 
	  SELECT varTitle, firstName, middleName, lastName, varDob, varGender, varEmail, varMob, priTelephone, secTelephone, langaugeID, varUsername, varPassword, varSalt, varNickname, varPin, 
		  receivePromotional, receivePromotional, receivePromotional, NOW(), gaming_client_segments.client_segment_id, activationCode, 
		  accountActivated, registrationIpAddress, registrationIpAddressV4, countryIDFromIP, affiliateID, affiliateCouponID, affiliateRegistrationCode, affiliateCampaignID,
		  bonusCouponID, originalAffiliateCouponCode, originalReferralCode, originalBonusCouponCode, gaming_client_acquisition_types.client_acquisition_type_id, affiliateSystemID, 1,
		  UPPER(REPLACE(CONCAT_WS(';',IFNULL(firstName,''),IFNULL(middleName,''),IFNULL(lastName,'')),' ','')),UPPER(REPLACE(IFNULL(varEmail,''),' ','')), extClientID, referral_client.client_id, NOW(), HashTypeID, 
		  BetFactor, riskClientSegmentID, macAddress, downloadClientID, platformTypeID, 0, 1, riskScore, clientRiskCategoryId, varToken
	  FROM gaming_client_segments
	  LEFT JOIN gaming_client_acquisition_types ON (acquisitionType IS NULL AND gaming_client_acquisition_types.is_default=1) OR gaming_client_acquisition_types.name=acquisitionType
	  LEFT JOIN gaming_clients AS referral_client ON referral_code=originalReferralCode
	  WHERE gaming_client_segments.client_segment_id=paymentClientSegmentID
	  LIMIT 1; 

	 SET clientID=LAST_INSERT_ID();
	 SET varClientID=clientID;

	
	  



	  INSERT INTO clients_locations (client_id, address_1, address_2, city, country_id, postcode, is_active, fraud_similar_address) 
	  SELECT clientID, varAddress_1, varAddress_2, varCity, IFNULL(gaming_countries.country_id, def.country_id), postCode, 1, 
		  UPPER(REPLACE(CONCAT_WS(';',varAddress_1,IFNULL(varAddress_2,''),varCity,postCode,countryCode),' ',''))
	  FROM gaming_clients 
	  LEFT JOIN gaming_countries ON gaming_countries.country_code=countryCode
	  LEFT JOIN gaming_countries def ON def.country_code=defaultCountryCode
	  WHERE gaming_clients.client_id=clientID; 

	  
	  INSERT INTO gaming_client_stats (client_id, currency_id, active_date, is_active,client_stat_id) 
	  SELECT clientID, currency_id, NOW(), 1, clientID 
	  FROM gaming_currency WHERE currency_code=currencyCode; 
	  SET clientStatID=varClientID;    

		
	  IF (ROW_COUNT()=0) THEN
		INSERT INTO gaming_client_stats (client_id, currency_id, active_date, is_active,client_stat_id) 
		SELECT clientID, defaultCurrencyID, NOW(), 1,clientID; 
		SET clientStatID=varClientID;
	  END IF;

	  INSERT INTO gaming_client_stats_no_lock(client_stat_id, client_id, currency_id, is_active) 
	  SELECT clientStatID, clientID, currency_id, 1 
	  FROM gaming_client_stats 
	  WHERE client_stat_id=clientStatID; 

	  INSERT INTO gaming_client_payment_info (client_id, payment_method_id)
	  SELECT gaming_clients.client_id, gaming_payment_method.payment_method_id
	  FROM gaming_payment_method 
	  JOIN gaming_clients ON gaming_clients.client_id=clientID AND gaming_clients.is_account_closed=0
	  WHERE gaming_payment_method.is_payment_gateway_method=1  
	  ON DUPLICATE KEY UPDATE gaming_client_payment_info.session_id=gaming_client_payment_info.session_id;

	  INSERT INTO gaming_client_wager_stats (client_stat_id, client_wager_type_id)
	  SELECT clientStatID, client_wager_type_id
	  FROM gaming_client_wager_types
	  WHERE is_active=1;
	 
	  INSERT INTO gaming_clients_login_attempts_totals(client_id,last_success) 
	  VALUES (clientID,IF(lastLogin='',NULL,lastLogin));
	  
	  INSERT INTO gaming_event_rows (event_table_id, elem_id, rule_engine_state) SELECT 5, clientID, 4;
	  
	  IF CommitAndChain THEN
		COMMIT AND CHAIN;
	  END IF;

	  
		
	  SELECT clientID AS client_id, clientStatID AS client_stat_id;
	  
	  CALL PlayerUpdateUniquePin(clientID, bypassCheck, @pinStatusCode);
	  
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
	  
	  

	  IF CommitAndChain THEN
		COMMIT AND CHAIN;
	  END IF;
		SELECT @pinStatusCode, @activationResStatusCode; 
	
	ELSE 
		SET statusCode = -1;
		 SELECT client_id INTO varClientID FROM gaming_clients where ext_client_id=extClientID;
		SELECT varClientID AS client_id, varClientID AS client_stat_id;
		SELECT 0 AS player_restriction_id;
		SELECT NULL;
		SELECT @pinStatusCode, @activationResStatusCode; 
	  END IF; 

	
END$$

DELIMITER ;

