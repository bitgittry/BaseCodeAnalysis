DROP procedure IF EXISTS `PlayerCreateVerificationToken`;

DELIMITER $$

CREATE PROCEDURE `PlayerCreateVerificationToken`(clientID BIGINT, actionTypeName VARCHAR(80), verificationCode VARCHAR(45), verificationToken VARCHAR(45), curVerificationTokenID BIGINT(20), OUT statusCode INT, OUT tokenID BIGINT)
root:BEGIN
	DECLARE actionTypeID INT DEFAULT -1;
    DECLARE requiresVerification TINYINT(1) DEFAULT 0;
    DECLARE expirationSeconds BIGINT(20) DEFAULT 300;
    DECLARE expirationDate DATETIME;
    
    
    SELECT action_type_id, requires_verification
    INTO actionTypeID, requiresVerification
    FROM gaming_verification_action_types 
    WHERE action_type_name = actionTypeName;
    
   	IF (requiresVerification=0) THEN
    SET statusCode=1;
    LEAVE root;
    END IF;
    
    
    -- Check if Token if need to Generate New Token for Existing Token
    IF(curVerificationTokenID > -1) THEN
		UPDATE gaming_verification_tokens
		SET is_active=0, is_already_processed=1
        WHERE verification_token_id = curVerificationTokenID;
		END IF;
        
    -- Create New Token  
    SELECT expiration_seconds INTO expirationSeconds FROM gaming_verification_action_types WHERE action_type_name = actionTypeName;
    
    SET expirationDate = DATE_ADD(NOW(), INTERVAL expirationSeconds SECOND);
    
    
    INSERT INTO gaming_verification_tokens (`verification_code`,`verification_token`,`request_timestamp`,`expiration_timestamp`,`is_active`,`is_verified`,`verification_timestamp`,`action_type_id`,`client_id`)
    VALUES (verificationCode,verificationToken,NOW(),expirationDate,1,0,NULL,actionTypeID,clientID);

	SET statusCode=0;
	SET tokenID=LAST_INSERT_ID(); 

END root$$

DELIMITER ;