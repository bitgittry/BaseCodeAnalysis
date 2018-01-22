DROP procedure IF EXISTS `PlaceCashWinTypeTwoLotto`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceCashWinTypeTwoLotto`(lotteryParticipationID BIGINT, sessionID BIGINT, OUT statusCode INT)
root:BEGIN
	
	DECLARE clientStatID, clientID, currencyID, gamePlayID, gameRoundID, gameRoundIDForParticipation, topBonusInstanceID, gamePlayWinCounterID, couponID, gameID, gameManufacturerID, operatorGameID,
		platformTypeID, newGamePlayID, lotteryDrawID, lotteryParticipationPrizeID,lotteryEntryID, gamePlayLotteryEntryIDWin, approvalLevelID, paymentMethodID, newBalanceAccountID, balanceManualTransactionID, pendingWinGamePlayID BIGINT DEFAULT -1;
	DECLARE playLimitEnabled, bonusEnabledFlag, bonusReedemAll, ringFencedEnabled, ruleEngineEnabled, bonusesUsedAllWhenZero, addWagerContributionWithRealBet,
    IsFreeBonus,isFreeBonusPhase, playerHasActiveBonuses, notMoreRows, channelCashEnabled TINYINT(1) DEFAULT 0;
    DECLARE betFromReal, exchangeRate, winCash, winAmount, grossAmount, netAmount, taxAmount, totalWinAmount, totalGrossAmount, totalNetAmount, totalTaxAmount, totalParticipationWinAmount DECIMAL(18,5);
    DECLARE retType, licenseType VARCHAR(80);
    DECLARE numTransactions, bonusCount, errorCode, classificationPayoutTypeID, participationStatusID, participationWagerStatus, blockLevel, licenseTypeID, clientWagerTypeID INT;
	DECLARE notificationEnabled, approvalRequired TINYINT DEFAULT 0;
	DECLARE newCouponStatus, currentCouponStatus INT(4);
	-- Variables for non-menetary wins
	DECLARE isGift TINYINT DEFAULT 0;
	DECLARE giftId, redemptionPrizeCount, giftTypeId BIGINT(20);
    DECLARE giftDescription VARCHAR(255);
	DECLARE giftAmount DECIMAL(18,5);

    DECLARE prizeCursor CURSOR FOR
		SELECT lottery_participation_prize_id, net, platform_type_id, gross, gift_id, gift_description
        FROM gaming_lottery_participation_prizes FORCE INDEX (lottery_participation_id)
        WHERE lottery_participation_id = lotteryParticipationID AND net > 0;
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET notMoreRows = TRUE;

	SET totalWinAmount = 0;
	
	SET totalGrossAmount = 0;
	SET totalNetAmount = 0;
	SET totalTaxAmount = 0;
    SET totalParticipationWinAmount = 0;
    
  SELECT gs1.value_bool as vb1
  INTO ruleEngineEnabled
  FROM gaming_settings gs1 
  WHERE gs1.name='RULE_ENGINE_ENABLED';
  
    /*SELECT error_code, lottery_wager_status_id, lottery_participation_status_id, block_level
    INTO errorCode, participationWagerStatus, participationStatusID, blockLevel
    FROM gaming_lottery_participations
    WHERE lottery_participation_id = lotteryParticipationID;*/
	
	SELECT gaming_game_plays_lottery_entries.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.client_stat_id, gaming_game_plays_lottery.lottery_coupon_id, gaming_lottery_draws.game_id, 
		gaming_lottery_draws.game_manufacturer_id, gaming_operator_games.operator_game_id, num_transactions, gaming_lottery_draws.lottery_draw_id,gaming_game_plays_lottery_entries.game_play_lottery_entry_id, gaming_game_plays.session_id, gaming_game_plays.payment_method_id, gaming_lottery_participations.lottery_wager_status_id, gaming_lottery_participations.lottery_participation_status_id, gaming_lottery_participations.block_level
    INTO gamePlayID, gameRoundID, clientStatID, couponID, gameID, gameManufacturerID, operatorGameID, numTransactions,lotteryDrawID, lotteryEntryID, sessionID, paymentMethodID, participationWagerStatus, participationStatusID, blockLevel
    FROM gaming_game_plays_lottery_entries FORCE INDEX (lottery_participation_id)
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (PRIMARY) ON gaming_lottery_participations.lottery_participation_id = gaming_game_plays_lottery_entries.lottery_participation_id -- AND gaming_lottery_participations.lottery_wager_status_id = 9
    STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery_entries.game_play_id
    STRAIGHT_JOIN gaming_game_plays_lottery FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery.game_play_id
    STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_game_plays_lottery_entries.lottery_draw_id
    STRAIGHT_JOIN gaming_operator_games ON gaming_operator_games.game_id = gaming_lottery_draws.game_id
	STRAIGHT_JOIN gaming_operators ON gaming_operators.operator_id = gaming_operator_games.operator_id AND gaming_operators.is_main_operator = 1
    STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (PRIMARY) ON gaming_game_rounds.game_round_id = gaming_game_plays.game_round_id
    WHERE gaming_game_plays_lottery_entries.lottery_participation_id = lotteryParticipationID;
	
    SELECT 
		gaming_pending_winnings.game_play_id INTO pendingWinGamePlayID
	FROM gaming_game_plays_lottery_entries  FORCE INDEX (lottery_participation_id)
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (PRIMARY) ON gaming_lottery_participations.lottery_participation_id = gaming_game_plays_lottery_entries.lottery_participation_id AND gaming_lottery_participations.lottery_wager_status_id = participationWagerStatus
    LEFT OUTER JOIN gaming_pending_winnings ON gaming_game_plays_lottery_entries.game_play_id = gaming_pending_winnings.game_play_id     
    WHERE gaming_lottery_participations.lottery_participation_id = lotteryParticipationID AND gaming_pending_winnings.game_play_id IS NOT NULL LIMIT 0, 1;
    
	SELECT lottery_coupon_status_id, gaming_lottery_coupons.license_type_id, gaming_license_type.`name`, gaming_client_wager_types.client_wager_type_id,
		   IFNULL(win_gross_amount, 0), IFNULL(win_net_amount, 0), IFNULL(win_tax_amount, 0), IFNULL(win_amount, 0)
	INTO currentCouponStatus, licenseTypeID, licenseType, clientWagerTypeID, totalGrossAmount, totalNetAmount, totalTaxAmount, totalWinAmount
	FROM gaming_lottery_coupons 
	JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_lottery_coupons.license_type_id
	JOIN gaming_client_wager_types ON gaming_client_wager_types.license_type_id = gaming_license_type.license_type_id
	WHERE lottery_coupon_id=couponID;
	
	IF (blockLevel = 2108) THEN
  		SET statusCode = 2;
  		LEAVE root;
  	END IF;

	IF (participationWagerStatus = 10) THEN   

		SELECT gaming_game_plays.game_round_id, gaming_game_plays.client_stat_id, gaming_game_plays.game_manufacturer_id
		INTO gameRoundID, clientStatID, gameManufacturerID
		FROM gaming_game_plays_lottery_entries FORCE INDEX (lottery_participation_id)
		JOIN gaming_lottery_participations FORCE INDEX (PRIMARY) ON gaming_lottery_participations.lottery_participation_id = gaming_game_plays_lottery_entries.lottery_participation_id
		JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery_entries.game_play_id
        WHERE gaming_lottery_participations.lottery_participation_id = lotteryParticipationID
		LIMIT 1;
-- check
    	CALL PlayReturnDataWithoutGameForSbExtraID(lotteryParticipationID, licenseTypeID, gameRoundID, clientStatID, gameManufacturerID, 0);
		CALL PlayReturnBonusInfoOnWinForSbExtraID(lotteryParticipationID, licenseTypeID);
        SET statusCode=0;
        LEAVE root;
	ELSEIF (statusCode != 9) THEN
		SET statusCode = 1;
		LEAVE root;
    END IF;
    
-- check to skip limits
	SELECT IFNULL(gs1.value_bool,0), IFNULL(gs2.value_bool,0)
    INTO addWagerContributionWithRealBet, notificationEnabled
	FROM gaming_settings gs1 
	JOIN gaming_settings gs2 ON gs2.`name` = 'NOTIFICATION_ENABLED'
    WHERE gs1.`name`='ADD_WAGER_CONTRIBUTION_WITH_REAL_BET';
       	
	SELECT client_id, gaming_client_stats.currency_id, bet_from_real
	INTO clientID, currencyID, betFromReal
	FROM gaming_client_stats 
	WHERE client_stat_id=clientStatID
	FOR UPDATE;
    
	SELECT exchange_rate into exchangeRate 
	FROM gaming_client_stats
	STRAIGHT_JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
	WHERE gaming_client_stats.client_stat_id=clientStatID
	LIMIT 1;
        
	UPDATE gaming_lottery_participations FORCE INDEX (PRIMARY)
    SET gaming_lottery_participations.lottery_wager_status_id = 10, lottery_participation_status_id = participationStatusID
    WHERE gaming_lottery_participations.lottery_participation_id = lotteryParticipationID;

	SELECT game_round_id INTO gameRoundIDForParticipation
	FROM gaming_game_rounds FORCE INDEX (sb_extra_id)
    WHERE gaming_game_rounds.sb_extra_id = lotteryParticipationID AND license_type_id = licenseTypeID;
  
    OPEN prizeCursor;
    
    prizeLoop : LOOP
    
		SET notMoreRows = 0;
        
        FETCH prizeCursor INTO lotteryParticipationPrizeID, winAmount, PlatformTypeID, grossAmount, giftId, giftDescription;
        
		SET netAmount = winAmount;
		SET taxAmount = grossAmount - netAmount;
		SET totalParticipationWinAmount = totalParticipationWinAmount + winAmount;
        
		-- I need both values to accept this as a non-monetary win
		SET isGift = NOT ISNULL(giftId) AND NOT ISNULL(giftDescription);

		IF(isGift) THEN
			SET giftAmount = winAmount;

			SET winAmount = 0;
			SET grossAmount = 0;
			SET netAmount = 0;
			SET taxAmount = 0;
		END IF;
		IF notMoreRows THEN
			LEAVE prizeLoop;
		END IF;
		
		SET totalWinAmount = (totalWinAmount + IFNULL(winAmount, 0));
		
		SET totalGrossAmount = (totalGrossAmount + IFNULL(grossAmount, 0));
		SET totalNetAmount = (totalNetAmount + IFNULL(netAmount, 0));
		SET totalTaxAmount = (totalTaxAmount + IFNULL(taxAmount, 0));
		
		CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, @platformTypeID, @platformType, @channelTypeID, @channelType);
		
    -- Check if Cash Enabled for that Channel
		SELECT cash_enabled INTO channelCashEnabled	FROM gaming_channel_types WHERE channel_type = @channelType;
		IF (channelCashEnabled = 1) THEN 

		INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameRoundID);
		SET gamePlayWinCounterID=LAST_INSERT_ID();		
		
		UPDATE gaming_client_stats AS gcs FORCE INDEX (PRIMARY)
		LEFT JOIN gaming_client_sessions AS gcsession FORCE INDEX (PRIMARY) ON gcsession.session_id=sessionID   
		LEFT JOIN gaming_client_wager_stats AS gcws FORCE INDEX (PRIMARY) ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
		SET 
			gcs.total_cash_win_paid_retail = IF(@channelType = 'retail', gcs.total_cash_win_paid_retail + winAmount, gcs.total_cash_win_paid_retail),
			gcs.total_cash_win_paid_self_service = IF(@channelType = 'self-service', gcs.total_cash_win_paid_self_service + winAmount, gcs.total_cash_win_paid_self_service),
			gcs.total_cash_win = gcs.total_cash_win_paid_retail + gcs.total_cash_win_paid_self_service,
			gcs.total_real_won = IF(@channelType NOT IN ('retail','self-service'),gcs.total_real_won+winAmount, gcs.total_wallet_real_won + gcs.total_cash_win),
			gcs.total_real_won_base=gcs.total_real_won_base+(winAmount/exchangeRate),


			gcsession.total_win=gcsession.total_win+winAmount,
			gcsession.total_win_base=gcsession.total_win_base+winAmount/exchangeRate,
     		gcsession.total_win_cash=gcsession.total_win_cash+winAmount,
			
			gcws.num_wins= gcws.num_wins+IF(winAmount>0, 1, 0),
			gcws.total_cash_won=gcws.total_cash_won+winAmount
			WHERE gcs.client_stat_id=clientStatID;  
		
		INSERT INTO gaming_game_plays
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_cash, timestamp, game_id, game_manufacturer_id,operator_game_id, client_id, client_stat_id, 
		 session_id, game_round_id, payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, license_type_id, pending_bet_real, pending_bet_bonus,  platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, sb_bet_id, sb_extra_id, pending_winning_real, payment_method_id)
		SELECT winAmount, winAmount/exchangeRate, exchangeRate,0,0,0,winAmount, NOW(), gameID, gameManufacturerID, operatorGameID, clientID, clientStatID, 
				sessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, current_real_balance,current_bonus_balance, current_bonus_win_locked_balance, currencyID, numTransactions+1, game_play_message_type_id, licenseTypeID , pending_bets_real, pending_bets_bonus, @platformTypeID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`), couponID, lotteryParticipationID,0, paymentMethodID
		FROM gaming_payment_transaction_type
		JOIN gaming_client_stats ON gaming_payment_transaction_type.name='Win' AND gaming_client_stats.client_stat_id=clientStatID
		JOIN gaming_game_play_message_types ON gaming_game_play_message_types.`name`=CAST(CASE licenseTypeID WHEN 6 THEN 'LotteryCashWin' WHEN 7 THEN 'SportsPoolCashWin' END AS CHAR(80));

		SET newGamePlayID=LAST_INSERT_ID();


  IF (ruleEngineEnabled) THEN
      IF NOT EXISTS (SELECT event_table_id FROM gaming_event_rows WHERE event_table_id=1 AND elem_id=newGamePlayID) THEN
		    INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, newGamePlayID
          ON DUPLICATE KEY UPDATE elem_id=VALUES(elem_id);
      END IF;
  END IF;
  
		UPDATE gaming_lottery_transactions SET game_play_id = newGamePlayID WHERE lottery_coupon_id = couponID and is_latest = 1;

		/* do it despite pending status  */
		UPDATE gaming_game_plays FORCE INDEX (game_round_id) SET is_win_placed=1 WHERE game_round_id=gameRoundID AND gaming_game_plays.is_win_placed=0;

		/* is show wins per participation (mostly for reports) */
		INSERT INTO gaming_game_plays_lottery_entries (game_play_id,lottery_draw_id, lottery_participation_id, amount_total, amount_cash,amount_real, amount_bonus, amount_bonus_win_locked, amount_ring_fenced, amount_free_bet, loyalty_points, loyalty_points_bonus,lottery_participation_prize_id)
		SELECT game_play_id, lotteryDrawID, lotteryParticipationID, amount_total,amount_cash,amount_real,amount_bonus, amount_bonus_win_locked, amount_ring_fenced, amount_free_bet, loyalty_points, loyalty_points_bonus, lotteryParticipationPrizeID
		FROM gaming_game_plays
		WHERE game_play_id = newGamePlayID;
		
		SET gamePlayLotteryEntryIDWin = LAST_INSERT_ID();
		
		SET @totalBetBonus = 0;

		INSERT INTO gaming_game_plays_win_counter_bets (game_play_win_counter_id, game_play_id, win_game_play_id)
		VALUES (gamePlayWinCounterID, gamePlayID, newGamePlayID);
		
		UPDATE gaming_game_rounds FORCE INDEX (PRIMARY)
		STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
		SET 
			win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+(winAmount/exchangeRate),5), win_cash=win_cash+winAmount, 
			win_bet_diffence_base=win_total_base-bet_total_base,		
			date_time_end= NOW(), is_round_finished= 1, num_transactions=num_transactions+1, 
			balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance
		WHERE gaming_game_rounds.game_round_id=gameRoundID;   
		
		UPDATE gaming_game_rounds FORCE INDEX (PRIMARY)
		STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
		SET 
			win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+(winAmount/exchangeRate),5), win_cash=win_cash+winAmount, win_bet_diffence_base=win_total_base-bet_total_base,
			date_time_end= NOW(), is_round_finished=1, num_transactions=num_transactions+1, 
			balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance
		WHERE gaming_game_rounds.game_round_id=gameRoundIDForParticipation;   

		IF (@isBonusSecured OR IsFreeBonus OR isFreeBonusPhase) THEN
			CALL BonusConvertWinningsAfterSecuredDate(newGamePlayID,gamePlayWinCounterID);
		END IF;
		

		IF (totalWinAmount > 0 AND notificationEnabled=1) THEN
			INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
			VALUES (CASE licenseTypeID WHEN 6 THEN 554 WHEN 7 THEN 565 END, couponID, lotteryParticipationID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
			
		END IF; 

		IF (isGift) THEN
			SELECT id INTO giftTypeId
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
	ELSE
		SET statusCode=10;
		LEAVE root;
		END IF;
	END LOOP;
 
	UPDATE gaming_lottery_coupons
    STRAIGHT_JOIN (
		SELECT COUNT(*) AS participationReserved
        FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
        STRAIGHT_JOIN gaming_lottery_participations ON 
			gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id AND 
            gaming_lottery_participations.lottery_wager_status_id IN (7, 10, 11)
        WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID 
    ) AS total_participations ON 1=1
    SET gaming_lottery_coupons.lottery_wager_status_id = 10
    WHERE lottery_coupon_id = couponID AND  participationReserved = gaming_lottery_coupons.num_participations;

	-- update Coupon Status
	SET newCouponStatus = PropagateCouponStatusFromParticipations(couponID, currentCouponStatus, 0);

	-- Update coupon amounts and status` and all win amounts
	UPDATE gaming_lottery_coupons
	SET lottery_coupon_status_id=newCouponStatus, win_gross_amount=totalGrossAmount, win_net_amount=totalNetAmount, win_tax_amount=totalTaxAmount, win_amount=totalWinAmount
	WHERE gaming_lottery_coupons.lottery_coupon_id=couponID;
	
    IF(currentCouponStatus = 2110) THEN 
		UPDATE gaming_lottery_blocked_coupons 
			SET user_id=-1, modified_date=NOW(), is_active=0
		WHERE lottery_coupon_id = couponID AND is_active = 1;
	END IF;

	IF(IFNULL(pendingWinGamePlayID,-1)<>-1) THEN
		UPDATE gaming_pending_winnings SET
			high_tier_winning_level_id=-1, -- System Provisional Paid with Cash Clasification
			amount=totalParticipationWinAmount,
			base_amount=totalParticipationWinAmount,
			currency_id=currencyID,
			pending_winning_status_id=5, -- Externally Approved
			payout_type_id=5, -- Cash
			date_updated=NOW()
		WHERE
			game_play_id = pendingWinGamePlayID;
    END IF;

	 CALL PlayReturnDataWithoutGameForSbExtraID(lotteryParticipationID, licenseTypeID, gameRoundIDForParticipation, clientStatID, gameManufacturerID, 0);
	 CALL PlayReturnBonusInfoOnWinForSbExtraID(lotteryParticipationID, licenseTypeID); 

	SET statusCode = 0;
END$$

DELIMITER ;

