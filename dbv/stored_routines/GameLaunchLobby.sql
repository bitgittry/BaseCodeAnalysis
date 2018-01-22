DROP procedure IF EXISTS `GameLaunchLobby`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameLaunchLobby`(sessionID BIGINT, clientStatID BIGINT, gameManufacturerID BIGINT, externalToken VARCHAR(80), generateToken TINYINT(1))
BEGIN
    -- Initial version

	DECLARE cwTokenID, gameLobbySessionID BIGINT DEFAULT -1; 
	DECLARE tokenKey VARCHAR(80) DEFAULT NULL;
    
    IF (generateToken) THEN
      SELECT CommonWalletCreateTokenGetID(gameManufacturerID, clientStatID, sessionID) INTO cwTokenID;
      SELECT token_key INTO tokenKey FROM gaming_cw_tokens WHERE cw_token_id=cwTokenID;
    END IF;
    
    INSERT INTO gaming_game_lobby_sessions (session_id, client_stat_id, token_key, external_token_key, session_start_date, session_end_Date, is_open, game_manufacturer_id)
	VALUES (sessionID, clientStatID, tokenKey, externalToken, NOW(), null, 1, gameManufacturerID);
    
    SET gameLobbySessionID = LAST_INSERT_ID();
    
    SELECT game_lobby_session_id, session_id, client_stat_id, token_key, external_token_key, session_start_date, session_end_date, is_open, game_manufacturer_id
    FROM gaming_game_lobby_sessions
    WHERE game_lobby_session_id = gameLobbySessionID;
END$$

DELIMITER ;

