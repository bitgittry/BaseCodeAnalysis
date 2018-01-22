DROP procedure IF EXISTS `CommonWalletP2PlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletP2PlaceBet`(clientStatID BIGINT, sbBetID BIGINT,sbExtraId BIGINT,betExtRef BIGINT, transactionRef VARCHAR(80), gameManufacturerID BIGINT, OUT statusCode INT)
root:BEGIN 
	
	DECLARE betAmount, exchangeRate, betAmountBase, balanceRealAfter, balanceBonusAfter,balanceBonusWinLockedAfter,pendingBetsReal,pendingBetsBonus DECIMAL(18, 5);
	DECLARE clientID,sessionID,sessionStatusCode,licenseType,currencyID, fraudClientEventID,clientWagerTypeID,prevStatusCode,roundId BIGINT;
	DECLARE isAccountClosed, isPlayAllowed,playLimitEnabled, fraudEnabled, playerRestrictionEnabled,disallowPlay,isLimitExceeded,alreadyProcessed TINYINT(1) DEFAULT 0;
	DECLARE NumSingles, NumMultiples INT; 
	DECLARE varUsername VARCHAR(80);

	SELECT client_id, current_real_balance, current_bonus_balance,current_bonus_win_locked_balance,pending_bets_real,pending_bets_bonus
	INTO clientID, balanceRealAfter, balanceBonusAfter,balanceBonusWinLockedAfter,pendingBetsReal,pendingBetsBonus
	FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;

	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3
	INTO playLimitEnabled, fraudEnabled, playerRestrictionEnabled
	FROM gaming_settings gs1 
    LEFT JOIN gaming_settings gs2 ON (gs2.name='FRAUD_ENABLED')
    LEFT JOIN gaming_settings gs3 ON (gs3.name='PLAYER_RESTRICTION_ENABLED')
	WHERE gs1.name='PLAY_LIMIT_ENABLED';

	SELECT 1, detailed_status_code INTO alreadyProcessed,prevStatusCode FROM gaming_sb_bets 
	WHERE client_stat_id = clientStatID AND  transaction_ref = transactionRef AND status_code != 1 LIMIT 1;

	IF (alreadyProcessed) THEN 
		SET statusCode=prevStatusCode; 

		SELECT current_real_balance 
		FROM gaming_client_stats 
		WHERE client_stat_id=clientStatId;

		LEAVE root;
	END IF;

	SELECT bet_total, gaming_sb_bets.client_stat_id, currency_id, num_singles,num_multiplies
	INTO betAmount, clientStatId, currencyID, NumSingles,NumMultiples
	FROM gaming_sb_bets
	JOIN gaming_client_stats ON gaming_sb_bets.client_stat_id = gaming_client_stats.client_stat_id
	WHERE sb_bet_id=sbBetID;

	SET licenseType = 3;

	SELECT IF(gaming_clients.is_account_closed OR gaming_fraud_rule_client_settings.block_account,1,0), gaming_clients.is_play_allowed AND !gaming_fraud_rule_client_settings.block_gameplay, sessions_main.session_id, sessions_main.status_code,username
	INTO isAccountClosed, isPlayAllowed, sessionID, sessionStatusCode,varUsername
	FROM gaming_clients
    LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
	JOIN sessions_main ON sessions_main.extra_id=gaming_clients.client_id AND sessions_main.is_latest
	WHERE gaming_clients.client_id=clientID;

	
	IF (clientStatId <> clientStatID) THEN 
		SET statusCode=1;
	ELSEIF (balanceRealAfter < betAmount) THEN
		 UPDATE gaming_sb_bets_p2 SET result='error', error_code=1005, error_message='Not enough money on user account' where sb_bet_id=betExtRef;
		SET statusCode=2;
	ELSEIF (betAmount < 0) THEN 
		 UPDATE gaming_sb_bets_p2 SET result='error', error_code=1097, error_message='Bet amount cannot be positive' WHERE sb_bet_id=betExtRef;
		SET statusCode=3;
	ELSEIF (isAccountClosed) THEN
		 UPDATE gaming_sb_bets_p2 SET result='error', error_code=2000, error_message='Player Account is closed' WHERE sb_bet_id=betExtRef;
		SET statusCode=4;
	ELSEIF (!isPlayAllowed) THEN 
		 UPDATE gaming_sb_bets_p2 SET result='error', error_code=2001, error_message='Player restricted from betting' WHERE sb_bet_id=betExtRef;
		SET statusCode=5;
	ELSEIF (sessionStatusCode!=1) THEN 
		 UPDATE gaming_sb_bets_p2 SET result='error', error_code=2002, error_message='Expired or invalid session' WHERE sb_bet_id=betExtRef;
		SET statusCode=6;
	END IF;

	IF (statusCode=0 AND playerRestrictionEnabled) THEN
		SET @numRestrictions=0;
		SET @restrictionType=NULL;
		SELECT restriction_types.name, COUNT(*) INTO @restrictionType, @numRestrictions
		FROM gaming_player_restrictions
		JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_play=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
		LEFT JOIN gaming_license_type ON gaming_player_restrictions.license_type_id=gaming_license_type.license_type_id
		WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date AND
			(gaming_license_type.name IS NULL OR gaming_license_type.name=licenseType);

		IF (@numRestrictions > 0) THEN
			 UPDATE gaming_sb_bets_p2 SET result='error', error_code=2003, error_message='Player restricted from play' WHERE sb_bet_id=betExtRef;
			SET statusCode=7;
		END IF;
	END IF;  
  
  
	IF (statusCode=0 AND fraudEnabled) THEN
		SELECT fraud_client_event_id, disallow_play 
		INTO fraudClientEventID, disallowPlay
		FROM gaming_fraud_client_events 
		JOIN gaming_fraud_classification_types ON gaming_fraud_client_events.client_stat_id=clientStatID AND gaming_fraud_client_events.is_current=1
			AND gaming_fraud_client_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id;

		IF (fraudClientEventID<>-1 AND disallowPlay=1) THEN
			 UPDATE gaming_sb_bets_p2 SET result='error', error_code=2004, error_message='Dissallow play by fraud' WHERE sb_bet_id=betExtRef;
			SET statusCode=8;
		END IF;
	END IF;
  
  
	IF (statusCode=0 AND playLimitEnabled) THEN 
		SET isLimitExceeded=PlayLimitCheckExceeded(betAmount, sessionID, clientStatID, licenseType);
		IF (isLimitExceeded>0) THEN
			 UPDATE gaming_sb_bets_p2 SET result='error', error_code=2005, error_message='Player play limit reached' WHERE sb_bet_id=betExtRef;
			SET statusCode=9;
		END IF;
	END IF;

	IF (statusCode != 0) THEN
		UPDATE gaming_sb_bets SET status_code = 2, detailed_status_code = statusCode WHERE sb_bet_id = sbBetID;

		SELECT current_real_balance 
		FROM gaming_client_stats 
		WHERE client_stat_id=clientStatId;
		LEAVE root;
	END IF;

	SELECT gaming_operator_currency.currency_id, exchange_rate INTO currencyID, exchangeRate FROM gaming_operator_currency
	JOIN gaming_operators ON  gaming_operators.operator_id=gaming_operator_currency.operator_id
	JOIN gaming_currency ON gaming_currency.currency_id=gaming_operator_currency.currency_id
	WHERE gaming_operators.is_main_operator=1 AND gaming_currency.currency_id=currencyID; 


	SET betAmountBase = IFNULL((betAmount/exchangeRate), 0);

	SET balanceRealAfter = balanceRealAfter - betAmount;

	SELECT client_wager_type_id INTO clientWagerTypeID FROM gaming_client_wager_types WHERE name='sb'; 

	UPDATE gaming_client_stats 
	LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
	SET 
		
		current_real_balance=current_real_balance-betAmount,total_real_played_base=total_real_played_base - betAmountBase,total_real_played=total_real_played-betAmount,last_played_date=NOW(),
	  
	  gcss.total_bet=gcss.total_bet+betAmount,gcss.total_bet_base=gcss.total_bet_base - betAmountBase, gcss.bets=gcss.bets+1, gcss.total_bet_real=gcss.total_bet_real+betAmount,
	  
	  gcws.num_bets=gcws.num_bets+1, gcws.total_real_wagered=gcws.total_real_wagered + betAmount, gcws.first_wagered_date=IFNULL(gcws.first_wagered_date, NOW()), gcws.last_wagered_date=NOW()
	WHERE gaming_client_stats.client_stat_id=clientStatId;

	INSERT INTO gaming_game_rounds
			(bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,bet_free_bet, num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, sb_bet_id, sb_extra_id, sb_odd, license_type_id) 
	SELECT betAmount, betAmountBase, exchangeRate, betAmount, 0, 0, 0, 1, 1, NOW(), gameManufacturerID, clientID, clientStatID, 0, IF(NumSingles>0,4,5), currencyID, sbBetID, sbExtraId, 1, licenseType;
	SET roundId = LAST_INSERT_ID();

	INSERT INTO gaming_game_plays 
			(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, is_win_placed, is_processed, currency_id, round_transaction_no, game_play_message_type_id, sign_mult, sb_bet_id,sb_extra_id, license_type_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT bet_total, bet_total_base, exchangeRate, bet_real, bet_bonus, bet_bonus_win_locked,bet_free_bet, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, game_round_id, 12,balanceRealAfter, balanceBonusAfter,balanceBonusWinLockedAfter, 0, 0, currencyID, 1, 8, -1, sbBetID,sb_extra_id, 3, pendingBetsReal, pendingBetsBonus,0,loyalty_points,0,loyalty_points_bonus
	FROM gaming_game_rounds
	WHERE game_round_id = roundId; 

	CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());  

	INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, units)
	SELECT gaming_game_plays.game_play_id, gaming_game_plays.payment_transaction_type_id, gaming_game_plays.amount_total, gaming_game_plays.amount_total_base, gaming_game_plays.amount_real, gaming_game_plays.amount_real/exchange_rate, gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/exchange_rate, gaming_game_plays.timestamp, gaming_game_plays.exchange_rate, gaming_game_plays.game_manufacturer_id, clientID, clientStatID, currencyID, 6,
		gaming_game_plays.round_transaction_no, 0, 0,0, 0,0, 0, gaming_game_plays.sb_bet_id, @singleMultTypeID, 0, 1
	FROM gaming_game_plays
	WHERE gaming_game_plays.sb_bet_id=sbBetID AND gaming_game_plays.game_play_message_type_id=8;

	IF (playLimitEnabled) THEN 
		CALL PlayLimitsUpdate(clientStatID, licenseType, betAmount, 1);
	END IF;

	UPDATE gaming_sb_bets_p2 SET result='ok', after_balance=balanceRealAfter, round_id = roundId where sb_bet_id=betExtRef;

	UPDATE gaming_sb_bets SET status_code = 5, detailed_status_code =0 WHERE sb_bet_id = sbBetID;

	SELECT current_real_balance FROM gaming_client_stats WHERE client_stat_id=clientStatId;

	SET statusCode = 0;
END root$$

DELIMITER ;

