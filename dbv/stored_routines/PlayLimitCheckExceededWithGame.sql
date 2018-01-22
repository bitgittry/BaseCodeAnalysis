DROP function IF EXISTS `PlayLimitCheckExceededWithGame`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PlayLimitCheckExceededWithGame`(
  transactionAmount DECIMAL(18, 5), sessionID BIGINT, clientStatID BIGINT, licenseType VARCHAR(20), gameID BIGINT) RETURNS tinyint(1)
    DETERMINISTIC
BEGIN

  -- Game Level
  -- Operator Level  
  -- Fixed time limit bug for admin limits 
  -- Updated with new SP for rolling limits 
  
  DECLARE limitExceededCount, limitExceededAdminCount, checklimitExceeded, vNumDays INT DEFAULT -1;
  DECLARE rollingLimitPlayerAmount, rollingLimitPlayerAmountCurrent,
    rollingLimitAdminAmount, rollingLimitAdminAmountCurrent DECIMAL(18,5) DEFAULT 0;
    
  DECLARE allowInsert TINYINT(1) DEFAULT transactionAmount > 0;

  DECLARE vNow DATETIME;
  DECLARE vCurdate DATE DEFAULT CURDATE();
  DECLARE playLimitGameLevelEnabled, operatorLimitsEnabled, rollingLevelEnabled, rollingLimitPlayerExists, rollingLimitAdminExists, checkIpBanning, countryDisallowLoginFromIP TINYINT(1) DEFAULT 0;
  DECLARE channelType VARCHAR(20) DEFAULT NULL;    
  DECLARE countryIdFromIp, countryRegionIdFromIp BIGINT DEFAULT NULL;   
  
  SET @license_type = licenseType;

  SELECT value_bool INTO playLimitGameLevelEnabled FROM gaming_settings WHERE `name`='PLAY_LIMIT_GAME_LEVEL_ENABLED';
  SELECT value_bool INTO operatorLimitsEnabled FROM gaming_settings WHERE `name`='OPERATOR_DEFAULT_PLAY_LIMITS';
  SELECT value_bool INTO rollingLevelEnabled FROM gaming_settings WHERE `name`='ROLLING_LIMIT_ENABLED';
  SELECT value_bool INTO checkIpBanning FROM gaming_settings WHERE `name`='FRAUD_IP_TO_COUNTRY_ENABLED';
  



  -- Get Channel Type
  SELECT gaming_channel_types.channel_type, sessions_main.country_id_from_ip, sessions_main.country_region_id_from_ip INTO channelType, countryIdFromIp, countryRegionIdFromIp
  FROM sessions_main FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_platform_types ON gaming_platform_types.platform_type_id=sessions_main.platform_type_id
  STRAIGHT_JOIN gaming_channels_platform_types ON gaming_channels_platform_types.platform_type_id=gaming_platform_types.platform_type_id
  LEFT JOIN  gaming_channel_types ON 
	gaming_channel_types.channel_type_id=gaming_channels_platform_types.channel_type_id
     AND gaming_channel_types.is_active = 1 AND gaming_channel_types.play_limits_active = 1
  WHERE sessions_main.session_id = sessionID;


  IF (checkIpBanning = 1) THEN
    SELECT 1 INTO countryDisallowLoginFromIP
    FROM gaming_fraud_banned_countries_from_ips
    WHERE (country_id = IFNULL(countryIdFromIp,0) AND country_region_id = 0 AND disallow_play=1) OR (country_id= IFNULL(countryIdFromIp,0) AND country_region_id = IFNULL(countryRegionIdFromIp,0) AND disallow_play=1);
    IF (countryDisallowLoginFromIP=1) THEN
      RETURN 10;
    END IF;
  END IF;

    
  SET @channel_type = channelType;
  
  SELECT license_type_id INTO @license_type_id FROM gaming_license_type WHERE `name`=@license_type;
  SELECT channel_type_id INTO @channel_type_id FROM gaming_channel_types WHERE `channel_type`=@channel_type;
  
  IF (playLimitGameLevelEnabled=0) THEN
	SET gameID=NULL;
  END IF;
 
  CALL PlayLimitsCurrentCheck(clientStatID, sessionID, licenseType, gameID, @channel_type, allowInsert);
  
  SET vNow = NOW();

  /**
  * Rolling limits
  */
  IF(rollingLevelEnabled = 1) THEN
    -- Per-player limit check
    /**
    * Global - All
    */    
    CALL PlayLimitGetRollingLimitValues(clientStatID, 'all', 'all', 0, rollingLimitPlayerExists, rollingLimitPlayerAmount, rollingLimitPlayerAmountCurrent);    
    -- Is current limit amount + transaction more than limit?
    IF (rollingLimitPlayerExists AND (rollingLimitPlayerAmountCurrent + IFNULL(transactionAmount,0) > rollingLimitPlayerAmount)) THEN      		     	
      CALL NotificationEventCreate(622, transactionAmount, clientStatID, 0);
      RETURN 1;
    END IF;

    /**
    * Global - Specific license
    */    
    CALL PlayLimitGetRollingLimitValues(clientStatID, @license_type, 'all', 0, rollingLimitPlayerExists, rollingLimitPlayerAmount, rollingLimitPlayerAmountCurrent);    
    -- Is current limit amount + transaction more than limit?
    IF (rollingLimitPlayerExists AND (rollingLimitPlayerAmountCurrent + IFNULL(transactionAmount,0) > rollingLimitPlayerAmount)) THEN      		     	
      CALL NotificationEventCreate(622, transactionAmount, clientStatID, 0);
      RETURN 1;
    END IF;

    /**
    * Specific channel - All
    */    
    CALL PlayLimitGetRollingLimitValues(clientStatID, 'all', @channel_type, 0, rollingLimitPlayerExists, rollingLimitPlayerAmount, rollingLimitPlayerAmountCurrent);    
    -- Is current limit amount + transaction more than limit?
    IF (rollingLimitPlayerExists AND (rollingLimitPlayerAmountCurrent + IFNULL(transactionAmount,0) > rollingLimitPlayerAmount)) THEN      		     	
      CALL NotificationEventCreate(622, transactionAmount, clientStatID, 0);
      RETURN 1;
    END IF;

    /**
    * Specific channel - Specific license
    */    
    CALL PlayLimitGetRollingLimitValues(clientStatID,  @license_type, @channel_type, 0, rollingLimitPlayerExists, rollingLimitPlayerAmount, rollingLimitPlayerAmountCurrent);    
    -- Is current limit amount + transaction more than limit?
    IF (rollingLimitPlayerExists AND (rollingLimitPlayerAmountCurrent + IFNULL(transactionAmount,0) > rollingLimitPlayerAmount)) THEN      		     	
      CALL NotificationEventCreate(622, transactionAmount, clientStatID, 0);
      RETURN 1;
    END IF;


            
    IF (operatorLimitsEnabled) THEN
      -- Operator level limit check
     /**
      * Global - All
      */
      CALL PlayLimitGetRollingLimitValues(clientStatID, 'all', 'all', 1, rollingLimitAdminExists, rollingLimitAdminAmount, rollingLimitAdminAmountCurrent);      
    	-- Is current limit amount + transaction more than limit?          
    	IF (rollingLimitAdminExists AND (rollingLimitAdminAmountCurrent + IFNULL(transactionAmount,0) > rollingLimitAdminAmount)) THEN      		     	
	      CALL NotificationEventCreate(622, transactionAmount, clientStatID, 0);
        RETURN 1;
      END IF;		

     /**
      * Global - Specific license
      */
      CALL PlayLimitGetRollingLimitValues(clientStatID, @license_type, 'all', 1, rollingLimitAdminExists, rollingLimitAdminAmount, rollingLimitAdminAmountCurrent);      
    	-- Is current limit amount + transaction more than limit?          
    	IF (rollingLimitAdminExists AND (rollingLimitAdminAmountCurrent + IFNULL(transactionAmount,0) > rollingLimitAdminAmount)) THEN      		     	
	      CALL NotificationEventCreate(622, transactionAmount, clientStatID, 0);
        RETURN 1;
      END IF;		


     /**
      * Specific channel - All
      */
      CALL PlayLimitGetRollingLimitValues(clientStatID, 'all', @channel_type, 1, rollingLimitAdminExists, rollingLimitAdminAmount, rollingLimitAdminAmountCurrent);      
    	-- Is current limit amount + transaction more than limit?          
    	IF (rollingLimitAdminExists AND (rollingLimitAdminAmountCurrent + IFNULL(transactionAmount,0) > rollingLimitAdminAmount)) THEN      		     	
	      CALL NotificationEventCreate(622, transactionAmount, clientStatID, 0);
        RETURN 1;
      END IF;

     /**
      * Specific channel - Specific license
      */
      CALL PlayLimitGetRollingLimitValues(clientStatID,  @license_type, @channel_type, 1, rollingLimitAdminExists, rollingLimitAdminAmount, rollingLimitAdminAmountCurrent);      
    	-- Is current limit amount + transaction more than limit?          
    	IF (rollingLimitAdminExists AND (rollingLimitAdminAmountCurrent + IFNULL(transactionAmount,0) > rollingLimitAdminAmount)) THEN      		     	
	      CALL NotificationEventCreate(622, transactionAmount, clientStatID, 0);
        RETURN 1;
      END IF;
    END IF;
  END IF;


  
  SELECT COUNT(*) AS limits_passed 
  INTO limitExceededCount
  FROM gaming_client_stats FORCE INDEX (PRIMARY)
  -- Player Level Limits
  STRAIGHT_JOIN gaming_play_limits gpl FORCE INDEX (active_player_license_channel_game) ON
	(gpl.client_stat_id=gaming_client_stats.client_stat_id AND gpl.is_active = 1) AND 
    gpl.license_type_id IN (@license_type_id, 4) AND -- all: 4
	gpl.channel_type_id IN (@channel_type_id, 0) AND -- all: 0
    (gpl.game_id IS NULL OR (gameID IS NULL AND gpl.game_id IS NULL) OR (gameID IS NOT NULL AND gpl.game_id=gameID)) AND
    ((gpl.end_date >= vNow OR gpl.end_date IS NULL) AND gpl.start_date <= vNow) 	
  STRAIGHT_JOIN gaming_interval_type git ON gpl.interval_type_id=git.interval_type_id
  STRAIGHT_JOIN gaming_play_limit_type AS gplt ON gpl.play_limit_type_id=gplt.play_limit_type_id
  -- Current Values (Player Level)
  LEFT JOIN gaming_player_current_limits gpcl FORCE INDEX (PRIMARY) ON 
	(gpcl.client_stat_id = gpl.client_stat_id AND gpcl.play_limit_type_id = gpl.play_limit_type_id 
		AND gpcl.interval_type_id = gpl.interval_type_id AND gpcl.license_type_id=gpl.license_type_id 
        AND gpcl.channel_type_id = gpl.channel_type_id
	)
  LEFT JOIN gaming_player_current_game_limits gpcgl FORCE INDEX (PRIMARY) ON 
	(gpcgl.client_stat_id = gpl.client_stat_id AND gpcgl.play_limit_type_id = gpl.play_limit_type_id 
		AND gpcgl.interval_type_id = gpl.interval_type_id AND gpcgl.license_type_id=gpl.license_type_id 
        AND gpcgl.game_id=gameID AND gpcl.channel_type_id = gpl.channel_type_id
	)	
  -- Session 
  LEFT JOIN sessions_main sm FORCE INDEX (PRIMARY) ON sm.session_id = sessionID
  WHERE gaming_client_stats.client_stat_id=clientStatID AND 
		(gpl.limit_amount IS NOT NULL AND (SELECT CASE gplt.name
		  WHEN 'BET_AMOUNT_LIMIT' THEN IFNULL(IF(gpl.game_id IS NULL, gpcl.amount, gpcgl.amount), 0)+transactionAmount > gpl.limit_amount
		  WHEN 'LOSS_AMOUNT_LIMIT' THEN IFNULL(IF(gpl.game_id IS NULL, gpcl.amount, gpcgl.amount), 0)+transactionAmount > gpl.limit_amount
		  WHEN 'DIRECT_BLOCK_LIMIT' THEN 1
		  WHEN 'TIME_LIMIT' THEN IFNULL(TIMESTAMPDIFF(MINUTE, sm.date_open, vNow) >= gpl.limit_amount, 0)
		END)=1);
  
  IF (limitExceededCount>0) THEN
	RETURN 1;
  END IF;

-- all: 0

  IF (operatorLimitsEnabled) THEN
	  SELECT COUNT(*) AS limits_passed INTO limitExceededAdminCount
	  FROM gaming_client_stats FORCE INDEX (PRIMARY)
	  STRAIGHT_JOIN gaming_play_limits_admin gpl_admin FORCE INDEX (active_license_channel_game) ON
		gpl_admin.is_active = 1 AND 
        gpl_admin.license_type_id IN (@license_type_id, 4) AND -- all: 4
        gpl_admin.channel_type_id IN (@channel_type_id, 0) AND -- all: 0
		(gpl_admin.game_id IS NULL OR (gameID IS NULL AND gpl_admin.game_id IS NULL) OR (gameID IS NOT NULL AND gpl_admin.game_id=gameID)) AND
        ((gpl_admin.end_date >= vNow OR gpl_admin.end_date IS NULL) AND gpl_admin.start_date <= vNow) 
	  STRAIGHT_JOIN gaming_interval_type AS git_admin ON gpl_admin.interval_type_id=git_admin.interval_type_id
	  STRAIGHT_JOIN gaming_play_limit_type AS gplt_admin ON gpl_admin.play_limit_type_id=gplt_admin.play_limit_type_id
      LEFT JOIN gaming_play_limits_admin_amounts AS gpl_amount_admin ON 
		gpl_admin.play_limit_admin_id=gpl_amount_admin.play_limit_admin_id AND 
		gpl_amount_admin.currency_id=gaming_client_stats.currency_id
	  LEFT JOIN gaming_player_current_limits AS gpcl_admin  FORCE INDEX (PRIMARY) ON 
		gpcl_admin.client_stat_id = gaming_client_stats.client_stat_id AND gpcl_admin.play_limit_type_id = gpl_admin.play_limit_type_id AND 
        gpcl_admin.interval_type_id = gpl_admin.interval_type_id AND gpcl_admin.license_type_id=gpl_admin.license_type_id AND 
        gpcl_admin.channel_type_id = gpl_admin.channel_type_id
	  LEFT JOIN gaming_player_current_game_limits AS gpcgl_admin FORCE INDEX (PRIMARY) ON 
		gpcgl_admin.client_stat_id = gaming_client_stats.client_stat_id AND gpcgl_admin.play_limit_type_id = gpl_admin.play_limit_type_id AND 
        gpcgl_admin.interval_type_id = gpl_admin.interval_type_id AND gpcgl_admin.license_type_id=gpl_admin.license_type_id AND 
        gpcgl_admin.game_id=gameID AND gpcgl_admin.channel_type_id = gpl_admin.channel_type_id
	  LEFT JOIN sessions_main sm  FORCE INDEX (PRIMARY) ON sm.session_id = sessionID
	  WHERE gaming_client_stats.client_stat_id=clientStatID AND 
		(SELECT CASE gplt_admin.name
			  WHEN 'BET_AMOUNT_LIMIT' THEN IFNULL(IF(gpl_admin.game_id IS NULL, gpcl_admin.amount, gpcgl_admin.amount), 0)+transactionAmount > gpl_amount_admin.limit_amount
			  WHEN 'LOSS_AMOUNT_LIMIT' THEN IFNULL(IF(gpl_admin.game_id IS NULL, gpcl_admin.amount, gpcgl_admin.amount), 0)+transactionAmount > gpl_amount_admin.limit_amount
			  WHEN 'DIRECT_BLOCK_LIMIT' THEN 1
			  WHEN 'TIME_LIMIT' THEN IFNULL(TIMESTAMPDIFF(MINUTE, sm.date_open, vNow) >= gpl_admin.limit_amount, 0)
			END)=1; 
 
	  RETURN limitExceededAdminCount > 0;
  END IF;

  RETURN 0;

END$$

DELIMITER ;

