DROP procedure IF EXISTS `CommonWalletCasinoPlaceWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCasinoPlaceWin`(
  externalGameSessionId VARCHAR(80), clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80),
  roundRef VARCHAR(50), gameRef VARCHAR(80), winAmount DECIMAL(18, 5), jackpotAmount DECIMAL(18, 5), amountCurrency CHAR(3),
  canCommit TINYINT(1), isManualUpdate TINYINT(1), closeRound TINYINT(1), ignoreSessionExpiry TINYINT(1), extendSessionExpiry TINYINT(1), 
  transactionComment TEXT, minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN

  -- Parameter: minimalData
  -- jackpot flow

  DECLARE sessionID, gameManufacturerID, gameRoundID, clientStatIDCheck, plCurrencyID BIGINT DEFAULT -1;
  DECLARE clearBonusLost, cwCloseRoundOnWin, isAlreadyProcessed, cwNoRound,hasAlphanumericRoundRefs TINYINT(1) DEFAULT 0; 
  DECLARE gamePlayIDReturned, cwTransactionID, jpWinGamePlayIDReturned, gameSessionID, numericRoundRef,gameID BIGINT DEFAULT NULL;
  DECLARE transactionType VARCHAR(40) DEFAULT NULL;
  DECLARE isJackpotWin, jackpotWinMoneyFlowAsNormalWin TINYINT(1) DEFAULT 0;
  DECLARE sessionStatusCode INT DEFAULT 0;
  DECLARE plCurrencyCode VARCHAR(3) DEFAULT NULL;
  DECLARE originalTotalAmount, exchangeRate, origWinAmt DECIMAL(18,5) DEFAULT NULL;
  DECLARE jpWinAmt DECIMAL(18,5) DEFAULT NULL;
  DECLARE jpComment VARCHAR(30) DEFAULT NULL;
  
  IF (externalGameSessionId IS NULL) THEN
    
    IF (gameRef IS NULL OR gameRef='') THEN
      SELECT gaming_games.manufacturer_game_idf INTO gameRef
      FROM gaming_game_rounds 
      JOIN gaming_game_manufacturers ON gaming_game_manufacturers.name=gameManufacturerName AND gaming_game_rounds.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
      JOIN gaming_games ON gaming_game_rounds.game_id=gaming_games.game_id
      WHERE gaming_game_rounds.round_ref=roundRef AND gaming_game_rounds.client_stat_id=clientStatID  
      ORDER BY date_time_start DESC, game_round_id DESC LIMIT 1;
    END IF;

    CALL CommonWalletGeneralGetGameSession(clientStatID, gameManufacturerName, gameRef, gameSessionID);
	
  END IF;
  
  SELECT client_stat_id, currency_id INTO clientStatIDCheck, plCurrencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN 
	SET statusCode=101; 
	LEAVE root;
  END IF;
  
  IF(jackpotAmount > 0) THEN
	SET transactionType='PJWin';
	SET isJackpotWin = 1;
  ELSE
	SET transactionType='Win';
  END IF;
  
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    LEAVE root;
  END IF;

  IF (gameSessionID IS NOT NULL) THEN
		SET ignoreSessionExpiry=ignoreSessionExpiry OR isManualUpdate; 
		SET extendSessionExpiry=1; 
		CALL CommonWalletCheckGameSessionByID(gameSessionID, ignoreSessionExpiry, extendSessionExpiry, canCommit, sessionStatusCode);
	ELSE
		SET statusCode=11;
		LEAVE root;
  END IF;
  
  IF (sessionStatusCode!=0) THEN 
	IF(sessionStatusCode=1) THEN
		SET statusCode=11;
		LEAVE root;
	ELSE
		SET statusCode=7;
		LEAVE root;
	END IF;
  END IF;  
  
  SELECT gaming_game_sessions.session_id, gaming_game_sessions.game_manufacturer_id, cw_close_round_onwin, cw_no_round, gaming_game_manufacturers.has_alphanumeric_round_refs,game_id
  INTO sessionID, gameManufacturerID, cwCloseRoundOnWin, cwNoRound,hasAlphanumericRoundRefs,gameID
  FROM gaming_game_sessions 
  JOIN gaming_game_manufacturers ON gaming_game_sessions.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  WHERE gaming_game_sessions.game_session_id=gameSessionID;
  
  IF (amountCurrency IS NOT NULL) THEN
    
	SELECT currency_code INTO plCurrencyCode
	FROM gaming_currency
	WHERE currency_id = plCurrencyID;
	
	SET originalTotalAmount=winAmount + jackpotAmount;
	SET origWinAmt = winAmount;

	CALL CurrencyExchangeAmt(origWinAmt, amountCurrency, plCurrencyCode, winAmount, exchangeRate);
	IF(winAmount IS NULL) THEN 
		SET statusCode=660;
		LEAVE root;
	END IF;

	SET winAmount = CEILING(winAmount); 
	
    IF(jackpotAmount > 0) THEN
		CALL CurrencyExchangeAmt(jackpotAmount, amountCurrency, plCurrencyCode, jpWinAmt, exchangeRate); 
		SET jpWinAmt = CEILING(jpWinAmt); 
    END IF;
  ELSE
    
    SET originalTotalAmount=winAmount + jackpotAmount;
	SET jpWinAmt = jackpotAmount;
  END IF;

   
  IF (hasAlphanumericRoundRefs) THEN
		IF (cwNoRound=0) THEN 
			-- Check if RoundRef has already been stored in gaming_cw_rounds
			SELECT cw_round_id INTO numericRoundRef FROM gaming_cw_rounds WHERE client_stat_id=clientStatID AND game_manufacturer_id=gameManufacturerID AND manuf_round_ref=roundRef;
			  
			  SELECT game_round_id INTO gameRoundID
			  FROM gaming_game_rounds  FORCE INDEX (client_game_round_ref)
			  WHERE round_ref=numericRoundRef AND client_stat_id=clientStatID AND game_id=gameID AND is_round_finished=0  
			  ORDER BY game_round_id DESC LIMIT 1;
			  
			IF (numericRoundRef IS NULL) AND (gameRoundID = -1) THEN
				-- no round found throw error
				SET statusCode=1;
				LEAVE root;
			END IF;
		END IF;
  ELSE
	  SELECT game_round_id INTO gameRoundID
      FROM gaming_game_rounds  FORCE INDEX (client_game_round_ref)
	  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID AND is_round_finished=0  
      ORDER BY game_round_id DESC LIMIT 1;
  END IF;  
  
  
  IF (gameRoundID=-1) THEN
	IF (cwNoRound=1) THEN  
		IF(exchangeRate IS NULL) THEN
			SELECT exchange_rate INTO exchangeRate 
			FROM gaming_client_stats
			JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
			WHERE gaming_client_stats.client_stat_id=clientStatID
			LIMIT 1;
		END IF;
	  
		INSERT INTO gaming_game_rounds
		(bet_total, bet_total_base, bet_real, bet_bonus, bet_bonus_win_locked, bet_bonus_lost, jackpot_contribution, num_bets, num_transactions, date_time_start, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, round_ref, exchange_rate) 
		SELECT 0, 0, 0, 0, 0, 0, 0, 0, 0, NOW(), gaming_game_sessions.game_id, gaming_game_sessions.game_manufacturer_id, gaming_game_sessions.operator_game_id, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, 0, gaming_game_round_types.game_round_type_id, gaming_client_stats.currency_id, roundRef, exchangeRate 
		FROM gaming_game_round_types
		JOIN gaming_game_sessions ON gaming_game_round_types.name='Normal' AND gaming_game_sessions.game_session_id=gameSessionID
		JOIN gaming_client_stats ON gaming_game_sessions.client_stat_id=gaming_client_stats.client_stat_id; 
		
		SET gameRoundID=LAST_INSERT_ID();
	ELSE
		SET statusCode=1;
		LEAVE root;
	END IF;
  END IF;
  
  SET closeRound=IFNULL(closeRound, IFNULL(cwCloseRoundOnWin, 0));  
  SET clearBonusLost = 1;
  SET @returnData=1;

  SELECT value_bool INTO jackpotWinMoneyFlowAsNormalWin FROM gaming_settings WHERE name='JACKPOT_WIN_MONEY_FLOW_AS_NORMAL_WIN';
    
  IF(isJackpotWin=1 AND jackpotWinMoneyFlowAsNormalWin=0) THEN
    CALL PlaceJackpotWin(gameRoundID, sessionID, gameSessionID, jpWinAmt, transactionRef, @returnData, jpWinGamePlayIDReturned, statusCode);
	SET jpComment = CONCAT('jpID: ', CAST(jpWinGamePlayIDReturned AS CHAR));
  ELSE
	  SET @wagerType='Type1';
	  SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
	  IF (@wagerType='Type2') THEN
		CALL PlaceWinTypeTwo(gameRoundID, sessionID, gameSessionID, winAmount, clearBonusLost, transactionRef, closeRound, isJackpotWin, 
			@returnData, minimalData, gamePlayIDReturned, statusCode);   
	  ELSE
		CALL PlaceWin(gameRoundID, sessionID, gameSessionID, winAmount, clearBonusLost, transactionRef, closeRound, isJackpotWin, 
			@returnData, minimalData, gamePlayIDReturned, statusCode);
	  END IF;
  END IF;

  
  INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, `timestamp`, other_data, is_success, status_code, manual_update, currency_code, exchange_rate)
  SELECT gameManufacturerID, transaction_type.payment_transaction_type_id, originalTotalAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), CONCAT_WS(',', jpComment, transactionComment), IF(statusCode=0,1,0), statusCode, isManualUpdate, amountCurrency, exchangeRate
  FROM gaming_payment_transaction_type AS transaction_type
  WHERE transaction_type.name=transactionType;
   
  SET cwTransactionID=LAST_INSERT_ID();
  
  IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
 
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
END root$$

DELIMITER ;

