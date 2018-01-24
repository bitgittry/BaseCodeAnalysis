DROP procedure IF EXISTS `JobGameDrawResultsNotification`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `JobGameDrawResultsNotification`(jobRunID BIGINT)
root: BEGIN
	-- CPREQ-38 


	DECLARE v_playersBlockSizeDefault INT DEFAULT 10000; -- or ~0 >> 33 MAX INTEGER SIGNED
	DECLARE v_playersBlockSize, drawAllDrawsTypeID, drawParticipationTypeID INT;
    DECLARE notificationEnabled, eventTypeEnabled TINYINT(1) DEFAULT 0;
    DECLARE notificationTypeID INT DEFAULT 605;
    DECLARE curDate DATETIME DEFAULT NOW();
    
    -- Get Settings
    SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';
    SELECT IFNULL(value_int, v_playersBlockSizeDefault) INTO v_playersBlockSize FROM gaming_settings WHERE `name`='JOB_GAME_DRAW_RESULTS_NOTIFICATION_PLAYERS_BLOCK_SIZE';

	SELECT 1 INTO eventTypeEnabled FROM notifications_event_types WHERE notification_event_type_id=notificationTypeID AND is_active;

	SELECT gaming_game_draw_notification_types.game_draw_notification_type_id INTO drawAllDrawsTypeID FROM gaming_game_draw_notification_types WHERE `name` = 'All-Draws';
	SELECT gaming_game_draw_notification_types.game_draw_notification_type_id INTO drawParticipationTypeID FROM gaming_game_draw_notification_types WHERE `name` = 'Participated-Only';

	
	
	
	
	-- Update that notification will be sent now
	UPDATE  
	(
		SELECT gaming_game_client_notifications.game_client_notification_id, gaming_lottery_draws.lottery_draw_id
		FROM gaming_lottery_draws
		JOIN gaming_games ON gaming_lottery_draws.game_id = gaming_games.game_id
		JOIN gaming_game_client_notifications ON gaming_games.game_id = gaming_game_client_notifications.game_id
		WHERE 
				gaming_lottery_draws.`status` = 6
			AND gaming_games.is_active_draw_notification = 1
			AND gaming_lottery_draws.draw_date_results > COALESCE(gaming_game_client_notifications.last_date_sent_notification, gaming_game_client_notifications.date_subscription)
			AND gaming_game_client_notifications.game_draw_notification_type_id = drawAllDrawsTypeID
	  UNION
		SELECT gaming_game_client_notifications.game_client_notification_id, gaming_lottery_draws.lottery_draw_id
		FROM gaming_lottery_draws
		JOIN gaming_games ON gaming_lottery_draws.game_id = gaming_games.game_id AND gaming_games.is_active_draw_notification = 1
		JOIN gaming_game_client_notifications FORCE INDEX (idx_game_id) ON gaming_games.game_id = gaming_game_client_notifications.game_id 
		JOIN gaming_lottery_participations ON gaming_lottery_draws.lottery_draw_id = gaming_lottery_participations.lottery_draw_id
		JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
		JOIN gaming_lottery_coupons ON gaming_lottery_coupons.lottery_coupon_id = gaming_lottery_dbg_tickets.lottery_coupon_id
		JOIN gaming_game_client_notifications AS playerSubscriptions ON playerSubscriptions.client_stat_id = gaming_lottery_coupons.client_stat_id 
		WHERE
				gaming_lottery_draws.`status` = 6
			AND gaming_lottery_draws.draw_date_results > COALESCE(gaming_game_client_notifications.last_date_sent_notification, gaming_game_client_notifications.date_subscription)
			AND gaming_game_client_notifications.game_draw_notification_type_id = drawParticipationTypeID
	  LIMIT v_playersBlockSize
	) AS ToUpdate 
	JOIN gaming_game_client_notifications ON gaming_game_client_notifications.game_client_notification_id=ToUpdate.game_client_notification_id
	SET 
		gaming_game_client_notifications.lottery_draw_id=ToUpdate.lottery_draw_id,
		gaming_game_client_notifications.last_date_sent_notification=curDate;

		-- SET gaming_game_client_notifications.last_date_sent_notification to now for players that want to receive notifications
		-- BUT notifications are disabled for the game.
		-- If we don't update the last_date_sent_notification then the player will receive notifications for past draws
		-- when notifications are re-enabled for the game.
   UPDATE gaming_game_client_notifications ggcn 
    JOIN gaming_games gg ON gg.game_id = ggcn.game_id 
  JOIN gaming_lottery_draws gld ON gld.game_id = gg.game_id
  JOIN gaming_game_draw_notification_types ggnt ON ggnt.game_draw_notification_type_id = ggcn.game_draw_notification_type_id
    SET ggcn.last_date_sent_notification = NOW()
      WHERE gld.`status` = 6
      AND gg.is_active_draw_notification = 0
      AND gld.draw_date_results > coalesce(ggcn.last_date_sent_notification, ggcn.date_subscription)    
      AND ggnt.`name` IN ('Participated-Only', 'All-Draws');
		
	-- Send Notification
	IF (notificationEnabled AND eventTypeEnabled) THEN 
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
		SELECT notificationTypeID, game_client_notification_id, lottery_draw_id, 0
        FROM gaming_game_client_notifications 
        WHERE last_date_sent_notification=curDate AND lottery_draw_id IS NOT NULL
		ON DUPLICATE KEY UPDATE event2_id = VALUES(event2_id), is_processing=VALUES(is_processing);
    END IF;    
  
END root$$

DELIMITER ;

