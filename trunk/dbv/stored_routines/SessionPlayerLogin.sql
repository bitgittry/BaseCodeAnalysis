DROP procedure IF EXISTS `SessionPlayerLogin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionPlayerLogin`(operatorID BIGINT, playerUsername VARCHAR(255), playerPassword VARCHAR(255), playerAuthenticationPin VARCHAR(255), 
sessionGUID VARCHAR(80), serverID BIGINT, componentID BIGINT, IP VARCHAR(40), IPv4 VARCHAR(20), countryIDFromIP BIGINT, countryRegionIdFromIp BIGINT,
runFraudEngine TINYINT(1), macAddress VARCHAR(40), downloadClientID VARCHAR(40), platformType VARCHAR(20), 
uaBrandName VARCHAR(60), uaModelName VARCHAR(60), uaOSName VARCHAR(60), uaOSVersionName VARCHAR(60), uaBrowserName VARCHAR(60), uaBrowserVersionName VARCHAR(60), uaEngineName VARCHAR(60), 
uaEngineVersionName VARCHAR(60), bonusVoucherCode VARCHAR(45), deviceAccountId BIGINT, clientIDFromApplication BIGINT, 
 playerCard VARCHAR(255), playerEmail VARCHAR(255), loginType VARCHAR(255), OUT statusCode INT)
