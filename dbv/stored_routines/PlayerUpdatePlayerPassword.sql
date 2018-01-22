DROP procedure IF EXISTS `PlayerUpdatePlayerPassword`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdatePlayerPassword`(clientID BIGINT, varPassword VARCHAR(250), varPasswordChangeOnLogin TINYINT(1), isPlayer TINYINT(1), userID BIGINT)
BEGIN

  -- Inserting in gaming_clients_password_changes if password was changed
  -- Updating num_password_changes if password was changed  
  -- Always updating last_password_change_date  

  DECLARE HashTypeID INT;
  DECLARE curPassword VARCHAR(255);
  DECLARE numPasswordChanges INT DEFAULT 0;
  DECLARE auditLogGroupId BIGINT;
  DECLARE modifierEntityType VARCHAR(45) DEFAULT IF(isPlayer, 'Player', 'User');
  
  SELECT pass_hash_type_id INTO HashTypeID FROM gaming_clients_pass_hash_type WHERE is_default=1;
  SELECT IFNULL(password,'') INTO curPassword FROM gaming_clients WHERE client_id=clientID;
 
  UPDATE gaming_clients 
  SET  password=IFNULL(varPassword, password),
	   pass_hash_type = HashTypeID,
	   last_password_change_date = IF(varPassword IS NOT NULL, NOW(), last_password_change_date),
	   password_change_on_login = IF(varPassword IS NOT NULL AND varPassword!=curPassword, varPasswordChangeOnLogin, 0),
	   num_password_changes=IF(varPassword IS NOT NULL AND varPassword!=curPassword, num_password_changes+1, num_password_changes)
  WHERE client_id=clientID; 

  UPDATE gaming_clients_login_attempts_totals
  SET last_consecutive_bad=0, temporary_locking_bad_attempts=0
  WHERE client_id=clientID; 

  IF (varPassword IS NOT NULL AND varPassword!=curPassword) THEN
	  INSERT INTO gaming_clients_password_changes (client_id, change_num, hashed_password, salt)
	  SELECT client_id, num_password_changes, password, salt
	  FROM gaming_clients
	  WHERE client_id=clientID;
		
	SET auditLogGroupId = AuditLogNewGroup(userID, NULL, clientID, 2, modifierEntityType, NULL, NULL, clientID);
	CALL AuditLogAttributeChange('Password Change', clientID, auditLogGroupId, '********', '********', NOW());
  END IF;
  
END$$

DELIMITER ;

