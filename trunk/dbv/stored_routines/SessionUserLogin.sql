DROP procedure IF EXISTS `SessionUserLogin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionUserLogin`(
  varUsername VARCHAR(255), userPassword VARCHAR(255), newHashedPassword VARCHAR(255), sessionGUID VARCHAR(80), 
  serverID BIGINT, componentID BIGINT, IP VARCHAR(40), IPv4 VARCHAR(20), OUT statusCode INT)
root:BEGIN

  /*
  1 - Invalid Login Details
  2 - Account not activated
  3 - User has been blocked
  4 - Invalid Login Details
  // To DO
  5 - System Login disabled
  6 - Country banning by IP
  7 - Banned IP
  8 - User Restriction
  // Done
  9 - Password expired, password mut be updated
  10 - Login has been temporary blocked
  11 - Login has been permanently blocked
  12 - Password needs to be changed
  */  

  -- If user is already logged in and password need not be changed on login we simply return the existing session
  -- Password Policy Enhancements
  -- Temporary & Indefinite Blocking
  -- Checking if password needs to be changed
  -- Fixed: Not to add a user restriction when the player is already blocked for both temporary and indefinite. 
  -- Fixed: Not to increment BadAttempts and LastConsecutiveBad after reaching indefinite blocking and trying to log in again with bad combinination

  DECLARE userID, sessionID, userLoginAttemptID BIGINT DEFAULT -1;
  DECLARE varSalt, dbPassword, hashedPassword, sessionGUIDCurrent VARCHAR(255);
  DECLARE hasLoginAttemptTotal, accountActivated, isActive, passwordExpiryEnabled, userRestrictionEnabled, 
	temporaryLockEnabled, indefiniteLockEnabled, hasTemporaryLock, hasIndefiniteBlock, requirePasswordChange, isDisabled TINYINT(1) DEFAULT 0;
  DECLARE lastPasswordChangeDate DATETIME DEFAULT NULL;
  DECLARE temporaryLockNumMinutes, temporaryLockMaxFailedAttempts, numPasswordExpiryDays, userMaxLoginAttemps, lastConsecutiveBad, 
	userTemporaryLockingBadAttempts, numRestrictions INT DEFAULT 0;

  SET statusCode=0;
  
  SELECT user_id, salt, password, activated, active, last_password_change_date, require_password_change, is_disabled
  INTO userID, varSalt, dbPassword, accountActivated, isActive, lastPasswordChangeDate, requirePasswordChange, isDisabled
  FROM users_main 
  WHERE users_main.username=varUsername AND active=1 AND account_closed=0 AND is_global_view_user=0;
  
  IF (userID = -1) THEN
    SET statusCode = 1;
  ELSEIF (isActive=0) THEN
    SET statusCode = 3;
  ELSEIF (isDisabled = 1) THEN
	SET statusCode = 2;
  ELSE
    SET hashedPassword = UPPER(SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(userPassword,'')),256));
    IF (hashedPassword <> dbPassword) THEN
      SET statusCode = 4;
    END IF;
  END IF;

 SELECT value_bool INTO userRestrictionEnabled FROM gaming_settings WHERE name='USER_RESTRICTION_ENABLED';
  SELECT value_bool INTO temporaryLockEnabled FROM gaming_settings WHERE `name`='USER_TEMPORARY_LOCK_FAILED_LOGINS_ENABLED';
  SELECT value_int INTO userMaxLoginAttemps FROM gaming_settings WHERE name='USER_INDEFINITE_LOCK_FAILED_LOGINS_COUNT';
  IF (userMaxLoginAttemps > 0) THEN
    SET indefiniteLockEnabled = 1;
  END IF;

  IF (userID !=-1 AND (temporaryLockEnabled=1 OR indefiniteLockEnabled=1)) THEN
	
	SELECT COUNT(*)>0 INTO hasIndefiniteBlock
	FROM users_restrictions
	JOIN users_restriction_types AS restriction_types ON restriction_types.name='account_lock' AND restriction_types.disallow_login=1 AND users_restrictions.user_restriction_type_id=restriction_types.user_restriction_type_id
	WHERE users_restrictions.user_id=userID AND users_restrictions.is_active=1 AND users_restrictions.is_indefinitely=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date;
	
	SELECT COUNT(*)>0 INTO hasTemporaryLock
	FROM users_restrictions
	JOIN users_restriction_types AS restriction_types ON restriction_types.name='account_lock' AND restriction_types.disallow_login=1 AND users_restrictions.user_restriction_type_id=restriction_types.user_restriction_type_id
	WHERE users_restrictions.user_id=userID AND users_restrictions.is_active=1 AND users_restrictions.is_indefinitely=0 AND NOW() BETWEEN restrict_from_date AND restrict_until_date;

	IF (hasIndefiniteBlock = 1) then
		SET statusCode = 11;
	ELSEIF (hasTemporaryLock = 1) THEN
	  SET statusCode = 10;
	END IF;
    
  ELSE IF (userRestrictionEnabled=1) THEN
    
    SELECT COUNT(*) INTO numRestrictions
    FROM users_restrictions
    JOIN users_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_login=1 AND users_restrictions.user_restriction_type_id=restriction_types.user_restriction_type_id
    WHERE users_restrictions.user_id=userID AND users_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date;
  
	IF (numRestrictions>0) THEN
	  SET statusCode=8;
	  SET hasTemporaryLock=1; -- even if not due to temporary lock we set the value to 1 not to increment bad attemps
	END IF;
  END IF;
  
  END IF;

  SELECT value_bool INTO passwordExpiryEnabled FROM gaming_settings WHERE name='USER_PASSWORD_EXPIRATION_ENABLED';	
  SELECT value_int INTO numPasswordExpiryDays FROM gaming_settings WHERE name='USER_PASSWORD_EXPIRATION_DAYS';
  
  -- Check if password has expired
  IF (statusCode=0 AND passwordExpiryEnabled=1) THEN
	  IF (lastPasswordChangeDate IS NOT NULL) THEN
		IF (DATE_ADD(lastPasswordChangeDate, INTERVAL numPasswordExpiryDays DAY)<NOW() AND newHashedPassword IS NULL) THEN
			SET statusCode=9;
		END IF;
	  ELSE
		UPDATE users_main SET last_password_change_date=NOW() WHERE user_id=userID;
	  END IF;
  END IF;
  
  IF (newHashedPassword IS NULL AND statusCode=0) THEN
 
	SELECT session_id, session_guid INTO sessionID, sessionGUIDCurrent 
	FROM sessions_main FORCE INDEX (user_active_session) 
	WHERE sessions_main.user_id=userID AND sessions_main.status_code=1 AND sessions_main.session_type=1 AND sessions_main.date_expiry > NOW()
    ORDER BY session_id DESC LIMIT 1;
    
    IF (sessionID != -1) THEN
		SELECT sessionID AS session_id, sessionGUIDCurrent AS session_key;
        LEAVE root;
    END IF;
 
 END IF;

  INSERT INTO users_login_attempts (
	user_id, ip, ip_v4, server_id, component_id, is_success, attempt_datetime, 
	session_id, username_entered, user_login_attempt_status_code_id) 
  SELECT userID, IP, IPv4, serverID, componentID, 0, NOW(), NULL, varUsername, 0; 
  
  SET userLoginAttemptID=LAST_INSERT_ID();

  IF (userID!=-1) THEN
   
    SELECT 1
    INTO hasLoginAttemptTotal
    FROM users_login_attempts_totals 
    WHERE user_id=userID;
    
    IF (hasLoginAttemptTotal<>1) THEN
      INSERT INTO users_login_attempts_totals(user_id, last_ip, last_ip_v4) 
      VALUES (userID, IP, IPv4);
    END IF;
 
    UPDATE users_login_attempts_totals
    SET 
      last_success = IF(statusCode=0,NOW(),last_success),
      last_attempt = NOW(),
      last_ip = IP, 
      last_ip_v4 = IPv4,
      bad_attempts = IF(statusCode=0, bad_attempts, bad_attempts + IF(hasTemporaryLock OR hasIndefiniteBlock OR statusCode=9, 0, 1)),
      good_attempts = IF(statusCode=0, good_attempts + 1, good_attempts),
      last_consecutive_bad = IF(statusCode=0, 0, last_consecutive_bad + IF(hasTemporaryLock OR hasIndefiniteBlock OR statusCode=9, 0, 1)),
	  temporary_locking_bad_attempts = IF(statusCode=0 OR temporaryLockEnabled=0,
		0, temporary_locking_bad_attempts + IF(hasTemporaryLock OR hasIndefiniteBlock OR statusCode=9, 0, 1))
    WHERE user_id=userID;
 
	SELECT last_consecutive_bad, temporary_locking_bad_attempts 
	INTO lastConsecutiveBad, userTemporaryLockingBadAttempts 
	FROM users_login_attempts_totals 
	WHERE user_id=userID;
    
	IF (lastConsecutiveBad > 0 AND hasTemporaryLock=0 AND hasIndefiniteBlock=0) THEN
	
		IF (lastConsecutiveBad >= userMaxLoginAttemps) THEN
			SET @restrictionReason=REPLACE('Account indefinitely locked due to wrong password [X] times', '[X]', userMaxLoginAttemps);
			CALL UserRestrictionAddRestriction(userID, 'account_lock', 1, NULL, NOW(), NULL, 0, NULL, @restrictionReason, 0, @restrictionStatusCode);

			SET statusCode = 11;

		ELSE

			SELECT value_int INTO temporaryLockMaxFailedAttempts FROM gaming_settings WHERE `name`='USER_TEMPORARY_LOCK_FAILED_LOGINS_COUNT';
	
			IF (temporaryLockEnabled=1 AND userTemporaryLockingBadAttempts>=temporaryLockMaxFailedAttempts) THEN
				-- Apply restriction
				SET @restrictionReason=REPLACE('Account temporarily locked due to wrong password [X] times', '[X]', temporaryLockMaxFailedAttempts);
				SELECT value_int INTO temporaryLockNumMinutes FROM gaming_settings WHERE `name`='USER_TEMPORARY_LOCK_FAILED_LOGINS_LOCK_DURATION';
				CALL UserRestrictionAddRestriction(userID, 'account_lock', 0, temporaryLockNumMinutes, NOW(), NULL, 0, NULL, @restrictionReason, 0, @restrictionStatusCode);
				-- rest the lock counter
				UPDATE users_login_attempts_totals
				SET temporary_locking_bad_attempts = 0
				WHERE user_id=userID;

				SET statusCode = 10;
			END IF;

		END IF;
	END IF;
    
  END IF;
  
  IF (statusCode=0 AND requirePasswordChange AND newHashedPassword IS NULL) THEN
	SET statusCode=12;
  END IF;

  IF (statusCode<>0) THEN
    UPDATE users_login_attempts AS login_attemp
    JOIN users_login_attempts_status_codes AS login_status_code ON
      login_attemp.user_login_attempt_id=userLoginAttemptID AND
      login_status_code.status_code=statusCode
    SET login_attemp.is_success=0, login_attemp.session_id=NULL, 
		login_attemp.user_login_attempt_status_code_id=login_status_code.user_login_attempt_status_code_id;
  
    LEAVE root;
  END IF;

  -- Change password
  IF (statusCode=0 AND newHashedPassword IS NOT NULL) THEN 
    CALL UserUpdatePassword(userID, newHashedPassword);
  END IF;
  
  UPDATE sessions_main 
  SET date_closed=NOW(), status_code=2, date_expiry=SUBTIME(NOW(), '00:00:01'), 
	session_close_type_id=(SELECT session_close_type_id FROM sessions_close_types WHERE name='NewLogin')   
  WHERE user_id=userID AND status_code=1 AND session_type=1;
  
  INSERT INTO sessions_main (
	server_id, component_id, ip, ip_v4, session_guid, date_open, status_code, 
	session_type, user_id, extra_id, date_expiry, active, platform_type_id) 
  
  SELECT serverID, componentID, IP,IPv4, sessionGUID, NOW(), 1, 1, userID, NULL, DATE_ADD(NOW(), INTERVAL sessions_defaults.user_expirey_duration MINUTE), 1, 6
  FROM sessions_defaults WHERE server_id=serverID AND component_id=componentID AND active=1;
  
  SET sessionID=LAST_INSERT_ID();
    
  UPDATE users_login_attempts AS login_attemp
  JOIN users_login_attempts_status_codes AS login_status_code ON
    login_attemp.user_login_attempt_id=userLoginAttemptID AND
    login_status_code.status_code=statusCode
  SET login_attemp.is_success=1, 
	login_attemp.session_id=sessionID, 
    login_attemp.user_login_attempt_status_code_id=login_status_code.user_login_attempt_status_code_id;
    
  SELECT sessionID AS session_id, sessionGUID AS session_key;
    
END root$$

DELIMITER ;

