DROP procedure IF EXISTS `LottoHeroCloseRound`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LottoHeroCloseRound`(
  sbExtraId BIGINT)
root:BEGIN
  
  DECLARE gameManufacturerID, clientStatID, roundRef BIGINT DEFAULT 0;
  
  DECLARE done INT DEFAULT 0;
  
  DECLARE cancelRoundDataCursor CURSOR FOR SELECT DISTINCT round_ref, gaming_game_rounds.client_stat_id
  FROM gaming_game_rounds
  JOIN gaming_game_manufacturers ON gaming_game_manufacturers.game_manufacturer_id = gaming_game_rounds.game_manufacturer_id
  WHERE gaming_game_manufacturers.name = 'LottoHero' AND 
	gaming_game_rounds.sb_extra_id = sbExtraId;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done =1;

  SELECT game_manufacturer_id
  INTO gameManufacturerID
  FROM gaming_game_manufacturers
  WHERE gaming_game_manufacturers.name = 'LottoHero';
  
  OPEN cancelRoundDataCursor;
  
  read_loop: LOOP
	FETCH cancelRoundDataCursor INTO roundRef, clientStatID;
	
	IF clientStatID = 0 THEN
		LEAVE read_loop;
	END IF;
	
	CALL CommonWalletCloseRound(roundRef, gameManufacturerID, clientStatID);
	
	SET roundRef = 0;
	SET clientStatID = 0;
	
  END LOOP;
  
  CLOSE cancelRoundDataCursor;
  
END root$$

DELIMITER ;