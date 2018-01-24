DROP procedure IF EXISTS `CommonWalletSportsGenericPlaceBetTypeTwo`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsGenericPlaceBetTypeTwo`(
  sbBetID BIGINT, minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN

	-- First Version :)  
    -- Performance: 2017-01-15
    -- Optimized for Parititioning
    
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
	DECLARE balanceReal, balanceBonus, balanceWinLocked, betRemain, exchangeRate, betAmountBase, sbOdd, 
		pendingBetsReal, pendingBetsBonus, loyaltyPoints, loyaltyPointsBonus DECIMAL(18, 5) DEFAULT 0;

	DECLARE currentVipType VARCHAR(100) DEFAULT '';
	DECLARE roundType, licenseType VARCHAR(20) DEFAULT NULL;

	DECLARE isAlreadyProcessed, playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, isProcessed, isCouponBet TINYINT(1) DEFAULT 0;
	DECLARE recalcualteBonusWeight TINYINT(1) DEFAULT 0;
	DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
	
	-- *****************************************************
	-- Loyalty Points Bonus variables which now not used
	-- *****************************************************
	DECLARE loyaltyPointsEnabledWager, loyaltyPointsDisabledTypeTwo, loyaltyPointsEnabled TINYINT(1) DEFAULT 0;

	DECLARE partitioningMinusFromMax INT DEFAULT 10000;
	DECLARE minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, 
		minSbBetMultipleSingleID, maxSbBetMultipleSingleID, minGameRoundID, maxGameRoundID, 
		minGamePlaySBID, maxGamePlaySBID, minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID BIGINT DEFAULT NULL; 

	-- *****************************************************
	-- Set defaults
	-- *****************************************************
	SET statusCode = 0;
	SET @totalLoyaltyPoints = 0;
	SET @totalLoyaltyPointsBonus = 0;
    
	-- *****************************************************   
	-- Check the bet exists and it is in the correct status
	-- *****************************************************
	SELECT gsb.sb_bet_id, gsb.game_manufacturer_id, IFNULL(gsb.wager_game_play_id, -1), gsb.client_stat_id, gsb.bet_total, 
		gsb.num_singles, gsb.num_multiplies, gsb.status_code, gsb.amount_real, 
        gsb.amount_bonus, gsb.amount_bonus_win_locked, gsb.amount_free_bet, 
        gsb.is_processed, gsb.lottery_dbg_ticket_id IS NOT NULL,
		gsbpf.max_sb_bet_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_single_id, 
		gsbpf.max_sb_bet_multiple_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_id,
		gsbpf.max_sb_bet_multiple_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_single_id,
		gsbpf.min_game_round_id, gsbpf.max_game_round_id, 
		gsbpf.min_game_play_sb_id, gsbpf.max_game_play_sb_id,
        gsbpf.max_game_play_bonus_instance_id-partitioningMinusFromMax, gsbpf.max_game_play_bonus_instance_id
	INTO sbBetID, gameManufacturerID, gamePlayID, clientStatID, betAmount, 
		numSingles, numMultiples, sbBetStatusCode, betReal, betBonus, betBonusWinlocked, betFreeBet, 
        isProcessed, isCouponBet,
        minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, minSbBetMultipleSingleID, maxSbBetMultipleSingleID,
		minGameRoundID, maxGameRoundID, minGamePlaySBID, maxGamePlaySBID, minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID
	FROM gaming_sb_bets AS gsb
	LEFT JOIN gaming_sb_bets_partition_fields AS gsbpf ON gsbpf.sb_bet_id=gsb.sb_bet_id
    WHERE gsb.sb_bet_id=sbBetID;
  
	IF (sbBetID = -1 OR clientStatID = -1 OR gamePlayID = -1) THEN
		SET statusCode = 1;
		LEAVE root;
	END IF;

	IF (sbBetStatusCode NOT IN (3, 6) OR isProcessed = 1) THEN 
		SET statusCode = 2;
        
		IF (isCouponBet) THEN
			SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayID;
			CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID, minimalData);
			CALL PlayReturnBonusInfoOnWin(gamePlayID);
		ELSE
			CALL CommonWalletSBReturnData(sbBetID, clientStatID, gamePlayID, minimalData);
		END IF;
        
		LEAVE root;
	END IF;	

	-- *****************************************************
	-- Get Settings
	-- *****************************************************
	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, IFNULL(gs4.value_bool, 0), 
		IFNULL(gs5.value_bool, 0) AS vb5, IFNULL(gs6.value_bool, 0) AS vb6
	INTO playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, recalcualteBonusWeight, 
		 loyaltyPointsEnabledWager, loyaltyPointsDisabledTypeTwo
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
	FROM clients_locations FORCE INDEX (client_id)
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
	WHERE sb_bet_id = sbBetID AND 
		-- parition filtering
		(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID) AND
		-- other filtering
        confirmation_status = 0 AND payment_transaction_type_id IN (12, 45);

	-- *****************************************************
	-- Set to confirmed all bet slips which have not been explicitily cancelled
	-- *****************************************************
	UPDATE gaming_game_plays_sb FORCE INDEX (sb_bet_id) 
	SET confirmation_status=2 
	WHERE sb_bet_id=sbBetID AND 
		-- parition filtering
		(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID) AND
		-- other filtering
        confirmation_status=0 AND payment_transaction_type_id IN (12, 45);

	UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
	SET processing_status=2
	WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID AND 
		-- parition filtering
		(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID) AND
		-- other filtering
		gaming_sb_bet_singles.processing_status<>3;

	UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id) 
	SET processing_status=2 
	WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND 
		-- parition filtering
		(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID) AND
		-- other filtering
		gaming_sb_bet_multiples.processing_status<>3;

	-- *****************************************************
	-- Get How much was confirmed in total for the whole bet slip
	-- *****************************************************
	SELECT COUNT(*), 
		IFNULL(SUM(amount_real), 0) AS amount_real, 
		IFNULL(SUM(amount_bonus-amount_bonus_win_locked_component), 0) AS amount_bonus, 
		IFNULL(SUM(amount_bonus_win_locked_component), 0) AS amount_bonus_win_locked
	INTO commmitedBetEntries, betReal, betBonus, betBonusWinLocked
	FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
	WHERE sb_bet_id = sbBetID AND 
		-- parition filtering
		(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID) AND
		-- other filtering
        confirmation_status = 2;

	IF (commmitedBetEntries = 0) THEN
		UPDATE gaming_sb_bets FORCE INDEX (PRIMARY) 
        SET bet_total=bet_total-betAmount, is_processed=1, is_success=1, status_code=5 
        WHERE sb_bet_id=sbBetID;

		CALL CommonWalletSBReturnData(sbBetID, clientStatID, gamePlayID, minimalData);
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
	STRAIGHT_JOIN gaming_operator_currency ON gaming_client_stats.currency_id = gaming_operator_currency.currency_id 
	STRAIGHT_JOIN gaming_clients gc ON gc.client_id = gaming_client_stats.client_id
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
		FROM gaming_game_plays_sb FORCE INDEX (game_play_id)
		STRAIGHT_JOIN gaming_game_plays_sb_bonuses ON 
			gaming_game_plays_sb_bonuses.game_play_sb_id  = gaming_game_plays_sb.game_play_sb_id
		WHERE gaming_game_plays_sb.game_play_id = gamePlayID AND
			-- parition filtering
			(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID);

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
				STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS sb_bonuses ON 
					sb_bonuses.game_play_sb_id=gaming_game_plays_sb.game_play_sb_id
				STRAIGHT_JOIN gaming_bonus_instances ON 
					sb_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
				STRAIGHT_JOIN gaming_bonus_rules ON 
					gaming_bonus_rules.bonus_rule_id=gaming_bonus_instances.bonus_rule_id 
				LEFT JOIN  gaming_sb_bets_bonus_rules ON 
					gaming_sb_bets_bonus_rules.sb_bet_id=gaming_game_plays_sb.sb_bet_id AND 
					gaming_sb_bets_bonus_rules.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON 
					gaming_bonus_rules.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID
				WHERE gaming_game_plays_sb.sb_bet_id=sbBetID AND sb_bonuses.wager_requirement_non_weighted > 0 AND
					-- parition filtering
					(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
			) AS XX 
			STRAIGHT_JOIN gaming_game_plays_sb_bonuses FORCE INDEX (PRIMARY) ON 
				gaming_game_plays_sb_bonuses.game_play_sb_id=XX.game_play_sb_id AND 
				gaming_game_plays_sb_bonuses.bonus_instance_id=XX.bonus_instance_id
			SET gaming_game_plays_sb_bonuses.wager_requirement_non_weighted=XX.wagerNonWeighted,
				gaming_game_plays_sb_bonuses.wager_requirement_contribution_before_real_only=XX.wager_requirement_contribution_pre, 
				gaming_game_plays_sb_bonuses.wager_requirement_contribution=XX.wager_requirement_contribution;

		END IF;
        
        -- INSERT into gaming_game_plays_bonus_instances is done in GetFunds for Type2

		IF (@wagerReqNonWeighted > 0) THEN

			SET @curWagerReqMet=0;
			SET @countWagerReqMet=0;

			SET @curReleaseBonus=0;
			SET @countReleaseBonus=0;

			-- *****************************************************
			-- Bonus balance has already been updated but we need to update the bonus_wager_requirement_remain
			-- *****************************************************
			UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
			STRAIGHT_JOIN gaming_bonus_instances AS gbi ON 
				gbi.bonus_instance_id=ggpbi.bonus_instance_id
			SET 
				gbi.bonus_wager_requirement_remain=gbi.bonus_wager_requirement_remain-ggpbi.wager_requirement_contribution,
				gbi.is_secured=LEAST(@countWagerReqMet:=GREATEST(@countWagerReqMet,
					@curWagerReqMet:=IF(ggpbi.now_wager_requirement_met=1, 1, gbi.is_secured)), @curWagerReqMet), 
				gbi.secured_date=IF(ggpbi.now_wager_requirement_met=1, NOW(),NULL),
				gbi.reserved_bonus_funds = gbi.reserved_bonus_funds - (ggpbi.bet_bonus + ggpbi.bet_bonus_win_locked),
				-- current_ring_fenced_amount=current_ring_fenced_amount-bet_ring_fenced,
				-- gaming_bonus_instances.open_rounds=gaming_bonus_instances.open_rounds+1
                ggpbi.now_release_bonus=LEAST(@countReleaseBonus:=GREATEST(@countReleaseBonus,
					@curReleaseBonus:=ggpbi.now_release_bonus), @curReleaseBonus) 
			WHERE ggpbi.game_play_id=gamePlayID AND
				-- parition filtering
				(ggpbi.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID);

			IF (@countWagerReqMet > 0) THEN
				-- *****************************************************      
				-- Wagering Requirement Met
				-- *****************************************************        
				UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
				STRAIGHT_JOIN gaming_bonus_instances ON 
					ggpbi.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
				STRAIGHT_JOIN gaming_bonus_rules ON 
					gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON 
					gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
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
				WHERE ggpbi.game_play_id=gamePlayID AND 
					-- parition filtering
					-- (ggpbi.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID) AND
					-- other filtering
					ggpbi.now_wager_requirement_met=1 AND ggpbi.now_used_all=0;

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
				LEFT JOIN gaming_bonus_rules_deposits ON 
					gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id
				WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND 
					-- parition filtering
					-- (gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID) AND
					-- other filtering
					now_wager_requirement_met=1 AND now_used_all=0;

				SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
				SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;

				IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
					CALL PlaceBetBonusCashExchangeTypeTwo(clientStatID, gamePlayID, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, 
						@bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
				END IF; 
			END IF;

			-- *****************************************************      
			-- Slow Release
			-- *****************************************************
            IF (@countReleaseBonus > 0) THEN
            
				UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
				STRAIGHT_JOIN gaming_bonus_instances ON 
					gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id
				STRAIGHT_JOIN gaming_bonus_rules ON 
					gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON 
					gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id AND 
					transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus')
				SET 
					ggpbi.bonus_transfered_total=LEAST(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-
						transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))*gaming_bonus_instances.transfer_every_amount, 
						bonus_amount_remaining+current_win_locked_amount), 
					ggpbi.bonus_transfered=LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining),
					ggpbi.bonus_win_locked_transfered=ggpbi.bonus_transfered_total-ggpbi.bonus_transfered,
					bonus_amount_remaining=bonus_amount_remaining-bonus_transfered, 
					current_win_locked_amount=current_win_locked_amount-bonus_win_locked_transfered,  
					gaming_bonus_instances.transfer_every_x_last=gaming_bonus_instances.transfer_every_x_last+
						(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-
						transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))*gaming_bonus_instances.transfer_every_x),
					gaming_bonus_instances.bonus_transfered_total=IFNULL(gaming_bonus_instances.bonus_transfered_total,0)+ggpbi.bonus_transfered_total,
					gaming_bonus_instances.session_id=sessionID
				WHERE ggpbi.game_play_id=gamePlayID AND 
					-- parition filtering
					-- (ggpbi.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID) AND
					-- other filtering
					ggpbi.now_release_bonus=1 AND ggpbi.now_used_all=0 AND ggpbi.now_wager_requirement_met=0;

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
				LEFT JOIN gaming_bonus_rules_deposits ON 
					gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id
				WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND 
					-- parition filtering
					-- (gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID) AND
					-- other filtering
					now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

				SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
				SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;

				IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
					CALL PlaceBetBonusCashExchangeTypeTwo(clientStatID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, 
						@bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
				END IF; 

			END IF;
            
		END IF; 

	END IF;

	-- *****************************************************
	-- If the bonus is secured than it is no longer active
	-- *****************************************************  
	UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_bonus_instances ON 
		gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
	SET gaming_bonus_instances.is_active=IF(is_active=0, 0, IF(is_secured, 0, 1))
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND
		-- parition filtering
		(gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID);           

	UPDATE gaming_sb_bets 
	SET 
		bet_total=bet_total-betAmount, 
		is_processed=1, 
		is_success=1,
		status_code=5 
	WHERE sb_bet_id=sbBetID;

	IF (isCouponBet) THEN
		SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayID;
        
		CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID, minimalData);
		CALL PlayReturnBonusInfoOnWin(gamePlayID);
	ELSE
		CALL CommonWalletSBReturnData(sbBetID, clientStatID, gamePlayID, minimalData);
	END IF;

    IF (select value_bool from gaming_settings where name='RULE_ENGINE_ENABLED')=1 THEN
        INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, gamePlayID;
    END IF;
    
    CALL NotificationEventCreate(700, sbBetID, clientStatID, 0);
    
	SET statusCode=0;

END root$$

DELIMITER ;

