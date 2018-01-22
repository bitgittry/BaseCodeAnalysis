DROP procedure IF EXISTS `PlaceSBWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceSBWin`(clientStatID BIGINT, betGamePlayID BIGINT, winAmount DECIMAL(18, 5), betType VARCHAR(80), liveBetType TINYINT(4), deviceType TINYINT(4), closeRound TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN

  DECLARE betAmount, exchangeRate DECIMAL(18, 5) DEFAULT 0;
  DECLARE winTotalBase, winReal, winBonus, winBonusWinLocked, roundBetTotal, roundWinTotal, betReal, betBonus, betBonusLost, betTotal,FreeBonusAmount, amountTaxPlayer, amountTaxOperator, taxBet, taxWin, 
			roundWinTotalFullReal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, taxModificationOperator, taxModificationPlayer, roundBetTotalReal, roundWinTotalReal, taxOnReturn, taxAmount, roundWinTotalFull DECIMAL(18, 5) DEFAULT 0;
  DECLARE amountTaxPlayerBonus, taxAlreadyChargedPlayerBonus, taxModificationPlayerBonus, roundWinBonusAlready, roundWinBonusWinLockedAlready, roundWinTotalFullBonus, taxModificationOperatorBonus, taxAlreadyChargedOperatorBonus, roundBetTotalBonus, amountTaxOperatorBonus, taxReduceBonus, taxReduceBonusWinLocked DECIMAL(18, 5) DEFAULT 0;
  DECLARE gameRoundID, sessionID, gameManufacturerID, clientStatIDCheck, clientID, currencyID, gamePlayID, gamePlayWinCounterID, betGamePlayIDCheck, sbBetID, betMessageTypeID, betSBExtraID, countryID, countryTaxID, gameSessionID  BIGINT DEFAULT -1;
  DECLARE dateTimeWin DATETIME DEFAULT NULL;
  DECLARE bonusEnabledFlag, playLimitEnabled, isRoundFinished, updateGamePlayBonusInstanceWin, applyNetDeduction, winTaxPaidByOperator, taxEnabled, sportsTaxCountryEnabled,usedFreeBonus TINYINT(1) DEFAULT 0;
  DECLARE numTransactions INT DEFAULT 0;
  DECLARE licenseType, taxAppliedOnType VARCHAR(20) DEFAULT NULL;
  DECLARE clientWagerTypeID INT DEFAULT 3; 
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
  DECLARE taxCycleID INT DEFAULT NULL;
  
  SET gamePlayIDReturned=NULL;
  SET licenseType='sportsbook';
  
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, IFNULL(gs3.value_bool,0) AS vb3
    INTO playLimitEnabled, bonusEnabledFlag, taxEnabled
    FROM gaming_settings gs1 
    JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	LEFT JOIN gaming_settings gs3 ON (gs3.name='TAX_ON_GAMEPLAY_ENABLED')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
  SELECT client_stat_id, client_id, gaming_client_stats.currency_id INTO clientStatIDCheck, clientID, currencyID
  FROM gaming_client_stats 
  WHERE client_stat_id=clientStatID
  FOR UPDATE;
  
  SELECT country_id INTO countryID FROM clients_locations WHERE clients_locations.client_id=clientID AND clients_locations.is_primary=1; 
  SELECT session_id INTO sessionID FROM sessions_main WHERE extra_id=clientID AND is_latest;
  
  SELECT exchange_rate INTO exchangeRate FROM gaming_operator_currency WHERE gaming_operator_currency.currency_id=currencyID;
  
  IF (clientStatIDCheck=-1) THEN 
    SET statusCode = 1;
    LEAVE root;
  END IF;
  
  
  SELECT game_play_id, sb_bet_id, game_round_id, game_manufacturer_id, amount_total, bonus_lost, amount_real, amount_bonus+amount_bonus_win_locked, sb_extra_id, game_play_message_type_id 
  INTO betGamePlayIDCheck, sbBetID, gameRoundID, gameManufacturerID, betTotal, betBonusLost, betReal, betBonus, betSBExtraID, betMessageTypeID 
  FROM gaming_game_plays
  WHERE game_play_id=betGamePlayID AND is_win_placed=0 AND payment_transaction_type_id=12 
  FOR UPDATE;
  
  SELECT num_transactions, bet_total, win_total, is_round_finished, amount_tax_operator, amount_tax_player, amount_tax_player_bonus, amount_tax_operator_bonus, bet_real, win_real, win_bonus, win_bonus_win_locked
  INTO numTransactions, roundBetTotal, roundWinTotal, isRoundFinished, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, taxAlreadyChargedPlayerBonus, taxAlreadyChargedOperatorBonus, roundBetTotalReal, roundWinTotalReal, roundWinBonusAlready, roundWinBonusWinLockedAlready
  FROM gaming_game_rounds
  WHERE game_round_id=gameRoundID;
    SET winBonus = 0; 
 
  IF (betGamePlayIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SET @winBonusLost=0;
  SET @winBonusWinLockedLost=0;
  SET @numPlayBonusInstances=0;  
  SET @updateBonusInstancesWins=0;  
  
  IF (bonusEnabledFlag) THEN 
    
    
    SET winBonusWinLocked = 0; 
    SET winBonus = 0;
    SET winReal = winAmount; 
    
    
    
    SELECT COUNT(*),MAX(is_free_bonus) INTO @numPlayBonusInstances,usedFreeBonus
    FROM gaming_game_plays_bonus_instances 
	JOIN gaming_bonus_instances gbi ON gbi.bonus_instance_id = gaming_game_plays_bonus_instances.bonus_instance_id
	JOIN gaming_bonus_rules gbr ON gbi.bonus_rule_id = gbr.bonus_rule_id
    WHERE game_play_id=betGamePlayID; 
    
    IF (@numPlayBonusInstances>0) THEN
    
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
          @winBonusAllTemp:=ROUND(((bet_bonus+bet_bonus_win_locked)/betTotal)*winAmount,0), 
          @winBonusTemp:=IF(bet_returns_type.name!='BonusWinLocked' , LEAST(ROUND((bet_bonus/betTotal)*winAmount,0), bet_bonus), 0),
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
					  WHEN 'All' THEN GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
					  WHEN 'Bonus' THEN GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
					  WHEN 'BonusWinLocked' THEN GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
					  WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
					  WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total, GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
					  WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)))
					  WHEN 'ReleaseAllBonus' THEN GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0)
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
      ON DUPLICATE KEY UPDATE bonus_instance_id=VALUES(bonus_instance_id), win_real=VALUES(win_real), win_bonus=VALUES(win_bonus), win_bonus_win_locked=VALUES(win_bonus_win_locked), lost_win_bonus=VALUES(lost_win_bonus), lost_win_bonus_win_locked=VALUES(lost_win_bonus_win_locked), client_stat_id=VALUES(client_stat_id);
      

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
    ELSE 
      
      IF (betReal=0 AND betBonus>0 AND winReal>0) THEN
        SET @winBonusLost=winReal;
        INSERT INTO gaming_game_rounds_misc (game_round_id, timestamp, win_real)
        VALUES (gameRoundID, NOW(), winReal);
        SET winReal=0;
      END IF;
      
    END IF; 
    
  ELSE 
    SET winReal=winAmount;
    SET winBonus=0; SET winBonusWinLocked=0; 
	SET FreeBonusAmount =0;
    SET @winBonusLost=0; SET @winBonusWinLockedLost=0;
  END IF; 
    
  
  SET @winBonusLostFromPrevious=IFNULL(ROUND(((betBonusLost)/betTotal)*winAmount,5), 0);        
  SET winReal=winReal-@winBonusLostFromPrevious;  
  SET winReal=IF(winReal<0, 0, winReal);
 
  
  SET winTotalBase=ROUND(winAmount/exchangeRate,5);


