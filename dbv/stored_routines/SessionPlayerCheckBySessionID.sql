DROP procedure IF EXISTS `SessionPlayerCheckBySessionID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionPlayerCheckBySessionID`(
  sessionID BIGINT, serverID BIGINT, componentID BIGINT, ignoreSessionExpiry TINYINT(1), extendSessionExpiry TINYINT(1), OUT statusCode INT)
root: BEGIN

  DECLARE clientID,clientStatID,sessionCheckID,currencyID,clientSegmentID BIGINT DEFAULT -1;
  DECLARE currentExpiryDate, newExpiryDate DATETIME; 
  DECLARE currentBalance DECIMAL(18,5);
  DECLARE currencyCode VARCHAR(3);
  DECLARE sessionGUID VARCHAR(80);
  DECLARE isSuspicious, isTestPlayer TINYINT(1) DEFAULT 0;
  DECLARE platformTypeID, channelTypeID INT DEFAULT NULL;
  
  SELECT sessions_main.extra_id, session_id, session_guid, date_expiry, sessions_main.platform_type_id
  INTO clientID,sessionCheckID,sessionGUID, currentExpiryDate, platformTypeID
  FROM sessions_main 
  WHERE sessions_main.session_id=sessionID AND (ignoreSessionExpiry=1 OR (sessions_main.status_code=1 AND sessions_main.date_expiry > NOW())) AND sessions_main.active=1;
  
  IF (clientID = -1) THEN
    SET statusCode = 1;
    LEAVE root;
  ELSE 
  
    SELECT client_stat_id, (current_real_balance+current_bonus_balance+current_bonus_win_locked_balance) AS current_balance, gaming_currency.currency_code, gaming_currency.currency_id, client_segment_id, is_suspicious, is_test_player 
      INTO clientStatID, currentBalance, currencyCode, currencyID, clientSegmentID, isSuspicious, isTestPlayer   
    FROM gaming_clients
    STRAIGHT_JOIN gaming_client_stats ON 
		gaming_clients.client_id=clientID AND 
		gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1
    STRAIGHT_JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id;
      
    IF (clientStatID = -1) THEN 
      SET statusCode = 2;
      LEAVE root;
    ELSE
      IF (extendSessionExpiry) THEN
        SELECT DATE_ADD(NOW(), INTERVAL sessions_defaults.expiry_duration MINUTE) INTO newExpiryDate 
        FROM sessions_defaults WHERE active=1 AND server_id=serverID AND component_id=componentID;
        
        UPDATE sessions_main SET date_expiry=newExpiryDate 
        WHERE session_id=sessionID AND active=1 AND status_code=1; 
        
        
      END IF;
      
      CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, platformTypeID, @platformType, channelTypeID, @channelType);

	  SELECT clientID AS client_id, clientStatID AS client_stat_id, serverID AS server_id, sessionID AS session_id, sessionGUID AS session_guid, IF (extendSessionExpiry, newExpiryDate, currentExpiryDate) AS expiry_date,
           currentBalance AS current_balance, currencyCode AS currency_code, currencyID AS currency_id, clientSegmentID AS client_segment_id, isSuspicious AS is_suspicious, isTestPlayer AS is_test_player,
			platformTypeID AS platform_type_id, @platformType AS platform_type, channelTypeID AS channel_type_id, @channelType AS channel_type;  

      SET statusCode = 0;
    END IF;
  END IF;
  
END root$$

DELIMITER ;

