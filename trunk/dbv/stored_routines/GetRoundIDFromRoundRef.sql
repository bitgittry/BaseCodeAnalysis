DROP function IF EXISTS `GetRoundIDFromRoundRef`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `GetRoundIDFromRoundRef`(roundRef VARCHAR(65), clientStatID BIGINT(20), gameManufacturerName VARCHAR(60), gameRef VARCHAR(60)) RETURNS bigint(20)
BEGIN
	-- More redundancy in case GameRef is not supplied 

	DECLARE roundID BIGINT(20) DEFAULT NULL;
    DECLARE gameManufacturerID  BIGINT DEFAULT NULL;

	SET gameRef=IF(gameRef='', NULL, gameRef);
    
	SELECT game_manufacturer_id
    INTO gameManufacturerID
    FROM gaming_game_manufacturers 
    WHERE name = gameManufacturerName;
    
    SELECT ifnull(gameManufacturerID, game_manufacturer_id)
	INTO gameManufacturerID
	FROM gaming_game_manufacturers
	WHERE name='ThirdPartyClient';
      
	SELECT cw_round_id, IFNULL(gameRef, gaming_games.manufacturer_game_idf)
    INTO roundID, gameRef 
	FROM gaming_cw_rounds FORCE INDEX (cw_round_idx)
	LEFT JOIN gaming_games FORCE INDEX (manufacturer_game_idf) ON 
		gaming_games.game_manufacturer_id = gameManufacturerID AND manufacturer_game_idf = gameRef
	WHERE (gaming_cw_rounds.client_stat_id = clientStatID AND gaming_cw_rounds.game_manufacturer_id = gameManufacturerID AND
		gaming_cw_rounds.manuf_round_ref = roundRef) AND 
		(gameRef IS NULL OR gaming_cw_rounds.game_id = gaming_games.game_id)
	ORDER BY gaming_cw_rounds.cw_round_id DESC
	LIMIT 1;
	 
	IF(roundID IS NULL) THEN
		 INSERT INTO gaming_cw_rounds (game_manufacturer_id, client_stat_id, game_id, cw_latest, timestamp, manuf_round_ref) 
		 SELECT gaming_games.game_manufacturer_id, clientStatID, gaming_games.game_id, 0, NOW(), roundRef
		 FROM gaming_games FORCE INDEX (manufacturer_game_idf)
		 WHERE gaming_games.game_manufacturer_id = gameManufacturerID AND gaming_games.manufacturer_game_idf = gameRef
         LIMIT 1;
		 
         IF (ROW_COUNT() = 1) THEN
			SET roundID = LAST_INSERT_ID();
		 END IF;
	 END IF;
 
	 RETURN roundID; 

END$$

DELIMITER ;

