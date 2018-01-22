DROP procedure IF EXISTS `PlaceSBWinGeneric`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceSBWinGeneric`(clientStatID BIGINT, betGamePlayID BIGINT, betGamePlaySBID BIGINT, winAmount DECIMAL(18, 5), closeRound TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root: BEGIN
  -- Bad Dept and Negative win amount
  -- Minor bug fixing
  -- Duplicate transaction with bad dept
  -- Fixed when betting only from real money with no bonuses
  -- Storing GamePlayID of original transaction in bad debt transaction as extra_id
  -- Sports Book v2
  -- SportsAdjustment message type

  DECLARE betAmount, exchangeRate DECIMAL(18, 5) DEFAULT 0;
  DECLARE winTotalBase, winReal, winBonus, winBonusWinLocked, winFreeBet, winFreeBetWinLocked, roundBetTotal, roundWinTotal, 
		  betReal, betBonus, betBonusWinLocked, betBonusLost, betTotal, FreeBonusAmount, amountTaxPlayer, 
		  amountTaxOperator, taxBet, taxWin, roundWinTotalFullReal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, taxModificationOperator, taxModificationPlayer, roundBetTotalReal, 
		  roundWinTotalReal DECIMAL(18, 5) DEFAULT 0;
  DECLARE amountTaxPlayerBonus, taxAlreadyChargedPlayerBonus, taxModificationPlayerBonus, roundWinBonusAlready, roundWinBonusWinLockedAlready, roundWinTotalFullBonus, taxModificationOperatorBonus, 
		  taxAlreadyChargedOperatorBonus, roundBetTotalBonus, amountTaxOperatorBonus, taxReduceBonus, taxReduceBonusWinLocked DECIMAL(18, 5) DEFAULT 0;
  DECLARE gameRoundID, sessionID, gameManufacturerID, clientStatIDCheck, clientID, currencyID, gamePlayID, gamePlayWinCounterID, betGamePlayIDCheck, sbBetID, betMessageTypeID, betSBExtraID, 
		  countryID, countryTaxID, badDeptGamePlayID, badDeptTransactionID BIGINT DEFAULT -1;
  DECLARE dateTimeWin DATETIME DEFAULT NULL;
  DECLARE bonusEnabledFlag, playLimitEnabled, isRoundFinished, updateGamePlayBonusInstanceWin, applyNetDeduction, winTaxPaidByOperator, taxEnabled, 
		  sportsTaxCountryEnabled, usedFreeBonus, isSBSingle, allowNegativeBalance, useFreeBet, disallowNegativeBalance TINYINT(1) DEFAULT 0;
  DECLARE numTransactions, singleMultTypeID INT DEFAULT 0;
  DECLARE licenseType VARCHAR(20) DEFAULT NULL;
  DECLARE clientWagerTypeID INT DEFAULT 3; 
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
  DECLARE currentRealBalance, badDebtRealAmount DECIMAL(18, 5) DEFAULT 0;
  
  SET gamePlayIDReturned=NULL;
  SET licenseType='sportsbook';
 
  -- Get the settings   
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, IFNULL(gs3.value_bool, 0) AS vb3, IFNULL(gs4.value_bool, 0) AS vb4
    INTO playLimitEnabled, bonusEnabledFlag, taxEnabled, disallowNegativeBalance
    FROM gaming_settings gs1 
    JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	LEFT JOIN gaming_settings gs3 ON (gs3.name='TAX_ON_GAMEPLAY_ENABLED')
	LEFT JOIN gaming_settings gs4 ON (gs4.name='WAGER_DISALLOW_NEGATIVE_BALANCE')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
 
  -- Lock the player 
  SELECT client_stat_id, client_id, gaming_client_stats.currency_id, current_real_balance 
  INTO clientStatIDCheck, clientID, currencyID, currentRealBalance
  FROM gaming_client_stats 
  WHERE client_stat_id=clientStatID
  FOR UPDATE;
  
  -- Get other player details
  SELECT country_id INTO countryID FROM clients_locations WHERE clients_locations.client_id=clientID AND clients_locations.is_primary=1; 
  SELECT session_id INTO sessionID FROM sessions_main WHERE extra_id=clientID AND is_latest;
  
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
  SELECT sb_bet_id, sb_bet_entry_id, game_round_id, game_manufacturer_id, amount_total, 0, amount_real, amount_bonus-amount_bonus_win_locked_component, amount_bonus_win_locked_component, sb_multiple_type_id=singleMultTypeID 
  INTO sbBetID, betSBExtraID, gameRoundID, gameManufacturerID, betTotal, betBonusLost, betReal, betBonus, betBonusWinLocked, isSBSingle
  FROM gaming_game_plays_sb
  WHERE game_play_sb_id=betGamePlaySBID AND payment_transaction_type_id=12;
  
  -- Get the round information
  SELECT num_transactions, bet_total, win_total, is_round_finished, amount_tax_operator, amount_tax_player, amount_tax_player_bonus, amount_tax_operator_bonus, bet_real, win_real, win_bonus, win_bonus_win_locked
  INTO numTransactions, roundBetTotal, roundWinTotal, isRoundFinished, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, taxAlreadyChargedPlayerBonus, taxAlreadyChargedOperatorBonus, roundBetTotalReal, roundWinTotalReal, roundWinBonusAlready, roundWinBonusWinLockedAlready
  FROM gaming_game_rounds
  WHERE game_round_id=gameRoundID;
   
  -- Sanity check 
  IF (sbBetID=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
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
  SET @numPlayBonusInstances=0;  
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
    INTO @numPlayBonusInstances, usedFreeBonus
    FROM gaming_game_plays_bonus_instances 
	  JOIN gaming_bonus_instances gbi ON gbi.bonus_instance_id = gaming_game_plays_bonus_instances.bonus_instance_id
	  JOIN gaming_bonus_rules gbr ON gbi.bonus_rule_id = gbr.bonus_rule_id
    WHERE game_play_id=betGamePlayID; 
    
    IF (@numPlayBonusInstances>0 OR (winBonus+winBonusWinLocked)>0) THEN
	
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
				  SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, IF(useFreeBet, 0, current_win_locked_amount) AS current_win_locked_amount, IF(useFreeBet, IF(gaming_bonus_types_awarding.name='FreeBet', bonus_amount_remaining, 0), IF(gaming_bonus_types_awarding.name='FreeBet', 0, bonus_amount_remaining)) AS bonus_amount_remaining
				  FROM gaming_bonus_instances
				  JOIN gaming_sb_bets_bonus_rules ON gaming_sb_bets_bonus_rules.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=gaming_sb_bets_bonus_rules.bonus_rule_id
				  JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				  JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
				  WHERE client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 
				  ORDER BY gaming_bonus_types_awarding.order ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.bonus_instance_id ASC
				) AS gaming_bonus_instances  
				HAVING bet_bonus > 0 OR bet_bonus_win_locked > 0
		) AS b;

		-- Update the remaining bonus balance
		UPDATE gaming_bonus_instances AS gbi
		JOIN gaming_game_plays_bonus_instances_wins AS ggpbi ON gbi.bonus_instance_id=ggpbi.bonus_instance_id
		SET gbi.bonus_amount_remaining=gbi.bonus_amount_remaining+ggpbi.win_bonus,
		    gbi.current_win_locked_amount=gbi.current_win_locked_amount+ggpbi.win_bonus_win_locked
		WHERE ggpbi.game_play_win_counter_id=gamePlayWinCounterID;   

	  ELSE

		  -- Initialize Values (these will be used when no bonuses have been used when wagering
		  SET winBonusWinLocked = 0; 
		  SET winBonus = 0;
		  SET winReal = winAmount; 

		  -- Initialize values
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
		  SET updateGamePlayBonusInstanceWin=1;
		  
		  INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameRoundID);
		  SET gamePlayWinCounterID=LAST_INSERT_ID();
		  
		  INSERT INTO gaming_game_plays_win_counter_bets (game_play_win_counter_id, game_play_id)
		  SELECT DISTINCT gamePlayWinCounterID, game_play_id
		  FROM gaming_game_plays
		  WHERE game_play_id=betGamePlayID;

		  INSERT INTO gaming_game_plays_bonus_instances_wins (game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, timestamp, exchange_rate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution)
		  SELECT gamePlayWinCounterID, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, NOW(), exchangeRate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, clientStatID, NULL, add_wager_contribution
		  FROM
		  (
			SELECT 
			  play_bonus_instances.game_play_bonus_instance_id, play_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id,
			  
			  @isBonusSecured:=IF(gaming_bonus_instances.is_secured, 1, @isBonusSecured),
			  @winBonusAllTemp:=ROUND(((betBonus+betBonusWinLocked)/betTotal)*winAmount,0), 
			  @winBonusTemp:=IF(bet_returns_type.name!='BonusWinLocked' , LEAST(ROUND((betBonus/betTotal)*winAmount,0), betBonus), 0),
			  @winBonusWinLockedTemp:=@winBonusAllTemp-@winBonusTemp,
			  @winBonusCurrent:=ROUND(IF(bet_returns_type.name='Bonus' OR bet_returns_type.name='Loss', @winBonusTemp, 0.0), 0) AS win_bonus,
			  @winBonusWinLockedCurrent:=ROUND(IF(bet_returns_type.name='BonusWinLocked', @winBonusAllTemp, @winBonusWinLockedTemp),0) AS win_bonus_win_locked,
				  @lostBonus :=  IF(is_secured  || is_free_bonus,(CASE transfer_type.name
							WHEN 'BonusWinLocked' THEN IF(bet_returns_type.name='Bonus' AND is_free_bonus,0,@winBonusCurrent)
							WHEN 'UpToBonusAmount' THEN @winBonusCurrent -  GREATEST(0,(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total))
							WHEN 'UpToPercentage' THEN @winBonusCurrent - GREATEST(0,((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total))
							WHEN 'ReleaseBonus' THEN @winBonusCurrent  - GREATEST(0,(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total))
							ELSE 0
						END),0),
				  @lostBonusWinLocked := IF(is_secured || is_free_bonus,IF(@lostBonus<=0,(CASE transfer_type.name
							WHEN 'Bonus' THEN @winBonusWinLockedCurrent
							WHEN 'UpToBonusAmount' THEN @winBonusWinLockedCurrent -  GREATEST(0,(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total-@winBonusCurrent))
							WHEN 'UpToPercentage' THEN @winBonusWinLockedCurrent - GREATEST(0,((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total-@winBonusCurrent))
							WHEN 'ReleaseBonus' THEN @winBonusWinLockedCurrent - GREATEST(0,(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total-@winBonusCurrent))
							ELSE 0
						END),IF (transfer_type.name='BonusWinLocked',0,@winBonusWinLockedCurrent)),0),
				  @winBonusLostCurrent:=ROUND(IF(bet_returns_type.name='Loss' OR gaming_bonus_instances.is_lost=1, @winBonusTemp, IF(@lostBonus<0,0,@lostbonus)), 0) AS lost_win_bonus,
			  @winBonusWinLockedLostCurrent:=ROUND(IF(gaming_bonus_instances.is_lost=1 AND is_free_bonus = 0, 
					  @winBonusWinLockedCurrent, IF(@lostBonusWinLocked<0,0,@lostBonusWinLocked))) AS lost_win_bonus_win_locked,     
			  @winRealBonusCurrent:=IF(is_free_bonus=1,
						(CASE transfer_type.name
						  WHEN 'All' THEN GREATEST((betBonus/betTotal)*winAmount - @winBonusLostCurrent,0)
						  WHEN 'Bonus' THEN GREATEST((betBonus/betTotal)*winAmount - @winBonusLostCurrent,0)
						  WHEN 'BonusWinLocked' THEN GREATEST((betBonus/betTotal)*winAmount - @winBonusLostCurrent,0)
						  WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, GREATEST((betBonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
						  WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total, GREATEST((betBonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
						  WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, GREATEST((betBonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
						  WHEN 'ReleaseAllBonus' THEN GREATEST((betBonus/betTotal)*winAmount - @winBonusLostCurrent,0)
						  ELSE 0
						END),
					IF(gaming_bonus_instances.is_secured=1, 
						(CASE transfer_type.name
						  WHEN 'All' THEN @winBonusAllTemp
						  WHEN 'Bonus' THEN @winBonusTemp
						  WHEN 'BonusWinLocked' THEN @winBonusWinLockedTemp
						  WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
						  WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
						  WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
						  WHEN 'ReleaseAllBonus' THEN @winBonusAllTemp
						  ELSE 0
						END),
					0.0)
			) AS win_real,

			  @winBonus:=@winBonus+@winBonusCurrent,
			  @winBonusWinLocked:=@winBonusWinLocked+@winBonusWinLockedCurrent,
			  @winBonusLost:=@winBonusLost+@winBonusLostCurrent,
			  @winBonusWinLockedLost:=@winBonusWinLockedLost+@winBonusWinLockedLostCurrent,
			  
			  IF (gaming_bonus_instances.is_secured OR wager_restrictions.max_bet_add_win_contr IS NULL OR is_free_bonus=1, 0, 
				ROUND((GREATEST(0, (play_bonus_instances.bet_bonus+play_bonus_instances.bet_bonus_win_locked)-wager_restrictions.max_bet_add_win_contr)/
				  (play_bonus_instances.bet_bonus+play_bonus_instances.bet_bonus_win_locked))*(@winBonusCurrent+@winBonusWinLockedCurrent)*gaming_bonus_rules.over_max_bet_win_contr_multiplier, 0)) AS add_wager_contribution,           
			  gaming_bonus_instances.bonus_amount_remaining, gaming_bonus_instances.current_win_locked_amount
			FROM gaming_game_plays_bonus_instances AS play_bonus_instances  
			JOIN gaming_bonus_instances ON play_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			JOIN gaming_bonus_types_bet_returns AS bet_returns_type ON gaming_bonus_rules.bonus_type_bet_return_id=bet_returns_type.bonus_type_bet_return_id
			JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
			LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON gaming_bonus_rules.bonus_rule_id=wager_restrictions.bonus_rule_id AND wager_restrictions.currency_id=currencyID
			WHERE play_bonus_instances.game_play_id=betGamePlayID
		  ) AS XX
		  ON DUPLICATE KEY UPDATE bonus_instance_id=VALUES(bonus_instance_id), win_real=VALUES(win_real), win_bonus=VALUES(win_bonus), 
													win_bonus_win_locked=VALUES(win_bonus_win_locked), lost_win_bonus=VALUES(lost_win_bonus),
													lost_win_bonus_win_locked=VALUES(lost_win_bonus_win_locked), client_stat_id=VALUES(client_stat_id);

		  
		  SELECT SUM(win_bonus) - SUM(lost_win_bonus) + SUM(win_bonus_win_locked - lost_win_bonus_win_locked) INTO FreeBonusAmount FROM gaming_game_plays_bonus_instances_wins 
		  JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_game_plays_bonus_instances_wins.bonus_instance_id
		  JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		  JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
		  WHERE game_play_win_counter_id = gamePlayWinCounterID AND (gaming_bonus_types_awarding.name='FreeBet' OR is_free_bonus = 1);

		  SET FreeBonusAmount = IFNULL(FreeBonusAmount,0);      
		  
		  UPDATE gaming_game_plays_bonus_instances AS pbi_update
		  JOIN gaming_game_plays_bonus_instances_wins AS PIU ON PIU.game_play_win_counter_id=gamePlayWinCounterID AND pbi_update.game_play_bonus_instance_id=PIU.game_play_bonus_instance_id 
		  JOIN gaming_bonus_instances ON pbi_update.bonus_instance_id=gaming_bonus_instances.bonus_instance_id AND PIU.game_play_bonus_instance_id=pbi_update.game_play_bonus_instance_id 
		  SET
			pbi_update.win_bonus=IFNULL(pbi_update.win_bonus,0)+PIU.win_bonus-PIU.lost_win_bonus, 
			pbi_update.win_bonus_win_locked=IFNULL(pbi_update.win_bonus_win_locked,0)+PIU.win_bonus_win_locked-PIU.lost_win_bonus_win_locked, 
			pbi_update.win_real=IFNULL(pbi_update.win_real,0)+PIU.win_real,
			pbi_update.lost_win_bonus=IFNULL(pbi_update.lost_win_bonus,0)+PIU.lost_win_bonus,
			pbi_update.lost_win_bonus_win_locked=IFNULL(pbi_update.lost_win_bonus_win_locked,0)+PIU.lost_win_bonus_win_locked,
			
			pbi_update.now_used_all=IF(ROUND(gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount+gaming_bonus_instances.reserved_bonus_funds
					+PIU.win_bonus+PIU.win_bonus_win_locked-PIU.lost_win_bonus-PIU.lost_win_bonus_win_locked,5)=0 AND (gaming_bonus_instances.open_rounds-1)<=0, 1, 0),
			pbi_update.add_wager_contribution=IFNULL(pbi_update.add_wager_contribution, 0)+PIU.add_wager_contribution;
		 
		  SET winBonus=@winBonus-@winBonusLost;
		  SET winBonusWinLocked=@winBonusWinLocked-@winBonusWinLockedLost;      
		  SET winReal = winAmount - (@winBonus + @winBonusWinLocked); 
		  
		  UPDATE gaming_bonus_instances
		  JOIN 
		  (
			SELECT play_bonus.bonus_instance_id, SUM(play_bonus_wins.win_real) AS win_real, SUM(play_bonus_wins.win_bonus) AS win_bonus, 
			  SUM(play_bonus_wins.win_bonus_win_locked) AS win_bonus_win_locked, SUM(IFNULL(play_bonus_wins.add_wager_contribution, 0)) AS add_wager_contribution, MIN(play_bonus.now_used_all) AS now_used_all,
			  SUM(play_bonus_wins.lost_win_bonus) AS lost_win_bonus,SUM(play_bonus_wins.lost_win_bonus_win_locked) AS lost_win_bonus_win_locked
			FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins
			JOIN gaming_game_plays_bonus_instances AS play_bonus ON play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND play_bonus_wins.game_play_bonus_instance_id=play_bonus.game_play_bonus_instance_id 
			
			GROUP BY play_bonus.bonus_instance_id
		  ) AS PB ON gaming_bonus_instances.bonus_instance_id=PB.bonus_instance_id  
		  SET 
			bonus_amount_remaining=bonus_amount_remaining+PB.win_bonus-PB.lost_win_bonus,
			current_win_locked_amount=current_win_locked_amount+PB.win_bonus_win_locked-PB.lost_win_bonus_win_locked,
			total_amount_won=total_amount_won+(PB.win_bonus+PB.win_bonus_win_locked),
			bonus_transfered_total=bonus_transfered_total+PB.win_real,
				open_rounds = GREATEST(open_rounds -1,0),
			
			bonus_wager_requirement=IF(gaming_bonus_instances.is_active, bonus_wager_requirement+add_wager_contribution, bonus_wager_requirement),
			bonus_wager_requirement_remain=IF(gaming_bonus_instances.is_active, bonus_wager_requirement_remain+add_wager_contribution, bonus_wager_requirement_remain),
			
			is_used_all=IF(PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-1)<=0, 1, 0),
			used_all_date=IF(PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-1)<=0 AND used_all_date IS NULL, NOW(), used_all_date),
			gaming_bonus_instances.is_active=IF(PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds-1)<=0, 0, gaming_bonus_instances.is_active);
		  
		  IF (@winBonusLost+@winBonusWinLockedLost>0) THEN
			
			INSERT INTO gaming_bonus_losts (bonus_instance_id, client_stat_id, bonus_lost_type_id, bonus_amount, bonus_win_locked_amount, extra_id, date_time_lost, session_id)
			SELECT bonus_instance_id, client_stat_id, gaming_bonus_lost_types.bonus_lost_type_id, IFNULL(SUM(lost_win_bonus),0), IFNULL(SUM(lost_win_bonus_win_locked),0), gamePlayWinCounterID, NOW(), sessionID
			FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins  
			JOIN gaming_bonus_lost_types ON 
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

  -- Tax functionality, not yet completed
  IF (taxEnabled) THEN
    SELECT clients_locations.country_id, gaming_countries.sports_tax INTO countryID, sportsTaxCountryEnabled  
    FROM clients_locations
    JOIN gaming_countries ON gaming_countries.country_id = countryID
    WHERE clients_locations.client_id = clientID;
  
	SET amountTaxPlayer = 0.0;
	SET amountTaxOperator = 0.0;
	SET amountTaxPlayerBonus = 0.0;
	SET amountTaxOperatorBonus = 0.0;
	SET taxModificationOperator = 0.0;
	SET taxModificationPlayer = 0.0;
	SET taxModificationPlayerBonus = 0.0;
	SET taxModificationOperatorBonus = 0.0;

    IF (countryID > 0 AND sportsTaxCountryEnabled = 1) THEN
	  
	  SELECT country_tax_id, bet_tax, win_tax, apply_net_deduction, tax_paid_by_operator_win INTO countryTaxID, taxBet, taxWin, applyNetDeduction, winTaxPaidByOperator
	  FROM gaming_country_tax AS gct
	  WHERE gct.country_id = countryID AND gct.is_current =  1 AND gct.licence_type_id = licenseTypeID AND gct.is_active = 1 LIMIT 1;

	  SET roundWinTotalFullReal = roundWinTotalReal + winReal;
	  SET roundWinTotalFullBonus = roundWinBonusAlready + roundWinBonusWinLockedAlready + winBonus + winBonusWinLocked;
	  SET roundBetTotalBonus = roundBetTotal - roundBetTotalReal;

      IF(closeRound || IsRoundFinished) THEN      
		  
		  IF(countryTaxID > 0) THEN
			  CALL TaxCalculateTax(roundWinTotalFullReal, roundWinTotalFullBonus, roundBetTotalReal, roundBetTotalBonus, applyNetDeduction, winTaxPaidByOperator, taxBet, taxWin, amountTaxOperator, amountTaxPlayer, amountTaxPlayerBonus, amountTaxOperatorBonus);
	    END IF; -- country TaxID
      END IF; -- close Round
    END IF; -- country ID

	  SET taxModificationOperator = amountTaxOperator - taxAlreadyChargedOperator;
	  SET taxModificationPlayer = amountTaxPlayer - taxAlreadyChargedPlayer;
	  SET taxModificationPlayerBonus = amountTaxPlayerBonus - taxAlreadyChargedPlayerBonus;
	  SET taxModificationOperatorBonus = amountTaxOperatorBonus - taxAlreadyChargedOperatorBonus;

	  -- Handle the reduction from bonus money
	  IF(taxModificationPlayerBonus <=  winBonusWinLocked) THEN
			SET taxReduceBonusWinLocked = taxModificationPlayerBonus;
			SET taxReduceBonus = 0.0;
	  ELSE 
			SET taxReduceBonusWinLocked = winBonusWinLocked;
			SET taxReduceBonus = taxModificationPlayerBonus - taxReduceBonusWinLocked;
	  END IF; -- Bonus Tax Balance seperation
  END IF; -- Tax enabled
  
  -- Update player's balance and statitics statistics  
  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID   
  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET 
	-- client stats
    gcs.total_real_won=gcs.total_real_won+winReal, gcs.current_real_balance=gcs.current_real_balance+(winReal - taxModificationPlayer), 
    gcs.total_bonus_won=gcs.total_bonus_won+winBonus, gcs.current_bonus_balance=gcs.current_bonus_balance+winBonus - taxReduceBonus, 
    gcs.total_bonus_win_locked_won=gcs.total_bonus_win_locked_won+winBonusWinLocked, gcs.current_bonus_win_locked_balance=current_bonus_win_locked_balance+winBonusWinLocked - taxReduceBonusWinLocked, 
    gcs.total_real_won_base=gcs.total_real_won_base+(winReal/exchangeRate), gcs.total_bonus_won_base=gcs.total_bonus_won_base+((winBonus+winBonusWinLocked)/exchangeRate), gcs.total_tax_paid = gcs.total_tax_paid + taxModificationPlayer, gcs.total_tax_paid_bonus = gcs.total_tax_paid_bonus + taxModificationPlayerBonus,
    -- client session
    gcsession.total_win=gcsession.total_win+winAmount, gcsession.total_win_base=gcsession.total_win_base+winTotalBase, gcsession.total_bet_placed=gcsession.total_bet_placed+betTotal, gcsession.total_win_real=gcsession.total_win_real+winReal, gcsession.total_win_bonus=gcsession.total_win_bonus+winBonus+winBonusWinLocked,
	-- wager status
    gcws.num_wins=gcws.num_wins+IF(winAmount>0, 1, 0), gcws.total_real_won=gcws.total_real_won+winReal, gcws.total_bonus_won=gcws.total_bonus_won+winBonus+winBonusWinLocked
  WHERE gcs.client_stat_id=clientStatID;  
  
  -- Insert into gaming_plays (main transaction)
  SET @messageType=IF(winAmount=0, 'SportsLoss', IF (winAmount < 0, 'SportsAdjustment', IF(isSBSingle='Single','SportsWin','SportsWinMult')));
  SET @transactionType=IF(winAmount>=0, 'Win', 'WinAdjustment');
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_free_bet, amount_other, bonus_lost, bonus_win_locked_lost, 
   jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, is_win_placed, 
   balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, 
   sb_extra_id, sb_bet_id, license_type_id, device_type, pending_bet_real, pending_bet_bonus, 
   amount_tax_operator, amount_tax_player, amount_tax_player_bonus, amount_tax_operator_bonus, 
   loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus) 
  SELECT winAmount, winTotalBase, exchangeRate, winReal, winBonus, winBonusWinLocked, FreeBonusAmount, 0, @winBonusLost, ROUND(@winBonusWinLockedLost+@winBonusLostFromPrevious, 0), 
   0, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 
   gcs.current_real_balance, ROUND(gcs.current_bonus_balance+gcs.current_bonus_win_locked_balance, 0), gcs.current_bonus_win_locked_balance, currencyID, numTransactions+1, gaming_game_play_message_types.game_play_message_type_id, 
   betSBExtraID, sbBetID, gaming_game_plays.license_type_id, gaming_game_plays.device_type, gcs.pending_bets_real, gcs.pending_bets_bonus, 
   taxModificationOperator, taxModificationPlayer, taxModificationPlayerBonus, taxModificationOperatorBonus, 
   0, gcs.current_loyalty_points, 0, gcs.total_loyalty_points_given_bonus - gcs.total_loyalty_points_used_bonus
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats AS gcs ON gaming_payment_transaction_type.name=@transactionType AND gcs.client_stat_id=clientStatID
  JOIN gaming_game_plays ON gaming_game_plays.game_play_id=betGamePlayID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=@messageType;
  
  SET gamePlayID=LAST_INSERT_ID();

  -- Update ring fencing balance and statistics
  CALL GameUpdateRingFencedBalances(clientStatID, gamePlayID);

  IF (disallowNegativeBalance AND badDebtRealAmount > 0) THEN

	UPDATE gaming_client_stats AS gcs
	SET gcs.current_real_balance=gcs.current_real_balance+badDebtRealAmount, gcs.total_bad_debt=gcs.total_bad_debt+badDebtRealAmount
	WHERE gcs.client_stat_id=clientStatID;  

	INSERT INTO gaming_transactions
    (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, 
	 timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, 
	 extra_id, pending_bet_real, pending_bet_bonus, withdrawal_pending_after, loyalty_points_bonus, loyalty_points_after_bonus) 
    SELECT gaming_payment_transaction_type.payment_transaction_type_id, badDebtRealAmount, ROUND(badDebtRealAmount/exchangeRate,5), gaming_client_stats.currency_id, exchangeRate, badDebtRealAmount, 0, 0, 0, 
	  NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, 
	  gamePlayID, pending_bets_real, pending_bets_bonus, withdrawal_pending_amount, 0, (gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
    FROM gaming_client_stats 
    JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
    JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='BadDebt'
    WHERE gaming_client_stats.client_stat_id=clientStatID;  
    
    SET badDeptTransactionID=LAST_INSERT_ID();
  
    INSERT INTO gaming_game_plays 
    (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, 
     payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, 
     platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, extra_id, sb_extra_id, sb_bet_id, license_type_id) 
    SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, 
	 payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, 
     platform_type_id, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, gamePlayID, betSBExtraID, sbBetID, 3
    FROM gaming_transactions
    WHERE transaction_id=badDeptTransactionID;
	
    SET badDeptGamePlayID=LAST_INSERT_ID();

	CALL GameUpdateRingFencedBalances(clientStatID, badDeptGamePlayID);

  END IF;
  
  -- update bet and win bonus counters
  UPDATE gaming_game_plays_win_counter_bets
  SET win_game_play_id=gamePlayID
  WHERE game_play_win_counter_id=gamePlayWinCounterID;

  IF (updateGamePlayBonusInstanceWin) THEN
    UPDATE gaming_game_plays_bonus_instances_wins SET win_game_play_id=gamePlayID WHERE game_play_win_counter_id=gamePlayWinCounterID;
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
  JOIN gaming_game_plays_sb AS bet_play_sb ON bet_play_sb.game_play_sb_id=betGamePlaySBID 
  WHERE gaming_game_plays.game_play_id=gamePlayID;
 
  -- Update play limits current status (loss only) 
  IF (winAmount > 0 AND playLimitEnabled) THEN
    CALL PlayLimitsUpdate(clientStatID, licenseType, winAmount, 0);
  END IF;
  
  -- Update the round statistics and close it
  UPDATE gaming_game_rounds
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET 
    win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+winTotalBase,5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus, 
    win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked,win_free_bet = win_free_bet+FreeBonusAmount, win_bet_diffence_base=win_total_base-bet_total_base,
    bonus_lost=bonus_lost+@winBonusLost, bonus_win_locked_lost=bonus_win_locked_lost+@winBonusWinLockedLost+@winBonusLostFromPrevious, 
    date_time_end= IF (closeRound, NOW(), date_time_end), is_round_finished=IF (closeRound, 1, is_round_finished), num_transactions=num_transactions+1, 
    balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance, amount_tax_operator = amountTaxOperator, amount_tax_player = amountTaxPlayer , amount_tax_player_bonus = amountTaxPlayerBonus, amount_tax_operator_bonus = amountTaxOperatorBonus
  WHERE game_round_id=gameRoundID;   

  -- Check if bonus is secured
  IF (@isBonusSecured OR usedFreeBonus) THEN
	CALL BonusConvertWinningsAfterSecuredDate(gamePlayID,  gamePlayWinCounterID);
  END IF;
  
  -- Set output variables
  SET gamePlayIDReturned=gamePlayID;
  SET statusCode=0;

  IF (winAmount<0) THEN
	SELECT badDeptGamePlayID AS game_play_id, IF(disallowNegativeBalance, badDebtRealAmount, 0.00000) AS bad_dept_real_amount;
  END IF;
    
END root$$

DELIMITER ;

