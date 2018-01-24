DROP procedure IF EXISTS `PlayLimitGetPlayerStatus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitGetPlayerStatus`(
  clientStatID BIGINT, licenseType VARCHAR(20), channelType VARCHAR(20), allowInsert TINYINT(1))
BEGIN
  
  -- Operator Game Limit  
  -- Fixed time limit bug for admin limits 
  -- Added fetching the limit_percentage and game_limit_percentage
  -- Added fetching of start/end dates and number of days
  
  DECLARE vNow DATETIME;
  DECLARE sessionID BIGINT DEFAULT NULL;
  DECLARE sessionDuration INT DEFAULT 0;
  DECLARE rollingAmountCurrent, rollingAmountCurrentAdmin, rollingAmountPlays, rollingAmountPlaysAdmin  DECIMAL(18,5) DEFAULT 0;
  DECLARE playLimitGameLevelEnabled, operatorLimitsEnabled, rollingLimitsEnabled TINYINT(1) DEFAULT 0;

  SET vNow = NOW();
  SET @license_type = licenseType;
  SET @channel_type = channelType;

  SELECT sessions_main.session_id, TIMESTAMPDIFF(MINUTE, sessions_main.date_open, vNow) AS session_duration
  INTO sessionID, sessionDuration
  FROM sessions_main
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND
    sessions_main.extra_id=gaming_client_stats.client_id AND sessions_main.status_code=1 AND sessions_main.extra2_id=gaming_client_stats.client_stat_id	
  ORDER BY session_id asc
  LIMIT 1;
  
  CALL PlayLimitsCurrentCheck(clientStatID, sessionID, @license_type, NULL, @channel_type, allowInsert);
   
  SELECT value_bool INTO operatorLimitsEnabled FROM gaming_settings WHERE `name`='OPERATOR_DEFAULT_PLAY_LIMITS';
  SELECT value_bool INTO rollingLimitsEnabled FROM gaming_settings WHERE `name`='ROLLING_LIMIT_ENABLED';

  SELECT
    gpl.play_limit_id, 
    gaming_play_limit_type.name AS limit_type,
    gaming_play_limit_type.display_name AS limit_type_display, 
    gaming_interval_type.name AS interval_type,
    gaming_license_type.name AS license_type,
	gaming_channel_types.channel_type,
    gaming_games.game_id, gaming_games.game_name, gaming_games.game_description, gaming_game_manufacturers.name AS game_manufacturer,
    gpl.limit_amount AS limit_value, 
    CASE gaming_play_limit_type.name
      WHEN 'BET_AMOUNT_LIMIT' THEN IFNULL(
          IF(gaming_interval_type.interval_type_id=9,
          PlayLimitGetRollingLimitCurrentValue(clientStatID, gaming_license_type.name, gaming_channel_types.channel_type, 0)
          ,gpcl.amount)    
      ,0)
      WHEN 'LOSS_AMOUNT_LIMIT' THEN IFNULL(gpcl.amount,0)
      WHEN 'DIRECT_BLOCK_LIMIT' THEN IFNULL(FLOOR(TIME_TO_SEC(TIMEDIFF(NOW(), gpl.start_date))/60),0) 
      WHEN 'TIME_LIMIT' THEN IFNULL(sessionDuration,0)
    END AS current_value,
    IF (gpl.game_id IS NULL, NULL,
		CASE gaming_play_limit_type.name
		  WHEN 'BET_AMOUNT_LIMIT' THEN IFNULL(gpcgl.amount,0)
		  WHEN 'LOSS_AMOUNT_LIMIT' THEN IFNULL(gpcgl.amount,0)
		  WHEN 'DIRECT_BLOCK_LIMIT' THEN IFNULL(FLOOR(TIME_TO_SEC(TIMEDIFF(NOW(), gpl.start_date))/60),0) 
		  WHEN 'TIME_LIMIT' THEN IFNULL(sessionDuration,0)
    END) AS game_current_value,
	gpcl.limit_percentage,
	gpcgl.limit_percentage AS game_limit_percentage,
  gpl.start_date AS start_date,
  gpl.end_date AS end_date,
  gpl.no_of_days AS no_of_days
  FROM gaming_client_stats
  JOIN gaming_play_limits AS gpl ON (gaming_client_stats.client_stat_id=clientStatID AND gpl.is_active=1) AND
    ((gpl.end_date >= vNow OR gpl.end_date IS NULL) AND gpl.start_date <= vNow) AND 
    (gpl.is_active=1 AND (gpl.end_date IS NULL OR gpl.end_date >= NOW()) AND gpl.start_date <= NOW()) AND
    gaming_client_stats.client_stat_id=gpl.client_stat_id 
  JOIN gaming_play_limit_type ON gpl.play_limit_type_id=gaming_play_limit_type.play_limit_type_id
  JOIN gaming_license_type ON (@license_type IS NULL OR gaming_license_type.name=@license_type) AND gaming_license_type.license_type_id=gpl.license_type_id 
  JOIN gaming_interval_type ON gpl.interval_type_id=gaming_interval_type.interval_type_id
  JOIN gaming_channel_types ON (@channel_type IS NULL OR gaming_channel_types.channel_type=@channel_type) AND gaming_channel_types.channel_type_id = gpl.channel_type_id
  LEFT JOIN gaming_games ON gpl.game_id=gaming_games.game_id
  LEFT JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id	
  LEFT JOIN gaming_player_current_limits gpcl ON (gpcl.client_stat_id = gpl.client_stat_id AND gpcl.play_limit_type_id = gpl.play_limit_type_id AND gpcl.interval_type_id = gpl.interval_type_id AND gpcl.license_type_id=gaming_license_type.license_type_id AND gpcl.channel_type_id = gaming_channel_types.channel_type_id)
  LEFT JOIN gaming_player_current_game_limits gpcgl ON (gpcgl.client_stat_id = gpl.client_stat_id AND gpcgl.play_limit_type_id = gpl.play_limit_type_id AND gpcgl.interval_type_id = gpl.interval_type_id AND gpcgl.license_type_id=gaming_license_type.license_type_id AND gpcgl.game_id=gpl.game_id AND gpcgl.channel_type_id = gaming_channel_types.channel_type_id)	
  ORDER BY gaming_license_type.order_no, gaming_play_limit_type.order_no, gaming_interval_type.order_no;
  
  IF (operatorLimitsEnabled) THEN
	SELECT
		gpl_admin.play_limit_admin_id, 
		gaming_play_limit_type.name AS limit_type,
		gaming_play_limit_type.display_name AS limit_type_display, 
		gaming_interval_type.name AS interval_type,
		gaming_license_type.name AS license_type,
		gaming_channel_types.channel_type,
		gaming_games.game_id, gaming_games.game_description, gaming_game_manufacturers.name AS game_manufacturer,
		IFNULL(gpl_amount_admin.limit_amount, gpl_admin.limit_amount) AS admin_limit_value, 
		CASE gaming_play_limit_type.name
		  WHEN 'BET_AMOUNT_LIMIT' THEN IFNULL(
          IF(gaming_interval_type.interval_type_id=9,
          PlayLimitGetRollingLimitCurrentValue(clientStatID, gaming_license_type.name, gaming_channel_types.channel_type, 1)
          ,gpcl.amount)    
      ,0)
		  WHEN 'LOSS_AMOUNT_LIMIT' THEN IFNULL(gpcl.amount,0)
		  WHEN 'DIRECT_BLOCK_LIMIT' THEN FLOOR(TIME_TO_SEC(TIMEDIFF(NOW(), gpl_admin.start_date))/60) 
		  WHEN 'TIME_LIMIT' THEN IFNULL(sessionDuration,0)
		END AS current_value,
		IF (gpl_admin.game_id IS NULL, NULL,
			CASE gaming_play_limit_type.name
			  WHEN 'BET_AMOUNT_LIMIT' THEN IFNULL(gpcgl.amount,0)
			  WHEN 'LOSS_AMOUNT_LIMIT' THEN IFNULL(gpcgl.amount,0)
			  WHEN 'DIRECT_BLOCK_LIMIT' THEN FLOOR(TIME_TO_SEC(TIMEDIFF(NOW(), gpl_admin.start_date))/60) 
			  WHEN 'TIME_LIMIT' THEN IFNULL(sessionDuration,0)
			END) AS game_current_value,
		gpcl.limit_percentage,
		gpcgl.limit_percentage AS game_limit_percentage,
    gpl_admin.start_date AS start_date,
    gpl_admin.end_date AS end_date,
    gpl_admin.no_of_days AS no_of_days
	  FROM gaming_client_stats
	  JOIN gaming_play_limits_admin AS gpl_admin ON gpl_admin.is_active=1 AND
		((gpl_admin.end_date >= vNow OR gpl_admin.end_date IS NULL) AND gpl_admin.start_date <= vNow) AND 
		(gpl_admin.is_active=1 AND (gpl_admin.end_date IS NULL OR gpl_admin.end_date >= NOW()) AND gpl_admin.start_date <= NOW()) 
	  JOIN gaming_play_limit_type ON gpl_admin.play_limit_type_id=gaming_play_limit_type.play_limit_type_id
	  JOIN gaming_license_type ON (@license_type IS NULL OR gaming_license_type.name=@license_type) AND gaming_license_type.license_type_id=gpl_admin.license_type_id 
	  JOIN gaming_interval_type ON gpl_admin.interval_type_id=gaming_interval_type.interval_type_id
      JOIN gaming_channel_types ON (@channel_type IS NULL OR gaming_channel_types.channel_type=@channel_type) AND gaming_channel_types.channel_type_id = gpl_admin.channel_type_id
      LEFT JOIN gaming_play_limits_admin_amounts AS gpl_amount_admin ON gpl_admin.play_limit_admin_id=gpl_amount_admin.play_limit_admin_id AND gpl_amount_admin.currency_id=gaming_client_stats.currency_id
	  LEFT JOIN gaming_games ON gpl_admin.game_id=gaming_games.game_id
	  LEFT JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id	
	  LEFT JOIN gaming_player_current_limits gpcl ON (gpcl.client_stat_id = gaming_client_stats.client_stat_id AND gpcl.play_limit_type_id = gpl_admin.play_limit_type_id AND gpcl.interval_type_id = gpl_admin.interval_type_id AND gpcl.license_type_id=gaming_license_type.license_type_id AND gpcl.channel_type_id = gaming_channel_types.channel_type_id)
	  LEFT JOIN gaming_player_current_game_limits gpcgl ON (gpcgl.client_stat_id = gaming_client_stats.client_stat_id AND gpcgl.play_limit_type_id = gpl_admin.play_limit_type_id AND gpcgl.interval_type_id = gpl_admin.interval_type_id AND gpcgl.license_type_id=gaming_license_type.license_type_id AND gpcgl.game_id=gpl_admin.game_id AND gpcgl.channel_type_id = gaming_channel_types.channel_type_id)	
	  WHERE gaming_client_stats.client_stat_id=clientStatID
	  ORDER BY gaming_license_type.order_no, gaming_play_limit_type.order_no, gaming_interval_type.order_no;

  END IF;
END$$

DELIMITER ;

