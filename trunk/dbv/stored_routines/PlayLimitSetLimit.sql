DROP procedure IF EXISTS `PlayLimitSetLimit`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitSetLimit`(
  clientStatID BIGINT, intervalType VARCHAR(20), limitType VARCHAR(20), licenseType VARCHAR(20), channelType VARCHAR(20), 
  gameID BIGINT, varAmount DECIMAL(18, 5), ignoreTimeWindow TINYINT(1), sessionID BIGINT, modifierEntityType VARCHAR(45), OUT statusCode INT)
root: BEGIN

  -- Added GameID 
  -- Added push notifications
  -- Added logging the changes to Audit Logs
  
  DECLARE pushNotificationsEnabled TINYINT(1) DEFAULT 0;
  DECLARE increaseDays, noOfDays INT DEFAULT 0;
  DECLARE notificationEventTypeId INT;
  DECLARE auditLogGroupId, clientID, userID BIGINT DEFAULT -1;
  DECLARE effectiveDate DATETIME DEFAULT NOW();
  DECLARE currentValue DECIMAL(18, 5) DEFAULT NULL;
  DECLARE futureValue DECIMAL(18, 5) DEFAULT NULL;
  DECLARE tempLimitAmountValue DECIMAL(18, 5) DEFAULT NULL;
  DECLARE limitTypeDisplayName VARCHAR(80);
  DECLARE licenseTypeDisplayName VARCHAR(50);
  DECLARE channelTypeDisplayName VARCHAR(100);
  DECLARE gameDisplayName VARCHAR(256);
  SET @limit_type = limitType;
  SET @interval_type = intervalType;
  SET @client_stat_id = clientStatID;
  SET @session_id = sessionID;
  SET @license_type = licenseType;
  SET @channel_type = IFNULL(channelType, 'all');
  SET @currentAmount = 0;
  SET @rowCount = 0;
  SET @vNow = NOW(); 

  SELECT gs1.value_bool, gs2.value_int, gs3.value_int INTO pushNotificationsEnabled, increaseDays, noOfDays
  FROM gaming_settings AS gs1
  LEFT JOIN gaming_settings AS gs2 ON gs2.name='PLAYING_LIMIT_INCREASE_OPERATOR_TIMEPERIOD_DAYS'
  LEFT JOIN gaming_settings AS gs3 ON gs3.name='ROLLING_LIMIT_AMOUNT_DEFAULT'
  WHERE gs1.name='NOTIFICATION_ENABLED';
  
  SELECT clientStatID INTO @clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=@client_stat_id FOR UPDATE;
  SELECT notification_event_type_id INTO notificationEventTypeId FROM notifications_event_types WHERE event_name = 'PlayLimitPlayerUpdate';
  SELECT clientStatID, client_id INTO @clientStatIDCheck, clientID FROM gaming_client_stats WHERE client_stat_id=@client_stat_id FOR UPDATE;
  
  SELECT SUBSTR(game_description, 0, 180) INTO gameDisplayName FROM gaming_games WHERE game_id = gameID;
  SELECT friendly_name INTO channelTypeDisplayName FROM gaming_channel_types WHERE channel_type = @channel_type;	
  SELECT friendly_name INTO licenseTypeDisplayName FROM gaming_license_type WHERE `name` = @license_type;

  SELECT @rowCount+1, limit_amount INTO @rowCount, @currentAmount 
  FROM gaming_play_limits 
  JOIN gaming_client_stats ON 
    gaming_client_stats.client_stat_id=@client_stat_id AND
    gaming_play_limits.client_stat_id=gaming_client_stats.client_stat_id 
  JOIN gaming_interval_type ON 
    gaming_interval_type.name=@interval_type AND
    gaming_interval_type.interval_type_id=gaming_play_limits.interval_type_id
  JOIN gaming_license_type ON 
    gaming_license_type.name=@license_type AND
    gaming_license_type.license_type_id=gaming_play_limits.license_type_id
  JOIN gaming_play_limit_type ON 
    gaming_play_limit_type.name=@limit_type AND
    gaming_play_limit_type.play_limit_type_id = gaming_play_limits.play_limit_type_id
  JOIN gaming_channel_types ON 
	gaming_channel_types.channel_type=@channel_type AND	
    gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
  WHERE gaming_play_limits.is_active=1 AND start_date <= @vNow AND (end_date IS NULL OR end_date >= @vNow) AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
  
  
  SET @ApplyInNextTimePeriod = 0;
  IF (@rowCount = 1) THEN
    IF (varAMount > @currentAmount) THEN
      SET @ApplyInNextTimePeriod = 1;
    END IF;
  ELSE 
    
    IF (@rowCount > 1) THEN
      SET statusCode=1;
      LEAVE root;
    END IF;
  END IF;
   
  SET @ApplyInNextTimePeriod=(@ApplyInNextTimePeriod AND NOT ignoreTimeWindow); 
   
  IF (@ApplyInNextTimePeriod = 1) THEN    
    SET @end_date = DATE_SUB(DATE_ADD(@vNow, INTERVAL increaseDays DAY), INTERVAL 1 SECOND);  
    
    UPDATE gaming_play_limits 
      JOIN gaming_play_limit_type ON 
        gaming_play_limit_type.name=@limit_type AND  
        gaming_play_limits.play_limit_type_id=gaming_play_limit_type.play_limit_type_id 
      JOIN gaming_license_type ON 
        gaming_license_type.name=@license_type AND
        gaming_license_type.license_type_id=gaming_play_limits.license_type_id
      JOIN gaming_client_stats ON 
        gaming_client_stats.client_stat_id=@client_stat_id AND
        gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id
      JOIN gaming_interval_type ON 
        gaming_interval_type.name=@interval_type AND
        gaming_interval_type.interval_type_id=gaming_play_limits.interval_type_id
	JOIN gaming_channel_types ON 
		gaming_channel_types.channel_type=@channel_type AND	
		gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
    SET end_date=@end_date, gaming_play_limits.session_id=@session_id
    WHERE
      gaming_play_limits.is_active=1 AND start_date <= @vNow AND (end_date IS NULL OR end_date >= @vNow) 
	  AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
    
    -- Select old value

    SELECT limit_amount INTO futureValue FROM gaming_play_limits
      JOIN gaming_play_limit_type ON 
        gaming_play_limits.is_active=1  AND
        gaming_play_limit_type.name=@limit_type AND
        gaming_play_limits.play_limit_type_id=gaming_play_limit_type.play_limit_type_id 
      JOIN gaming_license_type ON 
        gaming_license_type.name=@license_type AND
        gaming_license_type.license_type_id=gaming_play_limits.license_type_id
      JOIN gaming_client_stats ON 
        gaming_client_stats.client_stat_id=@client_stat_id AND
        gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id 
      JOIN gaming_interval_type ON 
        gaming_interval_type.name=@interval_type AND
        gaming_interval_type.interval_type_id=gaming_play_limits.interval_type_id
	  JOIN gaming_channel_types ON 
		gaming_channel_types.channel_type=@channel_type AND	
		gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
    WHERE gaming_play_limits.end_date IS NULL
	 AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));

    -- Deactivate current future limit

    UPDATE gaming_play_limits
      JOIN gaming_play_limit_type ON 
        gaming_play_limits.is_active=1  AND
        gaming_play_limit_type.name=@limit_type AND
        gaming_play_limits.play_limit_type_id=gaming_play_limit_type.play_limit_type_id 
      JOIN gaming_license_type ON 
        gaming_license_type.name=@license_type AND
        gaming_license_type.license_type_id=gaming_play_limits.license_type_id
      JOIN gaming_client_stats ON 
        gaming_client_stats.client_stat_id=@client_stat_id AND
        gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id 
      JOIN gaming_interval_type ON 
        gaming_interval_type.name=@interval_type AND
        gaming_interval_type.interval_type_id=gaming_play_limits.interval_type_id
	  JOIN gaming_channel_types ON 
		gaming_channel_types.channel_type=@channel_type AND	
		gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
    SET gaming_play_limits.is_active=0, gaming_play_limits.session_id=@session_id
    WHERE gaming_play_limits.end_date IS NULL
	 AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
    
    SET @start_date = DATE_ADD(@end_date, INTERVAL 1 SECOND);
    SET effectiveDate = @start_date;

    INSERT INTO gaming_play_limits (play_limit_type_id, interval_type_id, limit_amount, create_date, start_date, client_stat_id, license_type_id, channel_type_id, game_id, is_active, session_id, no_of_days)
    SELECT gaming_play_limit_type.play_limit_type_id, gaming_interval_type.interval_type_id, varAmount, @vNow, @start_date, gaming_client_stats.client_stat_id, gaming_license_type.license_type_id, gaming_channel_types.channel_type_id, gameID, 1, @session_id, IF(@limit_type='BET_AMOUNT_LIMIT' AND @interval_type='Rolling', noOfDays, NULL)
    FROM gaming_client_stats            
    JOIN gaming_play_limit_type ON 
      gaming_client_stats.client_stat_id=@client_stat_id AND 
      gaming_play_limit_type.name=@limit_type
    JOIN gaming_license_type ON gaming_license_type.name=@license_type
    JOIN gaming_interval_type ON gaming_interval_type.name=@interval_type
    JOIN gaming_channel_types ON gaming_channel_types.channel_type=@channel_type;
    
  ELSE
    
	-- Retrieving old value of current limit 
    SELECT limit_amount INTO currentValue FROM gaming_play_limits
    JOIN gaming_play_limit_type ON
      gaming_play_limits.is_active=1 AND
      gaming_play_limit_type.name=@limit_type AND
      gaming_play_limits.play_limit_type_id=gaming_play_limit_type.play_limit_type_id 
    JOIN gaming_license_type ON 
      gaming_license_type.name=@license_type AND
      gaming_license_type.license_type_id=gaming_play_limits.license_type_id
    JOIN gaming_client_stats ON 
      gaming_client_stats.client_stat_id=@client_stat_id AND
      gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id 
    JOIN gaming_interval_type ON 
      gaming_interval_type.name=@interval_type AND
      gaming_interval_type.interval_type_id=gaming_play_limits.interval_type_id 
    JOIN gaming_channel_types ON 
		gaming_channel_types.channel_type=@channel_type AND	
		gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
	WHERE ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID))
    AND gaming_play_limits.end_date IS NOT NULL;  

	-- Retrieving old value of future limit if the current limit value was retrieved otherwise set the current limit value
    
	SELECT limit_amount INTO tempLimitAmountValue FROM gaming_play_limits
    JOIN gaming_play_limit_type ON
      gaming_play_limits.is_active=1 AND
      gaming_play_limit_type.name=@limit_type AND
      gaming_play_limits.play_limit_type_id=gaming_play_limit_type.play_limit_type_id 
    JOIN gaming_license_type ON 
      gaming_license_type.name=@license_type AND
      gaming_license_type.license_type_id=gaming_play_limits.license_type_id
    JOIN gaming_client_stats ON 
      gaming_client_stats.client_stat_id=@client_stat_id AND
      gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id 
    JOIN gaming_interval_type ON 
      gaming_interval_type.name=@interval_type AND
      gaming_interval_type.interval_type_id=gaming_play_limits.interval_type_id 
    JOIN gaming_channel_types ON 
		gaming_channel_types.channel_type=@channel_type AND	
		gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
	WHERE ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID))
    AND (((currentValue IS NULL AND gaming_play_limits.end_date IS NULL) AND gaming_play_limits.end_date IS NULL) OR (currentValue IS NULL AND gaming_play_limits.end_date IS NOT NULL));  
    
	IF currentValue IS NULL THEN
		SET currentValue = tempLimitAmountValue;
	ELSE
		SET futureValue = tempLimitAmountValue;
	END IF;

    -- Deactivating current limit
    UPDATE gaming_play_limits
    JOIN gaming_play_limit_type ON
      gaming_play_limits.is_active=1 AND
      gaming_play_limit_type.name=@limit_type AND
      gaming_play_limits.play_limit_type_id=gaming_play_limit_type.play_limit_type_id 
    JOIN gaming_license_type ON 
      gaming_license_type.name=@license_type AND
      gaming_license_type.license_type_id=gaming_play_limits.license_type_id
    JOIN gaming_client_stats ON 
      gaming_client_stats.client_stat_id=@client_stat_id AND
      gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id 
    JOIN gaming_interval_type ON 
      gaming_interval_type.name=@interval_type AND
      gaming_interval_type.interval_type_id=gaming_play_limits.interval_type_id 
    JOIN gaming_channel_types ON 
		gaming_channel_types.channel_type=@channel_type AND	
		gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
    SET gaming_play_limits.is_active=0, gaming_play_limits.session_id=@session_id
	WHERE ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
      
    
    INSERT INTO gaming_play_limits (play_limit_type_id, interval_type_id, limit_amount, create_date, start_date, end_date, client_stat_id, license_type_id, channel_type_id, game_id, is_active, session_id, no_of_days)
    SELECT 
      gaming_play_limit_type.play_limit_type_id, gaming_interval_type.interval_type_id, varAmount, @vNow, @vNow, 
      IF(@limit_type='DIRECT_BLOCK_LIMIT',TIMESTAMPADD(MINUTE,varAmount,@vNow),NULL), gaming_client_stats.client_stat_id, gaming_license_type.license_type_id, gaming_channel_types.channel_type_id, gameID, 1, @session_id, IF(@limit_type='BET_AMOUNT_LIMIT' AND @interval_type='Rolling', noOfDays, NULL)
    FROM gaming_client_stats            
    JOIN gaming_play_limit_type ON 
      gaming_client_stats.client_stat_id=@client_stat_id AND
      gaming_play_limit_type.name=@limit_type 
    JOIN gaming_license_type ON gaming_license_type.name=@license_type
    JOIN gaming_interval_type ON gaming_interval_type.name=@interval_type
    JOIN gaming_channel_types ON gaming_channel_types.channel_type=@channel_type;
  END IF;
  
    -- Audit log
    SELECT user_id INTO userID FROM sessions_main WHERE session_id = @session_id;
    SELECT display_name INTO limitTypeDisplayName FROM gaming_play_limit_type WHERE name = @limit_type;
    SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 5, modifierEntityType, NULL, NULL, clientID);

	IF currentValue IS NOT NULL OR @ApplyInNextTimePeriod = 0 THEN
	CALL AuditLogAttributeChange(
			CONCAT(CASE WHEN gameDisplayName IS NOT NULL THEN CONCAT(gameDisplayName, ': ') ELSE licenseTypeDisplayName END, 
			CASE WHEN channelTypeDisplayName IS NOT NULL THEN CONCAT(channelTypeDisplayName, ': ') ELSE '' END, 
			CASE WHEN @limit_type NOT IN ('DIRECT_BLOCK_LIMIT','TIME_LIMIT') THEN CONCAT(@interval_type, ' ') ELSE '' END, 
			limitTypeDisplayName), 
			clientID, auditLogGroupId, varAmount, currentValue, effectiveDate);
	END IF; 
    IF futureValue IS NOT NULL OR @ApplyInNextTimePeriod = 1 THEN
		CALL AuditLogAttributeChange(
			CONCAT(CASE WHEN gameDisplayName IS NOT NULL THEN CONCAT(gameDisplayName, ': ') ELSE licenseTypeDisplayName END, 
			CASE WHEN channelTypeDisplayName IS NOT NULL THEN CONCAT(channelTypeDisplayName, ': ') ELSE '' END, 
			CASE WHEN @limit_type NOT IN ('DIRECT_BLOCK_LIMIT','TIME_LIMIT') THEN CONCAT(@interval_type, ' ') ELSE '' END, 'Future ', 
			limitTypeDisplayName), 
			clientID, auditLogGroupId, CASE @ApplyInNextTimePeriod WHEN 1 THEN varAmount ELSE NULL END, futureValue, effectiveDate);
	END IF;

	-- Notification BEGIN 

	IF pushNotificationsEnabled THEN 
	
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing)
			SELECT notificationEventTypeId, play_limit_id, @client_stat_id, 0 
		FROM gaming_play_limits
		  JOIN gaming_client_stats ON  
			gaming_client_stats.client_stat_id=@client_stat_id AND
			gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id
		  JOIN gaming_play_limit_type ON gaming_play_limit_type.name=@limit_type AND gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id
		  JOIN gaming_interval_type ON gaming_interval_type.name=@interval_type AND gaming_play_limits.interval_type_id = gaming_interval_type.interval_type_id
		  JOIN gaming_license_type ON gaming_license_type.name=@license_type AND gaming_license_type.license_type_id=gaming_play_limits.license_type_id
		  JOIN gaming_channel_types ON gaming_channel_types.channel_type=@channel_type AND gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
          LEFT JOIN gaming_games ON gaming_play_limits.game_id=gaming_games.game_id
		  LEFT JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
		WHERE gaming_play_limits.is_active=1 AND (end_date IS NULL OR end_date >= @vNow) AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID))
		LIMIT 1
		ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing = 0;

		-- Notification END

	END IF;

  CALL PlayLimitGetLimits(NULL, @client_stat_id, @interval_type, @limit_type, @license_type, @channel_type, gameID);
 
  SET statusCode = 0;
END root$$

DELIMITER ;
