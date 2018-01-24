DROP procedure IF EXISTS `PlayerUpdatePlayerDetails`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdatePlayerDetails`(clientID BIGINT, clientStatID BIGINT, sessionID BIGINT, userID BIGINT, 
  varTitle VARCHAR(10), firstName VARCHAR(80), middleName VARCHAR(40), lastName VARCHAR(80), secondLastName VARCHAR(80), varEmail VARCHAR(255), varDob DATETIME, varGender CHAR(1), varMob VARCHAR(45), priTelephone VARCHAR(45), secTelephone VARCHAR(45), 
  promoByEmail TINYINT(1), promoBySMS TINYINT(1), promoByPost TINYINT(1), promoByPhone TINYINT(1), promoByMobile TINYINT(1), promoByThirdParty TINYINT(1), 
  emailVerificationTypeID TINYINT(4), smsVerificationTypeID TINYINT(4), postVerificationTypeID TINYINT(4), phoneVerificationTypeID TINYINT(4), thirdPartyVerificationTypeID TINYINT(4), preferredPromotionTypeID INT(11),
  contactByEmail TINYINT(1), contactBySMS TINYINT(1), contactByPost TINYINT(1), contactByPhone TINYINT(1), contactByMobile TINYINT(1), contactByThirdParty TINYINT(1),
  varUsername VARCHAR(60), varPassword VARCHAR(250), varNickname VARCHAR(60), languageCode VARCHAR(10), clientSegmentID BIGINT, riskClientSegmentID BIGINT, allowLoginBannedCountryFromIP TINYINT(1), 
  vipLevel INT(11), rndScore DECIMAL(22,9), ageVerificationTypeName VARCHAR(64), newsFeedAllow TINYINT(1),
  varAddress_1 VARCHAR(255), varAddress_2 VARCHAR(255), varCity VARCHAR(80), countryCode VARCHAR(3), postCode VARCHAR(80), stateID BIGINT, vipDowngradeDisabled TINYINT(1), registrationType VARCHAR(5),
  stateName VARCHAR(128), townName VARCHAR(128), streetType VARCHAR(80), streetName VARCHAR(255), streetNumber VARCHAR(45), houseName VARCHAR(80), houseNumber VARCHAR(45), flatNumber VARCHAR(45), 
  poBoxName VARCHAR(80), suburbName VARCHAR(40), registrationIpAddress VARCHAR(40), registrationIpAddressV4 VARCHAR(20), countryIDFromIP BIGINT, platformType VARCHAR(20), 
  isPlayer TINYINT(1), BetFactor DECIMAL(22,9), riskScore DECIMAL(22,9), clientRiskCategoryId INT, retailerID VARCHAR(20), employeeID VARCHAR(20), OUT statusCode INT)
root:BEGIN

  
  DECLARE clientStatIDCheck, currentClientSegmentID, currentRiskClientSegmentID BIGINT DEFAULT -1; 
  DECLARE curVipLevelID, newVipLevelID, curCityID, curPostcodeID, curStreetTypeID, curStreetID, curSuburbID, cityID, townID, 
	postcodeID, streetTypeID, streetID, suburbID BIGINT DEFAULT NULL;
  DECLARE fraudEnabled, fraudPlayerDetailsEnabled, changedSegment, fraudChange, changeDetected, updateSignUpDate TINYINT(1) DEFAULT 0;
  DECLARE curPromoByEmail, curPromoBySMS, curPromoByPost, curPromoByPhone, curPromoByMobile, curPromoByThirdParty TINYINT(1) DEFAULT 0;
  DECLARE curEmailVerificationTypeID, curSMSVerificationTypeID, curPostVerificationTypeID, curPhoneVerificationTypeID, curThirdPartyVerificationTypeID TINYINT(4) DEFAULT 1;
  DECLARE curPreferredPromotionTypeID INT(11) DEFAULT 1;
  DECLARE curContactByEmail, curContactBySMS, curContactByPost, curContactByPhone, curContactByMobile, curContactByThirdParty TINYINT(1) DEFAULT 0;
  DECLARE HashTypeID INT;
  DECLARE countryID, counterID BIGINT DEFAULT -1;
  DECLARE curVIPLevel INT(11);
  DECLARE curRndScore DECIMAL(22,9);
  DECLARE fraudSimialarName, fraudSimilarDetails, fraudSimilarAddress VARCHAR(1024);
  DECLARE curTitle VARCHAR(10);
  DECLARE curFirstName, curLastName, curSecondLastName VARCHAR(80);
  DECLARE curMiddleName, curSuburbName VARCHAR(40);
  DECLARE curEmail, curStreetName VARCHAR(255);
  DECLARE curDob, curTimeStamp DATETIME;
  DECLARE curGender CHAR(1);
  DECLARE curMob, curPriTelephone, curSecTelephone, curHouseNumber, curFlatNumber VARCHAR(45);
  DECLARE curUsername VARCHAR(60);
  DECLARE curNickname VARCHAR(60);
  DECLARE curLanguageCode VARCHAR(10);
  DECLARE curAddress1, curAddress2, curPassword VARCHAR(255);
  DECLARE curCity VARCHAR(80);
  DECLARE curCountryCode VARCHAR(3);
  DECLARE curPostCode, curHouseName, curStreetType, curPoBoxName VARCHAR(80);
  DECLARE curStateName VARCHAR(128);
  DECLARE curTownName VARCHAR(128);
  DECLARE curRegistrationType VARCHAR(4);
  DECLARE changeNo INT DEFAULT NULL;
  DECLARE auditLogGroupId BIGINT DEFAULT -1;
  DECLARE downloadClientEnabled TINYINT(1) DEFAULT 0;
  DECLARE platformTypeID INT DEFAULT NULL;
  DECLARE curStreetNumber VARCHAR(45);
  DECLARE curRetailerID, curEmployeeID VARCHAR(20);

  SET statusCode = 0;
  
  SELECT gs1.value_bool, gs2.value_bool, IFNULL(gs3.value_bool, 0)
  INTO fraudEnabled, fraudPlayerDetailsEnabled, downloadClientEnabled
  FROM gaming_settings AS gs1
  JOIN gaming_settings AS gs2 ON gs2.name='FRAUD_ON_PLAYER_DETAILS_ENABLED'
  LEFT JOIN gaming_settings AS gs3 ON gs3.name='DOWNLOAD_CLIENT_AVAILABLE'
  WHERE gs1.name='FRAUD_ENABLED';

  
  
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  SELECT client_segment_id, risk_client_segment_id INTO currentClientSegmentID, currentRiskClientSegmentID FROM gaming_clients WHERE client_id=clientID;
  SELECT pass_hash_type_id INTO HashTypeID FROM gaming_clients_pass_hash_type WHERE is_default=1;
  
  SELECT vip_level, rnd_score, vip_level_id, num_details_changes+1
  INTO curVIPLevel, curRndScore, curVipLevelID, changeNo
  FROM gaming_clients 
  WHERE client_id=clientID;

  IF (vipLevel IS NOT NULL) THEN
	SELECT vip_level_id INTO newVipLevelID FROM gaming_vip_levels WHERE vipLevel BETWEEN min_vip_level AND IFNULL(max_vip_level, 999999999) ORDER BY min_vip_level LIMIT 1;
  END IF;


  

  SET userID=IFNULL(userID, 0);	  

	
    SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, IF(isPlayer, 'Player', 'User'), NULL, NULL, clientID);

    
	  IF (vipLevel IS NOT NULL) THEN
		IF (curVIPLevel!=vipLevel) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'vip_level', vipLevel, curVIPLevel, changeNo);
			CALL AuditLogAttributeChange('VIP Level', clientID, auditLogGroupId, vipLevel, curVIPLevel, NOW());
		END IF;
	  END IF;
  
	  IF (rndScore IS NOT NULL) THEN
		IF (curRndScore!=rndScore) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'rnd_score', rndScore, curRndScore, changeNo);
			CALL AuditLogAttributeChange('Rnd Score', clientID, auditLogGroupId, rndScore, curRndScore, NOW());
		END IF;
	  END IF;

  
	  SELECT gaming_clients.title, gaming_clients.name, gaming_clients.middle_name, gaming_clients.surname, gaming_clients.sec_surname, 
			 gender, gaming_clients.email, gaming_clients.dob, gaming_clients.mob, gaming_clients.pri_telephone, gaming_clients.sec_telephone, 
			 username, nickname, gaming_languages.language_code, password, retailer_id, employee_id
	  INTO curTitle, curFirstName, curMiddleName, curLastName, curSecondLastName, curGender, curEmail, 
		   curDob, curMob, curPriTelephone, curSecTelephone, curUsername, curNickname, curLanguageCode, curPassword, curRetailerID, curEmployeeID
	  FROM gaming_clients  
	  LEFT JOIN gaming_languages ON gaming_clients.language_id = gaming_languages.language_id 
	  WHERE gaming_clients.client_id=clientID;

	  IF (varTitle IS NOT NULL) THEN
		IF (!(IFNULL(curTitle,'') <=>  varTitle)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Title', varTitle, curTitle, changeNo);
			CALL AuditLogAttributeChange('Title', clientID, auditLogGroupId, varTitle, curTitle, NOW());
		END IF;
	  END IF;
  
      IF (firstName IS NOT NULL) THEN
		IF (!(IFNULL(curFirstName,'') <=>  firstName)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'First Name', firstName, curFirstName, changeNo);
			CALL AuditLogAttributeChange('First Name', clientID, auditLogGroupId, firstName, curFirstName, NOW());
		END IF;
	  END IF;
  
	   IF (middleName IS NOT NULL) THEN
    IF (!(IFNULL(curMiddleName,'') <=>  middleName)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Middle Name', middleName, curMiddleName, changeNo);
			CALL AuditLogAttributeChange('Middle Name', clientID, auditLogGroupId, middleName, curMiddleName, NOW());
		END IF;
	  END IF;
  
	  IF (lastName IS NOT NULL) THEN
		IF (!(IFNULL(curLastName,'') <=>  lastName)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Last Name', lastName, curLastName, changeNo);
			CALL AuditLogAttributeChange('Last Name', clientID, auditLogGroupId, lastName, curLastName, NOW());
		END IF;
	  END IF;
  
	  IF (secondLastName IS NOT NULL) THEN
		IF (!(IFNULL(curSecondLastName,'') <=>  secondLastName)) THEN
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Second Last Name', secondLastName, curSecondLastName, changeNo);
			CALL AuditLogAttributeChange('Second Last Name', clientID, auditLogGroupId, secondLastName, curSecondLastName, NOW());
		END IF;
	  END IF;
  
	  IF (varGender IS NOT NULL) THEN
		IF (!(IFNULL(curGender,'') <=>  varGender)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Gender', varGender, curGender, changeNo);
			CALL AuditLogAttributeChange('Gender', clientID, auditLogGroupId, varGender, curGender, NOW());
		END IF;
	  END IF;
  
	  IF (varEmail IS NOT NULL) THEN
		IF (!(IFNULL(curEmail,'') <=>  varEmail)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Email', varEmail, curEmail, changeNo);
			CALL AuditLogAttributeChange('Email', clientID, auditLogGroupId, varEmail, curEmail, NOW());
		END IF;
	  END IF;

	  IF (varDob IS NOT NULL) THEN
		IF (!(curDob <=> varDob)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Date of Birth', varDob, curDob, changeNo);
			CALL AuditLogAttributeChange('Date of Birth', clientID, auditLogGroupId, varDob, curDob, NOW());
		END IF;
	  END IF;

	  IF (varMob IS NOT NULL) THEN
		IF (!(IFNULL(curMob,'') <=>  varMob)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Mobile', varMob, curMob, changeNo);
			CALL AuditLogAttributeChange('Mobile', clientID, auditLogGroupId, varMob, curMob, NOW());
		END IF;
	  END IF;

	  IF (priTelephone IS NOT NULL) THEN
		IF (!(IFNULL(curPriTelephone,'') <=>  priTelephone)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Primary Telephone', priTelephone, curPriTelephone, changeNo);
			CALL AuditLogAttributeChange('Primary Telephone', clientID, auditLogGroupId, priTelephone, curPriTelephone, NOW());
		END IF;
	  END IF;

      IF (secTelephone IS NOT NULL) THEN
		IF (!(IFNULL(curSecTelephone,'') <=>  secTelephone)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Secondary Telephone', secTelephone, curSecTelephone, changeNo);
			CALL AuditLogAttributeChange('Secondary Telephone', clientID, auditLogGroupId, secTelephone, curSecTelephone, NOW());
		END IF;
	  END IF;

	  IF (varUsername IS NOT NULL) THEN
		IF (!(IFNULL(curUsername,'') <=>  varUsername)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Username', varUsername, curUsername, changeNo);
			CALL AuditLogAttributeChange('Username', clientID, auditLogGroupId, varUsername, curUsername, NOW());
		END IF;
	  END IF;

	  IF (varNickname IS NOT NULL) THEN
		IF (!(IFNULL(curNickname,'') <=>  varNickname)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Nickname', varNickname, curNickname, changeNo);
			CALL AuditLogAttributeChange('Nickname', clientID, auditLogGroupId, varNickname, curNickname, NOW());
		END IF;
	  END IF;

      IF (languageCode IS NOT NULL) THEN
		IF (!(IFNULL(curLanguageCode,'') <=>  languageCode) and languageCode != '') THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Language', languageCode, curLanguageCode, changeNo);
			CALL AuditLogAttributeChange('Language', clientID, auditLogGroupId, languageCode, curLanguageCode, NOW());
		END IF;
	  END IF;

	  SELECT address_1, address_2, city, clients_locations.postcode, gaming_countries.country_code,clients_locations.country_id, city_id, postcode_id, 
		street_type_desc, street_type_id, street_name, street_id, house_name, house_number, flat_number, po_box_name,
  state_name, town_name, suburb, suburb_id, street_number
	  INTO curAddress1, curAddress2, curCity, curPostCode, curCountryCode, countryID, curCityID, curPostcodeID, 
		curStreetType, streetTypeID, curStreetName, curStreetID, curHouseName, curHouseNumber, curFlatNumber, curPoBoxName,
  curStateName, curTownName, curSuburbName, curSuburbID, curStreetNumber
	  FROM clients_locations 
	  LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
	  WHERE clients_locations.client_id=clientID AND clients_locations.is_primary=1;

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

	  IF (varAddress_1 IS NOT NULL) THEN
		IF (!(IFNULL(curAddress1,'') <=>  varAddress_1)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Address', varAddress_1, curAddress1, changeNo);
			CALL AuditLogAttributeChange('Address', clientID, auditLogGroupId, varAddress_1, curAddress1, NOW());
		END IF;
	  END IF;

      IF (varAddress_2 IS NOT NULL) THEN
		IF (!(IFNULL(curAddress2,'') <=>  varAddress_2)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Address 2', varAddress_2, curAddress2, changeNo);
			CALL AuditLogAttributeChange('Address 2', clientID, auditLogGroupId, varAddress_2, curAddress2, NOW());
		END IF;
	  END IF;

	  IF (varCity IS NOT NULL) THEN
		IF (!(IFNULL(curCity,'') <=>  varCity)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'City', varCity, curCity, changeNo);
			CALL AuditLogAttributeChange('City', clientID, auditLogGroupId, varCity, curCity, NOW());
		END IF;
	  END IF;

      IF (postCode IS NOT NULL) THEN
		IF (!(IFNULL(curPostCode,'') <=>  postCode)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Post Code', postCode, curPostCode, changeNo);
			CALL AuditLogAttributeChange('Post Code', clientID, auditLogGroupId, postCode, curPostCode, NOW());
		END IF;
	  END IF;	

	  IF (countryCode IS NOT NULL) THEN
		IF (!(IFNULL(curCountryCode,'') <=>  countryCode)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Country', countryCode, curCountryCode, changeNo);
			CALL AuditLogAttributeChange('Country', clientID, auditLogGroupId, countryCode, curCountryCode, NOW());
		END IF;
	  END IF;

	  IF (streetType IS NOT NULL) THEN
		IF (!(IFNULL(curStreetType,'') <=>  streetType)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'StreetType', streetType, curStreetType, changeNo);
			CALL AuditLogAttributeChange('Street Type', clientID, auditLogGroupId, streetType, curStreetType, NOW());
		END IF;
	  END IF;

	  IF (streetName IS NOT NULL) THEN
		IF (!(IFNULL(curStreetName,'') <=>  streetName)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'StreetName', streetName, curStreetName, changeNo);
			CALL AuditLogAttributeChange('Street Name', clientID, auditLogGroupId, streetName, curStreetName, NOW());
		END IF;
	  END IF;

  IF (streetNumber IS NOT NULL) THEN
		IF (!(IFNULL(curStreetNumber,'') <=>  streetNumber)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'StreetNumber', streetNumber, curStreetNumber, changeNo);
			CALL AuditLogAttributeChange('Street Number', clientID, auditLogGroupId, streetNumber, curStreetNumber, NOW());
		END IF;
  END IF;

	  IF (houseName IS NOT NULL) THEN
		IF (!(IFNULL(curHouseName,'') <=>  houseName)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'HouseName', houseName, curHouseName, changeNo);
			CALL AuditLogAttributeChange('House Name', clientID, auditLogGroupId, houseName, curHouseName, NOW());
		END IF;
	  END IF;

	  IF (houseNumber IS NOT NULL) THEN
		IF (!(IFNULL(curHouseNumber,'') <=>  houseNumber)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'HouseNumber', houseNumber, curHouseNumber, changeNo);
			CALL AuditLogAttributeChange('House Number', clientID, auditLogGroupId, houseNumber, curHouseNumber, NOW());
		END IF;
	  END IF;

	  IF (flatNumber IS NOT NULL) THEN
		IF (!(IFNULL(curFlatNumber,'') <=>  flatNumber)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'FlatNumber', flatNumber, curFlatNumber, changeNo);
			CALL AuditLogAttributeChange('Flat Number', clientID, auditLogGroupId, flatNumber, curFlatNumber, NOW());
		END IF;
	  END IF;

	  IF (poBoxName IS NOT NULL) THEN
		IF (!(IFNULL(curPoBoxName,'') <=>  poBoxName)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'POBoxName', poBoxName, curPoBoxName, changeNo);
			CALL AuditLogAttributeChange('PO Box Name', clientID, auditLogGroupId, poBoxName, curPoBoxName, NOW());
		END IF;
	  END IF;

	  IF (stateName IS NOT NULL) THEN
		IF (!(IFNULL(curStateName,'') <=>  stateName)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'State', stateName, curStateName, changeNo);
			CALL AuditLogAttributeChange('State', clientID, auditLogGroupId, stateName, curStateName, NOW());
		END IF;
	  END IF;      

	  IF (townName IS NOT NULL) THEN
		IF (!(IFNULL(curTownName,'') <=>  townName)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'TownName', townName, curTownName, changeNo);
			CALL AuditLogAttributeChange('TownName', clientID, auditLogGroupId, townName, curTownName, NOW());
		END IF;
	  END IF;

   IF (suburbName IS NOT NULL) THEN
		IF (!(IFNULL(curSuburbName,'') <=>  suburbName)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Suburb', suburbName, curSuburbName, changeNo);
			CALL AuditLogAttributeChange('Suburb', clientID, auditLogGroupId, suburbName, curSuburbName, NOW());
		END IF;
	  END IF;

			IF (retailerID IS NOT NULL) THEN
			IF (!(IFNULL(curRetailerID,'') <=>  retailerID)) THEN
				SET changeDetected = 1;
				INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
				VALUES (clientID, userID, now(), 'RetailerID', retailerID, curRetailerID, changeNo);
				CALL AuditLogAttributeChange('RetailerID', clientID, auditLogGroupId, retailerID, curRetailerID, NOW());
			END IF;
		  END IF;

		IF (employeeID IS NOT NULL) THEN
			IF (!(IFNULL(curEmployeeID,'') <=>  employeeID)) THEN
				SET changeDetected = 1;
				INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
				VALUES (clientID, userID, now(), 'EmployeeID', employeeID, curEmployeeID, changeNo);
				CALL AuditLogAttributeChange('EmployeeID', clientID, auditLogGroupId, employeeID, curEmployeeID, NOW());
			END IF;
		  END IF;
	
	  SELECT 
		receive_promotional_by_email, receive_promotional_by_sms, receive_promotional_by_post, receive_promotional_by_phone, receive_promotional_by_mobile, receive_promotional_by_third_party,
		contact_by_email, contact_by_sms, contact_by_post, contact_by_phone, contact_by_mobile, contact_by_third_party, 
		email_verification_type_id, sms_verification_type_id, post_verification_type_id, phone_verification_type_id, third_party_verification_type_id,
		preferred_promotion_type_id
	  INTO 
		curPromoByEmail, curPromoBySMS, curPromoByPost, curPromoByPhone, curPromoByMobile, curPromoByThirdParty,
		curContactByEmail, curContactBySMS, curContactByPost, curContactByPhone, curContactByMobile, curContactByThirdParty,
		curEmailVerificationTypeID, curSMSVerificationTypeID, curPostVerificationTypeID, curPhoneVerificationTypeID, curThirdPartyVerificationTypeID,
		curPreferredPromotionTypeID
	  FROM gaming_clients WHERE client_id=clientID;

  
	  IF (promoByEmail IS NOT NULL) THEN
		IF (!(IFNULL(curPromoByEmail,'') <=>  promoByEmail)) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before)
			VALUES (clientID, userID, now(), 'Promo By Email', promoByEmail, curPromoByEmail);
		END IF;
	  END IF;

   
	  CALL PlayerUpdateContactFlags(userID, sessionID, clientID, contactByEmail, contactBySMS, contactByPost, contactByPhone, contactByMobile, contactByThirdParty, 0, changeDetected);
	
  
    CALL PlayerUpdatePromotionalFlags(userID, sessionID, clientID, promoByEmail, promoBySMS, promoByPost, promoByPhone, promoByMobile, promoByThirdParty, emailVerificationTypeID, 
		   smsVerificationTypeID, postVerificationTypeID, phoneVerificationTypeID, thirdPartyVerificationTypeID, preferredPromotionTypeID, newsFeedAllow, 0, changeDetected);

  IF (fraudEnabled AND fraudPlayerDetailsEnabled) THEN
	SELECT fraud_similar_name, fraud_similar_details, fraud_similar_address INTO fraudSimialarName, fraudSimilarDetails, fraudSimilarAddress 
    FROM gaming_clients JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary=1 
    WHERE gaming_clients.client_id=clientID;
  END IF;

  
  UPDATE clients_locations SET address_1=IFNULL(varAddress_1, address_1), address_2=IFNULL(varAddress_2, address_2), clients_locations.postcode=IFNULL(postCode, clients_locations.postcode), 
    city=IFNULL(varCity, city), state_id = IFNULL(stateID,state_id), country_id=IF(countryCode IS NULL,country_id,(SELECT country_id FROM gaming_countries WHERE country_code=countryCode)), 
    session_id=sessionID, 
	city_id=IFNULL(cityID,city_id), postcode_id=IFNULL(postcodeID,postcode_id), street_type_desc=IFNULL(streetType,street_type_desc), street_type_id=IFNULL(streetTypeID,street_type_id), 
	street_name=IFNULL(streetName,street_name), street_id=IFNULL(streetID,street_id), house_name=IFNULL(houseName,house_name), house_number=IFNULL(houseNumber,house_number), 
	flat_number=IFNULL(flatNumber,flat_number), po_box_name=IFNULL(poBoxName,po_box_name), state_name=IFNULL(stateName,state_name), 
    suburb=IFNULL(suburbName,suburb), suburb_id=IFNULL(suburbID,suburb_id), town_name=IFNULL(townName,town_name), 
    town_id=IFNULL(townID,town_id), street_number=IFNULL(streetNumber, street_number)
  WHERE client_id=clientID; 
  
  -- Check tax cycles when changing player country (Since tax rules are set per country)
  IF (countryCode IS NOT NULL) THEN
	IF (!(IFNULL(curCountryCode,'') <=>  countryCode)) THEN
	  SET curTimeStamp = NOW();

	  INSERT INTO gaming_transaction_counter (date_created) VALUES (NOW());
	  SET counterID = LAST_INSERT_ID();

	  INSERT INTO gaming_transaction_counter_amounts (transaction_counter_id,client_stat_id,amount)
	  SELECT counterID, gaming_tax_cycles.client_stat_id, LEAST(current_real_balance,deferred_tax)* -1 AS fee 
	  FROM gaming_clients
	  JOIN gaming_client_stats ON gaming_client_stats.client_id = gaming_clients.client_id
	  JOIN gaming_tax_cycles ON gaming_tax_cycles.client_stat_id = gaming_client_stats.client_stat_id AND gaming_tax_cycles.is_active = 1	 
	  WHERE gaming_tax_cycles.client_stat_id = clientStatID;  
      
      SET @TransactionAmountId = LAST_INSERT_ID();
		
	  IF(@TransactionAmountId <> -1 AND @TransactionAmountId IS NOT NULL) THEN
		UPDATE gaming_client_stats
		JOIN gaming_transaction_counter_amounts ON gaming_client_stats.client_stat_id = gaming_transaction_counter_amounts.client_stat_id AND transaction_counter_id = counterID
		SET current_real_balance = current_real_balance + gaming_transaction_counter_amounts.amount,
		  total_tax_paid = total_tax_paid - gaming_transaction_counter_amounts.amount
		WHERE gaming_transaction_counter_amounts.amount < 0;

		UPDATE gaming_client_stats
		JOIN gaming_transaction_counter_amounts ON gaming_client_stats.client_stat_id = gaming_transaction_counter_amounts.client_stat_id AND transaction_counter_id = counterID
		SET deferred_tax = 0;
		  
		INSERT INTO gaming_transactions
		(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, reason, pending_bet_real, pending_bet_bonus,transaction_counter_id,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
		SELECT gaming_payment_transaction_type.payment_transaction_type_id, gaming_transaction_counter_amounts.amount, ROUND(gaming_transaction_counter_amounts.amount/exchange_rate,5), gaming_client_stats.currency_id, exchange_rate, gaming_transaction_counter_amounts.amount, 0, 0, 0, CurTimeStamp, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, 0, 0, 'Deferred Tax', pending_bets_real, pending_bets_bonus,CounterID,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
		FROM gaming_transaction_counter_amounts
		JOIN gaming_client_stats ON gaming_transaction_counter_amounts.client_stat_id = gaming_client_stats.client_stat_id
		JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = 'DeferredTaxRuleChange '
		JOIN gaming_operators ON is_main_operator
		JOIN gaming_operator_currency ON gaming_operator_currency.operator_id = gaming_operators.operator_id AND gaming_operator_currency.currency_id = gaming_client_stats.currency_id
		WHERE transaction_counter_id = counterID AND gaming_transaction_counter_amounts.amount < 0;

		SET @BeforeInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays); 

		INSERT INTO gaming_game_plays (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,sign_mult,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
		SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, gaming_transactions.client_id, gaming_transactions.client_stat_id, gaming_transactions.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,1,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
		FROM gaming_transactions
		JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.payment_transaction_type_id = gaming_transactions.payment_transaction_type_id AND gaming_payment_transaction_type.name = 'DeferredTaxRuleChange' AND gaming_transactions.transaction_counter_id = CounterID
		JOIN gaming_transaction_counter_amounts ON gaming_transactions.client_stat_id =gaming_transaction_counter_amounts.client_stat_id AND gaming_transaction_counter_amounts.transaction_counter_id = counterID
		WHERE gaming_transaction_counter_amounts.amount < 0;

		SET @AfterInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays);

		INSERT INTO 	gaming_game_play_ring_fenced 
			(game_play_id,ring_fenced_sb_after,ring_fenced_casino_after,ring_fenced_poker_after,ring_fenced_pb_after)
		SELECT 		game_play_id, current_ring_fenced_sb, current_ring_fenced_casino, current_ring_fenced_poker, 0
		FROM			gaming_client_stats
			JOIN gaming_game_plays ON gaming_client_stats.client_stat_id = gaming_game_plays.client_stat_id
			  AND game_play_id BETWEEN @BeforeInsert AND @AfterInsert
		ON DUPLICATE KEY UPDATE   
		`ring_fenced_sb_after`=values(`ring_fenced_sb_after`), 
		`ring_fenced_casino_after`=values(`ring_fenced_casino_after`),  
		`ring_fenced_poker_after`=values(`ring_fenced_poker_after`), 
		`ring_fenced_pb_after`=values(`ring_fenced_pb_after`);

		UPDATE gaming_tax_cycles
		JOIN gaming_transaction_counter_amounts ON gaming_transaction_counter_amounts.transaction_counter_id = counterID AND gaming_tax_cycles.client_stat_id = gaming_transaction_counter_amounts.client_stat_id
		SET cycle_end_date = NOW(), is_active = 0, deferred_tax_amount = gaming_transaction_counter_amounts.amount, cycle_closed_on = 'Other'
		WHERE gaming_tax_cycles.is_active = 1;    
      END IF;
        
	  /*#Insert new tax cycles
	  INSERT INTO gaming_tax_cycles (country_tax_id, client_stat_id, deferred_tax_amount, cycle_start_date, cycle_end_date, is_active, cycle_client_counter)
	  SELECT gaming_country_tax.country_tax_id, clientStatID, 0, NOW(), '3000-01-01 00:00:00', 1, (SELECT COUNT(tax_cycle_id)+1 FROM gaming_tax_cycles WHERE client_stat_id = clientStatID)
	  FROM gaming_country_tax
	  WHERE gaming_country_tax.country_id = (SELECT country_id FROM gaming_countries WHERE country_code=countryCode)
	    AND gaming_country_tax.is_current = 1
	    AND gaming_country_tax.is_active = 1
	    AND gaming_country_tax.applied_on = 'Deferred'
	    AND NOW() BETWEEN gaming_country_tax.date_start AND gaming_country_tax.date_end;*/
        
	  DELETE FROM gaming_transaction_counter_amounts WHERE transaction_counter_id = counterID;        
    END IF;
  END IF;
  
  IF (downloadClientEnabled=0) THEN
    SET platformTypeID = 0;
  ELSE
    SELECT platform_type_id INTO platformTypeID FROM gaming_platform_types WHERE platform_type=platformType;
    
	IF (platformTypeID IS NULL) THEN
      SELECT platform_type_id INTO platformTypeID FROM gaming_clients WHERE client_id = clientID;
    END IF;
	
    IF (platformTypeID IS NULL) THEN
      SELECT platform_type_id INTO platformTypeID FROM gaming_platform_types WHERE is_default=1 LIMIT 1;
    END IF;
  END IF;
  
  SELECT registration_code INTO curRegistrationType FROM gaming_client_registrations as gcr 
	JOIN gaming_client_registration_types as gcrt ON gcr.client_registration_type_id = gcrt.client_registration_type_id 
	WHERE is_current = 1 AND client_id = clientID;

	IF ((NULLIF(registrationType, '') IS NOT NULL) AND curRegistrationType != registrationType) THEN
	 
		UPDATE gaming_client_registrations SET is_current = 0 WHERE is_current = 1 AND client_id = clientID;
		
		SELECT IFNULL(registrationIpAddress, registration_ipaddress), IFNULL(registrationIpAddressV4, registration_ipaddress_v4), IFNULL(countryIDFromIP, country_id_from_ip), IFNULL(platformTypeID, platform_type_id) 
		INTO @ipAddressV6, @ipAddressV4, @countryIDFromIP, @platformTypeID 
		FROM gaming_clients
		WHERE client_id = clientID;

		SELECT channel_type_id INTO @channelTypeID FROM gaming_channels_platform_types WHERE platform_type_id = @platformTypeID;

		INSERT INTO gaming_client_registrations (client_id, client_registration_type_id, is_current, created_date, ipaddress_v6, ipaddress_v4, country_id_from_ip, platform_type_id, channel_type_id)
		SELECT clientID, client_registration_type_id, 1, NOW(), @ipAddressV6, @ipAddressV4, @countryIDFromIP, @platformTypeID, @channelTypeID 
		FROM gaming_client_registration_types 
		WHERE registration_code = registrationType
		ON DUPLICATE KEY UPDATE is_current = 1;    
		
		SET updateSignUpDate = 1;

	END IF;

  UPDATE gaming_clients 
  SET title=IFNULL(varTitle, title), name=IFNULL(firstName, name), middle_name=IFNULL(middleName, middle_name), surname=IFNULL(lastName, surname),  sec_surname=IFNULL(secondLastName, sec_surname), email=IFNULL(varEmail,email), dob=IFNULL(varDob, dob), gender=IFNULL(varGender, gender), mob=IFNULL(varMob, mob), pri_telephone=IFNULL(priTelephone, pri_telephone), sec_telephone=IFNULL(secTelephone, sec_telephone), 
    receive_promotional_by_email=IFNULL(promoByEmail, receive_promotional_by_email), receive_promotional_by_sms=IFNULL(promoBySMS, receive_promotional_by_sms), receive_promotional_by_post=IFNULL(promoByPost, receive_promotional_by_post), receive_promotional_by_phone=IFNULL(promoByPhone, receive_promotional_by_phone), receive_promotional_by_mobile=IFNULL(promoByMobile, receive_promotional_by_mobile), receive_promotional_by_third_party=IFNULL(promoByThirdParty, receive_promotional_by_third_party), 
    email_verification_type_id=IFNULL(emailVerificationTypeID, email_verification_type_id), sms_verification_type_id=IFNULL(smsVerificationTypeID, sms_verification_type_id), post_verification_type_id=IFNULL(postVerificationTypeID, post_verification_type_id), 
    phone_verification_type_id=IFNULL(phoneVerificationTypeID, phone_verification_type_id), third_party_verification_type_id=IFNULL(thirdPartyVerificationTypeID, third_party_verification_type_id), preferred_promotion_type_id=IFNULL(preferredPromotionTypeID, preferred_promotion_type_id), 
    contact_by_email=IFNULL(contactByEmail, contact_by_email), contact_by_sms=IFNULL(contactBySMS, contact_by_sms), contact_by_post=IFNULL(contactByPost, contact_by_post), contact_by_phone=IFNULL(contactByPhone, contact_by_phone), contact_by_mobile=IFNULL(contactByMobile, contact_by_mobile), contact_by_third_party=IFNULL(contactByThirdParty, contact_by_third_party), 
    username=IFNULL(varUsername, username), nickname=IFNULL(varNickname, nickname), language_id=IF((languageCode IS NULL or languageCode = ''), language_id, (SELECT language_id FROM gaming_languages WHERE language_code=languageCode)), 
    client_segment_id=IFNULL(clientSegmentID, client_segment_id), risk_client_segment_id=IFNULL(riskClientSegmentID, risk_client_segment_id), allow_login_banned_country_ip=IFNULL(allowLoginBannedCountryFromIP,allow_login_banned_country_ip), session_id=sessionID, last_updated=NOW(), 
    pass_hash_type = IF(varPassword IS NULL, pass_hash_type,HashTypeID), vip_level=IFNULL(vipLevel, vip_level), rnd_score=IFNULL(rndScore, rnd_score), news_feeds_allow=IFNULL(newsFeedAllow, news_feeds_allow),
    age_verification_type_id=IF(ageVerificationTypeName IS NULL, age_verification_type_id, IFNULL((SELECT client_age_verification_type_id FROM gaming_client_age_verification_types WHERE name=ageVerificationTypeName), age_verification_type_id)),
    age_verification_date = IF(ageVerificationTypeName IS NULL, age_verification_date, IF((SELECT clean_player_age_verification_date FROM gaming_client_age_verification_types WHERE name=ageVerificationTypeName)=1,null,NOW())), vip_level_id=IFNULL(newVipLevelID, vip_level_id), vip_downgrade_disabled = IFNULL(vipDowngradeDisabled, 0),
    day_of_year_dob=IF(varDob IS NULL, day_of_year_dob, DAYOFYEAR(varDob)), num_details_changes=IF(changeDetected, changeNo, num_details_changes),
    registration_ipaddress = IFNULL(registrationIpAddress, registration_ipaddress),
    registration_ipaddress_v4 = IFNULL(registrationIpAddressV4, registration_ipaddress_v4), 
    country_id_from_ip = IFNULL(countryIDFromIP, country_id_from_ip),
    platform_type_id = IFNULL(platformTypeID, platform_type_id),
	bet_factor = IFNULL(BetFactor, bet_factor), 
	risk_score = IFNULL(riskScore, risk_score), 
	client_risk_category_id = IFNULL(clientRiskCategoryId, client_risk_category_id),
	fraud_similar_details=SPLIT_EMAIL_IN_WORDS(email, 5, ' '),
	retailer_id = IFNULL(retailerID, retailer_id),
	employee_id = IFNULL(employeeID, employee_id)
  WHERE client_id=clientID;
  
  IF (varPassword IS NOT NULL AND varPassword!=curPassword) THEN
	CALL PlayerUpdatePlayerPassword(clientID, varPassword, 0, isPlayer, userID);
  END IF; 

  IF (clientSegmentID IS NOT NULL AND IFNULL(currentClientSegmentID,0)!=clientSegmentID) THEN
    CALL ClientSegmentAddPlayerToSegment(clientID, clientSegmentID, @changeSegmentStatus);
  END IF;
  
  IF (riskClientSegmentID IS NOT NULL AND IFNULL(currentRiskClientSegmentID,0)!=riskClientSegmentID) THEN
    CALL ClientSegmentAddPlayerToSegment(clientID, riskClientSegmentID, @changeSegmentStatus);
  END IF;

  COMMIT AND CHAIN;
  
  IF (fraudEnabled AND fraudPlayerDetailsEnabled) THEN
  
    IF (changeDetected) THEN 
		SET @fraudEventType='UpdateDetails';
		SET @operatorID=(SELECT operator_id FROM gaming_operators WHERE is_main_operator=1);
		CALL FraudEventRun(@operatorID, clientID, @fraudEventType, sessionID, sessionID, NULL, 0, 1, @fraudStatusCode);

		COMMIT AND CHAIN;
	END IF;

    CALL FruadGetCurrentClientEventSimple(clientID);
  END IF;

  CALL NotificationEventCreate(3, clientID, NULL, 0);
  CALL NotificationEventCreate(614, clientID, NULL, 0);
   
END$$
DELIMITER ;

