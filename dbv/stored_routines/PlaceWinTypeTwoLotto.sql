DROP procedure IF EXISTS `PlaceWinTypeTwoLotto`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceWinTypeTwoLotto`(
  lotteryParticipationID BIGINT, sessionID BIGINT, manualCashOut INT, OUT statusCode INT)
root:BEGIN

	-- Calling PlayReturnDataWithoutGameForSbExtraID & PlayReturnBonusInfoOnWinForSbExtraID to return an array of game plays
	-- Added gaming_game_play_message_types
    -- Play Limit Passing Game
	-- Pending Winnings and POS
    -- Returning child round (linked to participation) instead of parent round
	-- Updated coupon status according to participations
	-- Set participation status according participation status code and not to winnings
    -- Extracted coupon status setting from participation statuses to separate function, added condition for temp block
	-- Added manual cachout for online tickets
    -- Optimized
    -- Fixed bug with inverted ggpbi and ggpbiw
	-- Committing to DBV
    -- Provisional winner support	
    -- partizipation_prize_no
  
	DECLARE clientStatID, clientID, currencyID, gamePlayID, gameRoundID, gameRoundIDForParticipation, topBonusInstanceID, gamePlayWinCounterID, couponID, gameID, gameManufacturerID, operatorGameID,
		platformTypeID, newGamePlayID, lotteryDrawID, lotteryParticipationPrizeID,lotteryEntryID, 
        gamePlayLotteryEntryIDWin, approvalLevelID, paymentMethodID, newBalanceAccountID, balanceManualTransactionID,
		pendingWinGamePlayID, countPendingWins, pendingHighTierWinningLevelID, dummyGamePlayID, countGamePlays BIGINT DEFAULT -1;
	
    DECLARE playLimitEnabled, bonusEnabledFlag, bonusReedemAll, ringFencedEnabled, ruleEngineEnabled, bonusesUsedAllWhenZero, addWagerContributionWithRealBet,
		IsFreeBonus,isFreeBonusPhase, playerHasActiveBonuses, notMoreRows, winNotification, lossNotification TINYINT(1) DEFAULT 0;
    DECLARE totalWinnings, betFromReal, bonusRetLostTotal, exchangeRate, winReal, winBonus, winBonusWinLocked, currentBonusAmount, 
		currentRealAmount, currentWinLockedAmount, winAmount, totalWinAmount, highTierWins, grossToAdd, netToAdd, totalRefundAmount DECIMAL(18,5);
    DECLARE retType, licenseType VARCHAR(80);
    DECLARE numTransactions, bonusCount, errorCode, classificationPayoutTypeID, participationStatusID, 
		pendingWinStatusID, participationWagerStatus, blockLevel INT; 
	DECLARE notificationEnabled, winClassificationEnabled, approvalRequired, moveToPendingWinnings, forcePendingWinnings, 
		isProvisionalWin, hasPendingWin, insertPendingWin, forceNoNotifications TINYINT DEFAULT 0;
	DECLARE allParticipations, openParticipations, winParticipations, paidParticipations, lostParticipations, 
		playingParticipations, newCouponStatus, currentCouponStatus INT(4);
  	DECLARE pendingWinningStatusID, gameProviderWinStatusID,gameProviderWinStatusFallbackID, pendingGameProviderWinStatusID, 
		provisionalWinClassificationID, licenseTypeID, clientWagerTypeID INT DEFAULT -1;
	DECLARE participationPrizeNumber INT DEFAULT 0;
	-- Variables for non-menetary wins
	DECLARE isGift, isCustom TINYINT DEFAULT 0;
	DECLARE giftId, redemptionPrizeCount, giftTypeId BIGINT(20);
    DECLARE giftDescription VARCHAR(255);
	DECLARE giftAmount DECIMAL(18,5);
	
	-- Variables for Cancel Bet Chile
  DECLARE refundAmount decimal(18,5);


    DECLARE prizeCursor CURSOR FOR
		SELECT lottery_participation_prize_id, net, gift_id, gift_description, refund
        FROM gaming_lottery_participation_prizes FORCE INDEX (lottery_participation_id)
        WHERE lottery_participation_id = lotteryParticipationID;
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET notMoreRows = TRUE;

	SELECT value_bool INTO notificationEnabled FROM gaming_settings WHERE `name`='NOTIFICATION_ENABLED';
	SELECT value_bool INTO winClassificationEnabled FROM gaming_settings WHERE `name`='ENABLE_WINS_CLASSIFICATION_MANAGEMENT';

	SET totalWinAmount = 0;
	SET totalRefundAmount = 0;

    SELECT error_code, lottery_wager_status_id, lottery_participation_status_id, block_level
    INTO errorCode, participationWagerStatus, participationStatusID, blockLevel
    FROM gaming_lottery_participations
    WHERE lottery_participation_id = lotteryParticipationID;

    SELECT gs1.value_bool as vb1
    INTO ruleEngineEnabled
    FROM gaming_settings gs1 
    WHERE gs1.name='RULE_ENGINE_ENABLED';
    
	IF (blockLevel = 2108) THEN
		SET statusCode = 2;
		LEAVE root;
	END IF;

    -- Moved to the beginning, this data will be needed now
    SELECT gaming_game_plays_lottery_entries.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.client_stat_id, gaming_game_plays_lottery.lottery_coupon_id, gaming_lottery_draws.game_id, 
		gaming_lottery_draws.game_manufacturer_id, gaming_operator_games.operator_game_id, num_transactions, gaming_game_plays.platform_type_id, gaming_lottery_draws.lottery_draw_id,gaming_game_plays_lottery_entries.game_play_lottery_entry_id, gaming_game_plays.session_id
    INTO gamePlayID, gameRoundID, clientStatID, couponID, gameID, gameManufacturerID, operatorGameID, numTransactions, platformTypeID,lotteryDrawID, lotteryEntryID, sessionID
    FROM gaming_game_plays_lottery_entries  FORCE INDEX (lottery_participation_id)
	STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (PRIMARY) ON gaming_lottery_participations.lottery_participation_id = gaming_game_plays_lottery_entries.lottery_participation_id AND gaming_lottery_participations.lottery_wager_status_id = participationWagerStatus
    STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery_entries.game_play_id
    STRAIGHT_JOIN gaming_game_plays_lottery FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery.game_play_id
    STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_game_plays_lottery_entries.lottery_draw_id
	STRAIGHT_JOIN gaming_operator_games ON gaming_operator_games.game_id = gaming_lottery_draws.game_id
	STRAIGHT_JOIN gaming_operators ON gaming_operators.operator_id = gaming_operator_games.operator_id AND gaming_operators.is_main_operator = 1
    STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (PRIMARY) ON gaming_game_rounds.game_round_id = gaming_game_plays.game_round_id
    WHERE gaming_game_plays_lottery_entries.lottery_participation_id = lotteryParticipationID; 

	-- Get the Player channel
  	CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, @platformTypeID, @platformType, @channelTypeID, @channelType);
	
    -- Get first game play ID (that one would be connected to the pending winning
  	SELECT 
		gaming_pending_winnings.game_play_id INTO pendingWinGamePlayID
	FROM gaming_game_plays_lottery_entries  FORCE INDEX (lottery_participation_id)
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (PRIMARY) ON gaming_lottery_participations.lottery_participation_id = gaming_game_plays_lottery_entries.lottery_participation_id AND gaming_lottery_participations.lottery_wager_status_id = participationWagerStatus
    LEFT OUTER JOIN gaming_pending_winnings ON gaming_game_plays_lottery_entries.game_play_id = gaming_pending_winnings.game_play_id     
    WHERE gaming_lottery_participations.lottery_participation_id = lotteryParticipationID AND gaming_pending_winnings.game_play_id IS NOT NULL LIMIT 0, 1;
    
	SELECT lottery_coupon_status_id, gaming_lottery_coupons.license_type_id, gaming_license_type.`name`, gaming_client_wager_types.client_wager_type_id,
	gaming_lottery_coupons.win_notification, gaming_lottery_coupons.loss_notification
	INTO currentCouponStatus, licenseTypeID, licenseType, clientWagerTypeID, winNotification, lossNotification
	FROM gaming_lottery_coupons 
	JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_lottery_coupons.license_type_id
	JOIN gaming_client_wager_types ON gaming_client_wager_types.license_type_id = gaming_license_type.license_type_id
	WHERE lottery_coupon_id=couponID;
   
	IF (licenseTypeID = 7) THEN -- ONLY for SportsPool
		-- Check if Participation has Refund (hence meaning cancel bet - Chile)
		SELECT IFNULL(refund ,0)
		INTO refundAmount
		FROM gaming_lottery_participation_prizes
		WHERE lottery_participation_id = lotteryParticipationID;

		IF (refundAmount > 0) THEN  
			UPDATE gaming_lottery_coupons
			SET gaming_lottery_coupons.lottery_wager_status_id = 8, 
				gaming_lottery_coupons.lottery_coupon_status_id = 2104,
				cancel_reason='Coupon Cancelled and Refunded due to extraordinory circumstances', cancel_date=NOW()
			WHERE gaming_lottery_coupons.lottery_coupon_id = couponID;

			CALL ReturnFundsTypeTwoLotto(couponID, gamePlayID, sessionID, @statusCode);
			SET statusCode=@statusCode;
			LEAVE root;
		END IF;
	END IF;
    
   
	  -- Get POS & provisional win classification ID
    SELECT high_tier_winning_level_id INTO provisionalWinClassificationID FROM gaming_high_tier_winning_levels      
	WHERE license_type_id = licenseTypeID AND system_name = 'PROVISIONAL';

    -- Check if any pending wins exist
    SELECT 
    	COUNT(gaming_pending_winnings.game_play_id) INTO countPendingWins
    FROM gaming_pending_winnings WHERE gaming_pending_winnings.game_play_id = pendingWinGamePlayID; 
    
    SET hasPendingWin = IF (countPendingWins!=0, 1, 0);
   
    IF (hasPendingWin) THEN
    	-- If yes, get the pending winning status
    	SELECT 
        gpv.pending_winning_status_id, 
        gpv.high_tier_winning_level_id,
        ghtwl.game_provider_win_status_id
      INTO  
        pendingWinningStatusID,
        pendingHighTierWinningLevelID,
        pendingGameProviderWinStatusID
      FROM gaming_pending_winnings gpv LEFT JOIN
        gaming_high_tier_winning_levels ghtwl ON gpv.high_tier_winning_level_id = ghtwl.high_tier_winning_level_id
		WHERE game_play_id = pendingWinGamePlayID;
    END IF;
    
  #region Game provider win status
  -- Get game provider win status ID
  SELECT      
    ggpws.game_provider_win_status_id INTO gameProviderWinStatusID
  FROM
    gaming_game_provider_win_statuses ggpws LEFT JOIN 
    gaming_lottery_participation_statuses glps ON ggpws.status_code = glps.status_code 
  WHERE glps.lottery_participation_status_id = participationStatusID; -- May need to add manufacturer ID in future to ggpws

  IF (hasPendingWin) THEN        
    -- When pending win exists, override specific win status cases
    SET gameProviderWinStatusID = 
      CASE 
        -- was 'Win' + 'Paid' => now 'Paid from Win'
        WHEN pendingGameProviderWinStatusID=1 AND gameProviderWinStatusID=2 THEN 3
        -- was 'Provisional Win' + 'Paid' => now 'Paid from Provisional'
        WHEN pendingGameProviderWinStatusID=4 AND gameProviderWinStatusID=2 THEN 5
        -- All other cases defined (
        ELSE gameProviderWinStatusID
      END;                 
  END IF;

  -- Get game provider win fallback ID
  SELECT fallback_win_status_id INTO gameProviderWinStatusFallbackID FROM gaming_game_provider_win_statuses WHERE game_provider_win_status_id = gameProviderWinStatusID;


  #endregion

	IF (winClassificationEnabled=0 AND participationStatusID NOT IN (2105, 2110)) THEN
		SET statusCode = 3;
		LEAVE root;
	END IF;

	SET forcePendingWinnings = IF((winClassificationEnabled=1 AND participationStatusID=2104),1,0);
	IF (manualCashOut=1) THEN
		SET forcePendingWinnings=0;
	END IF;
  
	 -- provisional win status
	SET isProvisionalWin = IF (participationStatusID=2110, 1, 0);
  -- statuses that disable notifications
	SET forceNoNotifications = IF (participationStatusID IN (2110), 1, 0);

  IF (
     -- Catching multiple requests with win
    (participationWagerStatus = 6 /* win received */ AND pendingHighTierWinningLevelID <> provisionalWinClassificationID AND manualCashOut=0) OR
     -- Duplicate call place provisional win
    (hasPendingWin AND isProvisionalWin AND manualCashOut=0)
    ) THEN

  		IF (forcePendingWinnings=1 AND participationStatusID=2104 AND isProvisionalWin=0) THEN
			UPDATE gaming_lottery_participations
			SET lottery_participation_status_id = 2107 -- PENDING_PROCESSING (HIGH_WINNINGS)
			WHERE lottery_participation_id = lotteryParticipationID;
		END IF;

		SELECT gaming_game_plays.game_round_id, gaming_game_plays.client_stat_id, gaming_game_plays.game_manufacturer_id
		INTO gameRoundID, clientStatID, gameManufacturerID
		FROM gaming_game_plays_lottery_entries FORCE INDEX (lottery_participation_id)
		STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (PRIMARY) ON gaming_lottery_participations.lottery_participation_id = gaming_game_plays_lottery_entries.lottery_participation_id
		STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery_entries.game_play_id
        WHERE gaming_lottery_participations.lottery_participation_id = lotteryParticipationID
		LIMIT 1;
    
    	
    	CALL PlayReturnDataWithoutGameForSbExtraID(lotteryParticipationID, licenseTypeID, gameRoundID, clientStatID, gameManufacturerID, 0);
		CALL PlayReturnBonusInfoOnWinForSbExtraID(lotteryParticipationID, licenseTypeID);
        SET statusCode=0;

        LEAVE root;
  	ELSEIF (participationWagerStatus != 5 AND participationWagerStatus != 9 AND pendingHighTierWinningLevelID <> provisionalWinClassificationID AND manualCashOut=0) THEN
		SET statusCode = 1;
		LEAVE root;
    END IF;

	SELECT gs1.value_bool AS vb1, gs2.value_bool AS vb2, IFNULL(gs3.value_bool,0) AS bonusReedemAll,IFNULL(gs4.value_bool,0), IFNULL(gs5.value_bool,0) AS ruleEngineEnabled, IFNULL(gs6.value_bool,0) AS bonusesUsedAllWhenZero,
		IFNULL(gs7.value_bool,0) AS addWagerContributionWithRealBet
    INTO playLimitEnabled, bonusEnabledFlag,bonusReedemAll,ringFencedEnabled,ruleEngineEnabled, bonusesUsedAllWhenZero, addWagerContributionWithRealBet
    FROM gaming_settings gs1 
    STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	STRAIGHT_JOIN gaming_settings gs3 ON (gs3.name='BONUS_REEDEM_ALL_BONUS_ON_REDEEM')
	STRAIGHT_JOIN gaming_settings gs4 ON (gs4.name='RING_FENCED_ENABLED')
	STRAIGHT_JOIN gaming_settings gs5 ON (gs5.name='RULE_ENGINE_ENABLED')
	STRAIGHT_JOIN gaming_settings gs6 ON (gs6.name='TYPE_TWO_BONUSES_USED_ALL_WHEN_ZERO')
	STRAIGHT_JOIN gaming_settings gs7 ON (gs7.name='ADD_WAGER_CONTRIBUTION_WITH_REAL_BET')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
    
	SELECT client_id, gaming_client_stats.currency_id, bet_from_real
	INTO clientID, currencyID, betFromReal
	FROM gaming_client_stats 
	WHERE client_stat_id=clientStatID
	FOR UPDATE;

	SELECT exchange_rate INTO exchangeRate 
	FROM gaming_client_stats
	STRAIGHT_JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
	WHERE gaming_client_stats.client_stat_id=clientStatID
	LIMIT 1;
 
    SELECT SUM(net) INTO totalWinnings
	FROM gaming_lottery_participation_prizes FORCE INDEX (lottery_participation_id)
	WHERE lottery_participation_id = lotteryParticipationID AND net > 0;

	UPDATE gaming_lottery_participations FORCE INDEX (PRIMARY)
		SET gaming_lottery_participations.lottery_wager_status_id = 6, lottery_participation_status_id = participationStatusID
    WHERE gaming_lottery_participations.lottery_participation_id = lotteryParticipationID;

    SELECT gaming_game_plays_bonus_instances.bonus_instance_id, gaming_bonus_types_bet_returns.name, is_free_bonus, is_freebet_phase
    INTO topBonusInstanceID, retType,IsFreeBonus,isFreeBonusPhase
    FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
    STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_game_plays_bonus_instances.bonus_instance_id
	STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
    STRAIGHT_JOIN gaming_bonus_types_bet_returns ON gaming_bonus_types_bet_returns.bonus_type_bet_return_id = gaming_bonus_rules.bonus_type_bet_return_id
    WHERE gaming_game_plays_bonus_instances.game_play_id = gamePlayID AND gaming_game_plays_bonus_instances.bonus_order = 1;

	SELECT SUM(bet_bonus), COUNT(*)
    INTO bonusRetLostTotal, bonusCount
    FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_game_plays_bonus_instances.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
    WHERE gaming_game_plays_bonus_instances.game_play_id = gamePlayID;
    
	SELECT game_round_id INTO gameRoundIDForParticipation
	FROM gaming_game_rounds FORCE INDEX (sb_extra_id)
    WHERE gaming_game_rounds.sb_extra_id = lotteryParticipationID AND license_type_id = licenseTypeID;

    UPDATE gaming_game_rounds FORCE INDEX (PRIMARY)
    LEFT JOIN gaming_lottery_participation_prizes FORCE INDEX (lottery_participation_id) ON 
		gaming_lottery_participation_prizes.lottery_participation_id = gaming_game_rounds.sb_extra_id AND gaming_lottery_participation_prizes.lottery_participation_id IS NULL
    SET gaming_game_rounds.date_time_end= NOW(), gaming_game_rounds.is_round_finished=1, gaming_game_rounds.num_transactions=gaming_game_rounds.num_transactions+1
    WHERE gaming_game_rounds.game_round_id = gameRoundIDForParticipation;
    

    OPEN prizeCursor;
    
    prizeLoop : LOOP
    
		SET notMoreRows = 0;
        
        FETCH prizeCursor INTO lotteryParticipationPrizeID, winAmount, giftId, giftDescription, refundAmount;
        
		SET totalWinAmount = (totalWinAmount + winAmount);
		SET totalRefundAmount = (totalRefundAmount + refundAmount);

		-- I need both values to accept this as a non-monetary win
		SET isGift = NOT ISNULL(giftId) AND NOT ISNULL(giftDescription);

		IF(isGift) THEN
			SET giftAmount = winAmount;
			SET winAmount = 0;
 
		END IF; 
        
         -- For Jubilazo Win (Chile) Win amount is sent in 'Refund' as the money must not be added to player wallet
		SELECT lottery_wager_status_id INTO participationWagerStatus FROM gaming_lottery_participations WHERE lottery_participation_id = lotteryParticipationID;
        SET isCustom = ((licenseTypeID = 6) AND refundAmount > 0 AND participationWagerStatus = 6);
	
		IF (isCustom) THEN
		UPDATE gaming_lottery_participation_prizes SET gift_id='2' WHERE lottery_participation_id = lotteryParticipationID;
		END IF;
        
       
		IF notMoreRows THEN
			LEAVE prizeLoop;
		END IF;

		SET participationPrizeNumber=participationPrizeNumber+1;
        UPDATE gaming_lottery_participation_prizes SET participation_prize_no=participationPrizeNumber WHERE lottery_participation_prize_id=lotteryParticipationPrizeID;

    #region Loop params
		SET @updateBonusInstancesWins = 0;
		SET @ReduceFromReal = 0;
		SET @winBonusTemp=0;
		SET @winBonusCurrent=0;
		SET @winBonus=0;
		SET @winReal=0;
		SET @winBonusWinLocked=0;
		SET @winBonusLostCurrent=0;
		SET @winBonusWinLockedLostCurrent=0;
		SET @winBonusLost=0;
		SET @winBonusWinLockedLost=0;
		SET @winRealBonusCurrent=0;
		SET @winRealBonusWLCurrent=0;
		SET @NegateFromBetFromReal=0;
    #endregion

		INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameRoundID);
		SET gamePlayWinCounterID=LAST_INSERT_ID();

    #region Bonus
		IF (topBonusInstanceID!=-1) THEN
			SET @updateBonusInstancesWins = 1;
			-- IF (retType = 'Loss' ) THEN
			IF (retType = 'Loss' and not IsFreeBonus) THEN
				SET @winAmountTemp = winAmount - bonusRetLostTotal;
				IF (@winAmountTemp<0) THEN
					SET @winAmountTemp = 0;
				END IF;
			ELSE
				SET @winAmountTemp = winAmount;
			END IF;

			SET @bonusOrder = bonusCount + 1;

			INSERT INTO gaming_game_plays_bonus_instances_wins (game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, TIMESTAMP, exchange_rate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution,bonus_order)
			SELECT gamePlayWinCounterID, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, NOW(), exchangeRate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, clientStatID, NULL, 0, bonusOrder
			FROM
			(
				SELECT
					@bonusOrder := @bonusOrder - 1 AS bonusOrder,
					game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id,
					@isBonusSecured:=IF(is_secured, 1, @isBonusSecured),	
					@winBonusTemp := 
						ROUND(
								-- IF(@winAmountTemp>0,
								IF(@winAmountTemp>0 and not IsFreeBonus,
										IF(@winAmountTemp <  IF (is_freebet_phase OR IsFreeBonus, bonus_amount_given-bonus_amount_remaining,GREATEST(0,(bonus_amount_given-bonus_transfered_total-bonus_amount_remaining))),
												@winAmountTemp,
												IF (is_freebet_phase, bonus_amount_given-bonus_amount_remaining,GREATEST(0,(bonus_amount_given-bonus_transfered_total-bonus_amount_remaining)))
										   )
										,0
									),
							0),
					@winBonusCurrent :=  @winBonusTemp AS win_bonus,
					@winRealBonusCurrent := IF (is_secured=1  AND IsFreeBonus=0 AND is_freebet_phase=0, -- amount to win in real
										@winBonusTemp,
										@winRealBonusCurrent
									),

					@winAmountTemp:=  IF(@winAmountTemp>0 AND is_lost = 0,
							IF(@winAmountTemp < @winBonusCurrent,
									0,
									@winAmountTemp - @winBonusCurrent
							   )
							 ,@winAmountTemp
						   ) ,

					@ReduceFromReal :=  IF(bonus_order=1 AND @winAmountTemp>0,
									-- IF (IsFreeBonus OR is_freebet_phase,
									-- IF ((IsFreeBonus OR is_freebet_phase) AND is_lost=0,						 
									IF ((IsFreeBonus OR is_freebet_phase) AND is_lost=0,
										@winAmountTemp,
										IF(@winAmountTemp < IF(is_lost=1,bet_from_real,betFromReal),
													@winAmountTemp,
													IF(is_lost=1,bet_from_real,betFromReal)
										)
									),
									0
							),

					@winAmountTemp:= IF(bonus_order=1 AND @winAmountTemp>0,
								@winAmountTemp-@ReduceFromReal,
								@winAmountTemp
						),
						
					@winRealBonusWLCurrent := IF(bonus_order=1 AND is_lost = 0,
										@winAmountTemp,
										0
								   ) AS win_bonus_win_locked,
					@winAmountTemp:= IF(bonus_order=1 AND is_lost = 0,
								0,
								@winAmountTemp
						),
					@winBonusLostCurrent:=ROUND(
								IF(is_secured=0 AND is_lost=1,
										@winBonusTemp,
										0
									), 
								0) AS lost_win_bonus,
					@winBonusWinLockedLostCurrent:=ROUND(
											IF(is_secured=0 AND is_lost=1, 
												@winRealBonusWLCurrent,  
												0
											),
									 0) AS lost_win_bonus_win_locked,
					-- @winRealBonusCurrent:=IF((is_secured=1 ) OR (IsFreeBonus AND bonus_order=1), 
					-- @winRealBonusCurrent:=IF((is_secured=1 ) OR (IsFreeBonus AND bonus_order=1 AND is_lost=0), 
					@winRealBonusCurrent:=IF((is_secured=1 ) OR (not IsFreeBonus AND bonus_order=1 AND is_lost=0), 
					(CASE NAME
						WHEN 'All' THEN @winRealBonusWLCurrent + @winRealBonusCurrent - @winBonusLostCurrent - @winBonusWinLockedLostCurrent
						WHEN 'NonReedemableBonus' THEN @winRealBonusWLCurrent - @winBonusWinLockedLostCurrent
						WHEN 'Bonus' THEN @winRealBonusCurrent- @winBonusLostCurrent
						WHEN 'BonusWinLocked' THEN @winRealBonusWLCurrent- @winBonusWinLockedLostCurrent
						WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(bonus_amount_given-bonus_transfered_total, @winRealBonusWLCurrent + @winRealBonusCurrent- @winBonusLostCurrent - @winBonusWinLockedLostCurrent))
						WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((bonus_amount_given*transfer_upto_percentage)-bonus_transfered_total, @winRealBonusWLCurrent + @winRealBonusCurrent- @winBonusLostCurrent - @winBonusWinLockedLostCurrent))
						WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(bonus_amount_given-bonus_transfered_total, @winRealBonusWLCurrent + @winRealBonusCurrent- @winBonusLostCurrent - @winBonusWinLockedLostCurrent))
						WHEN 'ReleaseAllBonus' THEN @winBonusAllTemp
						ELSE 0
					-- END), 0) AS win_real,
					END), if(IsFreeBonus, @ReduceFromReal, 0))*1.00 AS win_real ,
					@winBonus:=@winBonus+@winBonusCurrent,
					@winBonusWinLocked:=@winBonusWinLocked+@winRealBonusWLCurrent,
					@winBonusLost:=@winBonusLost+@winBonusLostCurrent,
					@winBonusWinLockedLost:=@winBonusWinLockedLost+@winBonusWinLockedLostCurrent,
					@winReal := @winReal + @ReduceFromReal,
					bonus_amount_remaining, current_win_locked_amount
				FROM (
					SELECT 
						gaming_bonus_instances.bonus_amount_remaining,
						gaming_bonus_instances.current_win_locked_amount,
						SUM(bet_bonus_win_locked) AS bet_bonus_win_locked,
						gaming_bonus_instances.is_secured,
						gaming_bonus_instances.bonus_amount_given,
						gaming_bonus_instances.bonus_transfered_total,
						SUM(bet_bonus) AS bet_bonus,
						IF(gaming_bonus_rules.bonus_type_awarding_id  = 2 /*freebet*/ AND IsFreeBonus /*no wagering*/ , 0,  gaming_bonus_instances.is_lost) AS is_lost,
						bonus_order,
						gaming_bonus_rules.transfer_upto_percentage,
						transfer_type.name,
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
					WHERE  play_bonus_instances.game_play_id = gamePlayID
					GROUP BY gaming_bonus_instances.bonus_instance_id
					ORDER BY is_freebet_phase DESC, gaming_bonus_instances.given_date DESC, gaming_bonus_instances.bonus_instance_id DESC
				) AS gg
			) AS XX ON DUPLICATE KEY UPDATE bonus_instance_id=VALUES(bonus_instance_id), win_real=VALUES(win_real), win_bonus=VALUES(win_bonus), win_bonus_win_locked=VALUES(win_bonus_win_locked), lost_win_bonus=VALUES(lost_win_bonus), lost_win_bonus_win_locked=VALUES(lost_win_bonus_win_locked), client_stat_id=VALUES(client_stat_id);
			
			UPDATE gaming_game_plays_bonus_instances_wins AS ggpbiw FORCE INDEX (PRIMARY)
			STRAIGHT_JOIN gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (PRIMARY) ON ggpbiw.game_play_win_counter_id=gamePlayWinCounterID AND 
				ggpbi.game_play_bonus_instance_id=ggpbiw.game_play_bonus_instance_id 
			STRAIGHT_JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			SET
				ggpbi.win_bonus=IFNULL(ggpbi.win_bonus,0)+ggpbiw.win_bonus - ggpbiw.lost_win_bonus, 
				ggpbi.win_bonus_win_locked=IFNULL(ggpbi.win_bonus_win_locked,0)+ggpbiw.win_bonus_win_locked - ggpbiw.lost_win_bonus_win_locked, 
				ggpbi.win_real=  IFNULL(ggpbi.win_real,0)+ggpbiw.win_real,
				ggpbi.lost_win_bonus=IFNULL(ggpbi.lost_win_bonus,0)+ggpbiw.lost_win_bonus,
				ggpbi.lost_win_bonus_win_locked=IFNULL(ggpbi.lost_win_bonus_win_locked,0)+ggpbiw.lost_win_bonus_win_locked,
				ggpbi.now_used_all=IF(ROUND(gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount+ggpbiw.win_bonus+ggpbiw.win_bonus_win_locked,5)=0, 1, 0);

			SET winBonus=IFNULL(@winBonus,0)-IFNULL(@winBonusLost,0);
			SET winBonusWinLocked=IFNULL(@winBonusWinLocked,0)-IFNULL(@winBonusWinLockedLost,0);      
			SET winReal=IFNULL(@winReal,0);
		ELSE 
			SET winReal = winAmount;
			SET winBonus = 0;  
			SET winBonusWinLocked = 0; 
		END IF; 
		#endregion
		
    #region Win classifictaions
		IF (winClassificationEnabled=1) THEN
		  SET highTierWins = winReal + winBonus + winBonusWinLocked;

		  -- Get relevant classification
		  SELECT 
			lvl.high_tier_winning_level_id, act.payout_type_id, lvl.requires_approval
				INTO 
			approvalLevelID, classificationPayoutTypeID, approvalRequired

			FROM gaming_high_tier_winning_levels lvl
			LEFT JOIN gaming_high_tier_winning_level_amounts amnts ON amnts.high_tier_winning_level_id=lvl.high_tier_winning_level_id AND amnts.currency_id = currencyID
			STRAIGHT_JOIN gaming_high_tier_winning_level_actions act ON act.high_tier_winning_level_id=lvl.high_tier_winning_level_id
			WHERE 
			  act.is_default=1 AND -- only default payouts
			  lvl.license_type_id=licenseTypeID AND
			  (lvl.game_id IN (gameID) OR lvl.game_id IS NULL)  AND -- (game_id == gameID && game_id == null)
			  lvl.game_provider_win_status_id = gameProviderWinStatusID
		   AND (lvl.is_system OR  highTierWins BETWEEN amnts.min_amount AND IFNULL(amnts.max_amount,99999999999)) -- System classes do not carry amounts
			ORDER BY lvl.game_id DESC -- game_id == gameID priority over game_id == null
		   LIMIT 1;

		  IF (approvalLevelID=-1) THEN
			-- Get fallback classification
			SELECT 
			  lvl.high_tier_winning_level_id, act.payout_type_id, lvl.requires_approval
					INTO 
			  approvalLevelID, classificationPayoutTypeID, approvalRequired
			FROM gaming_high_tier_winning_levels lvl
					LEFT JOIN gaming_high_tier_winning_level_amounts amnts ON amnts.high_tier_winning_level_id=lvl.high_tier_winning_level_id AND amnts.currency_id = currencyID
					STRAIGHT_JOIN gaming_high_tier_winning_level_actions act ON act.high_tier_winning_level_id=lvl.high_tier_winning_level_id
					WHERE 
				act.is_default=1 AND -- only default payouts
				lvl.license_type_id=licenseTypeID AND
				(lvl.game_id IN (gameID) OR lvl.game_id IS NULL)  AND -- (game_id == gameID && game_id == null)
				lvl.game_provider_win_status_id = gameProviderWinStatusFallbackID
			 AND (lvl.is_system OR  highTierWins BETWEEN amnts.min_amount AND IFNULL(amnts.max_amount,99999999999)) -- System classes do not carry amounts
			  ORDER BY lvl.game_id DESC -- game_id == gameID priority over game_id == null
			 LIMIT 1;
		  END IF;


	   END IF;

  	SET moveToPendingWinnings= IF(
      -- Approval reqd.
      IFNULL(approvalRequired,0)=1 OR 
      -- payout not e-Wallet
      IFNULL(classificationPayoutTypeID,1) NOT IN (1) OR 
      -- high-tier forces pending win (this may not be necessary anymore)
      forcePendingWinnings=1, 
      1, 0
    );

    IF ( -- Approval not-reqd.
      IFNULL(approvalRequired,0)=0 AND 
      IFNULL(classificationPayoutTypeID,1) IN (4) AND
      forcePendingWinnings=0) THEN
      
      SET manualCashOut = 1;
      SET moveToPendingWinnings = 0;
    END IF;    
    #endregion

	SET forceNoNotifications = IFNULL(approvalRequired,0)=1;

		-- If manual cashout, avoid pending wins sum winnings together, disregard bonus
		IF(manualCashOut=1) THEN
			SET moveToPendingWinnings=0;
			SET highTierWins = winReal + winBonus + winBonusWinLocked;

			SET winReal=highTierWins;
			SET winBonus=0;
			SET winBonusWinLocked=0;
		END IF;
		
		IF (moveToPendingWinnings=1) THEN
			SET winReal=highTierWins;
			SET winBonus=0;
			SET winBonusWinLocked=0;
		END IF;
		
	
		UPDATE gaming_client_stats AS gcs FORCE INDEX (PRIMARY)
		LEFT JOIN gaming_client_sessions AS gcsession FORCE INDEX (PRIMARY) ON gcsession.session_id=sessionID   
		LEFT JOIN gaming_client_wager_stats AS gcws FORCE INDEX (PRIMARY) ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
		SET
		gcs.total_wallet_real_won_online = IF(moveToPendingWinnings=0,IF(@channelType = 'online', gcs.total_wallet_real_won_online + winReal, gcs.total_wallet_real_won_online),total_wallet_real_won_online),
			gcs.total_wallet_real_won_retail = IF(moveToPendingWinnings=0,IF(@channelType = 'retail', gcs.total_wallet_real_won_retail + winReal, gcs.total_wallet_real_won_retail),total_wallet_real_won_retail),
			gcs.total_wallet_real_won_self_service = IF(moveToPendingWinnings=0,IF(@channelType = 'self-service', gcs.total_wallet_real_won_self_service + winReal, gcs.total_wallet_real_won_self_service),total_wallet_real_won_self_service),
			gcs.total_wallet_real_won = IF(moveToPendingWinnings=0,gcs.total_wallet_real_won_online + gcs.total_wallet_real_won_retail + gcs.total_wallet_real_won_self_service,gcs.total_wallet_real_won),
			gcs.total_real_won = IF(moveToPendingWinnings=0,IF(@channelType NOT IN ('online','retail','self-service'),gcs.total_real_won+winReal, gcs.total_wallet_real_won + gcs.total_cash_win),gcs.total_real_won),
			gcs.current_real_balance=IF(moveToPendingWinnings=0,gcs.current_real_balance+winReal, gcs.current_real_balance),
			gcs.total_bonus_won=IF(moveToPendingWinnings=0,gcs.total_bonus_won+winBonus, gcs.total_bonus_won),
			gcs.current_bonus_balance=IF(moveToPendingWinnings=0,gcs.current_bonus_balance+winBonus, gcs.current_bonus_balance),
			gcs.total_bonus_win_locked_won=IF(moveToPendingWinnings=0,gcs.total_bonus_win_locked_won+winBonusWinLocked, gcs.total_bonus_win_locked_won),
			gcs.current_bonus_win_locked_balance=IF(moveToPendingWinnings=0,current_bonus_win_locked_balance+winBonusWinLocked, gcs.current_bonus_win_locked_balance),
			gcs.total_real_won_base=IF(moveToPendingWinnings=0,gcs.total_real_won_base+(winReal/exchangeRate), gcs.total_real_won_base),
			gcs.total_bonus_won_base=IF(moveToPendingWinnings=0,gcs.total_bonus_won_base+((winBonus+winBonusWinLocked)/exchangeRate),gcs.total_bonus_won_base),
			gcsession.total_win=IF(moveToPendingWinnings=0,gcsession.total_win+winAmount, gcsession.total_win),
			gcsession.total_win_base=IF(moveToPendingWinnings=0,gcsession.total_win_base+winAmount/exchangeRate, gcsession.total_win_base),
			gcsession.total_win_real=IF(moveToPendingWinnings=0,gcsession.total_win_real+winReal, gcsession.total_win_real),
			gcsession.total_win_bonus=IF(moveToPendingWinnings=0,gcsession.total_win_bonus+winBonus+winBonusWinLocked,gcsession.total_win_bonus),
			gcws.num_wins=IF(moveToPendingWinnings=0,gcws.num_wins+IF(winAmount>0, 1, 0), gcws.num_wins),
			gcws.total_real_won=IF(moveToPendingWinnings=0,gcws.total_real_won+winReal, gcws.total_real_won),
			gcws.total_bonus_won=IF(moveToPendingWinnings=0,gcws.total_bonus_won+winBonus+winBonusWinLocked,gcws.total_bonus_won),
			gcs.bet_from_real = IF(moveToPendingWinnings=0,IF(gcs.bet_from_real- winReal + IFNULL(@NegateFromBetFromReal,0)<0,0,gcs.bet_from_real- winReal + IFNULL(@NegateFromBetFromReal,0)),gcs.bet_from_real),
			gcs.pending_winning_real= IF(moveToPendingWinnings=0,gcs.pending_winning_real,IFNULL(gcs.pending_winning_real,0)+highTierWins)
		WHERE gcs.client_stat_id=clientStatID;  
	
		-- Adding a gameplay
		INSERT INTO gaming_game_plays 
		(
			amount_total, amount_total_base, exchange_rate, amount_real, 
			amount_bonus, amount_bonus_win_locked, bonus_lost, bonus_win_locked_lost, 
			jackpot_contribution, TIMESTAMP, game_id, game_manufacturer_id,
			operator_game_id, client_id, client_stat_id, session_id, game_round_id, 
			payment_transaction_type_id, is_win_placed, balance_real_after, 
			balance_bonus_after, balance_bonus_win_locked_after, currency_id, 
			round_transaction_no, game_play_message_type_id, license_type_id, 
			pending_bet_real, pending_bet_bonus, bet_from_real, platform_type_id,
			loyalty_points,loyalty_points_after,loyalty_points_bonus,
			loyalty_points_after_bonus, sb_bet_id, sb_extra_id, pending_winning_real
		)
		SELECT
			IF(moveToPendingWinnings=0, winAmount, 0), 
			IF(moveToPendingWinnings=0, winAmount/exchangeRate, 0), 
			IF(moveToPendingWinnings=0, exchangeRate, 0), 
			IF(moveToPendingWinnings=0, winReal, 0), 
			IF(moveToPendingWinnings=0, winBonus, 0), 
			IF(moveToPendingWinnings=0, winBonusWinLocked, 0), 
			IFNULL(@winBonusLost,0), ROUND(IFNULL(@winBonusWinLockedLost,0)+IFNULL(@winBonusLostFromPrevious,0),0), 0, NOW(), gameID, gameManufacturerID, operatorGameID, clientID, clientStatID, 
				sessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, current_real_balance, ROUND(current_bonus_balance+current_bonus_win_locked_balance,0), current_bonus_win_locked_balance, currencyID, numTransactions+1, game_play_message_type_id, licenseTypeID, pending_bets_real, pending_bets_bonus, gaming_client_stats.bet_from_real, @platformTypeID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`), couponID, lotteryParticipationID, 
			IF(moveToPendingWinnings=0, 0, highTierWins)
		FROM gaming_payment_transaction_type
		JOIN gaming_client_stats ON gaming_payment_transaction_type.name=IF(moveToPendingWinnings=1,'WinPendingAuthorisation','Win') AND gaming_client_stats.client_stat_id=clientStatID
		JOIN gaming_game_play_message_types ON gaming_game_play_message_types.`name`=
		CAST(CASE licenseTypeID 
		WHEN 6 THEN IF(moveToPendingWinnings=1,IF(isProvisionalWin=1, 'LotteryProvisionalPeriod','LotteryWinPendingAuthorization'),'LotteryWin') 
		WHEN 7 THEN IF(moveToPendingWinnings=1,IF(isProvisionalWin=1, 'SportsPoolProvisionalPeriod','SportsPoolWinPendingAuthorization'),'SportsPoolWin') END AS CHAR(80));

		SET newGamePlayID=LAST_INSERT_ID();

    IF (ruleEngineEnabled) THEN
        IF NOT EXISTS (SELECT event_table_id FROM gaming_event_rows WHERE event_table_id=1 AND elem_id=newGamePlayID) THEN
  		    INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, newGamePlayID
            ON DUPLICATE KEY UPDATE elem_id=VALUES(elem_id);
        END IF;
    END IF;
  
		UPDATE gaming_lottery_transactions SET game_play_id = newGamePlayID WHERE lottery_coupon_id = couponID and is_latest = 1;

		/* is show wins per participation (mostly for reports) */
		INSERT INTO gaming_game_plays_lottery_entries (game_play_id,lottery_draw_id, lottery_participation_id, amount_total, amount_real, amount_bonus, amount_bonus_win_locked, amount_ring_fenced, amount_free_bet, loyalty_points, loyalty_points_bonus,lottery_participation_prize_id)
		SELECT game_play_id, lotteryDrawID, lotteryParticipationID, amount_total, IF(moveToPendingWinnings=0,amount_real, highTierWins), amount_bonus, amount_bonus_win_locked, amount_ring_fenced, amount_free_bet, loyalty_points, loyalty_points_bonus, lotteryParticipationPrizeID
		FROM gaming_game_plays
		WHERE game_play_id = newGamePlayID;
		
		SET gamePlayLotteryEntryIDWin = LAST_INSERT_ID();
		
		SET @totalBetBonus = 0;

		/* is show wins from bonus bet (mostly for reports) */
		INSERT INTO gaming_game_plays_lottery_entry_bonus_wins (game_play_lottery_entry_id,bonus_instance_id,win_real,win_bonus,win_bonus_win_locked,win_ring_fenced,TIMESTAMP,game_play_lottery_entry_id_win)
		SELECT lotteryEntryID,bonus_instance_id, tempWinReal, tempWinBonus, tempWinBonusWinLocked, 0, NOW(), gamePlayLotteryEntryIDWin
		FROM (
			SELECT lottery_draw_id,lottery_participation_id,bonus_instance_id,
				@currentBetBonus := IF(amount_bonus>0,IF(amount_bonus - @totalBetBonus>bonus_amount_given-bonus_amount_remaining,bonus_amount_given-bonus_amount_remaining,amount_bonus-@totalBetBonus),0) AS tempWinBonus,
				@totalBetBonus := @totalBetBonus + @currentBetBonus,
				@currentBetreal := IF(bonus_order=1,amount_real,0) AS tempWinReal,
				@currentBetBonusWinLocked := IF(bonus_order=1,amount_bonus_win_locked,0) AS tempWinBonusWinLocked
			FROM (
				SELECT lottery_draw_id, lottery_participation_id, gaming_game_plays_bonus_instances_wins.bonus_instance_id,amount_bonus,bonus_amount_given,bonus_amount_remaining,amount_real,bonus_order,amount_bonus_win_locked
				FROM gaming_game_plays_lottery_entries FORCE INDEX (game_play_id)
				STRAIGHT_JOIN gaming_game_plays_bonus_instances_wins FORCE INDEX (PRIMARY) ON gaming_game_plays_bonus_instances_wins.game_play_win_counter_id = gamePlayWinCounterID
				STRAIGHT_JOIN gaming_bonus_instances ON gaming_game_plays_bonus_instances_wins.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
				WHERE gaming_game_plays_lottery_entries.game_play_id = newGamePlayID 
				ORDER BY gaming_bonus_instances.is_freebet_phase DESC, gaming_bonus_instances.given_date DESC, gaming_bonus_instances.bonus_instance_id DESC
			) AS innerTable
		) AS tempTbl;

		UPDATE gaming_game_plays_lottery_entry_bonus_wins FORCE INDEX (PRIMARY) 
		STRAIGHT_JOIN gaming_game_plays_lottery_entry_bonuses FORCE INDEX (PRIMARY) ON 
			gaming_game_plays_lottery_entry_bonus_wins.game_play_lottery_entry_id = gaming_game_plays_lottery_entry_bonuses.game_play_lottery_entry_id
			AND gaming_game_plays_lottery_entry_bonus_wins.bonus_instance_id = gaming_game_plays_lottery_entry_bonuses.bonus_instance_id
		SET 
			gaming_game_plays_lottery_entry_bonuses.win_real = gaming_game_plays_lottery_entry_bonuses.win_real + gaming_game_plays_lottery_entry_bonus_wins.win_real,
			gaming_game_plays_lottery_entry_bonuses.win_bonus = gaming_game_plays_lottery_entry_bonuses.win_bonus + gaming_game_plays_lottery_entry_bonus_wins.win_bonus,
			gaming_game_plays_lottery_entry_bonuses.win_bonus_win_locked = gaming_game_plays_lottery_entry_bonuses.win_bonus_win_locked + gaming_game_plays_lottery_entry_bonus_wins.win_bonus_win_locked
		WHERE gaming_game_plays_lottery_entry_bonus_wins.game_play_lottery_entry_id_win = gamePlayLotteryEntryIDWin;

		/* do it despite pending status */
		UPDATE gaming_game_plays FORCE INDEX (game_round_id) SET is_win_placed=1 WHERE game_round_id=gameRoundID AND gaming_game_plays.is_win_placed=0;
		
    #region Pending winnings
    -- Had pending win, now second place win
    IF (moveToPendingWinnings AND hasPendingWin) THEN       
				-- Approval required - Awaiting review
				SET pendingWinStatusID = 0;
				-- No notifications
				SET forceNoNotifications = 1;
				-- Update participatin
				UPDATE gaming_lottery_participations
					SET lottery_participation_status_id = 2107 -- pending processing (high winnings)
				WHERE lottery_participation_id = lotteryParticipationID;
				-- Update pending win
				UPDATE gaming_pending_winnings SET
					lottery_participation_id=lotteryParticipationID,
					high_tier_winning_level_id=approvalLevelID,
					amount=highTierWins,
					base_amount=highTierWins,
					currency_id=currencyID,
					pending_winning_status_id=pendingWinStatusID,
					payout_type_id=classificationPayoutTypeID,
					date_updated=NOW()
				WHERE
					game_play_id = pendingWinGamePlayID;
									
    -- Move to pending (requires approval or forced)
		ELSEIF (moveToPendingWinnings) THEN 
      
			-- Pre-approved statuses that do not require approval
			SET pendingWinStatusID = IF(approvalRequired=1, 0, 4);
			
			IF (isProvisionalWin) THEN
				-- Provisional winnings	place Win
				-- override pend. status for PROVISIONAL WIN (pending review)
				SET pendingWinStatusID = 6;
				
				UPDATE gaming_lottery_participations				
					SET lottery_participation_status_id = 2110
				WHERE lottery_participation_id = lotteryParticipationID;
				
			ELSEIF (forcePendingWinnings) THEN
				-- override pend. status for HIGH-TIER win
				SET pendingWinStatusID = 5;

				UPDATE gaming_lottery_participations
					SET lottery_participation_status_id = 2107 -- pending processing (high winnings)
				WHERE lottery_participation_id = lotteryParticipationID;
			ELSE
				UPDATE gaming_lottery_participations
					SET lottery_participation_status_id = 2107 -- pending processing (high winnings)
				WHERE lottery_participation_id = lotteryParticipationID;
			END IF;
		
		  -- Add pending win
		  INSERT INTO gaming_pending_winnings (game_play_id, lottery_coupon_id,lottery_participation_id, client_stat_id, high_tier_winning_level_id,
			amount, base_amount, currency_id, pending_winning_status_id, payout_type_id, date_created, date_updated, retailer_id, participation_prize_no)
		  VALUES (newGamePlayID, couponID, lotteryParticipationID, clientStatID, approvalLevelID, 
			highTierWins, highTierWins, currencyID, pendingWinStatusID, classificationPayoutTypeID, NOW(), NOW(), NULL, participationPrizeNumber);						
	
	  -- Do not move to pending (no approval reqd.) 
		ELSE
			-- below it is not approval required with default e-wallet, must be paid
      #region Bonus
			/* do not need for POS*/
			UPDATE 
			(
				SELECT play_bonus.bonus_instance_id, SUM(play_bonus_wins.win_real) AS win_real, SUM(play_bonus_wins.win_bonus-play_bonus_wins.lost_win_bonus) AS win_bonus, SUM(play_bonus_wins.win_ring_fenced) AS win_ring_fenced, 
					SUM(play_bonus_wins.win_bonus_win_locked-play_bonus_wins.lost_win_bonus_win_locked) AS win_bonus_win_locked, SUM(IFNULL(play_bonus_wins.add_wager_contribution, 0)) AS add_wager_contribution, MIN(play_bonus.now_used_all) AS now_used_all
				FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins FORCE INDEX (PRIMARY)
				STRAIGHT_JOIN gaming_game_plays_bonus_instances AS play_bonus FORCE INDEX (PRIMARY) ON play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND 
					play_bonus_wins.game_play_bonus_instance_id=play_bonus.game_play_bonus_instance_id 
				GROUP BY play_bonus.bonus_instance_id
			) AS PB
			STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=PB.bonus_instance_id
			STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
			SET 
				gaming_bonus_instances.bonus_amount_remaining=bonus_amount_remaining+IFNULL(PB.win_bonus,0),
				gaming_bonus_instances.current_win_locked_amount=gaming_bonus_instances.current_win_locked_amount+IFNULL(PB.win_bonus_win_locked,0),
				gaming_bonus_instances.total_amount_won=total_amount_won+(IFNULL(PB.win_bonus,0)+IFNULL(PB.win_bonus_win_locked,0)),
				gaming_bonus_instances.bonus_transfered_total=gaming_bonus_instances.bonus_transfered_total+IFNULL(PB.win_real,0),
				gaming_bonus_instances.current_ring_fenced_amount=gaming_bonus_instances.current_ring_fenced_amount+IFNULL(PB.win_ring_fenced,0),
				gaming_bonus_instances.is_used_all=IF(gaming_bonus_instances.is_active=1 AND PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-1)<=0 AND (gaming_bonus_rules.is_free_bonus OR gaming_bonus_instances.is_freebet_phase), 1, 0),
				gaming_bonus_instances.is_active=IF(gaming_bonus_instances.is_active=1 AND PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-1)<=0 AND (gaming_bonus_rules.is_free_bonus OR gaming_bonus_instances.is_freebet_phase), 0, gaming_bonus_instances.is_active),
				gaming_bonus_instances.open_rounds=gaming_bonus_instances.open_rounds-1;

			IF (@winBonusLost+@winBonusWinLockedLost>0) THEN
				INSERT INTO gaming_bonus_losts (bonus_instance_id, client_stat_id, bonus_lost_type_id, bonus_amount, bonus_win_locked_amount, extra_id, date_time_lost, session_id)
				SELECT bonus_instance_id, client_stat_id, gaming_bonus_lost_types.bonus_lost_type_id, IFNULL(SUM(lost_win_bonus),0), IFNULL(SUM(lost_win_bonus_win_locked),0), gamePlayWinCounterID, NOW(), sessionID
				FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins FORCE INDEX (PRIMARY) 
				STRAIGHT_JOIN gaming_bonus_lost_types ON play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND 
					(play_bonus_wins.lost_win_bonus!=0 OR play_bonus_wins.lost_win_bonus_win_locked!=0) 
				WHERE gaming_bonus_lost_types.name='WinAfterLost'
				GROUP BY play_bonus_wins.bonus_instance_id;  
			END IF;
			#endregion
			
			/* should we inform limits if it is POS? */
			IF (playLimitEnabled AND winAmount > 0) THEN
				CALL PlayLimitsUpdateWithGame(sessionID, clientStatID, licenseType, winAmount, 0, gameID);
			END IF;

      #region Bonus
			IF (bonusEnabledFlag AND @updateBonusInstancesWins) THEN
				UPDATE gaming_game_plays_bonus_instances_wins
				SET win_game_play_id=newGamePlayID
				WHERE game_play_win_counter_id=gamePlayWinCounterID;
			END IF;
      #endregion
			
			-- We should update the pending win
			IF (hasPendingWin) THEN
        -- Default paid
				SET pendingWinStatusID = 2;
				
				IF (pendingHighTierWinningLevelID=provisionalWinClassificationID AND gameProviderWinStatusID=5) THEN			
				-- Provisional win that was classified as auto-aproved
					SET pendingWinStatusID = 2; -- Provisional Winnings					
					SET forceNoNotifications = 0; -- Notifications on
			  END IF;
					
					UPDATE gaming_lottery_participations
						SET lottery_participation_status_id = 2105 -- Status PAID
					WHERE lottery_participation_id = lotteryParticipationID;
					-- Update pending win
					UPDATE gaming_pending_winnings SET
						lottery_participation_id=lotteryParticipationID,
						high_tier_winning_level_id=approvalLevelID,
						amount=highTierWins,
						base_amount=highTierWins,
						currency_id=currencyID,
						pending_winning_status_id=pendingWinStatusID,
						payout_type_id=classificationPayoutTypeID,
						date_updated=NOW()
					WHERE
						game_play_id = pendingWinGamePlayID;
										
		END IF;
			END IF;
		#endregion

		INSERT INTO gaming_game_plays_win_counter_bets (game_play_win_counter_id, game_play_id, win_game_play_id)
		VALUES (gamePlayWinCounterID, gamePlayID, newGamePlayID);

		UPDATE gaming_game_rounds FORCE INDEX (PRIMARY)
		STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
		SET 
			win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+(winAmount/exchangeRate),5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus, 
			win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked, win_bet_diffence_base=win_total_base-bet_total_base,
			bonus_lost=bonus_lost+@winBonusLost, bonus_win_locked_lost=bonus_win_locked_lost+IFNULL(@winBonusWinLockedLost,0)+IFNULL(@winBonusLostFromPrevious,0), 
			date_time_end= NOW(), is_round_finished= 1, num_transactions=num_transactions+1, 
			balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance
		WHERE gaming_game_rounds.game_round_id=gameRoundID;   

		UPDATE gaming_game_rounds FORCE INDEX (PRIMARY)
		STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
		SET 
			win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+(winAmount/exchangeRate),5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus, 
			win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked, win_bet_diffence_base=win_total_base-bet_total_base,
			bonus_lost=bonus_lost+@winBonusLost, bonus_win_locked_lost=bonus_win_locked_lost+IFNULL(@winBonusWinLockedLost,0)+IFNULL(@winBonusLostFromPrevious,0), 
			date_time_end= NOW(), is_round_finished=1, num_transactions=num_transactions+1, 
			balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance
		WHERE gaming_game_rounds.game_round_id=gameRoundIDForParticipation;   

    #region Bonus
		IF ((@isBonusSecured OR IsFreeBonus OR isFreeBonusPhase) AND (moveToPendingWinnings=0)) THEN
			CALL BonusConvertWinningsAfterSecuredDate(newGamePlayID,gamePlayWinCounterID);
		END IF;
		
		IF (bonusesUsedAllWhenZero AND bonusEnabledFlag) THEN

			SELECT current_bonus_balance, current_real_balance, current_bonus_win_locked_balance
			INTO currentBonusAmount, currentRealAmount, currentWinLockedAmount
			FROM gaming_client_stats
			WHERE client_stat_id = ClientStatID;

			-- CHECK IF PLAYER HAS ANY ACTIVE BONUSES
			SELECT IF (COUNT(1) > 0, 1, 0) INTO playerHasActiveBonuses FROM gaming_bonus_instances WHERE client_stat_id = clientStatID AND (is_active = 1);

			IF (currentBonusAmount = 0 AND currentRealAmount = 0 AND currentWinLockedAmount = 0 AND playerHasActiveBonuses) THEN -- AND -- has active bonuses)
				CALL BonusForfeitBonus(sessionID, clientStatID, 0, 0, 'IsUsedAll', 'TYPE_TWO_BONUSES_USED_ALL_WHEN_ZERO - Used All');
			END IF;
		END IF;
    #endregion

		IF (notificationEnabled=1 AND forceNoNotifications=0) THEN

			IF (moveToPendingWinnings=1) THEN
				INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
				VALUES (526,newGamePlayID, NULL, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
			END IF;

			IF (totalWinAmount > 0 AND IFNULL(winNotification, 1)) THEN -- Win Notification if Amount > 0
				INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
				VALUES (CASE licenseTypeID WHEN 6 THEN 523 WHEN 7 THEN 562 END, couponID, lotteryParticipationID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
			ELSEIF (totalRefundAmount > 0 AND IFNULL(winNotification, 1)=1) THEN
				INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
				VALUES (801, couponID, lotteryParticipationID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
			ELSEIF (lossNotification=1) THEN -- Loss Notification
				INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
				VALUES (CASE licenseTypeID WHEN 6 THEN 555 WHEN 7 THEN 567 END, couponID, lotteryParticipationID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
			END IF;
		END IF; 

		IF (isGift) THEN
			SELECT loyalty_redemption_prize_type_id INTO giftTypeId
			FROM gaming_loyalty_redemption_prize_types 
			WHERE prize_type='GIFT';

			SET redemptionPrizeCount = 0;
			SELECT COUNT(*) INTO redemptionPrizeCount
			FROM gaming_loyalty_redemption_prizes
			WHERE external_id = giftId AND loyalty_redemption_prize_type_id=giftTypeId;

			IF(redemptionPrizeCount > 0) THEN
				UPDATE gaming_loyalty_redemption_prizes SET prize_type_extra_text=giftDescription, cost=giftAmount WHERE external_id = giftId AND loyalty_redemption_prize_type_id=giftTypeId;
			ELSE
				INSERT INTO gaming_loyalty_redemption_prizes (external_id, loyalty_redemption_prize_type_id, prize_type_extra_text, cost) VALUES (giftId, giftTypeId, giftDescription, giftAmount);
			END IF;
		END IF;
	END LOOP;
 
	UPDATE gaming_lottery_coupons FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN (
		SELECT COUNT(*) AS participationReserved
        FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
        STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id AND lottery_wager_status_id IN (6,7,8)
        WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID 
    ) AS total_participations ON 1=1
    SET gaming_lottery_coupons.lottery_wager_status_id = 6
    WHERE gaming_lottery_coupons.lottery_coupon_id = couponID AND  participationReserved = gaming_lottery_coupons.num_participations;

	-- update Coupon Status
	SET newCouponStatus = PropagateCouponStatusFromParticipations(couponID, currentCouponStatus, 0);


	SELECT SUM(gross) AS gross, SUM(net) AS net
	INTO grossToAdd, netToAdd
	FROM gaming_lottery_participation_prizes FORCE INDEX (lottery_participation_id)
	WHERE lottery_participation_id = lotteryParticipationID
	GROUP BY lottery_participation_id;

	IF(grossToAdd IS NULL OR moveToPendingWinnings) THEN 
		SET grossToAdd=0;
	END IF;
	IF(netToAdd IS NULL OR moveToPendingWinnings) THEN 
		SET netToAdd=0;
	END IF;

	UPDATE gaming_lottery_coupons
	SET lottery_coupon_status_id=newCouponStatus, is_high_tier=IFNULL(moveToPendingWinnings, IF(isProvisionalWin=0,1,0)),
		win_gross_amount=IFNULL(win_gross_amount,0)+grossToAdd, win_net_amount=IFNULL(win_net_amount,0)+netToAdd,
		win_tax_amount=IFNULL(win_tax_amount,0)+(grossToAdd-netToAdd), win_amount=IFNULL(win_amount,0) + IF(moveToPendingWinnings,0,grossToAdd)
	WHERE gaming_lottery_coupons.lottery_coupon_id=couponID;

	IF (manualCashOut=1 AND classificationPayoutTypeID<>4) THEN -- High-tier Point of Sales cashouts
		SET paymentMethodID=250; -- POS

		-- Emulate top-up+manual withdrawal
		CALL TransactionBalanceAccountUpdate(NULL, clientStatID, NULL, NULL, NULL, paymentMethodID, 1, 0, 0, -1, 0, 
			NULL, NULL, 1, 0, 'User', NULL, NULL, NULL, newBalanceAccountID, statusCode);
		
        CALL TransactionCreateManualWithdrawal(clientStatID, paymentMethodID, newBalanceAccountID, highTierWins, NOW(), 0, NULL, 
			'Physical Pick-Up', NULL, NULL, 0, NULL, 0,balanceManualTransactionID, NULL, 'Lotto-3rdParty',1, 0, statusCode);
            
	ELSEIF (classificationPayoutTypeID=4) THEN
		-- External Payment payout method (CPREQ-128/131)
		-- Changed to External Payments PM for Manual Payment Processing
		SET paymentMethodID=290; -- External Payments

		-- Emulate top-up+manual withdrawal
		CALL TransactionBalanceAccountUpdate(NULL, clientStatID, NULL, NULL, NULL, paymentMethodID, 1, 0, 0, -1, 0, 
			NULL, NULL, 1, 0, 'User', NULL, NULL, NULL, newBalanceAccountID, statusCode);
		CALL TransactionCreateManualWithdrawal(clientStatID, paymentMethodID, newBalanceAccountID, highTierWins, NOW(), 0, NULL, 'External Payment', NULL, NULL, 0, NULL, 0, balanceManualTransactionID, NULL, 'Lotto-3rdParty', 1, 0, statusCode);
	END IF;

	CALL PlayReturnDataWithoutGameForSbExtraID(lotteryParticipationID, licenseTypeID, gameRoundIDForParticipation, clientStatID, gameManufacturerID, 0);
	CALL PlayReturnBonusInfoOnWinForSbExtraID(lotteryParticipationID, licenseTypeID);

	SET statusCode =0;
END$$

DELIMITER ;

