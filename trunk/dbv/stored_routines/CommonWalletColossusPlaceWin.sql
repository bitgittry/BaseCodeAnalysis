DROP procedure IF EXISTS `CommonWalletColossusPlaceWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletColossusPlaceWin`(clientStatID BIGINT, extPoolID BIGINT, CWTransactionID BIGINT, WinAmount DECIMAL(18,5), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN

	DECLARE betAmount, exchangeRate, betTotal, betBonusLost, betReal, betBonus,winReal, winBonus,winBonusWinLocked,FreeBonusAmount,winTotalBase,bonusTotal,WinAmountPoolCurrency, taxOnReturn, taxAmount DECIMAL(18, 5) DEFAULT 0;
	DECLARE  roundBetTotal, roundWinTotal,taxAlreadyChargedOperator, taxAlreadyChargedPlayer, taxAlreadyChargedPlayerBonus,taxAlreadyChargedOperatorBonus,
		 roundBetTotalReal, roundWinTotalReal, roundWinBonusAlready, roundWinBonusWinLockedAlready,amountTaxPlayer,amountTaxOperator, roundWinTotalFull, taxBet, taxWin, applyNetDeduction, winTaxPaidByOperator,
		amountTaxPlayerBonus,amountTaxOperatorBonus,taxModificationOperator,taxModificationPlayer,taxModificationPlayerBonus,taxModificationOperatorBonus,
		roundWinTotalFullReal, roundWinTotalFullBonus, roundBetTotalBonus,taxReduceBonusWinLocked, taxReduceBonus DECIMAL(18, 5) DEFAULT 0;
	DECLARE clientStatIDCheck, clientID, currencyID, countryID, gamePlayID, gameRoundID, gameManufacturerID,gamePlayWinCounterID,countryTaxID,sessionID,clientWagerTypeID, licenseTypeID,poolID,
			betGamePlayID, gameSessionID BIGINT DEFAULT -1;
	DECLARE numTransactions INT DEFAULT 0;
	DECLARE licenseType, taxAppliedOnType VARCHAR(20) DEFAULT NULL;
	DECLARE playLimitEnabled, bonusEnabledFlag, taxEnabled,isRoundFinished,updateGamePlayBonusInstanceWin,sportsTaxCountryEnabled TINYINT(1) DEFAULT 0;
	DECLARE taxCycleID INT DEFAULT NULL;

	SET statusCode =0;
	SET clientWagerTypeID = 6;
	SET licenseType = 'poolbetting';
	SET licenseTypeID = 5;

	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, IFNULL(gs3.value_bool,0) AS vb3
	INTO playLimitEnabled, bonusEnabledFlag, taxEnabled
	FROM gaming_settings gs1 
	JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	LEFT JOIN gaming_settings gs3 ON (gs3.name='TAX_ON_GAMEPLAY_ENABLED')
	WHERE gs1.name='PLAY_LIMIT_ENABLED';

	SELECT client_stat_id, gaming_clients.client_id, gaming_client_stats.currency_id,country_id,exchange_rate,sessions_main.session_id 
	INTO clientStatIDCheck, clientID, currencyID, countryID,exchangeRate,sessionID
	FROM gaming_client_stats 
	JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id
	JOIN clients_locations ON clients_locations.client_id = gaming_clients.client_id
	LEFT JOIN sessions_main ON extra_id = gaming_client_stats.client_stat_id AND is_latest AND sessions_main.status_code=1 
	JOIN gaming_operator_currency ON gaming_operator_currency.currency_id = gaming_client_stats.currency_id
	WHERE client_stat_id=clientStatID
	FOR UPDATE;

	IF (clientStatIDCheck=-1) THEN 
		SET statusCode = 1;
		LEAVE root;
	END IF;

	SET WinAmountPoolCurrency = WinAmount;

	SELECT WinAmount*exchange_rate,gaming_pb_pools.pb_pool_id INTO WinAmount, poolID
	FROM gaming_pb_pool_exchange_rates 
	JOIN gaming_pb_pools ON  gaming_pb_pool_exchange_rates.pb_pool_id =gaming_pb_pools.pb_pool_id
	WHERE gaming_pb_pool_exchange_rates.currency_id = currencyID AND ext_pool_id = extPoolID;

	SELECT ggp.game_play_id, ggp.game_round_id, ggp.game_manufacturer_id, ggp.amount_total, ggp.bonus_lost, ggp.amount_real, amount_bonus+amount_bonus_win_locked 
	INTO betGamePlayID, gameRoundID, gameManufacturerID, betTotal, betBonusLost, betReal, betBonus 
	FROM gaming_game_plays AS ggp
	JOIN gaming_cw_transactions AS cw_tran ON cw_tran.game_play_id = ggp.game_play_id
	WHERE cw_tran.cw_transaction_id=CWTransactionID AND is_win_placed=0 AND ggp.payment_transaction_type_id=12;

	IF (betGamePlayID=-1) THEN
		SET statusCode=2;
		LEAVE root;
	END IF;

	SELECT num_transactions, bet_total, win_total, is_round_finished, amount_tax_operator, amount_tax_player, amount_tax_player_bonus, amount_tax_operator_bonus, bet_real, win_real, win_bonus, win_bonus_win_locked
	INTO numTransactions, roundBetTotal, roundWinTotal, isRoundFinished, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, taxAlreadyChargedPlayerBonus, taxAlreadyChargedOperatorBonus, roundBetTotalReal, roundWinTotalReal, roundWinBonusAlready, roundWinBonusWinLockedAlready
	FROM gaming_game_rounds
	WHERE game_round_id=gameRoundID;
	SET winBonus = 0; 

	SET @winBonusLost=0;
	SET @winBonusWinLockedLost=0;
	SET @numPlayBonusInstances=0;  
	SET @updateBonusInstancesWins=0;  

	IF (bonusEnabledFlag) THEN 


		SET winBonusWinLocked = 0; 
		SET winBonus = 0;
		SET winReal = winAmount; 

		SELECT COUNT(*) INTO @numPlayBonusInstances
		FROM gaming_game_plays_bonus_instances 
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

			SET @isBonusSecured=0;
			SET updateGamePlayBonusInstanceWin=1;

			INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameRoundID);
			SET gamePlayWinCounterID=LAST_INSERT_ID();

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

					@winBonusCurrent:=ROUND(IF(gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=0  , IF(bet_returns_type.name='Bonus', @winBonusTemp, 0.0), 0.0), 0) AS win_bonus,
					@winBonusWinLockedCurrent:=ROUND(IF(gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=0 AND is_free_bonus=0, IF(bet_returns_type.name='BonusWinLocked', @winBonusAllTemp, @winBonusWinLockedTemp), 0.0), 0) AS win_bonus_win_locked,  
					@winBonusLostCurrent:=ROUND(IF((bet_returns_type.name='Loss') OR (gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=1), @winBonusTemp, 0), 0) AS lost_win_bonus,     
					@winRealBonusCurrent:=IF(is_free_bonus=1,GREATEST((bet_bonus/betTotal)*winAmount - @winBonusLostCurrent,0),IF(gaming_bonus_instances.is_secured=1, 
					(CASE transfer_type.name
						  WHEN 'All' THEN @winBonusAllTemp
						  WHEN 'Bonus' THEN @winBonusTemp
						  WHEN 'BonusWinLocked' THEN @winBonusWinLockedTemp
						  WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
						  WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
						  WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
						  WHEN 'ReleaseAllBonus' THEN @winBonusAllTemp
						  ELSE 0
					END), 0.0)) AS win_real,

					@winBonusWinLockedLostCurrent:=ROUND(IF(gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=1, 
					IF(bet_returns_type.name='BonusWinLocked' AND is_free_bonus != 1, @winBonusAllTemp, @winBonusWinLockedTemp),  
					IF(gaming_bonus_instances.is_secured=1, @winBonusAllTemp-@winRealBonusCurrent- @winBonusLostCurrent, 0)), 0) AS lost_win_bonus_win_locked,
					-
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


			SELECT SUM(win_bonus) INTO FreeBonusAmount FROM gaming_game_plays_bonus_instances_wins 
			JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_game_plays_bonus_instances_wins.bonus_instance_id
			JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
			WHERE game_play_win_counter_id = gamePlayWinCounterID AND (gaming_bonus_types_awarding.name='FreeBet' OR is_free_bonus = 1);

			SET FreeBonusAmount = IFNULL(FreeBonusAmount,0);      

			UPDATE gaming_game_plays_bonus_instances AS pbi_update
			JOIN gaming_game_plays_bonus_instances_wins AS PIU ON PIU.game_play_win_counter_id=gamePlayWinCounterID AND pbi_update.game_play_bonus_instance_id=PIU.game_play_bonus_instance_id 
			JOIN gaming_bonus_instances ON pbi_update.bonus_instance_id=gaming_bonus_instances.bonus_instance_id AND PIU.game_play_bonus_instance_id=pbi_update.game_play_bonus_instance_id 
			SET
				pbi_update.win_bonus=IFNULL(pbi_update.win_bonus,0)+PIU.win_bonus, 
				pbi_update.win_bonus_win_locked=IFNULL(pbi_update.win_bonus_win_locked,0)+PIU.win_bonus_win_locked, 
				pbi_update.win_real=IFNULL(pbi_update.win_real,0)+PIU.win_real,
				pbi_update.lost_win_bonus=IFNULL(pbi_update.lost_win_bonus,0)+PIU.lost_win_bonus,
				pbi_update.lost_win_bonus_win_locked=IFNULL(pbi_update.lost_win_bonus_win_locked,0)+PIU.lost_win_bonus_win_locked,

				pbi_update.now_used_all=IF(ROUND(gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount+PIU.win_bonus+PIU.win_bonus_win_locked,5)=0 AND (gaming_bonus_instances.open_rounds-1)<=0, 1, 0),
				pbi_update.add_wager_contribution=IFNULL(pbi_update.add_wager_contribution, 0)+PIU.add_wager_contribution;


			SET winBonus=@winBonus;
			SET winBonusWinLocked=@winBonusWinLocked;      
			SET winReal=winAmount-(winBonus+winBonusWinLocked)-(@winBonusLost+@winBonusWinLockedLost);

			UPDATE gaming_bonus_instances
			JOIN 
			(
				SELECT play_bonus.bonus_instance_id, SUM(play_bonus_wins.win_real) AS win_real, SUM(play_bonus_wins.win_bonus) AS win_bonus, 
					SUM(play_bonus_wins.win_bonus_win_locked) AS win_bonus_win_locked, SUM(IFNULL(play_bonus_wins.add_wager_contribution, 0)) AS add_wager_contribution, MIN(play_bonus.now_used_all) AS now_used_all
				FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins
				JOIN gaming_game_plays_bonus_instances AS play_bonus ON play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND play_bonus_wins.game_play_bonus_instance_id=play_bonus.game_play_bonus_instance_id 
				GROUP BY play_bonus.bonus_instance_id
			) AS PB ON gaming_bonus_instances.bonus_instance_id=PB.bonus_instance_id  
			SET 
				bonus_amount_remaining=bonus_amount_remaining+PB.win_bonus,
				current_win_locked_amount=current_win_locked_amount+PB.win_bonus_win_locked,
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
	SET taxModificationPlayerBonus = amountTaxPlayerBonus - taxAlreadyChargedPlayerBonus;
	SET taxModificationOperatorBonus = amountTaxOperatorBonus - taxAlreadyChargedOperatorBonus;

	
	IF(taxModificationPlayerBonus <=  winBonusWinLocked) THEN
		SET taxReduceBonusWinLocked = taxModificationPlayerBonus;
		SET taxReduceBonus = 0.0;
	ELSE 
		SET taxReduceBonusWinLocked = winBonusWinLocked;
		SET taxReduceBonus = taxModificationPlayerBonus - taxReduceBonusWinLocked;
	END IF; 

	UPDATE gaming_client_stats AS gcs
	LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID   
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
	SET 
		gcs.total_real_won=gcs.total_real_won+winReal, gcs.current_real_balance=gcs.current_real_balance+ROUND((winReal - taxOnReturn),0), 
		gcs.total_bonus_won=gcs.total_bonus_won+winBonus, gcs.current_bonus_balance=gcs.current_bonus_balance+ROUND(winBonus - taxReduceBonus,0),
		gcs.total_bonus_win_locked_won=gcs.total_bonus_win_locked_won+winBonusWinLocked, gcs.current_bonus_win_locked_balance=ROUND(current_bonus_win_locked_balance+winBonusWinLocked - taxReduceBonusWinLocked,0), 
		gcs.total_real_won_base=gcs.total_real_won_base+(winReal/exchangeRate), gcs.total_bonus_won_base=gcs.total_bonus_won_base+((winBonus+winBonusWinLocked)/exchangeRate), gcs.total_tax_paid = gcs.total_tax_paid + taxOnReturn, gcs.total_tax_paid_bonus = gcs.total_tax_paid_bonus + taxModificationPlayerBonus,

		gcsession.total_win=gcsession.total_win+winAmount, gcsession.total_win_base=gcsession.total_win_base+winTotalBase, gcsession.total_bet_placed=gcsession.total_bet_placed+betTotal, gcsession.total_win_real=gcsession.total_win_real+winReal, gcsession.total_win_bonus=gcsession.total_win_bonus+winBonus+winBonusWinLocked,

		gcws.num_wins=gcws.num_wins+IF(winAmount>0, 1, 0), gcws.total_real_won=gcws.total_real_won+winReal, gcws.total_bonus_won=gcws.total_bonus_won+winBonus+winBonusWinLocked,
		gcs.deferred_tax = @cumulativeDeferredTax := (gcs.deferred_tax + IF(taxAppliedOnType ='Deferred', taxAmount, 0)) -- cumulative deferred tax to later on (when we need to close tax cycle) transfer to the respective tax cycle 
	WHERE gcs.client_stat_id=clientStatID;  

	INSERT INTO gaming_game_plays 
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, license_type_id, pending_bet_real, pending_bet_bonus, amount_tax_operator, amount_tax_player, amount_tax_player_bonus, amount_tax_operator_bonus,extra_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, tax_cycle_id, cumulative_deferred_tax) 
	SELECT winAmount, winTotalBase, exchangeRate, winReal, winBonus, winBonusWinLocked,FreeBonusAmount, @winBonusLost, ROUND(@winBonusWinLockedLost+@winBonusLostFromPrevious,0), 0, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, current_real_balance, ROUND(current_bonus_balance+current_bonus_win_locked_balance,0), current_bonus_win_locked_balance, currencyID, numTransactions+1, game_play_message_type_id, licenseTypeID, pending_bets_real, pending_bets_bonus, taxModificationOperator, taxModificationPlayer, taxModificationPlayerBonus, taxModificationOperatorBonus,poolID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`), taxCycleID, gaming_client_stats.deferred_tax 
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_payment_transaction_type.name='Win' AND gaming_client_stats.client_stat_id=clientStatID
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name='PoolWin';

	SET gamePlayID=LAST_INSERT_ID();
	SET bonusTotal = winBonus+winBonusWinLocked+FreeBonusAmount;
	
	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);  

	INSERT INTO gaming_game_plays_pb (game_play_id,pb_fixture_id,pb_outcome_id,pb_pool_id,payment_transaction_type_id,client_id,client_stat_id,amount_total,amount_total_base,amount_total_pool_currency,
	amount_real,amount_real_base,amount_bonus,amount_bonus_base,timestamp,exchange_rate,currency_id,country_id,pb_league_id)
	SELECT gamePlayID,ggpp.pb_fixture_id,ggpp.pb_outcome_id,ggpp.pb_pool_id,ggp.payment_transaction_type_id,ggp.client_id,ggp.client_stat_id,ggp.amount_total*units,ggp.amount_total_base*units,WinAmountPoolCurrency*units,
	ggp.amount_real*units,ggp.amount_real/exchangeRate*units,bonusTotal*units,bonusTotal/exchangeRate*units,NOW(),exchangeRate,currencyID,countryID,ggpp.pb_league_id
	FROM gaming_game_plays_pb AS ggpp
	JOIN gaming_game_plays AS ggp ON ggp.game_play_id = gamePlayID
	WHERE ggpp.game_play_id = betGamePlayID;

	IF (updateGamePlayBonusInstanceWin) THEN
		UPDATE gaming_game_plays_bonus_instances_wins SET win_game_play_id=gamePlayID WHERE game_play_win_counter_id=gamePlayWinCounterID;
	END IF;


	IF (winAmount > 0 AND playLimitEnabled) THEN
		CALL PlayLimitsUpdate(clientStatID, licenseType, winAmount, 0);
	END IF;

	UPDATE gaming_game_plays SET is_win_placed=1, game_play_id_win=gamePlayID WHERE game_play_id=gamePlayID;

	UPDATE gaming_pb_bets
		SET pb_status_id = 5
	WHERE cw_transaction_id = CWTransactionID;

	UPDATE gaming_game_rounds
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
	SET 
		win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+winTotalBase,5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus, 
		win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked,win_free_bet = win_free_bet+FreeBonusAmount, win_bet_diffence_base=win_total_base-bet_total_base,
		bonus_lost=bonus_lost+@winBonusLost, bonus_win_locked_lost=bonus_win_locked_lost+@winBonusWinLockedLost+@winBonusLostFromPrevious, 
		date_time_end= NOW(), is_round_finished=1, num_transactions=num_transactions+1, 
		balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance, amount_tax_operator = amountTaxOperator, amount_tax_player = taxAmount , amount_tax_player_bonus = amountTaxPlayerBonus, amount_tax_operator_bonus = amountTaxOperatorBonus,
		tax_cycle_id = taxCycleID,
		cumulative_deferred_tax = @cumulativeDeferredTax
	WHERE game_round_id=gameRoundID;   

	SET gamePlayIDReturned=gamePlayID;
	SET statusCode =0;

END root$$

DELIMITER ;

