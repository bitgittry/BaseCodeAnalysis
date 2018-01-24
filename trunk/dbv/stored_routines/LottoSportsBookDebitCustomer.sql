DROP procedure IF EXISTS `LottoSportsBookDebitCustomer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LottoSportsBookDebitCustomer`(
  couponID BIGINT, transactionRef VARCHAR(100), BetRef VARCHAR(40), debitGrossAmount DECIMAL(18, 5), 
  debitNetAmount DECIMAL(18, 5), minimalData TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
BEGIN

	DECLARE playWagerType VARCHAR(80) DEFAULT 'Type1';
    DECLARE sbBetID, singleMultTypeID, gameManufacturerID, clientStatID BIGINT DEFAULT 0;
	DECLARE betTransactionRef VARCHAR(64) DEFAULT NULL;
    DECLARE numSingles, numMultiples, numBetEntries INT DEFAULT 0;
	-- DECLARE betRef VARCHAR(40) DEFAULT NULL;
    DECLARE taxEnabled, calucatedByProvider, verticalVersion TINYINT(1) DEFAULT 0;
    DECLARE taxAmount DECIMAL(18, 5) DEFAULT 0;
    
    SET statusCode = 0;
	SET gamePlayIDReturned = NULL;

	SELECT gs1.value_string as vs1
	INTO playWagerType
	FROM gaming_settings gs1
	WHERE gs1.name='PLAY_WAGER_TYPE';
    
	SELECT gaming_sb_bets.sb_bet_id, gaming_sb_bets.game_manufacturer_id, gaming_sb_bets.transaction_ref,
		gaming_sb_bets.num_singles, gaming_sb_bets.num_multiplies, gaming_sb_bets.client_stat_id, IFNULL(gaming_lottery_coupons.vertical_version,0)
    INTO sbBetID, gameManufacturerID, betTransactionRef, numSingles, numMultiples, clientStatID, verticalVersion
    FROM gaming_lottery_coupons
    STRAIGHT_JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
    STRAIGHT_JOIN gaming_sb_bets ON gaming_sb_bets.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
    WHERE gaming_lottery_coupons.lottery_coupon_id = couponID;

  IF (BetRef is NULL) THEN
  	IF (numBetEntries=1) THEN
  		SET betRef=NULL;
  	ELSEIF (numBetEntries>1 AND numMultiples=1) THEN
  		SELECT bet_ref INTO betRef FROM gaming_sb_bet_multiples FORCE INDEX (sb_bet_id) WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID LIMIT 1;
  	ELSE
  		SELECT bet_ref INTO betRef FROM gaming_sb_bet_singles FORCE INDEX (sb_bet_id) WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID LIMIT 1;
      END IF;
  END IF;


	-- type 1 or tyoe 2 is handled in the sp 
	CALL CommonWalletSportsGenericDebitCustomerByBetRef(gameManufacturerID, 
		transactionRef, betTransactionRef, betRef, debitNetAmount, minimalData, gamePlayIDReturned, statusCode);

	SELECT value_bool
	INTO taxEnabled
	FROM gaming_settings
	WHERE name = 'TAX_ON_GAMEPLAY_ENABLED';

	-- is tax on win calculated by provider
	SELECT gct.calculated_by_provider
	INTO calucatedByProvider
	FROM gaming_client_stats gcs
	INNER JOIN gaming_clients gc ON gc.client_id = gcs.client_id
	INNER JOIN clients_locations cl ON cl.client_id = gc.client_id
	INNER JOIN gaming_country_tax gct ON gct.country_id = cl.country_id
	WHERE gcs.client_stat_id = clientStatID 
		AND cl.is_primary = 1 AND cl.is_active = 1 
		AND gct.is_current = 1 AND gct.tax_rule_type_id = 2 AND gct.licence_type_id = 3
	ORDER BY gct.date_start DESC
    LIMIT 1;
	
    IF (statusCode = 0 AND gamePlayIDReturned IS NOT NULL AND taxEnabled = 1 AND calucatedByProvider = 1) THEN        
		-- CPREQ-294 tax player
        SET taxAmount = ABS(debitGrossAmount - debitNetAmount) * -1;
		
        UPDATE gaming_game_plays
        INNER JOIN gaming_game_rounds ON gaming_game_plays.game_round_id = gaming_game_rounds.game_round_id
		INNER JOIN gaming_game_plays_sb ON gaming_game_plays_sb.game_play_id = gaming_game_plays.game_play_id AND gaming_game_plays_sb.game_round_id = gaming_game_rounds.game_round_id
        SET gaming_game_plays.amount_tax_player = taxAmount,
			gaming_game_rounds.amount_tax_player = taxAmount,
			gaming_game_plays_sb.amount_tax_player = taxAmount,
			gaming_game_rounds.amount_tax_player_original = IFNULL(gaming_game_rounds.amount_tax_player_original, taxAmount)
        WHERE gaming_game_plays.game_play_id = gamePlayIDReturned;
        
    END IF;
    
END$$

DELIMITER ;

