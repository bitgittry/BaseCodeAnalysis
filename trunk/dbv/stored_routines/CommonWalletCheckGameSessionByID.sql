DROP procedure IF EXISTS `CommonWalletCheckGameSessionByID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCheckGameSessionByID`(gameSessionID BIGINT, ignoreSessionExpiry TINYINT(1), extendSessionExpiry TINYINT(1), commitTran TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  DECLARE sessionID, operatorGameID, clientStatID BIGINT DEFAULT -1; 
  DECLARE gameSessionIDCheck, clientStatIDCheck, sessionIDCheck BIGINT DEFAULT -1;
  DECLARE isOpen TINYINT(1) DEFAULT (0);
  DECLARE currentExpiryDate, newExpiryDate DATETIME;
  
   
  SELECT gaming_game_sessions.game_session_id, sessions_main.session_id, gaming_game_sessions.is_open, operator_game_id, gaming_game_sessions.client_stat_id
  INTO gameSessionIDCheck, sessionID, isOpen, operatorGameID, clientStatID 
  FROM gaming_game_sessions
  JOIN sessions_main ON gaming_game_sessions.session_id=sessions_main.session_id 
  WHERE gaming_game_sessions.game_session_id=gameSessionID;
  
  IF (gameSessionIDCheck=-1) THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;
  IF (ignoreSessionExpiry=0 AND isOpen=0) THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  
  SELECT client_stat_id INTO clientStatIDCheck
  FROM gaming_client_stats
  WHERE gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1;
  
  IF (clientStatIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  
  SET clientStatIDCheck=-1;
  SELECT session_id, sessions_main.extra2_id, date_expiry INTO sessionIDCheck, clientStatIDCheck, currentExpiryDate 
  FROM sessions_main 
  WHERE sessions_main.session_id=sessionID AND (ignoreSessionExpiry=1 OR (sessions_main.status_code=1 AND sessions_main.date_expiry > NOW()));
  IF (sessionIDCheck=-1 OR clientStatIDCheck!=clientStatID) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (extendSessionExpiry) THEN    
    UPDATE sessions_main 
    LEFT JOIN sessions_defaults ON sessions_defaults.server_id=sessions_main.server_id
    SET sessions_main.date_expiry=DATE_ADD(NOW(), INTERVAL IFNULL(sessions_defaults.expiry_duration, 30) MINUTE)
    WHERE sessions_main.session_id=sessionID AND sessions_main.status_code=1;
  
    IF (commitTran) THEN
      COMMIT AND CHAIN;
    END IF;
  END IF;
  
  SET statusCode=0;
END root$$

DELIMITER ;

