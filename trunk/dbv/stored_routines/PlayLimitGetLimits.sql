DROP procedure IF EXISTS `PlayLimitGetLimits`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitGetLimits`(playLimitID BIGINT, clientStatID BIGINT, intervalType VARCHAR(20), limitType VARCHAR(20), licenseType VARCHAR(20), channelType VARCHAR(20), gameID BIGINT)
root: BEGIN

  SET @play_limit_id = playLimitID;
  SET @client_stat_id = clientStatID;
  SET @limit_type = limitType;
  SET @interval_type = intervalType;
  SET @license_type = licenseType;
  SET @channel_type = channelType;
 
   SELECT 
    gaming_play_limit_type.name AS play_limit_type_name, gaming_play_limit_type.display_name AS play_limit_type_display, gaming_interval_type.name AS interval_type_name, gaming_license_type.name AS license_type_name, gaming_channel_types.channel_type, gaming_play_limits.limit_amount, 
    gaming_play_limits.start_date, gaming_play_limits.end_date, gaming_play_limits.no_of_days, IF(gaming_play_limits.start_date <= NOW(), 0, 1) AS is_future_limit,
	gaming_games.game_id, gaming_games.game_description, gaming_game_manufacturers.name AS game_manufacturer
  FROM gaming_play_limits
  JOIN gaming_client_stats ON 
    gaming_client_stats.client_stat_id=@client_stat_id AND
    gaming_client_stats.client_stat_id=gaming_play_limits.client_stat_id
  JOIN gaming_play_limit_type ON (@limit_type IS NULL OR gaming_play_limit_type.name=@limit_type) AND gaming_play_limits.play_limit_type_id = gaming_play_limit_type.play_limit_type_id
  JOIN gaming_interval_type ON (@interval_type IS NULL OR gaming_interval_type.name=@interval_type) AND gaming_play_limits.interval_type_id = gaming_interval_type.interval_type_id
  JOIN gaming_license_type ON (@license_type IS NULL OR gaming_license_type.name=@license_type) AND gaming_license_type.license_type_id=gaming_play_limits.license_type_id
  JOIN gaming_channel_types ON (@channel_type IS NULL OR gaming_channel_types.channel_type=@channel_type) AND gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
  LEFT JOIN gaming_games ON gaming_play_limits.game_id=gaming_games.game_id
  LEFT JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  WHERE gaming_play_limits.is_active=1 AND (end_date IS NULL OR end_date >= NOW()) AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID))
  AND (@play_limit_id IS NULL OR gaming_play_limits.play_limit_id=@play_limit_id)
  ORDER BY gaming_play_limit_type.name, gaming_interval_type.name, is_future_limit; 

END root$$

DELIMITER ;