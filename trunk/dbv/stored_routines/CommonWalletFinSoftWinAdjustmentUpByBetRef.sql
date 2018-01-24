DROP procedure IF EXISTS `CommonWalletFinSoftWinAdjustmentUpByBetRef`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletFinSoftWinAdjustmentUpByBetRef`(clientStatID BIGINT, transactionRef VARCHAR(100), betRef VARCHAR(40), adjustAmount DECIMAL(18,5), canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN

	DECLARE gameManufacturerName VARCHAR(20) DEFAULT 'FinSoft';
	DECLARE gameManufacturerID BIGINT DEFAULT 7; 
	DECLARE sbBetWinID, gamePlayID, sbBetID, sbBetIDCheck, sbExtraID, clientStatIDCheck, gameRoundID, sessionID, betGamePlayID, winGamePlayID, currencyID, gamePlayWinCounterID, clientID, countryID, countryTaxID BIGINT DEFAULT -1; 
	DECLARE winAmount, winAmountBase, winReal, winBonus, winBonusWinLocked, betTotal, exchangeRate, taxBet, taxWin, roundBetTotal, roundWinTotal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal,  amountTaxPlayer, amountTaxOperator, taxModificationOperator, taxModificationPlayer, roundWinTotalFull DECIMAL(18,5) DEFAULT 0;
	DECLARE bonusEnabledFlag, playLimitEnabled, isRoundFinished, updateGamePlayBonusInstanceWin, applyNetDeduction, winTaxPaidByOperator, taxEnabled, sportsTaxCountryEnabled,usedFreeBonus  TINYINT(1) DEFAULT 0;
	DECLARE numTransactions, gamePlayMessageTypeID INT DEFAULT 0;
	DECLARE liveBetType TINYINT(4) DEFAULT 2;
	DECLARE deviceType TINYINT(4) DEFAULT 1;
	DECLARE clientWagerTypeID INT DEFAULT 3; 
	DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
	DECLARE NumSingles INT DEFAULT 1;

	SET gamePlayID=NULL;
	SET winAmount=adjustAmount;

	SELECT client_stat_id, client_id, currency_id INTO clientStatIDCheck, clientID, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;

	IF (clientStatIDCheck=-1) THEN
		SET statusCode=1;
		IF (canCommit) THEN COMMIT AND CHAIN; END IF;
		LEAVE root;
	END IF;

	SELECT sb_bet_id, game_play_id, sb_extra_id INTO sbBetIDCheck, gamePlayID, sbExtraID FROM gaming_sb_bet_history WHERE transaction_ref=transactionRef AND sb_bet_transaction_type_id=7; 

	IF (sbBetIDCheck!=-1) THEN 
		SET statusCode=0;
		IF (canCommit) THEN COMMIT AND CHAIN; END IF;
		CALL CommonWalletSBReturnTransactionData(gamePlayID, sbBetIDCheck, sbExtraID, 'Win', clientStatID); 
		LEAVE root;
	END IF;

	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, IFNULL(gs3.value_bool,0) AS vb3
	INTO playLimitEnabled, bonusEnabledFlag, taxEnabled
	FROM gaming_settings gs1 
	JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	LEFT JOIN gaming_settings gs3 ON (gs3.name='TAX_ON_GAMEPLAY_ENABLED')
	WHERE gs1.name='PLAY_LIMIT_ENABLED';

	SELECT exchange_rate INTO exchangeRate FROM gaming_operator_currency WHERE gaming_operator_currency.currency_id=currencyID LIMIT 1;

	SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_play_id_win, gaming_game_plays.game_round_id, gaming_game_plays.session_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, 
		gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions, gaming_game_plays.game_play_id_win 
	INTO sbBetID, betGamePlayID, winGamePlayID, gameRoundID, sessionID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions, winGamePlayID
	FROM gaming_sb_bet_singles 
	JOIN gaming_sb_bets ON gaming_sb_bet_singles.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_singles.sb_bet_id
	AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1
	JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_singles.sb_selection_id=gaming_game_plays.sb_extra_id AND 
		gaming_game_plays.game_play_message_type_id=8 AND gaming_game_plays.payment_transaction_type_id=12
	JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
	ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 

	IF (betGamePlayID=-1) THEN
		SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_play_id_win, gaming_game_plays.game_round_id, gaming_game_plays.session_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, 
			gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions, gaming_game_plays.game_play_id_win,gaming_sb_bet_multiples.num_singles
		INTO sbBetID, betGamePlayID, winGamePlayID, gameRoundID, sessionID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions, winGamePlayID,NumSingles
		FROM gaming_sb_bet_multiples 
		JOIN gaming_sb_bets ON gaming_sb_bet_multiples.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_multiples.sb_bet_id
			AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1 
		JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_multiples.sb_multiple_type_id=gaming_game_plays.sb_extra_id AND 
			gaming_game_plays.game_play_message_type_id=10 AND gaming_game_plays.payment_transaction_type_id=12
		JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
		ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
	END IF;
    
	IF (betGamePlayID=-1) THEN
		SET statusCode=2;
		LEAVE root;
	END IF;

	SET @winBonusLost=0;
	SET @winBonusWinLockedLost=0;

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
			SET @isBonusSecured=0;
			SET updateGamePlayBonusInstanceWin=1;

			INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameRoundID);
			SET gamePlayWinCounterID=LAST_INSERT_ID();

			INSERT INTO gaming_game_plays_win_counter_bets (game_play_win_counter_id, game_play_id)
			SELECT DISTINCT gamePlayWinCounterID, game_play_id
			FROM gaming_game_plays
			WHERE game_play_id=betGamePlayID;

			INSERT INTO gaming_game_plays_bonus_instances_wins (win_game_play_id,game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, timestamp, exchange_rate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, add_wager_contribution)
			SELECT winGamePlayID,gamePlayWinCounterID, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, NOW(), exchangeRate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, clientStatID, add_wager_contribution
			FROM
			(
				SELECT 
					play_bonus_instances.game_play_bonus_instance_id, play_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id,

					@isBonusSecured:=IF(gaming_bonus_instances.is_secured, 1, @isBonusSecured),
					@winBonusAllTemp:=ROUND(((bet_bonus+bet_bonus_win_locked)/betTotal)*winAmount,0), 
					@winBonusTemp:= 0, 
					@winBonusWinLockedTemp:=@winBonusAllTemp-@winBonusTemp,
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
						  WHEN 'All' THEN @winBonusAllTemp
						  WHEN 'Bonus' THEN @winBonusTemp
						  WHEN 'BonusWinLocked' THEN @winBonusWinLockedTemp
						  WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
						  WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
						  WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
						  WHEN 'ReleaseAllBonus' THEN @winBonusAllTemp
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

					IF (gaming_bonus_instances.is_secured OR wager_restrictions.max_bet_add_win_contr IS NULL OR is_free_bonus=1, 0, 
						ROUND(
							(GREATEST(0, (play_bonus_instances.bet_bonus+play_bonus_instances.bet_bonus_win_locked)-wager_restrictions.max_bet_add_win_contr)/
								(play_bonus_instances.bet_bonus+play_bonus_instances.bet_bonus_win_locked))*(@winBonusCurrent+@winBonusWinLockedCurrent)*gaming_bonus_rules.over_max_bet_win_contr_multiplier
						, 0)
					) AS add_wager_contribution,           
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

			UPDATE gaming_game_plays_bonus_instances AS pbi_update
			JOIN gaming_game_plays_bonus_instances_wins AS PIU ON PIU.game_play_win_counter_id=gamePlayWinCounterID AND pbi_update.game_play_bonus_instance_id=PIU.game_play_bonus_instance_id 
			JOIN gaming_bonus_instances ON pbi_update.bonus_instance_id=gaming_bonus_instances.bonus_instance_id AND PIU.game_play_bonus_instance_id=pbi_update.game_play_bonus_instance_id  AND is_lost=0
			SET
				pbi_update.win_bonus=IFNULL(pbi_update.win_bonus,0)+PIU.win_bonus-PIU.lost_win_bonus, 
				pbi_update.win_bonus_win_locked=IFNULL(pbi_update.win_bonus_win_locked,0)+PIU.win_bonus_win_locked-PIU.lost_win_bonus_win_locked, 
				pbi_update.win_real=IFNULL(pbi_update.win_real,0)+PIU.win_real,
				pbi_update.lost_win_bonus=IFNULL(pbi_update.lost_win_bonus,0)+PIU.lost_win_bonus,
				pbi_update.lost_win_bonus_win_locked=IFNULL(pbi_update.lost_win_bonus_win_locked,0)+PIU.lost_win_bonus_win_locked,
				pbi_update.now_used_all=IF(ROUND(gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount+gaming_bonus_instances.reserved_bonus_funds
					+PIU.win_bonus+PIU.win_bonus_win_locked-PIU.lost_win_bonus-PIU.lost_win_bonus_win_locked,5)=0, 1, 0), 
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
				bonus_wager_requirement=IF(gaming_bonus_instances.is_active, bonus_wager_requirement+add_wager_contribution, bonus_wager_requirement),
				bonus_wager_requirement_remain=IF(gaming_bonus_instances.is_active, bonus_wager_requirement_remain+add_wager_contribution, bonus_wager_requirement_remain),
				is_active= IF(is_lost=0 AND is_secured=0,1,0),
				is_used_all = IF(is_lost=0 AND is_secured=0,0,1),
				used_all_date=IF(is_active=1 AND PB.now_used_all>0 AND (gaming_bonus_instances.open_rounds)<=0 AND used_all_date IS NULL, NOW(), used_all_date);

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

		END IF; 
    
	ELSE 
		SET winReal=winAmount;
		SET winBonus=0; SET winBonusWinLocked=0; 
		SET @winBonusLost=0; SET @winBonusWinLockedLost=0;
	END IF; 

	SET winAmountBase=ROUND(winAmount/exchangeRate,5);

	IF (taxEnabled) THEN

		SELECT bet_total, win_total, amount_tax_operator, amount_tax_player, bet_real, win_real
		INTO roundBetTotal, roundWinTotal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal
		FROM gaming_game_rounds
		WHERE game_round_id=gameRoundID;

		SELECT clients_locations.country_id, gaming_countries.sports_tax INTO countryID, sportsTaxCountryEnabled  
		FROM clients_locations
		JOIN gaming_countries ON gaming_countries.country_id = clients_locations.country_id
		WHERE clients_locations.client_id = clientID AND clients_locations.is_primary = 1;
		  
		SET amountTaxPlayer = 0.0;
		SET amountTaxOperator = 0.0;
		SET taxModificationOperator = 0.0;
		SET taxModificationPlayer = 0.0;

		IF (countryID > 0 AND sportsTaxCountryEnabled = 1) THEN
		  
			SELECT country_tax_id, bet_tax, win_tax, apply_net_deduction, tax_paid_by_operator_win INTO countryTaxID, taxBet, taxWin, applyNetDeduction, winTaxPaidByOperator
			FROM gaming_country_tax AS gct
			WHERE gct.country_id = countryID AND gct.is_current =  1 AND gct.licence_type_id = licenseTypeID AND gct.is_active = 1 LIMIT 1;

			SET roundWinTotalFull = roundWinTotalReal + winReal; 

			IF(countryTaxID > 0) THEN
				IF(roundWinTotalFull > 0) THEN
					IF(applyNetDeduction = 1) THEN
						IF(winTaxPaidByOperator = 0) THEN
							SET amountTaxPlayer = ABS(roundWinTotalFull - roundBetTotalReal) * taxWin; 
							SET amountTaxOperator = 0.0;
						ELSE 
							SET amountTaxPlayer = 0.0;
							SET amountTaxOperator = ABS(roundWinTotalFull - roundBetTotalReal) * taxWin; 
						END IF;
					ELSE 
						IF(winTaxPaidByOperator = 0) THEN
							SET amountTaxPlayer = ABS(roundWinTotalFull) * taxWin; 
							SET amountTaxOperator = 0.0;
						ELSE 
							SET amountTaxPlayer = 0.0;
							SET amountTaxOperator = ABS(roundWinTotalFull) * taxWin; 
						END IF;
					END IF;
				ELSE
					SET amountTaxPlayer = 0.0;
					SET amountTaxOperator = roundBetTotalReal * taxWin;
				END IF;
			END IF;
		END IF;
	END IF; 

	SET taxModificationOperator = amountTaxOperator - taxAlreadyChargedOperator;
	SET taxModificationPlayer = amountTaxPlayer - taxAlreadyChargedPlayer;

	UPDATE gaming_client_stats AS gcs
	LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID   
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
	SET 
		gcs.total_real_won=gcs.total_real_won+winReal, gcs.current_real_balance=gcs.current_real_balance+winReal - taxModificationPlayer, 
		gcs.total_bonus_won=gcs.total_bonus_won+winBonus, gcs.current_bonus_balance=gcs.current_bonus_balance+winBonus, 
		gcs.total_bonus_win_locked_won=gcs.total_bonus_win_locked_won+winBonusWinLocked, gcs.current_bonus_win_locked_balance=current_bonus_win_locked_balance+winBonusWinLocked, 
		gcs.total_real_won_base=gcs.total_real_won_base+(winReal/exchangeRate), gcs.total_bonus_won_base=gcs.total_bonus_won_base+((winBonus+winBonusWinLocked)/exchangeRate), gcs.total_tax_paid = gcs.total_tax_paid + taxModificationPlayer,

		gcsession.total_win=gcsession.total_win+winAmount, gcsession.total_win_base=gcsession.total_win_base+winAmountBase, gcsession.total_bet_placed=gcsession.total_bet_placed+betTotal, gcsession.total_win_real=gcsession.total_win_real+winReal, gcsession.total_win_bonus=gcsession.total_win_bonus+winBonus+winBonusWinLocked,

		gcws.num_wins=gcws.num_wins+IF(winAmount>0, 1, 0), gcws.total_real_won=gcws.total_real_won+winReal, gcws.total_bonus_won=gcws.total_bonus_won+winBonus+winBonusWinLocked
	WHERE gcs.client_stat_id=clientStatID;  


	UPDATE gaming_game_rounds AS ggr
	SET 
		ggr.win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+winAmountBase,5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus, win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked, 
		win_bet_diffence_base=win_total_base-bet_total_base, ggr.num_transactions=ggr.num_transactions+1, ggr.amount_tax_operator = amountTaxOperator, ggr.amount_tax_player = amountTaxPlayer
	WHERE game_round_id=gameRoundID;

	INSERT INTO gaming_game_plays 
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, game_round_id, payment_transaction_type_id, is_win_placed, is_processed, balance_real_after, balance_bonus_after,balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, sb_extra_id, sb_bet_id, license_type_id, device_type, pending_bet_real, pending_bet_bonus, amount_tax_operator, amount_tax_player,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT winAmount, winAmountBase, exchangeRate, winReal, winBonus, winBonusWinLocked, 0, @winBonusLost, @winBonusWinLockedLost, 0, NOW(), gameManufacturerID, clientID, clientStatID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 1, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance,current_bonus_win_locked_balance, currencyID, numTransactions+1, game_play_message_type_id, sbExtraID, sbBetID, licenseTypeID, deviceType, pending_bets_real, pending_bets_bonus, taxModificationOperator, taxModificationPlayer,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_payment_transaction_type.name='WinAdjustment' AND gaming_client_stats.client_stat_id=clientStatID
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.game_play_message_type_id=IF(gamePlayMessageTypeID=8,9,11);

	SET gamePlayID=LAST_INSERT_ID();

	-- IF (winGamePlayID IS NULL) THEN

		UPDATE gaming_game_plays_bonus_instances_wins SET win_game_play_id = winGamePlayID
		WHERE game_play_win_counter_id=gamePlayWinCounterID;

		UPDATE gaming_game_plays_win_counter_bets
	 	SET win_game_play_id=gamePlayID
	 	WHERE game_play_win_counter_id=gamePlayWinCounterID;

		-- UPDATE gaming_game_plays SET is_win_placed=1, game_play_id_win=gamePlayID WHERE game_play_id=betGamePlayID;

-- 	END IF;

	SET gamePlayID=LAST_INSERT_ID();
	
	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);  


	INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units)
	SELECT game_play_id, 13, winAmount/NumSingles, winAmountBase/NumSingles, winReal/NumSingles, winReal/NumSingles/exchangeRate, (winBonusWinLocked+winBonus)/NumSingles, (winBonusWinLocked+winBonus)/NumSingles/exchangeRate, NOW(), exchangeRate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, 2, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, liveBetType, deviceType, 0
	FROM gaming_game_plays_sb
	WHERE game_play_id=betGamePlayID
	GROUP BY sb_selection_id;

	IF (@isBonusSecured OR usedFreeBonus) THEN
		CALL BonusConvertWinningsAfterSecuredDate(gamePlayID,gamePlayWinCounterID);
	END IF;

	IF (playLimitEnabled AND winAmount>0) THEN 
		CALL PlayLimitsUpdate(clientStatID, 'sportsbook', winAmount, 0);
	END IF;
  
	INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount, transaction_ref, game_play_id, sb_extra_id) 
	SELECT sbBetID, sb_bet_transaction_type_id, NOW(), adjustAmount, transactionRef, gamePlayID, sbExtraID
	FROM gaming_sb_bet_transaction_types WHERE name='WinAdjustment';

	CALL CommonWalletSBReturnTransactionData(gamePlayID, sbBetID, sbExtraID, 'Win', clientStatID);

	SET statusCode=0;

END root$$

DELIMITER ;

