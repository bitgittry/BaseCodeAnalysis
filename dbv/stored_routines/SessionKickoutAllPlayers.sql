DROP procedure IF EXISTS `SessionKickoutAllPlayers`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionKickoutAllPlayers`(sessionID BIGINT)
BEGIN
  
  -- Optimised 
  SELECT session_close_type_id INTO @closeTypeID FROM sessions_close_types WHERE sessions_close_types.name='UserKickout';

  REPEAT

	  SET @effectedRows=0;

	  UPDATE sessions_main FORCE INDEX (session_type_status)
	  SET 
		sessions_main.date_closed=NOW(), sessions_main.status_code=2, 
		sessions_main.date_expiry=SUBTIME(NOW(), '00:00:01'), sessions_main.session_close_type_id=@closeTypeID,
		sessions_main.user_update_session_id=sessionID
	  WHERE sessions_main.session_type=2 AND sessions_main.status_code=1
	  LIMIT 25000; 
	  
	  SET @effectedRows=@effectedRows+ROW_COUNT();

	  UPDATE gaming_client_sessions FORCE INDEX (is_open)
	  SET gaming_client_sessions.is_open=0 
	  WHERE gaming_client_sessions.is_open=1
	  LIMIT 25000; 

	  SET @effectedRows=@effectedRows+ROW_COUNT();
	  
	  UPDATE gaming_game_sessions FORCE INDEX (is_open)
	  SET is_open=0, session_end_date=NOW() 
	  WHERE is_open=1
	  LIMIT 25000;

	  SET @effectedRows=@effectedRows+ROW_COUNT();
	  
  UNTIL @effectedRows < 10000 END REPEAT;

END$$

DELIMITER ;

