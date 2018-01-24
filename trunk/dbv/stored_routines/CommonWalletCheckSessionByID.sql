DROP procedure IF EXISTS `CommonWalletCheckSessionByID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCheckSessionByID`(sessionID BIGINT, 
  ignoreSessionExpiry TINYINT(1), extendSessionExpiry TINYINT(1), commitTran TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  DECLARE clientStatID, sessionIDCheck BIGINT DEFAULT -1; 
  DECLARE dateExpiry DATETIME DEFAULT NULL; 
  
  SELECT session_id, sessions_main.extra2_id, date_expiry
  INTO sessionIDCheck, clientStatID, dateExpiry
  FROM sessions_main FORCE INDEX (PRIMARY)
  WHERE sessions_main.session_id=sessionID AND (ignoreSessionExpiry=1 OR (sessions_main.status_code=1 AND sessions_main.date_expiry > NOW()));
  
  IF (sessionIDCheck=-1 OR IFNULL(clientStatID, -1)=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (extendSessionExpiry AND dateExpiry<DATE_ADD(NOW(), INTERVAL 25 MINUTE)) THEN    

    UPDATE sessions_main FORCE INDEX (PRIMARY)
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

