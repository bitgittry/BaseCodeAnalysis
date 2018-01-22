DROP procedure IF EXISTS `ReserveFundsTypeTwoLotto`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `ReserveFundsTypeTwoLotto`(
  couponID BIGINT, sessionID BIGINT, ignoreSessionExpiry TINYINT(1), realMoneyOnly TINYINT(1), OUT statusCode INT)
root:BEGIN
	-- Not securing bonus
    -- Added gaming_game_play_message_types 
    -- Play Limit Check and Update called per game
	-- Optimizations: Forcing STRAIGHT_JOINS and INDEXES 
    -- Merged in INPH
    -- Optimized 
	-- Added checking of total coupon cost against game limits if there is more than 1 game
	-- Performance Revision January-2017
    
	DECLARE clientStatID, gameManufacturerID, clientID, currencyID, lotteryTransactionID, fraudClientEventID, gamePlayID, gameRoundID, gamePlayBetCounterID,
		topBonusRuleID BIGINT DEFAULT -1;
	DECLARE gameID BIGINT DEFAULT NULL;
    DECLARE betAmount, balanceReal, balanceBonus, balanceWinLocked, betRemain, FreeBonusAmount,balanceRealBefore ,balanceBonusBefore, exchangeRate,
		betReal, betBonus, betBonusWinLocked, loyaltyBetBonus, bonusWagerRequirementRemain, loyaltyPointsBonus, pendingBetsReal, pendingBetsBonus, loyaltyPoints, totalLoyaltyPointsGivenBonus, totalLoyaltyPointsUsedBonus, lockedRealFunds DECIMAL(18,5) DEFAULT 0;
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
			
			CALL PlayReturnDataWithoutGame(IFNULL(gamePlayID,0), IFNULL(gameRoundID,0), clientStatID, gameManufacturerID, 0);
			CALL PlayReturnBonusInfoOnBet(IFNULL(gamePlayID,0));

			SET statusCode = 100; -- For Already Processed
			LEAVE root;
		ELSE
			SET statusCode = 10; -- Coupon already in another state
			LEAVE root;
		END IF;
    END IF;
	
    -- get player balance details plus lock the player so no other transaction can adjust his balance, till this is finished
	SELECT  gaming_client_stats.client_id, currency_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, pending_bets_real, pending_bets_bonus, current_loyalty_points, total_loyalty_points_given_bonus, total_loyalty_points_used_bonus, locked_real_funds
	INTO clientID, currencyID, balanceReal, balanceBonus, balanceWinLocked, pendingBetsReal, pendingBetsBonus, loyaltyPoints, totalLoyaltyPointsGivenBonus, totalLoyaltyPointsUsedBonus, lockedRealFunds
	FROM gaming_client_stats FORCE INDEX (PRIMARY)
	WHERE gaming_client_stats.client_stat_id=clientStatID
	FOR UPDATE;

    SELECT IFNULL(COUNT(*), 0), IFNULL(SUM(participation_cost),0), COUNT(DISTINCT gaming_lottery_dbg_tickets.game_id), gaming_lottery_dbg_tickets.game_id INTO numParticipations, betAmount, numGames, gameID
    FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON 
		gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND 
        gaming_lottery_participations.lottery_wager_status_id = 2 /*requires get funds*/
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
      
	SELECT gaming_license_type.`name`, gaming_client_wager_types.client_wager_type_id  
	INTO licenseType, clientWagerTypeID
	FROM gaming_license_type 
	JOIN gaming_client_wager_types ON gaming_client_wager_types.license_type_id = gaming_license_type.license_type_id
	WHERE gaming_license_type.license_type_id = licenseTypeID;
    
	SET balanceRealBefore=balanceReal;
	SET balanceBonusBefore=balanceBonus+balanceWinLocked;

	-- check any player restrictions
	SELECT gaming_clients.is_account_closed OR gaming_fraud_rule_client_settings.block_account, gaming_clients.is_play_allowed AND !gaming_fraud_rule_client_settings.block_gameplay, sessions_main.status_code, gaming_clients.vip_level_id, gaming_operator_currency.exchange_rate, gaming_vip_levels.set_type
	INTO isAccountClosed, isPlayAllowed, sessionStatusCode, vipLevelID, exchangeRate, currentVipType
	FROM gaming_clients FORCE INDEX (PRIMARY)
	JOIN gaming_operator_currency ON gaming_operator_currency.currency_id = currencyID
    LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
    LEFT JOIN sessions_main FORCE INDEX (PRIMARY) ON sessions_main.session_id = sessionID AND sessions_main.extra_id=gaming_clients.client_id
	LEFT JOIN gaming_vip_levels ON gaming_vip_levels.vip_level_id = gaming_clients.vip_level_id 
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
				STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON 
					gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND 
                    gaming_lottery_participations.lottery_wager_status_id = 2 /*requires get funds*/
				STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_lottery_participations.lottery_draw_id
				WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID
				GROUP BY gaming_lottery_draws.game_id
			) AS XX;
		END IF;
 
		IF (isLimitExceeded>0) THEN
       IF (isLimitExceeded = 10) THEN
  	    SET statusCode = 11;
       ELSE
        SET statusCode = 7;
      END IF;
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
		STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON 
			gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND 
            gaming_lottery_participations.lottery_wager_status_id = 2 /*requires get funds*/
		SET gaming_lottery_participations.lottery_wager_status_id=7, gaming_lottery_participations.error_code=statusCode
		WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
        
		UPDATE gaming_lottery_coupons
		SET gaming_lottery_coupons.lottery_wager_status_id = 7, gaming_lottery_coupons.error_code=statusCode
		WHERE gaming_lottery_coupons.lottery_coupon_id = couponID;
    
		LEAVE root;
	END IF;
  
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
				@freeBonusAmount := @freeBonusAmount + IF(awarding_type='FreeBet' OR is_free_bonus,@freeBetBonus,0),
				no_loyalty_points
			FROM
			(
				SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_types_awarding.name AS awarding_type, bonus_amount_remaining, current_win_locked_amount, gaming_bonus_rules.no_loyalty_points,current_ring_fenced_amount,is_free_bonus
				FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
				STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
				WHERE gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 AND gaming_bonus_instances.is_free_rounds_mode=0
				ORDER BY gaming_bonus_instances.is_freebet_phase ASC, gaming_bonus_instances.given_date ASC, gaming_bonus_instances.bonus_instance_id ASC
			) AS XX
		) AS XY;

		
		SET FreeBonusAmount = @freeBonusAmount;

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
		STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON 
			gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id AND 
            gaming_lottery_participations.lottery_wager_status_id = 2
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
	gcs.locked_real_funds = GREATEST(0, gcs.locked_real_funds - betReal),
	
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
		(amount_total, game_round_id, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, amount_other, bonus_lost, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, pending_bet_real, pending_bet_bonus, currency_id, sign_mult, license_type_id,loyalty_points, loyalty_points_bonus,loyalty_points_after, loyalty_points_after_bonus, sb_bet_id, game_play_message_type_id, is_win_placed, platform_type_id,is_processed,game_id, released_locked_funds) 
	SELECT betAmount, gameRoundID, betAmount/exchangeRate, exchangeRate, betReal, betBonus, betBonusWinLocked,IFNULL(FreeBonusAmount,0), 0, 0,NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gaming_payment_transaction_type.payment_transaction_type_id, balanceReal - betReal, (balanceBonus-betBonus)+(balanceWinLocked-betBonusWinLocked), balanceWinLocked - betBonusWinLocked, pendingBetsReal, pendingBetsBonus, currencyID, -1, licenseTypeID, @totalLoyaltyPoints, @totalLoyaltyPointsBonus, loyaltyPoints + IFNULL(@totalLoyaltyPoints,0), IFNULL((totalLoyaltyPointsGivenBonus + IFNULL(@totalLoyaltyPointsBonus,0)) - totalLoyaltyPointsUsedBonus,0), couponID, gaming_game_play_message_types.game_play_message_type_id, 0, @platformTypeID, 1, gameID, LEAST(lockedRealFunds, betReal)
	FROM gaming_payment_transaction_type
	STRAIGHT_JOIN gaming_game_play_message_types ON gaming_game_play_message_types.`name`= CAST(CASE licenseTypeID WHEN 6 THEN 'LotteryBet' WHEN 7 THEN 'SportsPoolBet' END AS CHAR(80))	
    WHERE gaming_payment_transaction_type.name = 'Bet';
    
    SET gamePlayID = LAST_INSERT_ID();
     
	UPDATE gaming_lottery_transactions SET game_play_id = gamePlayID WHERE lottery_coupon_id = couponID and is_latest = 1;
   
	IF(vipLevelID IS NOT NULL) THEN
		CALL PlayerUpdateVIPLevel(clientStatID,0);
	END IF;
 
    INSERT INTO gaming_game_plays_lottery(game_play_id, lottery_coupon_id) VALUES (gamePlayID, couponID);
    
    UPDATE gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON 
		gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
    STRAIGHT_JOIN gaming_game_plays_lottery_entries FORCE INDEX (lottery_participation_id) ON 
		gaming_game_plays_lottery_entries.lottery_participation_id  = gaming_lottery_participations.lottery_participation_id
    SET gaming_game_plays_lottery_entries.game_play_id = gamePlayID , gaming_lottery_participations.lottery_wager_status_id = 3
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
    
    UPDATE gaming_lottery_coupons
	LEFT JOIN gaming_channel_types ON gaming_channel_types.channel_type_id = @channelTypeID
    SET gaming_lottery_coupons.lottery_wager_status_id = 3, wager_game_play_id = gamePlayID, 
		gaming_lottery_coupons.platform_type_id = @platformTypeID, gaming_lottery_coupons.channel_type_id = @channelTypeID,
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
		gaming_game_rounds.sb_extra_id=gaming_game_plays_lottery_entries.lottery_participation_id AND gaming_game_rounds.license_type_id = licenseTypeID 
    WHERE gaming_game_plays_lottery_entries.game_play_id = gamePlayID;

	IF (playLimitEnabled AND betAmount > 0) THEN 

		SELECT SUM(PlayLimitsUpdateFunc(sessionID, clientStatID, licenseType, game_cost, 1, game_id)) 
		INTO @numUpdateLimitErrors
		FROM
		(
			SELECT gaming_lottery_draws.game_id, COUNT(*) AS num_participations, SUM(gaming_lottery_participations.participation_cost) AS game_cost 
			FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
			STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON 
				gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND 
                gaming_lottery_participations.lottery_wager_status_id = 3 /*funds reserved*/
			STRAIGHT_JOIN gaming_lottery_draws ON 
				gaming_lottery_draws.lottery_draw_id = gaming_lottery_participations.lottery_draw_id
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
    
	 CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID, 0);
     CALL PlayReturnBonusInfoOnBet(gamePlayID);
     
     
END$$

DELIMITER ;

