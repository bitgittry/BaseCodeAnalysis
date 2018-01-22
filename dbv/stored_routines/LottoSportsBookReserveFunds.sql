DROP procedure IF EXISTS `LottoSportsBookReserveFunds`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LottoSportsBookReserveFunds`(
  couponID BIGINT, sessionID BIGINT, canCommit TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root:BEGIN
	
	DECLARE playWagerType VARCHAR(80) DEFAULT 'Type1';
    DECLARE sbBetID, clientStatID, wagerGamePlayID BIGINT DEFAULT -1;
    DECLARE verifySessionPlayer TINYINT(1) DEFAULT 0;
    DECLARE betTotal, betTotalIndividual DECIMAL (18,5) DEFAULT 0;

    SET statusCode = 0; 

	SELECT gs1.value_string as vs1
	INTO playWagerType
	FROM gaming_settings gs1
	WHERE gs1.name='PLAY_WAGER_TYPE';
 
    -- gaming_sb_bets.wager_game_play_id
	SELECT gaming_sb_bets.client_stat_id, gaming_sb_bets.sb_bet_id, gaming_sb_bets.bet_total, gaming_sb_bets.wager_game_play_id
	INTO clientStatID, sbBetID, betTotal, wagerGamePlayID
	FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
	STRAIGHT_JOIN gaming_sb_bets ON 
		gaming_sb_bets.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
	WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID 
    ORDER BY is_processed LIMIT 1; 

    SELECT 1
    INTO verifySessionPlayer
    FROM sessions_main FORCE INDEX (PRIMARY)
    WHERE session_id = sessionID AND extra2_id = clientStatID;
    
    IF (verifySessionPlayer = 0) THEN
		SET statusCode = 7;
		LEAVE root;
    END IF;   
    
  IF (IFNULL(wagerGamePlayID,-1) = -1) THEN
  
	SELECT IFNULL(singleTotalTable.singleTotal,0) + IFNULL(multipleTotalTable.multipleTotal,0)
    INTO betTotalIndividual
    FROM
    (
		SELECT SUM(IFNULL(bet_amount,0)) AS singleTotal 
        FROM gaming_sb_bets
		STRAIGHT_JOIN gaming_sb_bet_singles ON gaming_sb_bet_singles.sb_bet_id = gaming_sb_bets.sb_bet_id
		WHERE gaming_sb_bets.sb_bet_id = sbBetID
    ) AS singleTotalTable
    JOIN
    (
		SELECT SUM(IFNULL(bet_amount,0)) AS multipleTotal 
        FROM gaming_sb_bets
		STRAIGHT_JOIN gaming_sb_bet_multiples ON gaming_sb_bet_multiples.sb_bet_id = gaming_sb_bets.sb_bet_id
		WHERE gaming_sb_bets.sb_bet_id = sbBetID
    ) AS multipleTotalTable ON 1=1;
    
    UPDATE gaming_sb_bets
	STRAIGHT_JOIN gaming_sb_bet_singles ON gaming_sb_bets.sb_bet_id = gaming_sb_bet_singles.sb_bet_id
	STRAIGHT_JOIN gaming_sb_selections ON gaming_sb_selections.sb_selection_id = gaming_sb_bet_singles.sb_selection_id
	STRAIGHT_JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id =  gaming_sb_markets.sb_market_id
	STRAIGHT_JOIN gaming_sb_groups ON gaming_sb_groups.sb_group_id = gaming_sb_selections.sb_group_id
	SET 
		gaming_sb_bet_singles.ext_market_id = gaming_sb_markets.ext_market_id,
		gaming_sb_bet_singles.ext_group_id = gaming_sb_groups.ext_group_id
		-- gaming_sb_bet_singles.sb_selection_id = gaming_sb_selections.sb_selection_id -- filled in CreateBetSlip
	WHERE gaming_sb_bets.sb_bet_id = sbBetID;

	UPDATE gaming_sb_bets
	STRAIGHT_JOIN gaming_sb_bet_multiples ON gaming_sb_bet_multiples.sb_bet_id = gaming_sb_bets.sb_bet_id
	STRAIGHT_JOIN gaming_sb_bet_multiples_singles ON gaming_sb_bet_multiples.sb_bet_multiple_id = gaming_sb_bet_multiples_singles.sb_bet_multiple_id
	STRAIGHT_JOIN gaming_sb_selections ON gaming_sb_selections.sb_selection_id = gaming_sb_bet_multiples_singles.sb_selection_id
	STRAIGHT_JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id =  gaming_sb_markets.sb_market_id
	STRAIGHT_JOIN gaming_sb_groups ON gaming_sb_selections.sb_group_id = gaming_sb_groups.sb_group_id
	SET 
		gaming_sb_bet_multiples_singles.ext_market_id = gaming_sb_markets.ext_market_id,
		gaming_sb_bet_multiples_singles.ext_group_id = gaming_sb_groups.ext_group_id
		-- gaming_sb_bet_multiples_singles.sb_selection_id = gaming_sb_selections.sb_selection_id -- filled in CreateBetSlip
	WHERE gaming_sb_bets.sb_bet_id = sbBetID;

	IF (betTotal  != betTotalIndividual) THEN
		SET statusCode = 25;
		LEAVE root;
    END IF;

  END IF;

    IF (playWagerType = 'Type1') THEN
		CALL CommonWalletSportsGenericGetFunds(sbBetID, clientStatID, canCommit, minimalData, statusCode);
    ELSE
		CALL CommonWalletSportsGenericGetFundsTypeTwo(sbBetID, clientStatID, canCommit, minimalData, statusCode);
    END IF;
    
    UPDATE gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON 
		gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
    SET gaming_lottery_participations.lottery_wager_status_id = 3
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;

	UPDATE gaming_sb_bets  
	STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.game_play_id = gaming_sb_bets.wager_game_play_id
	STRAIGHT_JOIN gaming_lottery_coupons ON gaming_lottery_coupons.lottery_coupon_id = couponID
	SET gaming_game_plays.platform_type_id = gaming_lottery_coupons.platform_type_id
    WHERE gaming_sb_bets.sb_bet_id=sbBetID;
	  
	UPDATE gaming_lottery_coupons
	SET lottery_wager_status_id = 3
	WHERE lottery_coupon_id = couponID;	

    -- reset processed state
    UPDATE gaming_sb_bets
    SET is_processed = 0
    WHERE sb_bet_id = sbBetID;
	
	-- INBUGCL-352
    DELETE FROM gaming_sb_bet_wins
    WHERE sb_bet_id = sbBetID;

END$$

DELIMITER ;