-- TAX
  IF(closeRound || IsRoundFinished) THEN

	SET roundWinTotalFull = roundWinTotalReal + winReal;
	-- betTotal is the sum of gaming_games_plays.amount_total of the bets in this round not processed (is_win_place = 0)
	CALL TaxCalculateTax(3, clientStatID, clientID, roundWinTotalFull, betReal, taxAmount, taxAppliedOnType, taxCycleID);

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
  
  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID   
  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET 
    gcs.total_real_won=gcs.total_real_won+winReal, gcs.current_real_balance=gcs.current_real_balance+(winReal - taxOnReturn), 
    gcs.total_bonus_won=gcs.total_bonus_won+winBonus, gcs.current_bonus_balance=gcs.current_bonus_balance+winBonus - taxReduceBonus, 
    gcs.total_bonus_win_locked_won=gcs.total_bonus_win_locked_won+winBonusWinLocked, gcs.current_bonus_win_locked_balance=current_bonus_win_locked_balance+winBonusWinLocked - taxReduceBonusWinLocked, 
    gcs.total_real_won_base=gcs.total_real_won_base+(winReal/exchangeRate), gcs.total_bonus_won_base=gcs.total_bonus_won_base+((winBonus+winBonusWinLocked)/exchangeRate), gcs.total_tax_paid = gcs.total_tax_paid + taxOnReturn, -- add to tax paid if is onReturn only! If is deferred When we close tax cycle we update this
	gcs.total_tax_paid_bonus = gcs.total_tax_paid_bonus + taxModificationPlayerBonus,
    
    gcsession.total_win=gcsession.total_win+winAmount, gcsession.total_win_base=gcsession.total_win_base+winTotalBase, gcsession.total_bet_placed=gcsession.total_bet_placed+betTotal, gcsession.total_win_real=gcsession.total_win_real+winReal, gcsession.total_win_bonus=gcsession.total_win_bonus+winBonus+winBonusWinLocked,
    
    gcws.num_wins=gcws.num_wins+IF(winAmount>0, 1, 0), gcws.total_real_won=gcws.total_real_won+winReal, gcws.total_bonus_won=gcws.total_bonus_won+winBonus+winBonusWinLocked,
	gcs.deferred_tax = @cumulativeDeferredTax := (gcs.deferred_tax + IF(taxAppliedOnType ='Deferred', taxAmount, 0)) -- cumulative deferred tax to later on (when we need to close tax cycle) transfer to the respective tax cycle 
  WHERE gcs.client_stat_id=clientStatID;  
  
  
    
   
  SET @messageType=IF(betType='Single','SportsWin','SportsWinMult');
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, sb_extra_id, sb_bet_id, license_type_id, device_type, pending_bet_real, pending_bet_bonus, amount_tax_operator, amount_tax_player, amount_tax_player_bonus, amount_tax_operator_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, tax_cycle_id, cumulative_deferred_tax) 
  SELECT winAmount, winTotalBase, exchangeRate, winReal, winBonus, winBonusWinLocked,FreeBonusAmount, @winBonusLost, ROUND(@winBonusWinLockedLost+@winBonusLostFromPrevious,0), 0, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, current_real_balance, ROUND(current_bonus_balance+current_bonus_win_locked_balance,0), current_bonus_win_locked_balance, currencyID, numTransactions+1, game_play_message_type_id, betSBExtraID, sbBetID, licenseTypeID, deviceType, pending_bets_real, pending_bets_bonus, taxModificationOperator, taxModificationPlayer, taxModificationPlayerBonus, taxModificationOperatorBonus, 0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`), taxCycleID, gaming_client_stats.deferred_tax 
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='Win' AND gaming_client_stats.client_stat_id=clientStatID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=@messageType;
  
  SET gamePlayID=LAST_INSERT_ID();

  CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);
  
  UPDATE gaming_game_plays_win_counter_bets
  SET win_game_play_id=gamePlayID
  WHERE game_play_win_counter_id=gamePlayWinCounterID;

  IF (updateGamePlayBonusInstanceWin) THEN
    UPDATE gaming_game_plays_bonus_instances_wins SET win_game_play_id=gamePlayID WHERE game_play_win_counter_id=gamePlayWinCounterID;
  END IF;
  
  IF (betType='Single') THEN
    SELECT sb_multiple_type_id INTO @singleMultTypeID FROM gaming_sb_multiple_types WHERE name='Single' AND game_manufacturer_id=gameManufacturerID;
    INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units)
    SELECT gaming_game_plays.game_play_id, gaming_game_plays.payment_transaction_type_id, gaming_game_plays.amount_total, gaming_game_plays.amount_total_base, gaming_game_plays.amount_real, gaming_game_plays.amount_real/exchange_rate, gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/exchange_rate, gaming_game_plays.timestamp, gaming_game_plays.exchange_rate, gaming_game_plays.game_manufacturer_id, clientID, clientStatID, currencyID, countryID,
      gaming_game_plays.round_transaction_no, gaming_sb_sports.sb_sport_id, gaming_sb_regions.sb_region_id, gaming_sb_groups.sb_group_id, gaming_sb_events.sb_event_id, gaming_sb_markets.sb_market_id, gaming_sb_selections.sb_selection_id, gaming_game_plays.sb_bet_id, @singleMultTypeID, liveBetType, deviceType, 0
    FROM gaming_game_plays
    JOIN gaming_sb_selections ON gaming_game_plays.sb_extra_id=gaming_sb_selections.sb_selection_id
    JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    JOIN gaming_sb_events ON gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_groups ON gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    JOIN gaming_sb_regions ON gaming_sb_groups.sb_region_id=gaming_sb_regions.sb_region_id
    JOIN gaming_sb_sports ON gaming_sb_regions.sb_sport_id=gaming_sb_sports.sb_sport_id
    WHERE gaming_game_plays.game_play_id=gamePlayID; 
  ELSE
    INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units)
    SELECT gaming_game_plays.game_play_id, gaming_game_plays.payment_transaction_type_id, gaming_game_plays.amount_total/bet_multiple.num_singles, gaming_game_plays.amount_total_base/bet_multiple.num_singles, gaming_game_plays.amount_real/bet_multiple.num_singles, (gaming_game_plays.amount_real/exchange_rate)/bet_multiple.num_singles, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/bet_multiple.num_singles, ((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/exchange_rate)/bet_multiple.num_singles, 
      gaming_game_plays.timestamp, gaming_game_plays.exchange_rate, gaming_game_plays.game_manufacturer_id, clientID, clientStatID, currencyID, countryID, 
      gaming_game_plays.round_transaction_no, gaming_sb_sports.sb_sport_id, gaming_sb_regions.sb_region_id, gaming_sb_groups.sb_group_id, gaming_sb_events.sb_event_id, gaming_sb_markets.sb_market_id, gaming_sb_selections.sb_selection_id, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, liveBetType, deviceType, 0
    FROM gaming_game_plays
    JOIN gaming_sb_bet_multiples AS bet_multiple ON gaming_game_plays.sb_bet_id=bet_multiple.sb_bet_id AND gaming_game_plays.sb_extra_id=bet_multiple.sb_multiple_type_id
    JOIN gaming_sb_bet_multiples_singles AS mult_singles ON bet_multiple.sb_bet_multiple_id=mult_singles.sb_bet_multiple_id
    JOIN gaming_sb_selections ON mult_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
    JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    JOIN gaming_sb_events ON gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_groups ON gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    JOIN gaming_sb_regions ON gaming_sb_groups.sb_region_id=gaming_sb_regions.sb_region_id
    JOIN gaming_sb_sports ON gaming_sb_regions.sb_sport_id=gaming_sb_sports.sb_sport_id
    WHERE gaming_game_plays.game_play_id=gamePlayID; 
  END IF;
  
  IF (winAmount > 0 AND playLimitEnabled) THEN
    CALL PlayLimitsUpdate(clientStatID, licenseType, winAmount, 0);
  END IF;
  
  UPDATE gaming_game_plays SET is_win_placed=1, game_play_id_win=gamePlayID WHERE game_play_id=betGamePlayID;
  
  UPDATE gaming_game_rounds
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET 
    win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+winTotalBase,5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus, 
    win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked,win_free_bet = win_free_bet+FreeBonusAmount, win_bet_diffence_base=win_total_base-bet_total_base,
    bonus_lost=bonus_lost+@winBonusLost, bonus_win_locked_lost=bonus_win_locked_lost+@winBonusWinLockedLost+@winBonusLostFromPrevious, 
    date_time_end= IF (closeRound, NOW(), date_time_end), is_round_finished=IF (closeRound, 1, is_round_finished), num_transactions=num_transactions+1, 
    balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance, amount_tax_operator = amountTaxOperator, amount_tax_player = taxAmount , amount_tax_player_bonus = amountTaxPlayerBonus, amount_tax_operator_bonus = amountTaxOperatorBonus,
	tax_cycle_id = taxCycleID,
	cumulative_deferred_tax = @cumulativeDeferredTax
  WHERE game_round_id=gameRoundID;   

  IF (@isBonusSecured OR usedFreeBonus) THEN
	CALL BonusConvertWinningsAfterSecuredDate(gamePlayID,gamePlayWinCounterID);
  END IF;
  
  SET gamePlayIDReturned=gamePlayID;
  SET statusCode=0;
    
END root$$

DELIMITER ;

