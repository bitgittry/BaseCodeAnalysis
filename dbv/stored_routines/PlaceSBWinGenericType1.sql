DROP procedure IF EXISTS `PlaceSBWinGenericType1`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceSBWinGenericType1`(
  clientStatID BIGINT, betGamePlayID BIGINT, betGamePlaySBID BIGINT, winAmount DECIMAL(18, 5), 
  closeRound TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root: BEGIN

  -- Bad Dept and Negative win amount
  -- Minor bug fixing
  -- Duplicate transaction with bad dept
  -- Fixed when betting only from real money with no bonuses
  -- Storing GamePlayID of original transaction in bad debt transaction as extra_id
  -- Sports Book v2
  -- SportsAdjustment message type
  -- Fixed by joining to gaming_game_plays_sb_bonuses AS play_bonus_instances ON play_bonus_instances.game_play_sb_id=gaming_game_plays_sb.game_play_sb_id
  -- Forced indices
  -- Moved queries to PlaceTransactionOffsetNegativeBalancePreComputred
  -- Optimized for partitioning

  DECLARE betAmount, exchangeRate DECIMAL(18, 5) DEFAULT 0;
  DECLARE winTotalBase, winReal, winBonus, winBonusWinLocked, winFreeBet, winFreeBetWinLocked, roundBetTotal, roundWinTotal, 
		  betReal, betBonus, betBonusWinLocked, betBonusLost, betTotal, FreeBonusAmount, amountTaxPlayer, 
		  amountTaxOperator, taxBet, taxWin, roundWinTotalFullReal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, 
          taxModificationOperator, taxModificationPlayer, roundBetTotalReal, 
		  roundWinTotalReal, taxOnReturn, taxAmount, roundWinTotalFull DECIMAL(18, 5) DEFAULT 0;
  DECLARE roundWinBonusAlready, roundWinBonusWinLockedAlready, roundWinTotalFullBonus, roundBetTotalBonus DECIMAL(18, 5) DEFAULT 0;
  DECLARE gameRoundID, sessionID, gameManufacturerID, clientStatIDCheck, clientID, currencyID, gamePlayID, gamePlayWinCounterID, 
		  betGamePlayIDCheck, sbBetID, betMessageTypeID, betSBExtraID, 
		  countryID, countryTaxID, badDeptGamePlayID, badDeptTransactionID, gameSessionID BIGINT DEFAULT -1;
  DECLARE dateTimeWin DATETIME DEFAULT NULL;
  DECLARE bonusEnabledFlag, playLimitEnabled, isRoundFinished, updateGamePlayBonusInstanceWin, applyNetDeduction, winTaxPaidByOperator, taxEnabled, 
		  usedFreeBonus, isSBSingle, allowNegativeBalance, useFreeBet, disallowNegativeBalance, addWagerContributionWithRealBet, fingFencedEnabled TINYINT(1) DEFAULT 0;
  DECLARE numTransactions, singleMultTypeID, numPlayBonusInstances, hasPreviousWinTrans INT DEFAULT 0;
  DECLARE licenseType, taxAppliedOnType VARCHAR(20) DEFAULT NULL;
  DECLARE clientWagerTypeID INT DEFAULT 3; 
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
  DECLARE currentRealBalance, badDebtRealAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE taxCycleID INT DEFAULT NULL;
  
  DECLARE partitioningMinusFromMax INT DEFAULT 10000;
  DECLARE minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, 
	minSbBetMultipleSingleID, maxSbBetMultipleSingleID, minGameRoundID, maxGameRoundID, 
    minGamePlaySBID, maxGamePlaySBID, minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID BIGINT DEFAULT NULL;

  SET gamePlayIDReturned=NULL;
  SET licenseType='sportsbook';
 
  -- Get the settings   
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, IFNULL(gs3.value_bool, 0) AS vb3, IFNULL(gs4.value_bool, 0) AS vb4, 
	IFNULL(gs7.value_bool, 0) AS vb7, IFNULL(gs8.value_bool, 0) AS vb8
    INTO playLimitEnabled, bonusEnabledFlag, taxEnabled, disallowNegativeBalance, 
		 addWagerContributionWithRealBet, fingFencedEnabled
    FROM gaming_settings gs1 
    STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	LEFT JOIN gaming_settings gs3 ON (gs3.name='TAX_ON_GAMEPLAY_ENABLED')
	LEFT JOIN gaming_settings gs4 ON (gs4.name='WAGER_DISALLOW_NEGATIVE_BALANCE')
    LEFT JOIN gaming_settings gs7 ON (gs7.name='ADD_WAGER_CONTRIBUTION_WITH_REAL_BET')
    LEFT JOIN gaming_settings gs8 ON (gs8.name='RING_FENCED_ENABLED')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
 
  -- Lock the player 
  SELECT client_stat_id, client_id, gaming_client_stats.currency_id, current_real_balance 
  INTO clientStatIDCheck, clientID, currencyID, currentRealBalance
  FROM gaming_client_stats 
  WHERE client_stat_id=clientStatID
  FOR UPDATE;
  
  -- Get other player details
  SELECT country_id INTO countryID FROM clients_locations WHERE clients_locations.client_id=clientID AND clients_locations.is_primary=1; 
  SELECT session_id INTO sessionID FROM sessions_main FORCE INDEX (client_latest_session) WHERE extra_id=clientID AND is_latest;
  
  -- Get current exchange rate
  SELECT exchange_rate INTO exchangeRate FROM gaming_operator_currency WHERE gaming_operator_currency.currency_id=currencyID;
    
  -- Return if player is not found
  IF (clientStatIDCheck=-1) THEN 
    SET statusCode = 1;
    LEAVE root;
  END IF;
  
  -- Insert the multiple type if doesn't exist (should be very rare, ideally never)
  SELECT sb_multiple_type_id INTO singleMultTypeID FROM gaming_sb_multiple_types WHERE name='Single' AND game_manufacturer_id=gameManufacturerID; 

  -- Get the bet/wager transaction information
  SELECT sb_bet_id, sb_bet_entry_id, game_round_id, game_manufacturer_id, amount_total, 0, 
	amount_real, amount_bonus-amount_bonus_win_locked_component, amount_bonus_win_locked_component, sb_multiple_type_id=singleMultTypeID 
  INTO sbBetID, betSBExtraID, gameRoundID, gameManufacturerID, betTotal, betBonusLost, betReal, betBonus, betBonusWinLocked, isSBSingle
  FROM gaming_game_plays_sb FORCE INDEX (PRIMARY)
  WHERE game_play_sb_id=betGamePlaySBID AND payment_transaction_type_id IN (12, 45)
  ORDER BY gaming_game_plays_sb.game_play_sb_id DESC
  LIMIT 1;
  
  -- Get the round information
  SELECT num_transactions, bet_total, win_total, is_round_finished, amount_tax_operator, amount_tax_player, bet_real, win_real, win_bonus, win_bonus_win_locked
  INTO numTransactions, roundBetTotal, roundWinTotal, isRoundFinished, taxAlreadyChargedOperator, 
	   taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal, roundWinBonusAlready, roundWinBonusWinLockedAlready
  FROM gaming_game_rounds FORCE INDEX (PRIMARY)
  WHERE game_round_id=gameRoundID;
   
  -- Sanity check 
  IF (sbBetID=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SELECT 
    gsbpf.max_sb_bet_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_single_id, 
    gsbpf.max_sb_bet_multiple_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_id,
    gsbpf.max_sb_bet_multiple_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_single_id,
    gsbpf.min_game_round_id, gsbpf.max_game_round_id, 
    gsbpf.min_game_play_sb_id, gsbpf.max_game_play_sb_id,
    gsbpf.max_game_play_bonus_instance_id-partitioningMinusFromMax, gsbpf.max_game_play_bonus_instance_id
  INTO 
    minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, minSbBetMultipleSingleID, maxSbBetMultipleSingleID,
    minGameRoundID, maxGameRoundID, minGamePlaySBID, maxGamePlaySBID, minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID
  FROM gaming_sb_bets AS gsb
  LEFT JOIN gaming_sb_bets_partition_fields AS gsbpf ON gsbpf.sb_bet_id=gsb.sb_bet_id
  WHERE gsb.sb_bet_id=sbBetID;
  
  -- Default Values
  SET winReal=ABS(winAmount);
  SET winBonus=0; 
  SET winBonusWinLocked=0; 
  SET FreeBonusAmount =0;
  SET @winBonusLost=0; SET @winBonusWinLockedLost=0;

  -- Initilize values
  SET winBonus = 0; 
  SET @winBonusLost=0;
  SET @winBonusWinLockedLost=0;
  SET numPlayBonusInstances=0;  
  SET @updateBonusInstancesWins=0;  
  
  -- If winAmount is smaller than zero than the player funds will be deducted with a similar process to the bet\wager
  IF (winAmount < 0) THEN

   -- Partition the bet between free bet, real, bonus and bonus win locked
	SET useFreeBet=0;
	CALL PlaceBetPartitionWagerComponentsForSports(clientStatID, sbBetID, ABS(winAmount), bonusEnabledFlag, 0, useFreeBet, 
	  1, @numBonusInstances, winReal, winBonus, winBonusWinLocked, winFreeBet, winFreeBetWinLocked, badDebtRealAmount, statusCode);

  END IF;

  IF (bonusEnabledFlag OR (winBonus+winBonusWinLocked)>0) THEN 
    
    -- Check how many bonuses the player used when wagering
    SELECT COUNT(*), MAX(is_free_bonus) 
    INTO numPlayBonusInstances, usedFreeBonus
    FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id) 
	STRAIGHT_JOIN gaming_bonus_instances gbi ON 
		gaming_game_plays_bonus_instances.game_play_id=betGamePlayID AND
        -- parition filtering
		(gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID) AND 
        -- join
        gbi.bonus_instance_id = gaming_game_plays_bonus_instances.bonus_instance_id
	STRAIGHT_JOIN gaming_bonus_rules gbr ON gbi.bonus_rule_id = gbr.bonus_rule_id;
    
    IF (numPlayBonusInstances>0 OR (winBonus+winBonusWinLocked)>0) THEN
	
	  INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameRoundID);
      SET gamePlayWinCounterID=LAST_INSERT_ID();
      
  	  INSERT INTO gaming_game_plays_win_counter_bets (game_play_win_counter_id, game_play_id)
  	  SELECT DISTINCT gamePlayWinCounterID, game_play_id
  	  FROM gaming_game_plays
  	  WHERE game_play_id=betGamePlayID;

	  -- If winAmount is smaller than zero than the player funds will be deducted with a similar process to the bet\wager
	  IF (winAmount < 0) THEN

		SET @BonusCounter = 0;
		SET @betBonusDeduct=winBonus;
		SET @betBonusDeductWinLocked=winBonusWinLocked;

		INSERT INTO gaming_game_plays_bonus_instances_wins (
		  game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, timestamp, exchange_rate, 
		  win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution)
		SELECT gamePlayWinCounterID, bonus_instance_id*-1, bonus_instance_id, bonus_rule_id, NOW(), exchangeRate, 
		  bet_real*-1, bet_bonus*-1, bet_bonus_win_locked*-1, 0, 0, clientStatID, NULL, 0
		FROM (
			SELECT sbBetID, bonus_instance_id, bonus_rule_id,
				@BonusCounter := @BonusCounter +1 AS bonus_order,
				@BetReal :=IF(@BonusCounter=1, winReal,  0) AS bet_real,
				@betBonus:=IF(@betBonusDeduct>=bonus_amount_remaining, bonus_amount_remaining, @betBonusDeduct) AS bet_bonus,
				@betBonusWinLocked:=IF(@betBonusDeductWinLocked>=current_win_locked_amount, current_win_locked_amount, @betBonusDeductWinLocked) AS bet_bonus_win_locked,
				@betBonusDeduct:=GREATEST(0, @betBonusDeduct-@betBonus) AS bonusDeductRemain, 
				@betBonusDeductWinLocked:=GREATEST(0, @betBonusDeductWinLocked-@betBonusWinLocked) AS bonusWinLockedRemain
				FROM 
				(
				  SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, 
					IF(useFreeBet, 0, current_win_locked_amount) AS current_win_locked_amount, 
                    IF(useFreeBet, IF(gaming_bonus_types_awarding.name='FreeBet', bonus_amount_remaining, 0), 
                    IF(gaming_bonus_types_awarding.name='FreeBet', 0, bonus_amount_remaining)) AS bonus_amount_remaining
				  FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
				  STRAIGHT_JOIN gaming_sb_bets_bonus_rules ON 
					gaming_sb_bets_bonus_rules.sb_bet_id=sbBetID AND 
                    gaming_bonus_instances.bonus_rule_id=gaming_sb_bets_bonus_rules.bonus_rule_id
				  STRAIGHT_JOIN gaming_bonus_rules ON 
					gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				  STRAIGHT_JOIN gaming_bonus_types_awarding ON 
					gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
				  WHERE gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 
				  ORDER BY gaming_bonus_types_awarding.`order` ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.bonus_instance_id ASC
				) AS gaming_bonus_instances  
				HAVING bet_bonus > 0 OR bet_bonus_win_locked > 0
		) AS b;

		-- Update the remaining bonus balance
		UPDATE gaming_game_plays_bonus_instances_wins AS ggpbi FORCE INDEX (PRIMARY)
		STRAIGHT_JOIN gaming_bonus_instances AS gbi ON 
			ggpbi.game_play_win_counter_id=gamePlayWinCounterID AND
			gbi.bonus_instance_id=ggpbi.bonus_instance_id
		SET gbi.bonus_amount_remaining=gbi.bonus_amount_remaining+ggpbi.win_bonus,
		    gbi.current_win_locked_amount=gbi.current_win_locked_amount+ggpbi.win_bonus_win_locked;

	  ELSE

		SET winBonus = 0; 
		SET winBonusWinLocked = 0; 
		SET winReal = winAmount; 
    
		  -- Initialize Values (these will be used when no bonuses have been used when wagering
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
		  
		  
		  INSERT INTO gaming_game_plays_bonus_instances_wins (game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, 
			timestamp, exchange_rate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution)
		  SELECT gamePlayWinCounterID, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, 
			NOW(), exchangeRate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, clientStatID, NULL, add_wager_contribution
		  FROM
		  (
			SELECT 
			  play_bonus_instances_all.game_play_bonus_instance_id, play_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id,
			  
			  @isBonusSecured:=IF(gaming_bonus_instances.is_secured, 1, @isBonusSecured),
			  @winBonusAllTemp:=ROUND(((play_bonus_instances.bet_bonus+play_bonus_instances.bet_bonus_win_locked)/betTotal)*winAmount,0), 
			  @winBonusTemp:=IF(bet_returns_type.name!='BonusWinLocked', LEAST(ROUND((play_bonus_instances.bet_bonus/betTotal)*winAmount,0), play_bonus_instances.bet_bonus), 0),
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
						  WHEN 'All' THEN GREATEST((play_bonus_instances.bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
						  WHEN 'Bonus' THEN GREATEST((play_bonus_instances.bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
						  WHEN 'BonusWinLocked' THEN GREATEST((play_bonus_instances.bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
						  WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(gaming_bonus_instances.bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, GREATEST((play_bonus_instances.bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
						  WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((gaming_bonus_instances.bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total, GREATEST((play_bonus_instances.bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
						  WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(gaming_bonus_instances.bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, GREATEST((play_bonus_instances.bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
						  WHEN 'ReleaseAllBonus' THEN GREATEST((play_bonus_instances.bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
						  ELSE 0
						END)
					,IF(gaming_bonus_instances.is_secured=1, 
						(CASE transfer_type.name
						  WHEN 'All' THEN @winBonusAllTemp
						  WHEN 'Bonus' THEN @winBonusTemp
						  WHEN 'BonusWinLocked' THEN @winBonusWinLockedTemp
						  WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(gaming_bonus_instances.bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
						  WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((gaming_bonus_instances.bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
						  WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(gaming_bonus_instances.bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
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
						(@winBonusCurrent+@winBonusWinLockedCurrent+(winAmount*(play_bonus_instances.bet_real/IFNULL(betReal,1))))
							* gaming_bonus_rules.over_max_bet_win_contr_multiplier, 0))
				ELSE
					IF (gaming_bonus_instances.is_secured OR wager_restrictions.max_bet_add_win_contr IS NULL OR is_free_bonus=1, 0, 
						ROUND((GREATEST(0, (play_bonus_instances.bet_bonus+play_bonus_instances.bet_bonus_win_locked)-wager_restrictions.max_bet_add_win_contr)/
						(play_bonus_instances.bet_bonus+play_bonus_instances.bet_bonus_win_locked))*(@winBonusCurrent+@winBonusWinLockedCurrent)*gaming_bonus_rules.over_max_bet_win_contr_multiplier, 0))
				END AS add_wager_contribution,  
				  
			  gaming_bonus_instances.bonus_amount_remaining, gaming_bonus_instances.current_win_locked_amount
			FROM gaming_game_plays_win_counter_bets AS play_win_bets FORCE INDEX (PRIMARY)
            STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (PRIMARY) ON 
				play_win_bets.game_play_win_counter_id=gamePlayWinCounterID AND
				(gaming_game_plays_sb.game_play_sb_id=betGamePlaySBID AND gaming_game_plays_sb.game_play_id=play_win_bets.game_play_id)
            STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS play_bonus_instances ON 
				play_bonus_instances.game_play_sb_id=gaming_game_plays_sb.game_play_sb_id
			STRAIGHT_JOIN gaming_bonus_instances ON 
				play_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			STRAIGHT_JOIN gaming_game_plays_bonus_instances AS play_bonus_instances_all FORCE INDEX (game_play_id) ON 
				play_bonus_instances_all.game_play_id=play_win_bets.game_play_id AND 
				play_bonus_instances_all.bonus_instance_id=gaming_bonus_instances.bonus_instance_id AND
                -- parition filtering
				(play_bonus_instances_all.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID)
            STRAIGHT_JOIN gaming_bonus_rules ON 
				gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			STRAIGHT_JOIN gaming_bonus_types_bet_returns AS bet_returns_type ON 
				gaming_bonus_rules.bonus_type_bet_return_id=bet_returns_type.bonus_type_bet_return_id
			STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON 
				gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
			LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON 
				gaming_bonus_rules.bonus_rule_id=wager_restrictions.bonus_rule_id AND wager_restrictions.currency_id=currencyID
		  ) AS XX
		  ON DUPLICATE KEY UPDATE 
			bonus_instance_id=VALUES(bonus_instance_id), win_real=VALUES(win_real), win_bonus=VALUES(win_bonus), 
			win_bonus_win_locked=VALUES(win_bonus_win_locked), lost_win_bonus=VALUES(lost_win_bonus), lost_win_bonus_win_locked=VALUES(lost_win_bonus_win_locked), 
            client_stat_id=VALUES(client_stat_id);
				
		  UPDATE gaming_game_plays_bonus_instances_wins AS PIU FORCE INDEX (PRIMARY)
		  STRAIGHT_JOIN gaming_game_plays_bonus_instances AS pbi_update FORCE INDEX (PRIMARY) ON 
			PIU.game_play_win_counter_id=gamePlayWinCounterID AND 
            pbi_update.game_play_bonus_instance_id=PIU.game_play_bonus_instance_id AND
            -- parition filtering
			(pbi_update.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID)
		  STRAIGHT_JOIN gaming_bonus_instances ON 
			pbi_update.bonus_instance_id=gaming_bonus_instances.bonus_instance_id 
		  SET
			pbi_update.win_bonus=IFNULL(pbi_update.win_bonus,0)+PIU.win_bonus-PIU.lost_win_bonus, 
			pbi_update.win_bonus_win_locked=IFNULL(pbi_update.win_bonus_win_locked,0)+PIU.win_bonus_win_locked-PIU.lost_win_bonus_win_locked, 
			pbi_update.win_real=IFNULL(pbi_update.win_real,0)+PIU.win_real,
			pbi_update.lost_win_bonus=IFNULL(pbi_update.lost_win_bonus,0)+PIU.lost_win_bonus,
			pbi_update.lost_win_bonus_win_locked=IFNULL(pbi_update.lost_win_bonus_win_locked,0)+PIU.lost_win_bonus_win_locked,
			
			pbi_update.now_used_all=IF(ROUND(gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount+gaming_bonus_instances.reserved_bonus_funds
				+PIU.win_bonus+PIU.win_bonus_win_locked,5)=0, 1, 0), 
			pbi_update.add_wager_contribution=IFNULL(pbi_update.add_wager_contribution, 0)+PIU.add_wager_contribution;
		 
  
		  SET winBonus=@winBonus-@winBonusLost;
		  SET winBonusWinLocked=@winBonusWinLocked-@winBonusWinLockedLost;      
		  SET winReal = winAmount - (@winBonus + @winBonusWinLocked);
			 
		  
		  UPDATE 
		  (
			SELECT play_bonus.bonus_instance_id, SUM(play_bonus_wins.win_real) AS win_real, 
			  SUM(play_bonus_wins.win_bonus) AS win_bonus, SUM(play_bonus_wins.win_bonus_win_locked) AS win_bonus_win_locked, 
              SUM(IFNULL(play_bonus_wins.add_wager_contribution, 0)) AS add_wager_contribution, MIN(play_bonus.now_used_all) AS now_used_all,
			  SUM(play_bonus_wins.lost_win_bonus) AS lost_win_bonus, SUM(play_bonus_wins.lost_win_bonus_win_locked) AS lost_win_bonus_win_locked
			FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins FORCE INDEX (PRIMARY)
			STRAIGHT_JOIN gaming_game_plays_bonus_instances AS play_bonus FORCE INDEX (PRIMARY) ON 
				play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND 
				play_bonus.game_play_bonus_instance_id=play_bonus_wins.game_play_bonus_instance_id AND
				-- parition filtering
				(play_bonus.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID)
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
			
			gaming_bonus_instances.open_rounds=IF(closeRound AND isRoundFinished= 0,gaming_bonus_instances.open_rounds-1, gaming_bonus_instances.open_rounds),
			is_used_all=IF(is_active=1 AND PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-closeRound + isRoundFinished)<=0, 1, 0),
			used_all_date=IF(is_active=1 AND PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-closeRound + isRoundFinished)<=0 AND used_all_date IS NULL, NOW(), used_all_date),
			gaming_bonus_instances.is_active=IF(is_active=1 AND PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-closeRound + isRoundFinished)<=0, 0, gaming_bonus_instances.is_active);
		  
		  IF (@winBonusLost+@winBonusWinLockedLost>0) THEN
			
			INSERT INTO gaming_bonus_losts (bonus_instance_id, client_stat_id, bonus_lost_type_id, bonus_amount, bonus_win_locked_amount, extra_id, date_time_lost, session_id)
			SELECT bonus_instance_id, client_stat_id, gaming_bonus_lost_types.bonus_lost_type_id, IFNULL(SUM(lost_win_bonus),0), IFNULL(SUM(lost_win_bonus_win_locked),0), gamePlayWinCounterID, NOW(), sessionID
			FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins FORCE INDEX (PRIMARY)
			STRAIGHT_JOIN gaming_bonus_lost_types ON 
			   play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND
			  (play_bonus_wins.lost_win_bonus!=0 OR play_bonus_wins.lost_win_bonus_win_locked!=0) 
			WHERE gaming_bonus_lost_types.name='WinAfterLost'
			GROUP BY play_bonus_wins.bonus_instance_id;  
		  END IF;
		  
		  SET @updateBonusInstancesWins=1;

	  END IF;

    ELSE  -- IF (@numPlayBonusInstances>0) THEN
      
      IF (betReal=0 AND (betBonus+betBonusWinLocked)>0 AND winReal>0) THEN
        SET @winBonusLost=winReal;
        INSERT INTO gaming_game_rounds_misc (game_round_id, timestamp, win_real)
        VALUES (gameRoundID, NOW(), winReal);
        SET winReal=0;
      END IF;
      
    END IF; 
    
  END IF; -- If bonuses are not enabled
    
  IF (winAmount>0) THEN
	SET @winBonusLostFromPrevious=IFNULL(ROUND(((betBonusLost)/betTotal)*winAmount,5), 0);        
  ELSE
	SET @winBonusLostFromPrevious=0;

	SET winReal=winReal*-1;
	SET winBonus=winBonus*-1;
	SET winBonusWinLocked=winBonusWinLocked*-1;
	SET winFreeBet=winFreeBet*-1;
	SET winFreeBetWinLocked=winFreeBetWinLocked*-1;
  END IF;

  SET winReal=winReal-@winBonusLostFromPrevious;  
 
  SET winTotalBase=ROUND(winAmount/exchangeRate, 5);

-- TAX
  IF(taxEnabled AND (closeRound OR IsRoundFinished)) THEN

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

  -- Update player's balance and statitics statistics  
  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID   
  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET 
	-- client stats
    gcs.total_real_won=gcs.total_real_won+winReal, gcs.current_real_balance=gcs.current_real_balance+(winReal - taxOnReturn), 
    gcs.total_bonus_won=gcs.total_bonus_won+winBonus, gcs.current_bonus_balance=gcs.current_bonus_balance+winBonus, 
    gcs.total_bonus_win_locked_won=gcs.total_bonus_win_locked_won+winBonusWinLocked, gcs.current_bonus_win_locked_balance=current_bonus_win_locked_balance+winBonusWinLocked, 
    gcs.total_real_won_base=gcs.total_real_won_base+(winReal/exchangeRate), gcs.total_bonus_won_base=gcs.total_bonus_won_base+((winBonus+winBonusWinLocked)/exchangeRate), gcs.total_tax_paid = gcs.total_tax_paid + taxOnReturn, gcs.total_tax_paid_bonus = gcs.total_tax_paid_bonus,
    -- client session
    gcsession.total_win=gcsession.total_win+winAmount, gcsession.total_win_base=gcsession.total_win_base+winTotalBase, gcsession.total_bet_placed=gcsession.total_bet_placed+betTotal, gcsession.total_win_real=gcsession.total_win_real+winReal, gcsession.total_win_bonus=gcsession.total_win_bonus+winBonus+winBonusWinLocked,
	-- wager status
    gcws.num_wins=gcws.num_wins+IF(winAmount>0, 1, 0), gcws.total_real_won=gcws.total_real_won+winReal, gcws.total_bonus_won=gcws.total_bonus_won+winBonus+winBonusWinLocked,
	gcs.deferred_tax = @cumulativeDeferredTax := (gcs.deferred_tax + IF(taxAppliedOnType ='Deferred', taxAmount, 0)) -- cumulative deferred tax to later on (when we need to close tax cycle) transfer to the respective tax cycle 
  WHERE gcs.client_stat_id=clientStatID;  
  
  -- Insert into gaming_plays (main transaction)
  SET @messageType=IF(winAmount=0, 'SportsLoss', IF (winAmount < 0, 'SportsAdjustment', IF(isSBSingle='Single','SportsWin','SportsWinMult')));
  
  -- check if there are previous win transactions
   SELECT COUNT(sb_bet_id) INTO hasPreviousWinTrans 
   FROM gaming_game_plays_sb 
   WHERE sb_bet_id = sbBetID AND payment_transaction_type_id = 13;
  
  SET @transactionType=
    CASE
      WHEN hasPreviousWinTrans = 0 THEN 'Win'
	  /* winAmount < 0 */
	  WHEN winAmount < 0 AND hasPreviousWinTrans >0 AND ABS(winAmount) = roundWinTotal THEN 'WinCancelled'
      /* Any additional transactiontypes ?? */
      ELSE 'WinAdjustment'
    END;
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_free_bet, amount_other, bonus_lost, bonus_win_locked_lost, 
   jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, is_win_placed, 
   balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, 
   sb_extra_id, sb_bet_id, license_type_id, device_type, pending_bet_real, pending_bet_bonus, 
   amount_tax_operator, amount_tax_player, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, tax_cycle_id, cumulative_deferred_tax) 
  SELECT winAmount, winTotalBase, exchangeRate, winReal, winBonus, winBonusWinLocked, FreeBonusAmount, badDebtRealAmount, @winBonusLost, ROUND(@winBonusWinLockedLost+@winBonusLostFromPrevious, 0), 
   0, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 
   gcs.current_real_balance, ROUND(gcs.current_bonus_balance+gcs.current_bonus_win_locked_balance, 0), gcs.current_bonus_win_locked_balance, currencyID, numTransactions+1, gaming_game_play_message_types.game_play_message_type_id, 
   betSBExtraID, sbBetID, gaming_game_plays.license_type_id, gaming_game_plays.device_type, gcs.pending_bets_real, gcs.pending_bets_bonus, 
   taxModificationOperator, taxModificationPlayer, 0, gcs.current_loyalty_points, 0, gcs.total_loyalty_points_given_bonus - gcs.total_loyalty_points_used_bonus, taxCycleID, gcs.deferred_tax 
  FROM gaming_client_stats AS gcs
  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=@transactionType 
  STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.game_play_id=betGamePlayID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=@messageType
  WHERE gcs.client_stat_id=clientStatID;
  
  SET gamePlayID=LAST_INSERT_ID();

  IF (select value_bool from gaming_settings where name='RULE_ENGINE_ENABLED')=1 AND ((SELECT amount_total_base FROM gaming_game_plays WHERE game_play_id=gamePlayID)> 0) THEN
      INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, gamePlayID;
  END IF;
  
  -- Update ring fencing balance and statistics
  IF (fingFencedEnabled) THEN
	CALL GameUpdateRingFencedBalances(clientStatID, gamePlayID);
  END IF;

  IF (disallowNegativeBalance AND badDebtRealAmount > 0) THEN
	CALL PlaceTransactionOffsetNegativeBalancePreComputred(clientStatID, badDebtRealAmount, exchangeRate, gamePlayID, betSBExtraID, sbBetID, 3, badDeptGamePlayID);
  END IF;
  
  -- update bet and win bonus counters
  UPDATE gaming_game_plays_win_counter_bets
  SET win_game_play_id=gamePlayID
  WHERE game_play_win_counter_id=gamePlayWinCounterID;

  IF (updateGamePlayBonusInstanceWin) THEN
    UPDATE gaming_game_plays_bonus_instances_wins 
    SET win_game_play_id=gamePlayID 
    WHERE game_play_win_counter_id=gamePlayWinCounterID;
  END IF;
 
  -- Insert into gaming_game_plays_sb to store extra sports book details and to have all sports book transactions in this table
  INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, 
	game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, 
	sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units, confirmation_status, amount_bonus_win_locked_component, game_round_id, sb_bet_entry_id)
  SELECT gaming_game_plays.game_play_id, gaming_game_plays.payment_transaction_type_id, gaming_game_plays.amount_total, gaming_game_plays.amount_total_base, gaming_game_plays.amount_real, gaming_game_plays.amount_real/gaming_game_plays.exchange_rate, 
	gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/gaming_game_plays.exchange_rate, gaming_game_plays.timestamp, gaming_game_plays.exchange_rate, 
	bet_play_sb.game_manufacturer_id, clientID, clientStatID, currencyID, countryID, gaming_game_plays.round_transaction_no, bet_play_sb.sb_sport_id, bet_play_sb.sb_region_id, bet_play_sb.sb_group_id, bet_play_sb.sb_event_id, bet_play_sb.sb_market_id, bet_play_sb.sb_selection_id, 
	gaming_game_plays.sb_bet_id, bet_play_sb.sb_multiple_type_id, bet_play_sb.sb_bet_type, bet_play_sb.device_type, 0, 2, gaming_game_plays.amount_bonus_win_locked, bet_play_sb.game_round_id, bet_play_sb.sb_bet_entry_id
  FROM gaming_game_plays
  STRAIGHT_JOIN gaming_game_plays_sb AS bet_play_sb ON 
	bet_play_sb.game_play_sb_id=betGamePlaySBID 
  WHERE gaming_game_plays.game_play_id=gamePlayID;
  
  SET maxGamePlaySBID = LAST_INSERT_ID(); 
  
  /* is show sum of wins from the above table (mostly for reports) */
	UPDATE gaming_game_plays_bonus_instances_wins FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_game_plays_sb_bonuses FORCE INDEX (PRIMARY) ON 
		(gaming_game_plays_sb_bonuses.game_play_sb_id=betGamePlaySBID AND
		 gaming_game_plays_bonus_instances_wins.bonus_instance_id=gaming_game_plays_sb_bonuses.bonus_instance_id)
	SET 
		gaming_game_plays_sb_bonuses.win_real = gaming_game_plays_sb_bonuses.win_real + gaming_game_plays_bonus_instances_wins.win_real,
		gaming_game_plays_sb_bonuses.win_bonus = gaming_game_plays_sb_bonuses.win_bonus + gaming_game_plays_bonus_instances_wins.win_bonus,
		gaming_game_plays_sb_bonuses.win_bonus_win_locked = gaming_game_plays_sb_bonuses.win_bonus_win_locked + gaming_game_plays_bonus_instances_wins.win_bonus_win_locked
	WHERE gaming_game_plays_bonus_instances_wins.game_play_win_counter_id=gamePlayWinCounterID;
 
  -- Update play limits current status (loss only) 
  IF (winAmount > 0 AND playLimitEnabled) THEN
    CALL PlayLimitsUpdate(clientStatID, licenseType, winAmount, 0);
  END IF;
  
  -- Update the round statistics and close it
  UPDATE gaming_game_rounds
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET 
    win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+winTotalBase,5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus, 
    win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked,win_free_bet = win_free_bet+FreeBonusAmount, 
    bonus_lost=bonus_lost+@winBonusLost, bonus_win_locked_lost=bonus_win_locked_lost+@winBonusWinLockedLost+@winBonusLostFromPrevious, 
    date_time_end= IF (closeRound, NOW(), date_time_end), is_round_finished=IF (closeRound, 1, is_round_finished), num_transactions=num_transactions+1, 
    balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance, 
    amount_tax_operator = amountTaxOperator, amount_tax_player = taxAmount,
	tax_cycle_id = taxCycleID,
	cumulative_deferred_tax = @cumulativeDeferredTax,
    win_bet_diffence_base=win_total_base-bet_total_base
  WHERE gaming_game_rounds.game_round_id=gameRoundID;   
  
  -- Update also the master round statistics
  UPDATE gaming_game_rounds
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET 
    win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+winTotalBase,5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus, 
    win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked, win_free_bet=win_free_bet+FreeBonusAmount,
    bonus_lost=bonus_lost+@winBonusLost, bonus_win_locked_lost=bonus_win_locked_lost+@winBonusWinLockedLost+@winBonusLostFromPrevious, 
    date_time_end=IF(closeRound, NOW(), date_time_end), num_transactions=num_transactions+1, 
    balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance, 
    amount_tax_operator = amountTaxOperator, amount_tax_player = taxAmount,
	tax_cycle_id = taxCycleID,
	cumulative_deferred_tax = @cumulativeDeferredTax,
    win_bet_diffence_base=win_total_base-bet_total_base
  WHERE gaming_game_rounds.round_ref=sbBetID AND gaming_game_rounds.is_cancelled = 0 AND
	-- parition filtering
	(gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID);

  -- Check if bonus is secured
  IF (@isBonusSecured OR usedFreeBonus) THEN
	CALL BonusConvertWinningsAfterSecuredDate(gamePlayID,  gamePlayWinCounterID);
  END IF;
  
  -- Set output variables
  SET gamePlayIDReturned=gamePlayID;
  SET statusCode=0;

  UPDATE gaming_sb_bets_partition_fields
  SET 
    max_game_play_sb_id=maxGamePlaySBID
  WHERE sb_bet_id=sbBetID;

  IF (winAmount<0) THEN
	SELECT badDeptGamePlayID AS game_play_id, IF(disallowNegativeBalance, badDebtRealAmount, 0.00000) AS bad_dept_real_amount;
  END IF;
    
END root$$

DELIMITER ;

