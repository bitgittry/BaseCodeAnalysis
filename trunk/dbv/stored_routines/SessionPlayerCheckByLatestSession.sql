DROP procedure IF EXISTS `SessionPlayerCheckByLatestSession`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionPlayerCheckByLatestSession`(clientStatID BIGINT, varUsername VARCHAR(80), serverID BIGINT, ignoreSessionExpiry TINYINT(1), extendSessionExpiry TINYINT(1), OUT statusCode INT)
root:BEGIN
  

 
  DECLARE componentID BIGINT DEFAULT -1;
  DECLARE sessionGUID VARCHAR(80) DEFAULT NULL;
  DECLARE clientID BIGINT DEFAULT NULL;
  DECLARE sessionType VARCHAR(80) DEFAULT 'session_key';
  DECLARE usernameCaseSensitive TINYINT(1) DEFAULT 0;

  SET componentID=1;
  
  SELECT value_bool INTO usernameCaseSensitive FROM gaming_settings WHERE name='USERNAME_CASE_SENSITIVE';
  SELECT value_string INTO sessionType FROM gaming_settings WHERE gaming_settings.name = 'PLAYER_SESSION_KEY_TYPE';

  IF (clientStatID IS NULL) THEN
    SELECT gaming_client_stats.client_stat_id, gaming_clients.client_id INTO clientStatID, clientID
    FROM gaming_clients	FORCE INDEX (username)
    JOIN gaming_client_stats ON gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1
    LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id 
	WHERE gaming_clients.username=varUsername AND IF (usernameCaseSensitive=1, BINARY gaming_clients.username = varUsername, LOWER(username) = BINARY LOWER(varUsername)) AND gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL);
      
    IF (clientStatID IS NULL) THEN
      SET statusCode=2;
      LEAVE root;
    END IF;
  END IF;
  
  IF (clientID IS NULL) THEN
    SELECT client_id INTO clientID FROM gaming_client_stats WHERE client_stat_id=clientStatID;
  END IF;
  
  IF (sessionType='session_key') THEN
	SELECT session_guid INTO sessionGUID FROM sessions_main WHERE extra_id=clientID AND is_latest ORDER BY sessions_main.date_open DESC LIMIT 1;
  ELSE
	SELECT ext_client_id INTO sessionGUID FROM gaming_clients WHERE client_id=clientID;
  END IF;

  CALL SessionPlayerCheckWithIgnore(sessionGUID, serverID, componentID, ignoreSessionExpiry, extendSessionExpiry, statusCode);
END root$$

DELIMITER ;

