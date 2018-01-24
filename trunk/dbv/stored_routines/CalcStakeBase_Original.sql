
DROP function IF EXISTS `CalcStakeBase_Original`;
DROP function IF EXISTS `CalcStakeRealBase_Original`;
DROP function IF EXISTS `CalcStakeBonusBase_Original`;
DROP function IF EXISTS `CalcStakeRealBase_Original_Singles`;
DROP function IF EXISTS `CalcStakeRealBase_Original_Multiples`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CalcStakeBase_Original`(sbEntityID BIGINT(11), entityType VARCHAR(10), isBonus TINYINT(1)) RETURNS decimal(18,2)
BEGIN

	DECLARE amountReal DECIMAL(18,5) DEFAULT 0.00;
	
	-- betslip
	IF(entityType IS NULL) THEN
		SELECT ROUND(CONV_BE( IF(isBonus = 0, gaming_game_plays.amount_real, gaming_game_plays.amount_bonus), 0), 2)
		INTO amountReal
		FROM gaming_sb_bets
		STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id = gaming_sb_bets.sb_bet_id
		WHERE gaming_sb_bets.sb_bet_id = sbEntityID AND gaming_game_plays.payment_transaction_type_id = 12
		ORDER BY gaming_game_plays.game_play_id
		LIMIT 1;
	
	-- singles
	ELSEIF(entityType = 'Singles') THEN
		SELECT ROUND(CONV_BE( IF(isBonus = 0, gaming_game_plays_sb.amount_real, gaming_game_plays_sb.amount_bonus), 0), 2)
		INTO amountReal
		FROM gaming_sb_bet_singles
		INNER JOIN gaming_game_rounds ON gaming_game_rounds.sb_bet_id = gaming_sb_bet_singles.sb_bet_id
        INNER JOIN gaming_game_plays_sb ON gaming_game_plays_sb.game_round_id = gaming_game_rounds.game_round_id
		WHERE sb_bet_single_id = sbEntityID AND 
			  gaming_game_rounds.sb_bet_entry_id = gaming_sb_bet_singles.sb_bet_single_id AND 
			  gaming_game_rounds.sb_extra_id IS NOT NULL 
			  AND gaming_game_rounds.game_round_type_id = 4
			  AND gaming_game_rounds.is_cancelled = 0
              AND gaming_game_plays_sb.payment_transaction_type_id = 12
		ORDER BY gaming_game_plays_sb.game_play_id
		LIMIT 1;
			  
	-- multiples
	ELSEIF(entityType = 'Multiples') THEN
		SELECT ROUND(CONV_BE( IF(isBonus = 0, gaming_game_plays_sb.amount_real, gaming_game_plays_sb.amount_bonus), 0), 2)
		INTO amountReal
		FROM gaming_sb_bet_multiples
		INNER JOIN gaming_game_rounds ON gaming_game_rounds.sb_bet_id = gaming_sb_bet_multiples.sb_bet_id
        INNER JOIN gaming_game_plays_sb ON gaming_game_plays_sb.game_round_id = gaming_game_rounds.game_round_id
		WHERE gaming_sb_bet_multiples.sb_bet_multiple_id = sbEntityID
			  AND gaming_game_rounds.sb_bet_entry_id = gaming_sb_bet_multiples.sb_bet_multiple_id
			  AND gaming_game_rounds.sb_extra_id IS NOT NULL 
			  AND gaming_game_rounds.game_round_type_id = 5
			  AND gaming_game_rounds.is_cancelled = 0
              AND gaming_game_plays_sb.payment_transaction_type_id = 12
		ORDER BY gaming_game_plays_sb.game_play_id
		LIMIT 1;

	END IF;

	RETURN amountReal;
	
END$$

DELIMITER ;
