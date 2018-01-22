DROP procedure IF EXISTS `PlaceSBBetCancelPartial`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceSBBetCancelPartial`(clientStatID BIGINT, gamePlayID BIGINT,gameParentRoundID BIGINT, sbBetID BIGINT, gameBetRoundIDToIndentifyBetRef BIGINT, betToCancelAmount DECIMAL(18, 5), liveBetType TINYINT(4), deviceType TINYINT(4), selectionID BIGINT, refundMultiples TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN

	DECLARE cancelAmount, cancelTotalBase, cancelReal, cancelBonus, cancelBonusWinLocked, cancelRemain, cancelOther, winReal, winBonus, winBonusWinLocked, winFreeBet, winFreeBetWinLocked DECIMAL(18, 5) DEFAULT 0;
	DECLARE betAmount, betTotalBase, betReal, betBonus, betBonusWinLocked, cancelRatio,adjustAmount,numBonuses,
			taxBet, taxWin, roundBetTotal, roundWinTotal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal,  amountTaxPlayer, amountTaxOperator, taxModificationOperator, taxModificationPlayer, roundWinTotalFull, roundBetTotalFull DECIMAL(18, 5) DEFAULT 0;
	DECLARE exchangeRate, playRemainingValue, totalLoyaltyPoints, totalLoyaltyPointsBonus DECIMAL(18, 5) DEFAULT 0;
	DECLARE gamePlayIDCheck, gameID, gameManufacturerID, clientStatIDCheck, clientID, currencyID, sbExtraID, gamePlayMessageTypeID,gamePlayBetCounterID, countryID, countryTaxID, topBonusInstanceID, gamePlayWinCounterID, vipLevelID, sessionID  BIGINT DEFAULT -1;
	DECLARE dateTimeWin DATETIME DEFAULT NULL;
	DECLARE bonusEnabledFlag, playLimitEnabled, disableBonusMoney, isAlreadyProcessed, applyNetDeduction, winTaxPaidByOperator, taxEnabled, sportsTaxCountryEnabled, IsFreeBonus,isFreeBonusPhase TINYINT(1) DEFAULT 0;
	DECLARE numTransactions INT DEFAULT 0;
	DECLARE roundType VARCHAR(20) DEFAULT NULL;
	DECLARE clientWagerTypeID INT DEFAULT -1;
	DECLARE licenseTypeID,bonusReqContributeRealOnly TINYINT(4) DEFAULT 3; -- SportsBook
	DECLARE numOfBets, countMult INT DEFAULT -1;
    DECLARE retType VARCHAR(80);
	DECLARE bonusRetLostTotal, betFromReal DECIMAL(18,5);
    DECLARE bonusCount INT; 
	DECLARE currentVipType VARCHAR(100) DEFAULT '';
    -- DECLARE sign_mult INT DEFAULT 1;
	SET gamePlayIDReturned=NULL;
	SET clientWagerTypeID=3;



	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, IFNULL(gs4.value_bool,0) AS vb4
	INTO playLimitEnabled, bonusEnabledFlag,bonusReqContributeRealOnly, taxEnabled
	FROM gaming_settings gs1 
	JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
    JOIN gaming_settings gs3 ON gs3.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY'
    LEFT JOIN gaming_settings gs4 ON (gs4.name='TAX_ON_GAMEPLAY_ENABLED')
	WHERE gs1.name='PLAY_LIMIT_ENABLED';

	SELECT client_stat_id, client_id, gaming_client_stats.currency_id, bet_from_real INTO clientStatIDCheck, clientID, currencyID, betFromReal  FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;


	SELECT gaming_operator_currency.exchange_rate, gaming_clients.vip_level_id, gaming_vip_levels.set_type, sessions_main.session_id
	INTO exchangeRate, vipLevelID, currentVipType, sessionID
	FROM gaming_clients
	STRAIGHT_JOIN sessions_main FORCE INDEX (client_latest_session) ON sessions_main.extra_id=gaming_clients.client_id AND sessions_main.is_latest
	JOIN gaming_operator_currency ON gaming_operator_currency.currency_id = currencyID
	LEFT JOIN gaming_vip_levels ON gaming_vip_levels.vip_level_id = gaming_clients.vip_level_id 
	WHERE gaming_clients.client_id=clientID;

	SELECT loyalty_points, loyalty_points_bonus
	INTO totalLoyaltyPoints, totalLoyaltyPointsBonus
	FROM gaming_game_plays
	WHERE game_play_id = gamePlayID;

	SET adjustAmount=betToCancelAmount;
	SET @bonusLost=0;
	SET @bonusWinLockedLost=0;

	
	IF (bonusEnabledFlag) THEN 

		SET @numPlayBonusInstances=0;
		SELECT COUNT(*) INTO @numPlayBonusInstances
		FROM gaming_game_plays_bonus_instances 
		WHERE game_play_id=gamePlayID;

        SELECT gaming_game_plays_bonus_instances.bonus_instance_id, gaming_bonus_types_bet_returns.name, is_free_bonus, is_freebet_phase
          INTO topBonusInstanceID, retType,IsFreeBonus,isFreeBonusPhase
        FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
          STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_game_plays_bonus_instances.bonus_instance_id
          STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
          STRAIGHT_JOIN gaming_bonus_types_bet_returns ON gaming_bonus_types_bet_returns.bonus_type_bet_return_id = gaming_bonus_rules.bonus_type_bet_return_id
            WHERE gaming_game_plays_bonus_instances.game_play_id = gamePlayID AND gaming_game_plays_bonus_instances.bonus_order = 1 LIMIT 1;

        SELECT 
           SUM(bet_bonus), COUNT(*) INTO 
           bonusRetLostTotal, bonusCount
        FROM 
           gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
          STRAIGHT_JOIN gaming_bonus_instances ON gaming_game_plays_bonus_instances.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
         WHERE gaming_game_plays_bonus_instances.game_play_id = gamePlayID;

		IF ( topBonusInstanceID != -1 ) THEN
			SET @isBonusSecured = 0;
			SET @winBonusTemp = 0.0;
			SET @winBonusCurrent = 0.0; 
			SET @winRealBonusCurrent = 0.0;
			SET @ReduceFromReal = 0.0;
			SET @winRealBonusCurrent=0.0;
			SET @winRealBonusWLCurrent=0.0;  
		    SET @winBonusLostCurrent=0.0;
		    SET @winBonusWinLockedLostCurrent=0.0;
		    SET @winReal=0.0;
		    SET @winBonus=0.0;

			INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameParentRoundID); #review
			SET gamePlayWinCounterID=LAST_INSERT_ID();

			SET @updateBonusInstancesWins = 1;
			SET @winAmountTemp = betToCancelAmount;
			SET @bonusOrder = bonusCount + 1;
			SET @topBonusNo = 1; 


          SELECT 
            play_bonus_instances.bonus_order INTO @topBonusNo
          FROM gaming_game_plays_bonus_instances AS play_bonus_instances FORCE INDEX (game_play_id)
  					STRAIGHT_JOIN gaming_bonus_instances ON play_bonus_instances.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
  					STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
  					STRAIGHT_JOIN gaming_bonus_types_bet_returns AS bet_returns_type ON gaming_bonus_rules.bonus_type_bet_return_id = bet_returns_type.bonus_type_bet_return_id
  					STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id = transfer_type.bonus_type_transfer_id
			    WHERE  play_bonus_instances.game_play_id = gamePlayID AND is_lost = 0
  					GROUP BY gaming_bonus_instances.bonus_instance_id
  					ORDER BY is_freebet_phase ASC, gaming_bonus_instances.given_date ASC, gaming_bonus_instances.bonus_instance_id ASC 
          LIMIT 1;   


			INSERT INTO gaming_game_plays_bonus_instances_wins (
				game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, 
				bonus_rule_id, `timestamp`, exchange_rate, win_real, win_bonus, win_bonus_win_locked, 
				lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution, bonus_order
			)
    			SELECT 
            gamePlayWinCounterID, game_play_bonus_instance_id, bonus_instance_id, 
            bonus_rule_id, NOW(), exchangeRate, win_real, win_bonus, win_bonus_win_locked,
            lost_win_bonus, lost_win_bonus_win_locked, clientStatID, NULL, 0, bonusOrder
    			FROM
    			(
    							SELECT
              /* Index of the bonus */
    					@bonusOrder := @bonusOrder - 1 AS bonusOrder,

    					game_play_bonus_instance_id, 
              bonus_instance_id, 
              bonus_rule_id,
              /* Bonus secured flag */
    					@isBonusSecured := IF( is_secured, 1, @isBonusSecured ),	
              /* Temp holder for bonus win */
    					@winBonusTemp := ROUND(
    								IF(@winAmountTemp > 0 AND gg.is_lost = 0,
    										IF(@winAmountTemp   <  IF(  is_freebet_phase, ( bonus_amount_given - bonus_amount_remaining ),   GREATEST(0, ( bonus_amount_given - bonus_transfered_total - bonus_amount_remaining ) )   ),
    										  @winAmountTemp,
    										  IF( is_freebet_phase , bonus_amount_given - bonus_amount_remaining, GREATEST(0, ( bonus_amount_given - bonus_transfered_total - bonus_amount_remaining ) ) )
    								    )
    							  ,0),
    					0),              
              /* Bonus win for this bonus */
    					@winBonusCurrent :=  @winBonusTemp AS win_bonus,
              /* If current bonus was secured, set win real from bonus  */
    					@winRealBonusCurrent := IF (is_secured = 1  AND IsFreeBonus = 0 AND is_freebet_phase = 0, -- amount to win in real
										@winBonusTemp,
										@winRealBonusCurrent
    					),
              /* Loop current value winAmount  */
    					@winAmountTemp := IF( ( @winAmountTemp > 0 AND is_lost = 0 ) ,
    							  IF( ( @winAmountTemp < @winBonusCurrent ),
    									 0,
    									 @winAmountTemp - @winBonusCurrent
    							  )
    							  ,@winAmountTemp
    				   ) ,
              /* Top-up real */
    					@ReduceFromReal :=  IF( ( bonus_order = @topBonusNo AND @winAmountTemp > 0 ),
    							IF ( ( is_freebet_phase = 1 ),
    								@winAmountTemp,                        
    								IF( @winAmountTemp <  IF( is_lost = 1, bet_from_real, betFromReal ),
    									@winAmountTemp,
    									 IF( is_lost = 1, bet_from_real, betFromReal )
    								)
    							),
    							0
    					),
              /* Loop current value, deduct reduce from real */
    					@winAmountTemp := IF( bonus_order = @topBonusNo AND @winAmountTemp > 0,
    						@winAmountTemp - @ReduceFromReal,
    						@winAmountTemp
    				  ),
    				  /* Winnings locked ?? */
    					@winRealBonusWLCurrent := IF( ( bonus_order = @topBonusNo AND is_lost = 0 ),
    									  @winAmountTemp,
    										0.0
						) AS win_bonus_win_locked,
              /* ?? */
    					@winAmountTemp := IF(bonus_order = @topBonusNo AND is_lost = 0,
    								0,
    								@winAmountTemp
    				  ),
              /* Current lost bonus */
    					@winBonusLostCurrent := ROUND(
								  IF( ( is_secured = 0 AND is_lost = 1 ),
    										@winBonusTemp,
    										0
    									), 
    				  0) AS lost_win_bonus,
              /* Bonus lost win locked amount */
    					@winBonusWinLockedLostCurrent := ROUND(
							    IF( ( is_secured = 0 AND is_lost = 1 ), 
										  @winRealBonusWLCurrent,  
										  0
									),
    					 0) AS lost_win_bonus_win_locked,
               /* Transfer to real current win bonus ?? */
    					@winRealBonusCurrent := IF(( is_secured = 1 ) OR ( IsFreeBonus = 1 AND bonus_order = @topBonusNo ), 
    					(CASE gg.`name`
                /* Types of bonus transfer logic ?? */
    						WHEN 'All' THEN @winRealBonusWLCurrent + @winRealBonusCurrent - @winBonusLostCurrent - @winBonusWinLockedLostCurrent
    						WHEN 'NonReedemableBonus' THEN @winRealBonusWLCurrent - @winBonusWinLockedLostCurrent
    						WHEN 'Bonus' THEN @winRealBonusCurrent- @winBonusLostCurrent
    						WHEN 'BonusWinLocked' THEN @winRealBonusWLCurrent- @winBonusWinLockedLostCurrent
    						WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(bonus_amount_given-bonus_transfered_total, @winRealBonusWLCurrent + @winRealBonusCurrent- @winBonusLostCurrent - @winBonusWinLockedLostCurrent))
    						WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((bonus_amount_given*transfer_upto_percentage)-bonus_transfered_total, @winRealBonusWLCurrent + @winRealBonusCurrent- @winBonusLostCurrent - @winBonusWinLockedLostCurrent))
    						WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(bonus_amount_given-bonus_transfered_total, @winRealBonusWLCurrent + @winRealBonusCurrent- @winBonusLostCurrent - @winBonusWinLockedLostCurrent))
    						WHEN 'ReleaseAllBonus' THEN @winBonusAllTemp
    						ELSE 0
    					END), 0) AS win_real,
    
    					@winBonus := @winBonus + @winBonusCurrent,
    					@winBonusWinLocked := @winBonusWinLocked + @winRealBonusWLCurrent,
    					@winBonusLost := @winBonusLost + @winBonusLostCurrent,
    					@winBonusWinLockedLost := @winBonusWinLockedLost + @winBonusWinLockedLostCurrent,
    					@winReal := @winReal + @ReduceFromReal,          
    
    					bonus_amount_remaining, 
              current_win_locked_amount
    				FROM (
    					SELECT 
    						gaming_bonus_instances.bonus_amount_remaining,
    						gaming_bonus_instances.current_win_locked_amount,
    						SUM(bet_bonus_win_locked) AS bet_bonus_win_locked,
    						gaming_bonus_instances.is_secured,
    						gaming_bonus_instances.bonus_amount_given,
    						gaming_bonus_instances.bonus_transfered_total,
    						SUM(bet_bonus) AS bet_bonus,
    						gaming_bonus_instances.is_lost,
    						bonus_order,
    						gaming_bonus_rules.transfer_upto_percentage,
    						transfer_type.`name`,
    						game_play_bonus_instance_id,
    						gaming_bonus_instances.bonus_instance_id,
    						gaming_bonus_instances.bonus_rule_id,
    						gaming_bonus_instances.bet_from_real,
    						gaming_bonus_rules.is_free_bonus,
    						gaming_bonus_instances.is_freebet_phase,
    						play_bonus_instances.bet_real
    					FROM gaming_game_plays_bonus_instances AS play_bonus_instances FORCE INDEX (game_play_id)
    					STRAIGHT_JOIN gaming_bonus_instances ON play_bonus_instances.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
    					STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
    					STRAIGHT_JOIN gaming_bonus_types_bet_returns AS bet_returns_type ON gaming_bonus_rules.bonus_type_bet_return_id = bet_returns_type.bonus_type_bet_return_id
    					STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id = transfer_type.bonus_type_transfer_id
    					WHERE  play_bonus_instances.game_play_id = gamePlayID /* changed to bet gameplay ID */
    					GROUP BY gaming_bonus_instances.bonus_instance_id
    					ORDER BY is_freebet_phase DESC, gaming_bonus_instances.given_date DESC, gaming_bonus_instances.bonus_instance_id DESC
    				) AS gg
    			) AS XX ON DUPLICATE KEY UPDATE 
              bonus_instance_id=VALUES(bonus_instance_id), win_real=VALUES(win_real), 
              win_bonus=VALUES(win_bonus), win_bonus_win_locked=VALUES(win_bonus_win_locked), 
              lost_win_bonus=VALUES(lost_win_bonus), lost_win_bonus_win_locked=VALUES(lost_win_bonus_win_locked), 
              client_stat_id=VALUES(client_stat_id);   

			SET @updatedBonusAmountRemaining = 0.0;
			SET winBonusWinLocked=IFNULL(@winBonusWinLocked,0)-IFNULL(@winBonusWinLockedLost,0);

			UPDATE gaming_game_plays_bonus_instances_wins AS ggpbiw FORCE INDEX (PRIMARY)
				STRAIGHT_JOIN gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (PRIMARY) ON ggpbiw.game_play_win_counter_id=gamePlayWinCounterID AND 
				ggpbi.game_play_bonus_instance_id=ggpbiw.game_play_bonus_instance_id 
    			STRAIGHT_JOIN gaming_bonus_instances AS gbi ON ggpbi.bonus_instance_id=gbi.bonus_instance_id
    			SET
    				ggpbi.win_bonus=IFNULL(ggpbi.win_bonus,0) - ggpbiw.win_bonus , 
    				ggpbi.win_bonus_win_locked=IFNULL(ggpbi.win_bonus_win_locked,0) - ggpbiw.win_bonus_win_locked, 
    				ggpbi.win_real=  IFNULL(ggpbi.win_real,0) - ggpbiw.win_real,
    				ggpbi.lost_win_bonus=IFNULL(ggpbi.lost_win_bonus,0) + ggpbiw.lost_win_bonus,
    				ggpbi.lost_win_bonus_win_locked=IFNULL(ggpbi.lost_win_bonus_win_locked,0) + ggpbiw.lost_win_bonus_win_locked,
           /**
            * top-up back amount remaining for this bonus instance, so that this is taken into account with subsequent bets
            */
					gbi.bonus_amount_remaining= @updatedBonusAmountRemaining := GREATEST(0, gbi.bonus_amount_remaining + IF( ( gbi.bonus_amount_remaining + IFNULL(ggpbiw.win_bonus,0) > gbi.bonus_amount_given),
							gbi.bonus_amount_given - gbi.bonus_amount_remaining, 
						IFNULL(ggpbiw.win_bonus,0)
					  )
					),
           /**
            * relative current win locked amount
            * TODO : Duplicate bonus if you have multiple bonuses ??????????????????????
            */
					gbi.current_win_locked_amount = gbi.current_win_locked_amount + IFNULL(ggpbiw.win_bonus_win_locked,0),

					ggpbi.now_used_all=IF(ROUND( @updatedBonusAmountRemaining + gbi.current_win_locked_amount + IFNULL(ggpbiw.win_bonus,0) + IFNULL(ggpbiw.win_bonus_win_locked,0), 5 ) = 0 , 1, 0);
					SET cancelReal=IFNULL(@winReal,0);   
					SET cancelBonus=IFNULL(@winBonus,0)-IFNULL(@winBonusLost,0);  
					SET cancelBonusWinLocked = winBonusWinLocked;

					
		ELSE 

			SET cancelReal = adjustAmount ;
			SET cancelBonus = 0;
			SET cancelBonusWinLocked = 0;

		END IF; 

	ELSE
		SET cancelReal = adjustAmount;
		SET cancelBonus = 0;
		SET cancelBonusWinLocked = 0;

	END IF;


 -- Add Tax Adjustment Calculations
   -- Retrieve Tax Flags
#TAXENABLED

   IF (taxEnabled) THEN
	SELECT bet_total, win_total, amount_tax_operator, amount_tax_player, bet_real, win_real
	INTO roundBetTotal, roundWinTotal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal
	FROM gaming_game_rounds
	WHERE game_round_id=gameBetRoundIDToIndentifyBetRef;

	SELECT clients_locations.country_id, gaming_countries.sports_tax INTO countryID, sportsTaxCountryEnabled  
	FROM clients_locations
	JOIN gaming_countries ON gaming_countries.country_id = clients_locations.country_id
	WHERE clients_locations.client_id = clientID AND clients_locations.is_primary = 1;
	  
	SET amountTaxPlayer = 0.0;
	SET amountTaxOperator = 0.0;
	SET taxModificationOperator = 0.0;
	SET taxModificationPlayer = 0.0;

	-- Bet cancel will cancel out all tax calculations which have previously occured.
	IF (countryID > 0 AND sportsTaxCountryEnabled = 1) THEN
	  SET taxModificationOperator = taxAlreadyChargedOperator;
	  SET taxModificationPlayer = taxAlreadyChargedPlayer;
	END IF;
END IF; -- taxEnabled

 	UPDATE gaming_client_stats AS gcs
    JOIN gaming_client_wager_types ON gaming_client_wager_types.client_wager_type_id = clientWagerTypeID
	LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=gaming_client_wager_types.client_wager_type_id
	SET gcs.total_real_played=gcs.total_real_played-cancelReal, 
		gcs.current_real_balance=gcs.current_real_balance+cancelReal - taxModificationPlayer,
		gcs.total_bonus_played=gcs.total_bonus_played+cancelBonus, 
		gcs.current_bonus_balance=gcs.current_bonus_balance+cancelBonus, 
		gcs.total_bonus_win_locked_played=gcs.total_bonus_win_locked_played-cancelBonusWinLocked, 
		gcs.current_bonus_win_locked_balance=gcs.current_bonus_win_locked_balance+cancelBonusWinLocked,
		gcs.total_real_played_base=gcs.total_real_played_base-(cancelReal/exchangeRate), 
		gcs.total_bonus_played_base=gcs.total_bonus_played_base-((cancelBonus+cancelBonusWinLocked)/exchangeRate), 
		gcs.total_tax_paid = gcs.total_tax_paid - taxModificationPlayer,
		-- loyalty points
		gcs.total_loyalty_points_given = gcs.total_loyalty_points_given - IFNULL(totalLoyaltyPoints,0),
		gcs.current_loyalty_points = gcs.current_loyalty_points - IFNULL(totalLoyaltyPoints,0),
		gcs.total_loyalty_points_given_bonus = gcs.total_loyalty_points_given_bonus - IFNULL(totalLoyaltyPointsBonus,0),
		gcs.loyalty_points_running_total = IF(currentVipType = 'LoyaltyPointsPeriod', gcs.loyalty_points_running_total - IFNULL(totalLoyaltyPoints,0), gcs.loyalty_points_running_total),
		
		-- gaming_client_sessions
		gcss.bets = gcss.bets - 1,
		gcss.total_bet_real = gcss.total_bet_real - cancelReal,
		gcss.total_bet_bonus = gcss.total_bet_bonus - cancelBonus - cancelBonusWinLocked,
		gcss.loyalty_points = gcss.loyalty_points - IFNULL(totalLoyaltyPoints,0), 
		gcss.loyalty_points_bonus = gcss.loyalty_points_bonus - IFNULL(totalLoyaltyPointsBonus,0),
		
		-- gaming_client_wager_types
		gcws.num_bets = gcws.num_bets - 1,
		gcws.total_real_wagered = gcws.total_real_wagered - cancelReal,
		gcws.total_bonus_wagered = gcws.total_bonus_wagered - (cancelBonus + cancelBonusWinLocked),
		gcws.loyalty_points = gcws.loyalty_points - IFNULL(totalLoyaltyPoints,0),
		gcws.loyalty_points_bonus = gcws.loyalty_points_bonus - IFNULL(totalLoyaltyPointsBonus,0)
	WHERE gcs.client_stat_id=clientStatID;  

	  
	SET cancelAmount=betToCancelAmount;
	SET cancelTotalBase=ROUND(cancelAmount/exchangeRate,5);

	-- 3. update is_win_placed flag (set flags are already processed)
	UPDATE gaming_game_plays SET is_processed=1, is_win_placed=1 WHERE game_play_id=gamePlayID;

	-- 3. Insert into gaming_game_plays 
	SET sbExtraID = gameBetRoundIDToIndentifyBetRef;
	INSERT INTO gaming_game_plays
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, bonus_win_locked_lost, 
     jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, game_round_id, payment_transaction_type_id, is_win_placed, 
     is_processed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, 
     sb_extra_id, sb_bet_id, license_type_id, device_type, pending_bet_real, pending_bet_bonus, amount_tax_operator, amount_tax_player, 
     loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus) 
	SELECT cancelAmount, cancelTotalBase, exchangeRate, cancelReal, cancelBonus, cancelBonusWinLocked, cancelOther, @bonusLost, @bonusWinLockedLost, 
		0, NOW(), gameManufacturerID, clientID, clientStatID, gameParentRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 
        0, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, currencyID, numTransactions+1, game_play_message_type_id, sbExtraID, sbBetID, licenseTypeID, deviceType, pending_bets_real, pending_bets_bonus, taxModificationOperator*-1, taxModificationPlayer*-1,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_payment_transaction_type.name='BetCancelled' AND gaming_client_stats.client_stat_id=clientStatID
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.game_play_message_type_id=IF(gamePlayMessageTypeID=8,12,13);

	SET gamePlayIDReturned=LAST_INSERT_ID();
	
	INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units, game_round_id, sb_bet_entry_id, sign_mult)
	SELECT gamePlayIDReturned, payment_transaction_type_id, amount_total*-1, amount_total_base*-1, amount_real*-1, amount_real_base*-1, amount_bonus*-1, amount_bonus_base*-1, NOW(), exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, liveBetType, deviceType, units*cancelRatio, game_round_id, sb_bet_entry_id, -1
	FROM gaming_game_plays_sb
	WHERE game_play_id=gamePlayID AND game_round_id = gameBetRoundIDToIndentifyBetRef;
	

	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayIDReturned);
    
	IF (bonusEnabledFlag && @numPlayBonusInstances>0) THEN 

		-- 2. update gaming_bonus_instances in-oder to add bonus_amount_remaining, current_win_locked_amount, bonus_wager_requirement_remain
		-- check wether all the bonus has been used
		INSERT INTO gaming_game_plays_bonus_instances (game_play_id,game_play_id_bet, bonus_instance_id, bonus_rule_id, client_stat_id, timestamp, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,
		  wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_wager_requirement_remain_after)
		SELECT gamePlayIDReturned,gamePlayID, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, clientStatID, NOW(), exchangeRate,

		  gaming_bonus_instances.bet_real, gaming_bonus_instances.bet_bonus, gaming_bonus_instances.bet_bonus_win_locked,
		  
		  @wager_requirement_non_weighted:=IF(ROUND(gaming_bonus_instances.bet_total*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, gaming_bonus_instances.bet_total) AS wager_requirement_non_weighted, 
		  @wager_requirement_contribution:=IF(ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,100000000*100),gaming_bonus_instances.bet_total)*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,1000000*100),gaming_bonus_instances.bet_total)*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)) AS wager_requirement_contribution_pre,
		  @wager_requirement_contribution:=LEAST(IFNULL(wgr_restrictions.max_wager_contibution,100000000*100), IF(wager_req_real_only OR bonusReqContributeRealOnly, ROUND(GREATEST(@wager_requirement_contribution-((gaming_bonus_instances.bet_bonus+gaming_bonus_instances.bet_bonus_win_locked)*IFNULL(sb_bonus_rules.weight,0)*IFNULL(license_weight_mod, 1)),0), 5), @wager_requirement_contribution)) AS wager_requirement_contribution, -- need test: *IFNULL(sb_bonus_rules.weight,0)*IFNULL(license_weight_mod, 1)
		  
		  @nowWagerReqMet:=IF (bonus_wager_requirement_remain-@wager_requirement_contribution=0,1,0) AS now_wager_requirement_met,
		  
		  IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wager_requirement_contribution)>=
			((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,
		  bonus_wager_requirement_remain-@wager_requirement_contribution AS bonus_wager_requirement_remain_after
		FROM 
		(
		  SELECT bonus_transaction.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, cancelAmount as bet_total, cancelReal as bet_real, bonus_transaction.win_bonus as bet_bonus, bonus_transaction.win_bonus_win_locked as bet_bonus_win_locked, bonus_wager_requirement_remain, IF(licenseTypeID=1,gaming_bonus_rules.casino_weight_mod, IF(licenseTypeID=2,gaming_bonus_rules.poker_weight_mod,IF(licenseTypeID=3, sportsbook_weight_mod ,1))) AS license_weight_mod,
			bonus_amount_given, bonus_wager_requirement, gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus
		  FROM gaming_game_plays_bonus_instances_wins AS bonus_transaction
		  JOIN gaming_bonus_instances ON bonus_transaction.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
		  JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		  JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
		  WHERE bonus_transaction.game_play_win_counter_id=gamePlayWinCounterID -- AND gaming_bonus_instances.expiry_date > NOW() 
		) AS gaming_bonus_instances  
		JOIN gaming_sb_bets_bonus_rules AS sb_bonus_rules ON sb_bonus_rules.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=sb_bonus_rules.bonus_rule_id  
		LEFT JOIN gaming_sb_bets_bonuses ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_sb_bets_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
		LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_instances.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID;

		UPDATE gaming_bonus_instances 
		JOIN gaming_game_plays_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
		SET 
			#bonus_amount_remaining=bonus_amount_remaining-bet_bonus, 
			#current_win_locked_amount=current_win_locked_amount-bet_bonus_win_locked,
			bonus_wager_requirement_remain=bonus_wager_requirement_remain + wager_requirement_contribution,
			is_active = IF (is_used_all=1 AND NOW() < expiry_date AND is_lost =0 ,1 , is_active),
			is_used_all = IF (is_used_all=1 AND NOW() < expiry_date AND is_lost =0 ,0 , is_used_all)
		WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayIDReturned; 

	END IF;


  -- 2.4 Update Play Limits Current Value
  IF (playLimitEnabled) THEN 
    CALL PlayLimitsUpdate(clientStatID, 'sportsbook', cancelAmount * -1, 1); 
  END IF;

  -- 4. update tables
  -- update parent gaming_game_round
  UPDATE gaming_game_rounds AS ggr
  SET 
  ggr.bet_total=bet_total-cancelAmount, 
  bet_total_base=ROUND(bet_total_base-cancelTotalBase,5),
	bet_real=bet_real-cancelReal,
	bet_bonus=bet_bonus-cancelBonus,
	bet_bonus_win_locked=bet_bonus_win_locked-cancelBonusWinLocked, 
	win_bet_diffence_base=win_total_base-bet_total_base,
#    ggr.num_bets=GREATEST(0, ggr.num_bets-1), 
	ggr.num_transactions=ggr.num_transactions+1, 
	ggr.amount_tax_operator = 0.0,
	ggr.amount_tax_player = 0.0
  WHERE game_round_id=gameParentRoundID;

  UPDATE gaming_game_plays_sb AS ggps FORCE INDEX (game_play_id)
  STRAIGHT_JOIN gaming_game_rounds AS ggr ON ggr.game_round_id=ggps.game_round_id
  STRAIGHT_JOIN gaming_game_plays_sb AS bets ON bets.game_round_id=ggr.game_round_id AND bets.game_play_id=gamePlayID
  SET 
    -- original wager
    bets.confirmation_status=1
  WHERE ggps.game_play_id=gamePlayIDReturned;

  UPDATE gaming_client_wager_stats AS gcws 
  SET gcws.num_bets=gcws.num_bets-1, gcws.total_real_wagered=gcws.total_real_wagered-cancelReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered-(cancelBonus+cancelBonusWinLocked)
  WHERE gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID;  

  SET statusCode=0;

END root$$

DELIMITER ;

