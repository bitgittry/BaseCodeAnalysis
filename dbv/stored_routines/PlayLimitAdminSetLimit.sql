DROP procedure IF EXISTS `PlayLimitAdminSetLimit`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitAdminSetLimit`(intervalType VARCHAR(20), limitType VARCHAR(20), licenseType VARCHAR(20), channelType VARCHAR(20), gameID BIGINT, varAmount DECIMAL(18, 5), ignoreTimeWindow TINYINT(1), startDate DateTime, noOfDays INT, sessionID BIGINT, OUT statusCode INT)
root: BEGIN
  -- First Version 
   
  DECLARE increaseDays INT DEFAULT 0;
  SET @limit_type = limitType;
  SET @interval_type = intervalType;
  SET @session_id = sessionID;
  SET @license_type = licenseType;
  SET @channel_type = IFNULL(channelType, 'all');
  SET @currentAmount = 0;
  SET @rowCount = 0;
  SET @vNow = NOW();
  
  SELECT @rowCount+1, limit_amount INTO @rowCount, @currentAmount 
  FROM gaming_play_limits_admin AS gaming_play_limits 
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
  WHERE gaming_play_limits.is_active=1 AND start_date <= @vNow AND (end_date IS NULL OR end_date >= @vNow)
	AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
    
  SET @ApplyInNextTimePeriod = 0;
  IF (@rowCount = 1) THEN
    IF (@limit_type = 'BET_AMOUNT_LIMIT' AND @interval_type = 'Rolling') THEN
		SET @ApplyInNextTimePeriod = 1;
    ELSE IF (varAMount > @currentAmount) THEN
      SET @ApplyInNextTimePeriod = 1;
    END IF;
	END IF;
  ELSE 
    
    IF (@rowCount > 1) THEN
      SET statusCode=1;
      LEAVE root;
    END IF;
  END IF;
   
  -- Commented out for now, was this a copy/paste artifact?
  IF (/* @limit_type <> 'BET_AMOUNT_LIMIT' AND */ @interval_type <> 'Rolling') THEN
  SET @ApplyInNextTimePeriod=(@ApplyInNextTimePeriod AND NOT ignoreTimeWindow); 
  END IF;
   
  IF (@ApplyInNextTimePeriod = 1) THEN
    SET increaseDays = (SELECT value_int FROM gaming_settings WHERE `name`='PLAYING_LIMIT_INCREASE_OPERATOR_TIMEPERIOD_DAYS');
    
  IF (@limit_type = 'BET_AMOUNT_LIMIT' AND @interval_type = 'Rolling') THEN
   SET @end_date = DATE_SUB(startDate, INTERVAL 1 SECOND);
  ELSE
    SET @end_date = DATE_SUB(DATE_ADD(@vNow, INTERVAL increaseDays DAY), INTERVAL 1 SECOND);
  END IF;
    
    UPDATE gaming_play_limits_admin AS gaming_play_limits 
      JOIN gaming_play_limit_type ON 
        gaming_play_limit_type.name=@limit_type AND  
        gaming_play_limits.play_limit_type_id=gaming_play_limit_type.play_limit_type_id 
      JOIN gaming_license_type ON 
        gaming_license_type.name=@license_type AND
        gaming_license_type.license_type_id=gaming_play_limits.license_type_id
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
      
    
    UPDATE gaming_play_limits_admin AS gaming_play_limits 
      JOIN gaming_play_limit_type ON 
        gaming_play_limits.is_active=1  AND
        gaming_play_limit_type.name=@limit_type AND
        gaming_play_limits.play_limit_type_id=gaming_play_limit_type.play_limit_type_id 
      JOIN gaming_license_type ON 
        gaming_license_type.name=@license_type AND
        gaming_license_type.license_type_id=gaming_play_limits.license_type_id
      JOIN gaming_interval_type ON 
        gaming_interval_type.name=@interval_type AND
        gaming_interval_type.interval_type_id=gaming_play_limits.interval_type_id
	JOIN gaming_channel_types ON 
		gaming_channel_types.channel_type=@channel_type AND	
		gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
    SET gaming_play_limits.is_active=0, gaming_play_limits.session_id=@session_id
    WHERE gaming_play_limits.end_date IS NULL AND ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
    
    SET @start_date = DATE_ADD(@end_date, INTERVAL 1 SECOND);
    INSERT INTO gaming_play_limits_admin (play_limit_type_id, interval_type_id, limit_amount, create_date, start_date, license_type_id, channel_type_id, game_id, is_active, session_id, no_of_days)
    SELECT gaming_play_limit_type.play_limit_type_id, gaming_interval_type.interval_type_id, varAmount, @vNow, 
    IF(@limit_type='BET_AMOUNT_LIMIT' AND @interval_type='Rolling', startDate, @start_date), gaming_license_type.license_type_id, gaming_channel_types.channel_type_id, gameID, 1, @session_id, IF(@limit_type='BET_AMOUNT_LIMIT' AND @interval_type='Rolling', noOfDays, NULL)
    FROM gaming_play_limit_type 
    JOIN gaming_license_type ON 
		gaming_play_limit_type.name=@limit_type AND
        gaming_license_type.name=@license_type
    JOIN gaming_interval_type ON gaming_interval_type.name=@interval_type
	JOIN gaming_channel_types ON gaming_channel_types.channel_type = @channel_type;
    
  ELSE
    
    UPDATE gaming_play_limits_admin AS gaming_play_limits 
    JOIN gaming_play_limit_type ON
      gaming_play_limits.is_active=1 AND
      gaming_play_limit_type.name=@limit_type AND
      gaming_play_limits.play_limit_type_id=gaming_play_limit_type.play_limit_type_id 
    JOIN gaming_license_type ON 
      gaming_license_type.name=@license_type AND
      gaming_license_type.license_type_id=gaming_play_limits.license_type_id
    JOIN gaming_interval_type ON 
      gaming_interval_type.name=@interval_type AND
      gaming_interval_type.interval_type_id=gaming_play_limits.interval_type_id
    JOIN gaming_channel_types ON 
		gaming_channel_types.channel_type=@channel_type AND	
		gaming_channel_types.channel_type_id = gaming_play_limits.channel_type_id
    SET gaming_play_limits.is_active=0, gaming_play_limits.session_id=@session_id
    WHERE ((gameID IS NULL AND gaming_play_limits.game_id IS NULL) OR (gameID IS NOT NULL AND gaming_play_limits.game_id=gameID));
      
    
    INSERT INTO gaming_play_limits_admin (play_limit_type_id, interval_type_id, limit_amount, create_date, start_date, end_date, license_type_id, channel_type_id, game_id, is_active, session_id, no_of_days)
    SELECT 
      gaming_play_limit_type.play_limit_type_id, gaming_interval_type.interval_type_id, varAmount, @vNow, 
	  IF(@limit_type='BET_AMOUNT_LIMIT' AND @interval_type='Rolling', startDate, @vNow),
      IF(@limit_type='DIRECT_BLOCK_LIMIT',TIMESTAMPADD(MINUTE,varAmount,@vNow),NULL), gaming_license_type.license_type_id, gaming_channel_types.channel_type_id, gameID, 1, @session_id, IF(@limit_type='BET_AMOUNT_LIMIT' AND @interval_type='Rolling', noOfDays, NULL)
    FROM gaming_play_limit_type
    JOIN gaming_license_type ON
		gaming_play_limit_type.name=@limit_type AND
        gaming_license_type.name=@license_type
    JOIN gaming_interval_type ON gaming_interval_type.name=@interval_type
	JOIN gaming_channel_types ON gaming_channel_types.channel_type = @channel_type;
      
  END IF;
  
 CALL PlayLimitAdminGetLimits(@interval_type, @limit_type, @license_type, @channel_type, gameID);

  SET statusCode = 0;
END root$$

DELIMITER ;