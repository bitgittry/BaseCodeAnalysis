DROP procedure IF EXISTS `LottoSportsBookReturnFunds`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LottoSportsBookReturnFunds`(lotteryCouponID BIGINT, minimalData TINYINT(1), OUT statusCode INT)
BEGIN

	DECLARE playWagerType VARCHAR(80) DEFAULT 'Type1'; 
    DECLARE sbBetID BIGINT DEFAULT 0;

	SET statusCode = 0;
    
	SELECT gaming_sb_bets.sb_bet_id
    INTO sbBetID
    FROM gaming_lottery_coupons
    STRAIGHT_JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
    STRAIGHT_JOIN gaming_sb_bets ON gaming_sb_bets.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
    WHERE gaming_lottery_coupons.lottery_coupon_id = lotteryCouponID;

	SELECT gs1.value_string as vs1
	INTO playWagerType
	FROM gaming_settings gs1
	WHERE gs1.name='PLAY_WAGER_TYPE';

	UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
	SET processing_status=1 
	WHERE sb_bet_id=sbBetID AND processing_status=0;
    
	UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id) 
	SET processing_status=1 
	WHERE sb_bet_id=sbBetID AND processing_status=0;
    
	IF (playWagerType = 'Type1') THEN
		CALL CommonWalletSportsGenericReturnFunds(sbBetID, 1, 0, minimalData, statusCode);
    ELSE
		CALL CommonWalletSportsGenericReturnFundsTypeTwo(sbBetID, 1, 0, minimalData, statusCode);
    END IF;
     
    UPDATE gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
    SET gaming_lottery_participations.lottery_wager_status_id = 4,
		gaming_lottery_participations.lottery_participation_status_id = 2103    
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = lotteryCouponID;

	UPDATE gaming_lottery_coupons
	SET lottery_wager_status_id = 4, lottery_coupon_status_id = 2104
	WHERE lottery_coupon_id = lotteryCouponID;	  
	
END$$

DELIMITER ;

