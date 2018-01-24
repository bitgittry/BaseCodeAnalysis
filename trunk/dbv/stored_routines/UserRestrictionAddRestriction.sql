DROP procedure IF EXISTS `UserRestrictionAddRestriction`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `UserRestrictionAddRestriction`(userID BIGINT, userRestrictionType VARCHAR(80), isIndefinitely TINYINT(1), restrictNumMinutes INT, restrictFromDate DATETIME, restrictUntilDate DATETIME, sessionID BIGINT, setUserID BIGINT, varReason TEXT, returnData TINYINT(1), OUT statusCode INT)
root: BEGIN
  -- Added parameter returnData so that the procedure can be called from other method without any data being returned
  -- Added Notifications  
  -- Fixed bug

  DECLARE userRestrictionTypeID, userRestrictionID BIGINT DEFAULT -1;
  DECLARE allowMultipleInstances, kickoutFlag, notificationEnabled TINYINT(1) DEFAULT 0;
  DECLARE systemEndDate DATETIME DEFAULT NULL;

  SELECT value_date INTO systemEndDate FROM gaming_settings WHERE name='SYSTEM_END_DATE';
  SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';

  SELECT user_restriction_type_id, allow_multiple_instances, kickout INTO userRestrictionTypeID, allowMultipleInstances, kickoutFlag FROM users_restriction_types  WHERE name=userRestrictionType AND is_active=1;
  
  IF (userRestrictionTypeID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  SET restrictFromDate=IFNULL(restrictFromDate, NOW());
  SET restrictUntilDate=IFNULL(restrictUntilDate, IF(isIndefinitely=1, systemEndDate, DATE_ADD(restrictFromDate, INTERVAL restrictNumMinutes MINUTE)));
  IF (restrictUntilDate <= restrictFromDate) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  IF (allowMultipleInstances=0) THEN
    UPDATE gaming_player_restrictions 
    SET gaming_player_restrictions.is_active=0, gaming_player_restrictions.session_id=sessionID
    WHERE user_id=userID AND user_restriction_type_id=userRestrictionTypeID AND users_restrictions.is_active=1;
  END IF;
  
  
  INSERT INTO users_restrictions (user_id, user_restriction_type_id, request_date, is_indefinitely, restrict_num_minutes, restrict_from_date, restrict_until_date, is_active, session_id, set_user_id, set_reason, notification_processed_set, notification_processed_release)
  SELECT userID, userRestrictionTypeID, NOW(), isIndefinitely, restrictNumMinutes, restrictFromDate, restrictUntilDate, 1, sessionID, setUserID, varReason, 1, 0;
   
  SET userRestrictionID=LAST_INSERT_ID();
  
  IF (notificationEnabled) THEN
	  IF (userRestrictionType='account_lock') THEN
		-- IF(isIndefinitely, UserPermanentLoginRestrictionSet, UserTemporaryLoginRestrictionSet)
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
		VALUES (IF(isIndefinitely, 510, 508), userRestrictionID, userID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
	  ELSE
		-- UserRestrictionSet
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
		VALUES (506, userRestrictionID, userID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
	  END IF;
  END IF;

  IF (kickoutFlag=1 AND (NOW() BETWEEN restrictFromDate AND restrictUntilDate)) THEN
    CALL SessionKickoutUserByCloseType(sessionID, userID, 'UserRestrictionKickout');
  END IF;
  
  IF (returnData) THEN

	  SELECT userRestrictionID AS user_restriction_id;
	  
	  SELECT user_restriction_type_id, name, display_name, allow_multiple_instances, disallow_login, disallow_execute_reports, disallow_view_players, disallow_execute_actions, kickout, is_active
	  FROM users_restriction_types 
	  WHERE user_restriction_type_id=userRestrictionTypeID;

  END IF;

  SET statusCode=0;
  
END root$$

DELIMITER ;

