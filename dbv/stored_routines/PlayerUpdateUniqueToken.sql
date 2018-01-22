DROP procedure IF EXISTS `PlayerUpdateUniqueToken`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdateUniqueToken`(clientID BIGINT, bypassCheck TINYINT(1), OUT statusCode INT)
root:BEGIN
  DECLARE minRange, maxRange, randToken BIGINT DEFAULT -1;
  DECLARE lockID BIGINT DEFAULT -1;
  DECLARE tokenLength INT DEFAULT -1;
  DECLARE tokenString VARCHAR(24);
  DECLARE tokenType VARCHAR(24) DEFAULT 'AlphaNumeric';
  DECLARE sameTokenCount INT DEFAULT 1;
	
  SELECT value_string INTO tokenType FROM gaming_settings WHERE name='PLAYER_TOKEN_TYPE';
  
  IF (NOT bypassCheck) THEN
    SELECT lock_id INTO lockID
    FROM gaming_locks
    WHERE name='player_update_unique_token' 
    FOR UPDATE;
   
    IF (lockID=-1) THEN
      SET statusCode=2;
      LEAVE root;
    END IF;
  END IF;
 
  IF (tokenType='Numeric') THEN
    SELECT value_long INTO minRange FROM gaming_settings WHERE name='PLAYER_TOKEN_MIN_INCLUSIVE';
    SELECT value_long INTO maxRange FROM gaming_settings WHERE name='PLAYER_TOKEN_MAX_NON_INCLUSIVE';
    SET tokenLength = CEILING(LOG10(maxRange));
    
    REPEAT
      SET randToken = (SELECT RandBigIntegerCO(minRange,maxRange));
      SET tokenString = LPAD(randToken,tokenLength,'0');
      
      SELECT COUNT(*) INTO sameTokenCount 
      FROM gaming_clients
      WHERE PIN2=tokenString;
    UNTIL sameTokenCount=0
    END REPEAT;
  ELSE
    REPEAT
      SET tokenString = SUBSTRING(UUID(),1, 8);
      
      IF (bypassCheck) THEN
        SET sameTokenCount=0;
      ELSE
        SELECT COUNT(*) INTO sameTokenCount FROM gaming_clients WHERE PIN2=tokenString;
      END IF;
    UNTIL sameTokenCount=0
    END REPEAT;
  END IF;
    
  UPDATE gaming_clients SET PIN2=tokenString WHERE client_id=clientID;
  
  SELECT tokenString AS PIN2;
  
  SET statusCode=0;
END root$$

DELIMITER ;

