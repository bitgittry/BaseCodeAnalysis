DROP procedure IF EXISTS `PlayerRestrictionDisactiveExpiredEntriesAndSendNotifications`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerRestrictionDisactiveExpiredEntriesAndSendNotifications`()
BEGIN
  -- Added Notification accessible
  
  DECLARE notificationEnabled TINYINT DEFAULT 0;
  DECLARE promotionalChannelsAutoDisable TINYINT DEFAULT 0;
  
  SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';
  SELECT value_bool INTO promotionalChannelsAutoDisable FROM gaming_settings WHERE name = 'PLAYER_RESTRICTIONS_AUTO_DISABLE_PROMOTIONAL_CONTACT';

  # Disabling the promotional channels for a player if a self exclusion restriction takes place
  UPDATE gaming_clients gc
  LEFT JOIN gaming_player_restrictions gpr ON gc.client_id = gpr.client_id
  LEFT JOIN gaming_player_restriction_types gprt ON gprt.player_restriction_type_id = gpr.player_restriction_type_id
  SET receive_promotional_by_email = 0, receive_promotional_by_sms = 0, receive_promotional_by_post = 0, news_feeds_allow = 0, receive_promotional_by_phone = 0, receive_promotional_by_third_party = 0
  WHERE gpr.is_active = 1 AND gpr.restrict_from_date <= NOW() AND gprt.name = 'self_exclusion' AND promotionalChannelsAutoDisable AND 
  (gc.receive_promotional_by_email || gc.receive_promotional_by_sms || gc.receive_promotional_by_post || gc.news_feeds_allow || gc.receive_promotional_by_phone || gc.receive_promotional_by_third_party);

  # If selF exclusion expires and dormant time is not 0 - new restriction with type 'Self exclusion expired'
  INSERT INTO gaming_player_restrictions 
  (client_id, client_stat_id, player_restriction_type_id, request_date, is_indefinitely, restrict_from_date, restrict_until_date, is_active, session_id, license_type_id, reason, user_id, notification_processed_set, notification_processed_release)
  SELECT gpr.client_id, client_stat_id, 6, now(), 0, now(), DATE_ADD(now(), INTERVAL gc.self_exclusion_dormant_time MONTH), 1, gpr.session_id, gpr.license_type_id, gpr.player_restriction_id, gpr.user_id, gpr.notification_processed_set, gpr.notification_processed_release
  FROM gaming_player_restrictions gpr
  LEFT JOIN gaming_clients ON gaming_clients.client_id = gpr.client_id
  LEFT JOIN clients_locations cl ON cl.client_id = gaming_clients.client_id AND cl.is_primary = 1
  LEFT JOIN gaming_countries gc ON gc.country_id = cl.country_id
  WHERE gpr.is_active=1 AND notification_processed_release IN (1,0) AND restrict_until_date<NOW() AND player_restriction_type_id = 1 AND gc.self_exclusion_dormant_time <> 0;
  
  # If self exclusion expired expires and cool off time is not 0 - new restriction with type 'Self-Exclusion Cool Off Period'
  INSERT INTO gaming_player_restrictions 
  (client_id, client_stat_id, player_restriction_type_id, request_date, is_indefinitely, restrict_from_date, restrict_until_date, is_active, session_id, license_type_id, reason, user_id, notification_processed_set, notification_processed_release)
  SELECT gpr.client_id, client_stat_id, 7, now(), 0, now(), DATE_ADD(now(), INTERVAL gc.self_exclusion_cool_off_time HOUR), 1, gpr.session_id, gpr.license_type_id, gpr.player_restriction_id, gpr.user_id, gpr.notification_processed_set, gpr.notification_processed_release
  FROM gaming_player_restrictions gpr
  LEFT JOIN gaming_clients ON gaming_clients.client_id = gpr.client_id
  LEFT JOIN clients_locations cl ON cl.client_id = gaming_clients.client_id AND cl.is_primary = 1
  LEFT JOIN gaming_countries gc ON gc.country_id = cl.country_id
  WHERE gpr.is_active=1 AND notification_processed_release IN (1,0) AND restrict_until_date<NOW() AND player_restriction_type_id = 6 AND gc.self_exclusion_cool_off_time <> 0;
  
  UPDATE gaming_player_restrictions FORCE INDEX (active_notification_release_until_date)
  SET is_active=0
  WHERE is_active=1 AND notification_processed_release IN (1,0) AND restrict_until_date<NOW();

  IF (notificationEnabled=1) THEN
	  INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
	  SELECT 
			CASE restr.player_restriction_type_id 
				WHEN 4 THEN 503 -- TemporaryLoginRestrictionRelease
				WHEN 5 THEN IF(is_indefinitely=1,519,518) -- 518:AuthenticationPinTemporaryLockRelease 519:AuthenticationPinIndefiniteLockRelease
			ELSE 501 END,
			player_restriction_id, client_id, 0
	  FROM gaming_player_restrictions restr FORCE INDEX (active_notification_release_until_date)
      LEFT JOIN gaming_player_restriction_types restr_types 
      ON restr_types.player_restriction_type_id = restr.player_restriction_type_id
	  WHERE restr.is_active IN (1,0) AND restr.notification_processed_release=0 AND restr.restrict_until_date<NOW() AND STRCMP(restr_types.name, 'self_exclusion_expired') <> 0
	  ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
  END IF;

  UPDATE gaming_player_restrictions FORCE INDEX (active_notification_release_until_date)
  SET notification_processed_release=1 
  WHERE is_active=0 AND notification_processed_release=0;
	
END$$

DELIMITER ;

