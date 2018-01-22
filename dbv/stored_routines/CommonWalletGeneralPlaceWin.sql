DROP procedure IF EXISTS `CommonWalletGeneralPlaceWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletGeneralPlaceWin`(
  gameSessionID BIGINT, clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80), roundRef BIGINT, gameRef VARCHAR(80), 
  winAmount DECIMAL(18, 5), varReason VARCHAR(80), canCommit TINYINT(1), manualUpdate TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN

  DECLARE sessionID, gameManufacturerID, gameManufacturerIDB, gameRoundID, clientStatIDCheck, currencyID BIGINT DEFAULT -1;
  DECLARE clearBonusLost, cwCloseRoundOnWin, isAlreadyProcessed TINYINT(1) DEFAULT 0; 
  DECLARE gamePlayIDReturned, cwTransactionID,gameID BIGINT DEFAULT NULL;
  DECLARE transactionType VARCHAR(40) DEFAULT NULL;
  DECLARE ignoreSessionExpiry, extendSessionExpiry, isJackpotWin, closeRound, jackpotWinMoneyFlowAsNormalWin TINYINT(1) DEFAULT 0;
  DECLARE sessionStatusCode INT DEFAULT 0;
  DECLARE currencyCode, cwExchangeCurrency VARCHAR(3) DEFAULT NULL;
  DECLARE exchangeRate, originalAmount, roundExchangeRate DECIMAL(18,5) DEFAULT NULL;
  
  SET isJackpotWin=IF(varReason='JACKPOT_WIN', 1, 0);
  SET closeRound=IF(varReason='PLAY_FINAL', 1, 0);
  
  SET transactionType='Win';
  SET clearBonusLost = 1;
  SELECT value_bool INTO jackpotWinMoneyFlowAsNormalWin FROM gaming_settings WHERE name='JACKPOT_WIN_MONEY_FLOW_AS_NORMAL_WIN';
    
  IF(isJackpotWin=1 AND jackpotWinMoneyFlowAsNormalWin=0) THEN
    SET transactionType='PJWin';
  END IF;
      
  SELECT client_stat_id, currency_id INTO clientStatIDCheck, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=1; LEAVE root; END IF;
  
  IF (gameSessionID IS NULL AND gameManufacturerName='ThirdPartyClient' AND gameRef<>'0') THEN
	SELECT ggm.name
	INTO gameManufacturerName
	FROM gaming_games AS gg
	JOIN gaming_game_manufacturers AS ggm ON gg.game_manufacturer_id=ggm.game_manufacturer_id
	WHERE gg.manufacturer_game_idf=gameRef
	LIMIT 1;
  END IF;

  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
    
  IF (gameSessionID IS NULL) THEN
    IF (gameRef IS NULL OR gameRef='' OR gameRef='0') THEN
      SELECT g.manufacturer_game_idf INTO gameRef
      FROM gaming_game_rounds AS r FORCE INDEX (client_round_ref) 
	  JOIN gaming_games AS g ON r.game_id=g.game_id
	  JOIN gaming_game_manufacturers AS m ON r.game_manufacturer_id=m.game_manufacturer_id
      WHERE r.round_ref=roundRef AND r.client_stat_id=clientStatID
      ORDER BY FIELD(m.name, 'ThirdPartyClient', gameManufacturerName) DESC, r.game_round_id DESC LIMIT 1;
    END IF;
    
    CALL CommonWalletGeneralGetGameSession(clientStatID, gameManufacturerName, gameRef, gameSessionID);
    IF (gameSessionID IS NULL) THEN SET statusCode=11; LEAVE root; END IF;
  END IF;
    
  SET ignoreSessionExpiry=1; SET extendSessionExpiry=0; 
  CALL CommonWalletCheckGameSessionByID(gameSessionID, ignoreSessionExpiry, extendSessionExpiry, canCommit, sessionStatusCode);
  
  SELECT gaming_game_sessions.session_id, gaming_game_sessions.client_stat_id, gaming_game_sessions.game_manufacturer_id, cw_close_round_onwin, cw_exchange_currency, game_id
  INTO sessionID, clientStatID, gameManufacturerID, cwCloseRoundOnWin, cwExchangeCurrency, gameID
  FROM gaming_game_sessions 
  JOIN gaming_game_manufacturers ON gaming_game_sessions.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  WHERE gaming_game_sessions.game_session_id=gameSessionID;
  
  IF (gameManufacturerID!=-1 AND cwExchangeCurrency IS NOT NULL) THEN
    SELECT pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate INTO exchangeRate
    FROM gaming_operators
    JOIN gaming_currency ON gaming_currency.currency_code=cwExchangeCurrency
    JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gaming_currency.currency_id=gm_exchange_rate.currency_id 
    JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=currencyID 
    WHERE gaming_operators.is_main_operator=1;
  
    SET originalAmount=winAmount;
    SET winAmount=FLOOR(winAmount*exchangeRate);
    SET currencyCode=cwExchangeCurrency;
  ELSE
    SET originalAmount=winAmount;
  END IF;
  
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID 
  ORDER BY gaming_game_rounds.round_ref DESC, game_round_id DESC LIMIT 1;
  
  IF (gameRoundID=-1) THEN
    
    SELECT exchange_rate into roundExchangeRate 
    FROM gaming_client_stats
    JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
    WHERE gaming_client_stats.client_stat_id=clientStatID
    LIMIT 1;
  
    INSERT INTO gaming_game_rounds
    (bet_total, bet_total_base, bet_real, bet_bonus, bet_bonus_win_locked, bet_bonus_lost, jackpot_contribution, num_bets, num_transactions, date_time_start, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, round_ref, exchange_rate) 
    SELECT 0, 0, 0, 0, 0, 0, 0, 0, 0, NOW(), gaming_game_sessions.game_id, gaming_game_sessions.game_manufacturer_id, gaming_game_sessions.operator_game_id, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, 0, gaming_game_round_types.game_round_type_id, gaming_client_stats.currency_id, roundRef, roundExchangeRate 
    FROM gaming_game_round_types
    JOIN gaming_game_sessions ON gaming_game_round_types.name='Normal' AND gaming_game_sessions.game_session_id=gameSessionID
    JOIN gaming_client_stats ON gaming_game_sessions.client_stat_id=gaming_client_stats.client_stat_id; 
    
    SET gameRoundID=LAST_INSERT_ID();
  END IF;
 
  SET closeRound = IF(cwCloseRoundOnWin, 1, closeRound); 
  SET @returnData=1;
  
  IF (transactionType='PJWin') THEN
	
    CALL PlaceJackpotWin(gameRoundID, sessionID, gameSessionID, winAmount, transactionRef, @returnData, gamePlayIDReturned, statusCode);
  
  ELSE
    
    SET @wagerType='Type1';
	SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
    
    IF (@wagerType='Type2') THEN
      CALL PlaceWinTypeTwo(gameRoundID, sessionID, gameSessionID, winAmount, clearBonusLost, transactionRef, closeRound, 
		isJackpotWin, @returnData, minimalData, gamePlayIDReturned, statusCode);   
    ELSE
	  CALL PlaceWin(gameRoundID, sessionID, gameSessionID, winAmount, clearBonusLost, transactionRef, closeRound, 
		isJackpotWin, @returnData, minimalData, gamePlayIDReturned, statusCode);   
	END IF;
    
  END IF;
  
  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code, manual_update, currency_code, exchange_rate)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, originalAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), NULL, IF(statusCode=0,1,0), statusCode, manualUpdate, currencyCode, exchangeRate
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name=transactionType;
   
    SET cwTransactionID=LAST_INSERT_ID();
  END IF;
 
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
END root$$

DELIMITER ;

