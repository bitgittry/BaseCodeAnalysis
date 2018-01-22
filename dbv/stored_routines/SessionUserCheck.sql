DROP procedure IF EXISTS `SessionUserCheck`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionUserCheck`(sessionGUID VARCHAR(80), serverID BIGINT, componentID BIGINT, OUT statusCode INT)
root:BEGIN

 
  DECLARE userID,sessionID,extraID BIGINT DEFAULT -1;
  DECLARE newExpiryDate DATETIME; 
  DECLARE platformTypeID, channelTypeID INT DEFAULT NULL;

  SELECT sessions_main.user_id, session_id, sessions_main.extra_id, sessions_main.platform_type_id INTO userID,sessionID, extraID, platformTypeID 
  FROM sessions_main 
  JOIN users_main ON  
    sessions_main.session_guid=sessionGUID AND sessions_main.active=1 AND sessions_main.status_code=1 AND sessions_main.date_expiry > NOW() AND 
    sessions_main.user_id=users_main.user_id AND users_main.active=1 AND users_main.is_disabled=0 AND sessions_main.session_type=1;
        
  IF (userID = -1) THEN
    SET statusCode = 1;
    LEAVE root;
  ELSE 
    
    SELECT DATE_ADD(NOW(), INTERVAL sessions_defaults.user_expirey_duration MINUTE) INTO newExpiryDate 
    FROM sessions_defaults WHERE active=1 AND server_id=serverID AND component_id=componentID;
    
    UPDATE sessions_main SET date_expiry=newExpiryDate 
    WHERE session_id=sessionID AND active=1 AND status_code=1; 
        
    SELECT userID AS user_id, serverID AS server_id, sessionID AS session_id, sessionGUID AS session_guid; 
    
    SELECT attr_name, attr_value 
    FROM sessions_attributes 
    WHERE session_id=sessionID AND active=1; 
      
    CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, platformTypeID, @platformType, channelTypeID, @channelType);

    SELECT gaming_clients.client_id, gaming_client_stats.client_stat_id, serverID AS server_id, sessionID AS session_id, sessionGUID AS session_guid, 
      (current_real_balance+current_bonus_balance+current_bonus_win_locked_balance) AS current_balance, gaming_currency.currency_code, gaming_currency.currency_id,
      gaming_clients.client_segment_id,gaming_clients.is_suspicious,gaming_clients.is_test_player, platformTypeID AS platform_type_id, @platformType AS platform_type, channelTypeID AS channel_type_id, @channelType AS channel_type
    FROM gaming_clients    
    JOIN gaming_client_stats ON gaming_clients.client_id=extraID AND gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1 
    JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id;    
   
    SET statusCode = 0;
  END IF;
  
END$$

DELIMITER ;