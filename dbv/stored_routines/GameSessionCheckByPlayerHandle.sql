DROP procedure IF EXISTS `GameSessionCheckByPlayerHandle`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameSessionCheckByPlayerHandle`(
  playerHandle VARCHAR(255), newGameSessionKey VARCHAR(80), operatorID BIGINT, serverID BIGINT, componentID BIGINT, 
  gameManufacturerName VARCHAR(80), manufacturerGameIDF VARCHAR(255), gameDoesNotMatchCreateSession TINYINT(1),
  ignoreSessionExpiry TINYINT(1), extendSessionExpiry TINYINT(0), matchManufacturerGameIDF TINYINT(1), OUT statusCode INT)
root:BEGIN

  -- Better handling if a new game session need to be created 

  DECLARE gameManufacturerID, gameID, newGameID, sessionID, clientStatID, newGameSessionID BIGINT DEFAULT -1;
  DECLARE createNewGameSessionStatusCode INT DEFAULT 0;
  DECLARE gameSessionKey VARCHAR(80) DEFAULT NULL;
  
  SELECT game_manufacturer_id INTO gameManufacturerID FROM gaming_game_manufacturers WHERE gaming_game_manufacturers.name=gameManufacturerName;
  
  SELECT gaming_game_sessions.game_session_key, gaming_game_sessions.game_id, 
	IF(new_game.is_sub_game, new_game.parent_game_id, new_game.game_id), 
    gaming_game_sessions.session_id, gaming_game_sessions.client_stat_id 
  INTO gameSessionKey, gameID, newGameID, sessionID, clientStatID
  FROM gaming_game_sessions
  STRAIGHT_JOIN sessions_main ON gaming_game_sessions.session_id=sessions_main.session_id 
  STRAIGHT_JOIN gaming_operator_games ON gaming_game_sessions.operator_game_id=gaming_operator_games.operator_game_id
  STRAIGHT_JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id
  LEFT JOIN gaming_games AS new_game ON 
	new_game.game_manufacturer_id=gameManufacturerID AND new_game.manufacturer_game_idf=manufacturerGameIDF 
    -- AND gaming_game_sessions.game_id=IF(new_game.is_sub_game, new_game.parent_game_id, new_game.game_id)
  WHERE gaming_game_sessions.player_handle=playerHandle AND gaming_game_sessions.game_manufacturer_id=gameManufacturerID
  ORDER BY IF(matchManufacturerGameIDF AND gaming_games.manufacturer_game_idf=manufacturerGameIDF, 0, 1) ASC, gaming_game_sessions.session_start_date DESC
  LIMIT 1;
  
  IF (matchManufacturerGameIDF AND newGameID IS NULL) THEN
	
    SET statusCode=20;
	LEAVE root;
  
  ELSEIF (gameID=IFNULL(newGameID, gameID)) THEN
    
    CALL GameSessionCheck(gameSessionKey, componentID, ignoreSessionExpiry, extendSessionExpiry, statusCode);  
  
  ELSE
  
    IF (gameDoesNotMatchCreateSession=0 OR IFNULL(newGameID, -1)=-1 OR gameSessionKey IS NULL) THEN
      SET statusCode=20;
      LEAVE root;
    END IF;
    
    SET newGameSessionKey=IFNULL(newGameSessionKey, UUID());
    
    CALL GameSessionStart(
		operatorID, newGameID, serverID, sessionID, clientStatID, 
        newGameSessionKey, playerHandle, 0, 0, 'None', 0, newGameSessionID, createNewGameSessionStatusCode);
      
    IF (createNewGameSessionStatusCode<>0) THEN 
      SET statusCode=21;
      LEAVE root;
	ELSE 
	  SET statusCode=-1;
    END IF;
    
    CALL GameSessionCheck(newGameSessionKey, componentID, ignoreSessionExpiry, extendSessionExpiry, statusCode);
    
  END IF;
END root$$

DELIMITER ;

