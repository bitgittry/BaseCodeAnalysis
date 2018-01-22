DROP procedure IF EXISTS `PlayLimitsCurrentCheck`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitsCurrentCheck`(
  clientStatID BIGINT, sessionID BIGINT, licenseType VARCHAR(20), gameID BIGINT, channelType VARCHAR(20), allowInsert TINYINT(1))
BEGIN

  -- Added Game Level  
  -- Added updating all current levels for all games that were played
  -- Added clearing the limit_percentage
  -- Added clearing the notified at percentage 
  
  DECLARE playLimitGameLevelEnabled TINYINT(1) DEFAULT 0;

  SELECT value_bool INTO playLimitGameLevelEnabled FROM gaming_settings WHERE `name`='PLAY_LIMIT_GAME_LEVEL_ENABLED';
    
  SET @channel_type = channelType;

  -- License Type Level  
  INSERT INTO gaming_player_current_limits (client_stat_id, play_limit_type_id, interval_type_id, license_type_id, channel_type_id, amount, limit_percentage, interval_type_reference)
  SELECT clientStatID as `client_stat_id`, gplt.play_limit_type_id, git.interval_type_id, glt.license_type_id, gaming_channel_types.channel_type_id, 0 as new_amount, 0 as new_limit_percentage,  
    CASE git.name
      WHEN 'Session' THEN IFNULL(sessionID, 'NotLoggedIn')
      WHEN 'Day' THEN CURRENT_DATE
      WHEN 'Week' THEN DateOnlyGetWeekStart(NULL)
      WHEN 'Month' THEN DateOnlyGetMonthStart(NULL)
      WHEN 'Year' THEN DateOnlyGetYearStart(NULL)
    END AS interval_type_reference
  FROM gaming_play_limit_type gplt
  STRAIGHT_JOIN gaming_interval_type git ON 
	(gplt.name = 'BET_AMOUNT_LIMIT' OR gplt.name = 'LOSS_AMOUNT_LIMIT') 
	AND (git.is_play_limit=1 AND git.`name`!='Transaction')
  STRAIGHT_JOIN gaming_license_type AS glt ON glt.is_active=1
  STRAIGHT_JOIN gaming_channel_types ON (gaming_channel_types.channel_type = @channel_type OR gaming_channel_types.channel_type = 'all')
  LEFT JOIN gaming_player_current_limits gpcl FORCE INDEX (PRIMARY) ON 
	gplt.play_limit_type_id = gpcl.play_limit_type_id AND gpcl.interval_type_id = git.interval_type_id AND 
    gpcl.license_type_id=glt.license_type_id AND client_stat_id = clientStatID AND 
    gpcl.channel_type_id = gaming_channel_types.channel_type_id
  WHERE (gpcl.client_stat_id IS NULL AND allowInsert) OR gpcl.interval_type_reference!=(CASE git.name
      WHEN 'Session' THEN IFNULL(sessionID, 'NotLoggedIn')
      WHEN 'Day' THEN CURRENT_DATE
      WHEN 'Week' THEN DateOnlyGetWeekStart(NULL)
      WHEN 'Month' THEN DateOnlyGetMonthStart(NULL)
	  WHEN 'Year' THEN DateOnlyGetYearStart(NULL)
    END)
  ON DUPLICATE KEY UPDATE 
    gaming_player_current_limits.interval_type_reference = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference), VALUES(interval_type_reference), gaming_player_current_limits.interval_type_reference),
    gaming_player_current_limits.amount = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference),0, gaming_player_current_limits.amount),
	gaming_player_current_limits.limit_percentage = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference),0, gaming_player_current_limits.limit_percentage),
    gaming_player_current_limits.notified_at_percentage = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference),0, gaming_player_current_limits.notified_at_percentage);
  
  -- Game Level
  IF (playLimitGameLevelEnabled) THEN

	-- Check previously created
	 INSERT INTO gaming_player_current_game_limits (client_stat_id, play_limit_type_id, interval_type_id, license_type_id, channel_type_id, game_id, amount, limit_percentage, interval_type_reference)
	  SELECT clientStatID as `client_stat_id`, gplt.play_limit_type_id, git.interval_type_id, glt.license_type_id, gaming_channel_types.channel_type_id, gpcl.game_id, 0 as new_amount, 0 as new_limit_percentage,   
		CASE git.name
		  WHEN 'Session' THEN IFNULL(sessionID, 'NotLoggedIn')
		  WHEN 'Day' THEN CURRENT_DATE
		  WHEN 'Week' THEN DateOnlyGetWeekStart(NULL)
		  WHEN 'Month' THEN DateOnlyGetMonthStart(NULL)
		  WHEN 'Year' THEN DateOnlyGetYearStart(NULL)
		END AS interval_type_reference
	  FROM gaming_play_limit_type gplt
	  STRAIGHT_JOIN gaming_interval_type git ON 
		(gplt.name = 'BET_AMOUNT_LIMIT' OR gplt.name = 'LOSS_AMOUNT_LIMIT') 
		AND (git.is_play_limit=1 AND git.`name`!='Transaction')
	  STRAIGHT_JOIN gaming_license_type glt ON glt.is_active = 1
	  STRAIGHT_JOIN gaming_channel_types ON (gaming_channel_types.channel_type = @channel_type OR gaming_channel_types.channel_type = 'all')
	  STRAIGHT_JOIN gaming_player_current_game_limits gpcl FORCE INDEX (PRIMARY) ON 
		gpcl.client_stat_id = clientStatID AND gplt.play_limit_type_id = gpcl.play_limit_type_id AND 
        gpcl.interval_type_id = git.interval_type_id AND glt.license_type_id=gpcl.license_type_id AND 
        gpcl.channel_type_id = gaming_channel_types.channel_type_id
	  
      WHERE (gpcl.client_stat_id IS NULL AND allowInsert) OR gpcl.interval_type_reference!=(CASE git.name
		  WHEN 'Session' THEN IFNULL(sessionID, 'NotLoggedIn')
		  WHEN 'Day' THEN CURRENT_DATE
		  WHEN 'Week' THEN DateOnlyGetWeekStart(NULL)
		  WHEN 'Month' THEN DateOnlyGetMonthStart(NULL)
		  WHEN 'Year' THEN DateOnlyGetYearStart(NULL)
		END) 
	  ON DUPLICATE KEY UPDATE 
		gaming_player_current_game_limits.interval_type_reference = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference), VALUES(interval_type_reference), gaming_player_current_game_limits.interval_type_reference),
		gaming_player_current_game_limits.amount = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference),0, gaming_player_current_game_limits.amount),
		gaming_player_current_game_limits.limit_percentage = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference),0, gaming_player_current_game_limits.limit_percentage),
		gaming_player_current_game_limits.notified_at_percentage = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference),0, gaming_player_current_game_limits.notified_at_percentage);
    
	IF (gameID IS NOT NULL AND gameID > 0) THEN
			
		 -- Insert if doesn't exist
		 INSERT INTO gaming_player_current_game_limits (client_stat_id, play_limit_type_id, interval_type_id, license_type_id, channel_type_id, game_id, amount, limit_percentage, interval_type_reference)
		  SELECT clientStatID as `client_stat_id`, gplt.play_limit_type_id, git.interval_type_id, glt.license_type_id, gaming_channel_types.channel_type_id, gameID, 0 as new_amount, 0 as new_limit_percentage,    
			CASE git.name
			  WHEN 'Session' THEN IFNULL(sessionID, 'NotLoggedIn')
			  WHEN 'Day' THEN CURRENT_DATE
			  WHEN 'Week' THEN DateOnlyGetWeekStart(NULL)
			  WHEN 'Month' THEN DateOnlyGetMonthStart(NULL)
			  WHEN 'Year' THEN DateOnlyGetYearStart(NULL)
			END AS interval_type_reference
		  FROM gaming_play_limit_type gplt 
		  STRAIGHT_JOIN gaming_interval_type git ON 
			(gplt.name = 'BET_AMOUNT_LIMIT' OR gplt.name = 'LOSS_AMOUNT_LIMIT') 
			AND (git.is_play_limit=1 AND git.`name`!='Transaction')
		  STRAIGHT_JOIN gaming_license_type glt ON glt.name=licenseType
		  STRAIGHT_JOIN gaming_channel_types ON (gaming_channel_types.channel_type = @channel_type OR gaming_channel_types.channel_type = 'all')
		  LEFT JOIN gaming_player_current_game_limits gpcl  FORCE INDEX (PRIMARY)  ON 
			gpcl.client_stat_id = clientStatID AND gplt.play_limit_type_id = gpcl.play_limit_type_id AND 
            gpcl.interval_type_id = git.interval_type_id AND glt.license_type_id=gpcl.license_type_id AND 
            gpcl.game_id=gameID AND gpcl.channel_type_id = gaming_channel_types.channel_type_id
		  WHERE (gpcl.client_stat_id IS NULL AND allowInsert) OR gpcl.interval_type_reference!=(CASE git.name
			  WHEN 'Session' THEN IFNULL(sessionID, 'NotLoggedIn')
			  WHEN 'Day' THEN CURRENT_DATE
			  WHEN 'Week' THEN DateOnlyGetWeekStart(NULL)
			  WHEN 'Month' THEN DateOnlyGetMonthStart(NULL)
			  WHEN 'Year' THEN DateOnlyGetYearStart(NULL)
			END) 
		  ON DUPLICATE KEY UPDATE 
			gaming_player_current_game_limits.interval_type_reference = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference), VALUES(interval_type_reference), gaming_player_current_game_limits.interval_type_reference),
			gaming_player_current_game_limits.amount = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference),0, gaming_player_current_game_limits.amount),
			gaming_player_current_game_limits.limit_percentage = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference),0, gaming_player_current_game_limits.limit_percentage),
			gaming_player_current_game_limits.notified_at_percentage = IF (gpcl.interval_type_reference!=VALUES(interval_type_reference),0, gaming_player_current_game_limits.notified_at_percentage);
            
	  END IF;
      
   END IF;

END$$

DELIMITER ;

