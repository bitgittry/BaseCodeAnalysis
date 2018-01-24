-- -------------------------------------
-- CommonWalletSportsGenericPlaceBetTypeTwo.sql
-- -------------------------------------
DROP procedure IF EXISTS `CommonWalletSportsGenericPlaceBetTypeTwo`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsGenericPlaceBetTypeTwo`(sbBetID BIGINT, OUT statusCode INT)
root: BEGIN
	-- First Version :)  
 	-- *****************************************************
	-- Declared variables
	-- *****************************************************
	DECLARE gameManufacturerID, gamePlayID, clientID, clientStatID, gameRoundID, currencyID, clientWagerTypeID, countryID, sessionID BIGINT DEFAULT -1;

 	DECLARE vipLevelID, platformTypeID INT;
	DECLARE numSingles, numMultiples, sbBetStatusCode, commmitedBetEntries INT DEFAULT 0;

	DECLARE betAmount, betRealRemain, betBonusRemain, betBonusWinLockedRemain, FreeBonusAmount DECIMAL(18,5) DEFAULT 0;
	DECLARE betReal, betBonus, betBonusWinLocked, betFreeBet DECIMAL(18,5) DEFAULT 0;
	DECLARE betRealConfirmedNow, betBonusConfirmedNow, betBonusWinLockedConfirmedNow, betFreeBetConfirmedNow DECIMAL(18,5) DEFAULT 0;
	DECLARE bxBetAmount, bxBetReal, bxBetBonus, bxBetBonusWinLocked DECIMAL(18,5) DEFAULT 0;
	DECLARE balanceReal, balanceBonus, balanceWinLocked, betRemain, exchangeRate, betAmountBase, sbOdd, pendingBetsReal, pendingBetsBonus, loyaltyPoints, loyaltyPointsBonus DECIMAL(18, 5) DEFAULT 0;

	DECLARE currentVipType VARCHAR(100) DEFAULT '';
	DECLARE roundType, licenseType VARCHAR(20) DEFAULT NULL;

	DECLARE isAlreadyProcessed, playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, isProcessed, isCouponBet TINYINT(1) DEFAULT 0;
	DECLARE recalcualteBonusWeight TINYINT(1) DEFAULT 0;
	DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
	
	-- *****************************************************
	-- Loyalty Points Bonus variables which now not used
	-- *****************************************************
	DECLARE loyaltyPointsEnabledWager, loyaltyPointsDisabledTypeTwo, loyaltyPointsEnabled TINYINT(1) DEFAULT 0;

	-- *****************************************************
	-- Set defaults
	-- *****************************************************
	SET statusCode = 0;

	-- *****************************************************   
	-- Check the bet exists and it is in the correct status
	-- *****************************************************
	SELECT sb_bet_id, game_manufacturer_id, IFNULL(wager_game_play_id, -1), client_stat_id, bet_total, num_singles, num_multiplies, status_code, 
		amount_real, amount_bonus, amount_bonus_win_locked, amount_free_bet, is_processed
	INTO sbBetID, gameManufacturerID, gamePlayID, clientStatID, betAmount, numSingles, numMultiples, sbBetStatusCode, betReal, betBonus, betBonusWinlocked, betFreeBet, isProcessed
	FROM gaming_sb_bets 
	WHERE sb_bet_id = sbBetID;
  
	IF (sbBetID = -1 OR clientStatID = -1 OR gamePlayID = -1) THEN
		SET statusCode = 1;
		LEAVE root;
	END IF;

	SELECT 1 INTO isCouponBet
	FROM gaming_sb_bets
	JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_sb_bets.lottery_dbg_ticket_id
	WHERE gaming_sb_bets.sb_bet_id=sbBetID;

	IF (sbBetStatusCode NOT IN (3, 6) OR isProcessed = 1) THEN 
		SET statusCode = 2;
		IF (isCouponBet) THEN
			SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayID;
			CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID);
			CALL PlayReturnBonusInfoOnWin(gamePlayID);
		ELSE
			CALL CommonWalletSBReturnData(sbBetID, clientStatID);
		END IF;
		LEAVE root;
	END IF;	

	-- *****************************************************
	-- Get Settings
	-- *****************************************************
	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, IFNULL(gs4.value_bool, 0), IFNULL(gs5.value_bool, 0) AS vb5, IFNULL(gs6.value_bool, 0) AS vb6
	INTO playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, recalcualteBonusWeight, loyaltyPointsEnabledWager, loyaltyPointsDisabledTypeTwo
	FROM gaming_settings gs1 
	STRAIGHT_JOIN gaming_settings gs2 ON gs2.name='IS_BONUS_ENABLED'
	STRAIGHT_JOIN gaming_settings gs3 ON gs3.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY'
	LEFT JOIN gaming_settings gs4 ON gs4.name='SPORTS_BOOK_RECALCULATE_BONUS_CONTRIBUTION_WEIGHT_ON_COMMIT'
 	LEFT JOIN gaming_settings gs5 ON (gs5.name='LOYALTY_POINTS_WAGER_ENABLED')
	LEFT JOIN gaming_settings gs6 ON (gs6.name='LOYALTY_POINTS_DISABLE_IF_WAGERING_BONUS_TYPE_TWO')
	WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
	SET licenseType = 'sportsbook';
	SELECT client_wager_type_id INTO clientWagerTypeID FROM gaming_client_wager_types WHERE name = 'sb'; 

	-- *****************************************************
	-- Lock Player
	-- *****************************************************
	SELECT client_stat_id, client_id, currency_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, 
		current_bonus_win_locked_balance, IFNULL(pending_bets_real,0), pending_bets_bonus
	INTO clientStatID, clientID, currencyID, balanceReal, balanceBonus, balanceWinLocked, pendingBetsReal, pendingBetsBonus 
	FROM gaming_client_stats 
	WHERE client_stat_id=clientStatID 
	FOR UPDATE;

	-- *****************************************************
	-- Get Country ID
	-- *****************************************************
	SELECT country_id 
	INTO countryID 
	FROM clients_locations 
	WHERE clients_locations.client_id = clientID AND clients_locations.is_primary = 1; 

	-- *****************************************************
	-- Get Session ID and platform Type ID of Reserve Funds
	-- *****************************************************
	SELECT session_id, platform_type_id 
	INTO sessionID, platformTypeID 
	FROM gaming_game_plays 
	WHERE game_play_id = gamePlayID;

	-- *****************************************************
	-- Get platform type and channel
	-- *****************************************************
	CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, @platformTypeID, @platformType, @channelTypeID, @channelType);

	-- *****************************************************
	-- Check how much is confirmed now and that needs to be deducted from the reserved funds
	-- *****************************************************
	SELECT 
		IFNULL(SUM(amount_real), 0) AS amount_real, 
		IFNULL(SUM(amount_bonus-amount_bonus_win_locked_component), 0) AS amount_bonus, 
		IFNULL(SUM(amount_bonus_win_locked_component), 0) AS amount_bonus_win_locked
	INTO betRealConfirmedNow, betBonusConfirmedNow, betBonusWinLockedConfirmedNow
	FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
	WHERE sb_bet_id = sbBetID AND confirmation_status = 0 AND payment_transaction_type_id = 12;

	-- *****************************************************
	-- Set to confirmed all bet slips which have not been explicitily cancelled
	-- *****************************************************
	UPDATE gaming_game_plays_sb FORCE INDEX (sb_bet_id) 
	SET confirmation_status=2 
	WHERE sb_bet_id=sbBetID AND confirmation_status=0 AND payment_transaction_type_id=12;

	UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
	SET processing_status=2
	WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.processing_status<>3;

	UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id) 
	SET processing_status=2 
	WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.processing_status<>3;

	-- *****************************************************
	-- Get How much was confirmed in total for the whole bet slip
	-- *****************************************************
	SELECT COUNT(*), 
		IFNULL(SUM(amount_real), 0) AS amount_real, 
		IFNULL(SUM(amount_bonus-amount_bonus_win_locked_component), 0) AS amount_bonus, 
		IFNULL(SUM(amount_bonus_win_locked_component), 0) AS amount_bonus_win_locked
	INTO commmitedBetEntries, betReal, betBonus, betBonusWinLocked
	FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
	WHERE sb_bet_id = sbBetID AND confirmation_status = 2;

	IF (commmitedBetEntries = 0) THEN
		UPDATE gaming_sb_bets FORCE INDEX (PRIMARY) SET bet_total=bet_total-betAmount, is_processed=1, is_success=1, status_code=5 WHERE sb_bet_id=sbBetID;

		INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount) 
		SELECT sbBetID, sb_bet_transaction_type_id, NOW(), 0
		FROM gaming_sb_bet_transaction_types WHERE name='PlaceBet';

		CALL CommonWalletSBReturnData(sbBetID, clientStatID);
		SET statusCode = 0;
	END IF;

	-- *****************************************************
	-- Update the SB Bet figures
	-- *****************************************************
	UPDATE gaming_sb_bets
	SET 
		gaming_sb_bets.amount_real=betReal, 
		gaming_sb_bets.amount_bonus=betBonus, 
		gaming_sb_bets.amount_bonus_win_locked=betBonusWinLocked,
		gaming_sb_bets.bet_total=betReal+betBonus+betBonusWinLocked
	WHERE sb_bet_id=sbBetID;

	-- Get Currenty Exchange Rate
	SELECT exchange_rate, gc.vip_level_id 
	INTO exchangeRate, vipLevelId
	FROM gaming_client_stats
	JOIN gaming_operator_currency ON gaming_client_stats.currency_id = gaming_operator_currency.currency_id 
	JOIN gaming_clients gc ON gc.client_id = gaming_client_stats.client_id
	WHERE gaming_client_stats.client_stat_id=clientStatID
	LIMIT 1;

	SELECT set_type INTO currentVipType FROM gaming_vip_levels vip WHERE vip.vip_level_id=vipLevelId;

	-- *****************************************************
	-- Set Loyalty Points Enabled
	-- *****************************************************
	SET loyaltyPointsEnabled = IF(loyaltyPointsEnabledWager = 0 OR loyaltyPointsDisabledTypeTwo = 1, 0, 1);

	IF(loyaltyPointsEnabled = 0) THEN
		SET @totalLoyaltyPoints = 0;
		SET @totalLoyaltyPointsBonus = 0;
	END IF;
  
	SET betAmountBase=ROUND(betAmount/exchangeRate, 5);

	-- *****************************************************
	-- Update player totals
	-- *****************************************************
	UPDATE gaming_client_stats AS gcs
	LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
	SET 
		-- Channels
		gcs.total_wallet_real_played_online = IF(@channelType = 'online', gcs.total_wallet_real_played_online + betReal, gcs.total_wallet_real_played_online),
		gcs.total_wallet_real_played_retail = IF(@channelType = 'retail', gcs.total_wallet_real_played_retail + betReal, gcs.total_wallet_real_played_retail),
		gcs.total_wallet_real_played_self_service = IF(@channelType = 'self-service' ,gcs.total_wallet_real_played_self_service + betReal, gcs.total_wallet_real_played_self_service),
		gcs.total_wallet_real_played = gcs.total_wallet_real_played_online + gcs.total_wallet_real_played_retail + gcs.total_wallet_real_played_self_service,
		gcs.total_real_played = IF(@channelType NOT IN ('online','retail','self-service'),gcs.total_real_played+betReal, gcs.total_wallet_real_played + gcs.total_cash_played),

		-- gaming_client_stats
		gcs.pending_bets_real = pending_bets_real - betRealConfirmedNow, 
		gcs.pending_bets_bonus = pending_bets_bonus - (betBonusConfirmedNow + betBonusWinLockedConfirmedNow),
		gcs.total_real_played = gcs.total_real_played + betReal, 
		gcs.total_bonus_played = gcs.total_bonus_played + betBonus, 
		gcs.total_bonus_win_locked_played = gcs.total_bonus_win_locked_played + betBonusWinLocked, 
		gcs.total_real_played_base = gcs.total_real_played_base + (betReal/exchangeRate), 
		gcs.total_bonus_played_base = gcs.total_bonus_played_base + ((betBonus+betBonusWinLocked)/exchangeRate),
		gcs.last_played_date=NOW(), 
    gcs.bet_from_real=gcs.bet_from_real+betReal,

		-- loyalty point
		gcs.total_loyalty_points_given = gcs.total_loyalty_points_given + IFNULL(@totalLoyaltyPoints,0) , 
		gcs.current_loyalty_points = gcs.current_loyalty_points + IFNULL(@totalLoyaltyPoints,0),
		gcs.total_loyalty_points_given_bonus = gcs.total_loyalty_points_given_bonus + IFNULL(@totalLoyaltyPointsBonus,0),
		gcs.loyalty_points_running_total = IF(currentVipType = 'LoyaltyPointsPeriod', gcs.loyalty_points_running_total + IFNULL(@totalLoyaltyPoints,0), gcs.loyalty_points_running_total),    
    		
		-- gaming_client_sessions
		gcss.total_bet = gcss.total_bet + betAmount,
		gcss.total_bet_base = gcss.total_bet_base + betAmountBase, 
		gcss.bets = gcss.bets + numSingles + numMultiples, 
		gcss.total_bet_real = gcss.total_bet_real + betReal, 
		gcss.total_bet_bonus = gcss.total_bet_bonus + betBonus + betBonusWinLocked,

		gcss.loyalty_points=gcss.loyalty_points+ IFNULL(@totalLoyaltyPoints,0), 
		gcss.loyalty_points_bonus=gcss.loyalty_points_bonus+ IFNULL(@totalLoyaltyPointsBonus,0),

		-- gaming_client_wager_stats
		gcws.num_bets = gcws.num_bets + numSingles + numMultiples, 
		gcws.total_real_wagered = gcws.total_real_wagered + betReal, 
		gcws.total_bonus_wagered = gcws.total_bonus_wagered + betBonus + betBonusWinLocked,
		gcws.first_wagered_date = IFNULL(gcws.first_wagered_date, NOW()), 
		gcws.last_wagered_date=NOW(),

 		gcws.loyalty_points=gcws.loyalty_points+ IFNULL(@totalLoyaltyPoints,0), 
		gcws.loyalty_points_bonus=gcws.loyalty_points_bonus+ IFNULL(@totalLoyaltyPointsBonus,0)
	WHERE gcs.client_stat_id = clientStatID;

	-- *****************************************************    
	-- Update confirmed amount
	-- *****************************************************
	UPDATE gaming_game_plays
	SET 
		is_confirmed = 1, 
		confirmed_amount = betReal + betBonus + betBonusWinLocked, 
        is_processed=0  
	WHERE game_play_id=gamePlayID;

	-- *****************************************************  
	-- Update bonus tables and check if the bonuses requirement has met 
	-- *****************************************************
	IF (bonusEnabledFlag AND betAmount > 0) THEN

		SET @wagerReqNonWeighted = 0;
		SET @wagerReqWeightedBeforeReal = 0;
		SET @wagerReqWeighted = 0;

		-- ***************************************************** 
		-- TODO: Uncomment : Used in Type2
    -- Placed IFNULL because trow exception "wager_requirement_non_weighted cannot be null" when is used multiple bonuses
    -- Maybe we need checked in tests that is OK
		-- ***************************************************** 
		SELECT IFNULL(SUM(wager_requirement_non_weighted), 0) AS wager_requirement_non_weighted, 
		IFNULL(SUM(wager_requirement_contribution_before_real_only), 0) AS wager_requirement_contribution_before_real_only,
		IFNULL(SUM(wager_requirement_contribution), 0) AS wager_requirement_contribution
		INTO @wagerReqNonWeighted, @wagerReqWeightedBeforeReal, @wagerReqWeighted
		FROM gaming_game_plays_sb_bonuses
		JOIN gaming_game_plays_sb ON gaming_game_plays_sb.game_play_sb_id  = gaming_game_plays_sb.game_play_sb_id
		WHERE gaming_game_plays_sb.game_play_id = gamePlayID;

		IF (recalcualteBonusWeight) THEN

			-- ***************************************************** 
			-- updated gaming_sb_bets_bonus_rules
			-- ***************************************************** 
			CALL CommonWalletSportsGenericCalculateBonusRuleWeightTypeTwo(sessionID, clientStatID, sbBetID, numSingles, numMultiples);

			UPDATE 
			(
				SELECT gaming_game_plays_sb.game_play_sb_id, sb_bonuses.bonus_instance_id, 
					@wagerNonWeighted := sb_bonuses.bet_bonus_win_locked+sb_bonuses.bet_real+sb_bonuses.bet_bonus AS wagerNonWeighted,
					@wagerWeighted :=
						ROUND(
							LEAST(
								IFNULL(wgr_restrictions.max_wager_contibution_before_weight, 100000000*100),
								@wagerNonWeighted
							)*IFNULL(gaming_sb_bets_bonus_rules.weight, 0)*IFNULL(gaming_bonus_rules.sportsbook_weight_mod, 1),
						5),
					IF(@wagerWeighted>=gaming_bonus_instances.bonus_wager_requirement_remain, gaming_bonus_instances.bonus_wager_requirement_remain, @wagerWeighted) AS wager_requirement_contribution_pre,
					@wagerNonWeighted:= IF(gaming_bonus_rules.wager_req_real_only OR bonusReqContributeRealOnly, sb_bonuses.bet_real, sb_bonuses.bet_bonus_win_locked+sb_bonuses.bet_real+sb_bonuses.bet_bonus),
					@wagerWeighted :=IF(gaming_bonus_instances.is_freebet_phase, 0,
						ROUND(
							LEAST(
								IFNULL(wgr_restrictions.max_wager_contibution_before_weight, 100000000*100),
								@wagerNonWeighted
							)*IFNULL(gaming_sb_bets_bonus_rules.weight, 0)*IFNULL(gaming_bonus_rules.sportsbook_weight_mod, 1),
						5)
					) AS wager_requirement_contribution           
				FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
				STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS sb_bonuses ON gaming_game_plays_sb.game_play_sb_id=sb_bonuses.game_play_sb_id
				STRAIGHT_JOIN gaming_bonus_instances ON sb_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
				STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_instances.bonus_rule_id 
				LEFT JOIN  gaming_sb_bets_bonus_rules ON gaming_sb_bets_bonus_rules.sb_bet_id=gaming_game_plays_sb.sb_bet_id AND gaming_sb_bets_bonus_rules.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_rules.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID
				WHERE gaming_game_plays_sb.sb_bet_id=sbBetID AND sb_bonuses.wager_requirement_non_weighted > 0
			) AS XX 
			STRAIGHT_JOIN gaming_game_plays_sb_bonuses FORCE INDEX (PRIMARY) ON (gaming_game_plays_sb_bonuses.game_play_sb_id=XX.game_play_sb_id 
				AND gaming_game_plays_sb_bonuses.bonus_instance_id=XX.bonus_instance_id)
				SET gaming_game_plays_sb_bonuses.wager_requirement_non_weighted=XX.wagerNonWeighted,
				gaming_game_plays_sb_bonuses.wager_requirement_contribution_before_real_only=XX.wager_requirement_contribution_pre, 
				gaming_game_plays_sb_bonuses.wager_requirement_contribution=XX.wager_requirement_contribution;

		END IF;

-- 		INSERT INTO gaming_game_plays_bonus_instances (game_play_id, bonus_instance_id, bonus_rule_id, client_stat_id, timestamp, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,
-- 			wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, 
-- 			bonus_wager_requirement_remain_after,bonus_order)
-- 		SELECT game_play_id, bonus_instance_id, bonus_rule_id, clientStatID, NOW(), exchangeRate, bet_real, bet_bonus, bet_bonus_win_locked,
-- 			wager_requirement_non_weighted, wager_requirement_contribution_pre, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus,
-- 			bonus_wager_requirement_remain_after, bonus_order
-- 		FROM 
-- 		(
-- 			SELECT game_play_id, bonus_instance_id, gaming_bonus_instances.bonus_rule_id, clientStatID, exchangeRate,
-- 				gaming_bonus_instances.bet_real, gaming_bonus_instances.bet_ring_fenced, gaming_bonus_instances.bet_bonus, gaming_bonus_instances.bet_bonus_win_locked,
-- 				@tempWagerNonWeighted := IF(bonus_wager_requirement_remain<wager_requirement_non_weighted, bonus_wager_requirement_remain, wager_requirement_non_weighted) AS wager_requirement_non_weighted,
-- 				@wagerReqNonWeighted := GREATEST(0,wager_requirement_non_weighted - @tempWagerNonWeighted),
-- 				@tempWagerReqWeightedBeforeReal := IF(bonus_wager_requirement_remain<wager_requirement_contribution_before_real_only, bonus_wager_requirement_remain, wager_requirement_contribution_before_real_only) AS wager_requirement_contribution_pre,
-- 				@wagerReqWeightedBeforeReal:= GREATEST(0,wager_requirement_contribution_before_real_only-@tempWagerReqWeightedBeforeReal), 
-- 				@tempWagerReqWeighted := IF(bonus_wager_requirement_remain<wager_requirement_contribution, bonus_wager_requirement_remain, wager_requirement_contribution) AS wager_requirement_contribution,
-- 				@wagerReqWeighted := GREATEST(0,wager_requirement_contribution- @tempWagerReqWeighted),
-- 				@nowWagerReqMet:=IF (bonus_wager_requirement_remain-@tempWagerReqWeighted=0 AND is_free_bonus=0, 1 ,0) AS now_wager_requirement_met,
-- 				IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wagerReqWeighted)>=((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,
-- 				bonus_wager_requirement_remain-@wagerReqWeighted AS bonus_wager_requirement_remain_after,
-- 				bonus_order
-- 			FROM 
-- 			(
-- 				SELECT BonusTransactions.game_play_id, BonusTransactions.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, 
-- 					BonusTransactions.bet_real, BonusTransactions.bet_ring_fenced, BonusTransactions.bet_bonus, BonusTransactions.bet_bonus_win_locked, gaming_bonus_rules.sportsbook_weight_mod AS license_weight_mod,
-- 					BonusTransactions.wager_requirement_non_weighted, BonusTransactions.wager_requirement_contribution_before_real_only, BonusTransactions.wager_requirement_contribution,
-- 					gaming_bonus_instances.bonus_amount_given, gaming_bonus_instances.bonus_wager_requirement, gaming_bonus_instances.bonus_wager_requirement_remain,
-- 					gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, IFNULL(transfer_type.name,'') IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus, 
-- 					IFNULL(gaming_sb_bets_bonuses.bonus_order, 100) AS bonus_order, gaming_bonus_rules.is_free_bonus, gaming_bonus_instances.is_freebet_phase, 0 AS ring_fence_only
-- 				FROM 
-- 				(
-- 					SELECT gaming_game_plays_sb.game_play_id, sb_bonuses.bonus_instance_id,
-- 						SUM(sb_bonuses.bet_real) AS bet_real, SUM(sb_bonuses.bet_bonus) AS bet_bonus, SUM(sb_bonuses.bet_bonus_win_locked) AS bet_bonus_win_locked, SUM(sb_bonuses.bet_ring_fenced) AS bet_ring_fenced,
-- 						SUM(sb_bonuses.wager_requirement_non_weighted) AS wager_requirement_non_weighted, SUM(sb_bonuses.wager_requirement_contribution_before_real_only) AS wager_requirement_contribution_before_real_only,
-- 						SUM(sb_bonuses.wager_requirement_contribution) AS wager_requirement_contribution
-- 					FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
-- 					STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS sb_bonuses ON gaming_game_plays_sb.game_play_sb_id=sb_bonuses.game_play_sb_id
-- 					WHERE gaming_game_plays_sb.sb_bet_id=sbBetID AND gaming_game_plays_sb.confirmation_status=2 
-- 					GROUP BY sb_bonuses.bonus_instance_id
-- 				) AS BonusTransactions
-- 				STRAIGHT_JOIN gaming_bonus_instances ON BonusTransactions.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
-- 				STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
-- 				LEFT JOIN gaming_sb_bets_bonuses ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_instance_id=gaming_sb_bets_bonuses.bonus_instance_id
-- 				LEFT JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
-- 				ORDER BY IFNULL(gaming_sb_bets_bonuses.bonus_order, 100), gaming_bonus_instances.priority
-- 			) AS gaming_bonus_instances  
-- 		) AS a;

--		IF (ROW_COUNT() > 0) THEN

			-- *****************************************************
			-- Bonus balance has already been updated but we need to update the bonus_wager_requirement_remain
			-- *****************************************************
			UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
			STRAIGHT_JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id=ggpbi.bonus_instance_id
			SET 
				gbi.bonus_wager_requirement_remain=gbi.bonus_wager_requirement_remain-ggpbi.wager_requirement_contribution,
				gbi.is_secured=IF(ggpbi.now_wager_requirement_met=1, 1, gbi.is_secured), 
				gbi.secured_date=IF(ggpbi.now_wager_requirement_met=1,NOW(),NULL),
				gbi.reserved_bonus_funds = gbi.reserved_bonus_funds - (ggpbi.bet_bonus + ggpbi.bet_bonus_win_locked)
				-- current_ring_fenced_amount=current_ring_fenced_amount-bet_ring_fenced,
				-- gaming_bonus_instances.open_rounds=gaming_bonus_instances.open_rounds+1
			WHERE ggpbi.game_play_id=gamePlayID;  

			-- *****************************************************      
			-- Wagering Requirement Met
			-- *****************************************************        
			UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
			STRAIGHT_JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
			SET 
				ggpbi.bonus_transfered_total = (CASE transfer_type.name
					WHEN 'All' THEN bonus_amount_remaining+current_win_locked_amount
					WHEN 'Bonus' THEN bonus_amount_remaining
					WHEN 'BonusWinLocked' THEN current_win_locked_amount
					WHEN 'UpToBonusAmount' THEN LEAST(bonus_amount_given, bonus_amount_remaining+current_win_locked_amount)
					WHEN 'UpToPercentage' THEN LEAST(bonus_amount_given*transfer_upto_percentage, bonus_amount_remaining+current_win_locked_amount)
					WHEN 'ReleaseBonus' THEN LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, bonus_amount_remaining+current_win_locked_amount)
					WHEN 'ReleaseAllBonus' THEN bonus_amount_remaining+current_win_locked_amount
					ELSE 0
				END),
				ggpbi.bonus_transfered= IF(transfer_type.name='BonusWinLocked', 0, LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining)), 
				ggpbi.bonus_win_locked_transfered = IF(transfer_type.name='Bonus', 0, ggpbi.bonus_transfered_total-ggpbi.bonus_transfered),
				ggpbi.bonus_transfered_lost=bonus_amount_remaining-ggpbi.bonus_transfered,
				ggpbi.bonus_win_locked_transfered_lost=current_win_locked_amount-bonus_win_locked_transfered,
				bonus_amount_remaining=0,
				current_win_locked_amount=0, 
				current_ring_fenced_amount=0,
				gaming_bonus_instances.bonus_transfered_total=gaming_bonus_instances.bonus_transfered_total+ggpbi.bonus_transfered_total,
				gaming_bonus_instances.session_id=sessionID
			WHERE ggpbi.game_play_id=gamePlayID AND ggpbi.now_wager_requirement_met=1 AND ggpbi.now_used_all=0;

			SET @requireTransfer=0;
			SET @bonusTransfered=0;
			SET @bonusWinLockedTransfered=0;
			SET @bonusTransferedLost=0;
			SET @bonusWinLockedTransferedLost=0;

			SET @ringFencedAmount=0;
			SET @ringFencedAmountSB=0;
			SET @ringFencedAmountCasino=0;
			SET @ringFencedAmountPoker=0;

			SELECT COUNT(*)>0, 
				IFNULL(ROUND(SUM(bonus_transfered),0),0), 
				IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), 
				IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), 
				IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0),
				ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),
				ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
				ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),
				ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
			INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
				@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
			FROM gaming_game_plays_bonus_instances
			LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id
			WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;

			SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
			SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;

			IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
				CALL PlaceBetBonusCashExchangeTypeTwo(clientStatID, gamePlayID, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, 
					@bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
			END IF; 

			-- *****************************************************      
			-- Slow Release
			-- *****************************************************
			UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
			STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id
			STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id AND transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus')
			SET 
				ggpbi.bonus_transfered_total=LEAST(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))*gaming_bonus_instances.transfer_every_amount, bonus_amount_remaining+current_win_locked_amount), 
				ggpbi.bonus_transfered=LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining),
				ggpbi.bonus_win_locked_transfered=ggpbi.bonus_transfered_total-ggpbi.bonus_transfered,
				bonus_amount_remaining=bonus_amount_remaining-bonus_transfered, 
				current_win_locked_amount=current_win_locked_amount-bonus_win_locked_transfered,  
				gaming_bonus_instances.transfer_every_x_last=gaming_bonus_instances.transfer_every_x_last+(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))*gaming_bonus_instances.transfer_every_x),
				gaming_bonus_instances.bonus_transfered_total=IFNULL(gaming_bonus_instances.bonus_transfered_total,0)+ggpbi.bonus_transfered_total,
				gaming_bonus_instances.session_id=sessionID
			WHERE ggpbi.game_play_id=gamePlayID AND ggpbi.now_release_bonus=1 AND ggpbi.now_used_all=0 AND ggpbi.now_wager_requirement_met=0;

			SET @requireTransfer=0;
			SET @bonusTransfered=0;
			SET @bonusWinLockedTransfered=0;
			SET @bonusTransferedLost=0;
			SET @bonusWinLockedTransferedLost=0;

			SET @ringFencedAmount=0;
			SET @ringFencedAmountSB=0;
			SET @ringFencedAmountCasino=0;
			SET @ringFencedAmountPoker=0;

			SELECT COUNT(*)>0, 
				IFNULL(ROUND(SUM(bonus_transfered),0),0), 
				IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), 
				IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), 
				IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0),
				ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),
				ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
				ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),
				ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
			INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
				@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
			FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
			LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id
			WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

			SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
			SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;

			IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
				CALL PlaceBetBonusCashExchangeTypeTwo(clientStatID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, 
					@bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
			END IF; 




--		END IF; 

	END IF;

	-- *****************************************************
	-- If the bonus is secured than it is no longer active
	-- *****************************************************  
	UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
	SET gaming_bonus_instances.is_active=IF(is_active=0, 0, IF(is_secured,0,1))
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;           

	UPDATE gaming_sb_bets 
	SET 
		bet_total=bet_total-betAmount, 
		is_processed=1, 
		is_success=1,
		status_code=5 
	WHERE sb_bet_id=sbBetID;

	INSERT INTO gaming_sb_bet_history 
		(sb_bet_id, sb_bet_transaction_type_id, timestamp, amount) 
	SELECT sbBetID, sb_bet_transaction_type_id, NOW(), betAmount
	FROM gaming_sb_bet_transaction_types WHERE name='PlaceBet';

	IF (isCouponBet) THEN
		SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayID;
		CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID);
		CALL PlayReturnBonusInfoOnWin(gamePlayID);
	ELSE
		CALL CommonWalletSBReturnData(sbBetID, clientStatID);
	END IF;
    CALL NotificationEventCreate(700, sbBetID, clientStatID, 0);
	SET statusCode=0;

END root$$

DELIMITER ;

-- -------------------------------------
-- CommonWalletSportsGenericPlaceBet.sql
-- -------------------------------------
DROP procedure IF EXISTS  `CommonWalletSportsGenericPlaceBet`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletLogRequest`(sbBetID BIGINT, OUT statusCode INT)
root: BEGIN
  -- First Version :) 
  -- All singles and multiples in (gaming_game_plays_sb) which have not been cancelled will be accepted/confirmed
  -- Updates the wagering requirement of a bonus  
  -- Checking only with payment_transaction_type_id=12
  -- Checking if there is nothing to commit return immediately
  -- Forced indicessadf
  -- Recalcualte Bonus Wagering Requirement if SPORTS_BOOK_RECALCULATE_BONUS_CONTRIBUTION_WEIGHT_ON_COMMIT setting is on
  -- WHERE gaming_game_plays_sb.sb_bet_id=sbBetID AND sb_bonuses.wager_requirement_non_weighted > 0
  
  DECLARE gameManufacturerID, gamePlayID, clientID, clientStatID, gameRoundID, currencyID, clientWagerTypeID, countryID, sessionID BIGINT DEFAULT -1;
  DECLARE isAlreadyProcessed, playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, isProcessed TINYINT(1) DEFAULT 0;
  DECLARE numSingles, numMultiples, sbBetStatusCode, commmitedBetEntries INT DEFAULT 0;
  DECLARE betAmount, betRealRemain, betBonusRemain, betBonusWinLockedRemain, FreeBonusAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE betReal, betBonus, betBonusWinLocked, betFreeBet DECIMAL(18,5) DEFAULT 0;
  DECLARE betRealConfirmedNow, betBonusConfirmedNow, betBonusWinLockedConfirmedNow, betFreeBetConfirmedNow DECIMAL(18,5) DEFAULT 0;
  DECLARE bxBetAmount, bxBetReal, bxBetBonus, bxBetBonusWinLocked DECIMAL(18,5) DEFAULT 0;
  DECLARE balanceReal, balanceBonus, balanceWinLocked, betRemain, exchangeRate, betAmountBase, sbOdd, pendingBetsReal, pendingBetsBonus, loyaltyPoints, loyaltyPointsBonus DECIMAL(18, 5) DEFAULT 0;
  DECLARE roundType, licenseType VARCHAR(20) DEFAULT NULL;
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
  DECLARE recalcualteBonusWeight, isCouponBet TINYINT(1) DEFAULT 0;

  SET statusCode=0;
   
  -- Check the bet exists and it is in the correct status
  SELECT sb_bet_id, game_manufacturer_id, IFNULL(wager_game_play_id, -1), client_stat_id, bet_total, num_singles, num_multiplies, status_code, amount_real, amount_bonus, amount_bonus_win_locked, amount_free_bet, is_processed
  INTO sbBetID, gameManufacturerID, gamePlayID, clientStatID, betAmount, numSingles, numMultiples, sbBetStatusCode, betReal, betBonus, betBonusWinlocked, betFreeBet, isProcessed
  FROM gaming_sb_bets WHERE sb_bet_id=sbBetID;
  
  IF (sbBetID=-1 OR clientStatID=-1 OR gamePlayID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  SELECT 1 INTO isCouponBet
  FROM gaming_sb_bets
  JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_sb_bets.lottery_dbg_ticket_id
  WHERE gaming_sb_bets.sb_bet_id=sbBetID;

  IF (sbBetStatusCode NOT IN (3,6) OR isProcessed=1) THEN 
    SET statusCode=2;
	IF (isCouponBet) THEN
		SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayID;
		CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID);
		CALL PlayReturnBonusInfoOnWin(gamePlayID);
	ELSE
		CALL CommonWalletSBReturnData(sbBetID, clientStatID);
	END IF;
    LEAVE root;
  END IF;	

  -- Get Settings
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, IFNULL(gs4.value_bool, 0)
  INTO playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, recalcualteBonusWeight
  FROM gaming_settings gs1 
  STRAIGHT_JOIN gaming_settings gs2 ON gs2.name='IS_BONUS_ENABLED'
  STRAIGHT_JOIN gaming_settings gs3 ON gs3.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY'
  LEFT JOIN gaming_settings gs4 ON gs4.name='SPORTS_BOOK_RECALCULATE_BONUS_CONTRIBUTION_WEIGHT_ON_COMMIT'
  WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
  SET licenseType='sportsbook';
  SELECT client_wager_type_id INTO clientWagerTypeID FROM gaming_client_wager_types WHERE name='sb'; 

  -- Lock Player
  SELECT client_stat_id, client_id, currency_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, IFNULL(pending_bets_real,0), pending_bets_bonus
  INTO clientStatID, clientID, currencyID, balanceReal, balanceBonus, balanceWinLocked, pendingBetsReal, pendingBetsBonus 
  FROM gaming_client_stats 
  WHERE client_stat_id=clientStatID 
  FOR UPDATE;
  
  -- Get Country ID
  SELECT country_id INTO countryID FROM clients_locations WHERE clients_locations.client_id=clientID AND clients_locations.is_primary=1; 
  
  -- Get Session ID of Reserve Funds
  SELECT session_id INTO sessionID FROM gaming_game_plays WHERE game_play_id=gamePlayID;

  -- Check how much is confirmed now and that needs to be deducted from the reserved funds
  SELECT IFNULL(SUM(amount_real),0) AS amount_real, IFNULL(SUM(amount_bonus-amount_bonus_win_locked_component),0) AS amount_bonus, IFNULL(SUM(amount_bonus_win_locked_component),0) AS amount_bonus_win_locked
  INTO betRealConfirmedNow, betBonusConfirmedNow, betBonusWinLockedConfirmedNow
  FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
  WHERE sb_bet_id=sbBetID AND confirmation_status=0 AND payment_transaction_type_id=12;

  -- Set to confirmed all bet slips which have not been explicitily cancelled
  UPDATE gaming_game_plays_sb FORCE INDEX (sb_bet_id) 
  SET confirmation_status=2 
  WHERE sb_bet_id=sbBetID AND confirmation_status=0 AND payment_transaction_type_id=12;
  
  UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
  SET processing_status=2
  WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.processing_status<>3;
  
  UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id) 
  SET processing_status=2 
  WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.processing_status<>3;

  -- Get How much was confirmed in total for the whole bet slip
  SELECT COUNT(*), IFNULL(SUM(amount_real),0) AS amount_real, IFNULL(SUM(amount_bonus-amount_bonus_win_locked_component),0) AS amount_bonus, IFNULL(SUM(amount_bonus_win_locked_component),0) AS amount_bonus_win_locked
  INTO commmitedBetEntries, betReal, betBonus, betBonusWinLocked
  FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
  WHERE sb_bet_id=sbBetID AND confirmation_status=2;

  IF (commmitedBetEntries=0) THEN
	UPDATE gaming_sb_bets FORCE INDEX (PRIMARY) SET bet_total=bet_total-betAmount, is_processed=1, is_success=1, status_code=5 WHERE sb_bet_id=sbBetID;
    
	  INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount) 
	  SELECT sbBetID, sb_bet_transaction_type_id, NOW(), 0
	  FROM gaming_sb_bet_transaction_types WHERE name='PlaceBet';
	  
	CALL CommonWalletSBReturnData(sbBetID, clientStatID);
    SET statusCode=0;
  END IF;

  -- Update the SB Bet figures
  UPDATE gaming_sb_bets
  SET gaming_sb_bets.amount_real=betReal, gaming_sb_bets.amount_bonus=betBonus, gaming_sb_bets.amount_bonus_win_locked=betBonusWinLocked,
	  gaming_sb_bets.bet_total=betReal+betBonus+betBonusWinLocked
  WHERE sb_bet_id=sbBetID;

  -- Get Currenty Exchange Rate
  SELECT exchange_rate into exchangeRate 
  FROM gaming_client_stats
  STRAIGHT_JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SET betAmountBase=ROUND(betAmount/exchangeRate, 5);
  
  -- Update player totals
  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET -- gaming_client_stats
	  gcs.pending_bets_real=pending_bets_real-betRealConfirmedNow, gcs.pending_bets_bonus=pending_bets_bonus-(betBonusConfirmedNow+betBonusWinLockedConfirmedNow),
	  gcs.total_real_played=gcs.total_real_played+betReal, 
      gcs.total_bonus_played=gcs.total_bonus_played+betBonus, 
      gcs.total_bonus_win_locked_played=gcs.total_bonus_win_locked_played+betBonusWinLocked, 
      gcs.total_real_played_base=gcs.total_real_played_base+(betReal/exchangeRate), gcs.total_bonus_played_base=gcs.total_bonus_played_base+((betBonus+betBonusWinLocked)/exchangeRate),
      gcs.last_played_date=NOW(), 
      -- gaming_client_sessions
      gcss.total_bet=gcss.total_bet+betAmount,gcss.total_bet_base=gcss.total_bet_base+betAmountBase, gcss.bets=gcss.bets+numSingles+numMultiples, gcss.total_bet_real=gcss.total_bet_real+betReal, gcss.total_bet_bonus=gcss.total_bet_bonus+betBonus+betBonusWinLocked,
      -- gaming_client_wager_stats
      gcws.num_bets=gcws.num_bets+numSingles+numMultiples, gcws.total_real_wagered=gcws.total_real_wagered+betReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered+betBonus+betBonusWinLocked,
      gcws.first_wagered_date=IFNULL(gcws.first_wagered_date, NOW()), gcws.last_wagered_date=NOW()
  WHERE gcs.client_stat_id = clientStatID;
  
  -- Update confirmed amount
  UPDATE gaming_game_plays
  SET is_confirmed=1, confirmed_amount=betReal+betBonus+betBonusWinLocked, is_processed=0  
  WHERE game_play_id=gamePlayID;
  
  -- Update bonus tables and check if the bonuses requirement has met 
  IF (bonusEnabledFlag AND betAmount>0) THEN
    
	SET @wagerReqNonWeighted=0;
    SET @wagerReqWeightedBeforeReal=0;
	SET @wagerReqWeighted=0;

    /* -- Used in Type2
	SELECT SUM(wager_requirement_non_weighted) AS wager_requirement_non_weighted, 
		SUM(wager_requirement_contribution_before_real_only) AS wager_requirement_contribution_before_real_only,
		SUM(wager_requirement_contribution) AS wager_requirement_contribution
	INTO @wagerReqNonWeighted, @wagerReqWeightedBeforeReal, @wagerReqWeighted
	FROM gaming_game_plays_sb_bonuses
	JOIN gaming_game_plays_sb ON gaming_game_plays_sb.game_play_sb_id  = gaming_game_plays_sb.game_play_sb_id
	WHERE gaming_game_plays_sb.game_play_id = gamePlayID;
    */
    
    IF (recalcualteBonusWeight) THEN
	-- updated gaming_sb_bets_bonus_rules
		CALL CommonWalletSportsGenericCalculateBonusRuleWeight(sessionID, clientStatID, sbBetID, numSingles, numMultiples);
	  
		UPDATE 
		(
			SELECT gaming_game_plays_sb.game_play_sb_id, sb_bonuses.bonus_instance_id, 
				@wagerNonWeighted := sb_bonuses.bet_bonus_win_locked+sb_bonuses.bet_real+sb_bonuses.bet_bonus AS wagerNonWeighted,
				@wagerWeighted :=
						ROUND(
							LEAST(
									IFNULL(wgr_restrictions.max_wager_contibution_before_weight, 100000000*100),
									@wagerNonWeighted
								  )*IFNULL(gaming_sb_bets_bonus_rules.weight, 0)*IFNULL(gaming_bonus_rules.sportsbook_weight_mod, 1),

						5),
				IF(@wagerWeighted>=gaming_bonus_instances.bonus_wager_requirement_remain, gaming_bonus_instances.bonus_wager_requirement_remain, @wagerWeighted) AS wager_requirement_contribution_pre,
				@wagerNonWeighted:= IF(gaming_bonus_rules.wager_req_real_only OR bonusReqContributeRealOnly, sb_bonuses.bet_real, sb_bonuses.bet_bonus_win_locked+sb_bonuses.bet_real+sb_bonuses.bet_bonus),
				@wagerWeighted :=IF(gaming_bonus_instances.is_freebet_phase, 0,
						ROUND(
							LEAST(
									IFNULL(wgr_restrictions.max_wager_contibution_before_weight, 100000000*100),
									@wagerNonWeighted
								  )*IFNULL(gaming_sb_bets_bonus_rules.weight, 0)*IFNULL(gaming_bonus_rules.sportsbook_weight_mod, 1),

						5)) AS wager_requirement_contribution           
			FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
			STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS sb_bonuses ON gaming_game_plays_sb.game_play_sb_id=sb_bonuses.game_play_sb_id
			STRAIGHT_JOIN gaming_bonus_instances ON sb_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_instances.bonus_rule_id 
			LEFT JOIN  gaming_sb_bets_bonus_rules ON gaming_sb_bets_bonus_rules.sb_bet_id=gaming_game_plays_sb.sb_bet_id AND gaming_sb_bets_bonus_rules.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_rules.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID
			WHERE gaming_game_plays_sb.sb_bet_id=sbBetID AND sb_bonuses.wager_requirement_non_weighted > 0
		) AS XX STRAIGHT_JOIN gaming_game_plays_sb_bonuses FORCE INDEX (PRIMARY) ON (gaming_game_plays_sb_bonuses.game_play_sb_id=XX.game_play_sb_id 
			AND gaming_game_plays_sb_bonuses.bonus_instance_id=XX.bonus_instance_id)
		SET gaming_game_plays_sb_bonuses.wager_requirement_non_weighted=XX.wagerNonWeighted,
			gaming_game_plays_sb_bonuses.wager_requirement_contribution_before_real_only=XX.wager_requirement_contribution_pre, 
			gaming_game_plays_sb_bonuses.wager_requirement_contribution=XX.wager_requirement_contribution;
	END IF;
    
	INSERT INTO gaming_game_plays_bonus_instances (game_play_id, bonus_instance_id, bonus_rule_id, client_stat_id, timestamp, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,
			wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_wager_requirement_remain_after,bonus_order)
	SELECT game_play_id, bonus_instance_id, bonus_rule_id, clientStatID, NOW(), exchangeRate, bet_real, bet_bonus, bet_bonus_win_locked,
		wager_requirement_non_weighted, wager_requirement_contribution_pre, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus,
		bonus_wager_requirement_remain_after, bonus_order
	FROM (
		SELECT game_play_id, bonus_instance_id, gaming_bonus_instances.bonus_rule_id, clientStatID, exchangeRate,
			gaming_bonus_instances.bet_real, gaming_bonus_instances.bet_ring_fenced, gaming_bonus_instances.bet_bonus, gaming_bonus_instances.bet_bonus_win_locked,
			@tempWagerNonWeighted := IF(bonus_wager_requirement_remain<wager_requirement_non_weighted, bonus_wager_requirement_remain, wager_requirement_non_weighted) AS wager_requirement_non_weighted,
			@wagerReqNonWeighted := GREATEST(0,wager_requirement_non_weighted - @tempWagerNonWeighted),
			@tempWagerReqWeightedBeforeReal := IF(bonus_wager_requirement_remain<wager_requirement_contribution_before_real_only, bonus_wager_requirement_remain, wager_requirement_contribution_before_real_only) AS wager_requirement_contribution_pre,
			@wagerReqWeightedBeforeReal:= GREATEST(0,wager_requirement_contribution_before_real_only-@tempWagerReqWeightedBeforeReal), 
			@tempWagerReqWeighted := IF(bonus_wager_requirement_remain<wager_requirement_contribution, bonus_wager_requirement_remain, wager_requirement_contribution) AS wager_requirement_contribution,
			@wagerReqWeighted := GREATEST(0,wager_requirement_contribution- @tempWagerReqWeighted),
			@nowWagerReqMet:=IF (bonus_wager_requirement_remain-@tempWagerReqWeighted=0 AND is_free_bonus=0, 1 ,0) AS now_wager_requirement_met,
			IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wagerReqWeighted)>=((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,
			bonus_wager_requirement_remain-@wagerReqWeighted AS bonus_wager_requirement_remain_after,
			bonus_order
		FROM 
		(
			SELECT BonusTransactions.game_play_id, BonusTransactions.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, 
			  BonusTransactions.bet_real, BonusTransactions.bet_ring_fenced, BonusTransactions.bet_bonus, BonusTransactions.bet_bonus_win_locked, gaming_bonus_rules.sportsbook_weight_mod AS license_weight_mod,
			  BonusTransactions.wager_requirement_non_weighted, BonusTransactions.wager_requirement_contribution_before_real_only, BonusTransactions.wager_requirement_contribution,
			  gaming_bonus_instances.bonus_amount_given, gaming_bonus_instances.bonus_wager_requirement, gaming_bonus_instances.bonus_wager_requirement_remain,
			  gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, IFNULL(transfer_type.name,'') IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus, 
			  IFNULL(gaming_sb_bets_bonuses.bonus_order, 100) AS bonus_order, gaming_bonus_rules.is_free_bonus, gaming_bonus_instances.is_freebet_phase, 0 AS ring_fence_only
			FROM (
				SELECT gaming_game_plays_sb.game_play_id, sb_bonuses.bonus_instance_id,
					SUM(sb_bonuses.bet_real) AS bet_real, SUM(sb_bonuses.bet_bonus) AS bet_bonus, SUM(sb_bonuses.bet_bonus_win_locked) AS bet_bonus_win_locked, SUM(sb_bonuses.bet_ring_fenced) AS bet_ring_fenced,
					SUM(sb_bonuses.wager_requirement_non_weighted) AS wager_requirement_non_weighted, SUM(sb_bonuses.wager_requirement_contribution_before_real_only) AS wager_requirement_contribution_before_real_only,
					SUM(sb_bonuses.wager_requirement_contribution) AS wager_requirement_contribution
				FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
				STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS sb_bonuses ON gaming_game_plays_sb.game_play_sb_id=sb_bonuses.game_play_sb_id
				WHERE gaming_game_plays_sb.sb_bet_id=sbBetID AND gaming_game_plays_sb.confirmation_status=2 
				GROUP BY sb_bonuses.bonus_instance_id
			) AS BonusTransactions
			STRAIGHT_JOIN gaming_bonus_instances ON BonusTransactions.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			LEFT JOIN gaming_sb_bets_bonuses ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_instance_id=gaming_sb_bets_bonuses.bonus_instance_id
			LEFT JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
			ORDER BY IFNULL(gaming_sb_bets_bonuses.bonus_order, 100), gaming_bonus_instances.priority
		) AS gaming_bonus_instances  
	) AS a;

	  IF (ROW_COUNT() > 0) THEN
	
		-- Bonus balance has already been updated but we need to update the bonus_wager_requirement_remain
		UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
		STRAIGHT_JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id=ggpbi.bonus_instance_id
		SET gbi.bonus_wager_requirement_remain=gbi.bonus_wager_requirement_remain-ggpbi.wager_requirement_contribution,
			gbi.is_secured=IF(ggpbi.now_wager_requirement_met=1, 1, gbi.is_secured), gbi.secured_date=IF(ggpbi.now_wager_requirement_met=1,NOW(),NULL),
			gbi.reserved_bonus_funds = gbi.reserved_bonus_funds - (ggpbi.bet_bonus + ggpbi.bet_bonus_win_locked)
			-- -- current_ring_fenced_amount=current_ring_fenced_amount-bet_ring_fenced,
			-- gaming_bonus_instances.open_rounds=gaming_bonus_instances.open_rounds+1
		WHERE ggpbi.game_play_id=gamePlayID;  
        

		-- Wagering Requirement Met
        UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
        STRAIGHT_JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
        STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
        SET 
            ggpbi.bonus_transfered_total=(CASE transfer_type.name
              WHEN 'All' THEN bonus_amount_remaining+current_win_locked_amount
              WHEN 'Bonus' THEN bonus_amount_remaining
              WHEN 'BonusWinLocked' THEN current_win_locked_amount
              WHEN 'UpToBonusAmount' THEN LEAST(bonus_amount_given, bonus_amount_remaining+current_win_locked_amount)
              WHEN 'UpToPercentage' THEN LEAST(bonus_amount_given*transfer_upto_percentage, bonus_amount_remaining+current_win_locked_amount)
              WHEN 'ReleaseBonus' THEN LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, bonus_amount_remaining+current_win_locked_amount)
              WHEN 'ReleaseAllBonus' THEN bonus_amount_remaining+current_win_locked_amount
              ELSE 0
            END),
            ggpbi.bonus_transfered=IF(transfer_type.name='BonusWinLocked', 0, LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining)),
            ggpbi.bonus_win_locked_transfered=IF(transfer_type.name='Bonus', 0, ggpbi.bonus_transfered_total-ggpbi.bonus_transfered),
            ggpbi.bonus_transfered_lost=bonus_amount_remaining-ggpbi.bonus_transfered,
            ggpbi.bonus_win_locked_transfered_lost=current_win_locked_amount-bonus_win_locked_transfered,
            bonus_amount_remaining=0,current_win_locked_amount=0, current_ring_fenced_amount=0,  
            gaming_bonus_instances.bonus_transfered_total=gaming_bonus_instances.bonus_transfered_total+ggpbi.bonus_transfered_total,
            gaming_bonus_instances.session_id=sessionID
        WHERE ggpbi.game_play_id=gamePlayID AND ggpbi.now_wager_requirement_met=1 AND ggpbi.now_used_all=0;
      
        SET @requireTransfer=0;
        SET @bonusTransfered=0;
        SET @bonusWinLockedTransfered=0;
        SET @bonusTransferedLost=0;
        SET @bonusWinLockedTransferedLost=0;

		SET @ringFencedAmount=0;
		SET @ringFencedAmountSB=0;
		SET @ringFencedAmountCasino=0;
		SET @ringFencedAmountPoker=0;
        
        SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0),
			ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
			ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
        INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
			 @ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
        FROM gaming_game_plays_bonus_instances
		LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;
        
        SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
        SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
        IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
          CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
        END IF; 
        
        -- Slow Release
        UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
        STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id
        STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON 
          gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id AND transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus')
        SET 
            ggpbi.bonus_transfered_total=LEAST(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))* 
              gaming_bonus_instances.transfer_every_amount, 
              bonus_amount_remaining+current_win_locked_amount), 
            ggpbi.bonus_transfered=LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining),
            ggpbi.bonus_win_locked_transfered=ggpbi.bonus_transfered_total-ggpbi.bonus_transfered,
            bonus_amount_remaining=bonus_amount_remaining-bonus_transfered, current_win_locked_amount=current_win_locked_amount-bonus_win_locked_transfered,  
            gaming_bonus_instances.transfer_every_x_last=gaming_bonus_instances.transfer_every_x_last+(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))*gaming_bonus_instances.transfer_every_x),
            gaming_bonus_instances.bonus_transfered_total=IFNULL(gaming_bonus_instances.bonus_transfered_total,0)+ggpbi.bonus_transfered_total,
            gaming_bonus_instances.session_id=sessionID
        WHERE ggpbi.game_play_id=gamePlayID AND ggpbi.now_release_bonus=1 AND ggpbi.now_used_all=0 AND ggpbi.now_wager_requirement_met=0;
        
        SET @requireTransfer=0;
        SET @bonusTransfered=0;
        SET @bonusWinLockedTransfered=0;
        SET @bonusTransferedLost=0;
        SET @bonusWinLockedTransferedLost=0;

		SET @ringFencedAmount=0;
		SET @ringFencedAmountSB=0;
		SET @ringFencedAmountCasino=0;
		SET @ringFencedAmountPoker=0;
        
        SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0)  ,
			ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
			ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
        INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
			 @ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
        FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
		LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

        SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
        SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
        IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
          CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
        END IF; 

      END IF; 

  END IF; 

  -- If the bonus is secured than it is no longer active
  UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
  STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
  SET gaming_bonus_instances.is_active=IF(is_active=0, 0, IF(is_secured,0,1))
  WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;           
    
  
  UPDATE gaming_sb_bets SET bet_total=bet_total-betAmount, is_processed=1, is_success=1, status_code=5 WHERE sb_bet_id=sbBetID;
    
  INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount) 
  SELECT sbBetID, sb_bet_transaction_type_id, NOW(), betAmount
  FROM gaming_sb_bet_transaction_types WHERE name='PlaceBet';

	IF (isCouponBet) THEN
		SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayID;
		CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID);
		CALL PlayReturnBonusInfoOnWin(gamePlayID);
	ELSE
		CALL CommonWalletSBReturnData(sbBetID, clientStatID);
	END IF;

  CALL NotificationEventCreate(700, sbBetID, clientStatID, 0);
  SET statusCode=0;
