DROP procedure IF EXISTS `LottoSportsBookCancelBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LottoSportsBookCancelBet`(
  couponID BIGINT, cancelReason VARCHAR(255), isPlayerCancel TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN

	DECLARE playWagerType VARCHAR(80) DEFAULT 'Type1';
    DECLARE sbBetID, singleMultTypeID, gameManufacturerID, clientStatID, gamePlayID, gameRoundID, sbBetTypeID, selectionToCancelID BIGINT DEFAULT 0;
	DECLARE gamePlayIDReturned BIGINT DEFAULT NULL;
    DECLARE betTransactionRef VARCHAR(64) DEFAULT NULL;
	DECLARE betAmount, amountTotal DECIMAL (18,5) DEFAULT 0;
    DECLARE isProcessed TINYINT(1) DEFAULT 0;
	DECLARE sbBetStatusCode, paymentTransactionTypeId INT DEFAULT 0;
    DECLARE numSingles, numMultiples, numBetEntries INT DEFAULT 0;
	DECLARE betRef VARCHAR(40) DEFAULT NULL;
   
    SET statusCode = 0;

	SELECT gs1.value_string as vs1
	INTO playWagerType
	FROM gaming_settings gs1
	WHERE gs1.name='PLAY_WAGER_TYPE';

	SELECT gaming_sb_bets.sb_bet_id, gaming_sb_bets.game_manufacturer_id, gaming_sb_bets.transaction_ref, 
		gaming_sb_bets.amount_real + gaming_sb_bets.amount_bonus + gaming_sb_bets.amount_free_bet + gaming_sb_bets.amount_bonus_win_locked,
		gaming_sb_bets.is_processed, gaming_sb_bets.status_code, gaming_sb_bets.num_singles, gaming_sb_bets.num_multiplies, gaming_lottery_coupons.client_stat_id,
        gaming_sb_bets.sb_bet_type_id
    INTO sbBetID, gameManufacturerID, betTransactionRef, betAmount, isProcessed, sbBetStatusCode, numSingles, numMultiples, clientStatID, sbBetTypeID
    FROM gaming_lottery_coupons
    STRAIGHT_JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
    STRAIGHT_JOIN gaming_sb_bets ON gaming_sb_bets.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
    WHERE gaming_lottery_coupons.lottery_coupon_id = couponID;

	SET numBetEntries = numSingles+numMultiples; 

	IF (sbBetStatusCode != 5 OR isProcessed = 0 OR numBetEntries=0) THEN 
		SET statusCode=3;
		LEAVE root;
	END IF;	

	UPDATE gaming_lottery_coupons
    SET gaming_lottery_coupons.lottery_wager_status_id = 8, 
		gaming_lottery_coupons.lottery_coupon_status_id = 2104,
        cancel_reason=cancelReason, cancel_date=NOW()
    WHERE gaming_lottery_coupons.lottery_coupon_id = couponID;
    
	UPDATE gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_lottery_participations ON 
		gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
		AND gaming_lottery_participations.lottery_wager_status_id = 5
    SET gaming_lottery_participations.lottery_wager_status_id = 8,
		gaming_lottery_participations.lottery_participation_status_id = 2103
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;


	IF (numBetEntries=1) THEN
		SET betRef=NULL;
	ELSEIF (numBetEntries>1 AND numMultiples=1) THEN
		SELECT bet_ref, gaming_sb_bet_multiples_singles.sb_selection_id 
        INTO betRef, selectionToCancelID 
        FROM gaming_sb_bet_multiples FORCE INDEX (sb_bet_id) 
        LEFT JOIN gaming_sb_bet_multiples_singles ON gaming_sb_bet_multiples_singles.sb_bet_multiple_id = gaming_sb_bet_multiples.sb_bet_multiple_id
        WHERE gaming_sb_bet_multiples.sb_bet_id = sbBetID 
        LIMIT 1;
	ELSE
		SELECT bet_ref, sb_selection_id INTO betRef, selectionToCancelID FROM gaming_sb_bet_singles FORCE INDEX (sb_bet_id) WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID LIMIT 1;
    END IF;
    
    SELECT game_play_id, game_round_id
    INTO gamePlayID, gameRoundID
    FROM gaming_game_plays FORCE INDEX (sb_bet_id)
    WHERE gaming_game_plays.sb_bet_id = sbBetID AND license_type_id = 3 AND payment_transaction_type_id in (12, 45)
    ORDER BY game_play_id DESC
    LIMIT 1;
	
    CALL PlaceSBBetCancel(clientStatID, gamePlayID, gameRoundID, betAmount, sbBetTypeID, 1, selectionToCancelID, 1, gamePlayIDReturned, statusCode);
	
	-- Update master record in gaming_game_rounds to reflect CancelBet operation
    UPDATE gaming_game_rounds FORCE INDEX (PRIMARY)
    JOIN gaming_client_stats FORCE INDEX (PRIMARY) ON gaming_game_rounds.client_stat_id = gaming_client_stats.client_stat_id
	SET
	  gaming_game_rounds.date_time_end = NOW(),
	  gaming_game_rounds.is_round_finished = 1,
	  gaming_game_rounds.is_processed = 1,
	  gaming_game_rounds.balance_real_after = gaming_client_stats.current_real_balance,
	  gaming_game_rounds.balance_bonus_after = gaming_client_stats.current_bonus_balance,
	  gaming_game_rounds.is_round_finished = 1,
	  gaming_game_rounds.is_cancelled = 1
	 WHERE gaming_game_rounds.round_ref=sbBetID;
	 
	IF(isPlayerCancel) THEN
		-- Set transaction type id to Player Stake Cancelled
		SET paymentTransactionTypeId = 247;
	ELSE
		-- Set transaction type id to Operator Stake Cancelled
		SET paymentTransactionTypeId = 20;
	END IF;
    
    UPDATE gaming_game_plays FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (game_play_id) ON 
		gaming_game_plays.game_play_id = gaming_game_plays_sb.game_play_id
	SET
	  gaming_game_plays.payment_transaction_type_id = paymentTransactionTypeId,
	  gaming_game_plays_sb.payment_transaction_type_id = paymentTransactionTypeId
	WHERE gaming_game_plays.game_play_id = gamePlayIDReturned;

    -- sum bet total
    SELECT amount_real + amount_bonus + amount_bonus_win_locked + amount_free_bet
    INTO amountTotal
    FROM gaming_sb_bets
    WHERE sb_bet_id = sbBetID;
    
    -- Update bet amount to bet total
    UPDATE gaming_sb_bets
    SET 
		bet_total = IFNULL(amountTotal, 0),
		amount_real = 0,
        amount_bonus = 0,
        amount_bonus_win_locked = 0,
        amount_free_bet = 0
		-- status_code = 4
    WHERE sb_bet_id = sbBetID;
	
	-- update rounds to cancelled
	UPDATE gaming_game_rounds
    SET
		is_cancelled = 1
	WHERE sb_bet_id = sbBetID;
    
	SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayIDReturned;
	CALL PlayReturnDataWithoutGame(gamePlayIDReturned, gameRoundID, clientStatID, gameManufacturerID, minimalData);
	CALL PlayReturnBonusInfoOnWin(gamePlayIDReturned);
    
    -- delete bonuses
    DELETE
    FROM gaming_sb_bets_bonuses
    WHERE sb_bet_id = sbBetID;

END root$$

DELIMITER ;

