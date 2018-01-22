DROP procedure IF EXISTS `GameSessionStartPFF`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameSessionStartPFF`(operatorID BIGINT, gameID BIGINT, serverID BIGINT, sessionID BIGINT, clientStatID BIGINT, gameSessionKey VARCHAR(80), gameSessionType VARCHAR(80), generateToken TINYINT(1), OUT statusCode INT)
root:BEGIN
  /*
    Status code
    0 - Success
    1 - Invalid OperatorID or GameID
  */
  DECLARE operatorGameID, gameManufacturerID, gameSessionID, cwTokenID BIGINT DEFAULT -1; 
  DECLARE tokenKey, betProfile VARCHAR(80) DEFAULT NULL;
  DECLARE isReal TINYINT(1) DEFAULT 0;
  DECLARE cwGenerateToken TINYINT(1) DEFAULT 0;


  SELECT gaming_operator_games.operator_game_id, gaming_games.game_manufacturer_id, gaming_game_manufacturers.cw_generate_token
  INTO operatorGameID, gameManufacturerID, cwGenerateToken
  FROM gaming_operator_games 
  JOIN gaming_games ON gaming_operator_games.operator_id=operatorID AND gaming_operator_games.game_id=gameID AND gaming_operator_games.game_id=gaming_games.game_id AND gaming_games.is_launchable=1
  JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id;
  
  IF operatorGameID = -1 THEN
    SET statusCode = 1;
    LEAVE root;
  END IF;
  
  INSERT INTO gaming_game_sessions_pff (operator_game_id,session_start_date,session_end_date,game_session_key,session_id,client_stat_id, game_id, game_manufacturer_id, server_id, game_session_type) 
  SELECT operatorGameID,NOW(),NULL,gameSessionKey,sessionID,clientStatID, gameID, gameManufacturerID, serverID, session_type.game_session_type
  FROM gaming_game_session_types AS session_type WHERE session_type.name=gameSessionType;
    
  SET gameSessionID=LAST_INSERT_ID();
    
  IF (generateToken || cwGenerateToken) THEN
	SELECT CommonWalletCreateTokenGetID(gameManufacturerID, clientStatID, gameSessionID) INTO cwTokenID;
	SELECT token_key INTO tokenKey FROM gaming_cw_tokens WHERE cw_token_id=cwTokenID;
  END IF;
    
  IF (clientStatID != 0) THEN 
	SELECT gmprofiles.`name` INTO betProfile
	FROM gaming_client_stats
		JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
		JOIN gaming_game_manufacturers_vip_levels viplevels ON viplevels.vip_level_id=gaming_clients.vip_level_id
		JOIN gaming_game_manufacturers_bet_profiles gmprofiles ON gmprofiles.bet_profile_id=viplevels.bet_profile_id AND gmprofiles.game_manufacturer_id=gameManufacturerID
	WHERE  gaming_client_stats.client_stat_id=clientStatID;
  END IF;

  SELECT gameSessionID AS game_session_id, gameSessionKey AS game_session_key, operatorGameID AS operator_game_id, CONCAT('PFF_', tokenKey) AS token_key, betProfile AS bet_profile; 
                  
  SET statusCode = 0;
  
END root$$

DELIMITER ;