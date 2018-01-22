DROP procedure IF EXISTS `CommonWalletCloseRound`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCloseRound`(
  roundRef BIGINT, gameManufacturerID BIGINT, clientStatID BIGINT)
root:BEGIN
  
  -- Added return of gameRoundID
  -- Passing checkWinZero = 0

  DECLARE gameRoundID BIGINT DEFAULT -1;
  
  SELECT IFNULL(gaming_game_rounds.game_round_id, -1)
  INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_round_ref)
  WHERE gaming_game_rounds.round_ref=roundRef AND gaming_game_rounds.client_stat_id=clientStatID AND gaming_game_rounds.game_manufacturer_id=gameManufacturerID
  ORDER BY gaming_game_rounds.game_round_id DESC LIMIT 1;
  
  IF (gameRoundID > 0) THEN
	
    CALL PlayCloseRound(gameRoundID, 0, 1, 1);
  
  ELSE
  
    CALL PlayReturnPlayBalanceData(clientStatID, -1);

    SELECT gameRoundID AS game_round_id;
  
  END IF;
  
END root$$

DELIMITER ;

