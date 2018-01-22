DROP procedure IF EXISTS `CommonWalletFinSoftWinAdjustmentDownByBetRef`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletFinSoftWinAdjustmentDownByBetRef`(clientStatID BIGINT, transactionRef VARCHAR(100), betRef VARCHAR(40), adjustAmount DECIMAL(18,5), canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  DECLARE gameManufacturerName VARCHAR(20) DEFAULT 'FinSoft';
  DECLARE gameManufacturerID BIGINT DEFAULT 7; 
  DECLARE clientWagerTypeID BIGINT DEFAULT 3;
  DECLARE sbBetWinID, gamePlayID,winGamePlayID, sbBetID, sbBetIDCheck, sbExtraID, clientStatIDCheck, gameRoundID, sessionID,clientID,currencyID,gamePlayMessageTypeID, countryID, countryTaxID, gameSessionID BIGINT DEFAULT -1; 
  DECLARE cancelAmount, cancelAmountBase, cancelReal,betTotal,winAmount,exchangeRate, taxBet, taxWin, roundBetTotal, roundWinTotal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal,  amountTaxPlayer, amountTaxOperator, taxModificationOperator, taxModificationPlayer, roundWinTotalFull, taxOnReturn, taxAmount  DECIMAL(18,5) DEFAULT 0;
  DECLARE amountTaxPlayerBonus, taxAlreadyChargedPlayerBonus, taxModificationPlayerBonus, roundWinBonusAlready, roundWinBonusWinLockedAlready, roundWinTotalFullBonus, taxModificationOperatorBonus, taxAlreadyChargedOperatorBonus, roundBetTotalBonus, amountTaxOperatorBonus, taxReduceBonus, taxReduceBonusWinLocked DECIMAL(18, 5) DEFAULT 0;
  DECLARE gamePlayIDReturned,gamePlayWinCounterID BIGINT DEFAULT NULL;
  DECLARE numTransactions INT DEFAULT 0;
  DECLARE liveBetType TINYINT(4) DEFAULT 2;
  DECLARE deviceType,licenseTypeID TINYINT(4) DEFAULT 1;
  DECLARE bonusEnabledFlag,playLimitEnabled, applyNetDeduction, winTaxPaidByOperator, taxEnabled, sportsTaxCountryEnabled TINYINT(1);
  DECLARE NumSingles INT DEFAULT 1;
  DECLARE taxAppliedOnType VARCHAR(20) DEFAULT NULL;
  DECLARE taxCycleID INT DEFAULT NULL;
  
  SET statusCode=0;
  SET adjustAmount = ABS(adjustAmount);
  SELECT client_id,client_stat_id,currency_id INTO clientID,clientStatID,currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  SELECT sb_bet_id, game_play_id,sb_extra_id INTO sbBetIDCheck, gamePlayIDReturned,sbExtraID FROM gaming_sb_bet_history WHERE transaction_ref=transactionRef AND sb_bet_transaction_type_id=7; 
  
  IF (sbBetIDCheck!=-1) THEN 
    SET statusCode=0;
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    CALL CommonWalletSBReturnTransactionData(gamePlayIDReturned, sbBetIDCheck, sbExtraID, 'Win', clientStatID); 
    LEAVE root;
  END IF;

	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, IFNULL(gs3.value_bool,0) AS vb3
    INTO playLimitEnabled, bonusEnabledFlag, taxEnabled
    FROM gaming_settings gs1 
    JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	LEFT JOIN gaming_settings gs3 ON (gs3.name='TAX_ON_GAMEPLAY_ENABLED')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
  
  SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_play_id_win, gaming_game_plays.game_round_id, gaming_game_plays.session_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, 
    gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions 
  INTO sbBetID, gamePlayID, winGamePlayID, gameRoundID, sessionID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions
  FROM gaming_sb_bet_singles 
  JOIN gaming_sb_bets ON gaming_sb_bet_singles.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_singles.sb_bet_id
    AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1
  JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_singles.sb_selection_id=gaming_game_plays.sb_extra_id AND 
    gaming_game_plays.game_play_message_type_id=8 AND gaming_game_plays.payment_transaction_type_id=12
  JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
  ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
    
  IF (gamePlayID=-1) THEN
    SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_play_id_win, gaming_game_plays.game_round_id, gaming_game_plays.session_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, 
      gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions,gaming_sb_bet_multiples.num_singles
    INTO sbBetID, gamePlayID, winGamePlayID, gameRoundID, sessionID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions,NumSingles
    FROM gaming_sb_bet_multiples 
    JOIN gaming_sb_bets ON gaming_sb_bet_multiples.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_multiples.sb_bet_id
      AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1 
    JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_multiples.sb_multiple_type_id=gaming_game_plays.sb_extra_id AND 
      gaming_game_plays.game_play_message_type_id=10 AND gaming_game_plays.payment_transaction_type_id=12
    JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
    ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
  END IF;
    

  IF (gamePlayID=-1 OR IFNULL(winGamePlayID,-1)=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SELECT SUM(amount_total),license_type_id,exchange_rate INTO winAmount,licenseTypeID,exchangeRate
  FROM gaming_game_plays WHERE game_round_id = gameRoundID AND payment_Transaction_type_id IN (46,13);
  SET cancelAmount = adjustAmount;

  IF (adjustAmount > winAmount) THEN
	SET statusCode=3;
    LEAVE root;
  END IF;
  IF (bonusEnabledFlag) THEN 
    
    SET cancelReal = adjustAmount;
    SET @cancelBonus = 0;
    SET @cancelBonusWinLocked = 0;
	SET @bonusTransfered = 0;
	SET @cancelFromRealWinLocked = 0;
	SET @cancelFromRealBonus = 0;
	SET @bonusLostWhenTransferedToReal = 0;
	SET @winBonusDeductTemp = 0;
	SET @winBonusLockedDeductTemp = 0;
	SET @failedCancels = 0;
    
    SET @numPlayBonusInstances=0;
    SELECT COUNT(*) INTO @numPlayBonusInstances
    FROM gaming_game_plays_bonus_instances_wins 
    WHERE win_game_play_id=winGamePlayID; 
    
    IF (@numPlayBonusInstances>0) THEN
		  
	  INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameRoundID);
	  SET gamePlayWinCounterID=LAST_INSERT_ID();

      
      INSERT INTO gaming_game_plays_bonus_instances_wins (game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, timestamp, exchange_rate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution)
      SELECT gamePlayWinCounterID, ggpbiw.game_play_bonus_instance_id, ggpbiw.bonus_instance_id, ggpbiw.bonus_rule_id, NOW(), exchange_rate, ROUND(SUM(win_real)/winAmount*adjustAmount*-1,0), IF(gbi.bonus_amount_remaining<SUM(win_bonus)/winAmount*adjustAmount,gbi.bonus_amount_remaining,ROUND(SUM(win_bonus)/winAmount*adjustAmount*-1,0)),
			IF(gbi.current_win_locked_amount<SUM(win_bonus_win_locked)/winAmount*adjustAmount,gbi.current_win_locked_amount,ROUND(SUM(win_bonus_win_locked)/winAmount*adjustAmount*-1,0)), ROUND(SUM(lost_win_bonus)/winAmount*adjustAmount*-1,0), ROUND(SUM(lost_win_bonus_win_locked)/winAmount*adjustAmount*-1,0), ggpbiw.client_stat_id, winGamePlayID, add_wager_contribution*-1
      FROM gaming_game_plays_bonus_instances_wins AS ggpbiw
	  JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id = ggpbiw.bonus_instance_id
	  WHERE ggpbiw.win_game_play_id=winGamePlayID
	  GROUP BY ggpbiw.bonus_instance_id;
				

      
		  UPDATE gaming_game_plays_bonus_instances
		  JOIN gaming_bonus_instances ON gaming_game_plays_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
		  SET
			gaming_game_plays_bonus_instances.win_bonus=IF(gaming_bonus_instances.is_active=1, win_bonus - (win_bonus/winAmount*adjustAmount), gaming_game_plays_bonus_instances.win_bonus), 
			gaming_game_plays_bonus_instances.win_bonus_win_locked=IF(gaming_bonus_instances.is_active=1, win_bonus_win_locked - (win_bonus_win_locked/winAmount*adjustAmount), gaming_game_plays_bonus_instances.win_bonus_win_locked), 
			gaming_game_plays_bonus_instances.win_real=win_real - (win_real/winAmount*adjustAmount),
			gaming_game_plays_bonus_instances.lost_win_bonus=IF(gaming_bonus_instances.is_active=1, lost_win_bonus - (lost_win_bonus/winAmount*adjustAmount), gaming_game_plays_bonus_instances.lost_win_bonus), 
			gaming_game_plays_bonus_instances.lost_win_bonus_win_locked=IF(gaming_bonus_instances.is_active=1, lost_win_bonus_win_locked - (lost_win_bonus_win_locked/winAmount*adjustAmount), gaming_game_plays_bonus_instances.lost_win_bonus_win_locked)
		  WHERE 
			gaming_game_plays_bonus_instances.game_play_id=gamePlayID;
			

		  UPDATE gaming_bonus_instances
		  JOIN 
		  (
				SELECT temp.bonus_instance_id, 
					@winBonusDeductTemp := IF(ROUND(win_bonus/winAmount * adjustAmount,0)>bonus_amount_remaining,bonus_amount_remaining,ROUND(win_bonus/winAmount * adjustAmount,0)),
					IF (is_secured=0 OR is_lost=0,@winBonusDeductTemp,0) AS win_bonus_deduct,
					@failedCancels := IF (is_secured=0 OR is_lost=0, IF(ROUND(win_bonus/winAmount * adjustAmount,0)>bonus_amount_remaining,@failedCancels + ROUND(win_bonus/winAmount * adjustAmount,0) - bonus_amount_remaining,@failedCancels),@failedCancels),
					@cancelFromRealBonus := IF (is_lost=0, @cancelFromRealBonus,@cancelFromRealBonus +  @winBonusDeductTemp),
					@cancelBonus := IF (is_lost=0, @cancelBonus +  @winBonusDeductTemp,@cancelBonus),
					@bonusLostWhenTransferedToReal := IF(is_secured=0,@bonusLostWhenTransferedToReal,ROUND(@bonusLostWhenTransferedToReal+(lost_win_bonus_win_locked+lost_win_bonus)/winAmount*adjustAmount,0)),
					@winBonusLockedDeductTemp :=   IF(ROUND(win_bonus_win_locked/winAmount * adjustAmount,0)>current_win_locked_amount,current_win_locked_amount,ROUND(win_bonus_win_locked/winAmount * adjustAmount,0)),
					IF (is_secured=0 OR is_lost=0,@winBonusLockedDeductTemp ,0) AS win_bonus_win_locked_deduct,
					@failedCancels := IF (is_secured=0 OR is_lost=0,  IF(ROUND(win_bonus_win_locked/winAmount * adjustAmount,0)>current_win_locked_amount,@failedCancels + ROUND(win_bonus_win_locked/winAmount * adjustAmount,0) -current_win_locked_amount,@failedCancels),@failedCancels),
					@cancelFromRealWinLocked := IF (is_lost=0, @cancelFromRealWinLocked,@cancelFromRealWinLocked +  @winBonusLockedDeductTemp),
					@cancelBonusWinLocked := IF (is_lost=0, @cancelBonusWinLocked + @winBonusLockedDeductTemp,@cancelBonusWinLocked),
					add_wager_contribution AS remove_from_wagering,
					ROUND(win_real/winAmount * adjustAmount,0) AS win_real
				FROM (
					SELECT SUM(win_bonus) AS win_bonus, SUM(win_real) AS win_real,is_secured,is_lost,SUM(lost_win_bonus_win_locked) AS lost_win_bonus_win_locked,SUM(lost_win_bonus) AS lost_win_bonus,
						SUM(win_bonus_win_locked) AS win_bonus_win_locked,SUM(add_wager_contribution) AS add_wager_contribution,ggpbiw.bonus_instance_id,
						current_win_locked_amount,bonus_amount_remaining
					FROM gaming_game_plays_bonus_instances_wins AS ggpbiw
					JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id = ggpbiw.bonus_instance_id
					WHERE ggpbiw.win_game_play_id=winGamePlayID AND game_play_win_counter_id != gamePlayWinCounterID
					GROUP BY gbi.bonus_instance_id
				) AS temp

		  ) AS PB ON gaming_bonus_instances.bonus_instance_id=PB.bonus_instance_id  
			SET 
			bonus_amount_remaining=bonus_amount_remaining-PB.win_bonus_deduct,
			current_win_locked_amount=current_win_locked_amount-PB.win_bonus_win_locked_deduct,
			total_amount_won=total_amount_won-PB.win_bonus_deduct-PB.win_bonus_win_locked_deduct,
			bonus_transfered_total=bonus_transfered_total-PB.win_real,
			
			bonus_wager_requirement=IF(gaming_bonus_instances.is_active, bonus_wager_requirement-(win_bonus_deduct+win_bonus_win_locked_deduct)/winAmount *remove_from_wagering,bonus_wager_requirement),
			bonus_wager_requirement_remain=IF(gaming_bonus_instances.is_active, bonus_wager_requirement_remain-(win_bonus_deduct+win_bonus_win_locked_deduct)/winAmount *remove_from_wagering, bonus_wager_requirement_remain);

 
	
		SET cancelReal =  cancelReal - @cancelBonus - @cancelBonusWinLocked - @cancelFromRealBonus-@cancelFromRealWinLocked - @bonusLostWhenTransferedToReal - @failedCancels;

	ELSE 
        SET cancelReal= adjustAmount;
		SET @cancelBonus = 0;
		SET @cancelBonusWinLocked = 0;
		SET @cancelBonusLost=0; SET @cancelBonusWinLockedLost=0;
    END IF; 
  
  ELSE 
    SET cancelReal= adjustAmount;
	SET @cancelBonus = 0;
    SET @cancelBonusWinLocked = 0;
    SET @cancelBonusLost=0; SET @cancelBonusWinLockedLost=0;
  END IF; 
  
  SET cancelAmountBase=ROUND(cancelAmount/exchangeRate,5);

-- TAX
  IF(closeRound || IsRoundFinished) THEN

	SET roundWinTotalFull = roundWinTotalReal + winReal;
  -- betTotal is the sum of gaming_games_plays.amount_total of the bets in this round not processed (is_win_place = 0)
  CALL TaxCalculateTax(licenseTypeID, clientStatID, clientID, roundWinTotalFull, betReal, taxAmount, taxAppliedOnType, taxCycleID);





  IF (taxAppliedOnType = 'OnReturn') THEN
		-- a) The tax should be stored in gaming_game_plays.amount_tax_player. 
		-- b) update gaming_client_stats -> current_real_balance
		-- c) update gaming_client_stats -> total_tax_paid

		SET taxOnReturn = taxAmount;

  ELSEIF (taxAppliedOnType = 'Deferred') THEN
		/*
		a) - Update gaming_tax_cycles -> deferred_tax_amount.
		b) - Update gaming_client_stats -> deferred_tax. 
		c) - insert gaming_game_plays -> tax_cycle_id (gaming_tax_cycles) to link to the respective tax cycle.
		d) - insert gaming_game_plays -> amount_tax_player The tax should be stored in the same column as non-deferred tax.

		Note: Looking just to gaming_game_plays we can differentiate if is OnReturn or Deferred, checking gaming_game_plays.tax_cycle_id
			  If it is filled its deferred tax otherwise its tax on Return.
		*/
		IF (ISNULL(taxCycleID)) THEN
			SET statusCode = 1;
			LEAVE root;
		END IF;
		
		UPDATE gaming_tax_cycles 
        SET cycle_bet_amount_real = cycle_bet_amount_real + betReal, cycle_win_amount_real = cycle_win_amount_real + roundWinTotalFull
        WHERE tax_cycle_id = taxCycleID;

		SELECT game_session_id INTO gameSessionID FROM gaming_game_sessions  where client_stat_id = clientStatID and session_id = sessionID and is_open= 1 limit 1;

		INSERT INTO gaming_tax_cycle_game_sessions
		(game_session_id, tax_cycle_id,  deferred_tax, win_real, bet_real, win_adjustment, bet_adjustment, deferred_tax_base, win_real_base, bet_real_base, win_adjustment_base, bet_adjustment_base)
		VALUES
		(gameSessionID, taxCycleID,	taxAmount, winReal, betReal, 0, 0, ROUND(taxAmount/exchangeRate,5), ROUND(winReal/exchangeRate,5), ROUND(betReal/exchangeRate,5), 0, 0)
		ON DUPLICATE KEY UPDATE 
		deferred_tax = deferred_tax + VALUES(deferred_tax),
		win_real = win_real + VALUES(win_real),
		bet_real = bet_real + VALUES(bet_real),
		win_adjustment = 0,
		bet_adjustment = 0,
		deferred_tax_base = deferred_tax_base + VALUES(deferred_tax_base),
		win_real_base = win_real_base + VALUES(win_real_base),
		bet_real_base = bet_real_base + VALUES(bet_real_base),
		win_adjustment_base = 0,
		bet_adjustment_base = 0;
		
  END IF;
  END IF;
 -- /TAX
    SET @cumulativeDeferredTax:=0;

   SET taxModificationOperator = amountTaxOperator - taxAlreadyChargedOperator;
  SET taxModificationPlayer = amountTaxPlayer - taxAlreadyChargedPlayer;

  
  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID   
  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET 
    gcs.total_real_won=gcs.total_real_won-cancelReal, gcs.current_real_balance=gcs.current_real_balance-cancelReal - taxOnReturn, 
    gcs.total_bonus_won=gcs.total_bonus_won-@cancelBonus, gcs.current_bonus_balance=gcs.current_bonus_balance-@cancelBonus, 
    gcs.total_bonus_win_locked_won=gcs.total_bonus_win_locked_won-@cancelBonusWinLocked, gcs.current_bonus_win_locked_balance=current_bonus_win_locked_balance-@cancelBonusWinLocked, 
    gcs.total_real_won_base=gcs.total_real_won_base-(cancelReal/exchangeRate), gcs.total_bonus_won_base=gcs.total_bonus_won_base-((@cancelBonus+@cancelBonusWinLocked)/exchangeRate), gcs.total_tax_paid = gcs.total_tax_paid + taxOnReturn,
    
    gcsession.total_win=gcsession.total_win-cancelAmount, gcsession.total_win_base=gcsession.total_win_base-cancelAmountBase, gcsession.total_win_real=gcsession.total_win_real-cancelReal, gcsession.total_win_bonus=gcsession.total_win_bonus-(@cancelBonus+@cancelBonusWinLocked),
    
    gcws.num_wins=gcws.num_wins-IF(cancelAmount>0, 1, 0), gcws.total_real_won=gcws.total_real_won-cancelReal, gcws.total_bonus_won=gcws.total_bonus_won-(@cancelBonus+@cancelBonusWinLocked),
	gcs.deferred_tax = @cumulativeDeferredTax := (gcs.deferred_tax + IF(taxAppliedOnType ='Deferred', taxAmount, 0)) -- cumulative deferred tax to later on (when we need to close tax cycle) transfer to the respective tax cycle 
  WHERE gcs.client_stat_id=clientStatID;  
    
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, game_round_id, payment_transaction_type_id, is_win_placed, is_processed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, gaming_game_plays.game_play_message_type_id, sb_extra_id, sb_bet_id, license_type_id, device_type,pending_bet_real, pending_bet_bonus, amount_tax_operator, amount_tax_player,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, tax_cycle_id, cumulative_deferred_tax) 
  SELECT (cancelReal + @cancelBonus + @cancelBonusWinLocked)*-1, (cancelReal + @cancelBonus + @cancelBonusWinLocked)/exchange_rate*-1, exchange_rate, cancelReal*-1, @cancelBonus*-1, @cancelBonusWinLocked*-1, amount_other*-1, @cancelFromRealBonus*-1, @cancelFromRealWinLocked*-1, 0, NOW(), gameManufacturerID, clientID, clientStatID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 1, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, currencyID, numTransactions+1, gaming_game_plays.game_play_message_type_id, sbExtraID, sbBetID, licenseTypeID, gaming_game_plays.device_type,pending_bets_real, pending_bets_bonus, taxModificationOperator, taxModificationPlayer,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`), taxCycleID, gaming_client_stats.deferred_tax 
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='WinAdjustment' AND gaming_client_stats.client_stat_id=clientStatID
  JOIN gaming_game_plays ON gaming_game_plays.game_play_id=winGamePlayID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.game_play_message_type_id=IF(gamePlayMessageTypeID=8,12,13);
  
  SET gamePlayIDReturned=LAST_INSERT_ID();

  CALL GameUpdateRingFencedBalances(clientStatID,gamePlayIDReturned);  
  
  
  INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units)
  SELECT gamePlayIDReturned, 13, (cancelReal + @cancelBonus + @cancelBonusWinLocked)/NumSingles*-1, (cancelReal + @cancelBonus + @cancelBonusWinLocked)/NumSingles/exchangeRate*-1, cancelReal/NumSingles*-1, cancelReal/NumSingles/exchangeRate*-1, (@cancelBonus+@cancelBonusWinLocked)/NumSingles*-1, (@cancelBonus+@cancelBonusWinLocked)/NumSingles/exchangeRate*-1, NOW(), exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, liveBetType, deviceType, 0
  FROM gaming_game_plays_sb
  WHERE game_play_id=gamePlayID
  GROUP BY sb_selection_id;

    
  
  IF (playLimitEnabled AND cancelAmount>0) THEN 
    CALL PlayLimitsUpdate(clientStatID, 'sportsbook', adjustAmount*-1, 0);
  END IF;
  
  
  
  UPDATE gaming_game_rounds AS ggr
  SET 
    ggr.win_total=win_total-(cancelReal + @cancelBonus + @cancelBonusWinLocked), win_total_base=ROUND(win_total_base-(cancelReal + @cancelBonus + @cancelBonusWinLocked)/exchangeRate,5), win_real=win_real-cancelReal, win_bonus=win_bonus-@cancelBonus, win_bonus_win_locked=win_bonus_win_locked-@cancelBonusWinLocked, win_bet_diffence_base=win_total_base-bet_total_base,
    ggr.num_transactions=ggr.num_transactions+1, ggr.amount_tax_operator = amountTaxOperator, ggr.amount_tax_player = taxAmount,
	tax_cycle_id = taxCycleID,
	cumulative_deferred_tax = @cumulativeDeferredTax
  WHERE game_round_id=gameRoundID;
  
	INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount, transaction_ref, game_play_id, sb_extra_id) 
    SELECT sbBetID, sb_bet_transaction_type_id, NOW(), adjustAmount*-1, transactionRef, gamePlayIDReturned, sbExtraID
    FROM gaming_sb_bet_transaction_types WHERE name='WinAdjustment';

  
  CALL CommonWalletSBReturnTransactionData(gamePlayIDReturned, sbBetID, sbExtraID, 'Win', clientStatID);
  
END root$$

DELIMITER ;

