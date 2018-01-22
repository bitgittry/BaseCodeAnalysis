DROP procedure IF EXISTS `NotificationEventCreate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `NotificationEventCreate`(
  notificationEventTypeID BIGINT, eventID BIGINT, event2ID BIGINT, isProcessing TINYINT(1))
BEGIN

	-- checking if notification is active
	DECLARE notificationEnabled TINYINT(1) DEFAULT 0;

	SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';

	IF (1 = notificationEnabled) THEN 
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
		SELECT notification_event_type_id, eventID, IFNULL(event2ID, 0), isProcessing
        FROM notifications_event_types 
        WHERE notification_event_type_id=notificationEventTypeID AND is_active
		ON DUPLICATE KEY UPDATE event2_id = VALUES(event2_id), is_processing=VALUES(is_processing);
    END IF;

END$$

DELIMITER ;

