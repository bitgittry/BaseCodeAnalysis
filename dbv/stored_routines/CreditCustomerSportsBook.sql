DROP procedure IF EXISTS `CreditCustomerSportsBook`;
DROP procedure IF EXISTS `LottoSportsBookCreditCustomer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LottoSportsBookCreditCustomer`(sportsBookParticipationID BIGINT, transactionRef VARCHAR(100), OUT statusCode INT)
root: BEGIN

	DECLARE playWagerType VARCHAR(80) DEFAULT 'Type1';
    DECLARE sbBetID, singleMultTypeID, gameManufacturerID BIGINT DEFAULT 0;
	DECLARE betTransactionRef VARCHAR(64) DEFAULT NULL;
    DECLARE betRef VARCHAR(40) DEFAULT NULL;
    DECLARE isProcessed,winNotification, lossNotification  TINYINT(1) DEFAULT 0;
	DECLARE sbBetStatusCode, numSingles, numMultiples, numBetEntries INT DEFAULT 0;
    DECLARE winAmount DECIMAL (18,5) DEFAULT 0;
	DECLARE gamePlayIDReturned BIGINT DEFAULT NULL;
    
    SET statusCode = 0; 

	SELECT gs1.value_string as vs1
	INTO playWagerType
	FROM gaming_settings gs1
	WHERE gs1.name='PLAY_WAGER_TYPE';

	SELECT gaming_sb_bets.sb_bet_id, gaming_sb_bets.game_manufacturer_id, gaming_sb_bets.transaction_ref, 
		gaming_sb_bets.is_processed, gaming_sb_bets.status_code, gaming_sb_bets.num_singles, gaming_sb_bets.num_multiplies, 
         IFNULL(gaming_lottery_coupons.win_notification,0), IFNULL(gaming_lottery_coupons.loss_notification,0)
    INTO sbBetID, gameManufacturerID, betTransactionRef, isProcessed, sbBetStatusCode, numSingles, numMultiples,winNotification, lossNotification
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
		gaming_lottery_coupons.lottery_coupon_status_id = 2107, -- PAID
		gaming_lottery_participations.lottery_wager_status_id = 6, -- WinReceived
		gaming_lottery_participations.lottery_participation_status_id = 2105 -- PAID
	WHERE gaming_lottery_participations.lottery_participation_id = sportsBookParticipationID;

	SET @total_net = 0.0;
	SET @total_refund = 0.0;
	SELECT SUM(IFNULL(net, 0)), SUM(IFNULL(refund, 0)) INTO @total_net, @total_refund 
    FROM gaming_lottery_participation_prizes 
	WHERE lottery_participation_id = sportsBookParticipationID AND prize_status = 5 AND approval_status_id = 2104;

	SET winAmount = IF(@total_net > 0, @total_net, @total_refund);

	IF (numBetEntries=1) THEN
		SET betRef=NULL;
	ELSEIF (numBetEntries>1 AND numMultiples=1) THEN
		SELECT bet_ref INTO betRef FROM gaming_sb_bet_multiples FORCE INDEX (sb_bet_id) WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID LIMIT 1;
	ELSE
		SELECT bet_ref INTO betRef FROM gaming_sb_bet_singles FORCE INDEX (sb_bet_id) WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID LIMIT 1;
    END IF;

    -- the win will have the same transaction ref of the bet
	-- type 1 or tyoe 2 is handled in the sp 
    
	CALL CommonWalletSportsGenericCreditCustomerByBetRef(gameManufacturerID, transactionRef, betTransactionRef, betRef, winAmount, 1, 0, 0, gamePlayIDReturned, statusCode);
	
	-- CPREQ-216 
    IF( IFNULL(winAmount,0) > 0 AND winNotification = 1) THEN 
		CALL PlaceClientNotificationInstance(sbBetID, 'SBWin');
    ELSEIF(lossNotification = 1) THEN
        CALL PlaceClientNotificationInstance(sbBetID, 'SBLoss');
    END IF;

END root$$

DELIMITER ;

