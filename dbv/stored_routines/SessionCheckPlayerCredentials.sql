DROP procedure IF EXISTS `SessionCheckPlayerCredentials`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionCheckPlayerCredentials`(playerUsername VARCHAR(255), playerPassword VARCHAR(255), OUT statusCode BIGINT)
BEGIN
  
  DECLARE userID, clientID, clientStatID, sessionID BIGINT DEFAULT -1;
  DECLARE varSalt, dbPassword, hashedPassword VARCHAR(255);
  DECLARE accountActivated, isActive, isTestPlayer, hasLoginAttemptTotal, playerLoginEnabled, testPlayerLoginEnabled, fraudEnabled, fraudOnLoginEnabled, allowLoginBannedCountryIP, countryDisallowLoginFromIP, playerRestrictionEnabled, usernameCaseSensitive TINYINT(1) DEFAULT 0;

  SET statusCode = 0; 
  
  SELECT value_bool INTO playerLoginEnabled FROM gaming_settings WHERE name='SESSION_ALLOW_LOGIN';
  SELECT value_bool INTO testPlayerLoginEnabled FROM gaming_settings WHERE name='SESSION_ALLOW_LOGIN_TESTPLAYERS';
  
  SELECT value_bool INTO usernameCaseSensitive FROM gaming_settings WHERE name='USERNAME_CASE_SENSITIVE';

  SELECT gaming_clients.client_id, gaming_client_stats.client_stat_id, salt, password, gaming_clients.account_activated, gaming_clients.is_active, gaming_clients.is_test_player, allow_login_banned_country_ip
  INTO clientID, clientStatID, varSalt, dbPassword, accountActivated, isActive, isTestPlayer, allowLoginBannedCountryIP    
  FROM gaming_clients FORCE INDEX (username)  
  JOIN gaming_client_stats ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active=1  
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
  WHERE gaming_clients.username = playerUsername AND IF (usernameCaseSensitive=1, BINARY gaming_clients.username = playerUsername, LOWER(username) = BINARY LOWER(playerUsername)) AND gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL);  
  
  IF (clientID=-1) THEN
    SET statusCode = 2;
  ELSEIF (isTestPlayer=0 AND playerLoginEnabled=0) THEN
    SET statusCode=6;
  ELSEIF (isTestPlayer=1 AND testPlayerLoginEnabled=0) THEN
    SET statusCode=6;
  
  
  ELSEIF (isActive=0) THEN
    SET statusCode = 4;
  ELSE
    SET hashedPassword = SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(playerPassword,'')),256);
    IF (hashedPassword <> dbPassword) THEN
      SET statusCode = 5;
    END IF;
  END IF;
  
  
  SELECT value_bool INTO playerRestrictionEnabled FROM gaming_settings WHERE name='PLAYER_RESTRICTION_ENABLED';
  IF (statusCode=0 AND playerRestrictionEnabled=1) THEN
    SET @numRestrictions=0;
    SET @restrictionType=NULL;
    SELECT restriction_types.name, COUNT(*) INTO @restrictionType, @numRestrictions
    FROM gaming_player_restrictions
    JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_login=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
    WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date;
  
    IF (@numRestrictions=1 AND @restrictionType='account_activation_policy' AND accountActivated=0) THEN
      SET statusCode = 3;
    ELSEIF (@numRestrictions > 0) THEN
      SET statusCode=12;
    END IF;
  END IF;
  
END$$

DELIMITER ;

