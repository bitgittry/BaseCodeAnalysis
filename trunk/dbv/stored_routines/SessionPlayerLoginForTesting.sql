DROP procedure IF EXISTS `SessionPlayerLoginForTesting`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionPlayerLoginForTesting`(operatorID BIGINT, clientID BIGINT, sessionGUID VARCHAR(80), serverID BIGINT, componentID BIGINT, IP VARCHAR(40), IPv4 VARCHAR(20), countryIDFromIP BIGINT, runFraudEngine TINYINT(1), OUT statusCode INT)
root:BEGIN
  
  DECLARE userID, clientStatID, sessionID BIGINT DEFAULT -1;
  DECLARE varSalt, dbPassword, hashedPassword VARCHAR(255);
  DECLARE playerMaxLoginAttemps, lastConsecutiveBad INT;
  DECLARE accountActivated, isActive, isTestPlayer, hasLoginAttemptTotal, playerLoginEnabled, testPlayerLoginEnabled, fraudEnabled, fraudOnLoginEnabled, allowLoginBannedCountryIP, countryDisallowLoginFromIP, playerRestrictionEnabled TINYINT(1) DEFAULT 0;
  
  SET statusCode = 0; 
    
  
  SELECT user_id INTO userID 
  FROM gaming_operators 
  WHERE operator_id=operatorID;
  
  if (userID = -1) THEN
    SET statusCode = 1;
    LEAVE root;
  END IF;
  
  SELECT gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.is_test_player
  INTO clientID, clientStatID, isTestPlayer    
  FROM gaming_clients 
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
  JOIN gaming_client_stats ON 
    gaming_clients.client_id=clientID AND
    gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1  
  WHERE gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL);
     
  
  IF (clientStatID = -1) THEN 
    SET statusCode = 2;
  END IF;
 
  
  INSERT INTO gaming_clients_login_attempts (client_id, ip, ip_v4, server_id, component_id, is_success, attempt_datetime, session_id, username_entered, client_login_attempt_status_code_id, country_id_from_ip)
  SELECT clientID, IP, IPv4, serverID, componentID, 0, NOW(), NULL, NULL, 0, countryIDFromIP; 
  
  SET @clientLoginAttemptID=LAST_INSERT_ID();
  
  
  IF (clientID<>-1) THEN
  
    
    SELECT 1
    INTO hasLoginAttemptTotal
    FROM gaming_clients_login_attempts_totals 
    WHERE client_id=clientID;
    
    IF (hasLoginAttemptTotal<>1) THEN
      INSERT INTO gaming_clients_login_attempts_totals(client_id, last_ip, last_ip_v4) 
      VALUES (clientID, IP, IPv4);
    END IF;
    
    UPDATE gaming_clients_login_attempts_totals
    SET 
      first_success = IF(first_success IS NULL AND statusCode=0, NOW(), first_success),
      previous_success = IF(statusCode=0,last_success, previous_success),
      last_success = IF(statusCode=0,NOW(),last_success),
      last_attempt = NOW(),
      last_ip = IP, 
      last_ip_v4 = IPv4,
      bad_attempts = IF(statusCode=0,bad_attempts,bad_attempts + 1),
      good_attempts = IF(statusCode=0,good_attempts + 1,good_attempts),
      last_consecutive_bad = IF(statusCode=0,0,last_consecutive_bad+1)
    WHERE client_id=clientID;
   
   SELECT last_consecutive_bad INTO lastConsecutiveBad FROM gaming_clients_login_attempts_totals WHERE client_id=clientID;
   
    
    IF lastConsecutiveBad >= playerMaxLoginAttemps THEN
        UPDATE gaming_clients SET is_active = 0 WHERE client_id=clientID;
        SET statusCode = 4;
    END IF;
  END IF;
  
  
  IF (statusCode<>0) THEN
    UPDATE gaming_clients_login_attempts AS login_attemp
    JOIN gaming_clients_login_attempts_status_codes AS login_status_code ON
      login_attemp.client_login_attempt_id=@clientLoginAttemptID AND
      login_status_code.status_code=statusCode
    SET login_attemp.is_success=0, login_attemp.session_id=NULL, login_attemp.client_login_attempt_status_code_id=login_status_code.client_login_attempt_status_code_id;
    LEAVE root;
  END IF;
  
  
  
  UPDATE sessions_main SET date_closed=NOW(), status_code=2, date_expiry=SUBTIME(NOW(), '00:00:01'), session_close_type_id=(SELECT session_close_type_id FROM sessions_close_types WHERE name='NewLogin') WHERE extra_id=clientID AND status_code=1;
  
  UPDATE gaming_client_sessions JOIN gaming_client_stats ON gaming_client_sessions.client_stat_id=gaming_client_stats.client_stat_id 
	SET gaming_client_sessions.is_open=0, gaming_client_sessions.end_balance_real=gaming_client_stats.current_real_balance, gaming_client_sessions.end_balance_bonus=gaming_client_stats.current_bonus_balance, gaming_client_sessions.end_balance_bonus_win_locked=gaming_client_stats.current_bonus_win_locked_balance 
  WHERE gaming_client_sessions.client_stat_id=clientStatID AND gaming_client_sessions.is_open=1; 
  
  UPDATE gaming_game_sessions SET is_open=0, session_end_date=NOW() WHERE client_stat_id=clientStatID AND is_open=1;  
  UPDATE sessions_main SET is_latest=0 WHERE extra_id=clientID AND is_latest=1;
  
  
  INSERT INTO sessions_main (server_id, component_id, ip, ip_v4, session_guid, date_open, status_code, session_type, user_id, extra_id, extra2_id, date_expiry, active, country_id_from_ip,is_latest) 
    SELECT serverID, componentID, IP, IPv4, sessionGUID, NOW(), 1, 2, userID, clientID, clientStatID, DATE_ADD(NOW(), INTERVAL sessions_defaults.expiry_duration MINUTE), 1, countryIDFromIP,1
    FROM sessions_defaults WHERE server_id=serverID AND component_id=componentID AND active=1;
  
  SET sessionID=LAST_INSERT_ID();
    
  
  INSERT INTO gaming_client_sessions (session_id, client_stat_id, is_open, start_balance_real, start_balance_bonus, start_balance_bonus_win_locked) 
  SELECT sessionID, clientStatID, 1, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance
  FROM gaming_client_stats WHERE client_stat_id=clientStatID;
  
  UPDATE gaming_clients_login_attempts AS login_attemp
  JOIN gaming_clients_login_attempts_status_codes AS login_status_code ON
    login_attemp.client_login_attempt_id=@clientLoginAttemptID AND
    login_status_code.status_code=statusCode
  SET login_attemp.is_success=1, login_attemp.session_id=sessionID, login_attemp.client_login_attempt_status_code_id=login_status_code.client_login_attempt_status_code_id;
    
  
  CALL BonusCheckAwardingOnLogin(sessionID, clientStatID, NULL);
  
  
  SELECT sessionID AS session_id, sessionGUID AS session_key, clientID AS client_id, clientStatID AS client_stat_id;
  
  
  
END root$$

DELIMITER ;

