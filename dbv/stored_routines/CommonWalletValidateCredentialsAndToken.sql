DROP procedure IF EXISTS `CommonWalletValidateCredentialsAndToken`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletValidateCredentialsAndToken`(gameManufacturerName VARCHAR(80), apiUsername VARCHAR(80), apiPassword VARCHAR(80), tokenKey VARCHAR(80), ignoreTokenExpiry TINYINT(1), extendTokenExpiry TINYINT(1), generateResponseToken TINYINT(1), expireCurrent TINYINT(1), lockPlayer TINYINT(1), skipCredentialsCheck TINYINT(1), gameReference VARCHAR(80), OUT statusCode INT)
root: BEGIN
  -- Added parameter to skip credentials check 

	DECLARE gameManufacturerID, cwTokenID, clientStatID, gameSessionID, gameSessionIdOverride BIGINT DEFAULT -1;
	DECLARE validCredentials, isConfirmed TINYINT(1) DEFAULT 0;
	DECLARE expiryDate DATETIME;
	DECLARE tokenExpirySec INT;
    DECLARE gameName VARCHAR(80);
    
	SELECT game_manufacturer_id INTO gameManufacturerID FROM gaming_game_manufacturers WHERE name=gameManufacturerName;

	IF (gameManufacturerID=-1) THEN
		SET statusCode=1;
		LEAVE root;
	END IF;


	IF (skipCredentialsCheck AND CommonWalletValidateCredentials(gameManufacturerName, apiUsername, apiPassword)=0) THEN
		SET statusCode=2;
		LEAVE root;
	END IF;

	IF (gameManufacturerName='Microgaming' AND gameReference IS NOT NULL) THEN 
    
		SELECT cw_token_id, expiry_date, gaming_cw_tokens.client_stat_id, gaming_cw_tokens.game_session_id, gaming_cw_tokens.is_confirmed, gaming_games.name
		INTO cwTokenID, expiryDate, clientStatID, gameSessionID, isConfirmed, gameName
		FROM gaming_cw_tokens FORCE INDEX (token_key)
		STRAIGHT_JOIN gaming_game_sessions ON gaming_game_sessions.game_session_id = gaming_cw_tokens.game_session_id
		STRAIGHT_JOIN gaming_games ON gaming_games.game_id = gaming_game_sessions.game_id
		WHERE gaming_cw_tokens.token_key=tokenKey AND gaming_cw_tokens.game_manufacturer_id=gameManufacturerID;
        
        IF (gameName != gameReference) THEN
        
			SELECT game_session_id, game_session_id INTO gameSessionID, gameSessionIdOverride
			FROM gaming_games FORCE INDEX (`name`)
			STRAIGHT_JOIN gaming_game_sessions FORCE INDEX (cw_latest_sessions) ON 
				gaming_game_sessions.client_stat_id=clientStatID AND 
                gaming_game_sessions.game_id = gaming_games.game_id AND gaming_game_sessions.cw_game_latest = 1
			WHERE gaming_games.name = gameReference 
            LIMIT 1;
        
        END IF;
    
    ELSE
    
		SELECT cw_token_id, expiry_date, client_stat_id, game_session_id, is_confirmed
		INTO cwTokenID, expiryDate, clientStatID, gameSessionID, isConfirmed
		FROM gaming_cw_tokens FORCE INDEX (token_key)
		WHERE token_key=tokenKey AND game_manufacturer_id=gameManufacturerID;
    
    END IF;

	IF (cwTokenID=-1) THEN
		SET statusCode=3;
		LEAVE root;
	END IF;

	SET @expiryDate=expiryDate; 
	SET @isExpired=@expiryDate<NOW();
    
	IF (ignoreTokenExpiry=0 AND @isExpired) THEN
		SET statusCode=4;
		LEAVE root;
	END IF;

	IF (clientStatID IS NULL OR clientStatID=-1) THEN
		SET statusCode=3;
		LEAVE root;
	END IF;

	IF (lockPlayer) THEN
		SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
	END IF;

	IF (isConfirmed=0) THEN
		UPDATE gaming_cw_tokens SET is_confirmed=1 WHERE cw_token_id=cwTokenID;

		IF (gameManufacturerName='Microgaming') THEN
			INSERT INTO gaming_cw_players (client_stat_id, game_manufacturer_id, transaction_check_ref)
			SELECT clientStatID, gameManufacturerID, tokenKey
			ON DUPLICATE KEY UPDATE transaction_check_ref=tokenKey;
		END IF;
	END IF;

	IF (extendTokenExpiry) THEN
		SELECT attr_value INTO tokenExpirySec FROM gaming_game_manufacturer_attributes 
        WHERE game_manufacturer_id=gameManufacturerID AND attr_name='token_expiry_sec'; 
		
        SET tokenExpirySec=IFNULL(tokenExpirySec, 600);

		SET @newExpiryDate=DATE_ADD(NOW(), INTERVAL tokenExpirySec SECOND);
		
        UPDATE gaming_cw_tokens SET expiry_date=@newExpiryDate WHERE cw_token_id=cwTokenID;
        
	END IF;


	CALL CommonWalletGetTokenByID(cwTokenID, gameSessionIdOverride);

	IF (generateResponseToken AND @isExpired=0) THEN
		CALL CommonWalletCreateTokenGetData(gameManufacturerID, clientStatID, gameSessionID);

		IF (expireCurrent=1) THEN
			UPDATE gaming_cw_tokens SET expiry_date=NOW() WHERE cw_token_id=cwTokenID;
		END IF;
	END IF;


	SET statusCode=0;
    
END root$$

DELIMITER ;

