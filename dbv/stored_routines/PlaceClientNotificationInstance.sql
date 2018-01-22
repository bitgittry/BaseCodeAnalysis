DROP procedure IF EXISTS `PlaceClientNotificationInstance`;


DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceClientNotificationInstance`(sbBetId BIGINT(20), notificationEventName VARCHAR(40))
root: BEGIN

	-- CPREQ-216
	DECLARE notificationEnabled, eventTypeEnabled TINYINT(1) DEFAULT 0;
    DECLARE clientStatId, notificationEventTypeId  BIGINT DEFAULT 0;

    -- Get Settings
    SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';
    SELECT 1, notification_event_type_id INTO eventTypeEnabled, notificationEventTypeId FROM notifications_event_types WHERE event_name=notificationEventName;
    
    
    SELECT gaming_sb_bets.client_stat_id INTO clientStatId
    FROM gaming_sb_bets
    WHERE gaming_sb_bets.sb_bet_id = sbBetId;
    
	-- Send Notification
	IF(notificationEnabled AND eventTypeEnabled) THEN 
    
    INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing)
    SELECT notificationEventTypeId, sbBetId,clientStatId,0
	FROM notifications_subscriptions  
	WHERE is_active = true AND notification_event_type_id = notificationEventTypeId;
        
		-- INSERT INTO gaming_client_notifications_instances
		-- (notification_subscription_id, sb_bet_id)
		-- SELECT notification_subscription_id, sbBetId
		-- FROM notifications_subscriptions  
		-- WHERE notifications_subscriptions.client_stat_id = clientStatId and is_active = true;
    
    -- CALL NotificationEventCreate(notificationEventTypeId, sbBetID, clientStatID, 0);
    END IF;

END root$$

DELIMITER ;


