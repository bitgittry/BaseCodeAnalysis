DROP procedure IF EXISTS `CommonWalletColossusPlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletColossusPlaceBet`(sessionID BIGINT, clientStatID BIGINT, betAmount DECIMAL(18,5), betReal DECIMAL(18,5), betBonus DECIMAL(18,5),
 betBonusWinLocked DECIMAL(18,5), gamePlayBetCounterID BIGINT,realMoneyOnly TINYINT(1), platformType VARCHAR(20), numBonuses INT,cwTransactionID BIGINT,transactionRef VARCHAR(40),
 poolID BIGINT,poolExchangeRate DECIMAL (18,5),pbCounterID BIGINT)
root:BEGIN

	DECLARE gameRoundID,gamePlayID,gameManufacturerID,clientID,countryID BIGINT;
	DECLARE licenseTypeID,NumBets INT;
	DECLARE betTotalBase,FreeBonusAmount,exchangeRate,currencyID,bonusTotal,platformComission,operatorCommision DECIMAL(18,5);
	DECLARE playLimitEnabled,bonusEnabledFlag TINYINT(1);
	DECLARE licenseType VARCHAR(40);

	SET platformComission = 0.005;
	SET operatorCommision = 0.125;
    SET gameManufacturerID = 18;
	SET licenseTypeID = 5; -- pool betting
	SET licenseType = 'poolbetting';
	SET bonusTotal = betBonus + betBonusWinLocked;

	SELECT gs1.value_bool as vb1,gs2.value_bool as vb2
	INTO playLimitEnabled,bonusEnabledFlag
	FROM gaming_settings gs1 
	JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	WHERE gs1.name='PLAY_LIMIT_ENABLED';

	SELECT exchange_rate,gaming_client_stats.client_id,gaming_client_stats.currency_id,country_id 
	INTO exchangeRate, clientID, currencyID, countryID
	FROM gaming_client_stats
	JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id
	JOIN clients_locations ON clients_locations.client_id = gaming_clients.client_id
	JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
	JOIN gaming_operators ON gaming_operators.operator_id = gaming_operator_currency.operator_id AND is_main_operator
	WHERE client_stat_id = clientStatID;

	SET betTotalBase=ROUND(betAmount/exchangeRate,5);  

	SELECT SUM(bet_bonus) INTO FreeBonusAmount 
	FROM gaming_game_plays_bonus_instances_pre 
	JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_game_plays_bonus_instances_pre.bonus_instance_id
	JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
	WHERE game_play_bet_counter_id = gamePlayBetCounterID AND (gaming_bonus_types_awarding.name='FreeBet' OR is_free_bonus = 1);

	SET FreeBonusAmount = IFNULL(FreeBonusAmount,0);

	UPDATE gaming_client_stats AS gcs
	LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=6
	SET total_real_played=total_real_played+betReal, current_real_balance=current_real_balance-betReal,
	  total_bonus_played=total_bonus_played+betBonus, current_bonus_balance=current_bonus_balance-betBonus, 
	  total_bonus_win_locked_played=total_bonus_win_locked_played+betBonusWinLocked, current_bonus_win_locked_balance=current_bonus_win_locked_balance-betBonusWinLocked, 
	  gcs.total_real_played_base=gcs.total_real_played_base +IFNULL((betReal/exchangeRate),0), gcs.total_bonus_played_base=gcs.total_bonus_played_base+((betBonus+betBonusWinLocked)/exchangeRate),
	  last_played_date=NOW(),
	  
	  gcss.total_bet=gcss.total_bet+betAmount,gcss.total_bet_base=gcss.total_bet_base+betTotalBase, gcss.bets=gcss.bets+1, gcss.total_bet_real=gcss.total_bet_real+betReal, gcss.total_bet_bonus=gcss.total_bet_bonus+betBonus+betBonusWinLocked,
	  
	  gcws.num_bets=gcws.num_bets+1, gcws.total_real_wagered=gcws.total_real_wagered+betReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered+betBonus+betBonusWinLocked,
	  gcws.first_wagered_date=IFNULL(gcws.first_wagered_date, NOW()), gcws.last_wagered_date=NOW()
	WHERE gcs.client_stat_id = clientStatID;

	INSERT INTO gaming_game_rounds
		(bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,bet_free_bet, num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, license_type_id) 
	SELECT betAmount, betTotalBase, exchangeRate, betReal, betBonus, betBonusWinLocked,FreeBonusAmount, 1, 1, NOW(),  gameManufacturerID, clientID, clientStatID, 0, gaming_game_round_types.game_round_type_id, currencyID, licenseTypeID 
	FROM gaming_game_round_types
	WHERE gaming_game_round_types.name=licenseType;

	SET gameRoundID=LAST_INSERT_ID();


	INSERT INTO gaming_game_plays 
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus,amount_free_bet, amount_bonus_win_locked, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, is_win_placed, is_processed, currency_id, round_transaction_no, game_play_message_type_id, sign_mult, extra_id, license_type_id, pending_bet_real, pending_bet_bonus, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, platform_type_id) 
	SELECT betAmount, betTotalBase, exchangeRate, betReal, betBonus,FreeBonusAmount, betBonusWinLocked, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, 0, 0, currencyID, gaming_game_rounds.num_transactions, game_play_message_type_id, -1, poolID, licenseTypeID, pending_bets_real, pending_bets_bonus, 0, gaming_client_stats.current_loyalty_points,
		0, gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus, gaming_platform_types.platform_type_id
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_payment_transaction_type.name='Bet' AND gaming_client_stats.client_stat_id=clientStatID
	JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id=gameRoundID
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name='PoolBet'
	LEFT JOIN gaming_platform_types ON gaming_platform_types.platform_type=platformType;

	SET gamePlayID=LAST_INSERT_ID();   

	SELECT COUNT(*) INTO NumBets FROM gaming_pb_bets_events WHERE pb_bet_counter_id = pbCounterID;

	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);  

	INSERT INTO gaming_game_plays_pb (game_play_id,pb_fixture_id,pb_outcome_id,pb_pool_id,pb_league_id,payment_transaction_type_id,client_id,client_stat_id,amount_total,amount_total_base,amount_total_pool_currency,
	amount_real,amount_real_base,amount_bonus,amount_bonus_base,timestamp,exchange_rate,currency_id,country_id,units,platform_type,operator_commision,platform_commision,
	operator_commision_base,platform_commision_base,operator_commision_pool_currency,platform_commision_pool_currency)
	SELECT gamePlayID,pb_fixture_id,pb_outcome_id,gaming_pb_bets_events.pb_pool_id,pb_league_id,payment_transaction_type_id,client_id,client_stat_id,amount_total/NumBets,amount_total_base/NumBets,amount_total/poolExchangeRate/NumBets,
	amount_real/NumBets,amount_real/exchangeRate/NumBets,bonusTotal/NumBets,bonusTotal/exchangeRate/NumBets,NOW(),exchangeRate,currencyID,countryID,1/NumBets,platformType,amount_total*operatorCommision/NumBets,amount_total*platformComission/NumBets,
	amount_total_base*operatorCommision/NumBets,amount_total_base*platformComission/NumBets,amount_total/poolExchangeRate*operatorCommision/NumBets,amount_total/poolExchangeRate*platformComission/NumBets
	FROM gaming_pb_bets_events
	JOIN gaming_pb_pools ON gaming_pb_pools.pb_pool_id = gaming_pb_bets_events.pb_pool_id
	JOIN gaming_pb_pool_fixtures ON gaming_pb_pool_fixtures.sequence_num = gaming_pb_bets_events.event_number  AND gaming_pb_pool_fixtures.pb_pool_id = gaming_pb_pools.pb_pool_id
	JOIN gaming_pb_competition_pools ON gaming_pb_competition_pools.pb_pool_id = gaming_pb_pools.pb_pool_id
	JOIN gaming_pb_competitions ON gaming_pb_competitions.pb_competition_id = gaming_pb_competition_pools.pb_competition_id
	JOIN gaming_game_plays ON gaming_game_plays.game_play_id = gamePlayID
	WHERE pb_bet_counter_id = pbCounterID;

	INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, gamePlayID;

	UPDATE gaming_pb_bets 
	SET 
		game_play_id = gamePlayID,
		transaction_ref = transactionRef,
		pb_status_id = 2,
		game_round_id = gameRoundID
	WHERE cw_transaction_id = cwTransactionID;

	UPDATE gaming_cw_transactions
	SET 
		transaction_ref = transactionRef,
		game_play_id = gamePlayID,
		is_success = 1
	WHERE cw_transaction_id = cwTransactionID;

	IF (playLimitEnabled AND betAmount > 0) THEN 
		CALL PlayLimitsUpdate(clientStatID, licenseType, betAmount, 1);
	END IF;

	IF (bonusEnabledFlag) THEN 
		IF (betAmount > 0 AND numBonuses>0) THEN 
			SET @transferBonusMoneyFlag=1;

			SET @betBonusDeductWagerRequirement=betAmount; 
			SET @wager_requirement_non_weighted=0;
			SET @wager_requirement_contribution=0;
			SET @betBonus=0;
			SET @betBonusWinLocked=0;
			SET @nowWagerReqMet=0;
			SET @hasReleaseBonus=0;

			INSERT INTO gaming_game_plays_bonus_instances (game_play_id, bonus_instance_id, bonus_rule_id, client_stat_id, timestamp, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,
				wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_wager_requirement_remain_after)
			SELECT gamePlayID, bonus_instance_id, gaming_bonus_instances.bonus_rule_id, clientStatID, NOW(), exchangeRate,	
				gaming_bonus_instances.bet_real, gaming_bonus_instances.bet_bonus, gaming_bonus_instances.bet_bonus_win_locked,
				@wager_requirement_non_weighted:=IF(gaming_bonus_instances.is_free_bonus=1,0,IF(ROUND(gaming_bonus_instances.bet_total*IFNULL(bonus_wgr_req_weigth, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain/IFNULL(bonus_wgr_req_weigth, 0)/IFNULL(license_weight_mod, 1), gaming_bonus_instances.bet_total)) AS wager_requirement_non_weighted, 
				@wager_requirement_contribution:=IF(gaming_bonus_instances.is_free_bonus=1,0,IF(ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,100000000*100),gaming_bonus_instances.bet_total)*IFNULL(bonus_wgr_req_weigth, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,1000000*100),gaming_bonus_instances.bet_total)*IFNULL(bonus_wgr_req_weigth, 0)*IFNULL(license_weight_mod, 1), 5))) AS wager_requirement_contribution_pre,
				@wager_requirement_contribution:=IF(gaming_bonus_instances.is_free_bonus=1,0,LEAST(IFNULL(wgr_restrictions.max_wager_contibution,100000000*100), IF(wager_req_real_only OR bonusReqContributeRealOnly, ROUND(GREATEST(@wager_requirement_contribution-((gaming_bonus_instances.bet_bonus+gaming_bonus_instances.bet_bonus_win_locked)*IFNULL(bonus_wgr_req_weigth,0)*IFNULL(license_weight_mod, 1)),0), 5), @wager_requirement_contribution))) AS wager_requirement_contribution, 
				@nowWagerReqMet:=IF (bonus_wager_requirement_remain-@wager_requirement_contribution=0 AND gaming_bonus_instances.is_free_bonus=0,1,0) AS now_wager_requirement_met,
				IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wager_requirement_contribution)>=
				  ((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,
				bonus_wager_requirement_remain-@wager_requirement_contribution AS bonus_wager_requirement_remain_after
			FROM 
			(
				SELECT bonus_transaction.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, bonus_transaction.bet_total, bonus_transaction.bet_real, bonus_transaction.bet_bonus, bonus_transaction.bet_bonus_win_locked, bonus_wager_requirement_remain, IF(licenseTypeID=1,gaming_bonus_rules.casino_weight_mod, IF(licenseTypeID=2,gaming_bonus_rules.poker_weight_mod,1)) AS license_weight_mod,
				  bonus_amount_given, bonus_wager_requirement, gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus,gaming_bonus_rules.is_free_bonus
				FROM gaming_game_plays_bonus_instances_pre AS bonus_transaction
				JOIN gaming_bonus_instances ON bonus_transaction.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
				JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
				WHERE bonus_transaction.game_play_bet_counter_id=gamePlayBetCounterID 
			) AS gaming_bonus_instances  
			JOIN gaming_bonus_rules_wgr_req_weights ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules_wgr_req_weights.bonus_rule_id AND gaming_bonus_rules_wgr_req_weights.operator_game_id=operatorGameID 
			LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_instances.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID;

			IF (ROW_COUNT() > 0) THEN


				UPDATE gaming_bonus_instances 
				JOIN gaming_game_plays_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
				SET bonus_amount_remaining=bonus_amount_remaining-bet_bonus, current_win_locked_amount=current_win_locked_amount-bet_bonus_win_locked,
					bonus_wager_requirement_remain=bonus_wager_requirement_remain-wager_requirement_contribution,
					is_secured=IF(now_wager_requirement_met=1,1,is_secured), secured_date=IF(now_wager_requirement_met=1,NOW(),NULL),
					gaming_bonus_instances.open_rounds=IF(isNewRound, gaming_bonus_instances.open_rounds+1, gaming_bonus_instances.open_rounds),
					gaming_bonus_instances.is_active=IF(is_active=0,0,IF(now_wager_requirement_met=1,0,1))
				WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;           

				UPDATE gaming_game_plays_bonus_instances AS ggpbi  
				JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
				JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
				SET 
					ggpbi.bonus_transfered_total=(CASE transfer_type.name
						WHEN 'All' THEN bonus_amount_remaining+current_win_locked_amount
						WHEN 'Bonus' THEN bonus_amount_remaining
						WHEN 'BonusWinLocked' THEN current_win_locked_amount
						WHEN 'UpToBonusAmount' THEN LEAST(bonus_amount_given, bonus_amount_remaining+current_win_locked_amount)
						WHEN 'UpToPercentage' THEN LEAST(bonus_amount_given*transfer_upto_percentage, bonus_amount_remaining+current_win_locked_amount)
						WHEN 'ReleaseBonus' THEN LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, bonus_amount_remaining+current_win_locked_amount)
						WHEN 'ReleaseAllBonus' THEN bonus_amount_remaining+current_win_locked_amount
						ELSE 0
					END),
					ggpbi.bonus_transfered=IF(transfer_type.name='BonusWinLocked', 0, LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining)),
					ggpbi.bonus_win_locked_transfered=IF(transfer_type.name='Bonus', 0, ggpbi.bonus_transfered_total-ggpbi.bonus_transfered),
					bonus_transfered_lost=bonus_amount_remaining-bonus_transfered,
					bonus_win_locked_transfered_lost=current_win_locked_amount-bonus_win_locked_transfered,
					bonus_amount_remaining=0,current_win_locked_amount=0,current_ring_fenced_amount=0,  
					gaming_bonus_instances.bonus_transfered_total=gaming_bonus_instances.bonus_transfered_total+ggpbi.bonus_transfered_total,
					gaming_bonus_instances.session_id=sessionID
				WHERE ggpbi.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;


				SET @requireTransfer=0;
				SET @bonusTransfered=0;
				SET @bonusWinLockedTransfered=0;
				SET @bonusTransferedLost=0;
				SET @bonusWinLockedTransferedLost=0;

				SET @ringFencedAmount=0;
				SET @ringFencedAmountSB=0;
				SET @ringFencedAmountCasino=0;
				SET @ringFencedAmountPoker=0;

				SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0),
				ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
				ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
				INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
				@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
				FROM gaming_game_plays_bonus_instances
				LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id
				WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;

				SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
				SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;

				IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
					CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
				END IF; 


				UPDATE gaming_game_plays_bonus_instances AS ggpbi 
				JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id
				JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				JOIN gaming_bonus_types_transfers AS transfer_type ON 
					gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id AND transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus')
				SET 
					ggpbi.bonus_transfered_total=LEAST(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))* 
					  gaming_bonus_instances.transfer_every_amount, 
					  bonus_amount_remaining+current_win_locked_amount), 
					ggpbi.bonus_transfered=LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining),
					ggpbi.bonus_win_locked_transfered=ggpbi.bonus_transfered_total-ggpbi.bonus_transfered,
					bonus_amount_remaining=bonus_amount_remaining-bonus_transfered, current_win_locked_amount=current_win_locked_amount-bonus_win_locked_transfered,  
					gaming_bonus_instances.transfer_every_x_last=gaming_bonus_instances.transfer_every_x_last+(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))*gaming_bonus_instances.transfer_every_x),
					gaming_bonus_instances.bonus_transfered_total=IFNULL(gaming_bonus_instances.bonus_transfered_total,0)+ggpbi.bonus_transfered_total,
					gaming_bonus_instances.session_id=sessionID
				WHERE ggpbi.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

				SET @requireTransfer=0;
				SET @bonusTransfered=0;
				SET @bonusWinLockedTransfered=0;
				SET @bonusTransferedLost=0;
				SET @bonusWinLockedTransferedLost=0;

				SET @ringFencedAmount=0;
				SET @ringFencedAmountSB=0;
				SET @ringFencedAmountCasino=0;
				SET @ringFencedAmountPoker=0;

				SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0)  ,
				ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
				ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
				INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
				@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
				FROM gaming_game_plays_bonus_instances
				LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id
				WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

				SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
				SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
				IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
					CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
				END IF; 
			END IF; 
		END IF; 
	END IF;

	CALL CommonWalletPBReturnData(clientStatID, gamePlayID);

END root$$

DELIMITER ;

