DROP procedure IF EXISTS `SessionPlayerCloseAllButCurrent`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionPlayerCloseAllButCurrent`(sessionID BIGINT, clientID BIGINT, clientStatID BIGINT)
BEGIN

  -- optimzed, if player wont' be accessed first need to lock player.
	
  UPDATE gaming_client_stats AS player
  STRAIGHT_JOIN sessions_main AS sm FORCE INDEX (client_active_session) ON
	sm.extra_id=player.client_id AND sm.status_code=1 AND sm.session_id<>sessionID 
  STRAIGHT_JOIN gaming_client_sessions AS gcs FORCE INDEX (client_open_sessions) ON 
	gcs.client_stat_id=clientStatID AND gcs.is_open=1 AND gcs.session_id <> sessionID
  LEFT JOIN gaming_game_sessions AS ggs FORCE INDEX (client_open_sessions) ON
	ggs.client_stat_id=clientStatID AND ggs.is_open=1 AND ggs.session_id <> sessionID
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

