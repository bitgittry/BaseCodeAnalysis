
DROP procedure IF EXISTS `GameSessionCheckByGameManufacturerRoundRef`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameSessionCheckByGameManufacturerRoundRef`(clientStatID BIGINT, gameManufacturerID BIGINT, roundRef BIGINT, operatorID BIGINT, componentID BIGINT, ignoreSessionExpiry TINYINT(1), extendSessionExpiry TINYINT(1), OUT statusCode INT)
root:BEGIN
  
--
  DECLARE gameRoundID, gameSessionID BIGINT DEFAULT NULL;
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_manufacturer_id=gameManufacturerID 
  ORDER BY gaming_game_rounds.round_ref DESC, game_round_id DESC LIMIT 1;

  SELECT game_session_id INTO gameSessionID FROM gaming_game_plays WHERE game_round_id=gameRoundID LIMIT 1;

  CALL GameSessionCheckByGameSessionID(gameSessionID, componentID, ignoreSessionExpiry, extendSessionExpiry, statusCode);

END root$$

DELIMITER ;

