DROP procedure IF EXISTS `SessionPlayerClose`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionPlayerClose`(sessionID BIGINT, clientID BIGINT, clientStatID BIGINT)
BEGIN

  -- optimzed, if player wont' be accessed first need to lock player.
	
  UPDATE gaming_client_stats AS player
  STRAIGHT_JOIN sessions_main AS sm FORCE INDEX (PRIMARY) ON
	sm.session_id=sessionID AND sm.status_code=1 AND sm.extra2_id=player.client_stat_id
  STRAIGHT_JOIN gaming_client_sessions AS gcs FORCE INDEX (PRIMARY) ON 
	gcs.session_id=sessionID AND gcs.is_open=1
  LEFT JOIN gaming_game_sessions AS ggs FORCE INDEX (open_sessions) ON
	ggs.session_id=sessionID AND ggs.is_open=1 
  SET 
	-- sessions_main
	sm.date_closed=NOW(), sm.status_code=2, sm.date_expiry=SUBTIME(NOW(), '00:00:01'), sm.session_close_type_id=2, -- PlayerLogout   
	-- gaming_client_sessions
    gcs.is_open=0, gcs.end_balance_real=player.current_real_balance, 
	gcs.end_balance_bonus=player.current_bonus_balance, gcs.end_balance_bonus_win_locked=player.current_bonus_win_locked_balance,
    -- gaming_game_sessions
    ggs.is_open=0, ggs.session_end_date=NOW()
  WHERE player.client_stat_id=clientStatID;
  
END$$

DELIMITER ;

