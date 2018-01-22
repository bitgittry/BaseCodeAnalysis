DROP procedure IF EXISTS `SessionPlayerLoginControl`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionPlayerLoginControl`(kickoutPlayers TINYINT(1), playerLoginEnabled TINYINT(1), testPlayerLoginEnabled TINYINT(1), sessionID BIGINT)
BEGIN
  -- Simplified the count of logged-in players
  
  IF (kickoutPlayers=1) THEN
    CALL SessionKickoutAllPlayers(sessionID);
  END IF;
  IF (playerLoginEnabled IS NOT NULL) THEN
    UPDATE gaming_settings SET value_bool=playerLoginEnabled, session_id=sessionID WHERE name='SESSION_ALLOW_LOGIN';
  END IF;
  
  IF (testPlayerLoginEnabled IS NOT NULL) THEN
    UPDATE gaming_settings SET value_bool=testPlayerLoginEnabled, session_id=sessionID WHERE name='SESSION_ALLOW_LOGIN_TESTPLAYERS';
  END IF;
  
  SELECT value_bool INTO playerLoginEnabled FROM gaming_settings WHERE name='SESSION_ALLOW_LOGIN';
  SELECT value_bool INTO testPlayerLoginEnabled FROM gaming_settings WHERE name='SESSION_ALLOW_LOGIN_TESTPLAYERS';
  
  SELECT COUNT(DISTINCT extra_id) AS num_players_online, playerLoginEnabled AS player_login_enabled, testPlayerLoginEnabled AS test_player_login_enabled
  FROM sessions_main 
  WHERE sessions_main.status_code=1 AND sessions_main.session_type=2;

END$$

DELIMITER ;