END root $$

DELIMITER ;

-- -------------------------------------
-- PlaceBetTypeTwoLotto.sql
-- -------------------------------------
DROP procedure IF EXISTS `PlaceBetTypeTwoLotto`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceBetTypeTwoLotto`(couponID BIGINT, sessionID BIGINT, OUT statusCode INT)
root: BEGIN
	-- Securing the bonus
    -- Added gaming_game_play_message_types
	-- Optimizations: Forcing STRAIGHT_JOINS and INDEXES 
-- Merge To INPH
-- Optimized
 
	DECLARE gamePlayID,gameRoundID, clientStatID, gameManufacturerID BIGINT;
    DECLARE bonusesLeft, wagerStatusCode, licenseTypeID INT DEFAULT 0;
	DECLARE exchangeRate DECIMAL(18,5);

	SELECT gaming_game_plays_lottery.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.client_stat_id, gaming_game_plays.game_manufacturer_id, MAX(gaming_lottery_participations.lottery_wager_status_id), gaming_lottery_coupons.license_type_id
    INTO gamePlayID, gameRoundID, clientStatID, gameManufacturerID, wagerStatusCode, licenseTypeID
    FROM gaming_game_plays_lottery FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery.game_play_id
	STRAIGHT_JOIN gaming_lottery_coupons FORCE INDEX (PRIMARY) ON gaming_lottery_coupons.lottery_coupon_id=gaming_game_plays_lottery.lottery_coupon_id
	STRAIGHT_JOIN gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id) ON gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
    WHERE gaming_game_plays_lottery.lottery_coupon_id = couponID;
    
	-- If Wager Status Code is FundsReserved Skip Validation
    IF (wagerStatusCode != 3) THEN
		IF (wagerStatusCode = 5) THEN
			CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID);
			CALL PlayReturnBonusInfoOnBet(gamePlayID);
			SET statusCode = 100;
			LEAVE root;
		ELSE 
			SET statusCode = 1;
			LEAVE root;
		END IF;
	 END IF;

	SELECT exchange_rate into exchangeRate 
	FROM gaming_client_stats
	JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
	WHERE gaming_client_stats.client_stat_id=clientStatID
	LIMIT 1;

	UPDATE gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_lottery_participations ON gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 3
    SET gaming_lottery_participations.lottery_wager_status_id = 5
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
    
    UPDATE gaming_lottery_coupons
    SET gaming_lottery_coupons.lottery_wager_status_id = 5, lottery_coupon_status_id = 2102
    WHERE gaming_lottery_coupons.lottery_coupon_id = couponID;

	UPDATE gaming_game_plays_bonus_instances 
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
	STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
	SET 
		is_secured=IF(now_wager_requirement_met=1 AND transfer_type.name!='NonReedemableBonus',1,is_secured),
		is_freebet_phase=IF(now_wager_requirement_met=1 AND transfer_type.name='NonReedemableBonus',1,is_freebet_phase),
		secured_date=IF(now_wager_requirement_met=1 AND transfer_type.name!='NonReedemableBonus',NOW(),NULL),
		gaming_bonus_instances.is_active=IF(gaming_bonus_instances.is_active=0,0,IF((now_wager_requirement_met=1 AND transfer_type.name!='NonReedemableBonus'),0,1))
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;  
    
	UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id) 
	STRAIGHT_JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
	STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
	SET 
		ggpbi.bonus_transfered_total=(
        CASE transfer_type.name
			WHEN 'All' THEN bonus_amount_remaining+current_win_locked_amount
			WHEN 'Bonus' THEN bonus_amount_remaining
			WHEN 'BonusWinLocked' THEN current_win_locked_amount
			WHEN 'UpToBonusAmount' THEN LEAST(bonus_amount_given, bonus_amount_remaining+current_win_locked_amount)
			WHEN 'UpToPercentage' THEN LEAST(bonus_amount_given*transfer_upto_percentage, bonus_amount_remaining+current_win_locked_amount)
			WHEN 'ReleaseBonus' THEN LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, bonus_amount_remaining+current_win_locked_amount)
			WHEN 'ReleaseAllBonus' THEN bonus_amount_remaining+current_win_locked_amount
			WHEN 'NonReedemableBonus' THEN current_win_locked_amount
			ELSE 0
		END),
		ggpbi.bonus_transfered=IF(transfer_type.name='BonusWinLocked' OR transfer_type.name='NonReedemableBonus', 0, LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining)),
		ggpbi.bonus_win_locked_transfered=IF(transfer_type.name='Bonus', 0, ggpbi.bonus_transfered_total-ggpbi.bonus_transfered),
		bonus_transfered_lost=IF(transfer_type.name!='NonReedemableBonus',bonus_amount_remaining-bonus_transfered,0),
		bonus_win_locked_transfered_lost=current_win_locked_amount-bonus_win_locked_transfered,
		ring_fenced_transfered = current_ring_fenced_amount,
		bonus_amount_remaining=IF(transfer_type.name!='NonReedemableBonus',0,bonus_amount_remaining),
		current_win_locked_amount=0, current_ring_fenced_amount=0,  
		gaming_bonus_instances.bonus_transfered_total=gaming_bonus_instances.bonus_transfered_total+ggpbi.bonus_transfered_total
	WHERE ggpbi.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;

	-- BonusRequirementMet
	SET @requireTransfer=0;

	SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
	INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
	FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id	
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;

	SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
	SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
	IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
		CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino ,@ringFencedAmountPoker, NULL);
	END IF; 

	-- BonusCashExchange
	UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id) 
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id
	STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON 
		gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id AND transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus')
	SET 
		ggpbi.bonus_transfered_total=LEAST(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))* -- number of transfers achieved
		gaming_bonus_instances.transfer_every_amount, -- amount to transfer each time
		bonus_amount_remaining+current_win_locked_amount), -- cannot transfer more than the bonus remaining value
		ggpbi.bonus_transfered=LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining),
		ggpbi.bonus_win_locked_transfered=ggpbi.bonus_transfered_total-ggpbi.bonus_transfered,
		bonus_amount_remaining=bonus_amount_remaining-bonus_transfered, current_win_locked_amount=current_win_locked_amount-bonus_win_locked_transfered,  -- update ggpbi
		gaming_bonus_instances.transfer_every_x_last=gaming_bonus_instances.transfer_every_x_last+(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))*gaming_bonus_instances.transfer_every_x),
		gaming_bonus_instances.bonus_transfered_total=IFNULL(gaming_bonus_instances.bonus_transfered_total,0)+ggpbi.bonus_transfered_total
	WHERE ggpbi.game_play_id=gamePlayID AND ggpbi.now_release_bonus=1 AND ggpbi.now_used_all=0 AND ggpbi.now_wager_requirement_met=0;

	SET @requireTransfer=0;

	SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0)  ,
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
	INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
	FROM gaming_game_plays_bonus_instances
	LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id	
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

	SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
	SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;

	IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
		CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino ,@ringFencedAmountPoker, NULL);
	END IF; 

    SELECT COUNT(1) AS numBonuses INTO bonusesLeft
	FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
	WHERE gaming_bonus_instances.client_stat_id=clientStatID AND is_active AND is_freebet_phase=0
	GROUP BY client_stat_id;

	UPDATE gaming_client_stats SET bet_from_real=IF(IFNULL(bonusesLeft,0)=0,0,bet_from_real) WHERE client_stat_id = clientStatID;  

	UPDATE gaming_game_plays SET is_processed=0 WHERE game_play_id=gamePlayID;

	CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID);
    CALL PlayReturnBonusInfoOnBet(gamePlayID);
	CALL NotificationEventCreate(CASE licenseTypeID WHEN 6 THEN 550	WHEN 7 THEN 560 END, couponID, clientStatID, 0);

	SET statusCode =0;
    
END$$

DELIMITER ;

-- -------------------------------------
-- PlayProcessBetsUpdatePromotionStatusesOnBet.sql
-- -------------------------------------
DROP procedure IF EXISTS `PlayProcessBetsUpdatePromotionStatusesOnBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayProcessBetsUpdatePromotionStatusesOnBet`(gamePlayProcessCounterID BIGINT)
root: BEGIN
  -- Sports Optimization
  -- Lottery Addition
  -- Removed AND condition on gaming_promotions.calculate_on_bet when checking the promotino with the highest priority 

  DECLARE promotionAwardPrizeOnAchievementEnabled, singlePromotionsEnabled, noMoreRecords TINYINT(1) DEFAULT 0;
  DECLARE contributeAllowMultiple, contributeRealMoneyOnly, sportsBookActive, lottoActive TINYINT(1) DEFAULT 0;
  DECLARE onBetTakesPrecedenced TINYINT(1) DEFAULT 0;
  DECLARE dateTimeNow DATETIME DEFAULT NOW();

  DECLARE promotionID, promotionGetCounterID, promotionRecurrenceID BIGINT DEFAULT -1;
  
  DECLARE promotionAwardOnAchievementCursor CURSOR FOR 
    SELECT pps.promotion_id, IFNULL(pps.promotion_recurrence_date_id, 0) 
    FROM gaming_game_rounds_promotion_contributions AS promotion_contributions
    JOIN gaming_promotions_player_statuses AS pps ON
      promotion_contributions.game_play_process_counter_id=gamePlayProcessCounterID AND
      promotion_contributions.promotion_player_status_id=pps.promotion_player_status_id AND
      (pps.requirement_achieved=1 AND pps.has_awarded_bonus=0)
    JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id AND gaming_promotions.is_active=1 AND 
      gaming_promotions.is_single=0 AND 
	  ((gaming_promotions.award_prize_on_achievement=1 OR gaming_promotions.award_prize_timing_type = 1) 
      AND (award_num_players=0 OR num_players_awarded<award_num_players) AND gaming_promotions.promotion_achievement_type_id NOT IN (5) )
	LEFT JOIN gaming_promotions_recurrence_dates dates ON dates.promotion_recurrence_date_id = pps.promotion_recurrence_date_id 
	WHERE (IFNULL(gaming_promotions.award_num_players_per_occurence, 9999999999) > IFNULL(dates.awarded_prize_count, 0))
    GROUP BY pps.promotion_id, IFNULL(pps.promotion_recurrence_date_id, 0);

  DECLARE promotionAwardSingleCursor CURSOR FOR 
    SELECT pps.promotion_id, IFNULL(pps.promotion_recurrence_date_id, 0) 
    FROM gaming_game_rounds_promotion_contributions AS promotion_contributions
    JOIN gaming_promotions_player_statuses AS pps ON
      promotion_contributions.game_play_process_counter_id=gamePlayProcessCounterID AND
      promotion_contributions.promotion_player_status_id=pps.promotion_player_status_id
    JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id AND gaming_promotions.is_active=1 AND 
      gaming_promotions.is_single=1 AND (award_num_players=0 OR num_players_awarded<=award_num_players) AND gaming_promotions.promotion_achievement_type_id IN (1,2)
      AND (gaming_promotions.award_prize_on_achievement=1 OR gaming_promotions.award_prize_timing_type = 1) 
      AND (gaming_promotions.single_prize_per_transaction OR (pps.requirement_achieved=1 AND pps.has_awarded_bonus=0))
	LEFT JOIN gaming_promotions_recurrence_dates dates ON dates.promotion_recurrence_date_id = pps.promotion_recurrence_date_id 
	WHERE (IFNULL(gaming_promotions.award_num_players_per_occurence, 9999999999) >= IFNULL(dates.awarded_prize_count, 0))
	AND pps.achieved_amount!=pps.single_achieved_amount_awarded
	GROUP BY pps.promotion_id, IFNULL(pps.promotion_recurrence_date_id, 0);

  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
        
  -- only process if gaming_promotions.calculate_on_bet is true
	SET @gamePlayProcessCounterID = gamePlayProcessCounterID;
	SELECT value_bool INTO contributeAllowMultiple FROM gaming_settings WHERE name='PROMOTION_ROUND_CONTRIBUTION_ALLOW_MULTIPLE'; 
	SELECT value_bool INTO contributeRealMoneyOnly FROM gaming_settings WHERE name='PROMOTION_CONTRIBUTION_REAL_MONEY_ONLY'; 
	SELECT value_bool INTO sportsBookActive FROM gaming_settings WHERE name='SPORTSBOOK_ACTIVE'; 
	SELECT value_bool INTO onBetTakesPrecedenced FROM gaming_settings WHERE name='PROMOTION_ON_BET_TAKES_PRECEDENCE'; 
	SELECT value_bool INTO singlePromotionsEnabled FROM gaming_settings WHERE name='PROMOTION_SINGLE_PROMOS_ENABLED';
	SELECT value_bool INTO lottoActive FROM gaming_settings WHERE name='LOTTO_ACTIVE'; 

	SET @round_row_count=1;
	SET @game_round_id=-1;
	SET @max_contributions_per_round=IF(contributeAllowMultiple, 10, 1); 
  

	INSERT INTO gaming_promotion_get_counter (date_added) VALUES (NOW());
	SET promotionGetCounterID=LAST_INSERT_ID();

-- UPDATE THE CURRENT OCCURENCE TO FALSE
	UPDATE gaming_game_plays_process_counter_bets 
	JOIN gaming_game_plays ON
		gaming_game_plays_process_counter_bets.game_play_process_counter_id=@gamePlayProcessCounterID AND
		gaming_game_plays_process_counter_bets.game_play_id=gaming_game_plays.game_play_id AND gaming_game_plays.payment_transaction_type_id=12 
	JOIN gaming_promotions_player_statuses AS gpps FORCE INDEX (client_open_promos) ON 
		gpps.client_stat_id=gaming_game_plays.client_stat_id AND gpps.is_active=1 AND gpps.is_current=1 AND gpps.end_date<dateTimeNow
	JOIN gaming_promotions ON gpps.promotion_id=gaming_promotions.promotion_id AND gaming_promotions.recurrence_enabled
	LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_dates FORCE INDEX (promotion_active_current) ON 
		recurrence_dates.promotion_id=gaming_promotions.promotion_id AND recurrence_dates.is_active=1 AND recurrence_dates.is_current=1 
	SET gpps.is_current=0 
	WHERE (recurrence_dates.promotion_recurrence_date_id IS NULL OR gpps.promotion_recurrence_date_id!=recurrence_dates.promotion_recurrence_date_id);

 -- INSERT AND SET THE NEW OCCURENCE TO CURRENT
	INSERT INTO gaming_promotions_player_statuses (promotion_id, child_promotion_id, client_stat_id, priority, opted_in_date, currency_id, creation_counter_id, promotion_recurrence_date_id, start_date, end_date)
	SELECT gaming_promotions.promotion_id, child_promotion.promotion_id, gaming_game_plays.client_stat_id, gaming_promotions.priority, NOW(), gcs.currency_id, promotionGetCounterID,
		recurrence_dates.promotion_recurrence_date_id, IFNULL(recurrence_dates.start_date, gaming_promotions.achievement_start_date), IFNULL(recurrence_dates.end_date, gaming_promotions.achievement_end_date)
	FROM gaming_game_plays_process_counter_bets 
	JOIN gaming_game_plays ON
		gaming_game_plays_process_counter_bets.game_play_process_counter_id=@gamePlayProcessCounterID AND
		gaming_game_plays_process_counter_bets.game_play_id=gaming_game_plays.game_play_id AND gaming_game_plays.payment_transaction_type_id=12 
	JOIN gaming_promotions ON gaming_promotions.is_active=1 AND gaming_promotions.recurrence_enabled =1
	JOIN gaming_promotions_players_opted_in AS gppo ON gppo.promotion_id = gaming_promotions.promotion_id 
		AND gppo.client_stat_id = gaming_game_plays.client_stat_id AND gppo.opted_in = 1 AND gppo.awarded_prize_count < IFNULL(gaming_promotions.award_num_times_per_player, 99999999999)
	JOIN gaming_promotions_recurrence_dates AS recurrence_dates FORCE INDEX (promotion_active_current) ON 
		recurrence_dates.promotion_id=gaming_promotions.promotion_id AND recurrence_dates.is_active=1 AND recurrence_dates.is_current=1 
		AND (recurrence_dates.awarded_prize_count < IFNULL(gaming_promotions.award_num_players_per_occurence, 99999999999))
	JOIN gaming_client_stats AS gcs ON gcs.client_stat_id = gaming_game_plays.client_stat_id AND gcs.is_active=1
	LEFT JOIN gaming_player_selections_player_cache AS CS ON CS.client_stat_id=gaming_game_plays.client_stat_id AND gaming_promotions.player_selection_id = CS.player_selection_id
	LEFT JOIN gaming_promotions AS child_promotion ON child_promotion.parent_promotion_id=gaming_promotions.promotion_id AND child_promotion.is_current=1
	LEFT JOIN gaming_promotions_player_statuses AS gpps ON gpps.promotion_id=gaming_promotions.promotion_id AND gpps.client_stat_id=gaming_game_plays.client_stat_id AND gpps.is_current=1
	WHERE (gaming_promotions.achievement_end_date>=NOW() AND ((gaming_promotions.need_to_opt_in_flag=0 AND IFNULL(gppo.creation_counter_id,0)=promotionGetCounterID) 
		OR (gpps.client_stat_id IS NULL AND gppo.client_stat_id IS NOT NULL AND gppo.opted_in = 1 AND 
		(gaming_promotions.auto_opt_in_next = 1 OR (gaming_promotions.auto_opt_in_next = 0 AND gaming_promotions.need_to_opt_in_flag = 0)))) AND 
		(gaming_promotions.can_opt_in=1 AND gaming_promotions.num_players_opted_in<gaming_promotions.max_players)) 
		AND (IFNULL(CS.player_in_selection, PlayerSelectionIsPlayerInSelectionCached(gaming_promotions.player_selection_id, gaming_game_plays.client_stat_id))=1 OR gaming_promotions.auto_opt_in_next = 1)
		AND gpps.promotion_player_status_id IS NULL ;

 -- CASINO --
	INSERT INTO gaming_game_rounds_promotion_contributions(game_round_id, promotion_id, timestamp, promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet, win, loss, game_play_process_counter_id)
	SELECT game_round_id, promotion_id, NOW(), promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet_total, win_total, loss_total, @gamePlayProcessCounterID
	FROM 
	(
		SELECT PP.*, @round_row_count:=IF(game_round_id!=@game_round_id, 1, @round_row_count+1) AS round_row_count, @game_round_id:=IF(game_round_id!=@game_round_id, game_round_id, @game_round_id)
		FROM
		(
			SELECT gaming_game_rounds.game_round_id, pps.promotion_id, pps.promotion_player_status_id, ppsd.promotion_player_status_day_id, gaming_promotions_games.promotion_wgr_req_weight, gaming_promotions_achievement_types.name AS promotion_type, gaming_promotions.calculate_on_bet,
				LEAST(IFNULL(wager_restrictions.max_wager_contibution, 1000000000000), LEAST(IFNULL(wager_restrictions.max_wager_contibution_before_weight, 1000000000000), IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, bet_real, bet_total))*gaming_promotions_games.promotion_wgr_req_weight, IF(gaming_promotions.is_single AND gaming_promotions_achievement_types.name='Bet'AND gppa.max_cap IS NOT NULL, gppa.max_cap, 1000000000000)) AS bet_total, 
				0 AS win_total, 
				0 AS loss_total
			FROM gaming_game_plays_process_counter_bets 
			JOIN gaming_game_plays ON
				gaming_game_plays_process_counter_bets.game_play_process_counter_id=@gamePlayProcessCounterID AND
				gaming_game_plays_process_counter_bets.game_play_id=gaming_game_plays.game_play_id AND gaming_game_plays.payment_transaction_type_id=12 
			JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id AND gaming_game_rounds.game_round_type_id=1 
			JOIN gaming_promotions ON gaming_promotions.is_active=1 AND (gaming_game_rounds.date_time_start BETWEEN achievement_start_date AND achievement_end_date)
					-- AND  gaming_promotions.calculate_on_bet -- This needs to be removed since we want to join with the other promotions and check that the promotion with calculate on bet has the highest priority
			JOIN gaming_promotions_achievement_types ON 
				gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
			JOIN gaming_promotions_player_statuses AS pps FORCE INDEX (promotion_client_active_current) ON
				(pps.promotion_id=gaming_promotions.promotion_id AND
				pps.client_stat_id=gaming_game_rounds.client_stat_id AND pps.is_active=1 AND pps.is_current = 1 AND (IF(gaming_promotions.recurrence_enabled = 1, (gaming_game_rounds.date_time_start BETWEEN pps.start_date AND pps.end_date), 1=1)))
			JOIN gaming_promotions_games ON 
				gaming_promotions.promotion_id=gaming_promotions_games.promotion_id AND
				gaming_game_rounds.operator_game_id=gaming_promotions_games.operator_game_id
			LEFT JOIN gaming_promotions_achievement_amounts ON
				gaming_promotions.promotion_id=gaming_promotions_achievement_amounts.promotion_id AND
				pps.currency_id=gaming_promotions_achievement_amounts.currency_id AND
				(gaming_promotions.is_single=0 OR ( 
				(gaming_promotions.promotion_achievement_type_id=1 AND (IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, bet_real, bet_total)*gaming_promotions_games.promotion_wgr_req_weight)>=gaming_promotions_achievement_amounts.amount)

				))
			LEFT JOIN gaming_promotions_achievement_rounds ON
				gaming_promotions.promotion_id=gaming_promotions_achievement_rounds.promotion_id AND
				pps.currency_id=gaming_promotions_achievement_rounds.currency_id
			LEFT JOIN gaming_promotions_status_days ON
				gaming_promotions.promotion_id=gaming_promotions_status_days.promotion_id AND (DATE(gaming_game_rounds.date_time_start)=gaming_promotions_status_days.day_start_time)    
			LEFT JOIN gaming_promotions_player_statuses_daily AS ppsd ON
				pps.promotion_player_status_id=ppsd.promotion_player_status_id AND
				gaming_promotions_status_days.promotion_status_day_id=ppsd.promotion_status_day_id
			LEFT JOIN gaming_promotion_wager_restrictions AS wager_restrictions ON
				wager_restrictions.promotion_id=gaming_promotions.promotion_id AND
				wager_restrictions.currency_id=pps.currency_id
			LEFT JOIN gaming_promotions_prize_amounts AS gppa ON
				gaming_promotions.promotion_id=gppa.promotion_id AND pps.currency_id=gppa.currency_id 
			WHERE
				(singlePromotionsEnabled OR gaming_promotions.is_single=0) AND
				(gaming_promotions_games.promotion_id IS NOT NULL) AND 

				(pps.promotion_recurrence_date_id IS NULL OR
				(gaming_promotions_status_days.promotion_recurrence_date_id IS NULL OR (pps.promotion_recurrence_date_id=gaming_promotions_status_days.promotion_recurrence_date_id))) AND

				((gaming_promotions_achievement_types.is_amount_achievement AND gaming_promotions_achievement_amounts.promotion_id IS NOT NULL) OR 
				(gaming_promotions_achievement_types.is_round_achievement AND gaming_promotions_achievement_rounds.promotion_id IS NOT NULL AND 
				IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, gaming_game_rounds.bet_real, gaming_game_rounds.bet_total)>=gaming_promotions_achievement_rounds.min_bet_amount) 
				) AND pps.requirement_achieved=0 AND IFNULL(ppsd.daily_requirement_achieved, 0)=0
			ORDER BY gaming_game_rounds.game_round_id, IF(onBetTakesPrecedenced AND gaming_promotions_achievement_types.name='Bet', pps.priority-1000, pps.priority) ASC, pps.opted_in_date DESC 
		) AS PP
	) AS PP
	WHERE PP.promotion_type='BET' AND pp.calculate_on_bet AND round_row_count<=@max_contributions_per_round
	GROUP BY game_round_id, promotion_player_status_id
	ON DUPLICATE KEY UPDATE promotion_player_status_day_id=VALUES(promotion_player_status_day_id), promotion_wgr_req_weight=VALUES(promotion_wgr_req_weight), bet=VALUES(bet), win=VALUES(win), loss=VALUES(loss), game_play_process_counter_id=VALUES(game_play_process_counter_id);   

	IF (lottoActive) THEN
    
		SET @round_row_count=1;
		SET @game_round_id=-1;
		SET @max_contributions_per_round=IF(contributeAllowMultiple, 10, 1); 
				
		INSERT INTO gaming_game_rounds_promotion_contributions(game_round_id, promotion_id, timestamp, promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet, win, loss, game_play_process_counter_id)
		SELECT game_round_id, promotion_id, NOW(), promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet_total, win_total, loss_total, @gamePlayProcessCounterID
		FROM 
		(
			SELECT PP.*, @round_row_count:=IF(game_round_id!=@game_round_id, 1, @round_row_count+1) AS round_row_count, @game_round_id:=IF(game_round_id!=@game_round_id, game_round_id, @game_round_id)
			FROM
			(
				SELECT gaming_game_rounds.game_round_id, pps.promotion_id, pps.promotion_player_status_id, ppsd.promotion_player_status_day_id, gaming_promotions_games.promotion_wgr_req_weight, gaming_promotions_achievement_types.name AS promotion_type, gaming_promotions.calculate_on_bet,
					LEAST(IFNULL(wager_restrictions.max_wager_contibution, 1000000000000), LEAST(IFNULL(wager_restrictions.max_wager_contibution_before_weight, 1000000000000), IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only,  gaming_game_rounds.bet_real,  gaming_game_rounds.bet_total))*gaming_promotions_games.promotion_wgr_req_weight, IF(gaming_promotions.is_single AND gaming_promotions_achievement_types.name='Bet'AND gppa.max_cap IS NOT NULL, gppa.max_cap, 1000000000000)) AS bet_total, 
					0 AS win_total, 
					0 AS loss_total
				FROM gaming_game_plays_process_counter_bets 
				JOIN gaming_game_plays ON
					gaming_game_plays_process_counter_bets.game_play_process_counter_id=@gamePlayProcessCounterID AND
					gaming_game_plays_process_counter_bets.game_play_id=gaming_game_plays.game_play_id AND gaming_game_plays.payment_transaction_type_id=12 
				JOIN gaming_game_rounds AS bet_round ON gaming_game_plays.game_round_id=bet_round.game_round_id AND bet_round.game_round_type_id=7 
				JOIN gaming_game_rounds_lottery AS parent_round ON parent_round.game_round_id = bet_round.game_round_id AND is_parent_round=1
				JOIN gaming_game_rounds_lottery AS child_round ON child_round.parent_game_round_id = parent_round.game_round_id
				JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id = child_round.game_round_id
				JOIN gaming_promotions ON gaming_promotions.is_active=1 AND (gaming_game_rounds.date_time_start BETWEEN achievement_start_date AND achievement_end_date)
					-- AND  gaming_promotions.calculate_on_bet -- This needs to be removed since we want to join with the other promotions and check that the promotion with calculate on bet has the highest priority
				JOIN gaming_promotions_achievement_types ON 
					gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
				JOIN gaming_promotions_player_statuses AS pps FORCE INDEX (promotion_client_active_current) ON
					(pps.promotion_id=gaming_promotions.promotion_id AND
					pps.client_stat_id=gaming_game_rounds.client_stat_id AND pps.is_active=1 AND pps.is_current = 1  AND (IF(gaming_promotions.recurrence_enabled = 1, (gaming_game_rounds.date_time_start BETWEEN pps.start_date AND pps.end_date), 1=1)))
				JOIN gaming_promotions_games ON 
					gaming_promotions.promotion_id=gaming_promotions_games.promotion_id AND
					gaming_game_rounds.operator_game_id=gaming_promotions_games.operator_game_id
				LEFT JOIN gaming_promotions_achievement_amounts ON
					gaming_promotions.promotion_id=gaming_promotions_achievement_amounts.promotion_id AND
					pps.currency_id=gaming_promotions_achievement_amounts.currency_id AND
					(gaming_promotions.is_single=0 OR 
						( 
							gaming_promotions.promotion_achievement_type_id=1 AND 
								(
									IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only,  gaming_game_rounds.bet_real,  gaming_game_rounds.bet_total)
									*gaming_promotions_games.promotion_wgr_req_weight
								) >=gaming_promotions_achievement_amounts.amount
						)
                    )
				LEFT JOIN gaming_promotions_achievement_rounds ON
					gaming_promotions.promotion_id=gaming_promotions_achievement_rounds.promotion_id AND
					pps.currency_id=gaming_promotions_achievement_rounds.currency_id
				LEFT JOIN gaming_promotions_status_days ON
					gaming_promotions.promotion_id=gaming_promotions_status_days.promotion_id AND (DATE(gaming_game_rounds.date_time_start)=gaming_promotions_status_days.day_start_time)    
				LEFT JOIN gaming_promotions_player_statuses_daily AS ppsd ON
					pps.promotion_player_status_id=ppsd.promotion_player_status_id AND
					gaming_promotions_status_days.promotion_status_day_id=ppsd.promotion_status_day_id
				LEFT JOIN gaming_promotion_wager_restrictions AS wager_restrictions ON
					wager_restrictions.promotion_id=gaming_promotions.promotion_id AND
					wager_restrictions.currency_id=pps.currency_id
				LEFT JOIN gaming_promotions_prize_amounts AS gppa ON
					gaming_promotions.promotion_id=gppa.promotion_id AND pps.currency_id=gppa.currency_id 
				WHERE
					(singlePromotionsEnabled OR gaming_promotions.is_single=0) AND
					(gaming_promotions_games.promotion_id IS NOT NULL) AND 
					(pps.promotion_recurrence_date_id IS NULL OR
					(gaming_promotions_status_days.promotion_recurrence_date_id IS NULL OR (pps.promotion_recurrence_date_id=gaming_promotions_status_days.promotion_recurrence_date_id))) AND
					((gaming_promotions_achievement_types.is_amount_achievement AND gaming_promotions_achievement_amounts.promotion_id IS NOT NULL) OR 
					(gaming_promotions_achievement_types.is_round_achievement AND gaming_promotions_achievement_rounds.promotion_id IS NOT NULL AND 
					IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, gaming_game_rounds.bet_real, gaming_game_rounds.bet_total)>=gaming_promotions_achievement_rounds.min_bet_amount) 
					) AND pps.requirement_achieved=0 AND IFNULL(ppsd.daily_requirement_achieved, 0)=0
				ORDER BY gaming_game_rounds.game_round_id, IF(onBetTakesPrecedenced AND gaming_promotions_achievement_types.name='Bet', pps.priority-1000, pps.priority) ASC, pps.opted_in_date DESC 
			) AS PP
		) AS PP
		WHERE PP.promotion_type='BET' AND pp.calculate_on_bet AND round_row_count<=@max_contributions_per_round
		GROUP BY game_round_id, promotion_player_status_id
		ON DUPLICATE KEY UPDATE promotion_player_status_day_id=VALUES(promotion_player_status_day_id), promotion_wgr_req_weight=VALUES(promotion_wgr_req_weight), bet=VALUES(bet), win=VALUES(win), loss=VALUES(loss), game_play_process_counter_id=VALUES(game_play_process_counter_id);   

	END IF;
    
  
  IF (sportsBookActive) THEN
    SET @round_row_count=1;
    SET @game_round_id=-1;
    SET @max_contributions_per_round=IF(contributeAllowMultiple, 10, 1); 
  
    INSERT INTO gaming_game_rounds_promotion_contributions(game_round_id, promotion_id, timestamp, promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet, win, loss, game_play_process_counter_id)
    SELECT game_round_id, promotion_id, NOW(), promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet_total, win_total, loss_total, @gamePlayProcessCounterID
    FROM 
    (
      SELECT PP.*, @round_row_count:=IF(game_round_id!=@game_round_id, 1, @round_row_count+1) AS round_row_count, @game_round_id:=IF(game_round_id!=@game_round_id, game_round_id, @game_round_id)
      FROM
      (
        SELECT gaming_game_rounds.game_round_id, pps.promotion_id, pps.promotion_player_status_id, ppsd.promotion_player_status_day_id, IFNULL(sb_weights.weight, sb_weights_multiple.weight) AS promotion_wgr_req_weight, gaming_promotions_achievement_types.name AS promotion_type,
        LEAST(IFNULL(wager_restrictions.max_wager_contibution, 10000000000), LEAST(IFNULL(wager_restrictions.max_wager_contibution_before_weight, 10000000000), 
			IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, bet_real, bet_total))*IFNULL(sb_weights.weight, sb_weights_multiple.weight), 
            IF(gaming_promotions.is_single AND gaming_promotions_achievement_types.name='Bet' AND gppa.max_cap IS NOT NULL, gppa.max_cap, 1000000000000))  AS bet_total, 
        0 AS win_total, 
        0 AS loss_total
        FROM gaming_game_plays_process_counter_bets 
         JOIN gaming_game_plays ON
          gaming_game_plays_process_counter_bets.game_play_process_counter_id=@gamePlayProcessCounterID AND
          gaming_game_plays_process_counter_bets.game_play_id=gaming_game_plays.game_play_id AND gaming_game_plays.payment_transaction_type_id=12 
        JOIN gaming_game_rounds ON gaming_game_rounds.sb_bet_id=gaming_game_plays.sb_bet_id AND gaming_game_rounds.sb_extra_id IS NOT NULL AND gaming_game_rounds.game_round_type_id IN (4,5) 
        JOIN gaming_promotions ON gaming_promotions.is_active=1 AND (gaming_game_rounds.date_time_start BETWEEN achievement_start_date AND achievement_end_date)
          AND gaming_promotions.promotion_achievement_type_id NOT IN (5) 
		  	-- AND  gaming_promotions.calculate_on_bet -- This needs to be removed since we want to join with the other promotions and check that the promotion with calculate on bet has the highest priority
        JOIN gaming_promotions_achievement_types ON 
          gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
        JOIN gaming_promotions_player_statuses AS pps FORCE INDEX (promotion_client_active_current) ON
          (pps.promotion_id=gaming_promotions.promotion_id AND
          pps.client_stat_id=gaming_game_rounds.client_stat_id AND pps.is_active=1 AND pps.is_current = 1  AND (IF(gaming_promotions.recurrence_enabled = 1, (gaming_game_rounds.date_time_start BETWEEN pps.start_date AND pps.end_date), 1=1)))
        LEFT JOIN gaming_sb_bet_singles ON gaming_game_rounds.game_round_type_id=4 AND
          gaming_game_rounds.sb_bet_id=gaming_sb_bet_singles.sb_bet_id AND gaming_game_rounds.sb_extra_id=gaming_sb_bet_singles.sb_selection_id
        LEFT JOIN gaming_sb_selections ON gaming_sb_selections.sb_selection_id=gaming_game_rounds.sb_extra_id
        LEFT JOIN gaming_promotions_wgr_sb_weights AS sb_weights ON gaming_promotions.promotion_id=sb_weights.promotion_id AND gaming_game_rounds.game_round_type_id IN (4) AND 
        (
          (sb_weights.sb_entity_type_id=1 AND sb_weights.sb_entity_id=gaming_sb_selections.sb_sport_id)  OR 
          (sb_weights.sb_entity_type_id=2 AND sb_weights.sb_entity_id=gaming_sb_selections.sb_region_id) OR 
          (sb_weights.sb_entity_type_id=3 AND sb_weights.sb_entity_id=gaming_sb_selections.sb_group_id)  OR
          (sb_weights.sb_entity_type_id=4 AND sb_weights.sb_entity_id=gaming_sb_selections.sb_event_id)  OR 
          (sb_weights.sb_entity_type_id=5 AND sb_weights.sb_entity_id=gaming_sb_selections.sb_market_id)
        ) AND (gaming_sb_bet_singles.odd>=sb_weights.min_odd AND (sb_weights.max_odd IS NULL OR gaming_sb_bet_singles.odd<sb_weights.max_odd)) 
          AND (gaming_promotions.min_odd IS NULL OR gaming_sb_bet_singles.odd>=gaming_promotions.min_odd)
        LEFT JOIN
        (
          SELECT gaming_game_rounds.game_round_id, sb_weights.promotion_id, gaming_sb_bet_multiples.odd, AVG(sb_weights.weight) AS weight
            FROM gaming_game_plays_process_counter_bets 
          JOIN gaming_game_plays ON
            gaming_game_plays_process_counter_bets.game_play_process_counter_id=@gamePlayProcessCounterID AND
            gaming_game_plays_process_counter_bets.game_play_id=gaming_game_plays.game_play_id AND gaming_game_plays.payment_transaction_type_id=12 
          JOIN gaming_game_rounds ON
			 gaming_game_rounds.sb_bet_id=gaming_game_plays.sb_bet_id AND gaming_game_rounds.sb_extra_id IS NOT NULL AND gaming_game_rounds.game_round_type_id IN (5)           
		   JOIN gaming_promotions ON gaming_promotions.is_active=1 AND (gaming_game_rounds.date_time_start BETWEEN achievement_start_date AND achievement_end_date)
            AND gaming_promotions.promotion_achievement_type_id NOT IN (5)
          JOIN gaming_sb_bet_multiples ON gaming_game_rounds.sb_bet_id=gaming_sb_bet_multiples.sb_bet_id AND gaming_game_rounds.sb_extra_id=gaming_sb_bet_multiples.sb_multiple_type_id
          JOIN gaming_game_plays_sb FORCE INDEX (sb_bet_entry_id) ON gaming_game_plays_sb.sb_bet_entry_id=gaming_sb_bet_multiples.sb_bet_multiple_id
			AND gaming_game_plays_sb.game_round_id=gaming_game_rounds.game_round_id
          JOIN gaming_promotions_wgr_sb_weights AS sb_weights ON gaming_promotions.promotion_id=sb_weights.promotion_id AND (
            (sb_weights.sb_entity_type_id=1 AND sb_weights.sb_entity_id=gaming_game_plays_sb.sb_sport_id)  OR 
            (sb_weights.sb_entity_type_id=2 AND sb_weights.sb_entity_id=gaming_game_plays_sb.sb_region_id) OR 
            (sb_weights.sb_entity_type_id=3 AND sb_weights.sb_entity_id=gaming_game_plays_sb.sb_group_id)  OR
            (sb_weights.sb_entity_type_id=4 AND sb_weights.sb_entity_id=gaming_game_plays_sb.sb_event_id)  OR 
            (sb_weights.sb_entity_type_id=5 AND sb_weights.sb_entity_id=gaming_game_plays_sb.sb_market_id)
          ) AND (gaming_sb_bet_multiples.odd>=sb_weights.min_odd AND (sb_weights.max_odd IS NULL OR gaming_sb_bet_multiples.odd<sb_weights.max_odd))
          GROUP BY sb_weights.promotion_id, gaming_game_rounds.game_round_id 
        ) AS sb_weights_multiple ON gaming_game_rounds.game_round_id=sb_weights_multiple.game_round_id AND 
          (gaming_promotions.promotion_id=sb_weights_multiple.promotion_id AND pps.promotion_id=sb_weights_multiple.promotion_id) AND
          (gaming_promotions.min_odd IS NULL OR sb_weights_multiple.odd>=gaming_promotions.min_odd)
        LEFT JOIN gaming_promotions_achievement_amounts ON
          gaming_promotions.promotion_id=gaming_promotions_achievement_amounts.promotion_id AND
          pps.currency_id=gaming_promotions_achievement_amounts.currency_id AND
		  (gaming_promotions.is_single=0 OR ( 
			(gaming_promotions.promotion_achievement_type_id=1 AND (IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, bet_real, bet_total)*IFNULL(sb_weights.weight, sb_weights_multiple.weight))>=gaming_promotions_achievement_amounts.amount) OR
			(gaming_promotions.promotion_achievement_type_id=2 AND (IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, win_real-bet_real, win_total-bet_total)*IFNULL(sb_weights.weight, sb_weights_multiple.weight))>=gaming_promotions_achievement_amounts.amount)
		  ))
        LEFT JOIN gaming_promotions_achievement_rounds ON
          gaming_promotions.promotion_id=gaming_promotions_achievement_rounds.promotion_id AND
          pps.currency_id=gaming_promotions_achievement_rounds.currency_id
        LEFT JOIN gaming_promotions_status_days ON
          gaming_promotions.promotion_id=gaming_promotions_status_days.promotion_id AND (DATE(gaming_game_rounds.date_time_start)=gaming_promotions_status_days.day_start_time)    
        LEFT JOIN gaming_promotions_player_statuses_daily AS ppsd ON
          pps.promotion_player_status_id=ppsd.promotion_player_status_id AND
          gaming_promotions_status_days.promotion_status_day_id=ppsd.promotion_status_day_id
        LEFT JOIN gaming_promotion_wager_restrictions AS wager_restrictions ON
          wager_restrictions.promotion_id=gaming_promotions.promotion_id AND
          wager_restrictions.currency_id=pps.currency_id
		LEFT JOIN gaming_promotions_prize_amounts AS gppa ON
		  gaming_promotions.promotion_id=gppa.promotion_id AND pps.currency_id=gppa.currency_id 
        WHERE
            (singlePromotionsEnabled OR gaming_promotions.is_single=0) AND
		    (pps.promotion_recurrence_date_id IS NULL OR
			(gaming_promotions_status_days.promotion_recurrence_date_id IS NULL OR (pps.promotion_recurrence_date_id=gaming_promotions_status_days.promotion_recurrence_date_id))) AND
        
          ((gaming_promotions_achievement_types.is_amount_achievement AND gaming_promotions_achievement_amounts.promotion_id IS NOT NULL) OR 
            (gaming_promotions_achievement_types.is_round_achievement AND gaming_promotions_achievement_rounds.promotion_id IS NOT NULL AND 
            IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, gaming_game_rounds.bet_real, gaming_game_rounds.bet_total)>=gaming_promotions_achievement_rounds.min_bet_amount) 
          ) AND pps.requirement_achieved=0 AND IFNULL(ppsd.daily_requirement_achieved, 0)=0 AND
          (sb_weights.weight IS NOT NULL OR sb_weights_multiple.weight IS NOT NULL)
        ORDER BY gaming_game_rounds.game_round_id, IF(onBetTakesPrecedenced AND gaming_promotions_achievement_types.name='Bet', pps.priority-1000, pps.priority) ASC, pps.opted_in_date DESC 
      ) AS PP
    ) AS PP
    WHERE PP.promotion_type='BET' AND round_row_count<=@max_contributions_per_round 
    GROUP BY game_round_id, promotion_player_status_id
    ON DUPLICATE KEY UPDATE promotion_player_status_day_id=VALUES(promotion_player_status_day_id), promotion_wgr_req_weight=VALUES(promotion_wgr_req_weight), bet=VALUES(bet), win=VALUES(win), loss=VALUES(loss), game_play_process_counter_id=VALUES(game_play_process_counter_id);  
  
  END IF;
  
  
  UPDATE gaming_promotions_player_statuses_daily AS ppsd
  JOIN
  (
    SELECT ppsd.promotion_player_status_day_id, gaming_promotions_achievement_types.name AS ach_type, 
      gaming_promotions_achievement_amounts.amount AS ach_amount, gaming_promotions_achievement_rounds.num_rounds AS ach_num_rounds,
      SUM(promotion_contributions.bet) AS bet_total, SUM(promotion_contributions.win) AS win_total, SUM(promotion_contributions.loss) AS loss_total, SUM(1) AS rounds
    FROM gaming_game_rounds_promotion_contributions AS promotion_contributions 
    JOIN gaming_promotions_player_statuses AS pps ON 
      promotion_contributions.game_play_process_counter_id=@gamePlayProcessCounterID AND
      promotion_contributions.promotion_player_status_id=pps.promotion_player_status_id
    JOIN gaming_promotions_player_statuses_daily AS ppsd ON 
      promotion_contributions.promotion_player_status_day_id=ppsd.promotion_player_status_day_id
    JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id
    JOIN gaming_promotions_achievement_types ON 
      gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
    LEFT JOIN gaming_promotions_achievement_amounts ON
      gaming_promotions.promotion_id=gaming_promotions_achievement_amounts.promotion_id AND
      pps.currency_id=gaming_promotions_achievement_amounts.currency_id
    LEFT JOIN gaming_promotions_achievement_rounds ON
      gaming_promotions.promotion_id=gaming_promotions_achievement_rounds.promotion_id AND
      pps.currency_id=gaming_promotions_achievement_rounds.currency_id
    GROUP BY ppsd.promotion_player_status_day_id  
  ) AS Totals ON ppsd.promotion_player_status_day_id=Totals.promotion_player_status_day_id
  SET 
    ppsd.day_bet=ppsd.day_bet+Totals.bet_total,
    ppsd.day_win=ppsd.day_win+Totals.win_total,
    ppsd.day_loss=ppsd.day_loss+Totals.loss_total,
    ppsd.day_num_rounds=ppsd.day_num_rounds+Totals.rounds,
    ppsd.daily_requirement_achieved_temp=ppsd.daily_requirement_achieved,
    ppsd.daily_requirement_achieved=IF(ppsd.daily_requirement_achieved=1,1,
      CASE 
        WHEN ach_type='BET' THEN (ppsd.day_bet+Totals.bet_total) >= ach_amount
        WHEN ach_type='WIN' THEN (ppsd.day_win+Totals.win_total) >= ach_amount
        WHEN ach_type='LOSS' THEN (ppsd.day_loss+Totals.loss_total) >= ach_amount
        WHEN ach_type='ROUNDS' THEN (ppsd.day_num_rounds+Totals.rounds) >= ach_num_rounds
        ELSE 0
      END),
    ppsd.achieved_amount=GREATEST(0, ROUND(
      CASE 
        WHEN ach_type='BET' THEN LEAST(ppsd.day_bet+Totals.bet_total, ach_amount)
        WHEN ach_type='WIN' THEN LEAST(ppsd.day_win+Totals.win_total, ach_amount)
        WHEN ach_type='LOSS' THEN LEAST(ppsd.day_loss+Totals.loss_total, ach_amount)
        WHEN ach_type='ROUNDS' THEN LEAST(ppsd.day_num_rounds+Totals.rounds, ach_num_rounds)
        ELSE 0
      END, 0)),  
    ppsd.achieved_percentage=GREATEST(0, IFNULL(LEAST(1, ROUND(IF(ppsd.daily_requirement_achieved=1,1,
      CASE 
        WHEN ach_type='BET' THEN (ppsd.day_bet+Totals.bet_total) / ach_amount 
        WHEN ach_type='WIN' THEN (ppsd.day_win+Totals.win_total) / ach_amount 
        WHEN ach_type='LOSS' THEN (ppsd.day_loss+Totals.loss_total) / ach_amount
        WHEN ach_type='ROUNDS' THEN (ppsd.day_num_rounds+Totals.rounds) / ach_num_rounds 
        ELSE 0
      END), 4)), 0));  
      
  
  UPDATE gaming_promotions_player_statuses_daily AS ppsd
  JOIN
  (
    SELECT ppsd.promotion_player_status_day_id
    FROM gaming_game_rounds_promotion_contributions AS promotion_contributions 
    JOIN gaming_promotions_player_statuses AS pps ON 
      promotion_contributions.game_play_process_counter_id=@gamePlayProcessCounterID AND
      promotion_contributions.promotion_player_status_id=pps.promotion_player_status_id
    JOIN gaming_promotions_player_statuses_daily AS ppsd ON promotion_contributions.promotion_player_status_day_id=ppsd.promotion_player_status_day_id
    JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id
    GROUP BY ppsd.promotion_player_status_day_id  
  ) AS Totals ON ppsd.promotion_player_status_day_id=Totals.promotion_player_status_day_id
  JOIN gaming_promotions_status_days AS psd ON ppsd.promotion_status_day_id=psd.promotion_status_day_id 
  
  JOIN gaming_promotions_player_statuses_daily AS c_ppsd ON c_ppsd.promotion_player_status_id=ppsd.promotion_player_status_id
  JOIN gaming_promotions_status_days AS c_psd ON 
    c_ppsd.promotion_status_day_id=c_psd.promotion_status_day_id AND
    ((psd.day_no=1 AND c_psd.day_no=1) OR (psd.day_no>1 AND c_psd.day_no=psd.day_no-1))
  SET
    ppsd.conseq_cur=c_ppsd.conseq_cur+1
  WHERE
    ppsd.daily_requirement_achieved=1 AND ppsd.daily_requirement_achieved_temp=0; 
  
  SET @numDaysAchieved=0;  
    
  
  UPDATE 
  (
    SELECT pps.promotion_player_status_id, gaming_promotions_achievement_types.name AS ach_type, 
      achievement_daily_flag, achievement_daily_consequetive_flag, achievement_days_num,
      gaming_promotions_achievement_amounts.amount AS ach_amount, gaming_promotions_achievement_rounds.num_rounds AS ach_num_rounds,
      SUM(promotion_contributions.bet) AS bet_total, SUM(promotion_contributions.win) AS win_total, SUM(promotion_contributions.loss) AS loss_total, SUM(1) AS rounds
    FROM gaming_game_rounds_promotion_contributions AS promotion_contributions 
    JOIN gaming_promotions_player_statuses AS pps ON 
      promotion_contributions.game_play_process_counter_id=@gamePlayProcessCounterID AND
      promotion_contributions.promotion_player_status_id=pps.promotion_player_status_id
    JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id
    JOIN gaming_promotions_achievement_types ON gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
    LEFT JOIN gaming_promotions_achievement_amounts ON
      gaming_promotions.promotion_id=gaming_promotions_achievement_amounts.promotion_id AND
      pps.currency_id=gaming_promotions_achievement_amounts.currency_id
    LEFT JOIN gaming_promotions_achievement_rounds ON
      gaming_promotions.promotion_id=gaming_promotions_achievement_rounds.promotion_id AND
      pps.currency_id=gaming_promotions_achievement_rounds.currency_id
    GROUP BY pps.promotion_player_status_id  
  ) AS Totals 
  STRAIGHT_JOIN gaming_promotions_player_statuses AS pps ON pps.promotion_player_status_id=Totals.promotion_player_status_id
  STRAIGHT_JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id
  LEFT JOIN gaming_promotions_prize_amounts AS prize_amount ON pps.promotion_id = prize_amount.promotion_id AND pps.currency_id=prize_amount.currency_id
  SET 
    gaming_promotions.player_statuses_used=1,
    pps.total_bet=pps.total_bet+Totals.bet_total, 
    pps.total_win=pps.total_win+Totals.win_total,
    pps.total_loss=pps.total_loss+Totals.loss_total,
    pps.num_rounds=pps.num_rounds+Totals.rounds,
	pps.single_achieved_num=LEAST(IF(gaming_promotions.is_single, single_achieved_num+Totals.rounds, pps.single_achieved_num), gaming_promotions.single_repeat_for),
    pps.requirement_achieved=IF(pps.requirement_achieved=1,1, IF (gaming_promotions.achieved_disabled, 0,
      CASE
		WHEN gaming_promotions.is_single THEN
		 (gaming_promotions.single_repeat_for=LEAST(pps.single_achieved_num+Totals.rounds, gaming_promotions.single_repeat_for))
        WHEN gaming_promotions.achievement_daily_flag=0 THEN
          CASE 
            WHEN ach_type='BET' THEN (pps.total_bet+Totals.bet_total) >= ach_amount
            WHEN ach_type='WIN' THEN (pps.total_win+Totals.win_total) >= ach_amount
            WHEN ach_type='LOSS' THEN (pps.total_loss+Totals.loss_total) >= ach_amount
            WHEN ach_type='ROUNDS' THEN (pps.num_rounds+Totals.rounds) >= ach_num_rounds
            ELSE 0
          END  
        WHEN gaming_promotions.achievement_daily_flag=1 AND gaming_promotions.achievement_daily_consequetive_flag=0 THEN
          (
            SELECT @numDaysAchieved:=LEAST(COUNT(1), gaming_promotions.achievement_days_num) AS achievement_days_cur
            FROM gaming_promotions_player_statuses_daily
            WHERE pps.promotion_player_status_id=gaming_promotions_player_statuses_daily.promotion_player_status_id AND gaming_promotions_player_statuses_daily.daily_requirement_achieved=1
          ) >= gaming_promotions.achievement_days_num
        WHEN gaming_promotions.achievement_daily_flag=1 AND gaming_promotions.achievement_daily_consequetive_flag=1 THEN 
          (
            SELECT @numDaysAchieved:=LEAST(MAX(conseq_cur), gaming_promotions.achievement_days_num)
            FROM gaming_promotions_player_statuses_daily
            WHERE pps.promotion_player_status_id=gaming_promotions_player_statuses_daily.promotion_player_status_id
            
          ) >= gaming_promotions.achievement_days_num
      END)),
    pps.achieved_amount=GREATEST(0, ROUND(
      IF (gaming_promotions.achievement_daily_flag=0,
        CASE 
		  WHEN ach_type='BET' AND gaming_promotions.is_single THEN pps.total_bet+LEAST(Totals.bet_total, prize_amount.max_cap*Totals.rounds)
          WHEN ach_type='WIN' AND gaming_promotions.is_single THEN pps.total_win+LEAST(Totals.win_total, prize_amount.max_cap*Totals.rounds)
		  WHEN ach_type='BET' THEN LEAST(pps.total_bet+Totals.bet_total, ach_amount)
          WHEN ach_type='WIN' THEN LEAST(pps.total_win+Totals.win_total, ach_amount)
          WHEN ach_type='LOSS' THEN LEAST(pps.total_loss+Totals.loss_total, ach_amount)
          WHEN ach_type='ROUNDS' THEN LEAST(pps.num_rounds+Totals.rounds, ach_num_rounds)
          ELSE 0
        END,
        CASE 
          WHEN ach_type='BET' THEN LEAST(ach_amount*@numDaysAchieved, ach_amount*gaming_promotions.achievement_days_num)
          WHEN ach_type='WIN' THEN LEAST(ach_amount*@numDaysAchieved, ach_amount*gaming_promotions.achievement_days_num)
          WHEN ach_type='LOSS' THEN LEAST(ach_amount*@numDaysAchieved, ach_amount*gaming_promotions.achievement_days_num)
          WHEN ach_type='ROUNDS' THEN LEAST(ach_num_rounds*@numDaysAchieved, ach_num_rounds*gaming_promotions.achievement_days_num)
          ELSE 0
        END
      ), 0)),  
    pps.achieved_percentage=GREATEST(0, IFNULL(LEAST(1, ROUND(IF(pps.requirement_achieved=1,1,
      CASE
        WHEN gaming_promotions.achievement_daily_flag=0 THEN
          CASE 
			WHEN gaming_promotions.is_single THEN LEAST(pps.single_achieved_num+Totals.rounds, gaming_promotions.single_repeat_for)/gaming_promotions.single_repeat_for
            WHEN ach_type='BET' THEN (pps.total_bet+Totals.bet_total) / ach_amount 
            WHEN ach_type='WIN' THEN (pps.total_win+Totals.win_total) / ach_amount 
            WHEN ach_type='LOSS' THEN (pps.total_loss+Totals.loss_total) / ach_amount
            WHEN ach_type='ROUNDS' THEN (pps.num_rounds+Totals.rounds) / ach_num_rounds 
            ELSE 0
          END  
        WHEN gaming_promotions.achievement_daily_flag=1 THEN 
          @numDaysAchieved/gaming_promotions.achievement_days_num
      END),4)), 0)),
    pps.achieved_days=IF(gaming_promotions.achievement_daily_flag=1, IF(pps.requirement_achieved=1, gaming_promotions.achievement_days_num, @numDaysAchieved), NULL)
	WHERE pps.is_current AND pps.is_active;
  
    
	UPDATE gaming_promotions_player_statuses AS pps 
	JOIN gaming_game_rounds_promotion_contributions AS promotion_contributions ON 
	  promotion_contributions.game_play_process_counter_id=@gamePlayProcessCounterID AND
	  promotion_contributions.promotion_player_status_id=pps.promotion_player_status_id AND
	  pps.requirement_achieved=1 AND requirement_achieved_date IS NULL
	SET pps.requirement_achieved_date=NOW();

  COMMIT AND CHAIN;
  
  SELECT value_bool INTO promotionAwardPrizeOnAchievementEnabled FROM gaming_settings WHERE name='PROMOTION_AWARD_PRIZE_ON_ACHIEVEMENT_ENABLED';
  IF (promotionAwardPrizeOnAchievementEnabled=1) THEN
    
    OPEN promotionAwardOnAchievementCursor;
    allPromotionsOnAchievement: LOOP 
      SET noMoreRecords=0;
      FETCH promotionAwardOnAchievementCursor INTO promotionID, promotionRecurrenceID;
      IF (noMoreRecords) THEN
        LEAVE allPromotionsOnAchievement;
      END IF;
    
      CALL PromotionAwardPrizeOnAchievement(promotionID, promotionRecurrenceID);
    
    END LOOP allPromotionsOnAchievement;
    CLOSE promotionAwardOnAchievementCursor;
  END IF;

  IF (singlePromotionsEnabled=1) THEN
    
    OPEN promotionAwardSingleCursor;
    allPromotionsOnSingle: LOOP 
      SET noMoreRecords=0;
      FETCH promotionAwardSingleCursor INTO promotionID, promotionRecurrenceID;
      IF (noMoreRecords) THEN
        LEAVE allPromotionsOnSingle;
      END IF;
   
	 CALL PromotionAwardPrizeForSingle(promotionID, promotionRecurrenceID);
    
    END LOOP allPromotionsOnSingle;
    CLOSE promotionAwardSingleCursor;
  END IF; 


END root $$

DELIMITER ;

-- -------------------------------------
-- ReserveFundsTypeTwoLotto.sql
-- -------------------------------------
DROP procedure IF EXISTS `ReserveFundsTypeTwoLotto`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `ReserveFundsTypeTwoLotto`(couponID BIGINT, sessionID BIGINT, ignoreSessionExpiry TINYINT(1), realMoneyOnly TINYINT(1), OUT statusCode INT)
root:BEGIN
	-- Not securing bonus
    -- Added gaming_game_play_message_types 
    -- Play Limit Check and Update called per game
	-- Optimizations: Forcing STRAIGHT_JOINS and INDEXES 
    -- Merged in INPH
    -- Optimized 
	-- Added checking of total coupon cost against game limits if there is more than 1 game
	--
	DECLARE clientStatID, gameManufacturerID, clientID, currencyID, lotteryTransactionID, fraudClientEventID, gamePlayID, gameRoundID, gamePlayBetCounterID,
		topBonusRuleID BIGINT DEFAULT -1;
	DECLARE gameID BIGINT DEFAULT NULL;
    DECLARE betAmount, balanceReal, balanceBonus, balanceWinLocked, betRemain, FreeBonusAmount,balanceRealBefore ,balanceBonusBefore, exchangeRate,
		betReal, betBonus, betBonusWinLocked, loyaltyBetBonus, bonusWagerRequirementRemain, loyaltyPointsBonus, pendingBetsReal, pendingBetsBonus, loyaltyPoints, totalLoyaltyPointsGivenBonus, totalLoyaltyPointsUsedBonus DECIMAL(18,5) DEFAULT 0;
    DECLARE isAccountClosed, isPlayAllowed, disallowPlay, topBonusApplicable, ringFencedEnabled, dominantNoLoyaltyPoints,playLimitEnabled,bonusReqContributeRealOnly,
		 bonusEnabledFlag, fraudEnabled, playerRestrictionEnabled, licenceCountryRestriction, isLimitExceeded, wagerReqRealOnly, isFreeBetPhase, loyaltyPointsEnabled, loyaltyPointsEnabledWager, loyaltyPointsDisabledTypeTwo, isVerticalActive TINYINT(1) DEFAULT 0;
    DECLARE numParticipations,vipLevelID,sessionStatusCode,licenseTypeID,clientWagerTypeID,wagerStatusCode, errorCode, numGames, platformTypeID INT;
	DECLARE lotteryTransactionIDF, licenseType VARCHAR(80);
    DECLARE currentVipType VARCHAR(100) DEFAULT '';

	SET statusCode =0;
  
	SELECT client_stat_id, game_manufacturer_id, lottery_wager_status_id, error_code, platform_type_id, license_type_id
	INTO clientStatID, gameManufacturerID, wagerStatusCode, errorCode, platformTypeID, licenseTypeID
	FROM gaming_lottery_coupons 
	WHERE lottery_coupon_id=couponID;
    
    CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, @platformTypeID, @platformType, @channelTypeID, @channelType);
      
    -- If Wager Status Code is ReadyForGetFunds Skip Validation
    IF (wagerStatusCode != 2) THEN
		/* to be reviewed later on */
		-- if not equal to one than this is a retry
		IF (wagerStatusCode = 7) THEN
			SET statusCode=errorCode; 
			LEAVE root;
		-- Wager Status Code 3 = FundsReserved. We Return as it's already processed
		ELSEIF (wagerStatusCode = 3) THEN
			SELECT gaming_game_plays_lottery.game_play_id, gaming_game_plays.game_round_id
			INTO gamePlayID, gameRoundID
			FROM gaming_game_plays_lottery FORCE INDEX (lottery_coupon_id)
			STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery.game_play_id
			WHERE gaming_game_plays_lottery.lottery_coupon_id = couponID;
			
			CALL PlayReturnDataWithoutGame(IFNULL(gamePlayID,0), IFNULL(gameRoundID,0), clientStatID, gameManufacturerID);
			CALL PlayReturnBonusInfoOnBet(IFNULL(gamePlayID,0));

			SET statusCode = 100; -- For Already Processed
			LEAVE root;
		ELSE
			SET statusCode = 10; -- Coupon already in another state
			LEAVE root;
		END IF;
    END IF;

    SELECT IFNULL(COUNT(*), 0), IFNULL(SUM(participation_cost),0), COUNT(DISTINCT gaming_lottery_dbg_tickets.game_id), gaming_lottery_dbg_tickets.game_id INTO numParticipations, betAmount, numGames, gameID
    FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 2 /*requires get funds*/
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
  
    -- get player balance details plus lock the player so no other transaction can adjust his balance, till this is finished
	SELECT  gaming_client_stats.client_id, currency_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, pending_bets_real, pending_bets_bonus, current_loyalty_points, total_loyalty_points_given_bonus, total_loyalty_points_used_bonus
	INTO clientID, currencyID, balanceReal, balanceBonus, balanceWinLocked, pendingBetsReal, pendingBetsBonus, loyaltyPoints, totalLoyaltyPointsGivenBonus, totalLoyaltyPointsUsedBonus
	FROM gaming_client_stats FORCE INDEX (PRIMARY)
	WHERE gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1 
	FOR UPDATE;
    
	SELECT gaming_license_type.`name`, gaming_client_wager_types.client_wager_type_id  
	INTO licenseType, clientWagerTypeID
	FROM gaming_license_type 
	JOIN gaming_client_wager_types ON gaming_client_wager_types.license_type_id = gaming_license_type.license_type_id
	WHERE gaming_license_type.license_type_id = licenseTypeID;
    
	SET balanceRealBefore=balanceReal;
	SET balanceBonusBefore=balanceBonus+balanceWinLocked;

	-- check any player restrictions
	SELECT gaming_clients.is_account_closed OR gaming_fraud_rule_client_settings.block_account, gaming_clients.is_play_allowed AND !gaming_fraud_rule_client_settings.block_gameplay, sessions_main.status_code, vip_level_id
	INTO isAccountClosed, isPlayAllowed, sessionStatusCode, vipLevelID
	FROM gaming_clients FORCE INDEX (PRIMARY)
    LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
    LEFT JOIN sessions_main FORCE INDEX (PRIMARY) ON sessions_main.session_id = sessionID AND sessions_main.extra_id=gaming_clients.client_id
	WHERE gaming_clients.client_id=clientID;
    
    -- check if can use bonus money
    SELECT 1,gbi.no_loyalty_points,wager_req_real_only, gbi.bonus_rule_id,bonus_wager_requirement_remain,is_freebet_phase
    INTO topBonusApplicable, dominantNoLoyaltyPoints,wagerReqRealOnly, topBonusRuleID, bonusWagerRequirementRemain,isFreeBetPhase
	FROM (
          SELECT gbi.bonus_rule_id, gbr.no_loyalty_points, wager_req_real_only, bonus_wager_requirement_remain, is_freebet_phase, gbr.restrict_platform_type
		FROM gaming_bonus_instances AS gbi FORCE INDEX (client_active_bonuses)
		STRAIGHT_JOIN gaming_bonus_rules AS gbr ON gbr.bonus_rule_id = gbi.bonus_rule_id
		WHERE gbi.client_stat_id=clientStatID AND gbi.is_active AND gbi.is_free_rounds_mode=0
		ORDER BY gbi.given_date ASC,gbi.bonus_instance_id ASC LIMIT 1 
	) AS gbi
	STRAIGHT_JOIN gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id) ON gaming_lottery_dbg_tickets.lottery_coupon_id = couponID
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 2 /*requires get funds*/
    STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_lottery_participations.lottery_draw_id
	STRAIGHT_JOIN gaming_operator_games ON gaming_lottery_draws.game_id = gaming_operator_games.game_id
    LEFT JOIN gaming_bonus_rules_wgr_req_draw_weights AS gbrwrdw ON gbi.bonus_rule_id=gbrwrdw.bonus_rule_id AND gbrwrdw.lottery_draw_id=gaming_lottery_participations.lottery_draw_id
	LEFT JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON gbi.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=gaming_operator_games.operator_game_id
	LEFT JOIN sessions_main ON sessions_main.session_id=sessionID
	LEFT JOIN gaming_bonus_rules_platform_types AS platform_types ON gbi.bonus_rule_id=platform_types.bonus_rule_id AND sessions_main.platform_type_id=platform_types.platform_type_id
    WHERE (gbrwrw.bonus_wgr_req_weigth IS NOT NULL OR gbrwrdw.bonus_wgr_req_weigth IS NOT NULL) AND (gbi.restrict_platform_type=0 OR platform_types.platform_type_id IS NOT NULL)
    HAVING COUNT(*) = numParticipations;

	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, gs4.value_bool, IFNULL(gs5.value_bool,0) AS vb5, IFNULL(gs6.value_bool,0) AS vb6, IFNULL(gs7.value_bool,0) AS vb7,IFNULL(gs8.value_bool,0) AS vb8,IFNULL(gs9.value_bool,0) AS vb9
	INTO playLimitEnabled, bonusEnabledFlag, fraudEnabled, playerRestrictionEnabled, licenceCountryRestriction,bonusReqContributeRealOnly, ringFencedEnabled /*to be implemented in a later phase*/ , loyaltyPointsEnabledWager, loyaltyPointsDisabledTypeTwo
	FROM gaming_settings gs1 
	STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	STRAIGHT_JOIN gaming_settings gs3 ON (gs3.name='FRAUD_ENABLED')
	STRAIGHT_JOIN gaming_settings gs4 ON (gs4.name='PLAYER_RESTRICTION_ENABLED')
	STRAIGHT_JOIN gaming_settings gs5 ON (gs5.name='LICENCE_COUNTRY_RESTRICTION_ENABLED')
    STRAIGHT_JOIN gaming_settings gs6 ON (gs6.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY')
    STRAIGHT_JOIN gaming_settings gs7 ON (gs7.name='RING_FENCED_ENABLED')
	LEFT JOIN gaming_settings gs8 ON (gs8.name='LOYALTY_POINTS_WAGER_ENABLED')
	LEFT JOIN gaming_settings gs9 ON (gs9.name='LOYALTY_POINTS_DISABLE_IF_WAGERING_BONUS_TYPE_TWO')
	WHERE gs1.name='PLAY_LIMIT_ENABLED';

	SET loyaltyPointsEnabled = IF(loyaltyPointsEnabledWager=0 OR loyaltyPointsDisabledTypeTwo=1,0,1);

	IF (isAccountClosed=1 OR clientStatID = -1) THEN
		SET statusCode=1;
	ELSEIF (numParticipations=0) THEN 
		SET statusCode=2;
	ELSEIF (isPlayAllowed=0) THEN 
		SET statusCode=2;
  ELSEIF ((betAmount > (balanceReal+balanceBonus+balanceWinLocked) AND realMoneyOnly = 0 AND topBonusApplicable) OR ((topBonusApplicable = 0 OR realMoneyOnly = 1) AND betAmount>balanceReal)) THEN
		SET statusCode=3;
	ELSEIF (ignoreSessionExpiry=0 AND IFNULL(sessionStatusCode,0)!=1) THEN
		SET statusCode=4;
	END IF;

	IF (statusCode=0 AND playerRestrictionEnabled) THEN
		SET @numRestrictions=0; SET @restrictionType=NULL;
        
		SELECT restriction_types.name, COUNT(*) INTO @restrictionType, @numRestrictions
		FROM gaming_player_restrictions FORCE INDEX (client_active_non_expired)
		STRAIGHT_JOIN gaming_player_restriction_types AS restriction_types ON 
			restriction_types.is_active=1 AND restriction_types.disallow_play=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
		LEFT JOIN gaming_license_type ON gaming_player_restrictions.license_type_id=gaming_license_type.license_type_id
		WHERE (gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND restrict_until_date>NOW()) AND
			(restrict_from_date<NOW() AND (gaming_license_type.name IS NULL OR gaming_license_type.license_type_id=licenseTypeID OR gaming_license_type.license_type_id=4 /*All*/ ));

		IF (@numRestrictions > 0) THEN
			SET statusCode=5;
		END IF;
	END IF; 
    
	IF (statusCode=0 AND fraudEnabled) THEN
		SELECT gaming_fraud_client_events.fraud_client_event_id, gaming_fraud_classification_types.disallow_play 
		INTO fraudClientEventID, disallowPlay
		FROM gaming_fraud_client_events FORCE INDEX (client_id_current_event)
		STRAIGHT_JOIN gaming_fraud_classification_types ON 
			(gaming_fraud_client_events.client_id=clientID AND gaming_fraud_client_events.is_current=1) 
            AND gaming_fraud_client_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id;

		IF (fraudClientEventID<>-1 AND disallowPlay=1) THEN
			SET statusCode=6;
		END IF;
	END IF;
  
  
	IF (statusCode=0 AND playLimitEnabled) THEN 

		-- Check for the whole coupon cost
		IF (numGames>1) THEN
			SELECT PlayLimitCheckExceededWithGame(betAmount, sessionID, clientStatID, licenseType, NULL) INTO isLimitExceeded;
        END IF;
        
        -- Check for each particular game
        IF (isLimitExceeded=0) THEN
			SELECT SUM(PlayLimitCheckExceededWithGame(game_cost, sessionID, clientStatID, licenseType, game_id))>0 INTO isLimitExceeded
			FROM
			(
				SELECT gaming_lottery_draws.game_id, COUNT(*) AS num_participations, SUM(gaming_lottery_participations.participation_cost) AS game_cost 
				FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
				STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 2 /*requires get funds*/
				STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_lottery_participations.lottery_draw_id
				WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID
				GROUP BY gaming_lottery_draws.game_id
			) AS XX;
		END IF;
 
		IF (isLimitExceeded>0) THEN
			SET statusCode=7;
		END IF;

	END IF;
  
  	IF(licenceCountryRestriction) THEN
		-- Check if there are any country/ip restrictions for this player 
		IF (SELECT !WagerRestrictionCheckCanWager(licenseTypeID, sessionID)) THEN 
			SET statusCode=8; 
		END IF;
	END IF;
  
  
	IF (statusCode != 0) THEN
        UPDATE gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
		STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 2 /*requires get funds*/
		SET gaming_lottery_participations.lottery_wager_status_id=7, gaming_lottery_participations.error_code=statusCode
		WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
        
		UPDATE gaming_lottery_coupons
		SET gaming_lottery_coupons.lottery_wager_status_id = 7, gaming_lottery_coupons.error_code=statusCode
		WHERE gaming_lottery_coupons.lottery_coupon_id = couponID;
    
		LEAVE root;
	END IF;
  
  -- Validation successfull starting actual bet process
	SELECT exchange_rate into exchangeRate 
	FROM gaming_client_stats
	STRAIGHT_JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
	WHERE gaming_client_stats.client_stat_id=clientStatID
	LIMIT 1;

	IF (bonusEnabledFlag=0 OR realMoneyOnly) THEN
		SET balanceBonus=0;
		SET balanceWinLocked=0; 
	END IF;
      
-- see how to split up the money we need to bet
	 IF (bonusEnabledFlag AND topBonusApplicable=1 AND realMoneyOnly = 0) THEN
      
		SET @betRemain=betAmount;
		SET @bonusCounter=0;
		SET @betReal=0.0;
		SET @betBonus=0.0;
		SET @betBonusWinLocked=0.0;
		SET @freeBetBonus=0.0;
		SET @freeBonusAmount=0.0;

		INSERT INTO gaming_game_plays_bet_counter (date_created, client_stat_id) VALUES (NOW(), clientStatID);
		SET gamePlayBetCounterID=LAST_INSERT_ID();

		INSERT INTO gaming_game_plays_bonus_instances_pre (game_play_bet_counter_id, bonus_instance_id, bet_total, bet_real, bet_bonus, bet_bonus_win_locked,bonus_order, no_loyalty_points)
		SELECT gamePlayBetCounterID, bonus_instance_id, bet_real+free_bet_bonus+bet_bonus+bet_bonus_win_locked  AS bet_total, bet_real, bet_bonus+free_bet_bonus, bet_bonus_win_locked,bonusCounter, no_loyalty_points
		FROM
		(
			SELECT 
				bonus_instance_id AS bonus_instance_id, 
				@freeBetBonus:=IF(awarding_type='FreeBet', IF(bonus_amount_remaining>@betRemain, @betRemain, bonus_amount_remaining), 0) AS free_bet_bonus, 
					@betRemain:=@betRemain-@freeBetBonus,   
				@betBonusWinLocked:= IF(current_win_locked_amount>@betRemain, @betRemain, current_win_locked_amount) AS bet_bonus_win_locked,
					@betRemain:=@betRemain-@betBonusWinLocked,
				@betReal:=IF(@bonusCounter=0, IF(balanceReal>@betRemain, @betRemain, balanceReal), 0) AS bet_real, 
					@betRemain:=@betRemain-@betReal,  
				@betBonus:= IF(awarding_type='FreeBet',0,IF(bonus_amount_remaining>@betRemain, @betRemain, bonus_amount_remaining)) AS bet_bonus,
					@betRemain:=@betRemain-@betBonus, @bonusCounter:=@bonusCounter+1 AS bonusCounter,
				@freeBonusAmount := @freeBonusAmount + IF(awarding_type='FreeBet' OR is_free_bonus,@betBonus,0),
				no_loyalty_points
			FROM
			(
				SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_types_awarding.name AS awarding_type, bonus_amount_remaining, current_win_locked_amount, gaming_bonus_rules.no_loyalty_points,current_ring_fenced_amount,is_free_bonus
				FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
				STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
				WHERE gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 AND gaming_bonus_instances.is_free_rounds_mode=0
				ORDER BY gaming_bonus_instances.is_freebet_phase ASC, gaming_bonus_instances.given_date ASC,gaming_bonus_instances.bonus_instance_id ASC
			) AS XX
		) AS XY;

		SELECT SUM(bet_real), SUM(bet_bonus), SUM(bet_bonus_win_locked), SUM(IF(dominantNoLoyaltyPoints,0,bet_bonus+bet_bonus_win_locked))
		INTO betReal, betBonus, betBonusWinLocked, loyaltyBetBonus 
		FROM gaming_game_plays_bonus_instances_pre
		WHERE game_play_bet_counter_id=gamePlayBetCounterID;

		SET betRemain=betRemain-(betReal+betBonus+betBonusWinLocked);
    ELSE
		IF (betAmount > 0) THEN
			IF (balanceReal >= betAmount) THEN
			  SET betReal=ROUND(betAmount, 5);
			  SET betRemain=0;
			ELSE
			  SET betReal=ROUND(balanceReal, 5);
			  SET betRemain=ROUND(betAmount-betReal,0);
			END IF;
		END IF;
		SET betBonusWinLocked=0;
		SET betBonus=0;
    END IF;
  -- this should never happen
	IF (betRemain > 0) THEN
		SET statusCode=9;
		LEAVE root;
	END IF;
    
  SET @currentBetAmount=0.0;
	SET @betReal=betReal;
	SET @betBonus=betBonus;
	SET @betBonusWinLocked=betBonusWinLocked;
	SET @currentBetBonusWinLocked = 0.0;
	SET @currentBetBonus = 0.0;
	SET @currentBetreal = 0.0;
    
  SET @currentLoyaltyPoints = 0.0;
  SET @currentLoyaltyPointsBonus = 0.0;
  SET @totalLoyaltyPoints =0.0;
  SET @totalLoyaltyPointsBonus = 0.0;
	
	INSERT INTO gaming_game_plays_lottery_entries (game_play_id, lottery_draw_id, lottery_participation_id, amount_total, amount_bonus_win_locked, amount_real, amount_bonus, amount_ring_fenced,amount_free_bet,loyalty_points,loyalty_points_bonus)
	SELECT gamePlayID, lottery_draw_id, lottery_participation_id,participation_cost, tempBetBonusWinLocked, tempBetReal, tempBetBonus,0,0,loyaltyPointsReal,tmpTable.loyaltyPointsBonus
	FROM 
	(
		SELECT gaming_lottery_participations.lottery_draw_id, gaming_lottery_participations.lottery_participation_id,participation_cost,
			@currentBetAmount:=participation_cost AS currentBet,
			@currentBetBonusWinLocked := IF(@currentBetAmount>@betBonusWinLocked,@betBonusWinLocked,@currentBetAmount) AS tempBetBonusWinLocked,
			@currentBetAmount := @currentBetAmount - @currentBetBonusWinLocked,
			@betBonusWinLocked := @betBonusWinLocked - @currentBetBonusWinLocked,
			@currentBetreal := IF(@currentBetAmount > @betReal, @betReal, @currentBetAmount) AS tempBetReal,
			@currentBetAmount := @currentBetAmount - @currentBetreal,
			@betReal := @betReal - @currentBetreal,
			@currentBetBonus := IF(@currentBetAmount > @betBonus, @betBonus, @currentBetAmount) AS tempBetBonus,
			@currentBetAmount := @currentBetAmount - @currentBetBonus,
			@betBonus := @betBonus - @currentBetBonus,
			@currentLoyaltyPoints := @currentBetreal * IFNULL(glpld.loyalty_points/glpld.amount,IFNULL(glpg.loyalty_points/glpg.amount,IFNULL(glpgc.loyalty_points/glpgc.amount,0)))   AS loyaltyPointsReal,
			@currentLoyaltyPointsBonus := (@currentBetBonus + @currentBetBonusWinLocked) * IFNULL(glpld.loyalty_points/glpld.amount,IFNULL(glpg.loyalty_points/glpg.amount,IFNULL(glpgc.loyalty_points/glpgc.amount,0))) AS loyaltyPointsBonus,
			@totalLoyaltyPoints := @totalLoyaltyPoints + @currentLoyaltyPoints,
            @totalLoyaltyPointsBonus := @totalLoyaltyPointsBonus + @currentLoyaltyPointsBonus
		FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
		STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 2
		STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_lottery_participations.lottery_draw_id
		LEFT JOIN gaming_game_categories_games ON gaming_lottery_draws.game_id = gaming_game_categories_games.game_id
		LEFT JOIN gaming_game_categories ON gaming_game_categories_games.game_category_id = gaming_game_categories.game_category_id
		LEFT JOIN gaming_loyalty_points_games AS glpg ON gaming_lottery_draws.game_id = glpg.game_id AND glpg.currency_id = currencyID AND glpg.vip_level_id = vipLevelID
		LEFT JOIN gaming_loyalty_points_game_categories AS glpgc ON glpgc.game_category_id = IFNULL(gaming_game_categories.parent_game_category_id, gaming_game_categories.game_category_id) AND 
			glpgc.vip_level_id = vipLevelID AND glpgc.currency_id = currencyID
		LEFT JOIN gaming_loyalty_points_lottery_draws AS glpld ON glpld.lottery_draw_id = gaming_lottery_draws.lottery_draw_id AND
			glpld.vip_level_id = vipLevelID AND glpld.currency_id = currencyID
		WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID 
		ORDER BY lottery_participation_id
	) AS tmpTable;
	
	SELECT set_type INTO currentVipType FROM gaming_vip_levels vip WHERE vip.vip_level_id=vipLevelID;

	IF(loyaltyPointsEnabled=0) THEN
		SET @totalLoyaltyPoints=0;
		SET @totalLoyaltyPointsBonus=0;
	END IF;
    
	-- update player balance
	UPDATE gaming_client_stats AS gcs
	LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
	SET 
	gcs.total_wallet_real_played_online = IF(@channelType = 'online', gcs.total_wallet_real_played_online + betReal, gcs.total_wallet_real_played_online),
	gcs.total_wallet_real_played_retail = IF(@channelType = 'retail', gcs.total_wallet_real_played_retail + betReal, gcs.total_wallet_real_played_retail),
	gcs.total_wallet_real_played_self_service = IF(@channelType = 'self-service' ,gcs.total_wallet_real_played_self_service + betReal, gcs.total_wallet_real_played_self_service),
    gcs.total_wallet_real_played = gcs.total_wallet_real_played_online + gcs.total_wallet_real_played_retail + gcs.total_wallet_real_played_self_service,
	gcs.total_real_played = IF(@channelType NOT IN ('online','retail','self-service'),gcs.total_real_played+betReal, gcs.total_wallet_real_played + gcs.total_cash_played),
	
	current_real_balance=current_real_balance-betReal,
		total_bonus_played=total_bonus_played+betBonus, current_bonus_balance=current_bonus_balance-betBonus, 
		total_bonus_win_locked_played=total_bonus_win_locked_played+betBonusWinLocked, current_bonus_win_locked_balance=current_bonus_win_locked_balance-betBonusWinLocked, 
		gcs.total_real_played_base=gcs.total_real_played_base +IFNULL((betReal/exchangeRate),0),
		gcs.total_bonus_played_base=gcs.total_bonus_played_base+((betBonus+betBonusWinLocked)/exchangeRate),
		gcs.total_loyalty_points_given = gcs.total_loyalty_points_given + IFNULL(@totalLoyaltyPoints,0) , gcs.current_loyalty_points = gcs.current_loyalty_points + IFNULL(@totalLoyaltyPoints,0) ,
		gcs.total_loyalty_points_given_bonus = gcs.total_loyalty_points_given_bonus + IFNULL(@totalLoyaltyPointsBonus,0) ,
        gcs.loyalty_points_running_total = IF(currentVipType = 'LoyaltyPointsPeriod', gcs.loyalty_points_running_total + IFNULL(@totalLoyaltyPoints,0), gcs.loyalty_points_running_total),
		last_played_date=NOW(), 
	
		-- gaming_client_sessions
		gcss.total_bet=gcss.total_bet+betAmount,gcss.total_bet_base=gcss.total_bet_base+(betAmount/exchangeRate),
        gcss.bets=gcss.bets+1, gcss.total_bet_real=gcss.total_bet_real+betReal, gcss.total_bet_bonus=gcss.total_bet_bonus+betBonus+betBonusWinLocked,
		gcss.loyalty_points=gcss.loyalty_points+ IFNULL(@totalLoyaltyPoints,0), gcss.loyalty_points_bonus=gcss.loyalty_points_bonus+ IFNULL(@totalLoyaltyPointsBonus,0),
		-- gaming_client_wager_types
		gcws.num_bets=gcws.num_bets+1, gcws.total_real_wagered=gcws.total_real_wagered+betReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered+betBonus+betBonusWinLocked,
		gcws.first_wagered_date=IFNULL(gcws.first_wagered_date, NOW()), gcws.last_wagered_date=NOW(), gcs.bet_from_real = if (topBonusApplicable = 0,gcs.bet_from_real ,gcs.bet_from_real + betReal),
        gcws.loyalty_points=gcws.loyalty_points+ IFNULL(@totalLoyaltyPoints,0), gcws.loyalty_points_bonus=gcws.loyalty_points_bonus+ IFNULL(@totalLoyaltyPointsBonus,0)
	WHERE gcs.client_stat_id = clientStatID;
    
    -- insert data
	INSERT INTO gaming_game_rounds
		(bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked, bet_bonus_lost, num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, round_ref, license_type_id, is_round_finished, balance_real_before, balance_bonus_before, loyalty_points, loyalty_points_bonus,sb_bet_id) 
    SELECT betAmount, ROUND(betAmount/exchangeRate,5), exchangeRate, betReal, betBonus, betBonusWinLocked, 0, 1, 1, NOW(), gameManufacturerID, clientID, clientStatID, 1, gaming_game_round_types.game_round_type_id, currencyID, couponID, licenseTypeID, 1, balanceRealBefore, balanceBonusBefore, @totalLoyaltyPoints, @totalLoyaltyPointsBonus,couponID
    FROM gaming_game_round_types
    WHERE gaming_game_round_types.`name` = CAST(CASE licenseTypeID WHEN 6 THEN 'Lotto' WHEN 7 THEN 'SportsPool' END AS CHAR(80));
    
    SET gameRoundID=LAST_INSERT_ID();
    
	INSERT INTO gaming_game_rounds_lottery (game_round_id, is_parent_round) 
    VALUES (gameRoundID, 1);
     
	INSERT INTO gaming_game_plays 
		(amount_total, game_round_id, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, amount_other, bonus_lost, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, pending_bet_real, pending_bet_bonus, currency_id, sign_mult, license_type_id,loyalty_points, loyalty_points_bonus,loyalty_points_after, loyalty_points_after_bonus, sb_bet_id, game_play_message_type_id, is_win_placed, platform_type_id,is_processed,game_id) 
	SELECT betAmount, gameRoundID, betAmount/exchangeRate, exchangeRate, betReal, betBonus, betBonusWinLocked,IFNULL(FreeBonusAmount,0), 0, 0,NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gaming_payment_transaction_type.payment_transaction_type_id, balanceReal - betReal, (balanceBonus-betBonus)+(balanceWinLocked-betBonusWinLocked), balanceWinLocked - betBonusWinLocked, pendingBetsReal, pendingBetsBonus, currencyID, -1, licenseTypeID, @totalLoyaltyPoints, @totalLoyaltyPointsBonus, loyaltyPoints + IFNULL(@totalLoyaltyPoints,0), IFNULL((totalLoyaltyPointsGivenBonus + IFNULL(@totalLoyaltyPointsBonus,0)) - totalLoyaltyPointsUsedBonus,0), couponID, gaming_game_play_message_types.game_play_message_type_id, 0, @platformTypeID, 1, gameID
	FROM gaming_payment_transaction_type
	STRAIGHT_JOIN gaming_game_play_message_types ON gaming_game_play_message_types.`name`= CAST(CASE licenseTypeID WHEN 6 THEN 'LotteryBet' WHEN 7 THEN 'SportsPoolBet' END AS CHAR(80))	
    WHERE gaming_payment_transaction_type.name = 'Bet';
    
    SET gamePlayID = LAST_INSERT_ID();
     
	UPDATE gaming_lottery_transactions SET game_play_id = gamePlayID WHERE lottery_coupon_id = couponID and is_latest = 1;
   
	IF(vipLevelID IS NOT NULL) THEN
		CALL PlayerUpdateVIPLevel(clientStatID);
	END IF;
    
    INSERT INTO gaming_game_plays_lottery(game_play_id, lottery_coupon_id) VALUES (gamePlayID, couponID);
    
    UPDATE gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
    STRAIGHT_JOIN gaming_game_plays_lottery_entries FORCE INDEX (lottery_participation_id) ON gaming_game_plays_lottery_entries.lottery_participation_id  = gaming_lottery_participations.lottery_participation_id
    SET gaming_game_plays_lottery_entries.game_play_id = gamePlayID , gaming_lottery_participations.lottery_wager_status_id = 3
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
    
    UPDATE gaming_lottery_coupons
	LEFT JOIN gaming_channel_types ON gaming_channel_types.channel_type_id = @channelTypeID
    SET gaming_lottery_coupons.lottery_wager_status_id = 3, wager_game_play_id = gamePlayID, gaming_lottery_coupons.platform_type_id = @platformTypeID, gaming_lottery_coupons.channel_type_id = @channelTypeID,
    paid_with = IFNULL(paid_with, gaming_channel_types.default_paid_with)
    WHERE lottery_coupon_id = couponID;
    
	INSERT INTO gaming_game_rounds
		(bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked, bet_bonus_lost, num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, round_ref, license_type_id,is_round_finished,balance_real_before, balance_bonus_before, loyalty_points, loyalty_points_bonus, sb_bet_id, sb_extra_id,game_id, operator_game_id) 
    SELECT amount_total, ROUND(amount_total/exchangeRate,5), exchangeRate, amount_real, amount_bonus, amount_bonus_win_locked, 0, 1, 1, NOW(), gameManufacturerID, clientID, clientStatID, 0, gaming_game_round_types.game_round_type_id, currencyID, couponID, licenseTypeID ,0, balanceRealBefore, balanceBonusBefore,@totalLoyaltyPoints,@totalLoyaltyPointsBonus, couponID, lottery_participation_id, gaming_operator_games.game_id, gaming_operator_games.operator_game_id
    FROM gaming_game_plays_lottery_entries FORCE INDEX (game_play_id)  
    STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_game_plays_lottery_entries.lottery_draw_id
    STRAIGHT_JOIN gaming_operator_games ON gaming_operator_games.game_id = gaming_lottery_draws.game_id
	JOIN gaming_game_round_types ON gaming_game_round_types.`name` = CAST(CASE licenseTypeID WHEN 6 THEN 'Lotto' WHEN 7 THEN 'SportsPool' END AS CHAR(80))
    WHERE gaming_game_plays_lottery_entries.game_play_id = gamePlayID;
    
    INSERT INTO gaming_game_rounds_lottery (game_round_id, is_parent_round, parent_game_round_id)
	SELECT gaming_game_rounds.game_round_id, 0, gameRoundID
    FROM gaming_game_plays_lottery_entries FORCE INDEX (game_play_id)
    STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (sb_extra_id) ON 
		gaming_game_plays_lottery_entries.lottery_participation_id = gaming_game_rounds.sb_extra_id AND gaming_game_rounds.license_type_id = licenseTypeID 
    WHERE gaming_game_plays_lottery_entries.game_play_id = gamePlayID;

	IF (playLimitEnabled AND betAmount > 0) THEN 

		SELECT SUM(PlayLimitsUpdateFunc(sessionID, clientStatID, licenseType, game_cost, 1, game_id)) 
		INTO @numUpdateLimitErrors
		FROM
		(
			SELECT gaming_lottery_draws.game_id, COUNT(*) AS num_participations, SUM(gaming_lottery_participations.participation_cost) AS game_cost 
			FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
			STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 3 /*funds reserved*/
			STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_lottery_participations.lottery_draw_id
			WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID
			GROUP BY gaming_lottery_draws.game_id
		) AS XX;
		
	END IF;

	IF (bonusEnabledFlag AND topBonusApplicable=1 AND realMoneyOnly = 0) THEN
		
		SET @currentBetBonusWinLocked = 0.0;
        SET @currentBetBonus = 0.0;
        SET @currentBetreal = 0.0;
        
		SET @balanceBetBonusWinLocked = 0.0;
        SET @balanceBetBonus = 0.0;
        SET @balanceBetreal = betReal;
        
		SET @totalBetBonus = 0.0;
        SET @totalBetBonusWinLocked = 0.0;
        SET @totalBetReal = 0.0;
        
		SET @bonusInstanceID = 0;
        SET @bonusChanged = 0;
        SET @currentParticipation = 0;
        SET @particpationUpdate = 0;
        SET @wagerNonWeighted = 0.0;
        SET @wagerTotal = 0.0;
        
		SET @playLotteryWagerRemain=0.0;

        INSERT INTO gaming_game_plays_lottery_entry_bonuses(game_play_lottery_entry_id,bonus_instance_id,bet_bonus_win_locked,bet_real,bet_bonus,wager_requirement_non_weighted,
			wager_requirement_contribution_before_real_only,wager_requirement_contribution,wager_requirement_contribution_cancelled)
		SELECT game_play_lottery_entry_id,bonus_instance_id, tempBetBonusWinLocked, tempBetReal, tempBetBonus,wagerNonWeighted,wager_requirement_contribution_pre,wager_requirement_contribution,0
        FROM (
			SELECT tmpTable.game_play_lottery_entry_id,bonus_instance_id, tempBetBonusWinLocked, tempBetReal, tempBetBonus,
				@wagerNonWeighted:= tempBetBonusWinLocked+tempBetReal+tempBetBonus AS wagerNonWeighted,
                @wagerWeighted :=
						ROUND(
							LEAST(
									IFNULL(wgr_restrictions.max_wager_contibution_before_weight,100000000*100),
									@wagerNonWeighted
								  )*IFNULL(gaming_bonus_rules_wgr_req_weights.bonus_wgr_req_weigth, 0)*CASE licenseTypeID WHEN 6 THEN IFNULL(lottery_weight_mod, 1) WHEN 7 THEN IFNULL(sportspool_weight_mod, 1)	ELSE 1 END,	
						5),
				IF(@wagerWeighted>=bonusWagerRequirementRemain,bonusWagerRequirementRemain,@wagerWeighted) AS wager_requirement_contribution_pre,
                @wagerNonWeighted:= IF(wagerReqRealOnly OR bonusReqContributeRealOnly,tempBetReal,tempBetBonusWinLocked+tempBetReal+tempBetBonus),
                @wagerWeighted :=IF(isFreeBetPhase,0,
						ROUND(
							LEAST(
									IFNULL(wgr_restrictions.max_wager_contibution_before_weight,100000000*100),
									@wagerNonWeighted
								  )*IFNULL(gaming_bonus_rules_wgr_req_weights.bonus_wgr_req_weigth, 0)*CASE licenseTypeID WHEN 6 THEN IFNULL(lottery_weight_mod, 1) WHEN 7 THEN IFNULL(sportspool_weight_mod, 1)	ELSE 1 END,

						5)),
				IF(@wagerWeighted>=bonusWagerRequirementRemain,bonusWagerRequirementRemain,@wagerWeighted) AS wager_requirement_contribution
                
			FROM (
				SELECT game_play_lottery_entry_id,bonus_instance_id,
					@particpationUpdate:=IF(lottery_participation_id>@currentParticipation AND @playLotteryWagerRemain=0, 1,0) AS d,
					@currentParticipation := IF(@particpationUpdate,lottery_participation_id,@currentParticipation),

					@totalBetBonus := IF(@particpationUpdate=0,@totalBetBonus,0.0),
					@totalBetBonusWinLocked := IF(@particpationUpdate=0,@totalBetBonusWinLocked,0.0),
					@totalBetReal := IF(@particpationUpdate=0,@totalBetReal ,0.0),
					
					@bonusChanged := IF(@bonusInstanceID = bonus_instance_id,0,1),
					@bonusInstanceID := bonus_instance_id,
					
					@balanceBetBonusWinLocked := IF(@bonusChanged=1,current_win_locked_amount,@balanceBetBonusWinLocked),
					@balanceBetBonus := IF(@bonusChanged=1,bonus_amount_remaining,@balanceBetBonus),
					 
					@currentBetBonusWinLocked := IF(@balanceBetBonusWinLocked>0,IF(@balanceBetBonusWinLocked>(amount_bonus_win_locked-@totalBetBonusWinLocked),IF((amount_bonus_win_locked-@totalBetBonusWinLocked)<0,0.0,amount_bonus_win_locked-@totalBetBonusWinLocked),@balanceBetBonusWinLocked),0.0) AS tempBetBonusWinLocked,
					@balanceBetBonusWinLocked := @balanceBetBonusWinLocked - @currentBetBonusWinLocked,
					@totalBetBonusWinLocked := @totalBetBonusWinLocked + @currentBetBonusWinLocked,
					

					@currentBetreal := IF(@balanceBetreal>0,IF(@balanceBetreal>(amount_real-@totalBetReal),IF((amount_real-@totalBetReal)<0,0.0,(amount_real-@totalBetReal)),@balanceBetreal),0.0) AS tempBetReal,
					@balanceBetreal := @balanceBetreal - @currentBetreal,
					@totalBetReal := @totalBetReal + @currentBetreal,

					@currentBetBonus := IF(@balanceBetBonus>0,IF(@balanceBetBonus>(amount_bonus-@totalBetBonus),IF((amount_bonus-@totalBetBonus)<0,0.0,amount_bonus-@totalBetBonus),@balanceBetBonus),0.0) AS tempBetBonus,
					@balanceBetBonus := @balanceBetBonus - @currentBetBonus,
					@totalBetBonus := @totalBetBonus + @currentBetBonus,

					@playLotteryWagerRemain := IF(@particpationUpdate, amount_real+amount_bonus+amount_bonus_win_locked, @playLotteryWagerRemain)-(@currentBetreal+@currentBetBonus+@currentBetBonusWinLocked) AS playLotteryWagerRemain
				FROM (
					SELECT game_play_lottery_entry_id,lottery_participation_id,gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.current_win_locked_amount,gaming_bonus_instances.bonus_amount_remaining,
						amount_bonus_win_locked,amount_real,amount_bonus
					FROM gaming_game_plays_lottery_entries FORCE INDEX (game_play_id)
					STRAIGHT_JOIN gaming_game_plays_bonus_instances_pre ON gaming_game_plays_bonus_instances_pre.game_play_bet_counter_id = gamePlayBetCounterID
					STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_game_plays_bonus_instances_pre.bonus_instance_id
					WHERE gaming_game_plays_lottery_entries.game_play_id = gamePlayID 
					ORDER BY gaming_game_plays_bonus_instances_pre.bonus_order, gaming_game_plays_lottery_entries.lottery_participation_id
				) AS tmpTbl
			) AS tmpTable
			STRAIGHT_JOIN gaming_game_plays_lottery_entries ON gaming_game_plays_lottery_entries.game_play_lottery_entry_id = tmpTable.game_play_lottery_entry_id
			STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_game_plays_lottery_entries.lottery_draw_id
			STRAIGHT_JOIN gaming_operator_games ON gaming_lottery_draws.game_id = gaming_operator_games.game_id
			STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = topBonusRuleID
			LEFT JOIN gaming_bonus_rules_wgr_req_weights ON gaming_bonus_rules_wgr_req_weights.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND gaming_bonus_rules_wgr_req_weights.operator_game_id=gaming_operator_games.operator_game_id
			LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_rules.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID
        ) AS tmpTable;

		SET @OverWagerBonuses = 0;
        
		SELECT SUM(wager_requirement_non_weighted) AS wager_requirement_non_weighted, SUM(wager_requirement_contribution_before_real_only) AS wager_requirement_contribution_before_real_only,
		SUM(wager_requirement_contribution) AS wager_requirement_contribution
		INTO @wagerReqNonWeighted, @wagerReqWeightedBeforeReal, @wagerReqWeighted
		FROM gaming_game_plays_lottery_entries FORCE INDEX (game_play_id)
		STRAIGHT_JOIN gaming_game_plays_lottery_entry_bonuses ON gaming_game_plays_lottery_entry_bonuses.game_play_lottery_entry_id  = gaming_game_plays_lottery_entries.game_play_lottery_entry_id
		WHERE gaming_game_plays_lottery_entries.game_play_id = gamePlayID;
	
		INSERT INTO gaming_game_plays_bonus_instances (game_play_id, bonus_instance_id, bonus_rule_id, client_stat_id, timestamp, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,
			wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_wager_requirement_remain_after,bonus_order)
		SELECT gamePlayID, bonus_instance_id, bonus_rule_id, clientStatID, NOW(), exchangeRate,bet_real, bet_bonus, bet_bonus_win_locked,
			wager_requirement_non_weighted,wager_requirement_contribution_pre,wager_requirement_contribution,now_wager_requirement_met,now_release_bonus,
			bonus_wager_requirement_remain_after,bonus_order
		FROM (
			SELECT gamePlayID, bonus_instance_id, gaming_bonus_instances.bonus_rule_id, clientStatID, exchangeRate,
			gaming_bonus_instances.bet_real,gaming_bonus_instances.bet_ring_fenced, gaming_bonus_instances.bet_bonus, gaming_bonus_instances.bet_bonus_win_locked,
			@tempWagerNonWeighted := IF(bonus_wager_requirement_remain<@wagerReqNonWeighted,bonus_wager_requirement_remain,@wagerReqNonWeighted) AS wager_requirement_non_weighted,
            @wagerReqNonWeighted := GREATEST(0,@wagerReqNonWeighted - @tempWagerNonWeighted),
            @tempWagerReqWeightedBeforeReal := IF(bonus_wager_requirement_remain<@wagerReqWeightedBeforeReal,bonus_wager_requirement_remain,@wagerReqWeightedBeforeReal) AS wager_requirement_contribution_pre,
            @wagerReqWeightedBeforeReal:= GREATEST(0,@wagerReqWeightedBeforeReal-@tempWagerReqWeightedBeforeReal), 
			@tempWagerReqWeighted := IF(bonus_wager_requirement_remain<@wagerReqWeighted,bonus_wager_requirement_remain,@wagerReqWeighted) AS wager_requirement_contribution,
            @wagerReqWeighted := GREATEST(0,@wagerReqWeighted - @tempWagerReqWeighted),
			@nowWagerReqMet:=IF (bonus_wager_requirement_remain-@tempWagerReqWeighted=0 AND is_free_bonus=0,1,0) AS now_wager_requirement_met,
			IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wager_requirement_contribution)>=((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,
			bonus_wager_requirement_remain-@tempWagerReqWeighted AS bonus_wager_requirement_remain_after,
			bonus_order
			FROM 
			(
				SELECT bonus_transaction.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, bonus_transaction.bet_total, bonus_transaction.bet_real,bonus_transaction.bet_ring_fenced, bonus_transaction.bet_bonus, bonus_transaction.bet_bonus_win_locked, bonus_wager_requirement_remain, 
				CASE licenseTypeID 
						WHEN 6 THEN lottery_weight_mod
						WHEN 7 THEN sportspool_weight_mod
						ELSE 1
				END AS license_weight_mod,
					bonus_amount_given, bonus_wager_requirement, gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus, bonus_order,is_free_bonus,is_freebet_phase,ring_fence_only
				FROM gaming_game_plays_bonus_instances_pre AS bonus_transaction FORCE INDEX (PRIMARY)
				STRAIGHT_JOIN gaming_bonus_instances ON bonus_transaction.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
				STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
				WHERE bonus_transaction.game_play_bet_counter_id=gamePlayBetCounterID 
			) AS gaming_bonus_instances  
		) AS a;
        
		UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
		STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
		STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
		SET bonus_amount_remaining=bonus_amount_remaining-bet_bonus, current_win_locked_amount=current_win_locked_amount-bet_bonus_win_locked,
			bonus_wager_requirement_remain=bonus_wager_requirement_remain-wager_requirement_contribution,current_ring_fenced_amount=current_ring_fenced_amount-bet_ring_fenced,
			gaming_bonus_instances.open_rounds=gaming_bonus_instances.open_rounds+numParticipations
		WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;  
        
	END IF;
    
	 CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID);
     CALL PlayReturnBonusInfoOnBet(gamePlayID);
     
END$$

DELIMITER ;

