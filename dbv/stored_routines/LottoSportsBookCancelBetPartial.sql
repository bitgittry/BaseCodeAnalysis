DROP procedure IF EXISTS `LottoSportsBookCancelBetPartial`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LottoSportsBookCancelBetPartial`(
  couponID BIGINT, betSingleIdentifier VARCHAR(40), betMultipleIdentifier VARCHAR(40), cancelReason VARCHAR(255), 
  isPlayerCancel TINYINT, minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN
	DECLARE playWagerType VARCHAR(80) DEFAULT 'Type1';
    DECLARE sbBetID, singleMultTypeID, gameManufacturerID, clientStatID, gamePlayID, gameRoundID, gameParentRoundID, gameBetRoundIDToIndentifyBetRef, sbBetTypeID, selectionToCancelID, sbBetEntryID BIGINT DEFAULT 0;
	DECLARE gamePlayIDReturned BIGINT DEFAULT NULL;
    DECLARE betTransactionRef VARCHAR(64) DEFAULT NULL;
	DECLARE betAmount, amountTotal, betReal, betBonus, betFreeBet, betBonusWinLocked DECIMAL (18,5) DEFAULT 0;
    DECLARE isProcessed TINYINT(1) DEFAULT 0;
	DECLARE sbBetStatusCode, paymentTransactionTypeId, numOfBets INT DEFAULT 0;
    DECLARE numSingles, numMultiples, numBetEntries INT DEFAULT 0;
	DECLARE betRef VARCHAR(40) DEFAULT NULL;
    DECLARE codeToIdentifyRowsToCancel TINYINT(1) DEFAULT 3;
    
    SET statusCode = 0;

	SELECT gs1.value_string as vs1
	INTO playWagerType
	FROM gaming_settings gs1
	WHERE gs1.name='PLAY_WAGER_TYPE';

	IF (betMultipleIdentifier IS NOT NULL) THEN
		SET betRef = betMultipleIdentifier;

		#mark the records involved
		UPDATE gaming_game_rounds ggr
		JOIN  gaming_sb_bet_multiples gsbm ON gsbm.sb_bet_multiple_id = ggr.sb_bet_entry_id AND ggr.game_round_type_id = 5
				join gaming_sb_bets gsb ON gsbm.sb_bet_id = gsb.sb_bet_id
				join gaming_lottery_dbg_tickets gldt ON gldt.lottery_dbg_ticket_id  = gsb.lottery_dbg_ticket_id
				join gaming_lottery_coupons glc ON gldt.lottery_coupon_id = glc.lottery_coupon_id and glc.lottery_coupon_id = couponID
		SET ggr.is_cancelled = codeToIdentifyRowsToCancel
		where gsbm.bet_ref = betMultipleIdentifier and ggr.is_cancelled != 1;

		select gaming_sb_bet_multiples.sb_bet_id, gaming_sb_bets.game_manufacturer_id, gaming_sb_bet_multiples.client_stat_id, gaming_sb_bets.sb_bet_type_id
		#gaming_sb_bet_multiples.sb_selection_id  
		INTO sbBetID, gameManufacturerID, clientStatID, sbBetTypeID
		 from gaming_sb_bet_multiples 
		join gaming_sb_bets on gaming_sb_bet_multiples.sb_bet_id = gaming_sb_bets.sb_bet_id
		join gaming_lottery_dbg_tickets on gaming_lottery_dbg_tickets.lottery_dbg_ticket_id  = gaming_sb_bets.lottery_dbg_ticket_id
		join gaming_lottery_coupons on gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id and gaming_lottery_coupons.lottery_coupon_id = couponID
		where gaming_sb_bet_multiples.bet_ref = betMultipleIdentifier;	

	else
		SET betRef = betSingleIdentifier;

		#mark the records involved
		UPDATE gaming_game_rounds ggr
		JOIN  gaming_sb_bet_singles gsbs ON gsbs.sb_bet_single_id = ggr.sb_bet_entry_id AND ggr.game_round_type_id = 4
				join gaming_sb_bets gsb ON gsbs.sb_bet_id = gsb.sb_bet_id
				join gaming_lottery_dbg_tickets gldt ON gldt.lottery_dbg_ticket_id  = gsb.lottery_dbg_ticket_id
				join gaming_lottery_coupons glc ON gldt.lottery_coupon_id = glc.lottery_coupon_id and glc.lottery_coupon_id = couponID
		SET ggr.is_cancelled = codeToIdentifyRowsToCancel
				where gsbs.bet_ref = betSingleIdentifier and ggr.is_cancelled != 1;


		select gaming_sb_bet_singles.sb_bet_id, gaming_sb_bets.game_manufacturer_id, gaming_sb_bet_singles.client_stat_id, gaming_sb_bets.sb_bet_type_id
		#gaming_sb_bet_singles.sb_selection_id 
		INTO sbBetID, gameManufacturerID, clientStatID, sbBetTypeID
		 from gaming_sb_bet_singles 
		join gaming_sb_bets on gaming_sb_bet_singles.sb_bet_id = gaming_sb_bets.sb_bet_id
		join gaming_lottery_dbg_tickets on gaming_lottery_dbg_tickets.lottery_dbg_ticket_id  = gaming_sb_bets.lottery_dbg_ticket_id
		join gaming_lottery_coupons on gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id and gaming_lottery_coupons.lottery_coupon_id = couponID
		where gaming_sb_bet_singles.bet_ref = betSingleIdentifier LIMIT 1;
	END IF;

	#find the specific rounds of the bet using sb_bet_entry_id
	#note: if we have a single with 3 events will have a round per each single and with same bet_ref in gaming_sb_bet_singles
	SELECT count(1), sum(gaming_game_rounds.bet_real), sum(gaming_game_rounds.bet_bonus), sum(gaming_game_rounds.bet_free_bet), sum(gaming_game_rounds.bet_bonus_win_locked), MAX(gaming_game_rounds.game_round_id)
	INTO numBetEntries,  betReal, betBonus, betFreeBet, betBonusWinLocked, gameBetRoundIDToIndentifyBetRef
	from gaming_game_rounds where gaming_game_rounds.sb_bet_id = sbBetID and gaming_game_rounds.is_cancelled = codeToIdentifyRowsToCancel;

	IF (numBetEntries = 0) THEN	#bet was already cancelled
		SELECT gaming_game_plays.game_play_id, gaming_game_plays.game_round_id INTO gamePlayIDReturned, gameRoundID 
        FROM gaming_game_plays FORCE INDEX (sb_bet_id)
		STRAIGHT_JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id=gaming_game_plays.sb_extra_id
		WHERE gaming_game_plays.sb_bet_id = sbBetID and payment_transaction_type_id = 20 limit 1;
		
		#SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayIDReturned;
		CALL PlayReturnDataWithoutGame(gamePlayIDReturned, gameRoundID, clientStatID, gameManufacturerID, minimalData);
		CALL PlayReturnBonusInfoOnWin(gamePlayIDReturned);
    
		SET statusCode=2;
		LEAVE root;
	END IF;

	SET betAmount = betReal + betBonus + betFreeBet + betBonusWinLocked;

    SELECT game_play_id, game_round_id
    INTO gamePlayID, gameParentRoundID
    FROM gaming_game_plays
    WHERE gaming_game_plays.sb_bet_id = sbBetID AND license_type_id = 3 AND payment_transaction_type_id in (12, 45)
    ORDER BY game_play_id DESC
    LIMIT 1;

    UPDATE gaming_game_rounds AS ggr  SET ggr.num_bets=GREATEST(0, ggr.num_bets-numBetEntries)  WHERE game_round_id=gameParentRoundID;

    CALL PlaceSBBetCancelPartial(clientStatID, gamePlayID, gameParentRoundID, sbBetID, gameBetRoundIDToIndentifyBetRef, betAmount, sbBetTypeID, 1, selectionToCancelID, 1, gamePlayIDReturned, statusCode);
	
	-- Update all roundsrelated to the bet
    UPDATE gaming_game_rounds AS ggr FORCE INDEX (PRIMARY)
    JOIN gaming_client_stats FORCE INDEX (PRIMARY) ON ggr.client_stat_id = gaming_client_stats.client_stat_id
	SET
		ggr.is_cancelled = 1,
		ggr.is_round_finished = 1,
		ggr.is_processed = 1,
		ggr.date_time_end = NOW(),
		ggr.balance_real_after = gaming_client_stats.current_real_balance,
		ggr.balance_bonus_after = gaming_client_stats.current_bonus_balance,
		ggr.num_transactions=ggr.num_transactions+1,
		ggr.bet_total=0,
		ggr.bet_total_base=0,
		ggr.bet_real=0,
		ggr.bet_bonus=0,
		ggr.bet_bonus_win_locked=0, 
		ggr.win_bet_diffence_base=0,
		ggr.num_bets=0
	 WHERE ggr.sb_bet_id = sbBetID AND ggr.is_cancelled = codeToIdentifyRowsToCancel;
	 
  SELECT num_bets INTO numOfBets FROM gaming_game_rounds WHERE gaming_game_rounds.game_round_id=gameParentRoundID;

  IF(numOfBets = 0) THEN
	
	#check if all are cancelled to also set parent round as cancelled
	SET @allBetsCanceled = (select count(*) = sum(is_cancelled) from gaming_game_rounds where sb_bet_id = sbBetID and game_round_id != gameParentRoundID);
	IF @allBetsCanceled THEN
		UPDATE gaming_game_rounds 
		SET gaming_game_rounds.is_cancelled = 1
		WHERE gaming_game_rounds.game_round_id=gameParentRoundID;

		-- update gaming_game_plays.is_cancelled = true if master record from gaming_game_rounds is cancelled
		UPDATE gaming_game_plays 
		SET is_cancelled = 1 
		WHERE game_play_id = gamePlayID;

		UPDATE gaming_lottery_coupons
		SET gaming_lottery_coupons.lottery_wager_status_id = 8, 	#Bet Cancelled
			gaming_lottery_coupons.lottery_coupon_status_id = 2104, #CANCELLED
			cancel_reason=cancelReason, cancel_date=NOW()
		WHERE gaming_lottery_coupons.lottery_coupon_id = couponID;
    
		UPDATE gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
		STRAIGHT_JOIN gaming_lottery_participations ON 
			gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
			AND gaming_lottery_participations.lottery_wager_status_id = 5 			#Bet Placed
		SET gaming_lottery_participations.lottery_wager_status_id = 8,				#Bet Cancelled
			gaming_lottery_participations.lottery_participation_status_id = 2103 	#CANCELLED
		WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
	END IF;
    
  END IF;

	IF(isPlayerCancel) THEN
		-- Set transaction type id to Player Stake Cancelled
		SET paymentTransactionTypeId = 247;
	ELSE
		-- Set transaction type id to Operator Stake Cancelled
		SET paymentTransactionTypeId = 20;
	END IF;
    
	#REVIEW
    UPDATE gaming_game_plays 
    #STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (game_play_id) ON gaming_game_plays.game_play_id = gaming_game_plays_sb.game_play_id
	SET
	  gaming_game_plays.payment_transaction_type_id = paymentTransactionTypeId
	  #gaming_game_plays_sb.payment_transaction_type_id = paymentTransactionTypeId,
	WHERE gaming_game_plays.game_play_id = gamePlayIDReturned;

    UPDATE gaming_sb_bets
    SET 
		bet_total = bet_total + IFNULL(betAmount, 0),
		amount_real = amount_real - betReal,
        amount_bonus = amount_bonus - betBonus,
        amount_bonus_win_locked = amount_bonus_win_locked - betBonusWinLocked,
        amount_free_bet = amount_free_bet - betFreeBet
    WHERE sb_bet_id = sbBetID;


	SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayIDReturned;
	CALL PlayReturnDataWithoutGame(gamePlayIDReturned, gameRoundID, clientStatID, gameManufacturerID, minimalData);
	CALL PlayReturnBonusInfoOnWin(gamePlayIDReturned);
    
    -- REVIEW
    #DELETE    FROM gaming_sb_bets_bonuses    WHERE sb_bet_id = sbBetID;

END root$$

DELIMITER ;

