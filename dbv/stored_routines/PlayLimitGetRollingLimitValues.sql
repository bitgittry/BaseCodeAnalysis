DROP procedure IF EXISTS `PlayLimitGetRollingLimitValues`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitGetRollingLimitValues`(
  clientStatID BIGINT, licenseType VARCHAR(20), channelType VARCHAR(50), adminLimit TINYINT(1), 
  OUT limitExists TINYINT(1), OUT limitAmount DECIMAL(18,5), OUT currentAmount DECIMAL(18,5))
BEGIN
  -- Initial SP  
  -- Removed duplicated subtraction of cancelled bets for INBUGLW-271
  -- Corrected SP for INBUGLW-152
  DECLARE vNumDays INT DEFAULT -1;
  DECLARE licenseTypeID int(11) DEFAULT 4;
  DECLARE channelTypeID int(11) DEFAULT 0;
  DECLARE vTotalRolling DECIMAL(18,5) DEFAULT NULL;
  DECLARE vRollingAmount, vCancelledBetsFromGamePlays DECIMAL(18,5) DEFAULT 0;
  DECLARE vNow DATETIME;
  DECLARE vCurdate DATE DEFAULT CURDATE();
  DECLARE rollingLevelEnabled, operatorLimitsEnabled TINYINT(1) DEFAULT 0;
  DECLARE rollingLimitIntervalID BIGINT(20) DEFAULT 9;
  DECLARE parentLimitChannelLicensePlayer, parentLimitChannelLicenseAdmin varchar(20) DEFAULT NULL;  
  
  SELECT value_bool INTO rollingLevelEnabled FROM gaming_settings WHERE `name`='ROLLING_LIMIT_ENABLED';
  SELECT value_bool INTO operatorLimitsEnabled FROM gaming_settings WHERE `name`='OPERATOR_DEFAULT_PLAY_LIMITS';
  SELECT license_type_id INTO licenseTypeID FROM gaming_license_type WHERE `name`=licenseType;
  SELECT channel_type_id INTO channelTypeID FROM gaming_channel_types WHERE channel_type=channelType;

  SET limitAmount = 0;
  SET currentAmount = 0;        
  SET limitExists = 0;

  IF (rollingLevelEnabled) THEN

    SET vNow = NOW();

    IF (adminLimit AND operatorLimitsEnabled) THEN
    /**
    * gaming_play_limits_admin amounts
    * (operator limits)
    */
    IF (licenseTypeID = 4) THEN
      /**
      * Global license
      */
      SELECT
        SUM(gpclh_admin.amount), gpl_admin.no_of_days, gpl_amount_admin.limit_amount, glt_admin.name
      INTO 
        vRollingAmount, vNumDays, vTotalRolling, parentLimitChannelLicenseAdmin
      FROM gaming_client_stats FORCE INDEX (PRIMARY)
      JOIN gaming_play_limits_admin gpl_admin ON gpl_admin.is_active = 1 AND 
        ((gpl_admin.end_date >= vNow OR gpl_admin.end_date IS NULL) AND gpl_admin.start_date <= vNow) 
      JOIN gaming_interval_type AS git_admin ON gpl_admin.interval_type_id=git_admin.interval_type_id
      JOIN gaming_play_limit_type AS gplt_admin ON gpl_admin.play_limit_type_id=gplt_admin.play_limit_type_id
      JOIN gaming_license_type AS glt_admin ON glt_admin.name = 'all' AND gpl_admin.license_type_id=glt_admin.license_type_id
      JOIN gaming_channel_types gct ON gct.channel_type = channelType AND gpl_admin.channel_type_id=gct.channel_type_id
      LEFT JOIN gaming_play_limits_admin_amounts AS gpl_amount_admin ON gpl_admin.play_limit_admin_id=gpl_amount_admin.play_limit_admin_id AND 
        gpl_amount_admin.currency_id=gaming_client_stats.currency_id
      -- history aggregation data
      LEFT JOIN gaming_player_current_limits_aggregation_history AS gpclh_admin ON 
        (
          gpclh_admin.client_stat_id = gaming_client_stats.client_stat_id AND 
          gpclh_admin.play_limit_type_id = gpl_admin.play_limit_type_id AND 
          gpclh_admin.interval_type_id = gpl_admin.interval_type_id AND
          gpclh_admin.channel_type_id = gct.channel_type_id AND 
          gpclh_admin.interval_type_reference > DATE_ADD(vCurdate, interval -(gpl_admin.no_of_days) DAY) 
        )
      WHERE gaming_client_stats.client_stat_id=clientStatID and gpl_admin.interval_type_id = rollingLimitIntervalID;
    ELSE
     /**
      * All other license
      */
      SELECT 
        SUM(gpclh_admin.amount), gpl_admin.no_of_days, gpl_amount_admin.limit_amount, glt_admin.name
      INTO 
        vRollingAmount, vNumDays, vTotalRolling, parentLimitChannelLicenseAdmin
      FROM gaming_client_stats FORCE INDEX (PRIMARY)
      JOIN gaming_play_limits_admin gpl_admin ON gpl_admin.is_active = 1 AND
        ((gpl_admin.end_date >= vNow OR gpl_admin.end_date IS NULL) AND gpl_admin.start_date <= vNow) 
      JOIN gaming_interval_type AS git_admin ON gpl_admin.interval_type_id=git_admin.interval_type_id
      JOIN gaming_play_limit_type AS gplt_admin ON gpl_admin.play_limit_type_id=gplt_admin.play_limit_type_id
      JOIN gaming_license_type AS glt_admin ON glt_admin.name = licenseType AND gpl_admin.license_type_id=glt_admin.license_type_id
      JOIN gaming_channel_types gct ON gct.channel_type = channelType AND gpl_admin.channel_type_id=gct.channel_type_id
      LEFT JOIN gaming_play_limits_admin_amounts AS gpl_amount_admin ON gpl_admin.play_limit_admin_id=gpl_amount_admin.play_limit_admin_id AND 
        gpl_amount_admin.currency_id=gaming_client_stats.currency_id
      -- history aggregation data
      LEFT JOIN gaming_player_current_limits_aggregation_history AS gpclh_admin ON 
        (
          gpclh_admin.client_stat_id = gaming_client_stats.client_stat_id AND 
          gpclh_admin.play_limit_type_id = gpl_admin.play_limit_type_id AND 
          gpclh_admin.interval_type_id = gpl_admin.interval_type_id AND
          gpclh_admin.license_type_id = licenseTypeID AND 
          gpclh_admin.channel_type_id = channelTypeID AND 
          gpclh_admin.interval_type_reference > DATE_ADD(vCurdate, interval -(gpl_admin.no_of_days) DAY) 
        )
      WHERE gaming_client_stats.client_stat_id=clientStatID AND gpl_admin.interval_type_id = rollingLimitIntervalID;
    END IF;
    ELSE      
     /**
      * gaming_play_limits amounts
      * (per-player)
      */
    IF (licenseTypeID = 4) THEN
    /**
    * Global license
    */
      SELECT 
        SUM(gpclh.amount), gpl.no_of_days, gpl.limit_amount, glt.name
      INTO 
        vRollingAmount, vNumDays, vTotalRolling, parentLimitChannelLicensePlayer
      FROM gaming_client_stats FORCE INDEX (PRIMARY)
      -- Player Level Limits 
      JOIN gaming_play_limits gpl ON (gpl.client_stat_id=gaming_client_stats.client_stat_id AND gpl.is_active = 1) AND 
        ((gpl.end_date >= vNow OR gpl.end_date IS NULL) AND gpl.start_date <= vNow) 
      JOIN gaming_interval_type git ON gpl.interval_type_id=git.interval_type_id
      JOIN gaming_play_limit_type AS gplt ON gpl.play_limit_type_id=gplt.play_limit_type_id
      JOIN gaming_license_type glt ON glt.name='all' AND glt.license_type_id=gpl.license_type_id
      JOIN gaming_channel_types gct ON gct.channel_type = channelType AND gct.channel_type_id = gpl.channel_type_id
      -- history aggregation data
      LEFT JOIN gaming_player_current_limits_aggregation_history AS gpclh ON 
        (
          gpclh.client_stat_id = gaming_client_stats.client_stat_id AND 
          gpclh.play_limit_type_id = gpl.play_limit_type_id AND 
          gpclh.interval_type_id = gpl.interval_type_id AND
          gpclh.channel_type_id = gct.channel_type_id AND 
          gpclh.interval_type_reference > DATE_ADD(vCurdate, interval -(gpl.no_of_days) DAY) 
        )
      WHERE gaming_client_stats.client_stat_id=clientStatID and gpl.interval_type_id = rollingLimitIntervalID; 
    ELSE
    /**
    * All other license
    */
      SELECT 
        SUM(gpclh.amount), gpl.no_of_days, gpl.limit_amount, glt.name
      INTO 
        vRollingAmount, vNumDays,  vTotalRolling, parentLimitChannelLicensePlayer
      FROM gaming_client_stats FORCE INDEX (PRIMARY)
      -- Player Level Limits 
      JOIN gaming_play_limits gpl ON (gpl.client_stat_id=gaming_client_stats.client_stat_id AND gpl.is_active = 1) AND 
        ((gpl.end_date >= vNow OR gpl.end_date IS NULL) AND gpl.start_date <= vNow) 
      JOIN gaming_interval_type git ON gpl.interval_type_id=git.interval_type_id
      JOIN gaming_play_limit_type AS gplt ON gpl.play_limit_type_id=gplt.play_limit_type_id
      JOIN gaming_license_type glt ON glt.name=licenseType AND glt.license_type_id=gpl.license_type_id
      JOIN gaming_channel_types gct ON gct.channel_type = channelType AND gct.channel_type_id = gpl.channel_type_id
      -- history aggregation data
      LEFT JOIN gaming_player_current_limits_aggregation_history AS gpclh ON 
        (
          gpclh.client_stat_id = gaming_client_stats.client_stat_id AND 
          gpclh.play_limit_type_id = gpl.play_limit_type_id AND 
          gpclh.interval_type_id = gpl.interval_type_id AND
          gpclh.license_type_id = gpl.license_type_id AND 
          gpclh.channel_type_id = gct.channel_type_id AND 
          gpclh.interval_type_reference > DATE_ADD(vCurdate, interval -(gpl.no_of_days) DAY) 
        )
      WHERE gaming_client_stats.client_stat_id=clientStatID and gpl.interval_type_id = rollingLimitIntervalID; 
    END IF;
  END IF;    

      /**
      * gaming_game_plays amounts
      * - essentially just cancelled bets for now
      */
      /**SELECT 
       SUM(DISTINCT ggp.amount_total * -ggp.sign_mult) INTO vCancelledBetsFromGamePlays 
      FROM gaming_game_plays ggp 
      JOIN gaming_game_plays ggp_bet ON ggp.game_round_id = ggp_bet.game_round_id AND ggp_bet.payment_transaction_type_id = 12     
      JOIN gaming_channels_platform_types gcpt ON gcpt.platform_type_id = ggp_bet.platform_type_id 
      JOIN gaming_channel_types gct ON gcpt.channel_type_id = gct.channel_type_id AND
         -- If a specific licence is requested
        (channelType <> 'all' AND
        gct.channel_type = channelType)
        OR
        -- Otherwise take all licenses
        (channelType = 'all' AND
        gct.channel_type_id > -1)
        
      JOIN gaming_license_type AS glt ON glt.license_type_id = ggp_bet.license_type_id  AND
        -- If a specific licence is requested
        (licenseType <> 'all' AND
        glt.`name` = licenseType)
        OR
        -- Otherwise take all licenses
        (licenseType = 'all' AND
        glt.license_type_id = 4)
      
      WHERE 
        ggp.client_stat_id = clientStatID
        AND ggp.payment_transaction_type_id IN (20)
         AND ggp_bet.`timestamp` BETWEEN  CONCAT(DATE_ADD(vCurdate, interval -(vNumDays) DAY),' ',TIME(vNow))
          AND DATE_ADD(vCurdate, interval (vNumDays-1) DAY);
    **/
      
    IF (vTotalRolling IS NOT NULL) THEN
       SET limitAmount = vTotalRolling;
       SET currentAmount = ifnull(vRollingAmount,0);        
       SET limitExists = 1;
    END IF;

  END IF;
END$$

DELIMITER ;

