DROP procedure IF EXISTS `PlayerRestrictionAddRestriction`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerRestrictionAddRestriction`(clientID BIGINT, clientStatID BIGINT, playerRestrictionType VARCHAR(80), isIndefinitely TINYINT(1), restrictNumMinutes INT, restrictFromDate DATETIME, restrictUntilDate DATETIME, licenseType VARCHAR(20), sessionID BIGINT, userID BIGINT, varReason TEXT, returnData TINYINT(1), OUT statusCode INT)
root: BEGIN
  -- Added parameter returnData so that the procedure can be called from other method without any data being returned
  -- Added Notifications 

  DECLARE playerRestrictionTypeID, playerRestrictionID BIGINT DEFAULT -1;
  DECLARE licenseTypeID TINYINT(4) DEFAULT NULL;
  DECLARE allowMultipleInstances, kickoutFlag, notificationEnabled TINYINT(1) DEFAULT 0;
  DECLARE systemEndDate DATETIME DEFAULT NULL;
  DECLARE promotionalChannelsAutoDisable TINYINT DEFAULT 0;

  SELECT value_bool INTO promotionalChannelsAutoDisable FROM gaming_settings WHERE name = 'PLAYER_RESTRICTIONS_AUTO_DISABLE_PROMOTIONAL_CONTACT';
  SELECT value_date INTO systemEndDate FROM gaming_settings WHERE name='SYSTEM_END_DATE';
  SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';

  SELECT player_restriction_type_id, allow_multiple_instances, kickout INTO playerRestrictionTypeID, allowMultipleInstances,kickoutFlag FROM gaming_player_restriction_types  WHERE name=playerRestrictionType AND is_active=1;
  SELECT license_type_id INTO licenseTypeID FROM gaming_license_type WHERE name=licenseType;
  
  IF (playerRestrictionTypeID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  SET restrictFromDate=IFNULL(restrictFromDate, NOW());
  IF restrictFromDate <= NOW() && promotionalChannelsAutoDisable THEN
    # Disabling promotional channels to that player
    UPDATE gaming_clients 
    JOIN gaming_player_restriction_types ON gaming_player_restriction_types.player_restriction_type_id = playerRestrictionTypeID
    SET gaming_clients.receive_promotional_by_email = 0, gaming_clients.receive_promotional_by_sms=0, gaming_clients.receive_promotional_by_post=0, news_feeds_allow = 0, receive_promotional_by_phone = 0, receive_promotional_by_third_party = 0
    WHERE gaming_player_restriction_types.name = "self_exclusion" AND client_id = clientID;
  END IF;
  
  SET restrictUntilDate=IFNULL(restrictUntilDate, IF(isIndefinitely=1, systemEndDate, DATE_ADD(restrictFromDate, INTERVAL restrictNumMinutes MINUTE)));
  IF (restrictUntilDate <= restrictFromDate) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  IF (allowMultipleInstances=0) THEN
    UPDATE gaming_player_restrictions 
    LEFT JOIN gaming_license_type ON gaming_player_restrictions.license_type_id=gaming_license_type.license_type_id
    SET gaming_player_restrictions.is_active=0, gaming_player_restrictions.session_id=sessionID
    WHERE client_id=clientID AND player_restriction_type_id=playerRestrictionTypeID AND gaming_player_restrictions.is_active=1 AND (gaming_license_type.name IS NULL OR gaming_license_type.name=licenseType);
  END IF;
  
  
  INSERT INTO gaming_player_restrictions (client_id, client_stat_id, player_restriction_type_id, request_date, is_indefinitely, restrict_num_minutes, restrict_from_date, restrict_until_date, is_active, session_id, license_type_id, user_id, reason, notification_processed_set, notification_processed_release)
  SELECT clientID, clientStatID, playerRestrictionTypeID, NOW(), isIndefinitely, restrictNumMinutes, restrictFromDate, restrictUntilDate, 1, sessionID, licenseTypeID, userID, varReason, 1, 0;
   
  SET playerRestrictionID=LAST_INSERT_ID();
  
  IF (notificationEnabled) THEN
	  IF (playerRestrictionType='temporary_account_lock') THEN
		-- TemporaryLoginRestrictionSet
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
		VALUES (502, playerRestrictionID, clientID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
	  ELSEIF (playerRestrictionType='pin_code_temporary_lock') THEN
		IF (isIndefinitely = 1) THEN
			INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
			VALUES (517, playerRestrictionID, clientID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
		ELSE
			INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
			VALUES (516, playerRestrictionID, clientID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
		END IF;
	  ELSE
		-- PlayerRestrictionSet
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
		VALUES (500, playerRestrictionID, clientID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
	  END IF;
  END IF;

  IF (kickoutFlag=1 AND (NOW() BETWEEN restrictFromDate AND restrictUntilDate)) THEN
    CALL SessionKickoutPlayerByCloseType(sessionID,clientID,clientStatID,'PlayerRestrictionKickout');
  END IF;
  
  IF (returnData) THEN

	  SELECT playerRestrictionID AS player_restriction_id;
	  
	  SELECT player_restriction_type_id, name, display_name, allow_multiple_instances, disallow_login, disallow_transfers, disallow_deposits, disallow_withdrawals, disallow_play, kickout, is_active, disallow_pin, is_system
	  FROM gaming_player_restriction_types 
	  WHERE player_restriction_type_id=playerRestrictionTypeID;

  END IF;

  SET statusCode=0;
  
END root$$

DELIMITER ;

