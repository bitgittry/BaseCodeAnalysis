DROP procedure IF EXISTS `PlaceWinTypeTwo`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceWinTypeTwo`(
  gameRoundID BIGINT, sessionID BIGINT, gameSessionID BIGINT, winAmount DECIMAL(18, 5), clearBonusLost TINYINT(1), 
  transactionRef VARCHAR(80), closeRound TINYINT(1), isJackpotWin TINYINT(1), returnData TINYINT(1), 
  minimalData TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN
  
  -- Optimized
  -- Remove reference to gaming_bonus_free_rounds
  
  DECLARE a,winTotalBase, winReal, winBonus, winBonusWinLocked, roundBetTotal, roundWinTotal, bonusWgrReqWeight, betReal, betBonus, betBonusLost, 
	betTotal, betFromReal, roundWinTotalFull, amountTaxPlayer, amountTaxOperator, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, taxModificationOperator, 
    taxModificationPlayer, roundBetTotalReal, roundWinTotalReal, taxOnReturn, taxAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE betAmount, exchangeRate, freeRoundWinRemaining, freeRoundTotalAmountWon, freeRoundTransferTotal,bonusRetLostTotal, winRingFencedAmount, 
	winRingFencedAmountByLicenseType, totalWinRingFencedAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE gameRoundIDCheck, gameID, gameManufacturerID, operatorGameID, clientStatID, clientStatIDCheck, clientID, currencyID, gamePlayID, 
	prevWinGamePlayID, gamePlayExtraID, bonusFreeRoundID, bonusFreeRoundRuleID, gamePlayWinCounterID, bonusInstanceID BIGINT DEFAULT -1;
  DECLARE dateTimeWin DATETIME DEFAULT NULL;
  DECLARE bonusEnabledFlag, disableBonusMoney, bonusReedemAll,playLimitEnabled, isRoundFinished, remainingFundsCreateBonus, 
	IsFreeBonus ,isFreeBonusPhase, noMoreRecords, ruleEngineEnabled, onlyFeeBetPhase, addWagerContributionWithRealBet, 
    taxEnabled, loyaltyPointsEnabled, fingFencedEnabled, bonusRedeemThresholdEnabled TINYINT(1) DEFAULT 0;
  DECLARE numTransactions, numFreeRoundsRemaining, numBetsNotProcessed INT DEFAULT 0; 
  DECLARE licenseType, roundType, freeRoundAwardingType,retType, taxAppliedOnType VARCHAR(20) DEFAULT NULL;
  DECLARE clientWagerTypeID,bonusOrderUsed,numPlayBonusInstances INT DEFAULT -1;
  DECLARE licenseTypeID, platformTypeID,ringFencedEnabled TINYINT(4) DEFAULT 1;
  DECLARE currentBonusAmount, currentRealAmount, currentWinLockedAmount DECIMAL(18,5) DEFAULT 0; 
  DECLARE bonusesUsedAllWhenZero, playerHasActiveBonuses TINYINT(1) DEFAULT 0;
  DECLARE taxCycleID INT DEFAULT NULL;

  DECLARE redeemCursor CURSOR FOR 
    SELECT gbi.bonus_instance_id 
    FROM gaming_game_plays_win_counter_bets AS play_win_bets FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN gaming_game_plays_bonus_instances AS play_bonus_instances FORCE INDEX (game_play_id) ON
		play_win_bets.game_play_win_counter_id=gamePlayWinCounterID AND
		play_win_bets.game_play_id=play_bonus_instances.game_play_id 
    STRAIGHT_JOIN gaming_bonus_instances AS gbi ON play_bonus_instances.bonus_instance_id=gbi.bonus_instance_id AND gbi.open_rounds < 1     
	STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id=gbi.bonus_rule_id 
		AND gaming_bonus_rules.redeem_threshold_enabled = 1 
        AND gaming_bonus_rules.redeem_threshold_on_deposit = 0
    STRAIGHT_JOIN gaming_client_stats AS gcs ON gbi.client_stat_id=gcs.client_stat_id
    STRAIGHT_JOIN gaming_bonus_rules_wager_restrictions AS restrictions ON restrictions.bonus_rule_id=gbi.bonus_rule_id AND restrictions.currency_id=gcs.currency_id 
  WHERE restrictions.redeem_threshold >= (gbi.bonus_amount_remaining+gbi.current_win_locked_amount);
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;

  SET bonusWgrReqWeight=1.0;
  SET gamePlayIDReturned=NULL;
  
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, IFNULL(gs3.value_bool,0) AS bonusReedemAll, IFNULL(gs4.value_bool,0) AS fingFencedEnabled, 
		IFNULL(gs5.value_bool,0) AS ruleEngineEnabled, IFNULL(gs6.value_bool,0) AS bonusesUsedAllWhenZero,
		 IFNULL(gs7.value_bool,0) AS addWagerContributionWithRealBet, IFNULL(gs8.value_bool,0) AS taxOnGamePlayEnabled,
         IFNULL(gs9.value_bool,0) AS loyaltyPointsEnabled, IFNULL(gs10.value_bool,0) AS bonusRedeemThresholdEnabled
    INTO playLimitEnabled, bonusEnabledFlag, bonusReedemAll, fingFencedEnabled, ruleEngineEnabled, bonusesUsedAllWhenZero, 
			addWagerContributionWithRealBet, taxEnabled, loyaltyPointsEnabled, bonusRedeemThresholdEnabled
    FROM gaming_settings gs1 
    STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	LEFT JOIN gaming_settings gs3 ON (gs3.name='BONUS_REEDEM_ALL_BONUS_ON_REDEEM')
	LEFT JOIN gaming_settings gs4 ON (gs4.name='RING_FENCED_ENABLED')
	LEFT JOIN gaming_settings gs5 ON (gs5.name='RULE_ENGINE_ENABLED')
	LEFT JOIN gaming_settings gs6 ON (gs6.name='TYPE_TWO_BONUSES_USED_ALL_WHEN_ZERO')
	LEFT JOIN gaming_settings gs7 ON (gs7.name='ADD_WAGER_CONTRIBUTION_WITH_REAL_BET')
	LEFT JOIN gaming_settings gs8 ON (gs8.name='TAX_ON_GAMEPLAY_ENABLED')
	LEFT JOIN gaming_settings gs9 ON (gs9.name='LOYALTY_POINTS_WAGER_ENABLED')
	LEFT JOIN gaming_settings gs10 ON (gs10.name='BONUS_REEDEM_THRESHOLD_ENABLED')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
  SELECT game_round_id, game_id, game_manufacturer_id, operator_game_id, client_stat_id, client_id, num_transactions, bet_total, 
	win_total, is_round_finished, amount_tax_operator, amount_tax_player, bet_real, win_real
  INTO gameRoundIDCheck, gameID, gameManufacturerID, operatorGameID, clientStatID, clientID, numTransactions, roundBetTotal, 
	roundWinTotal, isRoundFinished, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal
  FROM gaming_game_rounds
  WHERE game_round_id=gameRoundID;
  
  SET closeRound=IF(isRoundFinished, 0, closeRound); 
  
  SELECT client_stat_id, client_id, gaming_client_stats.currency_id ,bet_from_real
  INTO clientStatIDCheck, clientID, currencyID, betFromReal
  FROM gaming_client_stats 
  WHERE client_stat_id=clientStatID
  FOR UPDATE;
  
  SELECT exchange_rate INTO exchangeRate
  FROM gaming_operator_currency 
  STRAIGHT_JOIN gaming_operators ON gaming_operator_currency.currency_id=currencyID AND 
    gaming_operators.is_main_operator AND gaming_operator_currency.operator_id=gaming_operators.operator_id;
  
  SELECT disable_bonus_money, gaming_license_type.name, gaming_license_type.license_type_id, gaming_games.client_wager_type_id, gaming_game_round_types.name AS round_type 
  INTO disableBonusMoney, licenseType, licenseTypeID, clientWagerTypeID, roundType
  FROM gaming_operator_games 
  STRAIGHT_JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id
  STRAIGHT_JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_games.license_type_id
  STRAIGHT_JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id=gameRoundID
  STRAIGHT_JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
  WHERE gaming_operator_games.operator_game_id=operatorGameID;
    
  IF (gameRoundIDCheck=-1 OR clientStatIDCheck=-1) THEN 
    SET statusCode = 1;
    LEAVE root;
  END IF;
  
  INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameRoundID);
  SET gamePlayWinCounterID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays_win_counter_bets (game_play_win_counter_id, game_play_id)
  SELECT DISTINCT gamePlayWinCounterID, game_play_id 
  FROM gaming_game_plays
  WHERE game_round_id=gameRoundID AND gaming_game_plays.is_win_placed=0;
  
  SET numBetsNotProcessed=ROW_COUNT();
  
  IF (numBetsNotProcessed=0) THEN
    
    SELECT game_play_id INTO prevWinGamePlayID
    FROM gaming_game_plays FORCE INDEX (game_round_id)
    STRAIGHT_JOIN gaming_payment_transaction_type AS transaction_type ON 
		game_round_id=gameRoundID AND 
		transaction_type.name IN ('Win') AND gaming_game_plays.payment_transaction_type_id=transaction_type.payment_transaction_type_id
    ORDER BY round_transaction_no DESC
    LIMIT 1;
  
    IF (prevWinGamePlayID!=-1) THEN
      
      
      INSERT INTO gaming_game_plays_win_counter_bets (game_play_win_counter_id, game_play_id)
      SELECT DISTINCT gamePlayWinCounterID, game_play_id
      FROM gaming_game_plays_win_counter_bets
      WHERE win_game_play_id=prevWinGamePlayID;
      
      SET numBetsNotProcessed=ROW_COUNT();
    END IF;
    
    IF (numBetsNotProcessed=0) THEN
      SET betTotal=0;
      
      
    END IF;
    
  END IF;
  
  
  SELECT COUNT(gaming_game_plays.game_play_id), SUM(amount_total), SUM(bonus_lost), SUM(amount_real), 
	SUM(amount_bonus+amount_bonus_win_locked), gaming_game_plays.extra_id, gaming_game_plays.platform_type_id
  INTO numBetsNotProcessed, betTotal, betBonusLost, betReal, betBonus, gamePlayExtraID, platformTypeID
  FROM gaming_game_plays_win_counter_bets AS win_counter_bets FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON 
	win_counter_bets.game_play_win_counter_id=gamePlayWinCounterID AND 
	gaming_game_plays.game_play_id=win_counter_bets.game_play_id;
 
 -- Get the Player channel
	CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, @platformTypeID, @platformType, @channelTypeID, @channelType);

  IF (numBetsNotProcessed=0) THEN
    SET betTotal=0;
      
      
  END IF;
 
  SET @winBonusLost=0;
  SET @winBonusWinLockedLost=0;
  SET numPlayBonusInstances=0;  
  SET @updateBonusInstancesWins=0;  
  
  IF (roundType='FreeRound') THEN
    
    SELECT bonus_free_round_id, gaming_bonus_rules.bonus_rule_id, bonus_wgr_req_weigth, 
		GREATEST(0, IFNULL(free_round_amount.max_win_total, 1000000)-gaming_bonus_free_rounds.bonus_transfered_total), 
        freeround_awarding_type.name AS freeround_awarding_type, remaining_funds_create_bonus, gaming_bonus_free_rounds.num_rounds_remaining
    INTO bonusFreeRoundID, bonusFreeRoundRuleID, bonusWgrReqWeight, freeRoundWinRemaining, freeRoundAwardingType, remainingFundsCreateBonus, numFreeRoundsRemaining
    FROM gaming_bonus_free_rounds
    JOIN gaming_bonus_rules ON gaming_bonus_free_rounds.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
    JOIN gaming_bonus_rules_free_rounds ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_free_rounds.bonus_rule_id
    JOIN gaming_bonus_rules_wgr_req_weights AS weights ON gaming_bonus_rules.bonus_rule_id=weights.bonus_rule_id AND weights.operator_game_id=operatorGameID
    JOIN gaming_bonus_rules_free_rounds_amounts AS free_round_amount ON free_round_amount.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND free_round_amount.currency_id=currencyID
    JOIN gaming_bonus_types_freeround_awarding AS freeround_awarding_type ON gaming_bonus_rules_free_rounds.bonus_type_freeround_awarding_id=freeround_awarding_type.bonus_type_freeround_awarding_id
    WHERE bonus_free_round_id=gamePlayExtraID;
  
    SET bonusWgrReqWeight=1.0; 
    SET @winTransfer=0;
    IF (freeRoundAwardingType='Real') THEN
      SET winReal = winAmount*bonusWgrReqWeight;
      SET winReal = LEAST(freeRoundWinRemaining, winReal);
      SET @winTransfer = winReal;
      SET winBonus = 0; 
      SET @winBonusLost=winAmount-winReal;
    ELSEIF (freeRoundAwardingType='Bonus') THEN
      SET winReal = 0;
      SET winBonus = winAmount*bonusWgrReqWeight;
      SET @winTransfer= LEAST(freeRoundWinRemaining, winBonus);
      SET @winBonusLost=0;
    END IF;
    
    SET winBonusWinLocked = 0;
  
    UPDATE gaming_bonus_free_rounds
    SET total_amount_won=total_amount_won+(winAmount*bonusWgrReqWeight), bonus_transfered_total=bonus_transfered_total+@winTransfer
    WHERE bonus_free_round_id=bonusFreeRoundID;
    
    IF (winReal > 0) THEN
      INSERT INTO gaming_bonus_free_round_transfers (bonus_rule_id, bonus_transfered)
      VALUES (bonusFreeRoundRuleID, winReal);
    END IF;
    
  ELSEIF (roundType='Normal' AND bonusEnabledFlag) THEN 
    
    
    SET winBonus = 0; 
    SET winBonusWinLocked = 0; 
    SET winReal = winAmount; 
    
    SELECT COUNT(*),MAX(bonus_order),SUM(bet_bonus),MIN(is_freebet_phase) 
    INTO numPlayBonusInstances,bonusOrderUsed,bonusRetLostTotal,onlyFeeBetPhase
    FROM gaming_game_plays_win_counter_bets AS play_win_bets FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN gaming_game_plays_bonus_instances FORCE INDEX (game_play_id) ON 
      play_win_bets.game_play_win_counter_id=gamePlayWinCounterID AND
      play_win_bets.game_play_id=gaming_game_plays_bonus_instances.game_play_id
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_game_plays_bonus_instances.bonus_instance_id = gaming_bonus_instances.bonus_instance_id;

    SELECT bet_returns_type.name,gaming_bonus_rules.is_free_bonus,gaming_bonus_instances.is_freebet_phase INTO retType,IsFreeBonus,isFreeBonusPhase
    FROM gaming_game_plays_win_counter_bets AS play_win_bets FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN gaming_game_plays_bonus_instances FORCE INDEX (game_play_id) ON 
      play_win_bets.game_play_win_counter_id=gamePlayWinCounterID AND
      play_win_bets.game_play_id=gaming_game_plays_bonus_instances.game_play_id
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_game_plays_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
	STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_types_bet_returns AS bet_returns_type ON gaming_bonus_rules.bonus_type_bet_return_id=bet_returns_type.bonus_type_bet_return_id
	WHERE gaming_game_plays_bonus_instances.bonus_order=1
    LIMIT 1;
    
    IF (numPlayBonusInstances>0) THEN
	  IF (retType = 'Loss' ) THEN
		SET @winAmountTemp = winAmount - bonusRetLostTotal;
		IF (@winAmountTemp<0) THEN
			SET @winAmountTemp = 0;
		END IF;
	  ELSE
		SET @winAmountTemp = winAmount;
	  END IF;
	 
	  SET @ReduceFromReal = 0;
  
      SET @winBonusTemp=0;
      
      SET @winBonusCurrent=0;
      SET @winBonus=0;
	  SET @winReal=0;
      SET @winBonusWinLocked=0;
		
      SET @winRingFencedAmount=0;
	  SET @totalWinRingFencedAmount=0;
	  SET @totalWinRingFencedAmountByLicenseType=0;
      
      SET @winBonusLostCurrent=0;
      SET @winBonusWinLockedLostCurrent=0;
      SET @winBonusLost=0;
      SET @winBonusWinLockedLost=0;
      SET @winRealBonusCurrent=0;
      SET @winRealBonusWLCurrent=0;
	  SET @NegateFromBetFromReal=0;
      
      SET @isBonusSecured=0;
	  SET @mainBonusLost =0;
	  
      
      INSERT INTO gaming_game_plays_bonus_instances_wins (game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, timestamp, exchange_rate, win_real, win_ring_fenced, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution)
      SELECT gamePlayWinCounterID, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, NOW(), exchangeRate, 
		win_real,win_ring_fenced, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, clientStatID, NULL, add_wager_contribution
      FROM
      (
        SELECT 
          game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id,
          
          @isBonusSecured:=IF(is_secured, 1, @isBonusSecured),	
		  
		  @winBonusTemp := IF((ring_fence_only = 1),  
							@winBonusTemp,
								ROUND(
										IF(@winAmountTemp>0,
												IF(@winAmountTemp <  IF (is_freebet_phase OR IsFreeBonus, bonus_amount_given-bonus_amount_remaining,GREATEST(0,(bonus_amount_given-bonus_transfered_total-bonus_amount_remaining))),
														@winAmountTemp,
														IF (is_freebet_phase, bonus_amount_given-bonus_amount_remaining,GREATEST(0,(bonus_amount_given-bonus_transfered_total-bonus_amount_remaining)))
												   )
												,0
											),
									0)
								),
		  @winBonusCurrent := IF ((  ring_fence_only = 1), 
										0,
										@winBonusTemp
							     ) AS win_bonus,
		  @winRealBonusCurrent := IF ( is_secured=1  AND IsFreeBonus=0 AND is_freebet_phase=0, 
											@winBonusTemp,
											@winRealBonusCurrent
										),
		  
		  @winAmountTemp:=  IF(@winAmountTemp>0  AND is_lost = 0,
								IF(@winAmountTemp < @winBonusCurrent,
										0,
										@winAmountTemp - @winBonusCurrent
								   )
								 ,@winAmountTemp
							   ) ,
		  
		  @ReduceFromReal :=  IF(bonus_order=1 AND @winAmountTemp>0,
										IF (IsFreeBonus OR  is_freebet_phase OR ring_fence_only = 1,
											IF(ring_fence_only,GREATEST(@winAmountTemp-(ring_fenced_amount_given-current_ring_fenced_amount),0),@winAmountTemp),
											IF(@winAmountTemp < IF(is_lost=1,IFNULL(bet_from_real,0),betFromReal),
														@winAmountTemp,
														IF(is_lost=1,IFNULL(bet_from_real,0),betFromReal)
											)
									 	),
										0
								),
			
		  @winAmountTemp:= IF(bonus_order=1 AND @winAmountTemp>0,
									@winAmountTemp-@ReduceFromReal,
									@winAmountTemp
							),

		  @winRingFencedAmount:= IF(ringFencedEnabled AND is_secured=0 AND is_lost = 0,
										IF(@winAmountTemp>ring_fenced_amount_given-current_ring_fenced_amount,
											ring_fenced_amount_given-current_ring_fenced_amount,	
											@winAmountTemp
										),
									0
								) AS win_ring_fenced,
					  @winAmountTemp:= @winAmountTemp-@winRingFencedAmount,

		  @winRingFencedAmountLost:= IF(ringFencedEnabled AND is_lost = 1,
										IF(@winAmountTemp>ring_fenced_amount_given-current_ring_fenced_amount,
											ring_fenced_amount_given-current_ring_fenced_amount,	
											@winAmountTemp
										),
									0
								) AS win_ring_fenced_lost,
		  @winAmountTemp:= @winAmountTemp-@winRingFencedAmountLost,

		  

		  @winRealBonusWLCurrent := IF(bonus_order=1  AND is_lost = 0,
											@winAmountTemp,
											0
									   ) AS win_bonus_win_locked,
			
		
		  @winAmountTemp:= IF(bonus_order=1  AND is_lost = 0,
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
          @winRealBonusCurrent:=IF((is_secured=1 ) , 
				(CASE name
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
       
          @winBonus:=@winBonus+@winBonusCurrent,
          @winBonusWinLocked:=@winBonusWinLocked+@winRealBonusWLCurrent,
		  @winBonusLost:=@winBonusLost+@winBonusLostCurrent,
          @winBonusWinLockedLost:=@winBonusWinLockedLost+@winBonusWinLockedLostCurrent,
		  @winReal := @winReal + @ReduceFromReal +  @winRingFencedAmountLost,
		  @totalWinRingFencedAmount := @totalWinRingFencedAmount + IF(ring_fenced_by_bonus_rules, @winRingFencedAmount, 0),
		  @totalWinRingFencedAmountByLicenseType := @totalWinRingFencedAmountByLicenseType +  IF(ring_fenced_by_license_type, @winRingFencedAmount, 0),
		CASE addWagerContributionWithRealBet
			WHEN 1 THEN		 
				IF (is_secured OR max_bet_add_win_contr IS NULL,
					0, 
					ROUND(
						(
							GREATEST(0, (bet_bonus+bet_bonus_win_locked+bet_real+bet_ring_fenced)-max_bet_add_win_contr)
							/(bet_bonus+bet_bonus_win_locked+bet_real+bet_ring_fenced)
						)
				*(@winBonusCurrent+@winRealBonusWLCurrent+@totalWinRingFencedAmountByLicenseType+@totalWinRingFencedAmount+
					((IFNULL(winAmount,0)-(@winBonusCurrent+@winRealBonusWLCurrent+@totalWinRingFencedAmountByLicenseType+@totalWinRingFencedAmount))*IFNULL((bet_real/betReal), 1)))*over_max_bet_win_contr_multiplier, 0))
			ELSE
				IF (is_secured OR max_bet_add_win_contr IS NULL,
					0, 
					ROUND(
						(
							GREATEST(0, (bet_bonus+bet_bonus_win_locked)-max_bet_add_win_contr)
							/(bet_bonus+bet_bonus_win_locked)
						)
				*(@winBonusCurrent+@winRealBonusWLCurrent)*over_max_bet_win_contr_multiplier, 0))
			END AS add_wager_contribution,
				
          bonus_amount_remaining, current_win_locked_amount
        FROM(
			SELECT 
				gaming_bonus_instances.bonus_amount_remaining,
				gaming_bonus_instances.current_win_locked_amount,
				gaming_bonus_instances.ring_fenced_amount_given,
				gaming_bonus_instances.current_ring_fenced_amount,
				gaming_bonus_rules.over_max_bet_win_contr_multiplier,
				SUM(bet_bonus_win_locked) AS bet_bonus_win_locked,
				gaming_bonus_instances.is_secured,
				gaming_bonus_instances.bonus_amount_given,
				gaming_bonus_instances.bonus_transfered_total,
				SUM(bet_bonus) AS bet_bonus,
				gaming_bonus_instances.is_lost || gaming_bonus_instances.is_used_all AS is_lost,
				bonus_order,
				gaming_bonus_rules.transfer_upto_percentage,
				transfer_type.name,
				max_bet_add_win_contr,
				game_play_bonus_instance_id,
				gaming_bonus_instances.bonus_instance_id,
				gaming_bonus_instances.bonus_rule_id,
				gaming_bonus_instances.bet_from_real,
				gaming_bonus_rules.is_free_bonus,
				gaming_bonus_instances.is_freebet_phase,
				ring_fenced_by_bonus_rules,
				ring_fenced_by_license_type,
				ring_fence_only,
				play_bonus_instances.bet_real,
				SUM(bet_ring_fenced) AS bet_ring_fenced
			FROM gaming_game_plays_win_counter_bets AS play_win_bets FORCE INDEX (PRIMARY)
			STRAIGHT_JOIN gaming_game_plays_bonus_instances AS play_bonus_instances FORCE INDEX (game_play_id) ON 
				play_win_bets.game_play_win_counter_id = gamePlayWinCounterID
				AND play_win_bets.game_play_id = play_bonus_instances.game_play_id
			STRAIGHT_JOIN gaming_bonus_instances ON play_bonus_instances.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
			STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
			STRAIGHT_JOIN gaming_bonus_types_bet_returns AS bet_returns_type ON gaming_bonus_rules.bonus_type_bet_return_id = bet_returns_type.bonus_type_bet_return_id
			STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id = transfer_type.bonus_type_transfer_id
			LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
			LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON gaming_bonus_rules.bonus_rule_id = wager_restrictions.bonus_rule_id
				AND wager_restrictions.currency_id = currencyID
	 		GROUP BY gaming_bonus_instances.bonus_instance_id
			ORDER BY is_freebet_phase DESC, gaming_bonus_instances.given_date DESC, gaming_bonus_instances.bonus_instance_id DESC) AS gg
      ) AS XX
      ON DUPLICATE KEY UPDATE bonus_instance_id=VALUES(bonus_instance_id), win_real=VALUES(win_real), win_bonus=VALUES(win_bonus), win_bonus_win_locked=VALUES(win_bonus_win_locked), lost_win_bonus=VALUES(lost_win_bonus), lost_win_bonus_win_locked=VALUES(lost_win_bonus_win_locked), client_stat_id=VALUES(client_stat_id);
            
      
      UPDATE gaming_game_plays_bonus_instances_wins AS PIU FORCE INDEX (PRIMARY)
      STRAIGHT_JOIN gaming_game_plays_bonus_instances AS pbi_update FORCE INDEX (PRIMARY) ON 
		PIU.game_play_win_counter_id=gamePlayWinCounterID AND 
        pbi_update.game_play_bonus_instance_id=PIU.game_play_bonus_instance_id 
      STRAIGHT_JOIN gaming_bonus_instances ON pbi_update.bonus_instance_id=gaming_bonus_instances.bonus_instance_id AND PIU.game_play_bonus_instance_id=pbi_update.game_play_bonus_instance_id 
      SET
        pbi_update.win_bonus=IFNULL(pbi_update.win_bonus,0)+PIU.win_bonus - PIU.lost_win_bonus, 
        pbi_update.win_bonus_win_locked=IFNULL(pbi_update.win_bonus_win_locked,0)+PIU.win_bonus_win_locked - PIU.lost_win_bonus_win_locked, 
        pbi_update.win_real=  IFNULL(pbi_update.win_real,0)+PIU.win_real,
		pbi_update.win_ring_fenced = IFNULL(pbi_update.win_ring_fenced,0)+PIU.win_ring_fenced,
        pbi_update.lost_win_bonus=IFNULL(pbi_update.lost_win_bonus,0)+PIU.lost_win_bonus,
        pbi_update.lost_win_bonus_win_locked=IFNULL(pbi_update.lost_win_bonus_win_locked,0)+PIU.lost_win_bonus_win_locked,
        
        pbi_update.now_used_all=IF(is_free_rounds_mode = 0 AND ROUND(gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount+PIU.win_bonus+PIU.win_bonus_win_locked,5)=0, 1, 0), 
        pbi_update.add_wager_contribution=IFNULL(pbi_update.add_wager_contribution, 0)+PIU.add_wager_contribution;
     
      
      SET winBonus=IFNULL(@winBonus,0)-IFNULL(@winBonusLost,0);
      SET winBonusWinLocked=IFNULL(@winBonusWinLocked,0)-IFNULL(@winBonusWinLockedLost,0);      
      SET winReal=IFNULL(@winReal ,0);
	  SET winRingFencedAmount=IFNULL(@totalWinRingFencedAmount,0);  
	  SET winRingFencedAmountByLicenseType=IFNULL(@totalWinRingFencedAmountByLicenseType,0); 
	  SET totalWinRingFencedAmount = winRingFencedAmountByLicenseType + winRingFencedAmount;
      
      UPDATE 
      (
        SELECT play_bonus.bonus_instance_id, SUM(play_bonus_wins.win_real) AS win_real, SUM(play_bonus_wins.win_bonus-play_bonus_wins.lost_win_bonus) AS win_bonus, SUM(play_bonus_wins.win_ring_fenced) AS win_ring_fenced, 
          SUM(play_bonus_wins.win_bonus_win_locked-play_bonus_wins.lost_win_bonus_win_locked) AS win_bonus_win_locked, SUM(IFNULL(play_bonus_wins.add_wager_contribution, 0)) AS add_wager_contribution, MIN(play_bonus.now_used_all) AS now_used_all
        FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins
        STRAIGHT_JOIN gaming_game_plays_bonus_instances AS play_bonus ON play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND 
			play_bonus_wins.game_play_bonus_instance_id=play_bonus.game_play_bonus_instance_id 
        GROUP BY play_bonus.bonus_instance_id
      ) AS PB 
      STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=PB.bonus_instance_id  
	  STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
       
      SET 
        bonus_amount_remaining=bonus_amount_remaining+IFNULL(PB.win_bonus,0),
        current_win_locked_amount=current_win_locked_amount+IFNULL(PB.win_bonus_win_locked,0),
        total_amount_won=total_amount_won+(IFNULL(PB.win_bonus,0)+IFNULL(PB.win_bonus_win_locked,0)),
        bonus_transfered_total=bonus_transfered_total+IFNULL(PB.win_real,0),
		current_ring_fenced_amount=current_ring_fenced_amount+IFNULL(PB.win_ring_fenced,0),
        
        bonus_wager_requirement=IF(gaming_bonus_instances.is_active, bonus_wager_requirement+add_wager_contribution, bonus_wager_requirement),
        bonus_wager_requirement_remain=IF(gaming_bonus_instances.is_active, bonus_wager_requirement_remain+add_wager_contribution, bonus_wager_requirement_remain),
        
        gaming_bonus_instances.open_rounds=IF(closeRound, gaming_bonus_instances.open_rounds-closeRound, gaming_bonus_instances.open_rounds),
        
        gaming_bonus_instances.is_used_all=IF(PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-closeRound)<=0 AND (is_free_bonus OR is_freebet_phase), 1, gaming_bonus_instances.is_used_all),
        gaming_bonus_instances.used_all_date=IF(PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-closeRound)<=0 AND used_all_date IS NULL AND (is_free_bonus OR is_freebet_phase), NOW(), used_all_date),
        
        gaming_bonus_instances.is_active=IF(gaming_bonus_instances.is_active=1 AND PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-1)<=0 AND (is_free_bonus OR is_freebet_phase), 0, gaming_bonus_instances.is_active);

		IF (@winBonusLost+@winBonusWinLockedLost>0) THEN
        
			INSERT INTO gaming_bonus_losts (bonus_instance_id, client_stat_id, bonus_lost_type_id, bonus_amount, bonus_win_locked_amount, extra_id, date_time_lost, session_id)
			SELECT bonus_instance_id, client_stat_id, gaming_bonus_lost_types.bonus_lost_type_id, IFNULL(SUM(lost_win_bonus),0), IFNULL(SUM(lost_win_bonus_win_locked),0), gamePlayWinCounterID, NOW(), sessionID
			FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins  
			STRAIGHT_JOIN gaming_bonus_lost_types ON 
			   play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND
			  (play_bonus_wins.lost_win_bonus!=0 OR play_bonus_wins.lost_win_bonus_win_locked!=0) 
			WHERE gaming_bonus_lost_types.name='WinAfterLost'
			GROUP BY play_bonus_wins.bonus_instance_id;  
		END IF;

		SET @winBonusLostFromPrevious=IFNULL(ROUND(((betBonusLost)/betTotal)*winAmount,5), 0);        
		SET winReal=winReal-@winBonusLostFromPrevious;  
		SET @updateBonusInstancesWins=1;
    ELSE 
		SET winReal = winAmount;
		SET winBonus = 0;  
		SET winBonusWinLocked = 0; 
      
    END IF; 

  ELSE 
  
	SET winBonus = 0; 
    SET winBonusWinLocked = 0; 
    SET winReal = winAmount;
    
  END IF;  

  SET winReal=IF(winReal<0, 0, winReal);
   
  SET winTotalBase=ROUND(winAmount/exchangeRate,5);

  -- TAX
  IF(taxEnabled AND (closeRound OR isRoundFinished)) THEN
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

			-- if we update here, at that time to close tax cyle we just change tax cycle to inactive. 
			-- if we don't update here we can transfer the value in gaming_client_stats.deferred_tax to the active tax cycle
			UPDATE gaming_tax_cycles 
			SET cycle_bet_amount_real = cycle_bet_amount_real + betReal, cycle_win_amount_real = cycle_win_amount_real + roundWinTotalFull
			WHERE tax_cycle_id = taxCycleID;

			INSERT INTO gaming_tax_cycle_game_sessions
			(game_session_id, tax_cycle_id,  deferred_tax, win_real, bet_real, win_adjustment, bet_adjustment, deferred_tax_base, win_real_base, bet_real_base, win_adjustment_base, bet_adjustment_base)
			VALUES
			(gameSessionID, taxCycleID,	taxAmount, roundWinTotalFull, betReal, 0, 0, ROUND(taxAmount/exchangeRate,5), ROUND(roundWinTotalFull/exchangeRate,5), ROUND(betReal/exchangeRate,5), 0, 0)
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

  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_game_sessions AS ggs ON ggs.game_session_id=gameSessionID
  LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID   
  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET 
	gcs.total_wallet_real_won_online = IF(@channelType = 'online', gcs.total_wallet_real_won_online + winReal + totalWinRingFencedAmount, gcs.total_wallet_real_won_online),
	gcs.total_wallet_real_won_retail = IF(@channelType = 'retail' , gcs.total_wallet_real_won_retail + winReal + totalWinRingFencedAmount, gcs.total_wallet_real_won_retail),
	gcs.total_wallet_real_won_self_service = IF(@channelType = 'self-service', gcs.total_wallet_real_won_self_service + winReal + totalWinRingFencedAmount, gcs.total_wallet_real_won_self_service),
	gcs.total_wallet_real_won = gcs.total_wallet_real_won_online + gcs.total_wallet_real_won_retail + gcs.total_wallet_real_won_self_service,
    gcs.total_real_won= IF(@channelType NOT IN ('online','retail','self-service'),gcs.total_real_won+winReal+totalWinRingFencedAmount, gcs.total_wallet_real_won + gcs.total_cash_win),

	gcs.current_real_balance=gcs.current_real_balance+winReal+totalWinRingFencedAmount - taxOnReturn, 
    gcs.total_bonus_won=gcs.total_bonus_won+winBonus, gcs.current_bonus_balance=gcs.current_bonus_balance+IF(roundType='FreeRound', 0, winBonus), 
    gcs.total_bonus_win_locked_won=gcs.total_bonus_win_locked_won+winBonusWinLocked, gcs.current_bonus_win_locked_balance=current_bonus_win_locked_balance+IF(roundType='FreeRound', 0, winBonusWinLocked), 
    gcs.total_real_won_base=gcs.total_real_won_base+((winReal+IFNULL(totalWinRingFencedAmount,0))/exchangeRate), gcs.total_bonus_won_base=gcs.total_bonus_won_base+((winBonus+winBonusWinLocked)/exchangeRate),
    gcs.current_bonus_lost=IF(clearBonusLost=1,0,ROUND(@winBonusLost+@winBonusWinLockedLost+@winBonusLostFromPrevious,0)),
	gcs.current_ring_fenced_amount = gcs.current_ring_fenced_amount + winRingFencedAmount , gcs.current_ring_fenced_casino = IF(licenseTypeID=1,gcs.current_ring_fenced_casino+winRingFencedAmountByLicenseType,gcs.current_ring_fenced_casino), gcs.current_ring_fenced_poker = IF(licenseTypeID=2,gcs.current_ring_fenced_poker+winRingFencedAmountByLicenseType,gcs.current_ring_fenced_poker),
    
    ggs.total_win=ggs.total_win+winAmount, ggs.total_win_base=ggs.total_win_base+winTotalBase, ggs.total_bet_placed=ggs.total_bet_placed+betTotal, ggs.total_win_real=ggs.total_win_real+winReal+totalWinRingFencedAmount, ggs.total_win_bonus=ggs.total_win_bonus+winBonus+winBonusWinLocked,
    
    gcsession.total_win=gcsession.total_win+winAmount, gcsession.total_win_base=gcsession.total_win_base+winTotalBase, gcsession.total_bet_placed=gcsession.total_bet_placed+betTotal, gcsession.total_win_real=gcsession.total_win_real+winReal+totalWinRingFencedAmount, gcsession.total_win_bonus=gcsession.total_win_bonus+winBonus+winBonusWinLocked,
    
    gcws.num_wins=gcws.num_wins+IF(winAmount>0, 1, 0), gcws.total_real_won=gcws.total_real_won+winReal+totalWinRingFencedAmount, gcws.total_bonus_won=gcws.total_bonus_won+winBonus+winBonusWinLocked,
	gcs.bet_from_real = IF(gcs.bet_from_real- winReal + IFNULL(@NegateFromBetFromReal,0)<0,0,gcs.bet_from_real- winReal + IFNULL(@NegateFromBetFromReal,0)),
	gcs.total_tax_paid = gcs.total_tax_paid + taxOnReturn, -- add to tax paid if is onReturn only! If is deferred When we close tax cycle we update this
	gcs.deferred_tax = @cumulativeDeferredTax := (gcs.deferred_tax + IF(taxAppliedOnType ='Deferred', taxAmount, 0)) -- cumulative deferred tax to later on (when we need to close tax cycle) transfer to the respective tax cycle 
  WHERE gcs.client_stat_id=clientStatID;  
  
  IF (closeRound OR isRoundFinished) THEN 
    SET roundWinTotal=roundWinTotal+winAmount;
    SET @messageType=IF(roundWinTotal<=roundBetTotal,'HandLoses','HandWins');
  ELSE
    SET @messageType='Win';
  END IF;

  IF (isJackpotWin) THEN
	SET @transactionType='PJWin';
	SET @messageType='PJWin';
  ELSE
	SET @transactionType='Win';
  END IF;
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real,amount_ring_fenced, amount_bonus, amount_bonus_win_locked, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, license_type_id, pending_bet_real, pending_bet_bonus, bet_from_real, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, amount_tax_operator, amount_tax_player, tax_cycle_id, cumulative_deferred_tax) 
  SELECT winAmount, winTotalBase, exchangeRate, winReal,totalWinRingFencedAmount, winBonus, winBonusWinLocked, @winBonusLost, ROUND(IFNULL(@winBonusWinLockedLost,0)+IFNULL(@winBonusLostFromPrevious,0),0), 0, NOW(), gameID, gameManufacturerID, operatorGameID, clientID, clientStatID, sessionID, gameSessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, current_real_balance, ROUND(current_bonus_balance+current_bonus_win_locked_balance,0), current_bonus_win_locked_balance, currencyID, numTransactions+1, game_play_message_type_id, licenseTypeID, pending_bets_real, pending_bets_bonus, gaming_client_stats.bet_from_real, platformTypeID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`), taxModificationOperator, taxAmount, taxCycleID, gaming_client_stats.deferred_tax  
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name=@transactionType AND gaming_client_stats.client_stat_id=clientStatID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=@messageType;
  
  SET gamePlayID=LAST_INSERT_ID();
  
  IF (fingFencedEnabled) THEN
	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);
  END IF;

  IF (select value_bool from gaming_settings where name='RULE_ENGINE_ENABLED')=1 AND (winAmount > 0) THEN
      INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, gamePlayID;
  END IF;

  /*
  IF (ruleEngineEnabled) THEN
	INSERT INTO gaming_event_rows (event_table_id, elem_id) 
	SELECT MAX(1) AS event_table_id, gamePlayID 
	FROM gaming_rules FORCE INDEX (is_active)
	STRAIGHT_JOIN gaming_rules_instances FORCE INDEX (client_stat_rule) ON gaming_rules.is_active AND
	(gaming_rules_instances.client_stat_id = clientStatID AND gaming_rules_instances.rule_id = gaming_rules.rule_id AND gaming_rules_instances.is_current AND gaming_rules_instances.is_achieved=0)
	STRAIGHT_JOIN gaming_rules_events ON gaming_rules_instances.rule_id = gaming_rules_events.rule_id
	STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id = gaming_events.event_id 
	STRAIGHT_JOIN gaming_event_types ON gaming_events.event_type_id = gaming_event_types.event_type_id
	WHERE gaming_event_types.name = 'Win'
	HAVING event_table_id IS NOT NULL;
  END IF;
  */
  
  IF (winAmount > 0 AND playLimitEnabled) THEN
    CALL PlayLimitsUpdateWithGame(sessionID, clientStatID, licenseType, winAmount, 0, gameID);
  END IF;
  
  UPDATE gaming_game_plays_win_counter_bets
  SET win_game_play_id=gamePlayID
  WHERE game_play_win_counter_id=gamePlayWinCounterID;
  
  IF (bonusEnabledFlag AND @updateBonusInstancesWins) THEN
    UPDATE gaming_game_plays_bonus_instances_wins
    SET win_game_play_id=gamePlayID
    WHERE game_play_win_counter_id=gamePlayWinCounterID;
  END IF;
  
  UPDATE gaming_game_plays FORCE INDEX (game_round_id)
  STRAIGHT_JOIN gaming_game_plays_win_counter_bets AS play_win_bets ON 
    play_win_bets.game_play_win_counter_id=gamePlayWinCounterID AND
    play_win_bets.game_play_id=gaming_game_plays.game_play_id
  SET is_win_placed=1, game_play_id_win=gamePlayID 
  WHERE game_round_id=gameRoundID AND gaming_game_plays.is_win_placed=0;
  
  UPDATE gaming_game_rounds
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET 
    win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+winTotalBase,5), win_real=win_real+winReal+totalWinRingFencedAmount, win_bonus=win_bonus+winBonus, 
    win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked, win_bet_diffence_base=win_total_base-bet_total_base,
    bonus_lost=bonus_lost+@winBonusLost, bonus_win_locked_lost=bonus_win_locked_lost+IFNULL(@winBonusWinLockedLost,0)+IFNULL(@winBonusLostFromPrevious,0), 
    date_time_end= IF (closeRound, NOW(), date_time_end), is_round_finished=IF (closeRound, 1, is_round_finished), num_transactions=num_transactions+1, 
    balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance, amount_tax_operator = amountTaxOperator, amount_tax_player = taxAmount, 
	jackpot_win=jackpot_win+IF(isJackpotWin, winAmount, 0),
	tax_cycle_id = taxCycleID,
	cumulative_deferred_tax = @cumulativeDeferredTax
  WHERE gaming_game_rounds.game_round_id=gameRoundID;   

   IF (@isBonusSecured OR IsFreeBonus  OR isFreeBonusPhase) THEN
 	CALL BonusConvertWinningsAfterSecuredDate(gamePlayID,gamePlayWinCounterID);
  END IF;

	IF (bonusesUsedAllWhenZero AND bonusEnabledFlag) THEN

		SELECT current_bonus_balance, current_real_balance, current_bonus_win_locked_balance
		INTO currentBonusAmount, currentRealAmount, currentWinLockedAmount
		FROM gaming_client_stats
		WHERE client_stat_id = ClientStatID;

		SELECT IF (COUNT(1) > 0, 1, 0) 
        INTO playerHasActiveBonuses 
        FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses) 
        WHERE client_stat_id = clientStatID AND is_active = 1;

	 	IF (currentBonusAmount = 0 AND currentRealAmount = 0 AND currentWinLockedAmount = 0 AND playerHasActiveBonuses) THEN 
	 		CALL BonusForfeitBonus(sessionID, clientStatID, 0, 0, 'IsUsedAll', 'TYPE_TWO_BONUSES_USED_ALL_WHEN_ZERO - Used All');
	 	END IF;

	END IF;

  IF (bonusRedeemThresholdEnabled) THEN
	  OPEN redeemCursor;
		allBonusLabel: LOOP
		  
		  SET noMoreRecords=0;
		  FETCH redeemCursor INTO bonusInstanceID;
		  IF (noMoreRecords) THEN
			LEAVE allBonusLabel;
		  END IF;
		  IF bonusReedemAll THEN
			CALL BonusRedeemAllBonus(bonusInstanceID, 0, 0, 'below threshold','RedeemBonus', gamePlayID);
		  ELSE
			CALL BonusRedeemBonus(bonusInstanceID, 0, 0, 'below threshold','RedeemBonus', gamePlayID);
		  END IF;

		END LOOP allBonusLabel;
	  CLOSE redeemCursor;
  END IF;
  
  IF (isJackpotWin) THEN
	  INSERT INTO `accounting_dc_notes` (dc_type, dc_note_type_id, timestamp, amount, amount_base, notes, date_created, user_id, client_stat_id, is_approved)
	  SELECT 'credit', dc_note_type_id, NOW(), winAmount, winTotalBase, 'Jackpot refund from manufacturer', NOW(), 0, clientStatID, 0
	  FROM accounting_dc_note_types WHERE note_type = 'JackpotRefund';
  END IF;

  IF (returnData) THEN
    CALL PlayReturnData(gamePlayID, gameRoundID, clientStatID , operatorGameID, minimalData);
  END IF;
  
  SET gamePlayIDReturned=gamePlayID;
  SET statusCode=0;


END$$

DELIMITER ;

