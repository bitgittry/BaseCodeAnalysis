DROP procedure IF EXISTS `PlayLimitRemoveLimit`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitRemoveLimit`(clientStatID BIGINT, intervalType VARCHAR(20), limitType VARCHAR(20), licenseType VARCHAR(20), channelType VARCHAR(20), gameID BIGINT, ignoreTimeWindow TINYINT(1), sessionID BIGINT,modifierEntityType VARCHAR(45))
BEGIN
  -- Added GameID
  -- Added Audit Log

  DECLARE pushNotificationsEnabled TINYINT(1) DEFAULT 0;
  DECLARE increaseDays INT DEFAULT 0;
  DECLARE notificationEventTypeId INT;
  DECLARE auditLogGroupId, clientID, userID BIGINT DEFAULT -1;
  DECLARE currentValue DECIMAL(18, 5) DEFAULT NULL;
  DECLARE licenseTypeDisplayName VARCHAR(50);
  DECLARE limitTypeDisplayName VARCHAR(50);
  DECLARE channelTypeDisplayName VARCHAR(100);
  DECLARE gameDisplayName VARCHAR(256);

  SET @client_stat_id = clientStatID;
  SET @interval_type = intervalType;
  SET @limit_type = limitType;
  SET @session_id = sessionID;
  SET @license_type = licenseType;
  SET @channel_type = IFNULL(channelType, 'all');
  SET increaseDays = (SELECT value_int FROM gaming_settings WHERE name='PLAYING_LIMIT_INCREASE_OPERATOR_TIMEPERIOD_DAYS');
  
  SET @end_date = DATE_ADD(NOW(), INTERVAL increaseDays DAY);

  SELECT value_bool INTO pushNotificationsEnabled FROM gaming_settings WHERE name='NOTIFICATION_ENABLED';
  SELECT notification_event_type_id INTO notificationEventTypeId FROM notifications_event_types WHERE event_name = 'PlayLimitPlayerUpdate';
  SELECT client_id INTO clientID FROM gaming_client_stats WHERE client_stat_id=@client_stat_id;
  SELECT display_name INTO limitTypeDisplayName FROM gaming_play_limit_type WHERE name = @limit_type;
  SELECT user_id INTO userID FROM sessions_main WHERE session_id = @session_id;
  SELECT game_description INTO gameDisplayName FROM gaming_games WHERE game_id = gameID;
  SELECT friendly_name INTO channelTypeDisplayName FROM gaming_channel_types WHERE channel_type = @channel_type;
  SELECT friendly_name INTO licenseTypeDisplayName FROM gaming_license_type WHERE `name` = @license_type;

	IF pushNotificationsEnabled THEN 
	-- Notification BEGIN
	INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing)
		SELECT notificationEventTypeId, play_limit_id, @client_stat_id, 0 
	FROM gaming_play_limits
	  JOIN gaming_play_limit_type ON 
    gaming_play_limit_type.name=@limit_type AND 
    gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id 
  JOIN gaming_client_stats ON 
    gaming_client_stats.client_stat_id=@client_stat_id AND 
    gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id 
  JOIN gaming_interval_type ON 
    gaming_interval_type.name=@interval_type AND 
    gaming_interval_type.interval_type_id = gaming_play_limits.interval_type_id
  JOIN gaming_license_type ON 
    gaming_license_type.name=@license_type AND
    gaming_license_type.license_type_id=gaming_play_limits.license_type_id
  JOIN gaming_channel_types ON 
	gaming_channel_types.channel_type=@channel_type AND	
    gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id 
  WHERE gaming_play_limits.is_active=1 AND ((start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW())) OR end_date IS NULL) AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID))
  LIMIT 1
  ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing = 0;
		
	-- Notification END
 END IF;

  -- Select old value of the current limit
  SELECT limit_amount INTO currentValue FROM gaming_play_limits
  JOIN gaming_play_limit_type ON 
    gaming_play_limit_type.name=@limit_type AND 
    gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id 
  JOIN gaming_client_stats ON 
    gaming_client_stats.client_stat_id=@client_stat_id AND 
    gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id 
  JOIN gaming_interval_type ON 
    gaming_interval_type.name=@interval_type AND 
    gaming_interval_type.interval_type_id = gaming_play_limits.interval_type_id
  JOIN gaming_license_type ON 
    gaming_license_type.name=@license_type AND
    gaming_license_type.license_type_id=gaming_play_limits.license_type_id
  JOIN gaming_channel_types ON 
	gaming_channel_types.channel_type=@channel_type AND	
    gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id 
  WHERE gaming_play_limits.is_active=1 AND start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW()) AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));

  IF currentValue IS NOT NULL THEN
	SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 5, modifierEntityType, NULL, NULL, clientID);

    CALL AuditLogAttributeChange(
		CONCAT(CASE WHEN gameDisplayName IS NOT NULL THEN CONCAT(gameDisplayName, ': ') ELSE licenseTypeDisplayName END, 
			CASE WHEN channelTypeDisplayName IS NOT NULL THEN CONCAT(channelTypeDisplayName, ': ') ELSE '' END, 
			CASE WHEN @limit_type NOT IN ('DIRECT_BLOCK_LIMIT','TIME_LIMIT') THEN CONCAT(@interval_type, ' ') ELSE '' END, limitTypeDisplayName), clientID, auditLogGroupId, NULL, currentValue, CASE WHEN NOT ignoreTimeWindow THEN @end_date ELSE NOW() END);
    SET currentValue = NULL;
  END IF;

  -- Deactivate current limit or set the end date
  UPDATE gaming_play_limits
  JOIN gaming_play_limit_type ON 
    gaming_play_limit_type.name=@limit_type AND 
    gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id 
  JOIN gaming_client_stats ON 
    gaming_client_stats.client_stat_id=@client_stat_id AND 
    gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id 
  JOIN gaming_interval_type ON 
    gaming_interval_type.name=@interval_type AND 
    gaming_interval_type.interval_type_id = gaming_play_limits.interval_type_id
  JOIN gaming_license_type ON 
    gaming_license_type.name=@license_type AND
    gaming_license_type.license_type_id=gaming_play_limits.license_type_id
  JOIN gaming_channel_types ON 
	gaming_channel_types.channel_type=@channel_type AND	
    gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
  SET gaming_play_limits.is_active=NOT ignoreTimeWindow, gaming_play_limits.end_date= CASE WHEN NOT ignoreTimeWindow THEN @end_date ELSE NOW() END, gaming_play_limits.session_id=@session_id
  WHERE gaming_play_limits.is_active=1 AND start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW()) AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));  
  
  -- Get old value of future limit
  SELECT limit_amount INTO currentValue FROM gaming_play_limits
    JOIN gaming_play_limit_type ON 
      gaming_play_limit_type.name=@limit_type AND 
      gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id 
    JOIN gaming_client_stats ON 
      gaming_client_stats.client_stat_id=@client_stat_id AND 
      gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id
    JOIN gaming_interval_type ON 
      gaming_interval_type.name=@interval_type AND 
      gaming_interval_type.interval_type_id = gaming_play_limits.interval_type_id
    JOIN gaming_license_type ON 
      gaming_license_type.name=@license_type AND
      gaming_license_type.license_type_id=gaming_play_limits.license_type_id
	JOIN gaming_channel_types ON 
		gaming_channel_types.channel_type=@channel_type AND	
		gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id 
  WHERE gaming_play_limits.is_active=1 AND end_date IS NULL AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));

  IF currentValue IS NOT NULL THEN
	IF auditLogGroupId IS NULL THEN
		SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 5, modifierEntityType, NULL, NULL, clientID);
	END IF;

    CALL AuditLogAttributeChange(
			CONCAT(CASE WHEN gameDisplayName IS NOT NULL THEN CONCAT(gameDisplayName, ': ') ELSE licenseTypeDisplayName END, 
				CASE WHEN channelTypeDisplayName IS NOT NULL THEN CONCAT(channelTypeDisplayName, ': ') ELSE '' END, 
				CASE WHEN @limit_type NOT IN ('DIRECT_BLOCK_LIMIT','TIME_LIMIT') THEN CONCAT(@interval_type, ' ') ELSE '' END, 'Future ', limitTypeDisplayName), clientID, auditLogGroupId, NULL, currentValue, NOW());
  END IF;
 
  -- Deactivate future limits 
  UPDATE gaming_play_limits
    JOIN gaming_play_limit_type ON 
      gaming_play_limit_type.name=@limit_type AND 
      gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id 
    JOIN gaming_client_stats ON 
      gaming_client_stats.client_stat_id=@client_stat_id AND 
      gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id
    JOIN gaming_interval_type ON 
      gaming_interval_type.name=@interval_type AND 
      gaming_interval_type.interval_type_id = gaming_play_limits.interval_type_id
    JOIN gaming_license_type ON  
      gaming_license_type.name=@license_type AND
      gaming_license_type.license_type_id=gaming_play_limits.license_type_id
	JOIN gaming_channel_types ON 
	gaming_channel_types.channel_type=@channel_type AND	
    gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
  SET gaming_play_limits.is_active=0, gaming_play_limits.session_id=@session_id
  WHERE gaming_play_limits.is_active=1 AND end_date IS NULL AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
  
  CALL PlayLimitGetLimits(NULL, @client_stat_id, @interval_type, @limit_type, @license_type, @channel_type, gameID);
  
END$$

DELIMITER ;

