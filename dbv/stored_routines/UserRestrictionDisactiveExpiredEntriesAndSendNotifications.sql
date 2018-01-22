DROP procedure IF EXISTS `UserRestrictionDisactiveExpiredEntriesAndSendNotifications`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `UserRestrictionDisactiveExpiredEntriesAndSendNotifications`()
BEGIN
  -- Added Notification  

  DECLARE notificationEnabled TINYINT DEFAULT 0;
  
  SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';

  UPDATE users_restrictions FORCE INDEX (active_notification_release_until_date)
  SET is_active=0
  WHERE is_active=1 AND notification_processed_release IN (1,0) AND restrict_until_date<NOW();

  IF (notificationEnabled=1) THEN
	  INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
	  SELECT IF(user_restriction_type_id=1, IF(is_indefinitely, 511, 509), 507), user_restriction_id, user_id, 0
	  FROM users_restrictions FORCE INDEX (active_notification_release_until_date)
	  WHERE is_active IN (1,0) AND notification_processed_release=0 AND restrict_until_date<NOW()
	  ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
  END IF;

  UPDATE users_restrictions FORCE INDEX (active_notification_release_until_date)
  SET notification_processed_release=1 
  WHERE is_active=0 AND notification_processed_release=0;

END$$

DELIMITER ;

