DROP procedure IF EXISTS `PlayerUpdatePassword`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdatePassword`(clientID BIGINT, varPassword VARCHAR(250), varNewPassword VARCHAR(250), OUT statusCode INT)
root: BEGIN
	-- check if new password matches with a historical password
	-- Inserting in gaming_clients_password_changes if pass was changed
	-- Updating num_password_changes if pass was changed  
    -- Added push notifications
	/*
		statusCode = 0 => success
		statusCode = 1 => player passed a wrong password
		statusCode = 2 => player contains username (Dependant On Setting)
		statusCode = 3 => password exists in historical passwords
	*/
	  DECLARE HashTypeID INT;
	  DECLARE curUsername, curPass, curEncryptionType VARCHAR(250);
	  DECLARE hashedNewPass, hashedPass VARCHAR(250);
	  DECLARE numPassChanges INT DEFAULT 0;
	  DECLARE historyNum, authWeight INT DEFAULT 0;
	  DECLARE curNumPassChanges INT DEFAULT 0;
	  DECLARE samehistoryPassCount INT DEFAULT 0;
	  DECLARE varSalt VARCHAR(60);
	  DECLARE authPassOk, passGiven, playerPasswordDisallowUsernameEnabled TINYINT(1) DEFAULT 0;

	  SET statusCode = 0;

	  SELECT username, `password`, num_password_changes, salt, gaming_clients_pass_hash_type.name 
		INTO curUsername, curPass, curNumPassChanges, varSalt, curEncryptionType
  	  FROM gaming_clients 
	  STRAIGHT_JOIN gaming_clients_pass_hash_type ON gaming_clients_pass_hash_type.pass_hash_type_id =gaming_clients.pass_hash_type
	  WHERE client_id=clientID;
  		
	  -- Get Default Hashing
	  SELECT pass_hash_type_id INTO HashTypeID FROM gaming_clients_pass_hash_type WHERE is_default=1;

	  SELECT gs1.value_int, gs2.value_bool INTO historyNum, playerPasswordDisallowUsernameEnabled FROM gaming_settings gs1
	  STRAIGHT_JOIN gaming_settings gs2 ON gs2.name='PLAYER_PASSWORD_DISALLOW_USERNAME'	
	  WHERE gs1.`name`='PLAYER_PASSWORD_DISALLOW_SAME_PASSWORD_COUNTER';
	 	    
     
	  SET passGiven = IF(varPassword IS NULL,0,1);

	  -- get hashed values 
	  IF (curEncryptionType = 'md5-username-passw') THEN
       SET hashedPass = UPPER(IF(passGiven, MD5(CONCAT(UPPER(curUsername),varPassword)), ''));
	  ELSEIF (curEncryptionType = 'SHA1') THEN
		  SET hashedPass = IF(passGiven, SHA1(varPassword), '');
    ELSE
      SET hashedPass = UPPER(IF(passGiven, SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(varPassword,'')),256), ''));
	  END IF;

	   -- Current Only SHA2
	  SET hashedNewPass = UPPER(SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(varNewPassword,'')),256));
	
   	  SET authPassOk = IF(curPass=hashedPass, 1, 0);
      
	  SET authWeight = IF(passGiven AND authPassOk, authWeight, authWeight+1);
   	 
   	  IF (authWeight > 0) THEN
   	  	IF (passGiven) THEN
   	  		SET statusCode = 1;
			LEAVE root;
		END IF;
   	 END IF;
 		
	  -- Check if New Password Contains Username
	  IF (playerPasswordDisallowUsernameEnabled) THEN
		IF (passGiven AND LOCATE(curUsername, varNewPassword) > 0) THEN
   	  		SET statusCode = 2;
			LEAVE root;
		END IF;
	END IF;

		  IF (historyNum > 0) THEN
			SELECT COUNT(*) INTO samehistoryPassCount
			FROM gaming_clients_password_changes 
			WHERE change_num > (curNumPassChanges - historyNum) 
				AND client_id = clientID
				AND hashed_password = hashedNewPass;
		  END IF;
	  
		  IF (samehistoryPassCount > 0) THEN
			  SET statusCode = 3;
			  LEAVE root;
		  ELSE 
				
		     -- Update to New password
			 -- Set Player Password to Not Expired
			 UPDATE gaming_clients 
			  SET `password`=IFNULL(hashedNewPass, `password`),
				   pass_hash_type = HashTypeID,
				   password_change_on_login = IF(varPassword IS NOT NULL, 0, password_change_on_login),
				   last_password_change_date = IF(varPassword IS NOT NULL, NOW(), last_password_change_date),
				   -- password_change_on_login = IF(varPassword IS NOT NULL AND varPassword!=curPass, varPasswordChangeOnLogin, 0),
				   num_password_changes=IF(varPassword IS NOT NULL AND varPassword!=curPass, num_password_changes+1, num_password_changes)
			  WHERE client_id=clientID; 
			  
			  IF (hashedNewPass IS NOT NULL) THEN
				  INSERT INTO gaming_clients_password_changes (client_id, change_num, hashed_password, salt)
				  SELECT client_id, num_password_changes, `password`, salt
				  FROM gaming_clients
				  WHERE client_id=clientID;
			  END IF;	
		  END IF;

		  CALL AuditLogAttributeChange('Password Change', clientID, 
			AuditLogNewGroup(@modifierEntityExtraId, @auditLogSessionId, clientID, 2, @modifierEntityType, NULL, NULL, clientID),
			'********', '********', NOW());

		 -- Remove Temporarily Lock (temporary_account_lock)
		  UPDATE gaming_player_restrictions
		  SET is_active = 0, removal_reason='Password Updated'
		  WHERE is_active = 1 AND client_id=clientID AND player_restriction_type_id=4;

END$$

DELIMITER ;

