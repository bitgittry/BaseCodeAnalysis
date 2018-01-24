DROP procedure IF EXISTS `GameSessionStartFromProc`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameSessionStartFromProc`(clientStatID BIGINT, gameManufacturerName VARCHAR(80), gameRef VARCHAR(80), OUT gameSessionID BIGINT)
root: BEGIN
	-- First Version
    
    DECLARE sessionID, serverID, operatorID, gameManufacturerID, gameID, clientID BIGINT DEFAULT NULL;
    DECLARE statusCode INT DEFAULT NULL;
    DECLARE cwAllowNoSession TINYINT(1) DEFAULT 0;
    
    SELECT client_id INTO clientID FROM gaming_client_stats WHERE client_stat_id=clientStatID;
    SELECT operator_id INTO operatorID FROM gaming_operators WHERE is_main_operator LIMIT 1;
    SELECT game_manufacturer_id, cw_allow_no_session INTO gameManufacturerID, cwAllowNoSession FROM gaming_game_manufacturers where name=gameManufacturerName;
	SELECT game_id INTO gameID FROM gaming_games WHERE manufacturer_game_idf=gameRef and game_manufacturer_id=gameManufacturerID LIMIT 1;
	
    if ((gameID IS NULL) OR (gameManufacturerID IS NULL) OR cwAllowNoSession=0) THEN 
		SET gameSessionID=NULL; 
        LEAVE root;  
	END IF; 
    
    SELECT session_id, server_id INTO sessionID, serverID 
    FROM sessions_main FORCE INDEX (client_latest_session) 
    WHERE extra_id=clientID AND is_latest=1 AND status_code=1
    LIMIT 1;
    
    if ((sessionID IS NULL) OR (serverID IS NULL)) THEN 
		SET gameSessionID=NULL; 
        LEAVE root;  
	END IF; 
    
    CALL GameSessionStart(operatorID, gameID, serverID, sessionID, clientStatID, UUID(), NULL, 0, 0, 'none', 0, gameSessionID, statusCode);
    
END root$$

DELIMITER ;

