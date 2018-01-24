DROP procedure IF EXISTS `LottoSportsBookCreditCustomer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LottoSportsBookCreditCustomer`(
  sportsBookParticipationID BIGINT, transactionRef VARCHAR(100), extBetRef VARCHAR(40), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN

	-- extBetRef is always null for IFLEX and is always with a value in AMELCO

	DECLARE playWagerType VARCHAR(80) DEFAULT 'Type1';
    DECLARE sbBetID, singleMultTypeID, gameManufacturerID, clientStatID, lotteryCouponId BIGINT DEFAULT 0;
	DECLARE betTransactionRef VARCHAR(64) DEFAULT NULL;
    -- DECLARE extBetRef VARCHAR(40) DEFAULT NULL;
    
    DECLARE isProcessed,winNotification, lossNotification, taxEnabled, calucatedByProvider, verticalVersion, skipStatusUpdate TINYINT(1) DEFAULT 0;
	DECLARE sbBetStatusCode, numSingles, numMultiples, numBetEntries, existingWins INT DEFAULT 0;
    DECLARE winAmount, taxAmount DECIMAL (18,5) DEFAULT 0;
	DECLARE gamePlayIDReturned BIGINT DEFAULT NULL;
    
    SET statusCode = 0; 

	SELECT gs1.value_string as vs1
	INTO playWagerType
	FROM gaming_settings gs1
	WHERE gs1.name='PLAY_WAGER_TYPE';
    
	SELECT gaming_sb_bets.sb_bet_id, gaming_sb_bets.game_manufacturer_id, gaming_sb_bets.transaction_ref, 
		gaming_sb_bets.is_processed, gaming_sb_bets.status_code, gaming_sb_bets.num_singles, gaming_sb_bets.num_multiplies, 
         IFNULL(gaming_lottery_coupons.win_notification,0), IFNULL(gaming_lottery_coupons.loss_notification,0), 
		 gaming_sb_bets.client_stat_id, gaming_lottery_coupons.lottery_coupon_id, IFNULL(gaming_lottery_coupons.vertical_version,0)
    INTO sbBetID, gameManufacturerID, betTransactionRef, isProcessed, sbBetStatusCode, numSingles, numMultiples,winNotification, lossNotification,
		 clientStatID, lotteryCouponId, verticalVersion
    FROM gaming_lottery_participations FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id=gaming_lottery_participations.lottery_dbg_ticket_id
	STRAIGHT_JOIN gaming_lottery_coupons ON gaming_lottery_coupons.lottery_coupon_id = gaming_lottery_dbg_tickets.lottery_coupon_id
    STRAIGHT_JOIN gaming_sb_bets FORCE INDEX (lottery_dbg_ticket_id) ON gaming_sb_bets.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
    WHERE gaming_lottery_participations.lottery_participation_id = sportsBookParticipationID;

	SET numBetEntries = numSingles+numMultiples;


	IF (sbBetStatusCode != 5 OR isProcessed=0 OR numBetEntries=0) THEN 
		SET statusCode=3;
		LEAVE root;
	END IF;	
    

  	-- UPDATE COUPON STATUS AND PARTICIPATION STATUS
	UPDATE gaming_lottery_participations FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
	STRAIGHT_JOIN gaming_lottery_coupons ON gaming_lottery_coupons.lottery_coupon_id = gaming_lottery_dbg_tickets.lottery_coupon_id 
	SET 
		gaming_lottery_coupons.lottery_wager_status_id = 6, -- WinReceived
		gaming_lottery_participations.lottery_wager_status_id = 6 -- WinReceived
	WHERE gaming_lottery_participations.lottery_participation_id = sportsBookParticipationID;


	SET @total_net = 0.0;
	SET @total_refund = 0.0;
    SET @total_gross = 0.0;
    

	SELECT SUM(IFNULL(net, 0)), SUM(IFNULL(refund, 0)), SUM(IFNULL(gross, 0)) INTO @total_net, @total_refund, @total_gross
    FROM gaming_lottery_participation_prizes 
	WHERE lottery_participation_id = sportsBookParticipationID AND prize_status = 5 AND approval_status_id = 2104
    AND IFNULL(bet_ref,'')= CASE WHEN extBetRef IS NULL THEN IFNULL(bet_ref,'') ELSE extBetRef END;


	SET winAmount = IF(@total_net > 0, @total_net, @total_refund);


  IF (extBetRef is NULL) THEN
  	IF (numBetEntries=1) THEN
  		SET extBetRef=NULL;
  	ELSEIF (numBetEntries>1 AND numMultiples=1) THEN
  		  SELECT bet_ref INTO extBetRef FROM gaming_sb_bet_multiples FORCE INDEX (sb_bet_id) WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID LIMIT 1;
    ELSE
  		SELECT bet_ref INTO extBetRef FROM gaming_sb_bet_singles FORCE INDEX (sb_bet_id) WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID LIMIT 1;
    END IF;
  END IF;	
  
  -- in Amelco winnings can be incremental, so they are considered adjustments only if a previous win exists with the same betRef
   SELECT COUNT(sb_bet_win_id) 
    INTO existingWins FROM gaming_sb_bet_wins where sb_bet_id = sbBetID AND transaction_ref=extBetRef;
  
    -- the win will have the same transaction ref of the bet
	-- type 1 or tyoe 2 is handled in the sp 

	  CALL CommonWalletSportsGenericCreditCustomerByBetRef(gameManufacturerID, 
        transactionRef, betTransactionRef, extBetRef, winAmount, 1, 0, 0, minimalData, gamePlayIDReturned, statusCode);

   -- for AMELCO the awarding of the winnings can be incremental, so the status is changed only if all the outcomes of the bet are received.
  IF ((verticalVersion=1) AND
    (SELECT COUNT(sb_bet_id) FROM gaming_sb_bet_wins where sb_bet_id=sbBetID)
        < (SELECT COUNT(sb_bet_id) FROM gaming_game_rounds where sb_bet_id=sbBetID AND sb_extra_id is not null))
    THEN
     SET skipStatusUpdate=1;
     END IF;

  -- in Amelco winnings can be incremental, so they are considered adjustments only if a previous win exists with the same betRef
  IF ((verticalVersion=1) AND (existingWins=0))
  THEN
    UPDATE gaming_game_plays SET payment_transaction_type_id=13 where game_play_id= gamePlayIDReturned;
    UPDATE gaming_game_plays_sb SET payment_transaction_type_id=13 where game_play_id= gamePlayIDReturned;
  END IF;
    
  -- UPDATE COUPON STATUS AND PARTICIPATION STATUS
	UPDATE gaming_lottery_participations FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
	STRAIGHT_JOIN gaming_lottery_coupons ON gaming_lottery_coupons.lottery_coupon_id = gaming_lottery_dbg_tickets.lottery_coupon_id 
	SET 
		gaming_lottery_coupons.lottery_coupon_status_id = CASE WHEN skipStatusUpdate=1 THEN gaming_lottery_coupons.lottery_coupon_status_id ELSE 2111 END, -- CLOSED
		gaming_lottery_participations.lottery_participation_status_id = CASE WHEN skipStatusUpdate=1 THEN gaming_lottery_participations.lottery_participation_status_id ELSE 2111 END -- CLOSED
	WHERE gaming_lottery_participations.lottery_participation_id = sportsBookParticipationID;
  
  
  
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
        SET taxAmount = @total_gross - @total_net;
		
        UPDATE gaming_game_plays
        INNER JOIN gaming_game_rounds ON gaming_game_plays.game_round_id = gaming_game_rounds.game_round_id
		INNER JOIN gaming_game_plays_sb ON gaming_game_plays_sb.game_round_id = gaming_game_rounds.game_round_id AND gaming_game_plays_sb.game_play_id = gaming_game_plays.game_play_id
        SET gaming_game_plays.amount_tax_player = taxAmount,
			gaming_game_rounds.amount_tax_player = taxAmount,
			gaming_game_plays_sb.amount_tax_player = taxAmount,
			gaming_game_rounds.amount_tax_player_original = IFNULL(gaming_game_rounds.amount_tax_player_original, taxAmount)
        WHERE gaming_game_plays.game_play_id = gamePlayIDReturned;
        
    END IF;
	
	-- CPREQ-216 
    IF( IFNULL(winAmount,0) > 0 AND winNotification = 1) THEN 
		CALL PlaceClientNotificationInstance(sbBetID, 'SBWin');
    ELSEIF(lossNotification = 1) THEN
        CALL PlaceClientNotificationInstance(sbBetID, 'SBLoss');
    END IF;

END root$$

DELIMITER ;

