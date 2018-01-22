DROP procedure IF EXISTS `PlayerCreateUpdateDrawNotification`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerCreateUpdateDrawNotification`(gameClientNotificationID BIGINT, gameID BIGINT, 
  clientStatID BIGINT, gameDrawNotification VARCHAR(20), isPlayer TINYINT(1), userID BIGINT, OUT statusCode INT)
root:BEGIN
   
  DECLARE v_notificationExists TINYINT(1) DEFAULT 0;
  DECLARE v_gameID BIGINT;
  DECLARE v_clientStatID, v_clientID, v_auditLogGroupId BIGINT;
  DECLARE v_gameDrawNotificationTypeID TINYINT(4);
  DECLARE v_gameClientNotificationID, v_modifierEntityExtraID, v_sessionID BIGINT;
  DECLARE v_modifierEntityType VARCHAR(45); 
  DECLARE v_curGameDrawNotification VARCHAR(20);
  DECLARE v_gameName VARCHAR(80);

  SELECT game_id, game_name INTO v_gameID, v_gameName FROM gaming_games WHERE game_id = gameID;
  
  IF (v_gameID is null) THEN
    SET statusCode = 902 /*Game_Invalid_Game_ID*/ ;
    LEAVE root;
  END IF;
  
  SELECT client_stat_id, client_id INTO v_clientStatID, v_clientID FROM gaming_client_stats WHERE client_stat_id = clientStatID;
  
  IF (v_clientStatID is null) THEN
    SET statusCode = 415 /*Player_Player_NotFound*/ ;
    LEAVE root;
  END IF;

  SELECT IF(COUNT(game_draw_notification_type_id) > 0, 1, 0) INTO v_notificationExists FROM gaming_game_client_notifications ggcn WHERE ggcn.game_id = gameID AND ggcn.client_stat_id = clientStatID;

  IF (v_notificationExists) and gameClientNotificationID is null THEN
    SET statusCode = 926 /*Game_Draw_Notification_Exists_IDRequired*/ ;
    LEAVE root;
  END IF;

  SELECT game_draw_notification_type_id INTO v_gameDrawNotificationTypeID FROM gaming_game_draw_notification_types WHERE `name` = gameDrawNotification;

  SELECT game_client_notification_id, drawNotifTypes.name INTO v_gameClientNotificationID, v_curGameDrawNotification 
  FROM gaming_game_client_notifications as gameClientNotif
  JOIN gaming_game_draw_notification_types as drawNotifTypes ON drawNotifTypes.game_draw_notification_type_id = gameClientNotif.game_draw_notification_type_id
  WHERE game_client_notification_id = gameClientNotificationID; 
   
  SET v_auditLogGroupId = 
	AuditLogNewGroup(userID, NULL, v_clientID, 8, 
		IF(isPlayer, 'Player', IF(userID=0, 'System', 'User')), NULL, NULL, v_clientID);
 
  IF (v_gameClientNotificationID IS NULL) THEN    
    INSERT INTO gaming_game_client_notifications (game_id, client_stat_id, game_draw_notification_type_id) VALUES (gameID, clientStatID, v_gameDrawNotificationTypeID);    
	  CALL AuditLogAttributeChange(CONCAT('Game Draw - ', v_gameName), v_clientID, v_auditLogGroupId, gameDrawNotification, 'None', NOW());
  ELSE
    UPDATE gaming_game_client_notifications SET game_draw_notification_type_id = v_gameDrawNotificationTypeID WHERE game_client_notification_id = v_gameClientNotificationID;
	  CALL AuditLogAttributeChange(CONCAT('Game Draw - ', v_gameName), v_clientID, v_auditLogGroupId, gameDrawNotification, v_curGameDrawNotification, NOW());
  END IF;

  SET statusCode = 0;
END root$$

DELIMITER ;

