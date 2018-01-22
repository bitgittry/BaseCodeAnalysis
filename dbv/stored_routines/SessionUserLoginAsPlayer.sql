DROP procedure IF EXISTS `SessionUserLoginAsPlayer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionUserLoginAsPlayer`(userUsername VARCHAR(80), userPassword  VARCHAR(80), playerPIN VARCHAR(20), sessionGUID VARCHAR(80), serverID BIGINT, componentID BIGINT, IP VARCHAR(40), IPv4 VARCHAR(20), countryIDFromIP BIGINT, countryRegionIdFromIp BIGINT, OUT statusCode INT)
root:BEGIN
  -- Added parameter to BonusCheckAwardingOnLogin to fix the method
  
  DECLARE userID, clientID, clientStatID, sessionID BIGINT DEFAULT -1;
  DECLARE varSalt, dbPassword, hashedPassword VARCHAR(255);
  DECLARE accountActivated, isActive, isTestPlayer, hasLoginAttemptTotal, playerLoginEnabled, testPlayerLoginEnabled, fraudEnabled, fraudOnLoginEnabled, allowLoginBannedCountryIP, countryDisallowLoginFromIP, playerRestrictionEnabled TINYINT(1) DEFAULT 0;
  
  SET statusCode = 0; 
  
 
  SELECT user_id, salt, password INTO userID, varSalt, dbPassword FROM users_main 
  WHERE users_main.username=userUsername AND active=1 AND account_closed=0;
  IF (userID = -1) THEN
    SET statusCode = 2;
    LEAVE root;
  ELSE
    SET hashedPassword = UPPER(SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(userPassword,'')),256));
    IF (hashedPassword <> dbPassword) THEN
      SET statusCode = 4;
      LEAVE root;
    END IF;
  END IF;
  
  SELECT gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.account_activated, gaming_clients.is_active, gaming_clients.is_test_player, allow_login_banned_country_ip
  INTO clientID, clientStatID, accountActivated, isActive, isTestPlayer, allowLoginBannedCountryIP    
  FROM gaming_clients 
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
  JOIN gaming_client_stats ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active 
  WHERE gaming_clients.PIN1=playerPIN AND (gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL));
  
  IF (clientID = -1) THEN
    SET statusCode = 13;
    LEAVE root;
  END IF; 
  
  IF (isActive=0) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  
  SELECT value_bool INTO playerRestrictionEnabled FROM gaming_settings WHERE name='PLAYER_RESTRICTION_ENABLED';
  IF (statusCode=0 AND playerRestrictionEnabled=1) THEN
    SET @numRestrictions=0;
    SET @restrictionType=NULL;
    SELECT restriction_types.name, COUNT(*) INTO @restrictionType, @numRestrictions
    FROM gaming_player_restrictions
    JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_login=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
    WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date;
  
    IF (@numRestrictions=1 AND @restrictionType='account_activation_policy' AND accountActivated=0) THEN
      SET statusCode = 3;
    ELSEIF (@numRestrictions > 0) THEN
      SET statusCode=12;
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
    SET @dissallowLogin=0;
    SELECT 1 INTO @dissallowLogin  
    FROM gaming_fraud_ips 
    JOIN gaming_fraud_ips_status_types ON gaming_fraud_ips_status_types.name='BlackListed' AND gaming_fraud_ips.fraud_ip_status_type_id=gaming_fraud_ips_status_types.fraud_ip_status_type_id
    WHERE (ip_v4_address=IPv4 OR ip_v6_address=IP) AND gaming_fraud_ips.is_active=1;
    
    IF (@dissallowLogin) THEN
      SET statusCode=11;
    END IF;
  END IF;
  
  IF (statusCode<>0) THEN
    LEAVE root;
  END IF;
  
  
  
  UPDATE sessions_main SET date_closed=NOW(), status_code=2, date_expiry=SUBTIME(NOW(), '00:00:01'), session_close_type_id=(SELECT session_close_type_id FROM sessions_close_types WHERE name='NewLogin') WHERE extra_id=clientID AND status_code=1;
  UPDATE gaming_client_sessions SET is_open=0 WHERE client_stat_id=clientStatID AND is_open=1; 
  UPDATE gaming_game_sessions SET is_open=0, session_end_date=NOW() WHERE client_stat_id=clientStatID AND is_open=1;  
  UPDATE sessions_main SET is_latest=0 WHERE extra_id=clientID AND is_latest=1;
  
  
  INSERT INTO sessions_main (server_id, component_id, ip, ip_v4, session_guid, date_open, status_code, session_type, user_id, extra_id, extra2_id, date_expiry, active, country_id_from_ip,is_latest, platform_type_id, country_region_id_from_ip) 
    SELECT serverID, componentID, IP, IPv4, sessionGUID, NOW(), 1, 2, userID, clientID, clientStatID, DATE_ADD(NOW(), INTERVAL sessions_defaults.expiry_duration MINUTE), 1, countryIDFromIP,1, 6, countryRegionIdFromIp
    FROM sessions_defaults WHERE server_id=serverID AND component_id=componentID AND active=1;
  
  SET sessionID=LAST_INSERT_ID();
    
  
  INSERT INTO gaming_client_sessions (session_id,client_stat_id,is_open) 
  SELECT sessionID,clientStatID,1;
              
  CALL BonusCheckAwardingOnLogin(sessionID, clientStatID, NULL);
  
  
  SELECT sessionID AS session_id, sessionGUID AS session_key, clientID AS client_id, clientStatID AS client_stat_id;            
     
END root$$

DELIMITER ;

