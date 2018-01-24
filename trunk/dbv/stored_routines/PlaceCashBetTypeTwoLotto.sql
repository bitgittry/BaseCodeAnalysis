DROP procedure IF EXISTS `PlaceCashBetTypeTwoLotto`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceCashBetTypeTwoLotto`(couponID BIGINT, sessionID BIGINT, paymentMethod VARCHAR(80), OUT statusCode INT)
root:BEGIN

	DECLARE clientStatID, gameManufacturerID, clientID, currencyID, gamePlayID, gameRoundID,
		topBonusRuleID BIGINT DEFAULT -1;
    DECLARE betAmount, balanceReal, betRemain, exchangeRate,
		betCash,  bonusWagerRequirementRemain DECIMAL(18,5) DEFAULT 0;
    DECLARE isAccountClosed, isPlayAllowed, topBonusApplicable, dominantNoLoyaltyPoints, bonusReqContributeRealOnly,
		 bonusEnabledFlag, fraudEnabled, playerRestrictionEnabled, licenceCountryRestriction, wagerReqRealOnly, isFreeBetPhase, loyaltyPointsEnabled, loyaltyPointsEnabledWager, loyaltyPointsDisabledTypeTwo, channelCashEnabled, allowCashTransaction ,ruleEngineEnabled TINYINT(1) DEFAULT 0;
    DECLARE numParticpations,vipLevelID,sessionStatusCode,licenseTypeID,clientWagerTypeID,wagerStatusCode, errorCode, numGames, platformTypeID INT;
    DECLARE currentVipType VARCHAR(100) DEFAULT '';
	DECLARE licenseType VARCHAR(80);
	DECLARE paymentMethodID, topBonusInstanceID BIGINT(20);

	SET statusCode =0;
    
  -- Get coupon details
	SELECT client_stat_id, gaming_lottery_coupons.game_manufacturer_id, MAX(gaming_lottery_participations.lottery_wager_status_id), gaming_lottery_coupons.error_code, gaming_lottery_coupons.platform_type_id, license_type_id
	INTO clientStatID, gameManufacturerID, wagerStatusCode, errorCode, platformTypeID, licenseTypeID
	FROM gaming_lottery_coupons 
    STRAIGHT_JOIN gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id) ON gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
	WHERE gaming_lottery_coupons.lottery_coupon_id=couponID;	
		
  SELECT gs1.value_bool as vb1
  INTO ruleEngineEnabled
  FROM gaming_settings gs1 
  WHERE gs1.name='RULE_ENGINE_ENABLED';
    
    -- get player balance details plus lock the player so no other transaction can adjust his balance, till this is finished
	SELECT gaming_client_stats.client_id, currency_id
	INTO clientID, currencyID
	FROM gaming_client_stats
	WHERE gaming_client_stats.client_stat_id=clientStatID
	FOR UPDATE;

	-- If Wager Status Code is ReadyForGetFunds Skip Validation
    IF (wagerStatusCode != 2) THEN
		IF (wagerStatusCode = 9) THEN
			SELECT gaming_game_plays_lottery.game_play_id, gaming_game_plays.game_round_id
			INTO gamePlayID, gameRoundID
			FROM gaming_lottery_coupons FORCE INDEX (PRIMARY) 
			LEFT JOIN gaming_game_plays_lottery FORCE INDEX (lottery_coupon_id) ON gaming_lottery_coupons.lottery_coupon_id=gaming_game_plays_lottery.lottery_coupon_id
			LEFT JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery.game_play_id
		
			WHERE gaming_game_plays_lottery.lottery_coupon_id = couponID;

			CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID, 0);
			CALL PlayReturnBonusInfoOnBet(gamePlayID);
			SET statusCode = 100;
			LEAVE root;
		ELSE 
			SET statusCode = 10;
			LEAVE root;
		END IF;
     END IF;

	-- Get the Player channel
	CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, @platformTypeID, @platformType, @channelTypeID, @channelType);
	
	-- Check if Cash Enabled for that Channel
	SELECT cash_enabled INTO channelCashEnabled	FROM gaming_channel_types WHERE channel_type = @channelType;
	IF (channelCashEnabled = 0)THEN 
		SET statusCode=11;
		LEAVE root;
	END IF;
		
	SELECT payment_method_id INTO paymentMethodID FROM gaming_payment_method WHERE `name` = paymentMethod;
	
	IF (paymentMethodID IS NULL) THEN
		SET statusCode = 13;
		LEAVE root;
	END IF;

	SELECT allow_cash_transaction INTO allowCashTransaction
	FROM gaming_payment_method
	WHERE payment_method_id = paymentMethodID;
	
	IF (allowCashTransaction = 0) THEN
	SET statusCode = 12;
	LEAVE root;
	END IF;
	      	
    SELECT COUNT(*), SUM(participation_cost), COUNT(DISTINCT gaming_lottery_dbg_tickets.game_id) INTO numParticpations, betAmount, numGames
    FROM gaming_lottery_dbg_tickets 
    STRAIGHT_JOIN gaming_lottery_participations ON gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 2 /*requires get funds*/
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
  	
	SELECT gaming_license_type.`name`, gaming_client_wager_types.client_wager_type_id  
	INTO licenseType, clientWagerTypeID
	FROM gaming_license_type 
	JOIN gaming_client_wager_types ON gaming_client_wager_types.license_type_id = gaming_license_type.license_type_id
	WHERE gaming_license_type.license_type_id = licenseTypeID;
    
	-- CHECK about session status and other player restrictions whether they are required
	SELECT gaming_clients.is_account_closed OR gaming_fraud_rule_client_settings.block_account, gaming_clients.is_play_allowed AND !gaming_fraud_rule_client_settings.block_gameplay, sessions_main.status_code, gaming_clients.vip_level_id,  gaming_operator_currency.exchange_rate, gaming_vip_levels.set_type
	INTO isAccountClosed, isPlayAllowed, sessionStatusCode, vipLevelID, exchangeRate, currentVipType
	FROM gaming_clients FORCE INDEX (PRIMARY)
	JOIN gaming_operator_currency ON gaming_operator_currency.currency_id = currencyID
    LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
    LEFT JOIN sessions_main FORCE INDEX (client_latest_session) ON sessions_main.session_id = sessionID AND sessions_main.extra_id=gaming_clients.client_id
	LEFT JOIN gaming_vip_levels ON gaming_vip_levels.vip_level_id = gaming_clients.vip_level_id 
	WHERE gaming_clients.client_id=clientID;
    
	-- check if can use bonus money 
    SELECT 1, gbi.bonus_instance_id, gbi.no_loyalty_points,1, gbi.bonus_rule_id,bonus_wager_requirement_remain
    INTO topBonusApplicable, topBonusInstanceID, dominantNoLoyaltyPoints,wagerReqRealOnly, topBonusRuleID, bonusWagerRequirementRemain
	FROM (
        SELECT  gbi.bonus_instance_id, gbi.bonus_rule_id, gbr.no_loyalty_points, wager_req_real_only, bonus_wager_requirement_remain, is_freebet_phase
		FROM gaming_bonus_instances AS gbi FORCE INDEX (client_active_bonuses)
		STRAIGHT_JOIN gaming_bonus_rules AS gbr ON gbr.bonus_rule_id = gbi.bonus_rule_id
		WHERE gbi.client_stat_id=clientStatID AND gbi.is_active AND gbi.is_free_rounds_mode=0
		ORDER BY gbi.given_date ASC,gbi.bonus_instance_id ASC LIMIT 1 
	) AS gbi
	STRAIGHT_JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_coupon_id = couponID
    STRAIGHT_JOIN gaming_lottery_participations ON gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 2 /*requires get funds*/
    STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_lottery_participations.lottery_draw_id
	STRAIGHT_JOIN gaming_operator_games ON gaming_lottery_draws.game_id = gaming_operator_games.game_id
    LEFT JOIN gaming_bonus_rules_wgr_req_draw_weights AS gbrwrdw ON gbi.bonus_rule_id=gbrwrdw.bonus_rule_id AND gbrwrdw.lottery_draw_id=gaming_lottery_participations.lottery_draw_id
	LEFT JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON gbi.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=gaming_operator_games.operator_game_id
    WHERE gbrwrw.bonus_wgr_req_weigth  IS NOT NULL OR gbrwrdw.bonus_wgr_req_weigth IS NOT NULL
    HAVING COUNT(*) = numParticpations;


	SELECT IFNULL(gs1.value_bool,0) AS vb1, gs2.value_bool AS vb2, IFNULL(gs3.value_bool,0) AS vb3
	INTO loyaltyPointsEnabledWager, playerRestrictionEnabled, loyaltyPointsDisabledTypeTwo
	FROM gaming_settings gs1 
	JOIN gaming_settings gs2 ON (gs2.name='PLAYER_RESTRICTION_ENABLED')
	LEFT JOIN gaming_settings gs3 ON (gs3.name='LOYALTY_POINTS_DISABLE_IF_WAGERING_BONUS_TYPE_TWO')
	WHERE gs1.name='LOYALTY_POINTS_WAGER_ENABLED';

	SET loyaltyPointsEnabled = IF(loyaltyPointsEnabledWager=0 OR loyaltyPointsDisabledTypeTwo=1,0,1);
	
	IF (isAccountClosed=1 OR clientStatID = -1) THEN
		SET statusCode=1;
	ELSEIF (isPlayAllowed=0) THEN 
		SET statusCode=2;
	END IF;

	-- Player Restrictions
	IF (statusCode=0 AND playerRestrictionEnabled) THEN
		SET @numRestrictions=0; SET @restrictionType=NULL;
        
		SELECT restriction_types.name, COUNT(*) INTO @restrictionType, @numRestrictions
		FROM gaming_player_restrictions
		STRAIGHT_JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_play=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
		LEFT JOIN gaming_license_type ON gaming_player_restrictions.license_type_id=gaming_license_type.license_type_id
		WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date AND
		(gaming_license_type.name IS NULL OR gaming_license_type.license_type_id=licenseTypeID OR gaming_license_type.license_type_id=4);

		IF (@numRestrictions > 0) THEN
			SET statusCode=5;
		END IF;
	END IF; 

	-- CHECK re: Country Restrictions
	/*
  	IF(licenceCountryRestriction) THEN
		-- Check if there are any country/ip restrictions for this player 
		IF (SELECT !WagerRestrictionCheckCanWager(licenseTypeID, sessionID)) THEN 
			SET statusCode=8; 
		END IF;
	END IF;
	*/
  
	IF (statusCode != 0) THEN
        
        UPDATE gaming_lottery_dbg_tickets
		STRAIGHT_JOIN gaming_lottery_participations ON gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 2 /*requires get funds*/
		SET gaming_lottery_participations.lottery_wager_status_id = 7, gaming_lottery_participations.error_code=statusCode
		WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
        
		UPDATE gaming_lottery_coupons
		SET gaming_lottery_coupons.lottery_wager_status_id = 7, gaming_lottery_coupons.error_code=statusCode
		WHERE gaming_lottery_coupons.lottery_coupon_id = couponID;
    
		LEAVE root;
	END IF;
  	
    SET @currentBetAmount=0;
	SET @betCash=betAmount;
	SET @currentBetCash = 0;
    
    SET @currentLoyaltyPoints = 0;
    SET @totalLoyaltyPoints =0;
	
	
	INSERT INTO gaming_game_plays_lottery_entries (game_play_id, lottery_draw_id, lottery_participation_id, amount_total, amount_cash, loyalty_points)
	SELECT gamePlayID, lottery_draw_id, lottery_participation_id,participation_cost, tempBetCash, loyaltyPointsReal
	FROM 
	(
		SELECT gaming_lottery_participations.lottery_draw_id, gaming_lottery_participations.lottery_participation_id,participation_cost,
			@currentBetAmount:= participation_cost AS currentBet,
			@currentBetCash := IF(@currentBetAmount > @betCash, @betCash, @currentBetAmount) AS tempBetCash,
			@currentBetAmount := @currentBetAmount - @currentBetCash,
			@betCash := @betCash - @currentBetCash,
			@currentLoyaltyPoints := @currentBetCash * IFNULL(glpld.loyalty_points/glpld.amount,IFNULL(glpg.loyalty_points/glpg.amount,IFNULL(glpgc.loyalty_points/glpgc.amount,0)))   AS loyaltyPointsReal,
			@totalLoyaltyPoints := @totalLoyaltyPoints + @currentLoyaltyPoints
		FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
		STRAIGHT_JOIN gaming_lottery_participations ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 2
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
	END IF;

	-- update player balance
	UPDATE gaming_client_stats AS gcs
	LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
	SET 
	gcs.total_cash_played_retail = IF(@channelType = 'retail', gcs.total_cash_played_retail + betAmount, gcs.total_cash_played_retail),
	gcs.total_cash_played_self_service = IF(@channelType = 'self-service' ,gcs.total_cash_played_self_service + betAmount, gcs.total_cash_played_self_service),
    gcs.total_cash_played = gcs.total_cash_played_retail + gcs.total_cash_played_self_service,
 	gcs.total_real_played = IF(@channelType NOT IN ('retail','self-service'),gcs.total_real_played+betAmount, gcs.total_wallet_real_played + gcs.total_cash_played),
	
	gcs.total_real_played_base=gcs.total_real_played_base +IFNULL((betAmount/exchangeRate),0),
	gcs.total_loyalty_points_given = gcs.total_loyalty_points_given + IFNULL(@totalLoyaltyPoints,0) , 
	gcs.current_loyalty_points = gcs.current_loyalty_points + IFNULL(@totalLoyaltyPoints,0) ,
    gcs.loyalty_points_running_total = IF(currentVipType = 'LoyaltyPointsPeriod', gcs.loyalty_points_running_total + IFNULL(@totalLoyaltyPoints,0), gcs.loyalty_points_running_total),
	last_played_date=NOW(), 
	
	-- gaming_client_sessions
 	gcss.total_bet=gcss.total_bet+betAmount,
 	gcss.total_bet_base=gcss.total_bet_base+(betAmount/exchangeRate),
	gcss.bets=gcss.bets+1, 
  
    gcss.total_bet_cash=gcss.total_bet_cash+betAmount, 
	gcss.loyalty_points=gcss.loyalty_points+ IFNULL(@totalLoyaltyPoints,0), gcss.loyalty_points_bonus=gcss.loyalty_points_bonus+ IFNULL(@totalLoyaltyPointsBonus,0),

	-- gaming_client_wager_types
	gcws.num_bets=gcws.num_bets+1, 
	gcws.total_cash_wagered=gcws.total_cash_wagered+betAmount,
	gcws.first_wagered_date=IFNULL(gcws.first_wagered_date, NOW()), 
	gcws.last_wagered_date=NOW(),
    gcws.loyalty_points=gcws.loyalty_points+ IFNULL(@totalLoyaltyPoints,0) 
	
  WHERE gcs.client_stat_id = clientStatID;
	
	INSERT INTO gaming_game_rounds
		(bet_total, bet_total_base, exchange_rate, bet_cash,  num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, round_ref, license_type_id, is_round_finished, loyalty_points, sb_bet_id) 
    SELECT betAmount, ROUND(betAmount/exchangeRate,5), exchangeRate, betAmount, 1, 1, NOW(), gameManufacturerID, clientID, clientStatID, 1, gaming_game_round_types.game_round_type_id, currencyID, couponID, licenseTypeID, 1, @totalLoyaltyPoints, couponID
    FROM gaming_game_round_types
    WHERE gaming_game_round_types.name=CAST(CASE licenseTypeID WHEN 6 THEN 'Lotto' WHEN 7 THEN 'SportsPool' END AS CHAR(80));
    
    SET gameRoundID=LAST_INSERT_ID();
    
	INSERT INTO gaming_game_rounds_lottery (game_round_id, is_parent_round) VALUES (gameRoundID,1);
     
	INSERT INTO gaming_game_plays 
		(amount_total, game_round_id, amount_total_base, exchange_rate, amount_cash, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, amount_other, bonus_lost, payment_method_id, TIMESTAMP,  game_manufacturer_id, client_id, client_stat_id, session_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, pending_bet_real, pending_bet_bonus, currency_id, sign_mult, license_type_id,loyalty_points, loyalty_points_bonus,loyalty_points_after, loyalty_points_after_bonus, sb_bet_id, game_play_message_type_id, is_win_placed, platform_type_id) 
	SELECT betAmount, gameRoundID, betAmount/exchangeRate, exchangeRate, betAmount, 0,0,0,0,0,0,paymentMethodID,NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gaming_payment_transaction_type.payment_transaction_type_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, pending_bets_real, pending_bets_bonus, currencyID, -1, licenseTypeID,@totalLoyaltyPoints,0,gaming_client_stats.current_loyalty_points,IFNULL(gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus,0), couponID, gaming_game_play_message_types.game_play_message_type_id, 0, @platformTypeID
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
	JOIN gaming_game_play_message_types ON gaming_game_play_message_types.`name` = CAST(CASE licenseTypeID WHEN 6 THEN 'LotteryCashBet' WHEN 7 THEN 'SportsPoolCashBet' END AS CHAR(80))
    WHERE gaming_payment_transaction_type.name = 'Bet';
    
    SET gamePlayID = LAST_INSERT_ID();
        
        
        
  IF (ruleEngineEnabled) THEN
      IF NOT EXISTS (SELECT event_table_id FROM gaming_event_rows WHERE event_table_id=1 AND elem_id=gamePlayID) THEN
		    INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, gamePlayID
          ON DUPLICATE KEY UPDATE elem_id=VALUES(elem_id);
      END IF;
  END IF;
        

        
	UPDATE gaming_lottery_transactions SET game_play_id = gamePlayID WHERE lottery_coupon_id = couponID and is_latest = 1;

	IF(vipLevelID IS NOT NULL) THEN
		CALL PlayerUpdateVIPLevel(clientStatID,0);
	END IF;
    
    INSERT INTO gaming_game_plays_lottery(game_play_id, lottery_coupon_id) VALUES (gamePlayID, couponID);
    
    UPDATE gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    JOIN gaming_lottery_participations ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
    JOIN gaming_game_plays_lottery_entries ON gaming_game_plays_lottery_entries.lottery_participation_id  = gaming_lottery_participations.lottery_participation_id
    SET gaming_game_plays_lottery_entries.game_play_id = gamePlayID, gaming_lottery_participations.lottery_wager_status_id = 9
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
    
	UPDATE gaming_lottery_coupons
    SET gaming_lottery_coupons.lottery_wager_status_id = 9, wager_game_play_id = gamePlayID, platform_type_id = @platformTypeID, channel_type_id = @channelTypeID,
    paid_with = IFNULL(paid_with, (SELECT default_paid_with FROM gaming_channel_types WHERE channel_type_id = @channelTypeID))
    WHERE lottery_coupon_id = couponID;
    
	INSERT INTO gaming_game_rounds 
		(bet_total, bet_total_base, exchange_rate, bet_cash, num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, round_ref, license_type_id,is_round_finished,  loyalty_points,  sb_bet_id, sb_extra_id,game_id,operator_game_id) 
    SELECT amount_total, ROUND(amount_total/exchangeRate,5), exchangeRate, amount_cash, 1, 1, NOW(), gameManufacturerID, clientID, clientStatID, 0, gaming_game_round_types.game_round_type_id, currencyID, couponID,licenseTypeID ,0,  @totalLoyaltyPoints, couponID, lottery_participation_id, gaming_operator_games.game_id, gaming_operator_games.operator_game_id
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

	
-- WAGERING FUNCTIONALITY FOR CASH BET 

IF (topBonusApplicable) THEN
		

        SET @currentBetCash = 0;
         
		SET @bonusInstanceID = 0;
        SET @bonusChanged = 0;
        SET @currentParticipation = 0;
        SET @particpationUpdate = 0;
        SET @wagerNonWeighted = 0;
        SET @wagerTotal = 0;
        
		SET @playLotteryWagerRemain=0;

		COMMIT;

        INSERT INTO gaming_game_plays_lottery_entry_bonuses(game_play_lottery_entry_id,bonus_instance_id,bet_bonus_win_locked,bet_real,bet_bonus,bet_cash,wager_requirement_non_weighted,
			wager_requirement_contribution_before_real_only,wager_requirement_contribution,wager_requirement_contribution_cancelled)
		SELECT game_play_lottery_entry_id,bonus_instance_id,0,0,0,wagerNonWeighted,wagerNonWeighted,wager_requirement_contribution_pre,wager_requirement_contribution,0
        FROM (
			SELECT tmpTable.game_play_lottery_entry_id,bonus_instance_id, playLotteryWagerRemain,
				@wagerNonWeighted:= playLotteryWagerRemain AS wagerNonWeighted,
                @wagerWeighted :=
						ROUND(
							LEAST(
									IFNULL(wgr_restrictions.max_wager_contibution_before_weight,100000000*100),
									@wagerNonWeighted
								  )*IFNULL(gaming_bonus_rules_wgr_req_weights.bonus_wgr_req_weigth, 0)*CASE licenseTypeID WHEN 6 THEN IFNULL(lottery_weight_mod, 1) WHEN 7 THEN IFNULL(sportspool_weight_mod, 1) ELSE 1 END,

						5),
				IF(@wagerWeighted>=bonusWagerRequirementRemain,bonusWagerRequirementRemain,@wagerWeighted) AS wager_requirement_contribution_pre,
                
				IF(@wagerWeighted>=bonusWagerRequirementRemain,bonusWagerRequirementRemain,@wagerWeighted) AS wager_requirement_contribution
                
			FROM (
				SELECT game_play_lottery_entry_id , bonus_instance_id, amount_cash AS playLotteryWagerRemain
				FROM (
					SELECT game_play_lottery_entry_id,gaming_bonus_instances.bonus_instance_id, amount_cash
					FROM gaming_game_plays_lottery_entries FORCE INDEX (game_play_id)
					STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = topBonusInstanceID
					WHERE gaming_game_plays_lottery_entries.game_play_id = gamePlayID 
					ORDER BY gaming_game_plays_lottery_entries.lottery_participation_id
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
	
    -- added amount_cash
		INSERT INTO gaming_game_plays_bonus_instances (game_play_id, bonus_instance_id, bonus_rule_id, client_stat_id, TIMESTAMP, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked, bet_cash,
			wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_wager_requirement_remain_after,bonus_order)
		SELECT gamePlayID, bonus_instance_id, bonus_rule_id, clientStatID, NOW(), exchangeRate,0, 0, 0, @wagerReqNonWeighted,
			 @wagerReqNonWeighted, @wagerReqWeightedBeforeReal,@wagerReqWeighted,@nowWagerReqMet:=IF (bonus_wager_requirement_remain-@wagerReqWeighted<=0,1,0) AS now_wager_requirement_met,
			IF (@nowWagerReqMet=0 AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wagerReqWeighted)>=((transfer_every_x_last+transfer_every_x)*bonus_amount_given), 1, 0) AS now_release_bonus,
			GREATEST(bonus_wager_requirement_remain-@wagerReqWeighted,0) AS bonus_wager_requirement_remain_after, 1 AS bonusOrder
		FROM gaming_bonus_instances 
        WHERE bonus_instance_id = topBonusInstanceID;
        
		UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
		STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
		STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
		SET bonus_wager_requirement_remain=bonus_wager_requirement_remain-wager_requirement_contribution
		WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;  
        
	END IF;
	 
	CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID, 0);
	CALL PlayReturnBonusInfoOnBet(gamePlayID);
	
    CALL NotificationEventCreate(CASE licenseTypeID WHEN 6 THEN 552	WHEN 7 THEN 563 END, couponID, clientStatID, 0);

END root$$

DELIMITER ;

