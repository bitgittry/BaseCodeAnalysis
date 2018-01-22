
DROP function IF EXISTS `CalcReturnBase_Adjustment`;
DROP function IF EXISTS `CalcReturnRealBase_Adjustment`;
DROP function IF EXISTS `CalcReturnBonusBase_Adjustment`;
DROP function IF EXISTS `CalcReturnRealBase_Adjustment_Singles`;
DROP function IF EXISTS `CalcReturnRealBase_Adjustment_Multiples`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CalcReturnBase_Adjustment`(sbEntityID BIGINT(11), entityType VARCHAR(10), isBonus TINYINT(1)) RETURNS decimal(18,2)
BEGIN
	
    DECLARE initialGamePlayID BIGINT DEFAULT NULL;
    DECLARE adjustmentAmount DECIMAL(18, 5) DEFAULT 0.00;

	-- betslip
	IF (entityType IS NULL) THEN	
		SELECT gaming_game_plays.game_play_id
		INTO initialGamePlayID
		FROM gaming_sb_bets
		STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id = gaming_sb_bets.sb_bet_id
		WHERE gaming_game_plays.payment_transaction_type_id IN (13, 30) AND gaming_sb_bets.sb_bet_id = sbEntityID
		ORDER BY gaming_game_plays.game_play_id
		LIMIT 1;
		
		IF (initialGamePlayID IS NOT NULL) THEN
				
			SELECT ROUND(CONV_BE(SUM((IF(isBonus = 0, gaming_game_plays.amount_real, gaming_game_plays.amount_bonus)
									+ IF(gaming_settings.value_bool = 1, gaming_game_plays.amount_tax_player + gaming_game_plays.amount_tax_operator, 0)) 
									* gaming_game_plays.sign_mult),
								 0),
						 2)
			INTO adjustmentAmount
			FROM gaming_sb_bets
			STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id = gaming_sb_bets.sb_bet_id
			STRAIGHT_JOIN gaming_settings ON gaming_settings.name = 'TAX_ON_GAMEPLAY_ENABLED'
			WHERE gaming_game_plays.payment_transaction_type_id IN (13, 30, 46) AND gaming_sb_bets.sb_bet_id = sbEntityID AND gaming_game_plays.game_play_id != initialGamePlayID
			GROUP BY gaming_sb_bets.sb_bet_id;
			
		END IF;
	
	-- singles
	ELSEIF(entityType = 'Singles') THEN
	
		SELECT gaming_game_plays_sb.game_play_sb_id
		INTO initialGamePlayID
		FROM gaming_sb_bet_singles
		INNER JOIN gaming_game_rounds ON gaming_game_rounds.sb_bet_id = gaming_sb_bet_singles.sb_bet_id
		INNER JOIN gaming_game_plays_sb ON gaming_game_plays_sb.game_round_id = gaming_game_rounds.game_round_id
		STRAIGHT_JOIN gaming_settings ON gaming_settings.name = 'TAX_ON_GAMEPLAY_ENABLED'
		WHERE sb_bet_single_id = sbEntityID
			  AND gaming_game_rounds.sb_bet_entry_id = gaming_sb_bet_singles.sb_bet_single_id 
			  AND gaming_game_rounds.sb_extra_id IS NOT NULL 
			  AND gaming_game_rounds.game_round_type_id = 4
			  AND gaming_game_rounds.is_cancelled = 0
			  AND gaming_game_plays_sb.payment_transaction_type_id IN (13, 30)
		ORDER BY gaming_game_plays_sb.game_play_sb_id
		LIMIT 1;
		
		IF (initialGamePlayID IS NOT NULL) THEN
			SELECT ROUND(CONV_BE(SUM((IF(isBonus = 0, gaming_game_plays_sb.amount_real, gaming_game_plays_sb.amount_bonus) + 
								 IF(gaming_settings.value_bool = 1, 
									gaming_game_plays_sb.amount_tax_player + gaming_game_plays_sb.amount_tax_operator, 0)) 
									* gaming_game_plays_sb.sign_mult), 
						0), 
					2)
			INTO adjustmentAmount
			FROM gaming_sb_bet_singles
			INNER JOIN gaming_game_rounds ON gaming_game_rounds.sb_bet_id = gaming_sb_bet_singles.sb_bet_id
			INNER JOIN gaming_game_plays_sb ON gaming_game_plays_sb.game_round_id = gaming_game_rounds.game_round_id
			STRAIGHT_JOIN gaming_settings ON gaming_settings.name = 'TAX_ON_GAMEPLAY_ENABLED'
			WHERE sb_bet_single_id = sbEntityID
				  AND gaming_game_rounds.sb_bet_entry_id = gaming_sb_bet_singles.sb_bet_single_id 
				  AND gaming_game_rounds.sb_extra_id IS NOT NULL 
				  AND gaming_game_rounds.game_round_type_id = 4
				  AND gaming_game_rounds.is_cancelled = 0
				  AND gaming_game_plays_sb.payment_transaction_type_id IN (13, 30, 46)
				  AND gaming_game_plays_sb.game_play_sb_id != initialGamePlayID
			GROUP BY gaming_game_rounds.game_round_id;
		END IF;
	
	-- multiples
	ELSEIF(entityType = 'Multiples') THEN
		
		SELECT gaming_game_plays_sb.game_play_sb_id
		INTO initialGamePlayID
		FROM gaming_sb_bet_multiples
		INNER JOIN gaming_game_rounds ON gaming_game_rounds.sb_bet_id = gaming_sb_bet_multiples.sb_bet_id
		INNER JOIN gaming_game_plays_sb ON gaming_game_plays_sb.game_round_id = gaming_game_rounds.game_round_id
		STRAIGHT_JOIN gaming_settings ON gaming_settings.name = 'TAX_ON_GAMEPLAY_ENABLED'
		WHERE gaming_sb_bet_multiples.sb_bet_multiple_id = sbEntityID
			  AND gaming_game_rounds.sb_bet_entry_id = gaming_sb_bet_multiples.sb_bet_multiple_id
			  AND gaming_game_rounds.sb_extra_id IS NOT NULL 
			  AND gaming_game_rounds.game_round_type_id = 5
			  AND gaming_game_rounds.is_cancelled = 0
			  AND gaming_game_plays_sb.payment_transaction_type_id IN (13, 30)
		ORDER BY gaming_game_plays_sb.game_play_sb_id
		LIMIT 1;
		
		IF (initialGamePlayID IS NOT NULL) THEN
			SELECT ROUND(CONV_BE(SUM((IF(isBonus = 0, gaming_game_plays_sb.amount_real, gaming_game_plays_sb.amount_bonus)
								+ IF(gaming_settings.value_bool = 1, 
									gaming_game_plays_sb.amount_tax_player + gaming_game_plays_sb.amount_tax_operator, 0))
									* gaming_game_plays_sb.sign_mult), 
						0), 
					2)
			INTO adjustmentAmount
			FROM gaming_sb_bet_multiples
			INNER JOIN gaming_game_rounds ON gaming_game_rounds.sb_bet_id = gaming_sb_bet_multiples.sb_bet_id
			INNER JOIN gaming_game_plays_sb ON gaming_game_plays_sb.game_round_id = gaming_game_rounds.game_round_id
			STRAIGHT_JOIN gaming_settings ON gaming_settings.name = 'TAX_ON_GAMEPLAY_ENABLED'
			WHERE gaming_sb_bet_multiples.sb_bet_multiple_id = sbEntityID
				  AND gaming_game_rounds.sb_bet_entry_id = gaming_sb_bet_multiples.sb_bet_multiple_id
				  AND gaming_game_rounds.sb_extra_id IS NOT NULL 
				  AND gaming_game_rounds.game_round_type_id = 5
				  AND gaming_game_rounds.is_cancelled = 0
				  AND gaming_game_plays_sb.payment_transaction_type_id IN (13, 30, 46)
				  AND gaming_game_plays_sb.game_play_sb_id != initialGamePlayID
			GROUP BY gaming_game_rounds.game_round_id;
		END IF;
		
	END IF;
    
    RETURN adjustmentAmount;

END$$

DELIMITER ;
