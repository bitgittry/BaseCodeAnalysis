DROP procedure IF EXISTS `CancelDrawParticipationsLotto`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CancelDrawParticipationsLotto`(gameManufacturerID BIGINT, gameStateIdf INT, drawNumber INT, OUT statusCode INT)
root: BEGIN

	DECLARE licenseTypeID, participationsCountToCancel, roundsCountToInsert INT DEFAULT 0;
    DECLARE newGamePlayID, gamePlayMessageTypeId, paymentTransactionTypeId, lotteryDrawID BIGINT DEFAULT 0;
    
	SET statusCode = 0;
    
    DROP TABLE IF EXISTS participationsToCancel;
	DROP TABLE IF EXISTS gamePlaysToCancel;
    DROP TABLE IF EXISTS existingGameRounds;
    
	SELECT license_type_id INTO licenseTypeID
	FROM gaming_license_type WHERE `name` = 'lotto';

	SELECT game_play_message_type_id INTO gamePlayMessageTypeId
	FROM gaming_game_play_message_types WHERE `name` = 'ReturnCancelled';
    
    SELECT payment_transaction_type_id INTO paymentTransactionTypeId
	FROM gaming_payment_transaction_type WHERE `name` = 'ReturnCancelled';
    
    SELECT gld.lottery_draw_id INTO lotteryDrawID
    FROM gaming_lottery_draws gld
    JOIN gaming_games gg ON gg.game_id = gld.game_id
    WHERE gld.game_manufacturer_id=gameManufacturerID
		AND gld.draw_number=drawNumber AND gg.manufacturer_game_idf=gameStateIdf;

	-- Get the Player channel
  	CALL PlatformTypesGetPlatformsByPlatformType(NULL, NULL, @platformTypeID, @platformType, @channelTypeID, @channelType);
    
	-- select all participations to cancel
    CREATE TEMPORARY TABLE IF NOT EXISTS participationsToCancel 
    (UNIQUE participationsToCancel_Unique (lottery_participation_id))
    (
    SELECT lottery_participation_id
	 FROM gaming_lottery_participations
	 WHERE lottery_draw_id=lotteryDrawID
		AND lottery_participation_status_id IN (2106)); -- get only not winnning

	SELECT COUNT(*) INTO participationsCountToCancel
    FROM participationsToCancel;
    
    -- if there are no participation to cancel leave
    IF(IFNULL(participationsCountToCancel,0) = 0) THEN
		SET statusCode = 1;
		LEAVE root;
    END IF;

	-- get round ids - cannot be used in the where close below
    CREATE TEMPORARY TABLE IF NOT EXISTS existingGameRounds 
    (UNIQUE existingGameRounds_Unique (game_round_id))
    (
	   SELECT gg.game_round_id AS `game_round_id`
		 FROM gaming_game_rounds gg FORCE INDEX (sb_extra_id)
         JOIN participationsToCancel part FORCE INDEX (participationsToCancel_Unique) 
			ON part.lottery_participation_id = gg.game_round_id
		WHERE gg.license_type_id = licenseTypeID
	);

	-- reopen the rounds
    UPDATE gaming_game_rounds ggr FORCE INDEX (PRIMARY)
    JOIN existingGameRounds egg FORCE INDEX (existingGameRounds_Unique) ON egg.game_round_id = ggr.game_round_id
    SET ggr.date_time_end= NULL, 
		ggr.is_round_finished=0, 
        ggr.num_transactions=ggr.num_transactions+1;


	-- delete the prizes
    DELETE glpr FROM gaming_lottery_participation_prizes glpr FORCE INDEX (lottery_participation_id)
    JOIN participationsToCancel epar FORCE INDEX (participationsToCancel_Unique) ON glpr.lottery_participation_id = epar.lottery_participation_id;

	-- select all game rounds, game plays, coupons to be used later
    CREATE TEMPORARY TABLE IF NOT EXISTS gamePlaysToCancel 
    (INDEX gamePlaysToCancel_ClientStat (client_stat_id),INDEX gamePlaysToCancel_GameRound (game_round_id),INDEX gamePlaysToCancel_CouponID (lottery_coupon_id))
    (
		SELECT ggple.game_play_id AS `game_play_id`, ggp.game_round_id AS `game_round_id`, ggp.client_stat_id AS `client_stat_id`, ggpl.lottery_coupon_id AS `lottery_coupon_id`, 
			gld.game_id AS `game_id`, gld.game_manufacturer_id AS `game_manufacturer_id`, gog.operator_game_id AS `operator_game_id`, 
			num_transactions, ggp.platform_type_id AS `platform_type_id`, gld.lottery_draw_id AS `lottery_draw_id`,ggple.game_play_lottery_entry_id AS `game_play_lottery_entry_id`,
            ggp.session_id AS `session_id`, glp.lottery_participation_id AS `lottery_participation_id`
		FROM gaming_game_plays_lottery_entries ggple  FORCE INDEX (lottery_participation_id)
		STRAIGHT_JOIN gaming_lottery_participations glp FORCE INDEX (PRIMARY) ON glp.lottery_participation_id = ggple.lottery_participation_id 
		STRAIGHT_JOIN gaming_game_plays ggp FORCE INDEX (PRIMARY) ON ggp.game_play_id = ggple.game_play_id
		STRAIGHT_JOIN gaming_game_plays_lottery ggpl FORCE INDEX (PRIMARY) ON ggp.game_play_id = ggpl.game_play_id
		STRAIGHT_JOIN gaming_lottery_draws gld ON gld.lottery_draw_id = ggple.lottery_draw_id
		STRAIGHT_JOIN gaming_operator_games gog ON gog.game_id = gld.game_id
		STRAIGHT_JOIN gaming_operators go ON go.operator_id = gog.operator_id AND go.is_main_operator = 1
		STRAIGHT_JOIN gaming_game_rounds ggr FORCE INDEX (PRIMARY) ON ggr.game_round_id = ggp.game_round_id
		WHERE ggple.lottery_participation_id IN ( SELECT lottery_participation_id FROM participationsToCancel));
	     
	-- get count or rounds
    SELECT COUNT(*) INTO roundsCountToInsert FROM gamePlaysToCancel;
    
    -- create new transactions in game plays to represend the cancel
    INSERT INTO gaming_game_plays 
		(
			amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, bonus_lost, bonus_win_locked_lost, 
			jackpot_contribution, TIMESTAMP, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_round_id, 
			payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, 
			round_transaction_no, game_play_message_type_id, license_type_id, pending_bet_real, pending_bet_bonus, bet_from_real, platform_type_id,
			loyalty_points,loyalty_points_after,loyalty_points_bonus, loyalty_points_after_bonus, sb_bet_id, sb_extra_id, pending_winning_real
		)
	SELECT
		0, 0, 0, 0, 0, 0, 0, 0, 0, NOW(), gpc.game_id, gpc.game_manufacturer_id, gpc.operator_game_id, gcs.client_id, gcs.client_stat_id, 
			gpc.session_id, gpc.game_round_id, paymentTransactionTypeId, 0, current_real_balance, 
			ROUND(current_bonus_balance+current_bonus_win_locked_balance,0), current_bonus_win_locked_balance, gcs.currency_id, gpc.num_transactions+1, gamePlayMessageTypeId, licenseTypeID,
			pending_bets_real, pending_bets_bonus, 0, @platformTypeID,0,gcs.current_loyalty_points,0,
			(gcs.`total_loyalty_points_given_bonus` - gcs.`total_loyalty_points_used_bonus`), gpc.lottery_coupon_id, gpc.lottery_participation_id, 
		0
	FROM gamePlaysToCancel gpc FORCE INDEX (gamePlaysToCancel_ClientStat)
	JOIN gaming_client_stats gcs FORCE INDEX(PRIMARY) ON gpc.client_stat_id = gcs.client_stat_id;

	-- this must be the first in the batch
	SET newGamePlayID = LAST_INSERT_ID() - roundsCountToInsert;
    
    -- add the new transactions in lottery entries
	INSERT INTO gaming_game_plays_lottery_entries (game_play_id,lottery_draw_id, lottery_participation_id, amount_total, amount_real, amount_bonus, amount_bonus_win_locked, amount_ring_fenced, amount_free_bet, loyalty_points, loyalty_points_bonus,lottery_participation_prize_id)
	SELECT ggp.game_play_id, lotteryDrawID, ggp.sb_extra_id, ggp.amount_total, ggp.amount_real, ggp.amount_bonus, ggp.amount_bonus_win_locked, ggp.amount_ring_fenced, ggp.amount_free_bet, ggp.loyalty_points, ggp.loyalty_points_bonus, NULL
	FROM gaming_game_plays ggp
	WHERE game_play_id > newGamePlayID AND payment_transaction_type_id = paymentTransactionTypeId;

	-- reopen old game plays
	UPDATE gaming_game_plays ggp FORCE INDEX (game_round_id) 
    JOIN gamePlaysToCancel gptc FORCE INDEX(gamePlaysToCancel_GameRound) ON ggp.game_round_id = gptc.game_round_id
    SET is_win_placed=0 ;

	-- Update participation status
	UPDATE gaming_lottery_participations glp FORCE INDEX (PRIMARY)
    JOIN participationsToCancel part FORCE INDEX (participationsToCancel_Unique) ON glp.lottery_participation_id = part.lottery_participation_id
	SET glp.lottery_wager_status_id = 5, -- BetPlaced
		glp.lottery_participation_status_id = 2101; -- PLAYED
	
	-- update coupon wager status and status
	UPDATE gaming_lottery_coupons glc FORCE INDEX (PRIMARY)
	JOIN gamePlaysToCancel gc FORCE INDEX (gamePlaysToCancel_CouponID) ON gc.lottery_coupon_id = glc.lottery_coupon_id 
    SET glc.lottery_wager_status_id = 5, -- BetPlaced
		glc.lottery_coupon_status_id = PropagateCouponStatusFromParticipations(glc.lottery_coupon_id, glc.lottery_coupon_status_id, 2);

	DROP TABLE participationsToCancel;
	DROP TABLE gamePlaysToCancel;
    DROP TABLE existingGameRounds;
END$$

DELIMITER ;

