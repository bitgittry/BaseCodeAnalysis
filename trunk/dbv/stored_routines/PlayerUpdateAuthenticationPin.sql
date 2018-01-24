DROP procedure IF EXISTS `PlayerUpdateAuthenticationPin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdateAuthenticationPin`(clientID BIGINT, varPass VARCHAR(250), varPin VARCHAR(250), varNewPin VARCHAR(250),  varPinChangeOnLogin TINYINT(1), varByPassValidations TINYINT(1), OUT statusCode INT)
root: BEGIN
	-- check if new pin matches with a historical pin
	-- Inserting in gaming_clients_pin_changes if pin was changed
	-- Updating num_pin_changes if pin was changed  
    -- Added push notifications
    -- Removed cursor
    -- Added a pin parameter to allow for PIN change using old PIN
    -- Fixed initial select query (selecting latest change)
	-- Revamped the authentication conditions
	-- Optimized
	/*
		statusCode = 0 => success
		statusCode = 1 => pin exists in historical pins
		statusCode = 2 => player passed a wrong password
		statusCode = 3 => player passed a wrong PIN
		statusCode = 4 => player passed a wrong password and/or wrong PIN
	*/
	  DECLARE curPin VARCHAR(250);
	  DECLARE curPass VARCHAR(250);
	  DECLARE hashedNewPin, hashedPin, hashedPass VARCHAR(250);
	  DECLARE numPinChanges INT DEFAULT 0;
	  DECLARE historyNum, authWeight INT DEFAULT 0;
	  DECLARE curNumPinChanges INT DEFAULT 0;
	  DECLARE samehistoryPinCount INT DEFAULT 0;
	  DECLARE varSalt VARCHAR(60);
	  DECLARE notificationEnabled, authPassOk, authPinOk, passGiven, pinGiven TINYINT(1) DEFAULT 0;

	  SET statusCode = 0;

	  SELECT 
	  	PASSWORD, authentication_pin, num_pin_changes, salt INTO curPass, curPin, curNumPinChanges, varSalt 
  	  FROM gaming_clients WHERE client_id=clientID ORDER BY num_pin_changes DESC LIMIT 1;
  		
	  SELECT value_int INTO historyNum FROM gaming_settings WHERE `name`='PIN_COUNT_HISTORY_VALIDATION';
	  SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';

	  SET passGiven = IF(varPass IS NULL,0,1);
  	  SET pinGiven = IF(varPin IS NULL,0,1);
	  
	  -- get hashed values
 	  SET hashedPass = UPPER(IF(passGiven, SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(varPass,'')),256), ''));
  	  SET hashedPin = UPPER(IF(pinGiven, SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(varPin,'')),256), ''));
   	  SET hashedNewPin = UPPER(SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(varNewPin,'')),256));
	
   	  SET authPassOk = IF(curPass=hashedPass, 1, 0);
   	  SET authPinOk = IF(curPin=hashedPin, 1, 0);
      
	  SET authWeight = IF(passGiven OR pinGiven, authWeight, authWeight+1);
   	  SET authWeight = IF((authPassOk AND passGiven) OR !passGiven, authWeight, authWeight+1);
   	  SET authWeight = IF((authPinOk AND pinGiven) OR !pinGiven, authWeight, authWeight+1);
   	  -- if backend, skip auth
   	  SET authWeight = IF(varByPassValidations, 0, authWeight);
   	 
   	  IF (authWeight > 0) THEN
   	  	IF (passGiven AND !pinGiven) THEN
   	  		SET statusCode = 2;
			LEAVE root;
   	  	ELSEIF (pinGiven AND !passGiven) THEN
   	  		SET statusCode = 3;
			LEAVE root;
   	  	ELSE
   	  		SET statusCode = 4;
			LEAVE root;
   	  	END IF;
   	  END IF;
   	  	
		  IF (historyNum > 0) THEN
			SELECT COUNT(*) INTO samehistoryPinCount
			FROM gaming_clients_pin_changes 
			WHERE change_num > (curNumPinChanges - historyNum) 
				AND client_id = clientID
				AND hashed_pin = hashedNewPin;
		  END IF;
	  
		  IF (samehistoryPinCount > 0 ) THEN
			  SET statusCode = 1;
			  LEAVE root;
		  ELSE 
			  UPDATE gaming_clients 
			  SET  authentication_pin=IFNULL(hashedNewPin, authentication_pin),
				   num_pin_changes=IF(varNewPin IS NOT NULL, num_pin_changes+1, num_pin_changes),
				   failed_consecutive_PIN_code_attempts=0,
				   failed_total_PIN_code_attempts=0,
				   reset_authentication_pin_request_date = IF(varNewPin IS NOT NULL, NOW(), reset_authentication_pin_request_date),
				   pin_change_on_login = IF(varNewPin IS NOT NULL AND varNewPin!=IFNULL(curPin,''), varPinChangeOnLogin, 0)
			  WHERE client_id=clientID;
			  
			  IF (hashedNewPin IS NOT NULL) THEN
				  INSERT INTO gaming_clients_pin_changes (client_id, change_num, hashed_pin, salt)
				  SELECT client_id, num_pin_changes, authentication_pin, salt
				  FROM gaming_clients
				  WHERE client_id=clientID;
			  END IF;	
		  END IF;

		  IF (notificationEnabled=1) THEN
			 INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing)  
			 SELECT IF(is_indefinitely, 519, 518), player_restriction_id, clientID, 0
			 FROM gaming_player_restrictions
			 WHERE is_active = 1 AND client_id=clientID AND player_restriction_type_id=5
			 ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
		  END IF;

		  CALL AuditLogAttributeChange('Authentication PIN Change', clientID, 
			AuditLogNewGroup(@modifierEntityExtraId, @auditLogSessionId, clientID, 2, @modifierEntityType, NULL, NULL, clientID),
			'********', '********', NOW());

		  UPDATE gaming_player_restrictions
		  SET is_active = 0, removal_reason='Authentication PIN Updated'
		  WHERE is_active = 1 AND client_id=clientID AND player_restriction_type_id=5;

END$$

DELIMITER ;

