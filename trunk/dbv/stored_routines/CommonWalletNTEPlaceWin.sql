DROP procedure IF EXISTS `CommonWalletNTEPlaceWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletNTEPlaceWin`(
  clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80), roundRef BIGINT, gameRef VARCHAR(80), 
  winAmount DECIMAL(18, 5), varReason VARCHAR(80), canCommit TINYINT(1), transactionComment TEXT, minimalData TINYINT(1), 
  OUT statusCode INT)
root: BEGIN


  DECLARE gameSessionID BIGINT DEFAULT NULL;
  DECLARE gameID, sessionID, gameManufacturerID, gameRoundID, clientStatIDCheck, currencyID BIGINT DEFAULT -1;
  DECLARE clearBonusLost, cwCloseRoundOnWin, isAlreadyProcessed TINYINT(1) DEFAULT 0; 
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE transactionType, roundType VARCHAR(40) DEFAULT NULL;
  DECLARE isJackpotWin, isTournamentWin, closeRound, jackpotWinMoneyFlowAsNormalWin TINYINT(1) DEFAULT 0;
  DECLARE currencyCode, cwExchangeCurrency VARCHAR(3) DEFAULT NULL;
  DECLARE exchangeRate, originalAmount DECIMAL(18,5) DEFAULT NULL;
  
   	CASE varReason
		WHEN 'PLAY' THEN
				BEGIN
					SET isTournamentWin = 0;
					SET isJackpotWin = 0;
					SET closeRound = 0;
					SET transactionType = 'Win';
					SET roundType = 'Normal';
				END;
		WHEN 'PLAY_FINAL' THEN
				BEGIN
					SET isTournamentWin = 0;
					SET isJackpotWin = 0;
					SET closeRound = 1;
					SET transactionType = 'Win';
					SET roundType = 'Normal';
				END;
		WHEN 'JACKPOT_WIN' THEN
				BEGIN
					SET isTournamentWin = 0;
					SET isJackpotWin = 1;
					SET closeRound = 0;
					SET transactionType = 'PJWin';
					SET roundType = 'Normal';
				END;
		WHEN 'TOURNAMENT_WIN' THEN
				BEGIN
					SET isTournamentWin = 1;
					SET isJackpotWin = 0;
					SET closeRound = 0;
					SET transactionType = 'TournamentWin';
					SET roundType = 'Tournament';
				END;
		ELSE
				BEGIN
					SET statusCode=1;
					LEAVE root;
				END;
	END CASE;

  
  SELECT client_stat_id, currency_id INTO clientStatIDCheck, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN 
		SET statusCode=1; 
		LEAVE root; 
  END IF;

  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
	IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    LEAVE root;
  END IF;

  CALL CommonWalletGeneralGetGameSession(clientStatID, gameManufacturerName, gameRef, gameSessionID);
  IF (gameSessionID IS NULL AND isTournamentWin=0) THEN 
		SET statusCode=11; 
		LEAVE root;
  END IF;

  
  IF (gameManufacturerID!=-1 AND cwExchangeCurrency IS NOT NULL) THEN
    SELECT pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate INTO exchangeRate
    FROM gaming_operators
    JOIN gaming_currency ON gaming_currency.currency_code=cwExchangeCurrency
    JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gaming_currency.currency_id=gm_exchange_rate.currency_id 
    JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=currencyID 
    WHERE gaming_operators.is_main_operator=1;
  
    SET originalAmount=winAmount;
    SET winAmount=FLOOR(winAmount/exchangeRate);
    SET currencyCode=cwExchangeCurrency;
  ELSE
    SET originalAmount=winAmount;
  END IF;

  IF(isTournamentWin=1) THEN
	CALL CommonWalletNTEAdjustRealMoney(clientStatID, winAmount, NULL, transactionType, gameManufacturerName, gamePlayIDReturned, statusCode);
  ELSE
	
	SELECT gaming_game_sessions.game_id, gaming_game_sessions.session_id, gaming_game_sessions.client_stat_id, gaming_game_sessions.game_manufacturer_id, cw_close_round_onwin, cw_exchange_currency
	INTO gameID, sessionID, clientStatID, gameManufacturerID, cwCloseRoundOnWin, cwExchangeCurrency
	FROM gaming_game_sessions 
	JOIN gaming_game_manufacturers ON gaming_game_sessions.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
	WHERE gaming_game_sessions.game_session_id=gameSessionID;

	SELECT game_round_id INTO gameRoundID
	FROM gaming_game_rounds  FORCE INDEX (client_game_round_ref)
	WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID 
	ORDER BY date_time_start DESC, game_round_id DESC LIMIT 1;

	IF (gameRoundID=-1) THEN
		SET statusCode = 1;
		LEAVE root;
	END IF;

    SELECT value_bool INTO jackpotWinMoneyFlowAsNormalWin FROM gaming_settings WHERE name='JACKPOT_WIN_MONEY_FLOW_AS_NORMAL_WIN';
    
	IF(isJackpotWin=1 AND jackpotWinMoneyFlowAsNormalWin=0) THEN
        CALL PlaceJackpotWin(gameRoundID, sessionID, gameSessionID, winAmount, transactionRef, 0, gamePlayIDReturned, statusCode);
	ELSE
		SET clearBonusLost = 1;
		SET closeRound = IF(cwCloseRoundOnWin, 1, closeRound);

		SET @wagerType='Type1';
		SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
		IF (@wagerType='Type2') THEN
		  CALL PlaceWinTypeTwo(gameRoundID, sessionID, gameSessionID, winAmount, clearBonusLost, transactionRef, closeRound, 
			isJackpotWin, 0, minimalData, gamePlayIDReturned, statusCode);   
		ELSE
		  CALL PlaceWin(gameRoundID, sessionID, gameSessionID, winAmount, clearBonusLost, transactionRef, closeRound, 
			isJackpotWin, 0, minimalData, gamePlayIDReturned, statusCode);   
		END IF;
	END IF;
  END IF;

  

  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, `timestamp`, other_data, is_success, status_code, manual_update, currency_code, exchange_rate)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, originalAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), transactionComment, IF(statusCode=0,1,0), statusCode, 0, currencyCode, exchangeRate
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name=transactionType;
   
    SET cwTransactionID=LAST_INSERT_ID();
  END IF;
 
  SET isAlreadyProcessed=0;

  CALL CommonWalletPlayReturnData(cwTransactionID);

  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
END root$$

DELIMITER ;

