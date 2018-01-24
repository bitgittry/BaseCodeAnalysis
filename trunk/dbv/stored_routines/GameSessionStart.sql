DROP procedure IF EXISTS `GameSessionStart`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameSessionStart`(operatorID BIGINT, gameID BIGINT, 
  serverID BIGINT, sessionID BIGINT, clientStatID BIGINT, gameSessionKey VARCHAR(80), 
  playerHandle VARCHAR(80), closePrevious TINYINT(1), generateToken TINYINT(1), startType VARCHAR(45), 
  returnData TINYINT(1), OUT gameSessionID BIGINT, OUT statusCode INT)
root:BEGIN
  /*
    Status code
    0 - Success
    1 - Invalid OperatorID or GameID
  */
  -- Added returnData & gameSessionID parameters 
  
  DECLARE operatorGameID, gameManufacturerID, cwTokenID BIGINT DEFAULT -1; -- game_id, game_manufacturer_id
  DECLARE tokenKey, gameManufacturerName, betProfile VARCHAR(80) DEFAULT NULL;
  DECLARE cwGenerateToken TINYINT(1) DEFAULT 0;
  DECLARE cwAllowConcurrentGames BIT;
  
  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;

  SELECT gaming_operator_games.operator_game_id, gaming_games.game_manufacturer_id, gaming_game_manufacturers.name, gaming_game_manufacturers.cw_generate_token
  INTO operatorGameID, gameManufacturerID, gameManufacturerName, cwGenerateToken
  FROM gaming_operator_games 
  JOIN gaming_games ON gaming_operator_games.operator_id=operatorID AND gaming_operator_games.game_id=gameID AND gaming_operator_games.game_id=gaming_games.game_id AND gaming_games.is_launchable=1
  JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id;

  SELECT cw_allow_concurrent_games INTO cwAllowConcurrentGames FROM gaming_game_manufacturers WHERE game_manufacturer_id = gameManufacturerID;
  
  IF operatorGameID = -1 THEN
    SET statusCode = 1;
    LEAVE root;
  ELSE
  
    IF cwAllowConcurrentGames = 0 THEN
      UPDATE gaming_game_sessions FORCE INDEX (client_open_sessions) SET is_open=0, session_end_date=NOW() WHERE client_stat_id=clientStatID AND is_open=1 AND game_manufacturer_id=gameManufacturerID;
    END IF;
  
    UPDATE gaming_game_sessions FORCE INDEX (cw_latest_sessions) 
	JOIN gaming_games ON gaming_game_sessions.game_id = gaming_games.game_id AND (gaming_games.game_id =gameID OR  gaming_games.parent_game_id = gameID)
	SET cw_game_latest=0
	WHERE client_stat_id=clientStatID AND cw_game_latest=1;
  
    INSERT INTO gaming_game_sessions 
    (operator_game_id,session_start_date,session_end_date,game_session_key,player_handle,session_id,client_stat_id, game_id, game_manufacturer_id, server_id, cw_game_latest, game_start_type_id) 
    SELECT operatorGameID,NOW(),NULL,gameSessionKey,playerHandle,sessionID,clientStatID, gameID, gameManufacturerID, serverID, 1, gaming_game_start_type.game_start_type_id
	FROM gaming_game_start_type
	WHERE gaming_game_start_type.start_type = startType;
    
    SET gameSessionID=LAST_INSERT_ID();
    
    IF (generateToken OR cwGenerateToken) THEN
      SELECT CommonWalletCreateTokenGetID(gameManufacturerID, clientStatID, gameSessionID) INTO cwTokenID;
      SELECT token_key INTO tokenKey FROM gaming_cw_tokens WHERE cw_token_id=cwTokenID;
    END IF;

    IF (gameManufacturerName='Chartwell') THEN
      INSERT INTO gaming_cw_players (client_stat_id, game_manufacturer_id, transaction_check_ref)
      SELECT clientStatID, gameManufacturerID, playerHandle
      ON DUPLICATE KEY UPDATE transaction_check_ref=playerHandle;
    END IF;
    
	SELECT gmprofiles.`name` INTO betProfile
	FROM gaming_client_stats
		JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
		JOIN gaming_game_manufacturers_vip_levels viplevels ON viplevels.vip_level_id=gaming_clients.vip_level_id
		JOIN gaming_game_manufacturers_bet_profiles gmprofiles ON gmprofiles.bet_profile_id=viplevels.bet_profile_id AND gmprofiles.game_manufacturer_id=gameManufacturerID
	WHERE  gaming_client_stats.client_stat_id=clientStatID;
	
    -- return required data
    IF (returnData) THEN
		SELECT gameSessionID AS game_session_id, gameSessionKey AS game_session_key, operatorGameID AS operator_game_id, playerHandle AS player_handle, tokenKey AS token_key, betProfile AS bet_profile;
	END IF;
                  
    SET statusCode = 0;
  END IF;
  
END root$$

DELIMITER ;

