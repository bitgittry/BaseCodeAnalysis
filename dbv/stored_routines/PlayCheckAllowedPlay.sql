DROP procedure IF EXISTS `PlayCheckAllowedPlay`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayCheckAllowedPlay`(clientStatID BIGINT, sessionID BIGINT, gameID BIGINT, licenseType VARCHAR(20), OUT statusCode INT)
root:BEGIN
  -- Game ID
  
  DECLARE isGameBlocked, limitExceeded, isPlayAllowed, accountActivated, playerRestrictionEnabled, playerLimitEnabled, licenceCountryRestriction, countryDisallowPlayFromIP TINYINT(1) DEFAULT 0;
  DECLARE clientID, gameIDCheck, licenceTypeID BIGINT DEFAULT -1;

  IF (gameID IS NOT NULL) THEN
    SELECT gaming_games.game_id, gaming_operator_games.is_game_blocked, gaming_license_type.name, gaming_license_type.license_type_id
    INTO gameIDCheck, isGameBlocked, licenseType, licenceTypeID
    FROM gaming_games
    JOIN gaming_operators ON gaming_games.game_id=gameID AND gaming_operators.is_main_operator=1
    JOIN gaming_operator_games ON gaming_operator_games.game_id=gaming_games.game_id AND gaming_operators.operator_id=gaming_operator_games.operator_id
    JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_games.license_type_id;
    IF (gameIDCheck=-1 OR isGameBlocked) THEN
      SET statusCode=6;
      LEAVE root;
    END IF;
  END IF;
  
  SELECT gaming_clients.client_id, is_play_allowed AND !gaming_fraud_rule_client_settings.block_gameplay, account_activated 
  INTO clientID, isPlayAllowed, accountActivated 
  FROM gaming_client_stats
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id
  JOIN gaming_clients ON gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.client_id=gaming_clients.client_id;
  IF (clientID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  IF (isPlayAllowed=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SELECT value_bool INTO playerRestrictionEnabled FROM gaming_settings WHERE name='PLAYER_RESTRICTION_ENABLED';
  IF (playerRestrictionEnabled) THEN
    SET @numRestrictions=0;
    SET @restrictionType=NULL;
    SELECT restriction_types.name, COUNT(*) INTO @restrictionType, @numRestrictions
    FROM gaming_player_restrictions
    JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_play=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
    LEFT JOIN gaming_license_type ON gaming_player_restrictions.license_type_id=gaming_license_type.license_type_id
    WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date AND
      (gaming_license_type.name IS NULL OR gaming_license_type.name=licenseType);
  
    IF (@numRestrictions=1 AND @restrictionType='account_activation_policy' AND accountActivated=0) THEN
      SET statusCode = 3;
      LEAVE root;
    ELSEIF (@numRestrictions > 0) THEN
      SET statusCode=4;
      LEAVE root;
    END IF;
  END IF;
  SELECT value_bool INTO playerLimitEnabled FROM gaming_settings WHERE name='PLAY_LIMIT_ENABLED';
  IF (playerLimitEnabled) THEN
    SET @transactionAmount=0;
    SELECT PlayLimitCheckExceededWithGame(@transactionAmount, sessionID, clientStatID, licenseType, gameID) INTO limitExceeded;
  END IF;

  SELECT value_bool INTO licenceCountryRestriction FROM gaming_settings WHERE name='LICENCE_COUNTRY_RESTRICTION_ENABLED';
  IF(licenceCountryRestriction) THEN	 
	  -- Check if there are any country/ip restrictions for this player 
	  IF (SELECT !WagerRestrictionCheckCanWager(licenceTypeID, sessionID)) THEN 
		SET statusCode=9; 
		LEAVE root;
	  END IF;
  END IF;

  IF (limitExceeded > 0) THEN
      IF (limitExceeded = 10) THEN
  	    SET statusCode = 52;
       ELSE
        SET statusCode = 5;
      END IF;
    LEAVE root;
  END IF;
  SET statusCode=0;
END root$$

DELIMITER ;

