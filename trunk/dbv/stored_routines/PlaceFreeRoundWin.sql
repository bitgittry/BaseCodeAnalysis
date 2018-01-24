DROP procedure IF EXISTS `PlaceFreeRoundWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceFreeRoundWin`(cwFreeRoundID BIGINT, clientStatID BIGINT, roundRef VARCHAR(80), gameRef VARCHAR(80), winAmount DECIMAL (18,5), transactionRef VARCHAR(80), gameManufacturerName VARCHAR(80), CloseRound TINYINT(1), OUT statusCode INT)
root: BEGIN
	DECLARE CurrencyID, GameID, SessionID, GameSessionID, PlatformTypeID, GameManufacturerID, bonusInstanceID, bonusRuleID, WinGamePlayID, BetGamePlayID BIGINT DEFAULT -1;
	DECLARE FreeRoundsRemaining INT DEFAULT -1;
	DECLARE CostPerFreeRound,ExchangeRate, BonusAmountGiven, BetTotal DECIMAL(18,5);
	DECLARE Complete, isAlreadyProcessed, hasAlphanumericRoundRefs TINYINT(1) DEFAULT 0;
	DECLARE cwTransactionID BIGINT DEFAULT NULL;
	DECLARE awardingType VARCHAR(80) DEFAULT NULL;
	DECLARE PlayerCurrencyCode VARCHAR(3) DEFAULT NULL;
	DECLARE numericRoundRef, GameRoundID BIGINT DEFAULT NULL;

	SET statusCode = 1;

	IF (gameRef is NULL) THEN
		SET gameRef = (select gaming_games.manufacturer_game_idf  from gaming_game_sessions
				JOIN gaming_games ON gaming_game_sessions.game_id = gaming_games.game_id 
				where gaming_game_sessions.client_stat_id = clientStatID and gaming_game_sessions.cw_game_latest = 1 order by gaming_game_sessions.game_session_id desc limit 1);
	END IF;

	IF (gameManufacturerName='ThirdPartyClient') THEN
		SELECT ggm.name 
		INTO gameManufacturerName
		FROM gaming_games AS gg
		JOIN gaming_game_manufacturers AS ggm ON gg.game_manufacturer_id=ggm.game_manufacturer_id
		WHERE gg.manufacturer_game_idf=gameRef
		LIMIT 1;
    END IF;
		
	CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, 'BonusAwarded', cwTransactionID, isAlreadyProcessed, statusCode);
	IF (isAlreadyProcessed) THEN
		SET statusCode=100; 
		LEAVE root;
	END IF;

	CALL CommonWalletGeneralGetGameSession(clientStatID, gameManufacturerName, gameRef, GameSessionID);
    IF (GameSessionID IS NULL) THEN 
		SET statusCode=11; 
		LEAVE root; 
	END IF;

	SELECT gaming_game_manufacturers.has_alphanumeric_round_refs INTO hasAlphanumericRoundRefs
	FROM gaming_game_manufacturers WHERE gaming_game_manufacturers.name = gameManufacturerName; -- the right manufacturer is known.

	SELECT gaming_bonus_instances.bonus_rule_id, gaming_bonus_instances.bonus_instance_id, free_rounds_remaining, game_manufacturer_id,cost_per_round,gaming_client_stats.currency_id, game_id_awarded, gaming_currency.currency_code
	INTO bonusRuleID, bonusInstanceID, FreeRoundsRemaining, GameManufacturerID, CostPerFreeRound,  CurrencyID, GameID,PlayerCurrencyCode
	FROM gaming_cw_free_rounds 
	JOIN gaming_bonus_instances ON gaming_bonus_instances.cw_free_round_id = gaming_cw_free_rounds.cw_free_round_id
	JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id = gaming_client_stats.client_stat_id
    JOIN gaming_currency ON gaming_currency.currency_id = gaming_client_stats.currency_id
	WHERE gaming_cw_free_rounds.cw_free_round_id=cwFreeRoundID AND gaming_cw_free_rounds.client_stat_id=clientStatID AND gaming_bonus_instances.is_active = 1 FOR UPDATE;

    IF (bonusInstanceID=-1) THEN
		SET statusCode = 1;
		LEAVE root;
    END IF;

	SELECT exchange_rate,gaming_game_sessions.session_id,game_session_id,platform_type_id INTO ExchangeRate, SessionID, GameSessionID, PlatformTypeID
	FROM gaming_operator_currency
	LEFT JOIN gaming_game_sessions ON gaming_game_sessions.client_stat_id = clientStatID AND gaming_game_sessions.game_id = GameID AND cw_game_latest = 1
	LEFT JOIN sessions_main ON gaming_game_sessions.session_id = sessions_main.session_id
	WHERE gaming_operator_currency.currency_id = CurrencyID;
	

	IF (FreeRoundsRemaining = 0 ) THEN
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
		win_total = win_total +  winAmount,
		gaming_client_stats.current_free_rounds_win_locked = current_free_rounds_win_locked + winAmount
	WHERE bonus_instance_id = bonusInstanceID;

	IF (hasAlphanumericRoundRefs) THEN
		SELECT cw_round_id INTO numericRoundRef FROM gaming_cw_rounds WHERE client_stat_id=clientStatID AND game_manufacturer_id=gameManufacturerID AND manuf_round_ref=roundRef;
	ELSE
		SELECT CONVERT(roundRef,UNSIGNED INTEGER) INTO numericRoundRef;
	END IF;

	SELECT gaming_game_rounds.game_round_id, bet_total 
	INTO  GameRoundID, BetTotal
	FROM gaming_game_rounds
	WHERE 
		gaming_game_rounds.client_stat_id = clientStatID
	AND gaming_game_rounds.round_ref = numericRoundRef
	AND gaming_game_rounds.game_id = GameID
	AND gaming_game_rounds.game_manufacturer_id= GameManufacturerID
	ORDER BY gaming_game_rounds.game_round_id DESC LIMIT 1;

    IF (GameRoundID IS NULL) THEN
		SET statusCode = 99;
		LEAVE root;
    END IF;

	SET CloseRound = IF(CloseRound = 1, 1, 0);-- sanitise

	IF (winAmount > 0) THEN
		-- update wins amount and close round if is the case
		UPDATE gaming_game_rounds
		SET win_bet_diffence_base = (winAmount-BetTotal)/ExchangeRate,
			win_total=winAmount ,
			win_total_base=winAmount/ExchangeRate,
			is_round_finished = IF(CloseRound = 1, 1, is_round_finished)
		WHERE 
			gaming_game_rounds.game_round_id = GameRoundID;

		UPDATE gaming_game_rounds_cw_free_rounds
			SET win_free_round = winAmount
		WHERE gaming_game_rounds_cw_free_rounds.game_round_id = GameRoundID;
	ELSE
		-- close round if is the case
		IF (CloseRound = 1) THEN
			UPDATE gaming_game_rounds
			SET is_round_finished = IF(CloseRound=1, 1, is_round_finished)
			WHERE 
				gaming_game_rounds.game_round_id = GameRoundID;
		END IF;
	END IF;

	INSERT INTO gaming_game_plays 
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, license_type_id, pending_bet_real, pending_bet_bonus, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT win_total, win_total_base, exchange_rate, win_real, win_bonus, win_bonus_win_locked,win_free_bet, bonus_lost, bonus_win_locked_lost, 0, NOW(), game_id, game_manufacturer_id, operator_game_id, gaming_game_rounds.client_id, gaming_game_rounds.client_stat_id, SessionID, GameSessionID, game_round_id, gaming_payment_transaction_type.payment_transaction_type_id, 1, balance_real_after, current_bonus_balance + current_bonus_win_locked_balance, current_bonus_win_locked_balance, gaming_client_stats.currency_id, 2, game_play_message_type_id, 1, pending_bets_real, pending_bets_bonus, PlatformTypeID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus)
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_payment_transaction_type.name='Win' AND gaming_client_stats.client_stat_id=clientStatID
	JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id=GameRoundID
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=IF(winAmount>0,'HandWins','HandLoses')  COLLATE utf8_general_ci;

	SET WinGamePlayID = LAST_INSERT_ID();


	SET BetGamePlayID = (SELECT game_play_id 
						 FROM gaming_game_plays 
						 JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.payment_transaction_type_id = gaming_game_plays.payment_transaction_type_id
						 JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id=gaming_game_plays.game_round_id 
						 AND gaming_payment_transaction_type.name='Bet'						 
						 -- AND gaming_payment_transaction_type.name='Win' -- CHECK
						 AND gaming_game_rounds.game_round_id = GameRoundID
						 ORDER BY game_play_id DESC
						 LIMIT 1 # Getting the last bet 
						);

	UPDATE gaming_game_plays SET game_play_id_win = WinGamePlayID WHERE game_play_id = BetGamePlayID;

	INSERT INTO gaming_game_plays_cw_free_rounds (game_play_id,amount_free_round_win,balance_free_round_after,balance_free_round_win_after,cw_free_round_id)
	SELECT WinGamePlayID,win_free_round,current_free_rounds_amount,current_free_rounds_win_locked,cwFreeRoundID
	FROM gaming_client_stats
	JOIN gaming_game_rounds_cw_free_rounds ON gaming_game_rounds_cw_free_rounds.game_round_id=GameRoundID
	WHERE gaming_client_stats.client_stat_id=clientStatID;

	CALL GameUpdateRingFencedBalances(clientStatID,WingamePlayID);

    SET statusCode = IFNULL(statusCode, 0); 
	INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, `timestamp`,  is_success, status_code, manual_update, currency_code)
	SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, winAmount, transactionRef, roundRef, null, clientStatID, WinGamePlayID, NOW(), 1, statusCode, 0, PlayerCurrencyCode 
	FROM gaming_payment_transaction_type AS transaction_type
	JOIN gaming_game_manufacturers ON gaming_game_manufacturers.name = gameManufacturerName
	WHERE transaction_type.name='BonusAwarded';
	
	SET cwTransactionID=LAST_INSERT_ID(); 
 	
	IF (Complete = 1  AND CloseRound = 1) THEN 

	 	CALL BonusFreeRoundsOnRedeemUpdateStats(bonusInstanceID,WingamePlayID);

		SELECT gaming_bonus_types_awarding.name INTO awardingType
		FROM gaming_bonus_rules 
		JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
		WHERE gaming_bonus_rules.bonus_rule_id = bonusRuleID;

		IF (awardingType='CashBonus') THEN
			CALL BonusRedeemAllBonus(bonusInstanceID, sessionID, -1, 'CashBonus','CashBonus', WinGamePlayID);
		END IF;

	END IF;

	CALL CommonWalletPlayReturnData(cwTransactionID);
	SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
	IF (Complete = 1  AND CloseRound = 1) THEN
		SELECT bonus_amount_given INTO BonusAmountGiven from gaming_bonus_instances where bonus_instance_id = bonusInstanceID;
		IF (BonusAmountGiven is NULL) then
			SELECT NULL AS bonusWon, bonusInstanceID as bonusLost;
		else
			SELECT  IF(BonusAmountGiven > 0, bonusInstanceID, NULL) AS bonusWon, 
					IF(BonusAmountGiven = 0, bonusInstanceID, NULL) AS bonusLost 
			FROM gaming_bonus_instances 
			WHERE bonus_instance_id=bonusInstanceID AND cw_free_round_id = cwFreeRoundID;
		END IF;
	END IF;
    SET statusCode = 0; 
END root$$

DELIMITER ;

