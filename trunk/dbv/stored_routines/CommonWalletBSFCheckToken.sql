DROP procedure IF EXISTS `CommonWalletBSFCheckToken`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletBSFCheckToken`(tokenKey VARCHAR(80), OUT statusCode INT)
root: BEGIN
  DECLARE cwTokenID, clientStatID, gameSessionID BIGINT DEFAULT -1;
  DECLARE validCredentials, isConfirmed, invalidateToken TINYINT(1) DEFAULT 0;
  DECLARE expiryDate DATETIME;
  DECLARE gameManufacturerID BIGINT DEFAULT 13;
  DECLARE gameManufacturerName VARCHAR(80) DEFAULT 'BetSoft';
  
  
  
  
  SELECT cw_token_id, expiry_date, client_stat_id, game_session_id, is_confirmed
  INTO cwTokenID, expiryDate, clientStatID, gameSessionID, isConfirmed
  FROM gaming_cw_tokens WHERE token_key=tokenKey AND game_manufacturer_id=gameManufacturerID;
  
  IF (cwTokenID=-1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (expiryDate<NOW()) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (clientStatID IS NULL OR clientStatID=-1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (isConfirmed=0) THEN
    INSERT INTO gaming_cw_players (client_stat_id, game_manufacturer_id, transaction_check_ref)
    SELECT clientStatID, gameManufacturerID, tokenKey
    ON DUPLICATE KEY UPDATE transaction_check_ref=tokenKey;
  END IF;
  
  SET invalidateToken=0;
  IF (invalidateToken) THEN
    UPDATE gaming_cw_tokens SET is_confirmed=1, expiry_date=DATE_SUB(NOW(), INTERVAL 1 SECOND) WHERE cw_token_id=cwTokenID;
  END IF;
  
  
  CALL CommonWalletGetTokenByID(cwTokenID, -1);
  
  SET statusCode=0;
END root$$

DELIMITER ;

