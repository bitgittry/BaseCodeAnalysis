DROP procedure IF EXISTS `PlayLimitAdminRemoveLimit`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitAdminRemoveLimit`(intervalType VARCHAR(20), limitType VARCHAR(20), licenseType VARCHAR(20), channelType VARCHAR(20), gameID BIGINT, ignoreTimeWindow TINYINT(1), sessionID BIGINT)
BEGIN
  -- First Version 

  DECLARE increaseDays INT DEFAULT 0;
  DECLARE currentExists TINYINT(1) DEFAULT 0;
  SET @interval_type = intervalType;
  SET @limit_type = limitType;
  SET @session_id = sessionID;
  SET @license_type = licenseType;
  SET @channel_type = IFNULL(channelType, 'all');
  SET increaseDays = (SELECT value_int FROM gaming_settings WHERE name='PLAYING_LIMIT_INCREASE_OPERATOR_TIMEPERIOD_DAYS');
  SET @end_date = DATE_ADD(NOW(), INTERVAL increaseDays DAY);
  
  SELECT IF(COUNT(play_limit_admin_id) > 0, 1, 0) INTO currentExists FROM gaming_play_limits_admin AS gaming_play_limits
  JOIN gaming_play_limit_type ON 
    gaming_play_limit_type.name=@limit_type AND 
    gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id 
  JOIN gaming_interval_type ON 
    gaming_interval_type.name=@interval_type AND 
    gaming_interval_type.interval_type_id = gaming_play_limits.interval_type_id
  JOIN gaming_license_type ON 
    gaming_license_type.name=@license_type AND
    gaming_license_type.license_type_id=gaming_play_limits.license_type_id
  JOIN gaming_channel_types ON 
	gaming_channel_types.channel_type=@channel_type AND	
    gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id  
  WHERE gaming_play_limits.is_active=1 AND @interval_type = 'rolling' AND
    start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW())
	AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));

  UPDATE gaming_play_limits_admin AS gaming_play_limits
  JOIN gaming_play_limit_type ON 
    gaming_play_limit_type.name=@limit_type AND 
    gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id 
  JOIN gaming_interval_type ON 
    gaming_interval_type.name=@interval_type AND 
    gaming_interval_type.interval_type_id = gaming_play_limits.interval_type_id
  JOIN gaming_license_type ON 
    gaming_license_type.name=@license_type AND
    gaming_license_type.license_type_id=gaming_play_limits.license_type_id
  JOIN gaming_channel_types ON 
	gaming_channel_types.channel_type=@channel_type AND	
    gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
  SET gaming_play_limits.is_active=NOT ignoreTimeWindow, gaming_play_limits.end_date=@end_date, gaming_play_limits.session_id=@session_id
  WHERE gaming_play_limits.is_active=1 AND start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW())
	AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
  
  IF (@interval_type = 'rolling') THEN
	  IF (currentExists = 1) THEN
		UPDATE gaming_play_limits_admin AS gaming_play_limits
		  JOIN gaming_play_limit_type ON 
			gaming_play_limit_type.name=@limit_type AND 
			  gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id 
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
		  WHERE gaming_play_limits.is_active=1 AND end_date IS NULL
			AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
	  ELSE 
		UPDATE gaming_play_limits_admin AS gaming_play_limits
		  JOIN gaming_play_limit_type ON 
			gaming_play_limit_type.name=@limit_type AND 
			gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id 
		  JOIN gaming_interval_type ON 
			gaming_interval_type.name=@interval_type AND 
			gaming_interval_type.interval_type_id = gaming_play_limits.interval_type_id
		  JOIN gaming_license_type ON 
			gaming_license_type.name=@license_type AND
			gaming_license_type.license_type_id=gaming_play_limits.license_type_id
		  JOIN gaming_channel_types ON 
			gaming_channel_types.channel_type=@channel_type AND	
			gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
		  SET gaming_play_limits.is_active=NOT ignoreTimeWindow, gaming_play_limits.end_date=@end_date, gaming_play_limits.session_id=@session_id
		  WHERE gaming_play_limits.is_active=1 AND (end_date IS NULL OR end_date >= NOW())
			AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
	  END IF;
	  ELSE
		UPDATE gaming_play_limits_admin AS gaming_play_limits
		  JOIN gaming_play_limit_type ON 
			gaming_play_limit_type.name=@limit_type AND 
			  gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id 
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
		  WHERE gaming_play_limits.is_active=1 AND end_date IS NULL
			AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
  END IF;
  
  CALL PlayLimitAdminGetLimits(@interval_type, @limit_type, @license_type, @channel_type, gameID); 
  
END$$

DELIMITER ;

