DROP procedure IF EXISTS `SessionCloseExpiredSessions`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionCloseExpiredSessions`()
BEGIN

  COMMIT; -- just in case 
  SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; 
	
  UPDATE 
  (
	SELECT session_id
    FROM sessions_main FORCE INDEX (status_code_date_expiry) 
    WHERE sessions_main.status_code=1 AND sessions_main.date_expiry < NOW()
    LIMIT 2000
  ) AS sessions_to_close
  STRAIGHT_JOIN sessions_main ON sessions_main.session_id=sessions_to_close.session_id
  STRAIGHT_JOIN gaming_client_sessions ON gaming_client_sessions.session_id=sessions_main.session_id
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_sessions.client_stat_id=gaming_client_stats.client_stat_id
  LEFT JOIN gaming_game_sessions FORCE INDEX (open_sessions) ON   
	gaming_game_sessions.session_id=sessions_main.session_id AND gaming_game_sessions.is_open=1
  SET 
    sessions_main.date_closed=IFNULL(sessions_main.date_closed, NOW()), 
    sessions_main.status_code=2, 
    sessions_main.session_close_type_id=3, -- SessionExpired
    gaming_client_sessions.is_open=0, 
    gaming_client_sessions.end_balance_real=gaming_client_stats.current_real_balance, 
    gaming_client_sessions.end_balance_bonus=gaming_client_stats.current_bonus_balance, 
    gaming_client_sessions.end_balance_bonus_win_locked=gaming_client_stats.current_bonus_win_locked_balance,
    gaming_game_sessions.is_open=0, 
    gaming_game_sessions.session_end_date=NOW();
  
  COMMIT; -- just in case
    
END$$

DELIMITER ;

