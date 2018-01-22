DROP function IF EXISTS `PlayLimitsUpdateFunc`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PlayLimitsUpdateFunc`(sessionID BIGINT, clientStatID BIGINT, licenseType VARCHAR(20), transactionAmount DECIMAL(18,5), isBet tinyint(1), gameID BIGINT) RETURNS int(11)
BEGIN
    -- Added Game Level   
	-- Added handling of limit_percentage 
    -- Added inserting push notifications  
    -- Added history of aggregated bets for rolling limits
	-- Optimized  
 
    DECLARE pushNotificationsEnabled TINYINT(1) DEFAULT 0;
	DECLARE playLimitGameLevelEnabled TINYINT(1) DEFAULT 0;
	DECLARE notificationEventTypeId INT;
    DECLARE vNow DATETIME DEFAULT NOW();
    DECLARE vCurdate DATE DEFAULT CURDATE();
	DECLARE currencyID BIGINT DEFAULT -1;
    DECLARE channelType VARCHAR(20) DEFAULT NULL;  
	DECLARE clientID BIGINT;

    SELECT value_bool INTO pushNotificationsEnabled FROM gaming_settings WHERE name='NOTIFICATION_ENABLED';
    SELECT value_bool INTO playLimitGameLevelEnabled FROM gaming_settings WHERE name='PLAY_LIMIT_GAME_LEVEL_ENABLED';
	SELECT notification_event_type_id INTO notificationEventTypeId FROM notifications_event_types WHERE event_name = 'PlayLimitThresholdReached';
	SELECT client_id, currency_id INTO clientID, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID;

    IF (sessionID IS NULL OR sessionID = 0) THEN
		SELECT session_id INTO sessionID FROM sessions_main FORCE INDEX (client_latest_session) WHERE extra_id = clientID AND is_latest = 1;
	END IF;

	-- Get Channel Type
	SELECT gaming_channel_types.channel_type INTO channelType
	FROM sessions_main FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_platform_types ON sessions_main.platform_type_id = gaming_platform_types.platform_type_id
	STRAIGHT_JOIN gaming_channels_platform_types ON gaming_platform_types.platform_type_id = gaming_channels_platform_types.platform_type_id
	STRAIGHT_JOIN gaming_channel_types ON gaming_channels_platform_types.channel_type_id = gaming_channel_types.channel_type_id
	WHERE sessions_main.session_id = sessionID AND gaming_channel_types.is_active = 1 AND gaming_channel_types.play_limits_active = 1;

	SET @license_type = licenseType;
	SET @channel_type = channelType;

    IF isBet = 1 THEN
        INSERT INTO gaming_player_current_limits (client_stat_id, play_limit_type_id, interval_type_id, license_type_id, channel_type_id, amount, limit_percentage)
           SELECT clientStatID as client_stat_id, gplt.play_limit_type_id, git.interval_type_id, glt.license_type_id, gaming_channel_types.channel_type_id, IFNULL(gpcl.amount,0)+transactionAmount as amount_insert, 
				IFNULL((IFNULL(gpcl.amount,0)+transactionAmount)/
				IF(gpl_amount_admin.limit_amount IS NULL OR gpl.limit_amount IS NULL, 
					COALESCE(gpl_amount_admin.limit_amount, gpl.limit_amount), 
					LEAST(gpl_amount_admin.limit_amount, gpl.limit_amount)), 0)*100 AS limit_percentage
           FROM gaming_play_limit_type gplt
           STRAIGHT_JOIN gaming_interval_type git ON (git.is_play_limit AND git.`name`!='Transaction' AND git.`name`!='Rolling')
           STRAIGHT_JOIN gaming_license_type glt ON (glt.name=@license_type OR glt.name='all') AND glt.is_active=1
           STRAIGHT_JOIN gaming_channel_types ON 
				((@channel_type IS NOT NULL AND gaming_channel_types.channel_type = @channel_type) OR 
					(gaming_channel_types.channel_type = 'all'))
           LEFT JOIN gaming_player_current_limits gpcl FORCE INDEX (PRIMARY) ON (gplt.play_limit_type_id = gpcl.play_limit_type_id AND git.interval_type_id = gpcl.interval_type_id AND glt.license_type_id=gpcl.license_type_id AND client_stat_id = clientStatID AND gpcl.channel_type_id = gaming_channel_types.channel_type_id)
		   -- for the percentage
		   LEFT JOIN gaming_play_limits AS gpl FORCE INDEX (player_limit_interval_game_channel) ON gpl.client_stat_id=clientStatID AND 
			  gpl.license_type_id=glt.license_type_id AND gpl.play_limit_type_id=gplt.play_limit_type_id AND gpl.interval_type_id=git.interval_type_id AND
			  ((gpl.end_date >= vNow OR gpl.end_date IS NULL) AND gpl.start_date <= vNow) AND 
			  (gpl.is_active=1 AND (gpl.end_date IS NULL OR gpl.end_date >= vNow) AND gpl.start_date <= vNow) AND
			  gpl.game_id IS NULL AND gpl.channel_type_id = gaming_channel_types.channel_type_id
		   LEFT JOIN gaming_play_limits_admin AS gpl_admin FORCE INDEX (limit_license_interval_active_game_channel) ON
			    (gpl_admin.license_type_id=glt.license_type_id AND gpl_admin.channel_type_id = gaming_channel_types.channel_type_id AND gpl_admin.play_limit_type_id=gplt.play_limit_type_id AND gpl_admin.interval_type_id=git.interval_type_id) AND
			    gpl_admin.is_active=1 AND
				((gpl_admin.end_date >= NOW() OR gpl_admin.end_date IS NULL) AND gpl_admin.start_date <= vNow) AND 
				(gpl_admin.is_active=1 AND (gpl_admin.end_date IS NULL OR gpl_admin.end_date >= vNow) AND gpl_admin.start_date <= vNow) AND
				gpl_admin.game_id IS NULL
			LEFT JOIN gaming_play_limits_admin_amounts AS gpl_amount_admin FORCE INDEX (PRIMARY) ON gpl_admin.play_limit_admin_id=gpl_amount_admin.play_limit_admin_id AND gpl_amount_admin.currency_id=currencyID

		   WHERE gplt.name = 'BET_AMOUNT_LIMIT' OR gplt.name = 'LOSS_AMOUNT_LIMIT'
        ON DUPLICATE KEY UPDATE 
			gaming_player_current_limits.limit_percentage = IFNULL((gpcl.amount+transactionAmount)/
				IF(gpl_amount_admin.limit_amount IS NULL OR gpl.limit_amount IS NULL, 
					COALESCE(gpl_amount_admin.limit_amount, gpl.limit_amount), 
					LEAST(gpl_amount_admin.limit_amount, gpl.limit_amount)), 0)*100,
			gaming_player_current_limits.amount = gpcl.amount+transactionAmount;
            
            
        
			-- add data to aggregation history
		INSERT INTO gaming_player_current_limits_aggregation_history  
           (client_stat_id, play_limit_type_id, interval_type_id, license_type_id, channel_type_id, amount, limit_percentage, interval_type_reference)
           SELECT clientStatID as client_stat_id, gplt.play_limit_type_id, git.interval_type_id, glt.license_type_id, gaming_channel_types.channel_type_id, 
           transactionAmount as amount_insert, 0 AS limit_percentage, vCurdate as interval_type_reference
           FROM gaming_play_limit_type gplt
           STRAIGHT_JOIN gaming_interval_type git ON (git.is_play_limit AND git.`name`='Rolling')
           STRAIGHT_JOIN gaming_license_type glt ON (glt.name=@license_type) AND glt.is_active=1
           STRAIGHT_JOIN gaming_channel_types ON 
				((@channel_type IS NOT NULL AND gaming_channel_types.channel_type = @channel_type) OR 
					(gaming_channel_types.channel_type = 'all'))
           LEFT JOIN gaming_player_current_limits_aggregation_history gpcl FORCE INDEX (PRIMARY) ON (gplt.play_limit_type_id = gpcl.play_limit_type_id AND git.interval_type_id = gpcl.interval_type_id AND glt.license_type_id=gpcl.license_type_id AND client_stat_id = clientStatID AND gpcl.channel_type_id = gaming_channel_types.channel_type_id 
           AND gpcl.interval_type_reference = vCurdate )
		   WHERE gplt.name = 'BET_AMOUNT_LIMIT' AND gpcl.client_stat_id IS NULL OR gpcl.interval_type_reference=vCurdate
        ON DUPLICATE KEY UPDATE 
			gaming_player_current_limits_aggregation_history.limit_percentage = 0,
			gaming_player_current_limits_aggregation_history.amount = gpcl.amount+transactionAmount;
  
                
    ELSE
        INSERT INTO gaming_player_current_limits (client_stat_id, play_limit_type_id, interval_type_id, license_type_id, channel_type_id, amount, limit_percentage)
           SELECT clientStatID as client_stat_id, gplt.play_limit_type_id, git.interval_type_id, glt.license_type_id, gaming_channel_types.channel_type_id, IFNULL(gpcl.amount,0)-transactionAmount as amount_insert,
				IFNULL((IFNULL(gpcl.amount,0)-transactionAmount)/
				IF(gpl_amount_admin.limit_amount IS NULL OR gpl.limit_amount IS NULL, 
					COALESCE(gpl_amount_admin.limit_amount, gpl.limit_amount), 
					LEAST(gpl_amount_admin.limit_amount, gpl.limit_amount)), 0)*100 AS limit_percentage 
           FROM gaming_play_limit_type gplt
           STRAIGHT_JOIN gaming_interval_type git ON (git.is_play_limit AND git.`name`!='Transaction' AND git.`name`!='Rolling')
           STRAIGHT_JOIN gaming_license_type glt ON (glt.name=@license_type OR glt.name='all') AND glt.is_active=1
           STRAIGHT_JOIN gaming_channel_types ON
				((@channel_type IS NOT NULL AND gaming_channel_types.channel_type = @channel_type) OR 
					(gaming_channel_types.channel_type = 'all'))
           LEFT JOIN gaming_player_current_limits gpcl FORCE INDEX (PRIMARY) ON (gplt.play_limit_type_id = gpcl.play_limit_type_id AND git.interval_type_id = gpcl.interval_type_id AND glt.license_type_id=gpcl.license_type_id AND client_stat_id = clientStatID AND gpcl.channel_type_id = gaming_channel_types.channel_type_id)
			-- for the percentage
		   LEFT JOIN gaming_play_limits AS gpl FORCE INDEX (player_limit_interval_game_channel) ON gpl.client_stat_id=clientStatID AND 
			  gpl.license_type_id=glt.license_type_id AND gpl.channel_type_id = gaming_channel_types.channel_type_id AND gpl.play_limit_type_id=gplt.play_limit_type_id AND gpl.interval_type_id=git.interval_type_id AND
			  ((gpl.end_date >= vNow OR gpl.end_date IS NULL) AND gpl.start_date <= vNow) AND 
			  (gpl.is_active=1 AND (gpl.end_date IS NULL OR gpl.end_date >= vNow) AND gpl.start_date <= vNow) AND
			  gpl.game_id IS NULL
		   LEFT JOIN gaming_play_limits_admin AS gpl_admin FORCE INDEX (limit_license_interval_active_game_channel) ON
			    (gpl_admin.license_type_id=glt.license_type_id AND gpl_admin.channel_type_id = gaming_channel_types.channel_type_id AND gpl_admin.play_limit_type_id=gplt.play_limit_type_id AND gpl_admin.interval_type_id=git.interval_type_id) AND
			    gpl_admin.is_active=1 AND
				((gpl_admin.end_date >= NOW() OR gpl_admin.end_date IS NULL) AND gpl_admin.start_date <= vNow) AND 
				(gpl_admin.is_active=1 AND (gpl_admin.end_date IS NULL OR gpl_admin.end_date >= vNow) AND gpl_admin.start_date <= vNow) AND
				gpl_admin.game_id IS NULL
			LEFT JOIN gaming_play_limits_admin_amounts AS gpl_amount_admin FORCE INDEX (PRIMARY) ON gpl_admin.play_limit_admin_id=gpl_amount_admin.play_limit_admin_id AND gpl_amount_admin.currency_id=currencyID

           WHERE gplt.name = 'LOSS_AMOUNT_LIMIT'
        ON DUPLICATE KEY UPDATE gaming_player_current_limits.amount = gpcl.amount-transactionAmount,
			gaming_player_current_limits.limit_percentage = IFNULL((gpcl.amount-transactionAmount)/
				IF(gpl_amount_admin.limit_amount IS NULL OR gpl.limit_amount IS NULL, 
					COALESCE(gpl_amount_admin.limit_amount, gpl.limit_amount), 
					LEAST(gpl_amount_admin.limit_amount, gpl.limit_amount)), 0)*100;
                    
                    
	 
    END IF;

	-- Game Level
	IF (playLimitGameLevelEnabled=1 AND gameID IS NOT NULL AND gameID > 0) THEN
		IF isBet = 1 THEN
			INSERT INTO gaming_player_current_game_limits (client_stat_id, play_limit_type_id, interval_type_id, license_type_id, channel_type_id, game_id, amount, limit_percentage)
			   SELECT clientStatID as client_stat_id, gplt.play_limit_type_id, git.interval_type_id, glt.license_type_id, IFNULL(gaming_channel_types.channel_type_id,0), gameID, IFNULL(gpcl.amount,0)+transactionAmount as amount_insert,
			     IFNULL((IFNULL(gpcl.amount,0)+transactionAmount)/
				IF(gpl_amount_admin.limit_amount IS NULL OR gpl.limit_amount IS NULL, 
					COALESCE(gpl_amount_admin.limit_amount, gpl.limit_amount), 
					LEAST(gpl_amount_admin.limit_amount, gpl.limit_amount)), 0)*100 AS limit_percentage
			   FROM gaming_play_limit_type gplt
			   STRAIGHT_JOIN gaming_interval_type git ON (git.is_play_limit AND git.`name`!='Transaction' AND git.`name`!='Rolling')
			   STRAIGHT_JOIN gaming_license_type glt ON glt.name=@license_type
               STRAIGHT_JOIN gaming_channel_types ON 
				((@channel_type IS NOT NULL AND gaming_channel_types.channel_type = @channel_type) OR 
					(gaming_channel_types.channel_type = 'all'))
			   LEFT JOIN gaming_player_current_game_limits gpcl FORCE INDEX (PRIMARY) ON (gplt.play_limit_type_id = gpcl.play_limit_type_id AND git.interval_type_id = gpcl.interval_type_id AND gpcl.license_type_id=glt.license_type_id AND gpcl.channel_type_id = gaming_channel_types.channel_type_id AND gpcl.game_id=gameID AND gpcl.client_stat_id = clientStatID)
			   -- for the percentage
			   LEFT JOIN gaming_play_limits AS gpl FORCE INDEX (player_limit_interval_game_channel) ON gpl.client_stat_id=clientStatID AND 
				  gpl.license_type_id=glt.license_type_id AND gpl.channel_type_id = gaming_channel_types.channel_type_id AND gpl.play_limit_type_id=gplt.play_limit_type_id AND gpl.interval_type_id=git.interval_type_id AND
				  ((gpl.end_date >= vNow OR gpl.end_date IS NULL) AND gpl.start_date <= vNow) AND 
				  (gpl.is_active=1 AND (gpl.end_date IS NULL OR gpl.end_date >= vNow) AND gpl.start_date <= vNow) AND
				  (gpcl.game_id IS NOT NULL AND gpl.game_id=gpcl.game_id) 
			   LEFT JOIN gaming_play_limits_admin AS gpl_admin FORCE INDEX (limit_license_interval_active_game_channel) ON
					(gpl_admin.license_type_id=glt.license_type_id AND gpl_admin.channel_type_id = gaming_channel_types.channel_type_id AND gpl_admin.play_limit_type_id=gplt.play_limit_type_id AND gpl_admin.interval_type_id=git.interval_type_id) AND
					gpl_admin.is_active=1 AND
					((gpl_admin.end_date >= NOW() OR gpl_admin.end_date IS NULL) AND gpl_admin.start_date <= vNow) AND 
					(gpl_admin.is_active=1 AND (gpl_admin.end_date IS NULL OR gpl_admin.end_date >= vNow) AND gpl_admin.start_date <= vNow) AND
					(gpcl.game_id IS NOT NULL AND gpl_admin.game_id=gpcl.game_id)
				LEFT JOIN gaming_play_limits_admin_amounts AS gpl_amount_admin FORCE INDEX (PRIMARY) ON gpl_admin.play_limit_admin_id=gpl_amount_admin.play_limit_admin_id AND gpl_amount_admin.currency_id=currencyID

			   WHERE gplt.name = 'BET_AMOUNT_LIMIT' OR gplt.name = 'LOSS_AMOUNT_LIMIT'
			ON DUPLICATE KEY UPDATE 
				gaming_player_current_game_limits.limit_percentage = IFNULL((gpcl.amount+transactionAmount)/
				IF(gpl_amount_admin.limit_amount IS NULL OR gpl.limit_amount IS NULL, 
					COALESCE(gpl_amount_admin.limit_amount, gpl.limit_amount), 
					LEAST(gpl_amount_admin.limit_amount, gpl.limit_amount)), 0)*100,
				gaming_player_current_game_limits.amount = gpcl.amount+transactionAmount;
		ELSE

			INSERT INTO gaming_player_current_game_limits (client_stat_id, play_limit_type_id, interval_type_id, license_type_id, channel_type_id, game_id, amount, limit_percentage)
			  SELECT clientStatID as client_stat_id, gplt.play_limit_type_id, git.interval_type_id, glt.license_type_id, IFNULL(gaming_channel_types.channel_type_id,0), gameID, IFNULL(gpcl.amount,0)-transactionAmount as amount_insert,
				IFNULL((IFNULL(gpcl.amount,0)-transactionAmount)/
				IF(gpl_amount_admin.limit_amount IS NULL OR gpl.limit_amount IS NULL, 
					COALESCE(gpl_amount_admin.limit_amount, gpl.limit_amount), 
					LEAST(gpl_amount_admin.limit_amount, gpl.limit_amount)), 0)*100 AS limit_percentage 
		      FROM gaming_play_limit_type gplt
			  STRAIGHT_JOIN gaming_interval_type git ON (git.is_play_limit AND git.`name`!='Transaction' AND git.`name`!='Rolling')
			  STRAIGHT_JOIN gaming_license_type glt ON glt.name=@license_type
			  STRAIGHT_JOIN gaming_channel_types ON 
				((@channel_type IS NOT NULL AND gaming_channel_types.channel_type = @channel_type) OR 
					(gaming_channel_types.channel_type = 'all'))	
			  LEFT JOIN gaming_player_current_game_limits gpcl FORCE INDEX (PRIMARY) ON (gplt.play_limit_type_id = gpcl.play_limit_type_id AND git.interval_type_id = gpcl.interval_type_id AND gpcl.license_type_id=glt.license_type_id AND gpcl.channel_type_id = gaming_channel_types.channel_type_id AND gpcl.game_id=gameID AND gpcl.client_stat_id = clientStatID)
 
				-- for the percentage
		   LEFT JOIN gaming_play_limits AS gpl FORCE INDEX (player_limit_interval_game_channel) ON gpl.client_stat_id=clientStatID AND 
			  gpl.license_type_id=glt.license_type_id AND gpl.play_limit_type_id=gplt.play_limit_type_id AND gpl.interval_type_id=git.interval_type_id AND
			  ((gpl.end_date >= vNow OR gpl.end_date IS NULL) AND gpl.start_date <= vNow) AND 
			  (gpl.is_active=1 AND (gpl.end_date IS NULL OR gpl.end_date >= vNow) AND gpl.start_date <= vNow) AND
			  gpl.game_id IS NULL AND gpl.channel_type_id = gaming_channel_types.channel_type_id
		   LEFT JOIN gaming_play_limits_admin AS gpl_admin FORCE INDEX (limit_license_interval_active_game_channel) ON
			    (gpl_admin.license_type_id=glt.license_type_id AND gpl_admin.channel_type_id = gaming_channel_types.channel_type_id AND gpl_admin.play_limit_type_id=gplt.play_limit_type_id AND gpl_admin.interval_type_id=git.interval_type_id) AND
			    gpl_admin.is_active=1 AND
				((gpl_admin.end_date >= NOW() OR gpl_admin.end_date IS NULL) AND gpl_admin.start_date <= vNow) AND 
				(gpl_admin.is_active=1 AND (gpl_admin.end_date IS NULL OR gpl_admin.end_date >= vNow) AND gpl_admin.start_date <= vNow) AND
				gpl_admin.game_id IS NULL
			LEFT JOIN gaming_play_limits_admin_amounts AS gpl_amount_admin FORCE INDEX (PRIMARY) ON gpl_admin.play_limit_admin_id=gpl_amount_admin.play_limit_admin_id AND gpl_amount_admin.currency_id=currencyID

			  WHERE gplt.name = 'LOSS_AMOUNT_LIMIT'
			ON DUPLICATE KEY UPDATE gaming_player_current_game_limits.amount = gpcl.amount-transactionAmount,
				gaming_player_current_game_limits.limit_percentage = IFNULL((gpcl.amount-transactionAmount)/
				IF(gpl_amount_admin.limit_amount IS NULL OR gpl.limit_amount IS NULL, 
					COALESCE(gpl_amount_admin.limit_amount, gpl.limit_amount), 
					LEAST(gpl_amount_admin.limit_amount, gpl.limit_amount)), 0)*100;
		END IF;
	END IF;
 
	-- Notification BEGIN
    -- non-game level
	IF pushNotificationsEnabled THEN 

		-- game level 
		IF (playLimitGameLevelEnabled=1) THEN
        
			SET @round_row_count=1;
			SET @play_limit_type_id=-1;
			SET @license_type_id=-1;
			SET @channel_type_id=-1;
        
			INSERT INTO gaming_play_limits_notification_rule_events (play_limit_notification_rule_id, client_stat_id, date_created)
			SELECT play_limit_notification_rule_id, clientStatID, vNow
            FROM (
				SELECT PP.*, 
					@round_row_count:=IF(@play_limit_type_id!=play_limit_type_id OR @license_type_id!=license_type_id, 1, @round_row_count+1) AS round_row_count, 
                    @play_limit_type_id:=play_limit_type_id, @license_type_id:=license_type_id, @channel_type_id:=channel_type_id
				FROM (
					SELECT gplnr.play_limit_notification_rule_id, gpcgl.play_limit_type_id, gpcgl.license_type_id, gpcgl.channel_type_id
					FROM gaming_play_limits_notification_rules as gplnr FORCE INDEX (is_active)
					STRAIGHT_JOIN gaming_player_current_game_limits as gpcgl FORCE INDEX (PRIMARY) ON 
						gpcgl.client_stat_id = clientStatID AND gplnr.play_limit_type_id = gpcgl.play_limit_type_id AND 
						gplnr.license_type_id = gpcgl.license_type_id AND gplnr.channel_type_id = gpcgl.channel_type_id AND gpcgl.interval_type_id = IFNULL(gplnr.interval_type_id, gpcgl.interval_type_id) AND
						gpcgl.limit_percentage >= gplnr.notify_at_percentage AND gpcgl.notified_at_percentage < gplnr.notify_at_percentage
					STRAIGHT_JOIN gaming_interval_type as git ON gpcgl.interval_type_id = git.interval_type_id
					WHERE gplnr.notify_for_game_limit = 1 AND gplnr.is_active = 1 
					ORDER BY gpcgl.play_limit_type_id, gpcgl.license_type_id, gpcgl.channel_type_id, git.order_no DESC
				) AS PP
			) AS XX
			WHERE round_row_count=1
			ON DUPLICATE KEY UPDATE client_stat_id=VALUES(client_stat_id), date_created = vNow;
			
			UPDATE gaming_play_limits_notification_rules as gplnr FORCE INDEX (is_active)
			STRAIGHT_JOIN gaming_player_current_game_limits as gpcgl FORCE INDEX (PRIMARY) ON 
				gpcgl.client_stat_id = clientStatID AND gplnr.play_limit_type_id = gpcgl.play_limit_type_id AND 
				gplnr.license_type_id = gpcgl.license_type_id AND gplnr.channel_type_id = gpcgl.channel_type_id AND gpcgl.interval_type_id = IFNULL(gplnr.interval_type_id, gpcgl.interval_type_id) AND
				gpcgl.limit_percentage >= gplnr.notify_at_percentage AND gpcgl.notified_at_percentage < gplnr.notify_at_percentage 
			SET gpcgl.notified_at_percentage = gpcgl.limit_percentage
			WHERE gplnr.is_active = 1;
		END IF;

-- license level
		SET @round_row_count=1;
		SET @play_limit_type_id=-1;
		SET @license_type_id=-1;
        SET @channel_type_id=-1;
        
		INSERT INTO gaming_play_limits_notification_rule_events (play_limit_notification_rule_id, client_stat_id, date_created)
		SELECT play_limit_notification_rule_id, clientStatID, vNow
        FROM (
			SELECT PP.*, 
              @round_row_count:=IF(@play_limit_type_id!=play_limit_type_id OR @license_type_id!=license_type_id OR @channel_type_id!=channel_type_id, 1, @round_row_count+1) AS round_row_count, 
              @play_limit_type_id:=play_limit_type_id, @license_type_id:=license_type_id, @channel_type_id:=channel_type_id
			FROM (
				SELECT gplnr.play_limit_notification_rule_id, gpcl.play_limit_type_id, gpcl.license_type_id, gpcl.channel_type_id 
				FROM gaming_play_limits_notification_rules as gplnr FORCE INDEX (is_active) 
				STRAIGHT_JOIN gaming_player_current_limits as gpcl FORCE INDEX (PRIMARY)  ON 
					gpcl.client_stat_id = clientStatID AND gplnr.play_limit_type_id = gpcl.play_limit_type_id AND 
					gplnr.license_type_id = gpcl.license_type_id AND gplnr.channel_type_id = gpcl.channel_type_id AND (gplnr.interval_type_id IS NULL OR gpcl.interval_type_id = gplnr.interval_type_id) AND
					gpcl.limit_percentage >= gplnr.notify_at_percentage AND gpcl.notified_at_percentage < gplnr.notify_at_percentage 
				STRAIGHT_JOIN gaming_interval_type as git ON gpcl.interval_type_id = git.interval_type_id
				WHERE gplnr.is_active = 1 
				ORDER BY gpcl.play_limit_type_id, gpcl.license_type_id, channel_type_id, git.order_no DESC
			) AS PP
		) AS XX
		WHERE round_row_count=1
		ON DUPLICATE KEY UPDATE client_stat_id=VALUES(client_stat_id), date_created = vNow;

		UPDATE gaming_play_limits_notification_rules as gplnr FORCE INDEX (is_active) 
		STRAIGHT_JOIN gaming_player_current_limits as gpcl FORCE INDEX (PRIMARY)  ON 
			gpcl.client_stat_id = clientStatID AND gplnr.play_limit_type_id = gpcl.play_limit_type_id AND 
			gplnr.license_type_id = gpcl.license_type_id AND gplnr.channel_type_id = gpcl.channel_type_id AND gpcl.interval_type_id = IFNULL(gplnr.interval_type_id, gpcl.interval_type_id) AND
			gpcl.limit_percentage >= gplnr.notify_at_percentage AND gpcl.notified_at_percentage < gplnr.notify_at_percentage 
		SET gpcl.notified_at_percentage = gpcl.limit_percentage
		WHERE gplnr.is_active = 1;

-- insert notification events 
    
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing)
		SELECT notificationEventTypeId, play_limit_notification_rule_event_id, clientStatID, 0
		FROM gaming_play_limits_notification_rule_events FORCE INDEX (player_date_created)
		WHERE client_stat_id = clientStatID AND date_created=vNow
		ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id);
		
	END IF;
		-- Notification END

  RETURN 0;
END$$

DELIMITER ;

