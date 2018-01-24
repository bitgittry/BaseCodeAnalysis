DROP procedure IF EXISTS `PlaceWin`; 

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceWin`(
  gameRoundID BIGINT, sessionID BIGINT, gameSessionID BIGINT, winAmount DECIMAL(18, 5), 
  clearBonusLost TINYINT(1), transactionRef VARCHAR(80), closeRound TINYINT(1), isJackpotWin TINYINT(1), returnData TINYINT(1), 
  minimalData TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN

  -- PlayLimitUpdate - gameID
  -- jackpot flow
  
  -- Optimized
  -- Remove reference to gaming_bonus_free_rounds

  DECLARE winTotalBase, winReal, winBonus, winBonusWinLocked, roundBetTotal, roundWinTotal, bonusWgrReqWeight, betReal, betBonus, betBonusLost, 
    betTotal, amountTaxPlayer, amountTaxOperator, roundWinTotalFull, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, taxModificationOperator, 
    taxOnReturn, roundBetTotalReal, roundWinTotalReal, taxAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE betAmount, exchangeRate, freeRoundWinRemaining, freeRoundTotalAmountWon, freeRoundTransferTotal, freeRoundMaxWin,FreeBonusAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE gameRoundIDCheck, gameID, gameManufacturerID, operatorGameID, clientStatID, clientStatIDCheck, clientID, currencyID, gamePlayID, 
	prevWinGamePlayID, gamePlayExtraID, bonusFreeRoundID, bonusFreeRoundRuleID, gamePlayWinCounterID, bonusInstanceID, countryID BIGINT DEFAULT -1;
  DECLARE dateTimeWin DATETIME DEFAULT NULL;
  DECLARE bonusEnabledFlag, bonusReedemAll, disableBonusMoney, playLimitEnabled, isRoundFinished, remainingFundsCreateBonus, 
	noMoreRecords, applyNetDeduction, winTaxPaidByOperator, bonusRedeemThresholdEnabled, taxEnabled, usedFreeBonus, 
    ruleEngineEnabled, addWagerContributionWithRealBet, loyaltyPointsEnabled, fingFencedEnabled TINYINT(1) DEFAULT 0;
  DECLARE numTransactions, numFreeRoundsRemaining, numBetsNotProcessed, numPlayBonusInstances INT DEFAULT 0;
  DECLARE licenseType, roundType, freeRoundAwardingType, channelType, taxAppliedOnType VARCHAR(20) DEFAULT NULL;
  DECLARE clientWagerTypeID INT DEFAULT -1; 
  DECLARE licenseTypeID TINYINT(4) DEFAULT 1;
  DECLARE platformTypeID INT DEFAULT 0;
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
  
  SELECT gs1.value_bool AS vb1, gs2.value_bool AS vb2, IFNULL(gs3.value_bool,0) AS vb3, IFNULL(gs4.value_bool,0) AS vb4, 
	IFNULL(gs5.value_bool,0) AS bonusReedemAll, IFNULL(gs6.value_bool,0) AS ruleEngineEnabled, IFNULL(gs7.value_bool,0) AS addWagerContributionWithRealBet, 
    IFNULL(gs8.value_bool,0) AS loyaltyPointsEnabled, IFNULL(gs9.value_bool,0) AS fingFencedEnabled
  INTO playLimitEnabled, bonusEnabledFlag, bonusRedeemThresholdEnabled, taxEnabled, 
	bonusReedemAll, ruleEngineEnabled, addWagerContributionWithRealBet, loyaltyPointsEnabled, fingFencedEnabled
  FROM gaming_settings gs1 
  STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
  LEFT JOIN gaming_settings gs3 ON (gs3.name='BONUS_REEDEM_THRESHOLD_ENABLED')
  LEFT JOIN gaming_settings gs4 ON (gs4.name='TAX_ON_GAMEPLAY_ENABLED')
  LEFT JOIN gaming_settings gs5 ON (gs5.name='BONUS_REEDEM_ALL_BONUS_ON_REDEEM')
  LEFT JOIN gaming_settings gs6 ON (gs6.name='RULE_ENGINE_ENABLED')
  LEFT JOIN gaming_settings gs7 ON (gs7.name='ADD_WAGER_CONTRIBUTION_WITH_REAL_BET')
  LEFT JOIN gaming_settings gs8 ON (gs8.name='LOYALTY_POINTS_WAGER_ENABLED')
  LEFT JOIN gaming_settings gs9 ON (gs9.name='RING_FENCED_ENABLED')
  WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
  SELECT game_round_id, game_id, game_manufacturer_id, operator_game_id, client_stat_id, client_id, num_transactions, bet_total, 
	win_total, is_round_finished, amount_tax_operator, amount_tax_player, bet_real, win_real
  INTO gameRoundIDCheck, gameID, gameManufacturerID, operatorGameID, clientStatID, clientID, numTransactions, roundBetTotal, 
	roundWinTotal, isRoundFinished, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal
  FROM gaming_game_rounds
  WHERE game_round_id=gameRoundID;
  
  SET closeRound=IF(isRoundFinished, 0, closeRound); 
  
  SELECT client_stat_id, client_id, gaming_client_stats.currency_id 
  INTO clientStatIDCheck, clientID, currencyID
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
  FROM gaming_game_plays FORCE INDEX (game_round_id)
  WHERE game_round_id=gameRoundID AND gaming_game_plays.is_win_placed=0;
  
  SET numBetsNotProcessed=ROW_COUNT();
  
  IF (numBetsNotProcessed=0) THEN
    
    SELECT game_play_id INTO prevWinGamePlayID
    FROM gaming_game_plays FORCE INDEX (game_round_id)
    STRAIGHT_JOIN gaming_payment_transaction_type AS transaction_type ON 
		game_round_id=gameRoundID AND transaction_type.name IN ('Win') AND 
        gaming_game_plays.payment_transaction_type_id=transaction_type.payment_transaction_type_id
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
  
  SELECT COUNT(gaming_game_plays.game_play_id), SUM(amount_total), SUM(bonus_lost), SUM(amount_real), SUM(amount_bonus+amount_bonus_win_locked), 
	gaming_game_plays.extra_id, gaming_game_plays.platform_type_id 
  INTO numBetsNotProcessed, betTotal, betBonusLost, betReal, betBonus, gamePlayExtraID, platformTypeID
  FROM gaming_game_plays_win_counter_bets AS win_counter_bets
  STRAIGHT_JOIN gaming_game_plays ON 
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
    
    SELECT bonus_free_round_id, gaming_bonus_rules.bonus_rule_id, bonus_wgr_req_weigth, IFNULL(free_round_amount.max_win, 10000000000), 
      GREATEST(0, IFNULL(free_round_amount.max_win_total, 10000000000)-gaming_bonus_free_rounds.bonus_transfered_total), 
      freeround_awarding_type.name AS freeround_awarding_type, remaining_funds_create_bonus, gaming_bonus_free_rounds.num_rounds_remaining
    INTO bonusFreeRoundID, bonusFreeRoundRuleID, bonusWgrReqWeight, freeRoundMaxWin, freeRoundWinRemaining, freeRoundAwardingType, remainingFundsCreateBonus, numFreeRoundsRemaining
    FROM gaming_bonus_free_rounds
    STRAIGHT_JOIN gaming_bonus_rules ON 
		gaming_bonus_free_rounds.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
    STRAIGHT_JOIN gaming_bonus_rules_free_rounds ON 
		gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_free_rounds.bonus_rule_id
    STRAIGHT_JOIN gaming_bonus_rules_wgr_req_weights AS weights ON 
		gaming_bonus_rules.bonus_rule_id=weights.bonus_rule_id AND weights.operator_game_id=operatorGameID
    STRAIGHT_JOIN gaming_bonus_rules_free_rounds_amounts AS free_round_amount ON 
		free_round_amount.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND free_round_amount.currency_id=currencyID
    STRAIGHT_JOIN gaming_bonus_types_freeround_awarding AS freeround_awarding_type ON 
		gaming_bonus_rules_free_rounds.bonus_type_freeround_awarding_id=freeround_awarding_type.bonus_type_freeround_awarding_id
    WHERE gaming_bonus_free_rounds.bonus_free_round_id=gamePlayExtraID;
  
    SET bonusWgrReqWeight=1.0; 
    SET @winTransfer=0;
    IF (freeRoundAwardingType='Real') THEN
      SET winReal = winAmount*bonusWgrReqWeight;
      SET winReal = LEAST(freeRoundMaxWin, freeRoundWinRemaining, winReal);
      SET @winTransfer = winReal;
      SET winBonus = 0; 
      SET @winBonusLost=winAmount-winReal;
    ELSEIF (freeRoundAwardingType='Bonus') THEN
      SET winReal = 0;
      SET winBonus = winAmount*bonusWgrReqWeight;
      SET @winTransfer= LEAST(freeRoundMaxWin, freeRoundWinRemaining, winBonus);
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
    
  ELSEIF (roundType='Normal' AND bonusEnabledFlag AND betTotal>0) THEN 
    
    SET winBonus = 0; 
    SET winBonusWinLocked = 0; 
    SET winReal = winAmount; 
    
    SELECT COUNT(*), MAX(is_free_bonus) INTO numPlayBonusInstances, usedFreeBonus
    FROM gaming_game_plays_win_counter_bets AS play_win_bets FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN gaming_game_plays_bonus_instances ON 
      play_win_bets.game_play_win_counter_id=gamePlayWinCounterID AND
      play_win_bets.game_play_id=gaming_game_plays_bonus_instances.game_play_id
	STRAIGHT_JOIN gaming_bonus_instances gbi ON gbi.bonus_instance_id = gaming_game_plays_bonus_instances.bonus_instance_id
	STRAIGHT_JOIN gaming_bonus_rules gbr ON gbi.bonus_rule_id = gbr.bonus_rule_id; 
    
    IF (numPlayBonusInstances>0) THEN
   
      SET @winRealDeduct=0;    
      SET @winBonusAllTemp=0; 
      SET @winBonusTemp=0;
      SET @winBonusWinLockedTemp=0;
      
      SET @winBonusCurrent=0;
      SET @winBonusWinLockedCurrent=0;
      SET @winBonus=0;
      SET @winBonusWinLocked=0;
      
      SET @winBonusLostCurrent=0;
      SET @winBonusWinLockedLostCurrent=0;
      SET @winBonusLost=0;
      SET @winBonusWinLockedLost=0;
      SET @winRealBonusCurrent=0;

      SET @winRealLostFreeBonus=0;
	  SET @winRealLostFreeBonusTotal=0;
      
      SET @isBonusSecured=0;      
      
      INSERT INTO gaming_game_plays_bonus_instances_wins (game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, timestamp, exchange_rate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution)
      SELECT gamePlayWinCounterID, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, NOW(), exchangeRate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, clientStatID, NULL, add_wager_contribution
      FROM
      (
        SELECT 
          play_bonus_instances.game_play_bonus_instance_id, play_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id,
          
          @isBonusSecured:=IF(gaming_bonus_instances.is_secured, 1, @isBonusSecured),
          @winBonusAllTemp:=ROUND(((bet_bonus+bet_bonus_win_locked)/betTotal)*winAmount,0), 
          @winBonusTemp:=IF(bet_returns_type.name!='BonusWinLocked', LEAST(ROUND((bet_bonus/betTotal)*winAmount,0), bet_bonus), 0),
          @winBonusWinLockedTemp:= @winBonusAllTemp-@winBonusTemp,
          
          @winBonusCurrent:=ROUND(IF(bet_returns_type.name='Bonus' OR bet_returns_type.name='Loss', @winBonusTemp, 0.0), 0) AS win_bonus,
          @winBonusWinLockedCurrent:=ROUND(IF(bet_returns_type.name='BonusWinLocked', @winBonusAllTemp, @winBonusWinLockedTemp),0) AS win_bonus_win_locked,
		  @lostBonus :=  IF(is_secured  || is_free_bonus,(CASE transfer_type.name
						WHEN 'BonusWinLocked' THEN @winBonusCurrent
						WHEN 'UpToBonusAmount' THEN @winBonusCurrent - (bonus_amount_given-gaming_bonus_instances.bonus_transfered_total)
						WHEN 'UpToPercentage' THEN @winBonusCurrent -((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total)
						WHEN 'ReleaseBonus' THEN @winBonusCurrent  -(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total)
						ELSE 0
					END),0),
		  @lostBonusWinLocked := IF(is_secured || is_free_bonus,IF(@lostBonus<=0,(CASE transfer_type.name
						WHEN 'Bonus' THEN @winBonusWinLockedCurrent
						WHEN 'UpToBonusAmount' THEN @winBonusWinLockedCurrent - (bonus_amount_given-gaming_bonus_instances.bonus_transfered_total-@winBonusCurrent)
						WHEN 'UpToPercentage' THEN @winBonusWinLockedCurrent -((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total-@winBonusCurrent)
						WHEN 'ReleaseBonus' THEN @winBonusWinLockedCurrent -(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total-@winBonusCurrent)
						ELSE 0
					END),IF (transfer_type.name='BonusWinLocked',0,@winBonusWinLockedCurrent)),0),
		  @winBonusLostCurrent:=ROUND(IF(bet_returns_type.name='Loss' OR gaming_bonus_instances.is_lost=1, @winBonusTemp, IF(@lostBonus<0,0,@lostbonus)), 0) AS lost_win_bonus,
          @winBonusWinLockedLostCurrent:=ROUND(IF(gaming_bonus_instances.is_lost=1  AND is_free_bonus = 0, 
				@winBonusWinLockedCurrent, IF(@lostBonusWinLocked<0,0,@lostBonusWinLocked))) AS lost_win_bonus_win_locked,     
     
		  @winRealBonusCurrent:=
				IF(is_free_bonus=1,
					(CASE transfer_type.name
					  WHEN 'All' THEN GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
					  WHEN 'Bonus' THEN GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
					  WHEN 'BonusWinLocked' THEN GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
					  WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
					  WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total, GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
					  WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
					  WHEN 'ReleaseAllBonus' THEN GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
					  ELSE 0
					END)
				,IF(gaming_bonus_instances.is_secured=1, 
					(CASE transfer_type.name
					  WHEN 'All' THEN @winBonusAllTemp
					  WHEN 'Bonus' THEN @winBonusTemp
					  WHEN 'BonusWinLocked' THEN @winBonusWinLockedTemp
					  WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
					  WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
					  WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
					  WHEN 'ReleaseAllBonus' THEN @winBonusAllTemp
					  ELSE 0
					END), 0.0
				)) AS win_real,
          @winBonus:=@winBonus+@winBonusCurrent,
          @winBonusWinLocked:=@winBonusWinLocked+@winBonusWinLockedCurrent, 
          
          @winBonusLost:=@winBonusLost+@winBonusLostCurrent,
          @winBonusWinLockedLost:=@winBonusWinLockedLost+@winBonusWinLockedLostCurrent,
          
		  CASE addWagerContributionWithRealBet
			WHEN 1 THEN		  
				IF(gaming_bonus_instances.is_secured OR wager_restrictions.max_bet_add_win_contr IS NULL OR is_free_bonus=1, 0, 
					ROUND((GREATEST(0, (play_bonus_instances.bet_bonus+play_bonus_instances.bet_bonus_win_locked+play_bonus_instances.bet_real)-wager_restrictions.max_bet_add_win_contr)/
					(play_bonus_instances.bet_bonus+play_bonus_instances.bet_bonus_win_locked+play_bonus_instances.bet_real))*
					(@winBonusCurrent+@winBonusWinLockedCurrent+(winAmount*(play_bonus_instances.bet_real/CASE WHEN IFNULL(betReal,0)=0 THEN 1 ELSE betReal END)))
						* gaming_bonus_rules.over_max_bet_win_contr_multiplier, 0))
			ELSE
				IF (gaming_bonus_instances.is_secured OR wager_restrictions.max_bet_add_win_contr IS NULL OR is_free_bonus=1, 0, 
					ROUND((GREATEST(0, (play_bonus_instances.bet_bonus+play_bonus_instances.bet_bonus_win_locked)-wager_restrictions.max_bet_add_win_contr)/
					(play_bonus_instances.bet_bonus+play_bonus_instances.bet_bonus_win_locked))*(@winBonusCurrent+@winBonusWinLockedCurrent)*gaming_bonus_rules.over_max_bet_win_contr_multiplier, 0))
			END AS add_wager_contribution,  
			  
          gaming_bonus_instances.bonus_amount_remaining, gaming_bonus_instances.current_win_locked_amount
        FROM gaming_game_plays_win_counter_bets AS play_win_bets FORCE INDEX (PRIMARY)
        STRAIGHT_JOIN gaming_game_plays_bonus_instances AS play_bonus_instances FORCE INDEX (game_play_id) ON 
          play_win_bets.game_play_win_counter_id=gamePlayWinCounterID AND
          play_win_bets.game_play_id=play_bonus_instances.game_play_id 
        STRAIGHT_JOIN gaming_bonus_instances ON 
			play_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
        STRAIGHT_JOIN gaming_bonus_rules ON 
			gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        STRAIGHT_JOIN gaming_bonus_types_bet_returns AS bet_returns_type ON 
			gaming_bonus_rules.bonus_type_bet_return_id=bet_returns_type.bonus_type_bet_return_id
        STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON
			gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
        LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON 
			gaming_bonus_rules.bonus_rule_id=wager_restrictions.bonus_rule_id AND 
			wager_restrictions.currency_id=currencyID
      ) AS XX
      ON DUPLICATE KEY UPDATE 
        bonus_instance_id=VALUES(bonus_instance_id), win_real=VALUES(win_real), win_bonus=VALUES(win_bonus), win_bonus_win_locked=VALUES(win_bonus_win_locked), 
        lost_win_bonus=VALUES(lost_win_bonus), lost_win_bonus_win_locked=VALUES(lost_win_bonus_win_locked), client_stat_id=VALUES(client_stat_id);
            
      UPDATE gaming_game_plays_bonus_instances_wins AS PIU FORCE INDEX (PRIMARY)
      STRAIGHT_JOIN gaming_game_plays_bonus_instances AS pbi_update  FORCE INDEX (PRIMARY) ON 
		PIU.game_play_win_counter_id=gamePlayWinCounterID AND 
        pbi_update.game_play_bonus_instance_id=PIU.game_play_bonus_instance_id 
      STRAIGHT_JOIN gaming_bonus_instances ON pbi_update.bonus_instance_id=gaming_bonus_instances.bonus_instance_id AND 
		PIU.game_play_bonus_instance_id=pbi_update.game_play_bonus_instance_id 
      SET
        pbi_update.win_bonus=IFNULL(pbi_update.win_bonus,0)+PIU.win_bonus-PIU.lost_win_bonus, 
        pbi_update.win_bonus_win_locked=IFNULL(pbi_update.win_bonus_win_locked,0)+PIU.win_bonus_win_locked-PIU.lost_win_bonus_win_locked, 
        pbi_update.win_real=IFNULL(pbi_update.win_real,0)+PIU.win_real,
        pbi_update.lost_win_bonus=IFNULL(pbi_update.lost_win_bonus,0)+PIU.lost_win_bonus,
        pbi_update.lost_win_bonus_win_locked=IFNULL(pbi_update.lost_win_bonus_win_locked,0)+PIU.lost_win_bonus_win_locked,
        
        pbi_update.now_used_all=IF(is_free_rounds_mode=0 AND ROUND(gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount+gaming_bonus_instances.reserved_bonus_funds
			+PIU.win_bonus+PIU.win_bonus_win_locked,5)=0, 1, 0), 
        pbi_update.add_wager_contribution=IFNULL(pbi_update.add_wager_contribution, 0)+PIU.add_wager_contribution;
     
      
      SET winBonus=@winBonus-@winBonusLost;
      SET winBonusWinLocked=@winBonusWinLocked-@winBonusWinLockedLost;      
      SET winReal = winAmount - (@winBonus + @winBonusWinLocked);
         
      
      UPDATE 
      (
        SELECT play_bonus.bonus_instance_id, SUM(play_bonus_wins.win_real) AS win_real, SUM(play_bonus_wins.win_bonus) AS win_bonus, 
          SUM(play_bonus_wins.win_bonus_win_locked) AS win_bonus_win_locked, SUM(IFNULL(play_bonus_wins.add_wager_contribution, 0)) AS add_wager_contribution, MIN(play_bonus.now_used_all) AS now_used_all,
		  SUM(play_bonus_wins.lost_win_bonus) AS lost_win_bonus,SUM(play_bonus_wins.lost_win_bonus_win_locked) AS lost_win_bonus_win_locked
        FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins FORCE INDEX (PRIMARY)
        STRAIGHT_JOIN gaming_game_plays_bonus_instances AS play_bonus ON play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID 
			AND play_bonus_wins.game_play_bonus_instance_id=play_bonus.game_play_bonus_instance_id 
        GROUP BY play_bonus.bonus_instance_id
      ) AS PB
      STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=PB.bonus_instance_id  
      SET 
        bonus_amount_remaining=bonus_amount_remaining+PB.win_bonus-PB.lost_win_bonus,
        current_win_locked_amount=current_win_locked_amount+PB.win_bonus_win_locked-PB.lost_win_bonus_win_locked,
        total_amount_won=total_amount_won+(PB.win_bonus+PB.win_bonus_win_locked),
		bonus_transfered_total=bonus_transfered_total+PB.win_real,
        
        bonus_wager_requirement=IF(gaming_bonus_instances.is_active, bonus_wager_requirement+add_wager_contribution, bonus_wager_requirement),
        bonus_wager_requirement_remain=IF(gaming_bonus_instances.is_active, bonus_wager_requirement_remain+add_wager_contribution, bonus_wager_requirement_remain),
        
        gaming_bonus_instances.open_rounds=IF(closeRound,gaming_bonus_instances.open_rounds-1, gaming_bonus_instances.open_rounds),
        gaming_bonus_instances.is_used_all=IF(gaming_bonus_instances.is_active=1 AND PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-closeRound)<=0, 1, gaming_bonus_instances.is_used_all),
        gaming_bonus_instances.used_all_date=IF(PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-closeRound)<=0 AND used_all_date IS NULL, NOW(), used_all_date),
        gaming_bonus_instances.is_active=IF(PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-closeRound)<=0, 0, gaming_bonus_instances.is_active);
      
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
      
      SET @updateBonusInstancesWins=1;
    ELSE 
      
      IF (betReal=0 AND betBonus>0 AND winReal>0) THEN
        SET @winBonusLost=winReal;
        INSERT INTO gaming_game_rounds_misc (game_round_id, timestamp, win_real)
        VALUES (gameRoundID, NOW(), winReal);
        SET winReal=0;
      END IF;
    END IF; 
  ELSE 
  
    SET winReal = winAmount;
    SET winBonus = 0;  
    SET winBonusWinLocked = 0; 
    
  END IF;  

  SELECT SUM(win_bonus - lost_win_bonus) + SUM(win_bonus_win_locked - lost_win_bonus_win_locked) 
  INTO FreeBonusAmount 
  FROM gaming_game_plays_bonus_instances_wins FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_game_plays_bonus_instances_wins.bonus_instance_id
  STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
  STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
  WHERE gaming_game_plays_bonus_instances_wins.game_play_win_counter_id = gamePlayWinCounterID AND (gaming_bonus_types_awarding.name='FreeBet' OR is_free_bonus = 1);

  SET FreeBonusAmount = IFNULL(FreeBonusAmount,0);
    
  SET @winBonusLostFromPrevious=IFNULL(ROUND(((betBonusLost)/betTotal)*winAmount,5), 0);        
  SET winReal=winReal-@winBonusLostFromPrevious;  
  SET winReal=IF(winReal<0, 0, winReal);
 
  SET winTotalBase=ROUND(winAmount/exchangeRate,5);
  
  
  IF(taxEnabled AND (closeRound OR isRoundFinished)) THEN

	SET roundWinTotalFull = roundWinTotalReal + winReal;
	  -- TAX
	  -- betTotal is the sum of gaming_games_plays.amount_total of the bets in this round not processed (is_win_place = 0)
	  CALL TaxCalculateTax(licenseTypeID, clientStatID, clientID, roundWinTotalFull, betReal, taxAmount, taxAppliedOnType, taxCycleID);
	  -- If taxAppliedOnType is filled, means that tax is enabled and tax rule defined...
	  IF (taxAppliedOnType = 'OnReturn') THEN
			-- a) The tax should be stored in gaming_game_plays.amount_tax_player. 
			-- b) update gaming_client_stats -> current_real_balance
			-- c) update gaming_client_stats -> total_tax_paid

			SET taxOnReturn = taxAmount;

	  ELSEIF (taxAppliedOnType = 'Deferred') THEN
			/*
			a) - we don't update as initial thought Update gaming_tax_cycles -> deferred_tax_amount.
			b) - Update gaming_client_stats -> deferred_tax. ONLY IF taxAmount is POSITIVE
			c) - insert gaming_game_plays -> tax_cycle_id (gaming_tax_cycles) to link to the respective tax cycle.
			d) - insert gaming_game_plays -> amount_tax_player (even if taxAmount is NEGATIVE) The tax should be stored in the same column as non-deferred tax.

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

	 -- /TAX
  END IF;

  SET @cumulativeDeferredTax:=0;

  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_game_sessions AS ggs ON ggs.game_session_id=gameSessionID
  LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID   
  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET 
	gcs.total_wallet_real_won_online = IF(@channelType = 'online', gcs.total_wallet_real_won_online + winReal, gcs.total_wallet_real_won_online),
	gcs.total_wallet_real_won_retail = IF(@channelType = 'retail', gcs.total_wallet_real_won_retail + winReal, gcs.total_wallet_real_won_retail),
	gcs.total_wallet_real_won_self_service = IF(@channelType = 'self-service', gcs.total_wallet_real_won_self_service + winReal, gcs.total_wallet_real_won_self_service),
	gcs.total_wallet_real_won = gcs.total_wallet_real_won_online + gcs.total_wallet_real_won_self_service + gcs.total_wallet_real_won_self_service,
	gcs.total_real_won= IF(@channelType NOT IN ('online','retail','self-service'), gcs.total_real_won+winReal, gcs.total_wallet_real_won + gcs.total_cash_win),
	gcs.current_real_balance=gcs.current_real_balance+(winReal - taxOnReturn), 
    gcs.total_bonus_won=gcs.total_bonus_won+winBonus, gcs.current_bonus_balance=gcs.current_bonus_balance+IF(roundType='FreeRound', 0, winBonus), 
    gcs.total_bonus_win_locked_won=gcs.total_bonus_win_locked_won+winBonusWinLocked, gcs.current_bonus_win_locked_balance=current_bonus_win_locked_balance+IF(roundType='FreeRound', 0, winBonusWinLocked), 
    gcs.total_real_won_base=gcs.total_real_won_base+(winReal/exchangeRate), gcs.total_bonus_won_base=gcs.total_bonus_won_base+((winBonus+winBonusWinLocked)/exchangeRate),
    gcs.current_bonus_lost=IF(clearBonusLost=1,0,ROUND(@winBonusLost+@winBonusWinLockedLost+@winBonusLostFromPrevious,0)), gcs.total_tax_paid = gcs.total_tax_paid + taxOnReturn, -- add to tax paid if is onReturn only! If is deferred When we close tax cycle we update this
    ggs.total_win=ggs.total_win+winAmount, ggs.total_win_base=ggs.total_win_base+winTotalBase, ggs.total_bet_placed=ggs.total_bet_placed+betTotal, ggs.total_win_real=ggs.total_win_real+winReal, ggs.total_win_bonus=ggs.total_win_bonus+winBonus+winBonusWinLocked,
    gcsession.total_win=gcsession.total_win+winAmount, gcsession.total_win_base=gcsession.total_win_base+winTotalBase, gcsession.total_bet_placed=gcsession.total_bet_placed+betTotal, gcsession.total_win_real=gcsession.total_win_real+winReal, gcsession.total_win_bonus=gcsession.total_win_bonus+winBonus+winBonusWinLocked,
    gcws.num_wins=gcws.num_wins+IF(winAmount>0, 1, 0), gcws.total_real_won=gcws.total_real_won+winReal, gcws.total_bonus_won=gcws.total_bonus_won+winBonus+winBonusWinLocked,
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
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, bonus_lost, bonus_win_locked_lost, jackpot_contribution, 
	timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, 
    is_win_placed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, license_type_id, 
    pending_bet_real, pending_bet_bonus, amount_tax_operator, amount_tax_player, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus, loyalty_points_after_bonus, 
    tax_cycle_id, cumulative_deferred_tax) 
  SELECT winAmount, winTotalBase, exchangeRate, winReal, winBonus, winBonusWinLocked,FreeBonusAmount, @winBonusLost, ROUND(@winBonusWinLockedLost+@winBonusLostFromPrevious,0), 0, 
	NOW(), gameID, gameManufacturerID, operatorGameID, clientID, clientStatID, sessionID, gameSessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id,
    1, current_real_balance, ROUND(current_bonus_balance+current_bonus_win_locked_balance,0), current_bonus_win_locked_balance, currencyID, numTransactions+1, game_play_message_type_id, licenseTypeID, 
    pending_bets_real, pending_bets_bonus, taxModificationOperator, taxAmount, @platformTypeID,0,gaming_client_stats.current_loyalty_points, 0, 
    (gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`), 
    taxCycleID, gaming_client_stats.deferred_tax 
  FROM gaming_client_stats
  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=@transactionType
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=@messageType
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SET gamePlayID=LAST_INSERT_ID();

  IF (fingFencedEnabled) THEN
	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);
  END IF;

  
  IF (select value_bool from gaming_settings where name='RULE_ENGINE_ENABLED')=1 AND (winAmount > 0) THEN
      INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, gamePlayID;
  END IF;

  
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
  STRAIGHT_JOIN gaming_game_plays_win_counter_bets AS play_win_bets FORCE INDEX (PRIMARY) ON 
    play_win_bets.game_play_win_counter_id=gamePlayWinCounterID AND
    play_win_bets.game_play_id=gaming_game_plays.game_play_id
  SET is_win_placed=1, game_play_id_win=gamePlayID 
  WHERE gaming_game_plays.game_round_id=gameRoundID AND gaming_game_plays.is_win_placed=0;
  
  -- 17/03/2015 Changed statement to update license type id in gaming_game_rounds for game providers which send wins with round references which do not have a respective bet
  -- One of these providers is Merge
  UPDATE gaming_game_rounds
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET 
    win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+winTotalBase,5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus,win_free_bet=win_free_bet+FreeBonusAmount, 
    win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked, win_bet_diffence_base=win_total_base-bet_total_base,
    bonus_lost=bonus_lost+@winBonusLost, bonus_win_locked_lost=bonus_win_locked_lost+@winBonusWinLockedLost+@winBonusLostFromPrevious, 
    date_time_end= IF (closeRound, NOW(), date_time_end), is_round_finished=IF (closeRound, 1, is_round_finished), num_transactions=num_transactions+1, 
    balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance, amount_tax_operator = amountTaxOperator, amount_tax_player = taxAmount, 
    license_type_id = licenseTypeID,
	jackpot_win=jackpot_win+IF(isJackpotWin, winAmount, 0),
	tax_cycle_id = taxCycleID,
	cumulative_deferred_tax = @cumulativeDeferredTax
  WHERE gaming_game_rounds.game_round_id=gameRoundID; 

   IF (@isBonusSecured OR usedFreeBonus) THEN
 	CALL BonusConvertWinningsAfterSecuredDate(gamePlayID,gamePlayWinCounterID);
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
    
    
END root$$

DELIMITER ;