root:BEGIN
  -- IF clientIDFromApplication is passed the password is not checked 

  DECLARE userID, clientID, clientStatID, sessionID, oldSessionID, latestSession BIGINT DEFAULT -1;
  DECLARE varSalt, dbPassword, dbAuthenticationPin, hashedPassword, hashedAuthenticationPin, EncryptionType, channelType VARCHAR(255);
  DECLARE playerMaxLoginAttemps, lastConsecutiveBad, HashTypeDefault INT;
  DECLARE accountActivated, isActive, isTestPlayer, hasLoginAttemptTotal, playerLoginEnabled, testPlayerLoginEnabled, fraudEnabled, 
	fraudOnLoginEnabled, allowLoginBannedCountryIP, countryDisallowLoginFromIP, playerRestrictionEnabled, 
    exceededLoginAttempts, dynamicFilterOnLogin, allowMultipleSessions, fraudAccountBlocked, 
    usernameCaseSensitive, hasPlayRestriction, uaAgentEnabled TINYINT(1) DEFAULT 0;
  DECLARE sessionType VARCHAR(80) DEFAULT 'credentials';
  DECLARE platformTypeID,cardStatus INT DEFAULT NULL;
  DECLARE platformTypeExpiryDuration INT DEFAULT NULL;
  DECLARE openSessionsCount, openSessionsCountSamePlatform INT DEFAULT 0;
  DECLARE realBalance, winLockedBalance,bonusBalance DECIMAL(18,5);
  DECLARE playRestrictionExpiryDate DATETIME DEFAULT NULL;
  
  DECLARE numRestrictions, fraudStatusCode, temporaryLockNumMinutes, 
	temporaryLockMaxFailedAttempts, playerTemporaryLockingBadAttempts, numPasswordExpiryDays INT DEFAULT 0;
  DECLARE restrictionType VARCHAR(255) DEFAULT NULL;
  DECLARE clientLoginAttemptID,clientIDCheck,sessionIDTemp BIGINT;
  DECLARE dissallowLogin, runPostLogin, temporaryLockEnabled, hasTemporaryLock, hasAuthenticationPinLock, 
	notificationEnabled, passwordExpiryEnabled, passwordMustChange, authenticationPinMustChange,
    throwErrorIfAlreadyLoggedIn, allowOneLoginFromEachPlatform, ruleEngineEnabled TINYINT(1) DEFAULT 0;
  DECLARE runPostLoginDate, lastPasswordChangeDate, lastLoginDate DATETIME DEFAULT NULL;

  DECLARE uaBrandID, uaModelID, uaOSID, uaOSVersionID, uaBrowserID, uaBrowserVersionID, uaEngineID, uaEngineVersionID BIGINT(20) DEFAULT NULL;
  DECLARE registrationCode VARCHAR(5) DEFAULT NULL;

  SET EncryptionType = 'Sha256';
  SET statusCode = 0;
    
  
  SELECT user_id INTO userID 
  FROM gaming_operators 
  WHERE operator_id=operatorID;
  
  IF (userID = -1) THEN
    SET statusCode = 1;
    LEAVE root;
  END IF;
  
	-- Get Settings
  SELECT IFNULL(gs1.value_bool, 0), IFNULL(gs2.value_bool, 0), IFNULL(gs3.value_bool, 0), gs4.value_int, gs5.value_string, 
		 IFNULL(gs6.value_bool, 0), IFNULL(gs7.value_bool, 0), IFNULL(gs8.value_bool, 0), gs9.value_int, IFNULL(gs10.value_bool, 0), IFNULL(gs11.value_bool, 0), 
         IFNULL(gs12.value_bool, 0), IFNULL(gs13.value_bool, 0), IFNULL(gs14.value_bool, 0),  IFNULL(gs15.value_bool, 0),  IFNULL(gs16.value_bool, 0),  IFNULL(gs17.value_bool, 0),
         IFNULL(gs18.value_bool, 0)
  INTO usernameCaseSensitive, playerLoginEnabled, testPlayerLoginEnabled, playerMaxLoginAttemps, sessionType, 
	dynamicFilterOnLogin, notificationEnabled, passwordExpiryEnabled, numPasswordExpiryDays, allowMultipleSessions, fraudEnabled, 
    fraudOnLoginEnabled, playerRestrictionEnabled, temporaryLockEnabled, throwErrorIfAlreadyLoggedIn, allowOneLoginFromEachPlatform, uaAgentEnabled, ruleEngineEnabled
  FROM gaming_settings gs1 
  STRAIGHT_JOIN gaming_settings gs2 ON gs2.name='SESSION_ALLOW_LOGIN'
  STRAIGHT_JOIN gaming_settings gs3 ON gs3.name='SESSION_ALLOW_LOGIN_TESTPLAYERS'
  STRAIGHT_JOIN gaming_settings gs4 ON gs4.name='PLAYER_LOGIN_ATTEMPS_MAX'
  STRAIGHT_JOIN gaming_settings gs5 ON gs5.name='PLAYER_SESSION_LOGIN_TYPE'
  STRAIGHT_JOIN gaming_settings gs6 ON gs6.name='DYNAMIC_FILTER_UPDATE_ON_LOGIN'
  STRAIGHT_JOIN gaming_settings gs7 ON gs7.name='NOTIFICATION_ENABLED'
  STRAIGHT_JOIN gaming_settings gs8 ON gs8.name='PLAYER_PASSWORD_EXPIRATION_ENABLED'
  STRAIGHT_JOIN gaming_settings gs9 ON gs9.name='PLAYER_PASSWORD_EXPIRATION_DAYS'
  STRAIGHT_JOIN gaming_settings gs10 ON gs10.name='PLAYER_SESSION_ALLOW_MULTIPLE'
  STRAIGHT_JOIN gaming_settings gs11 ON gs11.name='FRAUD_ENABLED'
  STRAIGHT_JOIN gaming_settings gs12 ON gs12.name='FRAUD_ON_LOGIN_ENABLED'
  STRAIGHT_JOIN gaming_settings gs13 ON gs13.name='PLAYER_RESTRICTION_ENABLED'
  LEFT JOIN gaming_settings gs14 ON gs14.name='SESSION_TEMPORARY_LOCK_FAILED_LOGINS_ENABLED'
  LEFT JOIN gaming_settings gs15 ON gs15.name='PLAYER_SESSION_ALREADY_LOGGED_IN_RETURN_ERROR'
  LEFT JOIN gaming_settings gs16 ON gs16.name='PLAYER_SESSION_ALLOW_LOGIN_FROM_DIFFERENT_PLATFORMS'
  LEFT JOIN gaming_settings gs17 ON gs17.name='UA_AGENT_ENABLED'
  LEFT JOIN gaming_settings gs18 ON gs18.name='RULE_ENGINE_ENABLED'
  WHERE gs1.name='USERNAME_CASE_SENSITIVE';

  -- Check if the account is fraud blocked first
  IF (fraudEnabled AND fraudOnLoginEnabled) THEN
    -- Get fraud block status (old players don't have a record yet)
    
      SELECT block_account INTO fraudAccountBlocked
      FROM gaming_clients FORCE INDEX (username)
      LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
      WHERE gaming_clients.username=playerUsername AND IF (usernameCaseSensitive=1, BINARY gaming_clients.username = playerUsername, LOWER(username) = BINARY LOWER(playerUsername)) AND gaming_clients.is_account_closed=0 AND IFNULL(gaming_fraud_rule_client_settings.block_account, 0) = 1;
    
    IF (fraudAccountBlocked) THEN
      -- Account is fraud-blocked : 20
      SET statusCode = 20;
      LEAVE root;
    END IF;
    
  END IF;
  
  COMMIT AND CHAIN;
  
  IF (sessionType = 'credentials') THEN

	IF (clientIDFromApplication IS NOT NULL) THEN
    
        SELECT gaming_clients.client_id, salt, `password`, authentication_pin, gaming_clients.account_activated, gaming_clients.is_active, 
			gaming_clients.is_test_player, allow_login_banned_country_ip, exceeded_login_attempts, last_password_change_date
		INTO clientID, varSalt, dbPassword, dbAuthenticationPin, accountActivated, isActive, 
			isTestPlayer, allowLoginBannedCountryIP, exceededLoginAttempts, lastPasswordChangeDate  
		FROM gaming_clients
        WHERE client_id=clientIDFromApplication AND gaming_clients.is_account_closed=0;
	
    ELSEIF (loginType = 'Default' OR loginType = 'UsernamePassword'  OR loginType = 'UsernamePin') THEN
    
        SELECT gaming_clients.client_id, salt, `password`, authentication_pin, gaming_clients.account_activated, gaming_clients.is_active, 
			gaming_clients.is_test_player, allow_login_banned_country_ip, exceeded_login_attempts, last_password_change_date
        INTO clientID, varSalt, dbPassword, dbAuthenticationPin, accountActivated, isActive, 
			isTestPlayer, allowLoginBannedCountryIP, exceededLoginAttempts, lastPasswordChangeDate  
        FROM gaming_clients FORCE INDEX (username)
        WHERE gaming_clients.username=playerUsername AND IF (usernameCaseSensitive=1, BINARY gaming_clients.username = playerUsername, LOWER(username) = BINARY LOWER(playerUsername)) AND gaming_clients.is_account_closed=0;
    
    ELSEIF (loginType = 'EmailPassword' OR loginType = 'EmailPin') THEN
        
        SELECT gaming_clients.client_id, salt, `password`, authentication_pin, gaming_clients.account_activated, gaming_clients.is_active, 
			gaming_clients.is_test_player, allow_login_banned_country_ip, exceeded_login_attempts, last_password_change_date
        INTO clientID, varSalt, dbPassword, dbAuthenticationPin, accountActivated, isActive, 
        isTestPlayer, allowLoginBannedCountryIP, exceededLoginAttempts, lastPasswordChangeDate  
        FROM gaming_clients FORCE INDEX (email)
        JOIN gaming_client_registrations ON gaming_clients.client_id = gaming_client_registrations.client_id and is_current = 1
        WHERE (gaming_clients.email=playerEmail AND IF (usernameCaseSensitive=1, BINARY gaming_clients.email = playerEmail,1)) 
			AND gaming_clients.is_account_closed=0 AND gaming_client_registrations.client_registration_type_id = 3;
       
	ELSEIF (loginType = 'Playercard' OR loginType = 'PlayercardPin') THEN
    		
            SELECT gaming_clients.client_id, salt, `password`, authentication_pin, gaming_clients.account_activated, gaming_clients.is_active, 
				gaming_clients.is_test_player, allow_login_banned_country_ip, exceeded_login_attempts, last_password_change_date, gaming_playercard_cards.card_status
    		INTO clientID, varSalt, dbPassword, dbAuthenticationPin, accountActivated, isActive, 
				isTestPlayer, allowLoginBannedCountryIP, exceededLoginAttempts, lastPasswordChangeDate, cardStatus 
    		FROM gaming_playercard_cards FORCE INDEX (PRIMARY)
            STRAIGHT_JOIN gaming_clients ON gaming_clients.client_id = gaming_playercard_cards.client_id AND gaming_clients.is_account_closed=0
    		WHERE gaming_playercard_cards.playercard_cards_id = playerCard AND gaming_playercard_cards.card_status IN  (0,1);

			IF (cardStatus = 1) THEN
				SET statusCode = 24; -- TD
				LEAVE root; 
			END IF;
            
  END IF;
    
    IF (clientID != -1) THEN
    
		SELECT gaming_client_stats.client_stat_id, gaming_client_stats.current_real_balance, gaming_client_stats.current_bonus_balance, gaming_client_stats.current_bonus_win_locked_balance, gaming_client_stats.run_post_login_date 
		INTO clientStatID, realBalance, bonusBalance, winLockedBalance, runPostLoginDate
		FROM gaming_client_stats 
		WHERE gaming_client_stats.client_id=clientID AND gaming_client_stats.is_active=1
		FOR UPDATE; 

		SELECT gaming_clients_pass_hash_type.name INTO EncryptionType
		FROM gaming_clients    
		STRAIGHT_JOIN gaming_clients_pass_hash_type ON gaming_clients_pass_hash_type.pass_hash_type_id =gaming_clients.pass_hash_type  
		WHERE gaming_clients.client_id=clientID;
        
	END IF;
    
  ELSE
  
    SELECT gaming_clients.client_id, salt, password, gaming_clients.account_activated, gaming_clients.is_active, gaming_clients.is_test_player, allow_login_banned_country_ip, exceeded_login_attempts, last_password_change_date
	INTO clientID, varSalt, dbPassword, accountActivated, isActive, isTestPlayer, allowLoginBannedCountryIP, exceededLoginAttempts, lastPasswordChangeDate	  
    FROM gaming_clients FORCE INDEX (ext_client_id)
	WHERE gaming_clients.ext_client_id=playerUsername AND gaming_clients.is_account_closed=0;
  
    IF (clientID != -1) THEN
		
        SELECT gaming_client_stats.client_stat_id, gaming_client_stats.current_real_balance, gaming_client_stats.current_bonus_balance, 
			gaming_client_stats.current_bonus_win_locked_balance, gaming_client_stats.run_post_login_date 
		INTO clientStatID, realBalance, bonusBalance, winLockedBalance, runPostLoginDate
		FROM gaming_client_stats FORCE INDEX (client_id)
		WHERE gaming_client_stats.client_id=clientID AND gaming_client_stats.is_active=1
		FOR UPDATE;
        
	END IF;
    
  END IF;

    -- Check if Platform is passed, If passed validate that it's active via the channel. If not passed get the default platform type
	IF (platformType IS NOT NULL) THEN
		
        SELECT gaming_platform_types.platform_type_id, gaming_platform_types.platform_type, expiry_duration, channel_type 
        INTO platformTypeID, platformType, platformTypeExpiryDuration, channelType
		FROM gaming_platform_types
		LEFT JOIN gaming_channels_platform_types ON gaming_channels_platform_types.platform_type_id = gaming_platform_types.platform_type_id
		LEFT JOIN gaming_channel_types ON gaming_channels_platform_types.channel_type_id = gaming_channel_types.channel_type_id
		WHERE platform_type=platformType AND IFNULL(gaming_channel_types.is_active, 1)=1;

		IF (platformTypeID IS NULL) THEN
			SET statusCode = 21;
		END IF;
        
	ELSE
    
		SELECT gaming_platform_types.platform_type_id, gaming_platform_types.platform_type,  expiry_duration, channel_type 
        INTO platformTypeID, platformType, platformTypeExpiryDuration, channelType
		FROM gaming_platform_types 
		LEFT JOIN gaming_channels_platform_types ON gaming_channels_platform_types.platform_type_id = gaming_platform_types.platform_type_id
		LEFT JOIN gaming_channel_types ON gaming_channels_platform_types.channel_type_id = gaming_channel_types.channel_type_id
		WHERE is_default=1 AND IFNULL(gaming_channel_types.is_active, 1)=1
        LIMIT 1;
        
	END IF;
  
  IF (clientID!=-1) THEN
	
      SELECT IFNULL(pin_change_on_login,0), IFNULL(password_change_on_login,0) 
      INTO authenticationPinMustChange, passwordMustChange 
      FROM gaming_clients WHERE client_id = clientID;    
  
  END IF;
   
  IF (clientID=-1) THEN
    SET statusCode = 2;
  ELSEIF (isTestPlayer=0 AND playerLoginEnabled=0) THEN
    SET statusCode=6;
	SELECT clientID AS client_id;
	LEAVE root; 
  ELSEIF (isTestPlayer=1 AND testPlayerLoginEnabled=0) THEN
    SET statusCode=6;
	SELECT clientID AS client_id;
	LEAVE root; 
  ELSEIF (isActive=0) THEN
    SET statusCode = 4;
	LEAVE root; 
  ELSEIF (exceededLoginAttempts=1) THEN
    SET statusCode = 15;
  ELSEIF (authenticationPinMustChange=1 AND (loginType = 'UsernamePin' OR loginType = 'EmailPin' OR loginType = 'PlayercardPin')) THEN
    SET statusCode=16;
    SELECT clientID AS client_id;
    LEAVE root; 
  ELSEIF (passwordMustChange=1 AND (loginType = 'UsernamePassword' OR loginType = 'EmailPassword')) THEN
    SET statusCode=14;
    SELECT clientID AS client_id; 
    LEAVE root; 
  END IF;
  
  IF(clientIDFromApplication IS NULL) THEN 
		IF (loginType = 'UsernamePassword' OR loginType = 'EmailPassword' OR loginType = 'Default') THEN 
			IF(EncryptionType='Sha256') THEN
				SET hashedPassword = SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(playerPassword,'')),256);
				IF (hashedPassword <> dbPassword) THEN
					SET statusCode = 5;
				END IF;
			ELSE 
				IF (EncryptionType='md5-finsoft') THEN  
					SET hashedPassword = MD5(CONCAT(IFNULL(UPPER(playerUsername),''),IFNULL(playerPassword,'')));
					IF (hashedPassword <> dbPassword) THEN
						SET statusCode = 5;
					END IF; 
				ELSE   
					SET hashedPassword = SHA1(IFNULL(playerPassword,''));
					IF (hashedPassword <> dbPassword) THEN
						SET statusCode = 5;
					END IF;
				END IF;
				IF (statusCode <> 5) THEN
					SELECT pass_hash_type_id INTO HashTypeDefault FROM gaming_clients_pass_hash_type WHERE is_default=1;
					UPDATE gaming_clients 
                    SET password=UPPER(SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(playerPassword,'')),256)), 
						pass_hash_type = HashTypeDefault 
					WHERE client_id = clientID;
				END IF;
			END IF;
		ELSE IF(loginType = 'UsernamePin' OR loginType = 'EmailPin' OR loginType = 'PlayercardPin') THEN
				SET hashedAuthenticationPin = SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(playerAuthenticationPin,'')),256);

				IF ((hashedAuthenticationPin <> dbAuthenticationPin) OR IFNULL(dbAuthenticationPin,'') = '' OR IFNULL(hashedAuthenticationPin,'') = '')  THEN
					SET statusCode = 5; -- TD
				END IF;
		END IF;
	END IF;
  END IF;

  IF (temporaryLockEnabled=1) THEN 
	
    SELECT COUNT(*)>0 INTO hasTemporaryLock
	FROM gaming_player_restrictions FORCE INDEX (client_active_non_expired)
	STRAIGHT_JOIN gaming_player_restriction_types AS restriction_types ON 
		restriction_types.name='temporary_account_lock' AND restriction_types.disallow_login=1 
        AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
	WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 
		AND NOW() BETWEEN restrict_from_date AND restrict_until_date;
	
	IF (hasTemporaryLock = 1) THEN
	  SET statusCode = 13;
	END IF;
  END IF;

	IF (loginType = 'UsernamePin' OR loginType = 'EmailPin' OR loginType = 'PlayercardPin') THEN
    
		SELECT COUNT(*)>0 INTO hasAuthenticationPinLock
		FROM gaming_player_restrictions FORCE INDEX (client_active_non_expired)
		STRAIGHT_JOIN gaming_player_restriction_types AS restriction_types ON 
			restriction_types.name='pin_code_temporary_lock' 
            AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
		WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 
			AND NOW() BETWEEN restrict_from_date AND restrict_until_date;
		IF (hasAuthenticationPinLock = 1) THEN
		  SET statusCode = 22;
		END IF;
        
	END IF;

  IF (playerRestrictionEnabled AND hasTemporaryLock=0 AND hasAuthenticationPinLock=0) THEN

	SELECT restriction_types.name, COUNT(*) 
    INTO restrictionType, numRestrictions
    FROM gaming_player_restrictions FORCE INDEX (client_active_non_expired)
    STRAIGHT_JOIN gaming_player_restriction_types AS restriction_types ON 
		restriction_types.is_active=1 AND restriction_types.disallow_login=1 
		AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
    WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date;

    IF (numRestrictions>0) THEN
	  SET statusCode=12;
      SET hasTemporaryLock=1; 
	END IF;

    IF (numRestrictions=1 AND restrictionType='account_activation_policy' AND accountActivated=0) THEN
      SET statusCode = 3;
	ELSEIF (numRestrictions=1 AND restrictionType = 'close_account_indefinite_policy') THEN
	  SET statusCode = 4;
    ELSEIF (numRestrictions=1 AND restrictionType='temporary_account_lock') THEN
	  SET statusCode = 13;
	ELSEIF (numRestrictions=1 AND restrictionType='pin_code_temporary_lock') THEN
	  SET statusCode = 22;
	END IF;
    
      IF (statusCode=0) THEN
    
		SELECT 1, restrict_until_date 
        INTO hasPlayRestriction, playRestrictionExpiryDate
		FROM gaming_player_restrictions FORCE INDEX (client_active_non_expired)
		STRAIGHT_JOIN gaming_player_restriction_types AS restriction_types ON 
			restriction_types.is_active=1 AND restriction_types.disallow_play=1 
			AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
		WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date
        ORDER BY restrict_until_date DESC
        LIMIT 1;
      
      END IF;
      
  END IF; 
  
  SELECT COUNT(*) INTO openSessionsCount 
  FROM sessions_main FORCE INDEX (client_active_session)
  WHERE extra_id=clientID AND status_code=1 AND session_type=2;
  
  IF (openSessionsCount > 0) THEN
  
	  IF (throwErrorIfAlreadyLoggedIn) THEN
		
			IF (allowOneLoginFromEachPlatform) THEN
				
                  SELECT COUNT(*) INTO openSessionsCountSamePlatform 
				  FROM sessions_main FORCE INDEX (client_active_session)
				  WHERE extra_id=clientID AND status_code=1 AND session_type=2 AND 
					 ((platformTypeID IS NULL AND platform_type_id IS NULL) OR (platformTypeID IS NOT NULL AND platform_type_id=platformTypeID));
				
				  IF (openSessionsCountSamePlatform>0) THEN
					SET statusCode=23;
                  END IF;
                
            ELSE
				SET statusCode=23;
			END IF;
      
      END IF;
      
  END IF;
  
  INSERT INTO gaming_clients_login_attempts (client_id, ip, ip_v4, server_id, component_id, is_success, attempt_datetime, session_id, 
	username_entered, client_login_attempt_status_code_id, country_id_from_ip, mac_address, download_client_id,platform_type_id, country_region_id_from_ip)
  SELECT clientID, IP, IPv4, serverID, componentID, 0, NOW(), NULL, 
	playerUsername, 0, countryIDFromIP, macAddress, downloadClientID, platformTypeID, countryRegionIdFromIp; 
  
  SET clientLoginAttemptID=LAST_INSERT_ID();

  IF (statusCode NOT IN (1,2,3,4,12,13,21,23)) THEN
  
    IF (fraudEnabled=1 AND fraudOnLoginEnabled=1 AND runFraudEngine=1) THEN  
    
      UPDATE gaming_clients_login_attempts_totals
      SET last_ip = IP, last_ip_v4 = IPv4
      WHERE client_id=clientID;
    
      SET fraudStatusCode=-1;
      SET sessionIDTemp=0;
      CALL FraudEventRun(operatorID,clientID,'Login',clientLoginAttemptID,sessionIDTemp,NULL,0,1,fraudStatusCode);
      
      
      IF (fraudStatusCode<>0) THEN
        SET statusCode=10;
        LEAVE root;
      END IF;
      
      SET clientIDCheck=-1;
      SET dissallowLogin=0;
      SELECT client_id, disallow_login INTO clientIDCheck, dissallowLogin
      FROM gaming_fraud_client_events AS cl_events FORCE INDEX (client_id_current_event)
      STRAIGHT_JOIN gaming_fraud_classification_types ON 
        cl_events.client_id=clientID AND cl_events.is_current=1 AND
        cl_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id;
          
      IF (dissallowLogin) THEN
        SET statusCode=7;
      END IF;
      
    END IF;
  
  END IF;
  
  IF (statusCode=0 AND allowLoginBannedCountryIP=0) THEN
    
    SELECT 1 INTO countryDisallowLoginFromIP
    FROM gaming_fraud_banned_countries_from_ips
    WHERE (country_id=countryIDFromIP AND country_region_id = 0 AND disallow_login=1) OR (country_id=countryIDFromIP AND country_region_id = countryRegionIdFromIp AND disallow_login=1);
    
    IF (countryDisallowLoginFromIP=1) THEN
      SET statusCode=8;
    END IF;
    
  END IF;
  
  IF (statusCode=0) THEN
  
    SET dissallowLogin=0;
    SELECT 1 INTO dissallowLogin  
    FROM gaming_fraud_ips FORCE INDEX (ip_v4_address, ip_v6_address)
    STRAIGHT_JOIN gaming_fraud_ips_status_types ON gaming_fraud_ips_status_types.name='BlackListed'
		AND gaming_fraud_ips.fraud_ip_status_type_id=gaming_fraud_ips_status_types.fraud_ip_status_type_id
    WHERE (ip_v4_address=IPv4 OR ip_v6_address=IP) AND gaming_fraud_ips.is_active=1
	LIMIT 1;
    
    IF (dissallowLogin) THEN
      SET statusCode=11;
    END IF;
  
  END IF;
  
  IF (statusCode=0 AND passwordExpiryEnabled=1 AND (loginType != 'UsernamePin' AND loginType != 'EmailPin' AND loginType != 'Playercard' AND loginType != 'PlayercardPin')) THEN
	  
      IF (lastPasswordChangeDate IS NOT NULL) THEN
		IF (DATE_ADD(lastPasswordChangeDate, INTERVAL numPasswordExpiryDays DAY)<NOW()) THEN
			SET statusCode=14;
		END IF;
	  ELSE
		UPDATE gaming_clients SET last_password_change_date=NOW() WHERE client_id=clientID;
	  END IF;
      
  END IF;

  IF (clientID<>-1) THEN
  
    SELECT 1, last_success
    INTO hasLoginAttemptTotal, lastLoginDate
    FROM gaming_clients_login_attempts_totals 
    WHERE client_id=clientID;
    
    IF (hasLoginAttemptTotal<>1) THEN
      INSERT INTO gaming_clients_login_attempts_totals(client_id, last_ip, last_ip_v4) 
      VALUES (clientID, IP, IPv4);
    END IF;
    
    UPDATE gaming_clients_login_attempts_totals
    SET 
      first_success = IF(first_success IS NULL AND statusCode=0, NOW(), first_success),
      previous_success = IF(statusCode=0, last_success, previous_success),
      last_success = IF(statusCode=0, NOW(), last_success),
      last_attempt = NOW(),
      last_ip = IP, 
      last_ip_v4 = IPv4,
      bad_attempts = IF(statusCode=0,bad_attempts,bad_attempts + IF(hasTemporaryLock OR exceededLoginAttempts, 0, 1)), 
      good_attempts = IF(statusCode=0,good_attempts + 1,good_attempts),
      last_consecutive_bad = IF(statusCode IN (0, 23) , 0,
			last_consecutive_bad + IF(hasTemporaryLock OR exceededLoginAttempts, 0, 1)),
	  temporary_locking_bad_attempts = IF(statusCode IN (0, 23) OR temporaryLockEnabled=0,0,
			temporary_locking_bad_attempts + IF(hasTemporaryLock OR exceededLoginAttempts, 0, 1)),
      last_mac_address = macAddress, 
      last_download_client_id = downloadClientID
    WHERE client_id=clientID;
   
   SELECT last_consecutive_bad, temporary_locking_bad_attempts 
   INTO lastConsecutiveBad, playerTemporaryLockingBadAttempts 
   FROM gaming_clients_login_attempts_totals 
   WHERE client_id=clientID;

    IF (lastConsecutiveBad > 0 AND hasTemporaryLock=0 AND exceededLoginAttempts=0) THEN
    
	  IF lastConsecutiveBad >= playerMaxLoginAttemps THEN
      
			UPDATE gaming_clients SET exceeded_login_attempts = 1 WHERE client_id=clientID;
			
			IF (notificationEnabled) THEN
				INSERT INTO notifications_events (notification_event_type_id, event_id, is_processing) 
				VALUES (504, clientID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
			END IF;

			SET statusCode = 15;
    
	  ELSE 
        
			SELECT value_int INTO temporaryLockMaxFailedAttempts FROM gaming_settings WHERE `name`='SESSION_TEMPORARY_LOCK_FAILED_LOGINS_COUNT';
		
			IF (temporaryLockEnabled=1 AND playerTemporaryLockingBadAttempts>=temporaryLockMaxFailedAttempts) THEN
					
				SELECT value_int INTO temporaryLockNumMinutes FROM gaming_settings WHERE `name`='SESSION_TEMPORARY_LOCK_FAILED_LOGINS_LOCK_DURATION';
				CALL PlayerRestrictionAddRestriction(clientID, clientStatID, 'temporary_account_lock', 0, 
					temporaryLockNumMinutes, NOW(), NULL, NULL, 0, NULL, 'Temporary Account Lock', 0, @restrictionStatusCode);
				
				UPDATE gaming_clients_login_attempts_totals
				SET temporary_locking_bad_attempts = 0
				WHERE client_id=clientID;

				SET statusCode = 13;
                
			END IF;
        
	  END IF;

	END IF;
	
  END IF;
  
  IF (statusCode<>0) THEN
    UPDATE gaming_clients_login_attempts AS login_attemp
    STRAIGHT_JOIN gaming_clients_login_attempts_status_codes AS login_status_code ON
      login_attemp.client_login_attempt_id=clientLoginAttemptID AND
      login_status_code.status_code=statusCode
    SET login_attemp.is_success=0, login_attemp.session_id=NULL, 
		login_attemp.client_login_attempt_status_code_id=login_status_code.client_login_attempt_status_code_id;
    
    SELECT clientID AS client_id;
    
    LEAVE root;
  END IF;
  
  CALL PlayerUpdatePlayerStatus(clientID);
  
  SELECT session_id INTO latestSession
  FROM sessions_main FORCE INDEX (client_latest_session)
  WHERE extra_id=clientID AND is_latest=1 
  LIMIT 1;  
  
	IF (openSessionsCount > 0 AND throwErrorIfAlreadyLoggedIn=0 AND allowMultipleSessions=0) THEN
	  SELECT session_id INTO oldSessionID
	  FROM sessions_main FORCE INDEX (client_active_session)
	  WHERE extra_id=clientID AND status_code=1;

	  UPDATE sessions_main 
	  SET date_closed=NOW(), status_code=2, date_expiry=SUBTIME(NOW(), '00:00:01'), 
		  session_close_type_id=(SELECT session_close_type_id FROM sessions_close_types WHERE name='NewLogin') 
	  WHERE session_id = oldSessionID;

	  UPDATE gaming_client_sessions FORCE INDEX (client_open_sessions)
		SET gaming_client_sessions.is_open=0, gaming_client_sessions.end_balance_real=realBalance, 
			gaming_client_sessions.end_balance_bonus= bonusBalance, gaming_client_sessions.end_balance_bonus_win_locked=winLockedBalance
	  WHERE gaming_client_sessions.client_stat_id=clientStatID AND gaming_client_sessions.is_open=1; 
	  
	  UPDATE gaming_game_sessions SET is_open=0, session_end_date=NOW() 
	  WHERE client_stat_id=clientStatID AND is_open=1;
	END IF;
   
  UPDATE sessions_main SET is_latest=0 
  WHERE session_id = latestSession;
  
  INSERT INTO sessions_main (server_id, component_id, ip, ip_v4, session_guid, date_open, status_code, session_type, user_id, extra_id, extra2_id, 
	date_expiry, active, country_id_from_ip, is_latest, mac_address, download_client_id, 
    platform_type_id, device_account_id, is_authenticated, session_credentials, country_region_id_from_ip) 
  SELECT serverID, componentID, IP, IPv4, sessionGUID, NOW(), 1, 2, userID, clientID, clientStatID, 
	DATE_ADD(NOW(), INTERVAL IFNULL(platformTypeExpiryDuration, sessions_defaults.expiry_duration) MINUTE), 1, countryIDFromIP, 1, macAddress, downloadClientID, 
    platformTypeID, deviceAccountId, IF(logintype = "Playercard",0,1), IF(loginType = 'Default', 'UsernamePassword', loginType), countryRegionIdFromIp
  FROM sessions_defaults 
  WHERE server_id=serverID AND component_id=componentID AND active=1;
   
  SET sessionID=LAST_INSERT_ID();
  
  -- actually we consider only sessions close, to get their duration
  -- IF (ruleEngineEnabled) THEN
	--  INSERT INTO gaming_event_rows (event_table_id, elem_id, rule_engine_state) SELECT 4, sessionID, 0 ON DUPLICATE KEY UPDATE elem_id=sessionID;
  -- END IF;
  
  
  INSERT INTO gaming_client_sessions (session_id, client_stat_id, is_open, start_balance_real, start_balance_bonus, start_balance_bonus_win_locked) 
  SELECT sessionID, clientStatID, 1, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance
  FROM gaming_client_stats 
  WHERE client_stat_id=clientStatID;
  
  UPDATE gaming_clients_login_attempts AS login_attemp
  STRAIGHT_JOIN gaming_clients_login_attempts_status_codes AS login_status_code ON
    login_attemp.client_login_attempt_id=clientLoginAttemptID AND
    login_status_code.status_code=statusCode
  SET login_attemp.is_success=1, login_attemp.session_id=sessionID, 
	  login_attemp.client_login_attempt_status_code_id=login_status_code.client_login_attempt_status_code_id;
  
  IF (fraudEnabled=1 AND fraudOnLoginEnabled=1 AND runFraudEngine=1) THEN
    SET sessionIDTemp=sessionID;
    CALL FraudEventRun(operatorID,clientID,'Login',clientLoginAttemptID,sessionIDTemp,NULL,0,1,fraudStatusCode);
  END IF;
  
  
  IF ((runPostLoginDate IS NULL OR (DATE_SUB(NOW(), INTERVAL 5 MINUTE) > runPostLoginDate)) AND statusCode=0)  THEN
	SET runPostLogin=1;
	UPDATE gaming_client_stats SET run_post_login_date=NOW() WHERE client_stat_id=clientStatID;
  END IF;
  
  IF (runPostLogin=0) THEN
    CALL BonusCheckAwardingOnLogin(sessionID, clientStatID, bonusVoucherCode);
  END IF;  
  
  IF (uaAgentEnabled) THEN
  
	  IF (uaBrandName IS NOT NULL) THEN
		SELECT ua_brand_id INTO uaBrandID
		FROM gaming_ua_brands 
		WHERE gaming_ua_brands.name = uaBrandName;

		IF (uaBrandID IS NULL) THEN
			INSERT INTO gaming_ua_brands (NAME)
			VALUES (uaBrandName);
			SET uaBrandID=LAST_INSERT_ID();     
		END IF;
	  END IF;

	  IF (uaModelName IS NOT NULL) THEN 	
		SELECT ua_model_id INTO uaModelID
		FROM gaming_ua_models 
		WHERE gaming_ua_models.name = uaModelName;

		IF (uaModelID IS NULL) THEN
			INSERT INTO gaming_ua_models (ua_model_type_id, ua_brand_id, NAME)
			VALUES (1, uaBrandID, uaModelName);
			SET uaModelID=LAST_INSERT_ID();
		END IF;
	  END IF;

	  IF (uaOSName IS NOT NULL) THEN
		SELECT ua_os_id INTO uaOSID
		FROM gaming_ua_os
		WHERE gaming_ua_os.name = uaOSName;

		IF (uaOSID IS NULL) THEN
			INSERT INTO gaming_ua_os (NAME)
			VALUES (uaOSName);
			SET uaOSID=LAST_INSERT_ID();          
		END IF;              
	  END IF;

	  IF (uaOSVersionName IS NOT NULL) THEN 	
		SELECT ua_os_version_id INTO uaOSVersionID
		FROM gaming_ua_os_versions 
		WHERE gaming_ua_os_versions.name = uaOSVersionName;

		IF (uaOSVersionID IS NULL) THEN
			INSERT INTO gaming_ua_os_versions (ua_os_id, NAME)
			VALUES (uaOSID, uaOSVersionName);
			SET uaOSVersionID=LAST_INSERT_ID();       
		END IF;                 
	  END IF;

	  IF (uaBrowserName IS NOT NULL) THEN 
		SELECT ua_browser_id INTO uaBrowserID
		FROM gaming_ua_browsers
		WHERE gaming_ua_browsers.name = uaBrowserName;

		IF (uaBrowserID IS NULL) THEN
			INSERT INTO gaming_ua_browsers (NAME)
			VALUES (uaBrowserName);
			SET uaBrowserID=LAST_INSERT_ID();         
		END IF;               
	  END IF;

	  IF (uaBrowserVersionName IS NOT NULL) THEN 
		SELECT ua_browser_version_id INTO uaBrowserVersionID
		FROM gaming_ua_browser_versions
		WHERE gaming_ua_browser_versions.name = uaBrowserVersionName;	

		IF (uaBrowserVersionID IS NULL) THEN
			INSERT INTO gaming_ua_browser_versions (ua_browser_id, NAME)
			VALUES (uaBrowserID, uaBrowserVersionName);
			SET uaBrowserVersionID=LAST_INSERT_ID();     
		END IF;                   
	  END IF;

	  IF (uaEngineName IS NOT NULL) THEN 	
		SELECT ua_engine_id INTO uaEngineID
		FROM gaming_ua_engines 
		WHERE gaming_ua_engines.name = uaEngineName;

		IF (uaEngineID IS NULL) THEN
			INSERT INTO gaming_ua_engines (NAME)
			VALUES (uaEngineName);
			SET uaEngineID=LAST_INSERT_ID();          
		END IF;              
	  END IF;

	  IF (uaEngineVersionName IS NOT NULL) THEN 	
		SELECT ua_engine_version_id INTO uaEngineVersionID
		FROM gaming_ua_engine_versions 
		WHERE gaming_ua_engine_versions.name = uaEngineVersionName;

		IF (uaEngineVersionID IS NULL) THEN
			INSERT INTO gaming_ua_engine_versions (ua_engine_id, NAME)
			VALUES (uaEngineID, uaEngineVersionName);
			SET uaEngineVersionID=LAST_INSERT_ID();      
		END IF;                  
	  END IF;

	  INSERT INTO gaming_client_ua_sessions (
		session_id, ua_brand_id, ua_model_id, ua_os_id, ua_os_version_id, ua_browser_id, 
		ua_browser_version_id, ua_engine_id, ua_engine_version_id)
	  VALUES (sessionID, uaBrandID, uaModelID, uaOSID, uaOSVersionID, uaBrowserID, uaBrowserVersionID, uaEngineID, uaEngineVersionID);

  END IF;

  COMMIT AND CHAIN;

  SELECT registration_code INTO registrationCode
	FROM gaming_client_registrations FORCE INDEX (client_current)
	STRAIGHT_JOIN gaming_client_registration_types 
		ON gaming_client_registrations.client_registration_type_id = gaming_client_registration_types.client_registration_type_id
	WHERE client_id = clientID AND is_current = 1;

  SELECT sessionID AS session_id, sessionGUID AS session_key, clientID AS client_id, clientStatID AS client_stat_id, 
	runPostLogin AS run_post_login, openSessionsCount AS current_open_sessions_count,
	registrationCode AS registration_code, lastLoginDate AS last_login_date, channelType AS channel_type, platformType AS platform_type,
    hasPlayRestriction AS has_play_restriction, playRestrictionExpiryDate AS play_restriction_expiry_date;
  

END root$$

DELIMITER ;

