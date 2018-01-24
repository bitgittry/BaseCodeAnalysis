DROP procedure IF EXISTS `CommonWalletColossusPartialCancel`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletColossusPartialCancel`(clientStatID BIGINT, extPoolID BIGINT, CWTransactionID BIGINT, adjustAmount DECIMAL(18,5), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root: BEGIN

	DECLARE playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, taxEnabled TINYINT(1);
	DECLARE clientStatIDCheck, clientID, currencyID, countryID,sessionID,poolID,clientWagerTypeID,gamePlayID,gameRoundID,gameManufacturerID,
	gamePlayBetCounterID,betGamePlayID, licenseTypeID BIGINT DEFAULT -1;
	DECLARE exchangeRate,adjustAmountPoolCurrency, betTotal, betReal, betBonusLost, betBonus,remainAmountTotal,adjustReal,adjustBonus,
	adjustBonusWinLocked,adjustAmountBase,bonusTotal DECIMAL(18,5) DEFAULT 0;
	DECLARE numBonuses,pbStatusID INT DEFAULT 0;
	DECLARE transactionType VARCHAR(45);

	SET statusCode=0;
	SET clientWagerTypeID= 6;
	SET licenseTypeID = 5;

	IF (adjustAmount<=0) THEN
		LEAVE root; 
	END IF;

	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, IFNULL(gs4.value_bool,0) AS vb4
	INTO playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, taxEnabled
	FROM gaming_settings gs1 
	JOIN gaming_settings gs2 ON gs2.name='IS_BONUS_ENABLED'
	JOIN gaming_settings gs3 ON gs3.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY'
	LEFT JOIN gaming_settings gs4 ON (gs4.name='TAX_ON_GAMEPLAY_ENABLED')
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

	SET adjustAmountPoolCurrency = adjustAmount;

	SELECT ROUND(adjustAmount*exchange_rate,2),gaming_pb_pools.pb_pool_id INTO adjustAmount, poolID
	FROM gaming_pb_pool_exchange_rates 
	JOIN gaming_pb_pools ON  gaming_pb_pool_exchange_rates.pb_pool_id =gaming_pb_pools.pb_pool_id
	WHERE gaming_pb_pool_exchange_rates.currency_id = currencyID AND ext_pool_id = extPoolID;

	SELECT ggp.game_play_id, ggp.game_round_id, ggp.game_manufacturer_id, ggp.amount_total, ggp.bonus_lost, ggp.amount_real, amount_bonus+amount_bonus_win_locked 
	INTO gamePlayID, gameRoundID, gameManufacturerID, betTotal, betBonusLost, betReal, betBonus 
	FROM gaming_game_plays AS ggp
	JOIN gaming_cw_transactions AS cw_tran ON cw_tran.game_play_id = ggp.game_play_id
	WHERE cw_tran.cw_transaction_id=CWTransactionID AND is_win_placed=0 AND ggp.payment_transaction_type_id=12;

	IF (betTotal = adjustAmount) THEN
		SET transactionType = 'BetCancelled';
		SET pbStatusID = 6;
	ELSE
		SET transactionType  = 'PartialCancel';
		SET pbStatusID =7;
	END IF;


	SELECT SUM(amount_total*sign_mult)
	INTO remainAmountTotal
	FROM gaming_game_plays WHERE game_round_id=gameRoundID AND  payment_Transaction_type_id IN (20,140,12);

	IF (remainAmountTotal*-1 <adjustAmount) THEN
	 
	
		SET adjustAmount = remainAmountTotal*-1;
		IF (adjustAmount =0) THEN
			LEAVE root;
		END IF;
	END IF;

	INSERT INTO gaming_game_plays_bet_counter (date_created, client_stat_id) VALUES (NOW(), clientStatID);
	SET gamePlayBetCounterID=LAST_INSERT_ID();

	SELECT COUNT(*) INTO @numPlayBonusInstances
	FROM gaming_game_plays_bonus_instances  
	WHERE game_play_id=gamePlayID;  

	IF (@numPlayBonusInstances>0) THEN

		INSERT INTO gaming_game_plays_bonus_instances_pre (game_play_bet_counter_id, bonus_instance_id, bet_total, bet_real, bet_bonus, bet_bonus_win_locked)
		SELECT gamePlayBetCounterID, bonus_instance_id, bet_real+bet_bonus+bet_bonus_win_locked AS bet_total, bet_real, bet_bonus, bet_bonus_win_locked   
		FROM
		(
		  SELECT 
			 play_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id,play_bonus_instances.client_stat_id,
			
			ROUND(IF(gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=0, ROUND((SUM(bet_bonus)/betTotal)*adjustAmount, 0), 0),0) AS bet_bonus,
			ROUND(IF(gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=0, ROUND(SUM(bet_bonus_win_locked)/betTotal*adjustAmount, 0), 0),0) AS bet_bonus_win_locked,  
			ROUND((SUM(bet_real)/betTotal)*adjustAmount,0) AS bet_real
		  FROM gaming_game_plays_bonus_instances AS play_bonus_instances FORCE INDEX (game_play_id)
		  JOIN gaming_bonus_instances ON play_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
		  JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		  LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON gaming_bonus_rules.bonus_rule_id=wager_restrictions.bonus_rule_id AND wager_restrictions.currency_id=currencyID
		  WHERE play_bonus_instances.game_play_id_Bet=gamePlayID OR play_bonus_instances.game_play_id = gamePlayID
		  GROUP BY play_bonus_instances.bonus_instance_id
		) AS XX;
	  

		SELECT COUNT(*), SUM(bet_real)*-1, SUM(bet_bonus)*-1, SUM(bet_bonus_win_locked)*-1  
		INTO numBonuses, adjustReal, adjustBonus, adjustBonusWinLocked 
		FROM gaming_game_plays_bonus_instances_pre
		WHERE game_play_bet_counter_id=gamePlayBetCounterID;

	ELSE 
		SET adjustBonus=0;
		SET adjustBonusWinLocked=0;      
		SET adjustReal=adjustAmount;

	END IF; 

	SET adjustAmountBase = adjustAmount/exchangeRate;

	IF (playLimitEnabled AND adjustAmount!=0) THEN 
		CALL PlayLimitsUpdate(clientStatID, 'poolbetting', adjustAmount, 0);
	END IF;

	UPDATE gaming_client_stats AS gcs
	LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
	SET 
		total_real_played=total_real_played-adjustReal, current_real_balance=current_real_balance+ROUND(adjustReal,0),
		total_bonus_played=total_bonus_played-adjustBonus, current_bonus_balance=current_bonus_balance+ROUND(adjustBonus,0), 
		total_bonus_win_locked_played=total_bonus_win_locked_played-adjustBonusWinLocked, current_bonus_win_locked_balance=current_bonus_win_locked_balance+ROUND(adjustBonusWinLocked,0), 
		gcs.total_real_played_base=gcs.total_real_played_base-IFNULL((adjustReal/exchangeRate),0), gcs.total_bonus_played_base=gcs.total_bonus_played_base-((adjustBonus+adjustBonusWinLocked)/exchangeRate),
		
		gcss.total_bet=gcss.total_bet-adjustAmount, gcss.total_bet_base=gcss.total_bet_base-adjustAmountBase, gcss.total_bet_real=gcss.total_bet_real-adjustReal, gcss.total_bet_bonus=gcss.total_bet_bonus-adjustBonus+adjustBonusWinLocked
	WHERE gcs.client_stat_id=clientStatID; 

	INSERT INTO gaming_game_plays 
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, game_round_id, payment_transaction_type_id, is_win_placed, is_processed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, sb_extra_id, license_type_id, sign_mult, pending_bet_real, pending_bet_bonus,extra_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT (adjustReal+adjustBonus+adjustBonusWinLocked), (adjustReal+adjustBonus+adjustBonusWinLocked), exchangeRate, adjustReal, adjustBonus, adjustBonusWinLocked, 0, 0, 0, 0, NOW(), gameManufacturerID, clientID, clientStatID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 1, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, currencyID, 2, game_play_message_type_id, PoolID, licenseTypeID, 1, pending_bets_real, pending_bets_bonus,poolID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_payment_transaction_type.name=transactionType AND gaming_client_stats.client_stat_id=clientStatID
	JOIN gaming_game_play_message_types AS ggpmt ON ggpmt.name = 'PoolCancelBet';

	SET betGamePlayID = gamePlayID;
	SET gamePlayID = LAST_INSERT_ID();
	SET bonusTotal =adjustBonus+adjustBonusWinLocked;

	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);  

	INSERT INTO gaming_game_plays_pb (game_play_id,pb_fixture_id,pb_outcome_id,pb_pool_id,pb_league_id,payment_transaction_type_id,client_id,client_stat_id,amount_total,amount_total_base,amount_total_pool_currency,
	amount_real,amount_real_base,amount_bonus,amount_bonus_base,timestamp,exchange_rate,currency_id,country_id)
	SELECT gamePlayID,ggpp.pb_fixture_id,ggpp.pb_outcome_id,ggpp.pb_pool_id,ggpp.pb_league_id,ggp.payment_transaction_type_id,ggp.client_id,ggp.client_stat_id,ggp.amount_total*units,ggp.amount_total_base*units,adjustAmountPoolCurrency*units,
	ggp.amount_real*units,ggp.amount_real/exchangeRate*units,bonusTotal*units,bonusTotal/exchangeRate*units,NOW(),exchangeRate,currencyID,countryID
	FROM gaming_game_plays_pb AS ggpp
	JOIN gaming_game_plays AS ggp ON ggp.game_play_id = gamePlayID
	WHERE ggpp.game_play_id = betGamePlayID;

	SET gamePlayIDReturned=LAST_INSERT_ID();


	IF (@numPlayBonusInstances>0) THEN

		INSERT INTO gaming_game_plays_bonus_instances (game_play_id,game_play_id_bet, bonus_instance_id, bonus_rule_id, client_stat_id, timestamp, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,
		  wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_wager_requirement_remain_after)
		SELECT gamePlayIDReturned,gamePlayID, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, clientStatID, NOW(), exchangeRate,

		  gaming_bonus_instances.bet_real, gaming_bonus_instances.bet_bonus, gaming_bonus_instances.bet_bonus_win_locked,
		  
		  @wager_requirement_non_weighted:=IF(ROUND(gaming_bonus_instances.bet_total*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain/IFNULL(sb_bonus_rules.weight, 1)/IFNULL(license_weight_mod, 1), gaming_bonus_instances.bet_total) AS wager_requirement_non_weighted, 
		  @wager_requirement_contribution:=IF(ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,100000000*100),gaming_bonus_instances.bet_total)*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,1000000*100),gaming_bonus_instances.bet_total)*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)) AS wager_requirement_contribution_pre,
		  @wager_requirement_contribution:=LEAST(IFNULL(wgr_restrictions.max_wager_contibution,100000000*100), IF(wager_req_real_only OR bonusReqContributeRealOnly, ROUND(GREATEST(@wager_requirement_contribution-((gaming_bonus_instances.bet_bonus+gaming_bonus_instances.bet_bonus_win_locked)*IFNULL(sb_bonus_rules.weight,0)*IFNULL(license_weight_mod, 1)),0), 5), @wager_requirement_contribution)) AS wager_requirement_contribution, 
		  
		  @nowWagerReqMet:=IF (bonus_wager_requirement_remain-@wager_requirement_contribution=0,1,0) AS now_wager_requirement_met,
		  
		  IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wager_requirement_contribution)>=
			((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,
		  bonus_wager_requirement_remain-@wager_requirement_contribution AS bonus_wager_requirement_remain_after
		FROM 
		(
		  SELECT bonus_transaction.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, bonus_transaction.bet_total, bonus_transaction.bet_real, bonus_transaction.bet_bonus, bonus_transaction.bet_bonus_win_locked, bonus_wager_requirement_remain, IF(licenseTypeID=1,gaming_bonus_rules.casino_weight_mod, IF(licenseTypeID=2,gaming_bonus_rules.poker_weight_mod,IF(licenseTypeID=3, sportsbook_weight_mod ,1))) AS license_weight_mod,
			bonus_amount_given, bonus_wager_requirement, gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus
		  FROM gaming_game_plays_bonus_instances_pre AS bonus_transaction
		  JOIN gaming_bonus_instances ON bonus_transaction.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
		  JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		  JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
		  WHERE bonus_transaction.game_play_bet_counter_id=gamePlayBetCounterID 
		) AS gaming_bonus_instances  
		JOIN gaming_sb_bets_bonus_rules AS sb_bonus_rules ON sb_bonus_rules.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=sb_bonus_rules.bonus_rule_id  
		LEFT JOIN gaming_sb_bets_bonuses ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_sb_bets_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
		LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_instances.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID;


		UPDATE gaming_bonus_instances 
		  JOIN gaming_game_plays_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
		  SET bonus_amount_remaining=bonus_amount_remaining-bet_bonus, current_win_locked_amount=current_win_locked_amount-bet_bonus_win_locked,
			  bonus_wager_requirement_remain=bonus_wager_requirement_remain-wager_requirement_contribution,
			  is_active = IF (is_used_all=1 AND NOW() < expiry_date AND is_lost =0 ,1 , is_active)
		  WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayIDReturned; 

	END IF;

	UPDATE gaming_pb_bets
		SET pb_status_id = pbStatusID
	WHERE gaming_pb_bets.cw_transaction_id = cwTransactionID;

	UPDATE gaming_game_rounds AS ggr
	SET 
	ggr.bet_total=bet_total-adjustAmount, bet_total_base=ROUND(bet_total_base-adjustAmountBase,5), bet_real=bet_real-adjustReal, bet_bonus=bet_bonus-adjustBonus, bet_bonus_win_locked=bet_bonus_win_locked-adjustBonusWinLocked, 
	win_bet_diffence_base=win_total_base-bet_total_base, ggr.num_transactions=ggr.num_transactions+1
	WHERE game_round_id=gameRoundID;


	UPDATE gaming_client_wager_stats AS gcws 
	SET gcws.total_real_wagered=gcws.total_real_wagered-adjustReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered-(adjustBonus+adjustBonusWinLocked)
	WHERE gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID;

END root$$

DELIMITER ;

