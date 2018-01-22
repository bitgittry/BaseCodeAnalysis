DROP procedure IF EXISTS `BonusExchangeRollBackFreeRounds`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusExchangeRollBackFreeRounds`(cwFreeRoundID BIGINT, clientStatID BIGINT, numFreeRoundsUsed INT, roundRef BIGINT, GameRoundID BIGINT, winAmount DECIMAL (18,5), transactionRef VARCHAR(80), gameManufacturerName VARCHAR(80), amountCurrency CHAR(3), OUT statusCode INT)
root: BEGIN
 
	DECLARE CurrencyID, GameID, SessionID, GameSessionID, PlatformTypeID, GamePlayID, bonusInstanceID, bonusRuleID BIGINT DEFAULT -1;
	DECLARE ExchangeRate DECIMAL(18,5);
	DECLARE Complete, isAlreadyProcessed TINYINT(1) DEFAULT 0;
	DECLARE cwTransactionID BIGINT DEFAULT NULL;
	DECLARE awardingType VARCHAR(80) DEFAULT NULL;
	
	SET statusCode = 1;

	SELECT gaming_bonus_instances.bonus_rule_id, gaming_bonus_instances.bonus_instance_id, gaming_client_stats.currency_id, game_id_awarded
	INTO bonusRuleID, bonusInstanceID, CurrencyID, GameID
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
	
	/* New Update */
	
	UPDATE gaming_cw_free_rounds
	JOIN gaming_bonus_instances ON gaming_cw_free_rounds.cw_free_round_id = gaming_bonus_instances.cw_free_round_id
	JOIN gaming_cw_free_round_statuses ON gaming_cw_free_round_statuses.name = 'StartedBeingUsed'
	JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id =gaming_client_stats.client_stat_id
	JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
	JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
	JOIN gaming_operators ON gaming_operators.is_main_operator=1 AND gaming_operator_currency.operator_id=gaming_operators.operator_id
	LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
	SET gaming_cw_free_rounds.cw_free_round_status_id = gaming_cw_free_round_statuses.cw_free_round_status_id,
		free_rounds_remaining=free_rounds_remaining+numFreeRoundsUsed,
		win_total = win_total -  winAmount,
		gaming_client_stats.current_free_rounds_amount = current_free_rounds_amount + (cost_per_round * numFreeRoundsUsed),
		gaming_client_stats.current_free_rounds_num = current_free_rounds_num + numFreeRoundsUsed,
		gaming_client_stats.current_free_rounds_win_locked = current_free_rounds_win_locked - winAmount,
		gaming_client_stats.total_free_rounds_played_num = total_free_rounds_played_num - numFreeRoundsUsed,

		-- New Updates
		gaming_bonus_instances.bonus_amount_remaining = 0,
		gaming_bonus_instances.is_free_rounds_mode = 1,
		gaming_client_stats.current_free_rounds_win_locked = gaming_client_stats.current_free_rounds_win_locked + winAmount,
		gaming_client_stats.total_free_rounds_win_transferred = gaming_client_stats.total_free_rounds_win_transferred - winAmount,
		gaming_client_stats.current_bonus_balance = gaming_client_stats.current_bonus_balance - winAmount,
		gaming_client_stats.total_bonus_awarded = gaming_client_stats.total_bonus_awarded - winAmount,
		gaming_client_stats.total_bonus_won = gaming_client_stats.total_bonus_won - winAmount,
		gaming_client_stats.total_bonus_won_base = gaming_client_stats.total_bonus_won_base - winAmount
	WHERE bonus_instance_id = bonusInstanceID;


/* New Update */
	INSERT INTO gaming_game_plays
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus,amount_free_bet, amount_bonus_win_locked, amount_other, bonus_lost, jackpot_contribution, timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, is_win_placed, is_processed, currency_id, round_transaction_no, game_play_message_type_id, extra_id, license_type_id, pending_bet_real, pending_bet_bonus, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, platform_type_id) 
	SELECT bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus,bet_free_bet, bet_bonus_win_locked, 0, bet_bonus_lost, jackpot_contribution, NOW(), game_id, game_manufacturer_id, operator_game_id, gaming_game_rounds.client_id, gaming_game_rounds.client_stat_id, SessionID, GameSessionID, game_round_id, gaming_payment_transaction_type.payment_transaction_type_id, balance_real_after, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, 0, 0, gaming_client_stats.currency_id, 1, game_play_message_type_id, bonusInstanceID, license_type_id, pending_bets_real, pending_bets_bonus, 0, current_loyalty_points, 0, total_loyalty_points_given_bonus-total_loyalty_points_used_bonus,PlatformTypeID
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_payment_transaction_type.name='BetCancelled' AND gaming_client_stats.client_stat_id=clientStatID
	JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id=GameRoundID
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name='InitialBet' COLLATE utf8_general_ci;

	SET GamePlayID=LAST_INSERT_ID();

	INSERT INTO gaming_game_plays_cw_free_rounds (game_play_id, amount_free_round, balance_free_round_after, balance_free_round_win_after, cw_free_round_id)
	SELECT GamePlayID, bet_free_round, current_free_rounds_amount, current_free_rounds_win_locked+winAmount, cwFreeRoundID
	FROM gaming_client_stats
	JOIN gaming_game_rounds_cw_free_rounds ON gaming_game_rounds_cw_free_rounds.game_round_id=GameRoundID
	WHERE gaming_client_stats.client_stat_id=clientStatID;

	INSERT INTO gaming_game_plays  
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, license_type_id, pending_bet_real, pending_bet_bonus, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, sign_mult) 
	SELECT win_total, win_total_base, exchange_rate, win_real, winAmount, win_bonus_win_locked, winAmount, bonus_lost, bonus_win_locked_lost, 0, NOW(), game_id, game_manufacturer_id, operator_game_id, gaming_game_rounds.client_id, gaming_game_rounds.client_stat_id, SessionID, GameSessionID, game_round_id, gaming_payment_transaction_type.payment_transaction_type_id, 1, balance_real_after, current_bonus_balance + current_bonus_win_locked_balance, current_bonus_win_locked_balance, gaming_client_stats.currency_id, 2, game_play_message_type_id, 1, pending_bets_real, pending_bets_bonus, PlatformTypeID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus), -1
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_payment_transaction_type.name='WinCancelled' AND gaming_client_stats.client_stat_id=clientStatID
	JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id=GameRoundID
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=IF(winAmount>0,'HandWins','HandLoses')  COLLATE utf8_general_ci;

	UPDATE gaming_game_plays SET game_play_id_win=gamePlayID WHERE game_play_id=GamePlayID;

	SET GamePlayID=LAST_INSERT_ID();

	INSERT INTO gaming_game_plays_cw_free_rounds (game_play_id,amount_free_round_win,balance_free_round_after,balance_free_round_win_after,cw_free_round_id)
	SELECT GamePlayID,win_free_round,current_free_rounds_amount,current_free_rounds_win_locked,cwFreeRoundID
	FROM gaming_client_stats
	JOIN gaming_game_rounds_cw_free_rounds ON gaming_game_rounds_cw_free_rounds.game_round_id=GameRoundID
	WHERE gaming_client_stats.client_stat_id=clientStatID;
	


	UPDATE gaming_game_rounds SET
		bet_total = 0, bet_total_base = 0, exchange_rate = 0, bet_real = 0, bet_bonus = 0, bet_bonus_win_locked = 0,bet_free_bet = 0, bet_bonus_lost = 0, jackpot_contribution = 0, num_bets = 0, 
		num_transactions = 0, balance_real_before = 0, balance_bonus_before = 0, loyalty_points = 0, loyalty_points_bonus = 0, win_total = 0, win_total_base = 0, win_real = 0, win_bonus = 0,
		win_free_bet = 0,win_bonus_win_locked = 0, win_bet_diffence_base = 0,bonus_lost = 0, bonus_win_locked_lost = 0,  balance_real_after = 0, balance_bonus_after = 0, is_cancelled = 1
	WHERE game_round_id = GameRoundID;


 
	/* New Update */
	UPDATE gaming_game_rounds_cw_free_rounds SET bet_free_round = 0,win_free_round = 0 WHERE game_round_id = GameRoundID;
		


	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);
	
	SET cwTransactionID=LAST_INSERT_ID(); 

    SET statusCode = 0; 
END root$$

DELIMITER ;

