
DROP function IF EXISTS `CalcReturnBase_Tax`;
DROP function IF EXISTS `CalcReturnRealBase_Tax`;
DROP function IF EXISTS `CalcReturnBonusBase_Tax`;
DROP function IF EXISTS `CalcReturnRealBase_Tax_Singles`;
DROP function IF EXISTS `CalcReturnRealBase_Tax_Multiples`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CalcReturnBase_Tax`(sbEntityID BIGINT(11), entityType VARCHAR(10), isBonus TINYINT(1)) RETURNS decimal(18,2)
BEGIN

	DECLARE taxAmount DECIMAL(18, 2) DEFAULT 0;
	    
	-- betslip
	IF (entityType IS NULL) THEN
		SELECT IF (gaming_settings.value_bool = 1, ROUND(CONV_BE(SUM(IFNULL(gaming_game_plays.amount_tax_player, 0) + gaming_game_plays.amount_tax_operator), 0), 2), 0)
		INTO taxAmount
		FROM gaming_sb_bets
		STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id = gaming_sb_bets.sb_bet_id
		STRAIGHT_JOIN gaming_settings ON gaming_settings.name = 'TAX_ON_GAMEPLAY_ENABLED'
		WHERE gaming_game_plays.payment_transaction_type_id IN (13, 30, 46) AND gaming_sb_bets.sb_bet_id = sbEntityID
		GROUP BY gaming_sb_bets.sb_bet_id;
	
	-- singles
	ELSEIF(entityType = 'Singles') THEN 
		SELECT IF(gaming_settings.value_bool = 1, gaming_game_rounds.amount_tax_player + gaming_game_rounds.amount_tax_operator, 0)
		INTO taxAmount
		FROM gaming_sb_bet_singles
		INNER JOIN gaming_game_rounds ON gaming_game_rounds.sb_bet_id = gaming_sb_bet_singles.sb_bet_id
		STRAIGHT_JOIN gaming_settings ON gaming_settings.name = 'TAX_ON_GAMEPLAY_ENABLED'
		WHERE sb_bet_single_id = sbEntityID
			  AND gaming_game_rounds.sb_bet_entry_id = gaming_sb_bet_singles.sb_bet_single_id 
			  AND gaming_game_rounds.sb_extra_id IS NOT NULL 
			  AND gaming_game_rounds.game_round_type_id = 4
			  AND gaming_game_rounds.is_cancelled = 0;
			  
	-- multiples
	ELSEIF(entityType = 'Multiples') THEN
		SELECT ROUND(CONV_BE(IF(gaming_settings.value_bool = 1, gaming_game_rounds.amount_tax_player + gaming_game_rounds.amount_tax_operator, 0), 
							 0), 
					 2)
		INTO taxAmount
		FROM gaming_sb_bet_multiples
		INNER JOIN gaming_game_rounds ON gaming_game_rounds.sb_bet_id = gaming_sb_bet_multiples.sb_bet_id
		STRAIGHT_JOIN gaming_settings ON gaming_settings.name = 'TAX_ON_GAMEPLAY_ENABLED'
		WHERE gaming_sb_bet_multiples.sb_bet_multiple_id = sbEntityID
			  AND gaming_game_rounds.sb_bet_entry_id = gaming_sb_bet_multiples.sb_bet_multiple_id
			  AND gaming_game_rounds.sb_extra_id IS NOT NULL 
			  AND gaming_game_rounds.game_round_type_id = 5
			  AND gaming_game_rounds.is_cancelled = 0;
	
	END IF;
    
	RETURN taxAmount;
	
END$$

DELIMITER ;
