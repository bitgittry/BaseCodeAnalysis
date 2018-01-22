DROP procedure IF EXISTS `CommonWalletSportsGenericReturnFundsTypeTwo`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsGenericReturnFundsTypeTwo`(
  sbBetID BIGINT, returnData TINYINT(1), backOfficeRequest TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN

	-- First Version :)   
	-- Performance: 2017-01-15
    -- Optimized for Parititioning
  
	-- *****************************************************
	-- Declared variables
	-- *****************************************************
    
	DECLARE vipLevelId BIGINT; 
	DECLARE platformTypeID BIGINT(20);
	DECLARE gamePlayID, clientID, currencyID, clientWagerTypeID, countryID, sessionID, singleMultTypeID, cancelGamePlayID,
		gameManufacturerID, clientStatID, gameRoundID BIGINT DEFAULT -1;

    DECLARE numSingles, numMultiples, sbBetStatusCode, numSinglesFound, numMultiplesFound, topBonusApplicable INT DEFAULT 0;

	DECLARE cancelBonus, cancelBonusWinLocked, exchangeRate, betReal, betBonus, 
		betBonusWinLocked, totalLoyaltyPoints, totalLoyaltyPointsBonus, releasedLockedFunds DECIMAL(18,5);
	DECLARE betAmount, confirmedAmount, cancelledReal, cancelledFreeBet,
		cancelledRealNow, cancelledBonusNow, cancelledBonusWinLockedNow, cancelledFreeBetNow, cancelledTotalNow, FreeBonusAmount DECIMAL(18,5) DEFAULT 0;

	DECLARE roundType, licenseType VARCHAR(20) DEFAULT NULL; 
	DECLARE currentVipType VARCHAR(100) DEFAULT '';

	DECLARE playLimitEnabled, bonusEnabledFlag, isAlreadyProcessed, bonusReqContributeRealOnly, 
		loyaltyPointsEnabledWager, ringFencedEnabled, ruleEngineEnabled, taxEnabled, isCouponBet TINYINT(1) DEFAULT 0;
  	DECLARE licenseTypeID TINYINT(4) DEFAULT 3; -- sports
	
    DECLARE partitioningMinusFromMax INT DEFAULT 10000;
	DECLARE minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, 
		minSbBetMultipleSingleID, maxSbBetMultipleSingleID, minGameRoundID, maxGameRoundID, 
		minGamePlaySBID, maxGamePlaySBID, minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID BIGINT DEFAULT NULL; 

	-- *****************************************************
	-- Set defaults
	-- *****************************************************
	SET licenseType='sportsbook';
	SET statusCode = 0;
  
	-- *****************************************************
	-- Check the bet exists and it is in the correct status
	-- *****************************************************
	SELECT gsb.sb_bet_id, gsb.game_manufacturer_id, IFNULL(gsb.wager_game_play_id, -1), 
		gsb.client_stat_id, gsb.bet_total, gsb.num_singles, gsb.num_multiplies, gsb.status_code, gsb.lottery_dbg_ticket_id IS NOT NULL,
		gsbpf.max_sb_bet_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_single_id, 
		gsbpf.max_sb_bet_multiple_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_id,
		gsbpf.max_sb_bet_multiple_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_single_id,
		gsbpf.min_game_round_id, gsbpf.max_game_round_id, 
		gsbpf.max_game_play_sb_id-partitioningMinusFromMax, gsbpf.max_game_play_sb_id,
        gsbpf.max_game_play_bonus_instance_id-partitioningMinusFromMax, gsbpf.max_game_play_bonus_instance_id
	INTO sbBetID, gameManufacturerID, gamePlayID, 
		clientStatID, betAmount, numSingles, numMultiples, sbBetStatusCode, isCouponBet,
		minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, minSbBetMultipleSingleID, maxSbBetMultipleSingleID,
		minGameRoundID, maxGameRoundID, minGamePlaySBID, maxGamePlaySBID, 
        minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID
	FROM gaming_sb_bets AS gsb
	LEFT JOIN gaming_sb_bets_partition_fields AS gsbpf ON gsbpf.sb_bet_id=gsb.sb_bet_id
	WHERE gsb.sb_bet_id=sbBetID;

	-- *****************************************************
	-- If is not the correct status return
	-- *****************************************************
	IF (gamePlayID = -1 OR clientStatID = -1) THEN
		SET statusCode = 1;
		LEAVE root;
	END IF;
  
	-- *****************************************************
	-- System settings based on operator - per site
	-- *****************************************************
	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, IFNULL(gs3.value_bool,0) AS vb3,
	  IFNULL(gs4.value_bool,0) AS vb4, IFNULL(gs5.value_bool,0) AS vb5, IFNULL(gs6.value_bool,0) AS vb6
	INTO playLimitEnabled, bonusEnabledFlag, ringFencedEnabled,
		loyaltyPointsEnabledWager, ruleEngineEnabled, taxEnabled
	FROM gaming_settings gs1 
	STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	STRAIGHT_JOIN gaming_settings gs3 ON (gs3.name='RING_FENCED_ENABLED')
	STRAIGHT_JOIN gaming_settings gs4 ON (gs4.name='LOYALTY_POINTS_WAGER_ENABLED')
    STRAIGHT_JOIN gaming_settings gs5 ON (gs5.name='RULE_ENGINE_ENABLED')
    STRAIGHT_JOIN gaming_settings gs6 ON (gs6.name='TAX_ON_GAMEPLAY_ENABLED')
	WHERE gs1.name='PLAY_LIMIT_ENABLED';

	-- *****************************************************
	-- Get data from gaming_game_plays
	-- *****************************************************
	SELECT game_round_id, client_stat_id, amount_real, platform_type_id, amount_bonus, amount_bonus_win_locked, loyalty_points, loyalty_points_bonus, 
		game_manufacturer_id, gaming_game_plays.session_id, released_locked_funds
	INTO gameRoundID, clientStatID, betReal, platformTypeID, betBonus, betBonusWinLocked, totalLoyaltyPoints, totalLoyaltyPointsBonus, 
		gameManufacturerID, sessionID, releasedLockedFunds
	FROM gaming_game_plays
	WHERE game_play_id = gamePlayID;

	-- *****************************************************
	-- Get the Player channel
	-- *****************************************************
	CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, @platformTypeID, @platformType, @channelTypeID, @channelType);

	-- *****************************************************
	-- Get exchange rate
	-- *****************************************************
	SELECT exchange_rate, gc.vip_level_id 
	INTO exchangeRate, vipLevelId
	FROM gaming_client_stats
	STRAIGHT_JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
	STRAIGHT_JOIN gaming_clients gc ON gc.client_id = gaming_client_stats.client_id
	WHERE gaming_client_stats.client_stat_id=clientStatID
	LIMIT 1;

	SELECT set_type INTO currentVipType FROM gaming_vip_levels vip WHERE vip.vip_level_id=vipLevelId;

	-- *****************************************************
	-- Lock Player
	-- *****************************************************
	SELECT client_stat_id, client_id, currency_id
	INTO clientStatID, clientID, currencyID 
	FROM gaming_client_stats 
	WHERE client_stat_id=clientStatID 
	FOR UPDATE;

	SELECT license_type_id INTO licenseTypeID FROM gaming_license_type WHERE name = 'sportsbook';
    SELECT client_wager_type_id INTO clientWagerTypeID FROM gaming_client_wager_types WHERE name = 'sb';

	-- *****************************************************
	-- Insert to get game_play_id but values would need to be updated to a later stage
	-- *****************************************************
	INSERT INTO gaming_game_plays 
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_free_bet, amount_other, bonus_lost, jackpot_contribution, 
		timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, 
		pending_bet_real, pending_bet_bonus, currency_id, sign_mult, sb_bet_id, license_type_id, loyalty_points, loyalty_points_bonus, loyalty_points_after, loyalty_points_after_bonus,
		confirmed_amount, is_confirmed, game_play_message_type_id, game_round_id, is_win_placed) 
	SELECT 0, 0, exchangeRate, 0, 0, 0, 0, 0, 0, 0, 
		NOW(), ggp.game_manufacturer_id, ggp.client_id, ggp.client_stat_id, ggp.session_id, gaming_payment_transaction_type.payment_transaction_type_id, 0, 0, 0, 
		0, 0, ggp.currency_id, 1,  ggp.sb_bet_id, ggp.license_type_id, -ggp.loyalty_points, -ggp.loyalty_points_bonus, gcs.current_loyalty_points-ggp.loyalty_points,
		IFNULL(gcs.total_loyalty_points_given_bonus - gcs.total_loyalty_points_used_bonus-ggp.loyalty_points_bonus,0),
		0, 0, gaming_game_play_message_types.game_play_message_type_id, ggp.game_round_id, 0
	FROM gaming_game_plays AS ggp FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_client_stats AS gcs ON gcs.client_stat_id=clientStatID
	STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='BetCancelled' -- 'FundsReturnedSports' 
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=('SportsCancelBet' COLLATE utf8_general_ci)
	WHERE ggp.game_play_id=gamePlayID;

	SET cancelGamePlayID = LAST_INSERT_ID();

	-- *****************************************************  
	-- Get How much was cancelled in total for the whole bet slip (before this procedure)
	-- *****************************************************
	SELECT 
		IFNULL(SUM(amount_real),0) AS amount_real, 
		IFNULL(SUM(amount_bonus-amount_bonus_win_locked_component),0) AS amount_bonus, 
		IFNULL(SUM(amount_bonus_win_locked_component),0) AS amount_bonus_win_locked
	INTO cancelledReal, cancelBonus, cancelBonusWinLocked
	FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
	WHERE sb_bet_id=sbBetID AND 
		-- parition filtering
		(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID) AND
		-- other filtering
        gaming_game_plays_sb.payment_transaction_type_id=20 /* 41 */ AND confirmation_status=1; -- 41=FundsReturnedSports instead of 20=cancel

	-- *****************************************************  
	-- Update the status of gaming_game_plays_sb, gaming_sb_bet_singles & gaming_sb_bet_multiples
	-- *****************************************************
	SELECT sb_multiple_type_id INTO singleMultTypeID FROM gaming_sb_multiple_types WHERE name='Single' AND game_manufacturer_id=gameManufacturerID; 

	IF (numSingles > 0) THEN

		-- *****************************************************
		-- update the status of bet slip entries which need to be processed to cancelled
		-- *****************************************************
		UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
		STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (sb_bet_entry_id) ON 
			(gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.processing_status=1) AND
            -- parition filtering
			(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID) AND
            -- join
			(gaming_game_plays_sb.sb_bet_entry_id=gaming_sb_bet_singles.sb_bet_single_id AND 
				gaming_game_plays_sb.sb_multiple_type_id=singleMultTypeID) AND
            -- parition filtering
			(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
		SET gaming_game_plays_sb.confirmation_status=1;

		-- *****************************************************
		-- update round
		-- *****************************************************
		UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
		STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (sb_bet_entry_id) ON 
			(gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.processing_status=1) AND
            -- parition filtering
			(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID) AND
			-- join
            (gaming_game_rounds.sb_bet_entry_id=gaming_sb_bet_singles.sb_bet_single_id AND 
				gaming_game_rounds.game_round_type_id=4 AND gaming_game_rounds.license_type_id=3) AND
			-- parition filtering
			(gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID)
		SET 
			gaming_game_rounds.is_cancelled = 1, 
			gaming_game_rounds.is_processed = 1, 
			gaming_game_rounds.date_time_end = NOW();

		-- *****************************************************
		-- insert counter transaction in game play sb
		-- *****************************************************
		INSERT INTO gaming_game_plays_sb 
			(game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, 
			amount_bonus, amount_bonus_base, amount_bonus_win_locked_component, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, 
			round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, 
			sb_bet_type, device_type, units, confirmation_status, game_round_id, sb_bet_entry_id)
		SELECT cancelGamePlayID, 20 /* 41 - FundsReturnedSports */ , gaming_game_plays_sb.amount_total, gaming_game_plays_sb.amount_total_base, gaming_game_plays_sb.amount_real, gaming_game_plays_sb.amount_real_base, 
			gaming_game_plays_sb.amount_bonus, gaming_game_plays_sb.amount_bonus_base, gaming_game_plays_sb.amount_bonus_win_locked_component, gaming_game_rounds.date_time_end, 
			exchangeRate, gaming_game_plays_sb.game_manufacturer_id, gaming_game_plays_sb.client_id, gaming_game_plays_sb.client_stat_id, gaming_game_plays_sb.currency_id, gaming_game_plays_sb.country_id,
			gaming_game_plays_sb.round_transaction_no+100, gaming_game_plays_sb.sb_sport_id, gaming_game_plays_sb.sb_region_id, gaming_game_plays_sb.sb_group_id, gaming_game_plays_sb.sb_event_id, gaming_game_plays_sb.sb_market_id, gaming_game_plays_sb.sb_selection_id, gaming_game_plays_sb.sb_bet_id, gaming_game_plays_sb.sb_multiple_type_id, 
			gaming_game_plays_sb.sb_bet_type, gaming_game_plays_sb.device_type, gaming_game_plays_sb.units, 1, gaming_game_plays_sb.game_round_id, gaming_game_plays_sb.sb_bet_entry_id
		FROM gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
		STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (sb_bet_entry_id) ON 
			(gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.processing_status=1) AND
            -- parition filtering
			(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID) AND
			-- join
            (gaming_game_rounds.sb_bet_entry_id=gaming_sb_bet_singles.sb_bet_single_id AND 
				gaming_game_rounds.sb_bet_id=sbBetID AND gaming_game_rounds.game_round_type_id=4 AND gaming_game_rounds.license_type_id=3) AND
			-- parition filtering
			(gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID)
		STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (game_play_id) ON 
			gaming_game_plays_sb.game_play_id=gamePlayID AND gaming_game_plays_sb.game_round_id=gaming_game_rounds.game_round_id AND
            -- parition filtering
			(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
		LEFT JOIN gaming_game_play_message_types ON 
			gaming_game_play_message_types.name=('SportsCancelBet' COLLATE utf8_general_ci); 


		SET numSinglesFound=ROW_COUNT(); 
    
		IF (numSinglesFound > 0) THEN
			SET maxGamePlaySBID=numSinglesFound+LAST_INSERT_ID()-1;
		END IF;
        
		-- *****************************************************
		-- update processing status to processed
		-- *****************************************************
		UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
		SET processing_status=3 
		WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID AND 
			-- parition filtering
			(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID) AND
			-- other filtering
            gaming_sb_bet_singles.processing_status=1;

	END IF;

	IF (numMultiples > 0) THEN

		-- *****************************************************
		-- update the status of bet slip entries which need to be processed to cancelled
		-- *****************************************************
		UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
		STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (sb_bet_entry_id) ON 
			(gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.processing_status=1) AND
            -- parition filtering
			(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID) AND
			-- join
			(gaming_game_plays_sb.sb_bet_entry_id=gaming_sb_bet_multiples.sb_bet_multiple_id AND 
				gaming_game_plays_sb.sb_multiple_type_id!=singleMultTypeID) AND
			-- parition filtering
			(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
		SET gaming_game_plays_sb.confirmation_status=1;

		UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
		STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (sb_bet_entry_id) ON 
			(gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.processing_status=1) AND
            -- parition filtering
			(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID) AND
			-- join
			(gaming_game_plays_sb.sb_bet_entry_id=gaming_sb_bet_multiples.sb_bet_multiple_id AND 
				gaming_game_plays_sb.sb_multiple_type_id!=singleMultTypeID) AND
            -- parition filtering
			(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)    
		STRAIGHT_JOIN gaming_sb_bet_multiples_singles FORCE INDEX (sb_bet_multiple_id) ON 
			gaming_sb_bet_multiples_singles.sb_bet_multiple_id=gaming_sb_bet_multiples.sb_bet_multiple_id
		SET gaming_sb_bet_multiples_singles.is_cancelled=1;

		-- *****************************************************
		-- update round
		-- *****************************************************
		UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
		STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (sb_bet_entry_id) ON 
			(gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.processing_status=1) AND
            -- parition filtering
			(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID) AND
            -- join
			(gaming_game_rounds.sb_bet_entry_id=gaming_sb_bet_multiples.sb_bet_multiple_id AND 
				gaming_game_rounds.game_round_type_id=5 AND gaming_game_rounds.license_type_id=3) AND
			-- parition filtering
			(gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID)
		SET gaming_game_rounds.is_cancelled=1, 
			gaming_game_rounds.is_processed=1, 
			gaming_game_rounds.date_time_end=NOW();        

		-- *****************************************************
		-- insert counter transaction in game play sb
		-- *****************************************************
		INSERT INTO gaming_game_plays_sb 
			(game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, 
			amount_bonus, amount_bonus_base, amount_bonus_win_locked_component, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, 
			round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, 
			sb_bet_type, device_type, units, confirmation_status, game_round_id, sb_bet_entry_id)
		SELECT cancelGamePlayID, 20 /* 41 - FundsReturnedSports */ , gaming_game_plays_sb.amount_total, gaming_game_plays_sb.amount_total_base, gaming_game_plays_sb.amount_real, gaming_game_plays_sb.amount_real_base, 
			gaming_game_plays_sb.amount_bonus, gaming_game_plays_sb.amount_bonus_base, gaming_game_plays_sb.amount_bonus_win_locked_component, gaming_game_rounds.date_time_end, 
			exchangeRate, gaming_game_plays_sb.game_manufacturer_id, gaming_game_plays_sb.client_id, gaming_game_plays_sb.client_stat_id, gaming_game_plays_sb.currency_id, gaming_game_plays_sb.country_id,
			gaming_game_plays_sb.round_transaction_no+100, gaming_game_plays_sb.sb_sport_id, gaming_game_plays_sb.sb_region_id, gaming_game_plays_sb.sb_group_id, gaming_game_plays_sb.sb_event_id, gaming_game_plays_sb.sb_market_id, gaming_game_plays_sb.sb_selection_id, gaming_game_plays_sb.sb_bet_id, gaming_game_plays_sb.sb_multiple_type_id, 
			gaming_game_plays_sb.sb_bet_type, gaming_game_plays_sb.device_type, gaming_game_plays_sb.units, 1, gaming_game_plays_sb.game_round_id, gaming_game_plays_sb.sb_bet_entry_id
		FROM gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
		STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (sb_bet_entry_id) ON 
			(gaming_game_rounds.sb_bet_id=sbBetID AND gaming_game_rounds.sb_bet_entry_id=gaming_sb_bet_multiples.sb_bet_multiple_id AND 
				gaming_game_rounds.game_round_type_id=5 AND gaming_game_rounds.license_type_id=3) AND
			-- parition filtering
			(gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID)
		STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (game_play_id) ON 
			gaming_game_plays_sb.game_play_id=gamePlayID AND gaming_game_plays_sb.game_round_id=gaming_game_rounds.game_round_id
		LEFT JOIN gaming_game_play_message_types ON 
			gaming_game_play_message_types.name=('SportsCancelBetMult' COLLATE utf8_general_ci)
		WHERE (gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.processing_status=1) AND
			-- parition filtering
			(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID);
        
        SET numMultiplesFound=ROW_COUNT();
    
		IF (numMultiplesFound > 0) THEN
			SET maxGamePlaySBID=numMultiplesFound+LAST_INSERT_ID()-1;
		END IF;
		
		-- update processing status to processed
		UPDATE gaming_sb_bet_multiples 
		SET processing_status=3 
		WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND 
			-- parition filtering
			(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID) AND
			-- other filtering
			gaming_sb_bet_multiples.processing_status=1;

	END IF;

	-- *****************************************************
	-- Get How much was confirmed by this stored procedure
	-- *****************************************************
	SELECT 
		IFNULL(SUM(amount_real), 0) - cancelledReal AS amount_real, 
		IFNULL(SUM(amount_bonus - amount_bonus_win_locked_component), 0) - cancelBonus AS amount_bonus, 
		IFNULL(SUM(amount_bonus_win_locked_component), 0) - cancelBonusWinLocked AS amount_bonus_win_locked
	INTO cancelledRealNow, cancelledBonusNow, cancelledBonusWinLockedNow
	FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
	WHERE gaming_game_plays_sb.sb_bet_id=sbBetID AND 
		-- parition filtering
		(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID) AND
		-- other filtering
		gaming_game_plays_sb.payment_transaction_type_id=20 /* 41 - FundsReturnedSports */ ;

	-- *****************************************************
	-- Get Total to cancel
	-- *****************************************************
	SET cancelledTotalNow=cancelledRealNow+cancelledBonusNow+cancelledBonusWinLockedNow;

	-- *****************************************************
	-- Return Error if there was noting to confirm
	-- *****************************************************
	IF (cancelledTotalNow=0) THEN
		DELETE FROM gaming_game_plays WHERE game_play_id=cancelGamePlayID;

		SET statusCode=2;
		LEAVE root;
	END IF;

	-- *****************************************************
	-- Return bonus funds if needed
	-- The procedure calculates in ratios but normally the ration of bet and cancellation will be 1.0
	-- *****************************************************
	CALL CommonWalletSportsGenericReturnBonusesTypeTwo(sbBetID, maxGamePlaySBID,
		cancelGamePlayID, cancelledTotalNow, cancelledRealNow, cancelledBonusNow, cancelledBonusWinLockedNow);

	UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_bonus_instances ON 
		gaming_game_plays_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
	SET
		gaming_game_plays_bonus_instances.wager_requirement_contribution_cancelled = gaming_game_plays_bonus_instances.wager_requirement_contribution,
		gaming_game_plays_bonus_instances.win_bonus = gaming_game_plays_bonus_instances.bet_bonus, 
		gaming_game_plays_bonus_instances.win_bonus_win_locked = gaming_game_plays_bonus_instances.bet_bonus_win_locked, 
		gaming_game_plays_bonus_instances.win_real = gaming_game_plays_bonus_instances.bet_real
	WHERE gaming_game_plays_bonus_instances.game_play_id = gamePlayID AND
		-- parition filtering
		(gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID);
    
    SET topBonusApplicable = ROW_COUNT();

	INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) 
	VALUES (NOW(), gameRoundID);
    
	INSERT INTO gaming_game_plays_bonus_instances_wins 
		(game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, timestamp, exchange_rate, win_real, win_bonus, win_bonus_win_locked, 
		lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution,bonus_order)
	SELECT LAST_INSERT_ID(), game_play_bonus_instance_id, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, NOW(), exchangeRate, win_real, 
		win_bonus, win_bonus_win_locked, 0, 0, gaming_bonus_instances.client_stat_id, cancelGamePlayID, 0, bonus_order
	FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_game_plays_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
	WHERE gaming_game_plays_bonus_instances.game_play_id = gamePlayID AND
		-- parition filtering
		(gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID);

	-- *****************************************************
	-- UPDATE gaming_bonus_instances (Part 1)
	-- *****************************************************
	UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_bonus_instances ON 
		gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
	SET 
    /**
    * Changed because add aditional amount to bonus_amount_remaining if the sum of (win_bonus+bonus_amount_remaining) is larger than bonus_amount_given
    * bonus_amount_remaining = bonus_amount_remaining + IF(is_lost, 0, win_bonus),
    */
    bonus_amount_remaining = IF((bonus_amount_remaining + IF(is_lost, 0, win_bonus)) > bonus_amount_given, bonus_amount_given, bonus_amount_remaining + IF(is_lost, 0, win_bonus)),		
    current_win_locked_amount = current_win_locked_amount + IF(is_lost, 0, win_bonus_win_locked),
		bonus_wager_requirement_remain = bonus_wager_requirement_remain + IF(is_lost, 0, wager_requirement_contribution_cancelled),
		bonus_wager_requirement_remain_after = bonus_wager_requirement_remain_after + IF(is_lost, 0, wager_requirement_contribution_cancelled),
		is_used_all = IF(is_active = 1 AND gaming_bonus_instances.open_rounds - (numMultiples + numSingles) <= 0 AND is_used_all = 0 AND is_lost = 0 
			AND (bonus_amount_remaining + IF(is_lost, 0, win_bonus)) = 0 AND (current_win_locked_amount + IF(is_lost, 0, win_bonus_win_locked))=0, 
		1, 0)
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND
		-- parition filtering
		(gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID);

	-- *****************************************************
	-- UPDATE gaming_bonus_instances (Part 2)
	-- *****************************************************
	UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_bonus_instances ON 
		gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
	SET 
		used_all_date = IF(is_used_all = 1 AND used_all_date IS NULL, NOW(), used_all_date),
		gaming_bonus_instances.is_active = IF(is_used_all, 0, gaming_bonus_instances.is_active),
		is_secured = IF(is_secured AND wager_requirement_contribution_cancelled > 0, 0, is_secured),
		open_rounds = gaming_bonus_instances.open_rounds - (numSingles + numMultiples)
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND
		-- parition filtering
		(gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID);
 

	UPDATE gaming_client_stats AS gcs
    STRAIGHT_JOIN gaming_client_wager_types ON gaming_client_wager_types.client_wager_type_id = clientWagerTypeID
	LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id = sessionID
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id = gaming_client_wager_types.client_wager_type_id
	SET 
		gcs.locked_real_funds = gcs.locked_real_funds + releasedLockedFunds,

		current_real_balance = current_real_balance + cancelledRealNow, -- TODO: Changed: This si from Lettery :: current_real_balance + betReal,
		current_bonus_balance = current_bonus_balance + cancelledBonusNow, -- TODO: Changed: This si from Lettery :: current_bonus_balance + betBonus - cancelBonus, 
		current_bonus_win_locked_balance = current_bonus_win_locked_balance + cancelledBonusWinLockedNow, -- TODO: Changed: This si from Lettery :: current_bonus_win_locked_balance + betBonusWinLocked - cancelBonusWinLocked, 
		gcs.bet_from_real = IF(topBonusApplicable < 1, gcs.bet_from_real, GREATEST(0, gcs.bet_from_real)),

		gcs.pending_bets_real = pending_bets_real - cancelledRealNow,  -- TODO: This is added from another SB query
		gcs.pending_bets_bonus = pending_bets_bonus - (cancelledBonusNow + cancelledBonusWinLockedNow),  -- TODO: This is added from another SB query
		gcs.total_loyalty_points_given = gcs.total_loyalty_points_given - IFNULL(totalLoyaltyPoints, 0),
        gcs.current_loyalty_points = gcs.current_loyalty_points - IFNULL(totalLoyaltyPoints, 0),
		gcs.total_loyalty_points_given_bonus = gcs.total_loyalty_points_given_bonus - IFNULL(totalLoyaltyPointsBonus, 0),
        gcs.loyalty_points_running_total = IF(currentVipType = 'LoyaltyPointsPeriod', loyalty_points_running_total - IFNULL(totalLoyaltyPoints, 0), loyalty_points_running_total),
		
		-- gaming_client_sessions
		gcss.bets = gcss.bets - 1,
		gcss.total_bet_real = gcss.total_bet_real + cancelledRealNow,
		gcss.total_bet_bonus = gcss.total_bet_bonus + cancelledBonusNow + cancelledBonusWinLockedNow,
		gcss.loyalty_points = gcss.loyalty_points - IFNULL(totalLoyaltyPoints,0), 
		gcss.loyalty_points_bonus = gcss.loyalty_points_bonus - IFNULL(totalLoyaltyPointsBonus,0),
		
		-- gaming_client_wager_types
		gcws.num_bets = gcws.num_bets - 1,
		gcws.total_real_wagered = gcws.total_real_wagered + cancelledRealNow,
		gcws.total_bonus_wagered = gcws.total_bonus_wagered + (cancelledBonusNow + cancelledBonusWinLockedNow),
		gcws.loyalty_points = gcws.loyalty_points - IFNULL(totalLoyaltyPoints,0),
		gcws.loyalty_points_bonus = gcws.loyalty_points_bonus - IFNULL(totalLoyaltyPointsBonus,0)
	WHERE gcs.client_stat_id = clientStatID;
	
	-- Update vip level of the client
	IF (loyaltyPointsEnabledWager AND vipLevelID IS NOT NULL AND vipLevelID > 0) THEN
		CALL PlayerUpdateVIPLevel(clientStatID,0);
	END IF;

	-- *****************************************************  
	-- Fix the values in the cancel transaction
	-- *****************************************************
	UPDATE gaming_game_plays AS ggp FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
	SET 
		ggp.amount_total=cancelledTotalNow,
		ggp.amount_total_base=cancelledTotalNow/exchangeRate,
		ggp.amount_real=cancelledRealNow,
		ggp.amount_bonus=cancelledBonusNow,
		ggp.amount_bonus_win_locked=cancelledBonusWinLockedNow, 
		ggp.amount_free_bet=0, -- To Check with Steve
		ggp.amount_other=0,
		ggp.bonus_lost=@bonusLost+@bonusWinLockedLost,
		ggp.balance_real_after=current_real_balance, 
		ggp.balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance, 
		ggp.balance_bonus_win_locked_after=current_bonus_win_locked_balance, 
		ggp.pending_bet_real=gaming_client_stats.pending_bets_real, 
		ggp.pending_bet_bonus=gaming_client_stats.pending_bets_bonus
	WHERE ggp.game_play_id=cancelGamePlayID;

	-- *****************************************************
	-- Update ring fenced statistics
	-- *****************************************************
    IF (ringFencedEnabled) THEN
		CALL GameUpdateRingFencedBalances(clientStatID, cancelGamePlayID);    
	END IF;

	-- *****************************************************
	-- Update the betslip status
	-- *****************************************************
	UPDATE gaming_sb_bets 
	SET 
		num_singles=num_singles-numSinglesFound, 
		num_multiplies=num_multiplies-numMultiplesFound,
		amount_real=amount_real-cancelledRealNow, 
		amount_bonus=amount_bonus-cancelledBonusNow, 
		amount_bonus_win_locked=amount_bonus_win_locked-cancelledBonusWinLockedNow, 
		amount_free_bet=IFNULL(FreeBonusAmount,0), -- Check with Steve
		status_code=IF((num_singles+num_multiplies)=0, 4, 6)
	WHERE sb_bet_id=sbBetID;
  
	IF (playLimitEnabled) THEN 
		CALL PlayLimitsUpdate(clientStatID, licenseType, cancelledTotalNow*-1, 1);
	END IF;

	-- *****************************************************
	-- Return data to the application 
	-- *****************************************************
	IF (isCouponBet AND returnData AND NOT backOfficeRequest) THEN 
		
        CALL PlayReturnDataWithoutGame(cancelGamePlayID, gameRoundID, clientStatID, gameManufacturerID, minimalData);
		CALL PlayReturnBonusInfoOnWin(cancelGamePlayID);
        
        IF (loyaltyPointsEnabledWager AND totalLoyaltyPoints != 0) THEN
			CALL PlayerUpdateVIPLevel(clientStatID, 0);
		END IF;
        
	ELSEIF (returnData) THEN 
	
		CALL CommonWalletSBReturnData(sbBetID, clientStatID, cancelGamePlayID, minimalData);  
	
    END IF;
  	
	-- *****************************************************
	-- Just In Case
	-- *****************************************************
    /*
	SELECT IF(current_bonus_balance!=IFNULL(bonus_amount_remaining,0) OR current_bonus_win_locked_balance!=IFNULL(current_win_locked_amount,0), 1, 0) 
	INTO @bonusMismatch 
	FROM gaming_client_stats 
	LEFT JOIN
	(
		SELECT client_stat_id, SUM(bonus_amount_remaining) AS bonus_amount_remaining, SUM(current_win_locked_amount) AS current_win_locked_amount
		FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
		WHERE gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 AND gaming_bonus_instances.is_free_rounds_mode=0
		GROUP BY client_stat_id
	) AS PB ON gaming_client_stats.client_stat_id=PB.client_stat_id
	WHERE gaming_client_stats.client_stat_id=clientStatID; 

	IF (@bonusMismatch=1) THEN
		CALL BonusAdjustBonusBalance(clientStatID);
	END IF;
	*/
    
	-- Update master record in gaming_game_rounds to reflect ReturnFunds operation
	SET numSingles = (numSingles + numMultiples) - (numSinglesFound + numMultiplesFound);
    
	UPDATE gaming_game_rounds AS ggr FORCE INDEX (sb_bet_id)
	STRAIGHT_JOIN gaming_client_stats AS gcs FORCE INDEX (PRIMARY) ON ggr.client_stat_id = gcs.client_stat_id
	SET
		ggr.bet_total = ggr.bet_total - cancelledTotalNow,
		ggr.bet_total_base = ggr.bet_total_base - (cancelledTotalNow / ggr.exchange_rate),
		ggr.bet_real = ggr.bet_real - cancelledRealNow,
		ggr.bet_bonus = ggr.bet_bonus - cancelledBonusNow,
		ggr.bet_bonus_win_locked = ggr.bet_bonus_win_locked - cancelledBonusWinLockedNow,
		ggr.balance_real_after = gcs.current_real_balance,
		ggr.balance_bonus_after = gcs.current_bonus_balance,
		ggr.num_bets = ggr.num_bets - (numSinglesFound + numMultiplesFound),
		ggr.num_transactions = ggr.num_transactions + 1,
		ggr.is_cancelled = IF(numSingles = 0, 1, 0),
		ggr.is_processed = IF(numSingles = 0, 1, ggr.is_processed),
		ggr.date_time_end = IF(numSingles = 0, NOW(), ggr.date_time_end),
		ggr.loyalty_points = ggr.loyalty_points - totalLoyaltyPoints,
		ggr.loyalty_points_bonus = ggr.loyalty_points_bonus - totalLoyaltyPointsBonus
	WHERE ggr.sb_bet_id=sbBetID AND ggr.sb_extra_id IS NULL AND ggr.license_type_id=3; 

	UPDATE gaming_sb_bets_partition_fields
	SET 
		max_game_play_sb_id=maxGamePlaySBID
	WHERE sb_bet_id=sbBetID;

	SET statusCode=0;

END root$$

DELIMITER ;

