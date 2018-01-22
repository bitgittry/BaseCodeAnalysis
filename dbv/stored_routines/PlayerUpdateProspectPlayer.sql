DROP procedure IF EXISTS `PlayerUpdateProspectPlayer`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdateProspectPlayer`(clientID BIGINT, clientStatID BIGINT, varTitle VARCHAR(10), firstName VARCHAR(80), middleName VARCHAR(40), lastName VARCHAR(80), secondLastName VARCHAR(80), varDob DATETIME, varGender CHAR(1), varEmail VARCHAR(255), varMob VARCHAR(45), priTelephone VARCHAR(45), secTelephone VARCHAR(45), languageCode VARCHAR(10), varUsername VARCHAR(45), varPassword VARCHAR(250), varSalt VARCHAR(60), varNickname VARCHAR(60), varPin VARCHAR(30),
  receivePromotional TINYINT(1), contactByEmail TINYINT(1), contactBySMS TINYINT(1), contactByPost TINYINT(1), contactByPhone TINYINT(1), contactByMobile TINYINT(1), contactByThirdParty TINYINT(1), activationCode VARCHAR(80), accountActivated TINYINT(1), isTestPlayer TINYINT(1), registrationIpAddress VARCHAR(40), registrationIpAddressV4 VARCHAR(20), countryIDFromIP BIGINT, affiliateID BIGINT, affiliateCouponID BIGINT, affiliateRegistrationCode VARCHAR(255),
  bonusCouponID BIGINT, originalAffiliateCouponCode VARCHAR(80), originalReferralCode VARCHAR(80), originalBonusCouponCode VARCHAR(80), affiliateCampaignID BIGINT, affiliateSystemID BIGINT, acquisitionType VARCHAR(80),
  varAddress_1 VARCHAR(255), varAddress_2 VARCHAR(255), varCity VARCHAR(80), postCode VARCHAR(80), countryCode VARCHAR(3), currencyCode VARCHAR(3), CommitAndChain TINYINT(1), 
  HashingFunction VARCHAR(80), bypassCheck TINYINT(1), BetFactor DECIMAL(13,5), macAddress VARCHAR(40), platformType VARCHAR(20), stateID BIGINT, riskScore DECIMAL(18,5), vipLevel INT(11), canContact TINYINT(1), 
  uaBrandName VARCHAR(60), uaModelName VARCHAR(60), uaOSName VARCHAR(60), uaOSVersionName VARCHAR(60), uaBrowserName VARCHAR(60), uaBrowserVersionName VARCHAR(60), uaEngineName VARCHAR(60), uaEngineVersionName VARCHAR(60), testPlayerAllowTransfer TINYINT(1), bonusSeeker TINYINT(1), bonusDontWant TINYINT(1), 
  authenticationPIN VARCHAR(250), stateName VARCHAR(128), townName VARCHAR(128), streetType VARCHAR(80), streetName VARCHAR(255), streetNumber VARCHAR(45), houseName VARCHAR(80), houseNumber VARCHAR(45), flatNumber VARCHAR(45), poBoxName VARCHAR(80), suburbName VARCHAR(40), registrationType VARCHAR(5),
  clientRiskCategoryId INT, OUT statusCode INT)
root:BEGIN
  
  DECLARE accountActivationPolicy, downloadClientEnabled, ruleEngineEnabled TINYINT(1) DEFAULT 0;
  DECLARE langaugeID, paymentClientSegmentID, riskClientSegmentID, paymentClientSegemntGroupID, riskClientSegmentGroupID, defaultCurrencyID BIGINT DEFAULT null;
  DECLARE HashTypeID INT DEFAULT 0;
  DECLARE clientSegmentRiskName VARCHAR(40);
  DECLARE operatorID, platformTypeID INT DEFAULT NULL;
  DECLARE exclientIDCheck BIGINT;
  DECLARE countryID BIGINT DEFAULT -1;
  DECLARE uaBrandID, uaModelID, uaOSID, uaOSVersionID, uaBrowserID, uaBrowserVersionID, uaEngineID, uaEngineVersionID BIGINT(20) DEFAULT NULL;

  SELECT gs1.value_bool, IFNULL(gs2.value_string, 'risk_catogaries'), IFNULL(gs3.value_bool, 0), IFNULL(gs5.value_bool, 0)
  INTO accountActivationPolicy, clientSegmentRiskName, downloadClientEnabled, ruleEngineEnabled
  FROM gaming_settings AS gs1
  LEFT JOIN gaming_settings AS gs2 ON gs2.name='PLAYER_CLIENT_SEGMENT_RISK_NAME'
  LEFT JOIN gaming_settings AS gs3 ON gs3.name='DOWNLOAD_CLIENT_AVAILABLE'
  LEFT JOIN gaming_settings AS gs5 ON gs5.name='RULE_ENGINE_ENABLED'
  WHERE gs1.name='REGISTRATION_ACCOUNT_ACTIVATION_POLICY_ENABLED';

  SELECT gaming_operators.operator_id, gaming_operators.currency_id 
  INTO operatorID, defaultCurrencyID
  FROM gaming_operators 
  WHERE gaming_operators.is_main_operator=1 LIMIT 1;
  
  SET statusCode = 0;
 
   UPDATE gaming_clients SET salt = IFNULL(varSalt, salt) WHERE client_id = clientID;  

  IF (authenticationPIN IS NOT NULL AND authenticationPIN <> '') THEN
    INSERT IGNORE INTO gaming_clients_pin_changes (client_id, change_num, hashed_pin, salt)
    VALUES (clientID, 1, authenticationPIN, varSalt);
  END IF;
  
  CALL PlayerUpdatePlayerDetails(clientID, clientStatID, 0, @modifierEntityExtraId, varTitle, firstName, middleName, lastName, secondLastName, varEmail, varDob, varGender, varMob, priTelephone, secTelephone, 
  receivePromotional,receivePromotional,receivePromotional,receivePromotional,receivePromotional,receivePromotional, 
  NULL,NULL,NULL,NULL,NULL,NULL, 
  contactByEmail, contactBySMS, contactByPost, contactByPhone, contactByMobile, contactByThirdParty, 
  varUsername, varPassword, varNickname, languageCode, paymentClientSegmentID, riskClientSegmentID, NULL,
  vipLevel, NULL, NULL, NULL,
  varAddress_1, varAddress_2, varCity, countryCode, postCode, stateID, NULL, registrationType,
  NULL, townName, streetType, streetName, streetNumber, houseName, houseNumber, flatNumber, poBoxName, 
  suburbName, registrationIpAddress, registrationIpAddressV4, countryIDFromIP, platformType, 
  BetFactor, riskScore, clientRiskCategoryId, statusCode);
 
  CALL PlayerUpdateVIPLevel(clientStatID,0);
 
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

  INSERT INTO gaming_client_ua_registrations (client_id, ua_brand_id, ua_model_id, ua_os_id, ua_os_version_id, ua_browser_id, ua_browser_version_id, ua_engine_id, ua_engine_version_id)
  VALUES (clientID, uaBrandID, uaModelID, uaOSID, uaOSVersionID, uaBrowserID, uaBrowserVersionID, uaEngineID, uaEngineVersionID)
  ON DUPLICATE KEY UPDATE 
    ua_brand_id = VALUES(ua_brand_id),
    ua_model_id = VALUES(ua_model_id),
    ua_os_id = VALUES(ua_os_id), 
    ua_os_version_id = VALUES(ua_os_version_id), 
    ua_browser_id = VALUES(ua_browser_id), 
    ua_browser_version_id = VALUES(ua_browser_version_id), 
    ua_engine_id = VALUES(ua_engine_id), 
    ua_engine_version_id = VALUES(ua_engine_version_id);

  IF CommitAndChain THEN
    COMMIT AND CHAIN;
  END IF;

  SELECT @pinStatusCode, @activationResStatusCode, @tokenStatusCode; 

END root$$

DELIMITER ;

