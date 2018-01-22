DROP procedure IF EXISTS `SessionGetPlayerActiveSession`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionGetPlayerActiveSession`(playerUsername VARCHAR(255))
BEGIN

  DECLARE clientID, clientStatID BIGINT DEFAULT -1;
  DECLARE sessionType VARCHAR(80) DEFAULT 'credentials';
  DECLARE usernameCaseSensitive TINYINT DEFAULT 0;

  SELECT value_bool INTO usernameCaseSensitive FROM gaming_settings WHERE name='USERNAME_CASE_SENSITIVE';  
  SELECT value_string INTO sessionType FROM gaming_settings WHERE gaming_settings.name = 'PLAYER_SESSION_LOGIN_TYPE';

  IF (sessionType = 'credentials') THEN
    SELECT gaming_clients.client_id, gaming_client_stats.client_stat_id
    INTO clientID, clientStatID
    FROM gaming_clients FORCE INDEX (username) 	
    JOIN gaming_client_stats ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active=1
    LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
	WHERE gaming_clients.username = playerUsername AND IF (usernameCaseSensitive=1, BINARY gaming_clients.username = playerUsername, LOWER(username) = BINARY LOWER(playerUsername)) AND gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL); 

  ELSE
    SELECT gaming_clients.client_id, gaming_client_stats.client_stat_id
    INTO clientID, clientStatID
    FROM gaming_clients FORCE INDEX (ext_client_id)
	JOIN gaming_client_stats ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active=1 
    LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id    
	WHERE gaming_clients.ext_client_id = playerUsername AND IF (usernameCaseSensitive=1, BINARY gaming_clients.ext_client_id = playerUsername, LOWER(ext_client_id) = BINARY LOWER(playerUsername)) AND gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL); 
  END IF;

  SELECT session_id AS session_id, session_guid AS session_key, extra_id AS client_id FROM sessions_main WHERE extra_id=clientID AND status_code=1 AND session_type=2 ORDER BY session_id DESC LIMIT 1;

END$$

DELIMITER ;

