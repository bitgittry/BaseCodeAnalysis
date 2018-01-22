DROP procedure IF EXISTS `BonusExchangeFreeRounds`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusExchangeFreeRounds`(cwFreeRoundID BIGINT, clientStatID BIGINT, numFreeRoundsUsed INT, roundRef BIGINT, winAmount DECIMAL (18,5), transactionRef VARCHAR(80), gameManufacturerName VARCHAR(80), amountCurrency CHAR(3), OUT statusCode INT)
root: BEGIN
    -- changed to cwFreeRoundID instead of bonusInstanceID
    -- added validation on clientStatID 

	DECLARE GameRoundID, CurrencyID, GameID, SessionID, GameSessionID, PlatformTypeID, GamePlayID,GameManufacturerID, bonusInstanceID, bonusRuleID BIGINT DEFAULT -1;
	DECLARE FreeRoundsRemaining INT DEFAULT -1;
	DECLARE CostPerFreeRound,ExchangeRate DECIMAL(18,5);
	DECLARE Complete, isAlreadyProcessed TINYINT(1) DEFAULT 0;
	DECLARE cwTransactionID BIGINT DEFAULT NULL;
	DECLARE awardingType VARCHAR(80) DEFAULT NULL;
	
	SET statusCode = 0;
		
	CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, 'BonusAwarded', cwTransactionID, isAlreadyProcessed, statusCode);
	IF (isAlreadyProcessed) THEN
		LEAVE root;
	END IF;

	SELECT gaming_bonus_instances.bonus_rule_id, gaming_bonus_instances.bonus_instance_id, free_rounds_remaining, game_manufacturer_id,cost_per_round,gaming_client_stats.currency_id, game_id_awarded
	INTO bonusRuleID, bonusInstanceID, FreeRoundsRemaining, GameManufacturerID, CostPerFreeRound,  CurrencyID, GameID
	FROM gaming_cw_free_rounds 
	JOIN gaming_bonus_instances ON gaming_bonus_instances.cw_free_round_id = gaming_cw_free_rounds.cw_free_round_id
	JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id = gaming_client_stats.client_stat_id
	WHERE gaming_cw_free_rounds.cw_free_round_id=cwFreeRoundID AND gaming_cw_free_rounds.client_stat_id=clientStatID FOR UPDATE;

    IF (bonusInstanceID=-1) THEN
		SET statusCode = 1;
		LEAVE root;
    END IF;

	SELECT exchange_rate,gaming_game_sessions.session_id,game_session_id,platform_type_id INTO ExchangeRate,SessionID,GameSessionID,PlatformTypeID
	FROM gaming_operator_currency
	LEFT JOIN gaming_game_sessions ON gaming_game_sessions.client_stat_id = clientStatID AND gaming_game_sessions.game_id = GameID AND cw_game_latest = 1
	LEFT JOIN sessions_main ON gaming_game_sessions.session_id = sessions_main.session_id
	WHERE gaming_operator_currency.currency_id = CurrencyID;
	

	IF (numFreeRoundsUsed =0 OR numFreeRoundsUsed = FreeRoundsRemaining) THEN
		SET numFreeRoundsUsed = FreeRoundsRemaining;
		SET Complete = 1;
	END IF;

	UPDATE gaming_cw_free_rounds
	JOIN gaming_bonus_instances ON gaming_cw_free_rounds.cw_free_round_id = gaming_bonus_instances.cw_free_round_id
	JOIN gaming_cw_free_round_statuses ON gaming_cw_free_round_statuses.name = 'StartedBeingUsed'
	JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id =gaming_client_stats.client_stat_id
	JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
	JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
	JOIN gaming_operators ON gaming_operators.is_main_operator=1 AND gaming_operator_currency.operator_id=gaming_operators.operator_id
	LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
	LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
	SET gaming_cw_free_rounds.cw_free_round_status_id = gaming_cw_free_round_statuses.cw_free_round_status_id,
		free_rounds_remaining=free_rounds_remaining-numFreeRoundsUsed,
		win_total = win_total +  winAmount,
		gaming_client_stats.current_free_rounds_amount = current_free_rounds_amount - (cost_per_round * numFreeRoundsUsed),
		gaming_client_stats.current_free_rounds_num = current_free_rounds_num - numFreeRoundsUsed,
		gaming_client_stats.current_free_rounds_win_locked = current_free_rounds_win_locked + winAmount,
		gaming_client_stats.total_free_rounds_played_num = total_free_rounds_played_num + numFreeRoundsUsed
	WHERE bonus_instance_id = bonusInstanceID;

	INSERT INTO gaming_game_rounds (
		bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,bet_free_bet, bet_bonus_lost, jackpot_contribution, num_bets, num_transactions, date_time_start,date_time_end, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, round_ref, license_type_id,is_round_finished, balance_real_before, balance_bonus_before, loyalty_points, loyalty_points_bonus,
		win_total, win_total_base, win_real, win_bonus,win_free_bet,win_bonus_win_locked, win_bet_diffence_base,bonus_lost, bonus_win_locked_lost,  balance_real_after, balance_bonus_after) 
	SELECT numFreeRoundsUsed * CostPerFreeRound, numFreeRoundsUsed * CostPerFreeRound / ExchangeRate, ExchangeRate, 0, 0, 0,0, 0, 0, 1, 2,NOW(), NOW(), gaming_operator_games.game_id, GameManufacturerID, gaming_operator_games.operator_game_id, gaming_client_stats.client_id, clientStatID, 1, gaming_game_round_types.game_round_type_id, CurrencyID, roundRef , 1 ,1, current_real_balance, current_bonus_balance + current_bonus_win_locked_balance, 0,0,
		winAmount,winAmount/ExchangeRate,0,0,0,0, (winAmount-(numFreeRoundsUsed * CostPerFreeRound))/ExchangeRate,0,0,current_real_balance, current_bonus_balance + current_bonus_win_locked_balance
	FROM gaming_game_round_types
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
	JOIN gaming_cw_free_rounds ON cw_free_round_id = cwFreeRoundID
	LEFT JOIN gaming_operator_games ON gaming_cw_free_rounds.game_id_awarded = gaming_operator_games.game_id 
	WHERE gaming_game_round_types.name='FreeRound';
	SET GameRoundID = LAST_INSERT_ID();

	INSERT INTO gaming_game_rounds_cw_free_rounds(game_round_id,bet_free_round,win_free_round)
	SELECT GameRoundID,numFreeRoundsUsed * CostPerFreeRound, winAmount;

	INSERT INTO gaming_game_plays 
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus,amount_free_bet, amount_bonus_win_locked, amount_other, bonus_lost, jackpot_contribution, timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, is_win_placed, is_processed, currency_id, round_transaction_no, game_play_message_type_id, sign_mult, extra_id, license_type_id, pending_bet_real, pending_bet_bonus, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, platform_type_id) 
	SELECT bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus,bet_free_bet, bet_bonus_win_locked, 0, bet_bonus_lost, jackpot_contribution, NOW(), game_id, game_manufacturer_id, operator_game_id, gaming_game_rounds.client_id, gaming_game_rounds.client_stat_id, SessionID, GameSessionID, game_round_id, gaming_payment_transaction_type.payment_transaction_type_id, balance_real_after, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, 0, 0, gaming_client_stats.currency_id, 1, game_play_message_type_id, -1, bonusInstanceID, license_type_id, pending_bets_real, pending_bets_bonus, 0, current_loyalty_points, 0, total_loyalty_points_given_bonus-total_loyalty_points_used_bonus,PlatformTypeID
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_payment_transaction_type.name='Bet' AND gaming_client_stats.client_stat_id=clientStatID
	JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id=GameRoundID
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name='InitialBet' COLLATE utf8_general_ci;

	SET GamePlayID=LAST_INSERT_ID();

	INSERT INTO gaming_game_plays_cw_free_rounds (game_play_id, amount_free_round, balance_free_round_after, balance_free_round_win_after, cw_free_round_id)
	SELECT GamePlayID, bet_free_round, current_free_rounds_amount, current_free_rounds_win_locked-winAmount, cwFreeRoundID
	FROM gaming_client_stats
	JOIN gaming_game_rounds_cw_free_rounds ON gaming_game_rounds_cw_free_rounds.game_round_id=GameRoundID
	WHERE gaming_client_stats.client_stat_id=clientStatID;

	INSERT INTO gaming_game_plays 
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, license_type_id, pending_bet_real, pending_bet_bonus, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT win_total, win_total_base, exchange_rate, win_real, win_bonus, win_bonus_win_locked,win_free_bet, bonus_lost, bonus_win_locked_lost, 0, NOW(), game_id, game_manufacturer_id, operator_game_id, gaming_game_rounds.client_id, gaming_game_rounds.client_stat_id, SessionID, GameSessionID, game_round_id, gaming_payment_transaction_type.payment_transaction_type_id, 1, balance_real_after, current_bonus_balance + current_bonus_win_locked_balance, current_bonus_win_locked_balance, gaming_client_stats.currency_id, 2, game_play_message_type_id, 1, pending_bets_real, pending_bets_bonus, PlatformTypeID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus)
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_payment_transaction_type.name='Win' AND gaming_client_stats.client_stat_id=clientStatID
	JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id=GameRoundID
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=IF(winAmount>0,'HandWins','HandLoses')  COLLATE utf8_general_ci;

	UPDATE gaming_game_plays SET game_play_id_win=gamePlayID WHERE game_play_id=GamePlayID;
	SET GamePlayID=LAST_INSERT_ID();

	INSERT INTO gaming_game_plays_cw_free_rounds (game_play_id,amount_free_round_win,balance_free_round_after,balance_free_round_win_after,cw_free_round_id)
	SELECT GamePlayID,win_free_round,current_free_rounds_amount,current_free_rounds_win_locked,cwFreeRoundID
	FROM gaming_client_stats
	JOIN gaming_game_rounds_cw_free_rounds ON gaming_game_rounds_cw_free_rounds.game_round_id=GameRoundID
	WHERE gaming_client_stats.client_stat_id=clientStatID;

	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);

	INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, `timestamp`,  is_success, status_code, manual_update, currency_code)
	SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, winAmount, transactionRef, roundRef, null, clientStatID, GamePlayID, NOW(), 1, statusCode, 0, amountCurrency 
	FROM gaming_payment_transaction_type AS transaction_type
	JOIN gaming_game_manufacturers ON gaming_game_manufacturers.name = gameManufacturerName
	WHERE transaction_type.name='BonusAwarded';
	
	SET cwTransactionID=LAST_INSERT_ID(); 
 	


	-- in proc we are commmiting as not to lock hence this should be the last step
	IF (Complete = 1) THEN
	 	CALL BonusFreeRoundsOnRedeemUpdateStats(bonusInstanceID,GamePlayID);

		SELECT gaming_bonus_types_awarding.name INTO awardingType
		FROM gaming_bonus_rules 
		JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
		WHERE gaming_bonus_rules.bonus_rule_id = bonusRuleID;

		IF (awardingType='CashBonus') THEN
			CALL BonusRedeemAllBonus(bonusInstanceID, sessionID, -1, 'CashBonus','CashBonus', GamePlayID);
		END IF;
	END IF;

	CALL CommonWalletPlayReturnData(cwTransactionID);
	SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
    SET statusCode = 0; 
    
END root$$

DELIMITER ;

