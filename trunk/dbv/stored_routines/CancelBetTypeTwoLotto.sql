DROP procedure IF EXISTS `CancelBetTypeTwoLotto`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CancelBetTypeTwoLotto`(
  couponID BIGINT, gamePlayID BIGINT, sessionID BIGINT, cancelReason VARCHAR(255), OUT statusCode INT)
root:BEGIN

	DECLARE tempGamePlayID, gameRoundID, gameManufacturerID, newGamePlayID, clientStatID, clientID, 
			cancelledGamePlayID, cancelledGameRoundID, platformTypeID, currencyID BIGINT;
	DECLARE betAmount,exchangeRate, betReal, betBonus, betBonusWinLocked, totalLoyaltyPoints, 
			totalLoyaltyPointsBonus, cancelBonus, cancelBonusWinLocked,
			convertedToRealBonus, convertedToRealBWL, releasedLockedFunds DECIMAL(18,5);
    DECLARE topBonusApplicable,wagerStatusCode, errorCode, numParticipations INT DEFAULT 0;
	DECLARE playLimitEnabled, bonusEnabledFlag, ringFencedEnabled TINYINT(1) DEFAULT 0;
	DECLARE currentVipType VARCHAR(100) DEFAULT '';
	DECLARE licenseType VARCHAR(40);
	DECLARE licenseTypeID, clientWagerTypeID INT DEFAULT -1;

	SET statusCode = 0;

	SELECT client_stat_id, game_manufacturer_id, lottery_wager_status_id, error_code, gaming_lottery_coupons.license_type_id, 
		gaming_license_type.`name`, gaming_client_wager_types.client_wager_type_id  
	INTO clientStatID, gameManufacturerID, wagerStatusCode, errorCode, licenseTypeID, licenseType, clientWagerTypeID
	FROM gaming_lottery_coupons 
	STRAIGHT_JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_lottery_coupons.license_type_id
	STRAIGHT_JOIN gaming_client_wager_types ON gaming_client_wager_types.license_type_id = gaming_license_type.license_type_id
	WHERE lottery_coupon_id=couponID;
    
	-- Lock
	SELECT client_id, currency_id INTO clientID, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;

	IF (gamePlayID = 0) THEN 
    
		SELECT MAX(gaming_game_plays_lottery.game_play_id), gaming_game_rounds.game_round_id, gaming_game_plays.client_stat_id, amount_real, platform_type_id, amount_bonus, 
			amount_bonus_win_locked, gaming_game_plays.loyalty_points, gaming_game_plays.loyalty_points_bonus, gaming_game_plays.game_manufacturer_id, 
			gaming_game_plays.released_locked_funds
		INTO tempGamePlayID, gameRoundID, clientStatID, betReal, platformTypeID, betBonus, betBonusWinLocked, totalLoyaltyPoints, totalLoyaltyPointsBonus, gameManufacturerID, releasedLockedFunds
		FROM gaming_game_plays_lottery FORCE INDEX (lottery_coupon_id)
		STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery.game_play_id
        STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (PRIMARY) ON  gaming_game_rounds.game_round_id = gaming_game_plays.game_round_id
		WHERE gaming_game_plays_lottery.lottery_coupon_id = couponID AND payment_transaction_type_id = 12;
        
        SELECT MAX(gaming_game_plays_lottery.game_play_id), gaming_game_rounds.game_round_id
		INTO cancelledGamePlayID, cancelledGameRoundID
		FROM gaming_game_plays_lottery FORCE INDEX (lottery_coupon_id)
		STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery.game_play_id
        STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (PRIMARY) ON  gaming_game_rounds.game_round_id = gaming_game_plays.game_round_id
		WHERE gaming_game_plays_lottery.lottery_coupon_id = couponID AND payment_transaction_type_id = 20;
        
		SET gamePlayID = tempGamePlayID;
    
    ELSE
    
		SELECT 	game_round_id, client_stat_id, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, loyalty_points_bonus, 
				game_manufacturer_id, platform_type_id, gaming_game_plays.released_locked_funds
        INTO gameRoundID, clientStatID, betReal, betBonus, betBonusWinLocked, totalLoyaltyPoints, totalLoyaltyPointsBonus, 
			 gameManufacturerID, platformTypeID, releasedLockedFunds
        FROM gaming_game_plays
        WHERE game_play_id = gamePlayID;
    
    END IF;
	
	CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, @platformTypeID, @platformType, @channelTypeID, @channelType);

	-- If Wager Status Code is BetPlaced Skip Validation
    IF (wagerStatusCode != 5) THEN
		IF (wagerStatusCode = 8) THEN        
			CALL PlayReturnDataWithoutGame(cancelledGamePlayID, cancelledGameRoundID, clientStatID, gameManufacturerID, 0);
			CALL PlayReturnBonusInfoOnBet(cancelledGamePlayID);
			
			SET statusCode = 100;
			LEAVE root;
		ELSE     
			SET statusCode = 1;
			LEAVE root;
		END IF;
 	END IF;

	SELECT gaming_operator_currency.exchange_rate, gaming_vip_levels.set_type
	INTO exchangeRate, currentVipType
	FROM gaming_clients
	STRAIGHT_JOIN gaming_operator_currency ON gaming_operator_currency.currency_id = currencyID
	LEFT JOIN gaming_vip_levels ON gaming_vip_levels.vip_level_id = gaming_clients.vip_level_id 
	WHERE gaming_clients.client_id=clientID;

	SELECT COUNT(*),SUM(participation_cost) INTO numParticipations, betAmount
    FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_lottery_participations ON 
		gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND 
        gaming_lottery_participations.lottery_wager_status_id = 5 /*requires bet to be placed*/
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
    
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
    

	UPDATE gaming_game_rounds FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN gaming_client_stats FORCE INDEX (PRIMARY) ON 
		gaming_client_stats.client_stat_id=gaming_game_rounds.client_stat_id
	SET
	  gaming_game_rounds.bet_total = 0,
	  gaming_game_rounds.bet_total_base = 0,
	  gaming_game_rounds.bet_real = 0,
	  gaming_game_rounds.bet_bonus = 0,
	  gaming_game_rounds.bet_bonus_win_locked = 0,
	  gaming_game_rounds.bet_free_bet = 0,
	  gaming_game_rounds.date_time_end = NOW(),
	  gaming_game_rounds.is_round_finished = 1,
	  gaming_game_rounds.is_processed = 1,
	  gaming_game_rounds.balance_real_after = gaming_client_stats.current_real_balance  - betReal,
	  gaming_game_rounds.balance_bonus_after = gaming_client_stats.current_bonus_balance + gaming_client_stats.current_bonus_win_locked_balance  -  betBonus -  betBonusWinLocked,
	  gaming_game_rounds.num_bets = 0,
	  gaming_game_rounds.is_round_finished = 1,
	  gaming_game_rounds.num_transactions = 0,
	  gaming_game_rounds.is_cancelled = 1,
	  gaming_game_rounds.loyalty_points = 0,
	  gaming_game_rounds.loyalty_points_bonus = 0
	 WHERE game_round_id=gameRoundID;

	UPDATE gaming_game_rounds_lottery FORCE INDEX (parent_game_round_id)
	STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (PRIMARY) ON 
		gaming_game_rounds_lottery.game_round_id=gaming_game_rounds.game_round_id
    STRAIGHT_JOIN gaming_client_stats FORCE INDEX (PRIMARY) ON 
		gaming_game_rounds.client_stat_id = gaming_client_stats.client_stat_id
	SET
	  gaming_game_rounds.bet_total = 0,
	  gaming_game_rounds.bet_total_base = 0,
	  gaming_game_rounds.bet_real = 0,
	  gaming_game_rounds.bet_bonus = 0,
	  gaming_game_rounds.bet_bonus_win_locked = 0,
	  gaming_game_rounds.bet_free_bet = 0,
	  gaming_game_rounds.date_time_end = NOW(),
	  gaming_game_rounds.is_round_finished = 1,
	  gaming_game_rounds.is_processed = 1,
	  gaming_game_rounds.balance_real_after = gaming_client_stats.current_real_balance  - betReal,
	  gaming_game_rounds.balance_bonus_after = gaming_client_stats.current_bonus_balance + gaming_client_stats.current_bonus_win_locked_balance  -  betBonus -  betBonusWinLocked,
	  gaming_game_rounds.num_bets = 0,
	  gaming_game_rounds.is_round_finished = 1,
	  gaming_game_rounds.num_transactions = 0,
	  gaming_game_rounds.is_cancelled = 1,
	  gaming_game_rounds.loyalty_points = 0,
	  gaming_game_rounds.loyalty_points_bonus = 0
	 WHERE gaming_game_rounds_lottery.parent_game_round_id = gameRoundID;

	SELECT IFNULL(SUM(IF(gbi.is_lost /*OR gbi.is_secured*/ , ggpbi.bet_bonus, 0)), 0), IFNULL(SUM(IF(gbi.is_lost /*OR gbi.is_secured*/ , ggpbi.bet_bonus_win_locked, 0)), 0),
    IFNULL(SUM(IF(gbi.is_secured, ggpbi.bet_bonus, 0)), 0), IFNULL(SUM(IF(gbi.is_secured, ggpbi.bet_bonus_win_locked, 0)), 0)
	INTO cancelBonus, cancelBonusWinLocked, convertedToRealBonus, convertedToRealBWL
	FROM gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id=ggpbi.bonus_instance_id
	WHERE ggpbi.game_play_id=gamePlayID;
    
	INSERT INTO gaming_game_plays 
		(amount_total, game_round_id, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_free_bet, amount_other, bonus_lost, bonus_win_locked_lost, 
		timestamp, game_manufacturer_id, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, pending_bet_real, pending_bet_bonus, 
		 currency_id, sign_mult, license_type_id,loyalty_points, loyalty_points_bonus,loyalty_points_after, loyalty_points_after_bonus, sb_bet_id, game_play_message_type_id, is_cancelled, platform_type_id) 
	SELECT ggp.amount_total, ggp.game_round_id, ggp.amount_total/exchangeRate, exchangeRate, ggp.amount_real + convertedToRealBonus+ convertedToRealBWL, ggp.amount_bonus-cancelBonus - convertedToRealBonus, ggp.amount_bonus_win_locked-cancelBonusWinLocked - convertedToRealBWL, ggp.amount_free_bet, 0, cancelBonus, cancelBonusWinLocked, 
		NOW(), ggp.game_manufacturer_id, ggp.client_id, ggp.client_stat_id, 20, gcs.current_real_balance + ggp.amount_real, gcs.current_bonus_balance+gcs.current_bonus_win_locked_balance + ggp.amount_bonus + ggp.amount_bonus_win_locked, gcs.current_bonus_win_locked_balance + ggp.amount_bonus_win_locked, gcs.pending_bets_real, gcs.pending_bets_bonus, 
		gcs.currency_id, 1, ggp.license_type_id,-ggp.loyalty_points,-ggp.loyalty_points_bonus,gcs.current_loyalty_points-ggp.loyalty_points,IFNULL(gcs.total_loyalty_points_given_bonus - gcs.total_loyalty_points_used_bonus-ggp.loyalty_points_bonus,0), couponID, gaming_game_play_message_types.game_play_message_type_id, 1, @platformTypeID
	FROM gaming_game_plays AS ggp FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_client_stats AS gcs ON gcs.client_stat_id=clientStatID
	STRAIGHT_JOIN gaming_game_play_message_types ON gaming_game_play_message_types.`name`=CAST(CASE licenseTypeID WHEN 6 THEN 'LotteryBetCancelled' WHEN 7 THEN 'SportsPoolBetCancelled' END AS CHAR(80))
    WHERE ggp.game_play_id = gamePlayID;
    
    SET newGamePlayID = LAST_INSERT_ID();

	INSERT INTO gaming_game_plays_lottery_entries (game_play_id, lottery_draw_id, lottery_participation_id, amount_total, amount_bonus_win_locked, amount_real, amount_bonus, amount_ring_fenced,amount_free_bet,loyalty_points,loyalty_points_bonus)
    SELECT newGamePlayID, lottery_draw_id, lottery_participation_id, -amount_total, -amount_bonus_win_locked, -amount_real, -amount_bonus, -amount_ring_fenced, -amount_free_bet, -loyalty_points, -loyalty_points_bonus
    FROM gaming_game_plays_lottery_entries 
	WHERE game_play_id = gamePlayID;

    INSERT INTO gaming_game_plays_lottery_entry_bonuses (
		game_play_lottery_entry_id,bonus_instance_id,bet_bonus_win_locked,bet_real,bet_bonus,wager_requirement_non_weighted,
		wager_requirement_contribution_before_real_only,wager_requirement_contribution,wager_requirement_contribution_cancelled)
    SELECT newggple.game_play_lottery_entry_id, bonus_instance_id,-bet_bonus_win_locked,-bet_real,-bet_bonus,-wager_requirement_non_weighted,
		-wager_requirement_contribution_before_real_only,-wager_requirement_contribution,-wager_requirement_contribution_cancelled
    FROM gaming_game_plays_lottery_entries AS ggple FORCE INDEX (game_play_id)
    STRAIGHT_JOIN gaming_game_plays_lottery_entry_bonuses FORCE INDEX (PRIMARY) ON 
		gaming_game_plays_lottery_entry_bonuses.game_play_lottery_entry_id = ggple.game_play_lottery_entry_id
    STRAIGHT_JOIN gaming_game_plays_lottery_entries AS newggple FORCE INDEX (game_play_draw_participation) ON 
		newggple.game_play_id = newGamePlayID AND 
		newggple.lottery_draw_id = ggple.lottery_draw_id AND newggple.lottery_participation_id = ggple.lottery_participation_id
    WHERE ggple.game_play_id = gamePlayID;
    
	UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_game_plays_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
	SET
		gaming_game_plays_bonus_instances.wager_requirement_contribution_cancelled=gaming_game_plays_bonus_instances.wager_requirement_contribution,
		gaming_game_plays_bonus_instances.win_bonus=gaming_game_plays_bonus_instances.bet_bonus, 
		gaming_game_plays_bonus_instances.win_bonus_win_locked = gaming_game_plays_bonus_instances.bet_bonus_win_locked, 
		gaming_game_plays_bonus_instances.win_real=gaming_game_plays_bonus_instances.bet_real
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;
    
    SET topBonusApplicable = ROW_COUNT();

	INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) 
	VALUES (NOW(), gameRoundID);
    
    INSERT INTO gaming_game_plays_bonus_instances_wins (game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, timestamp, exchange_rate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution,bonus_order)
    SELECT LAST_INSERT_ID() ,game_play_bonus_instance_id, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, NOW(), exchangeRate, win_real, win_bonus, win_bonus_win_locked, 0, 0, gaming_bonus_instances.client_stat_id, newGamePlayID,0,bonus_order
    FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
    STRAIGHT_JOIN gaming_bonus_instances ON gaming_game_plays_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
    WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;

    -- UPDATE gaming_bonus_instances (Part 1)
	UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
	SET 
		bonus_amount_remaining=bonus_amount_remaining + IF(is_lost OR is_secured,0,win_bonus),
		current_win_locked_amount=current_win_locked_amount + IF(is_lost OR is_secured,0,win_bonus_win_locked),
		bonus_wager_requirement_remain=bonus_wager_requirement_remain + IF(is_lost OR is_secured,0,wager_requirement_contribution_cancelled),
        bonus_wager_requirement_remain_after = bonus_wager_requirement_remain_after + IF(is_lost OR is_secured,0,wager_requirement_contribution_cancelled),
		is_used_all=IF(is_active=1 AND gaming_bonus_instances.open_rounds-numParticipations<=0 AND is_used_all=0 AND is_lost=0 AND is_secured = 0
			AND (bonus_amount_remaining+IF(is_lost,0,win_bonus))=0 AND (current_win_locked_amount+IF(is_lost,0,win_bonus_win_locked))=0, 1, 0)
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;

    -- UPDATE gaming_bonus_instances (Part 2)
	UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
	SET 
		used_all_date=IF(is_used_all=1 AND used_all_date IS NULL, NOW(), used_all_date),
		gaming_bonus_instances.is_active=IF(is_used_all, 0, gaming_bonus_instances.is_active),
        open_rounds = gaming_bonus_instances.open_rounds-numParticipations
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;
 
	UPDATE gaming_client_stats AS gcs
    JOIN gaming_client_wager_types ON gaming_client_wager_types.client_wager_type_id = clientWagerTypeID
	LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=gaming_client_wager_types.client_wager_type_id
	SET 
		gcs.total_wallet_real_played_online = IF(@channelType = 'online', gcs.total_wallet_real_played_online - betReal, gcs.total_wallet_real_played_online),
		gcs.total_wallet_real_played_retail = IF(@channelType = 'retail', gcs.total_wallet_real_played_retail - betReal, gcs.total_wallet_real_played_retail),
		gcs.total_wallet_real_played_self_service = IF(@channelType = 'self-service' ,gcs.total_wallet_real_played_self_service - betReal, gcs.total_wallet_real_played_self_service),
		gcs.total_wallet_real_played = gcs.total_wallet_real_played_online + gcs.total_wallet_real_played_retail + gcs.total_wallet_real_played_self_service,
		gcs.total_real_played = IF(@channelType NOT IN ('online','retail','self-service'),gcs.total_real_played-betReal, gcs.total_wallet_real_played + gcs.total_cash_played),
		current_real_balance=current_real_balance + betReal + convertedToRealBonus + convertedToRealBWL,
		current_bonus_balance=current_bonus_balance + betBonus-cancelBonus - convertedToRealBonus, current_bonus_win_locked_balance=current_bonus_win_locked_balance + betBonusWinLocked-cancelBonusWinLocked, 
		total_bonus_played=total_bonus_played-betBonus, total_bonus_win_locked_played=total_bonus_win_locked_played-betBonusWinLocked, 
		gcs.total_real_played_base=gcs.total_real_played_base - IFNULL((betReal/exchangeRate),0),
		gcs.total_bonus_played_base=gcs.total_bonus_played_base - ((betBonus + betBonusWinLocked)/exchangeRate),
		gcs.total_loyalty_points_given = gcs.total_loyalty_points_given - IFNULL(totalLoyaltyPoints,0) ,
		gcs.current_loyalty_points = gcs.current_loyalty_points - IFNULL(totalLoyaltyPoints,0) ,
		gcs.total_loyalty_points_given_bonus = gcs.total_loyalty_points_given_bonus - IFNULL(totalLoyaltyPointsBonus,0), 
		total_bonus_transferred = total_bonus_transferred + IFNULL(convertedToRealBonus, 0), 
		total_bonus_win_locked_transferred = total_bonus_win_locked_transferred + IFNULL(convertedToRealBWL, 0), 
		total_bonus_transferred_base = total_bonus_transferred_base + ((IFNULL(convertedToRealBonus, 0) + IFNULL(convertedToRealBWL, 0)) / exchangeRate),
		gcs.locked_real_funds = gcs.locked_real_funds + releasedLockedFunds,

        loyalty_points_running_total = IF(currentVipType = 'LoyaltyPointsPeriod', loyalty_points_running_total - IFNULL(totalLoyaltyPoints,0), loyalty_points_running_total),
		-- gaming_client_sessions
		gcss.total_bet=gcss.total_bet-(betReal + betBonus + betBonusWinLocked), gcss.total_bet_base=gcss.total_bet_base-(betAmount/exchangeRate),
        gcss.bets=gcss.bets-1, gcss.total_bet_real=gcss.total_bet_real-betReal, gcss.total_bet_bonus=gcss.total_bet_bonus-betBonus-betBonusWinLocked,
		gcss.loyalty_points=gcss.loyalty_points - IFNULL(totalLoyaltyPoints,0), gcss.loyalty_points_bonus=gcss.loyalty_points_bonus- IFNULL(totalLoyaltyPointsBonus,0),
		-- gaming_client_wager_types
		gcws.num_bets=gcws.num_bets-1, gcws.total_real_wagered=gcws.total_real_wagered-betReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered+betBonus-betBonusWinLocked,
		 gcs.bet_from_real = IF (topBonusApplicable < 1,gcs.bet_from_real , GREATEST(0,gcs.bet_from_real - betReal)),
        gcws.loyalty_points=gcws.loyalty_points - IFNULL(totalLoyaltyPoints,0), gcws.loyalty_points_bonus=gcws.loyalty_points_bonus - IFNULL(totalLoyaltyPointsBonus,0)
	WHERE gcs.client_stat_id = clientStatID;
    
     IF (playLimitEnabled AND betAmount > 0) THEN 

		SELECT SUM(PlayLimitsUpdateFunc(sessionID, clientStatID, licenseType, game_cost*-1, 1, game_id)) 
		INTO @numUpdateLimitErrors
		FROM
		(
			SELECT gaming_lottery_draws.game_id, COUNT(*) AS num_participations, SUM(gaming_lottery_participations.participation_cost) AS game_cost 
			FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
			STRAIGHT_JOIN gaming_lottery_participations ON gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 4 /*FundsReturned*/
			STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_lottery_participations.lottery_draw_id
			WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID
			GROUP BY gaming_lottery_draws.game_id
		) AS XX;
		
	END IF;

  CALL PlayReturnDataWithoutGame(newgamePlayID, gameRoundID, clientStatID, gameManufacturerID, 0);
  CALL PlayReturnBonusInfoOnWin(newgamePlayID);
  
  CALL PlayerUpdateVIPLevel(clientStatID,0);
  
  CALL NotificationEventCreate(CASE licenseTypeID WHEN 6 THEN 551 WHEN 7 THEN 561 END, couponID, clientStatID, 0);

END root$$

DELIMITER ;

