DROP procedure IF EXISTS `PlaceJackpotWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceJackpotWin`(
  gameRoundID BIGINT, sessionID BIGINT, gameSessionID BIGINT, winAmount DECIMAL(18, 5), transactionRef VARCHAR(80), 
  returnData TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root: BEGIN
     -- jackpot flow
  
  DECLARE winTotalBase, winReal, winBonus, winBonusWinLocked DECIMAL(18, 5);
  DECLARE exchangeRate, taxAmount, taxOnReturn, betReal, betTotal, prevWinRealTotal DECIMAL(18, 5) DEFAULT 0;
  DECLARE gameRoundIDCheck, gameID, gameManufacturerID, operatorGameID, clientStatID, clientID, clientStatIDCheck, 
	currencyID, gamePlayID, gamePlayWinCounterID, prevWinGamePlayID BIGINT DEFAULT -1;
  DECLARE bonusEnabledFlag, disableBonusMoney, playLimitEnabled, loyaltyPointsEnabled, 
	taxEnabled, fingFencedEnabled, ruleEngineEnabled TINYINT(1) DEFAULT 0;
  DECLARE numTransactions, numBetsNotProcessed INT DEFAULT 0;
  DECLARE taxAppliedOnType, licenseType VARCHAR(20) DEFAULT NULL;
  DECLARE taxCycleID INT DEFAULT NULL;
  DECLARE licenseTypeID TINYINT(4) DEFAULT 1;
  
  SET gamePlayIDReturned=NULL;
  
   SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, 
	gs4.value_bool as vb4, IFNULL(gs5.value_bool,0) as vb5, IFNULL(gs6.value_bool,0) AS vb6
  INTO playLimitEnabled, bonusEnabledFlag, loyaltyPointsEnabled, 
	taxEnabled, fingFencedEnabled, ruleEngineEnabled
  FROM gaming_settings gs1 
    STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	STRAIGHT_JOIN gaming_settings gs3 ON (gs3.name='LOYALTY_POINTS_WAGER_ENABLED')
    STRAIGHT_JOIN gaming_settings gs4 ON (gs4.name='TAX_ON_GAMEPLAY_ENABLED')
    STRAIGHT_JOIN gaming_settings gs5 ON (gs5.name='RING_FENCED_ENABLED')
    STRAIGHT_JOIN gaming_settings gs6 ON (gs6.name='RULE_ENGINE_ENABLED')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
  SELECT game_round_id, game_id, game_manufacturer_id, operator_game_id, client_stat_id, num_transactions, win_real
  INTO   gameRoundIDCheck, gameID, gameManufacturerID, operatorGameID, clientStatID, numTransactions, prevWinRealTotal
  FROM gaming_game_rounds
  WHERE game_round_id=gameRoundID;

  SELECT client_stat_id, client_id, gaming_client_stats.currency_id, exchange_rate 
  INTO clientStatIDCheck, clientID, currencyID, exchangeRate
  FROM gaming_client_stats 
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
  WHERE client_stat_id=clientStatID
  FOR UPDATE;
  
  SELECT disable_bonus_money, gaming_games.license_type_id, gaming_license_type.name
  INTO disableBonusMoney, licenseTypeID, licenseType
  FROM gaming_operator_games 
  STRAIGHT_JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id
  STRAIGHT_JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_games.license_type_id
  WHERE gaming_operator_games.operator_game_id=operatorGameID;
  
  IF (gameRoundIDCheck = -1 OR clientStatIDCheck=-1) THEN 
    SET statusCode = 1;
    LEAVE root;
  END IF;
       
  
  SET winBonus = 0; 
  SET winBonusWinLocked = 0; 
  SET winReal = winAmount; 
  
  -- This part is just to retrieve the bet amount for tax purposes
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
  
  SELECT SUM(amount_real)
  INTO betReal
  FROM gaming_game_plays_win_counter_bets AS win_counter_bets
  STRAIGHT_JOIN gaming_game_plays ON 
	win_counter_bets.game_play_win_counter_id=gamePlayWinCounterID AND 
	gaming_game_plays.game_play_id=win_counter_bets.game_play_id;

  IF (numBetsNotProcessed=0) THEN
    SET betTotal=0;    
  END IF;
  
  -- TAX
  -- betTotal is the sum of gaming_games_plays.amount_total of the bets in this round not processed (is_win_place = 0)
  IF (taxEnabled) THEN
  
	  CALL TaxCalculateTax(licenseTypeID, clientStatID, clientID, winReal + prevWinRealTotal, betReal, taxAmount, taxAppliedOnType, taxCycleID);

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
			IF (taxAmount > 0 AND ISNULL(taxCycleID)) THEN
				SET statusCode = 1;
				LEAVE root;
			END IF;

			IF (taxAmount > 0) THEN			
				UPDATE gaming_tax_cycles 
				SET cycle_win_amount_real = cycle_win_amount_real + winReal -- bet amount not added
				WHERE tax_cycle_id = taxCycleID;

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
  END IF; -- /TAX 
  
  SET @cumulativeDeferredTax:=0;

  UPDATE gaming_client_stats 
  SET 
    total_real_won=total_real_won+winReal, current_real_balance=current_real_balance+(winReal - taxOnReturn), 
    total_bonus_won=total_bonus_won+winBonus, current_bonus_balance=current_bonus_balance+winBonus, 
    total_bonus_win_locked_won=total_bonus_win_locked_won+winBonusWinLocked, current_bonus_win_locked_balance=current_bonus_win_locked_balance+winBonusWinLocked,
    total_tax_paid = total_tax_paid + taxOnReturn, -- add to tax paid if is onReturn only! If is deferred When we close tax cycle we update this
	deferred_tax = @cumulativeDeferredTax := (deferred_tax + IF(taxAppliedOnType ='Deferred', taxAmount, 0)) -- cumulative deferred tax to later on (when we need to close tax cycle) transfer to the respective tax cycle 
  WHERE client_stat_id=clientStatID;
  
  SET winTotalBase=ROUND(winAmount/exchangeRate,5);
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, currency_id, round_transaction_no, game_play_message_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, amount_tax_player, tax_cycle_id, cumulative_deferred_tax) 
  SELECT winAmount, winTotalBase, exchangeRate, winReal, winBonus, winBonusWinLocked, NOW(), gameID, gameManufacturerID, operatorGameID, clientID, clientStatID, sessionID, gameSessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, currencyID, numTransactions+1, game_play_message_type_id,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`), taxAmount, taxCycleID, gaming_client_stats.deferred_tax 
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='PJWin' AND gaming_client_stats.client_stat_id=clientStatID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name='PJWin';
  
  SET gamePlayID=LAST_INSERT_ID();

  IF (fingFencedEnabled) THEN
	CALL GameUpdateRingFencedBalances(clientStatID, gamePlayID);  
  END IF;
  
  UPDATE gaming_game_rounds
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET 
    win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+winTotalBase,5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus, 
    win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked, win_bet_diffence_base=win_total_base-bet_total_base, 
    jackpot_win=jackpot_win+winAmount,
    date_time_end=NOW(), is_round_finished=1, num_transactions=num_transactions+1, 
    balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance,
	amount_tax_player = amount_tax_player + taxAmount,
	tax_cycle_id = taxCycleID,
	cumulative_deferred_tax = @cumulativeDeferredTax
  WHERE gaming_game_rounds.game_round_id=gameRoundID;  
  
  UPDATE gaming_game_sessions
  SET total_win=total_win+winAmount, total_win_base=total_win_base+winTotalBase   
  WHERE game_session_id=gameSessionID;
  
  UPDATE gaming_client_sessions 
  SET total_win=total_win+winAmount, total_win_base=total_win_base+winTotalBase  
  WHERE session_id=sessionID;
  
  INSERT INTO `accounting_dc_notes` (dc_type, dc_note_type_id, timestamp, amount, amount_base, notes, date_created, user_id, client_stat_id, is_approved)
  SELECT 'credit', dc_note_type_id, NOW(), winTotalBase, winTotalBase, 'Jackpot refund from manufacturer', NOW(), 0, clientStatID, 0
  FROM accounting_dc_note_types WHERE note_type = 'JackpotRefund';
  
  IF (winAmount > 0 AND playLimitEnabled) THEN
    CALL PlayLimitsUpdateWithGame(sessionID, clientStatID, licenseType, winAmount, 0, gameID);
  END IF;
  
  IF (returnData) THEN
    CALL PlayReturnData(gamePlayID, gameRoundID, clientStatID , operatorGameID, 0);
  END IF;

  SET gamePlayIDReturned=gamePlayID;
  SET statusCode=0;
    
END root$$

DELIMITER ;

