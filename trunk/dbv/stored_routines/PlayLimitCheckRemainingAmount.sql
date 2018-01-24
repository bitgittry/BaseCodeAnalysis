DROP function IF EXISTS `PlayLimitCheckRemainingAmount`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PlayLimitCheckRemainingAmount`(sessionID BIGINT, clientStatID BIGINT) RETURNS decimal(18,5)
    READS SQL DATA
    DETERMINISTIC
BEGIN

  -- Fixed PlayLimitsCurrentCheck

  DECLARE limitExceededCount INT DEFAULT -1;
  DECLARE minPlayLimit DECIMAL(18,5) DEFAULT 1000000000;
  DECLARE vNow DATETIME;
  DECLARE channelType VARCHAR(20) DEFAULT NULL; 
  DECLARE allowInsert TINYINT(1) DEFAULT 0;
  
  -- Get Channel Type
  SELECT gaming_channel_types.channel_type INTO channelType
  FROM sessions_main 
  JOIN gaming_platform_types ON sessions_main.platform_type_id = gaming_platform_types.platform_type_id
  JOIN gaming_channels_platform_types ON gaming_platform_types.platform_type_id = gaming_channels_platform_types.platform_type_id
  JOIN gaming_channel_types ON gaming_channels_platform_types.channel_type_id = gaming_channel_types.channel_type_id
  WHERE sessions_main.session_id = sessionID AND gaming_channel_types.is_active = 1 AND gaming_channel_types.play_limits_active = 1;

  CALL PlayLimitsCurrentCheck(clientStatID, sessionID, NULL, NULL, channelType, allowInsert);
  
  SET vNow = NOW();
  
  SELECT MIN(CASE gplt.name
      WHEN 'BET_AMOUNT_LIMIT' THEN GREATEST(gpl.limit_amount - gpcl.amount, 0)
      WHEN 'LOSS_AMOUNT_LIMIT' THEN GREATEST(gpl.limit_amount - gpcl.amount , 0)
      WHEN 'DIRECT_BLOCK_LIMIT' THEN 0
      WHEN 'TIME_LIMIT' THEN IFNULL(IF(TIMESTAMPDIFF(MINUTE, sm.date_open, vNow) > gpl.limit_amount, 0, 1000000000), 0)
    END)  
  INTO minPlayLimit
  FROM gaming_play_limits gpl
  JOIN gaming_interval_type git ON 
    (gpl.client_stat_id=clientStatID AND gpl.is_active = 1) AND 
    ((gpl.end_date >= vNow OR gpl.end_date IS NULL) AND gpl.start_date <= vNow) AND 
    gpl.interval_type_id=git.interval_type_id
  JOIN gaming_play_limit_type AS gplt ON gpl.play_limit_type_id=gplt.play_limit_type_id
  JOIN gaming_license_type glt ON glt.license_type_id=gpl.license_type_id
  JOIN gaming_channel_types ON gaming_channel_types.channel_type_id = gpl.channel_type_id
  LEFT JOIN gaming_player_current_limits gpcl ON (gpcl.client_stat_id = gpl.client_stat_id AND gpcl.play_limit_type_id = gpl.play_limit_type_id AND gpcl.interval_type_id = gpl.interval_type_id)
  LEFT JOIN sessions_main sm ON sm.session_id = sessionID
  GROUP BY gpl.client_stat_id;
  
  RETURN minPlayLimit;
END$$

DELIMITER ;

