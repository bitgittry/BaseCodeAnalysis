DROP procedure IF EXISTS `LottoSportsBookPlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LottoSportsBookPlaceBet`(
  couponID BIGINT, minimalData TINYINT(1), OUT statusCode INT)
BEGIN

	DECLARE playWagerType VARCHAR(80) DEFAULT 'Type1';
    DECLARE sbBetID,singleMultTypeID,gameManufacturerID,gamePlayID BIGINT DEFAULT 0;
    
    SET statusCode = 0;

	SELECT gs1.value_string as vs1
	INTO playWagerType
	FROM gaming_settings gs1
	WHERE gs1.name='PLAY_WAGER_TYPE';
    
	SELECT gaming_sb_bets.sb_bet_id
    INTO sbBetID
    FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_sb_bets ON gaming_sb_bets.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID 
    ORDER BY is_processed LIMIT 1; 

	SELECT sb_multiple_type_id INTO singleMultTypeID FROM gaming_sb_multiple_types WHERE name='Single' AND game_manufacturer_id=gameManufacturerID; 

	UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id)
	STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (sb_bet_entry_id) ON 
		gaming_sb_bet_singles.sb_bet_id=sbBetID AND
		gaming_game_plays_sb.sb_bet_entry_id=gaming_sb_bet_singles.sb_bet_single_id AND gaming_game_plays_sb.sb_multiple_type_id=singleMultTypeID
	SET gaming_game_plays_sb.confirmation_status=2, gaming_sb_bet_singles.processing_status=2 ;
    
	UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
	STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (sb_bet_entry_id) ON 
		gaming_sb_bet_multiples.sb_bet_id=sbBetID AND
		gaming_game_plays_sb.sb_bet_entry_id=gaming_sb_bet_multiples.sb_bet_multiple_id AND gaming_game_plays_sb.sb_multiple_type_id!=singleMultTypeID
	SET gaming_game_plays_sb.confirmation_status=2, gaming_sb_bet_multiples.processing_status = 2;
    
	IF (playWagerType = 'Type1') THEN
		CALL CommonWalletSportsGenericPlaceBet(sbBetID, minimalData, statusCode);
    ELSE
		CALL CommonWalletSportsGenericPlaceBetTypeTwo(sbBetID, minimalData, statusCode);
    END IF;
    
    UPDATE gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
    SET gaming_lottery_participations.lottery_wager_status_id = 5, gaming_lottery_participations.lottery_participation_status_id = 2101
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;

	UPDATE gaming_lottery_coupons
	SET lottery_wager_status_id = 5, lottery_coupon_status_id = 2102
	WHERE lottery_coupon_id = couponID;	 
	
END$$

DELIMITER ;

