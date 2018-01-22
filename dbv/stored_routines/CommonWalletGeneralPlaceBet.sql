DROP procedure IF EXISTS `CommonWalletGeneralPlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletGeneralPlaceBet`(
  gameSessionID BIGINT, clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80), roundRef BIGINT, gameRef VARCHAR(80), 
  betAmount DECIMAL(18, 5), jackpotContribution DECIMAL(18, 5), roundType VARCHAR(20), ignoreSessionExpiry TINYINT(1), canCommit TINYINT(1), 
  manualUpdate TINYINT(1), realMoneyOnly TINYINT(1), platformType VARCHAR(20), realBalance DECIMAL(18,5), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  DECLARE operatorID, operatorGameID, sessionID, gameManufacturerID, clientStatIDCheck, clientID, currencyID BIGINT DEFAULT -1;
  DECLARE gameRoundID, operatorGameIDMinigame,gameID BIGINT DEFAULT NULL;
  DECLARE isSubGame, cwHasSubGames, cwCloseRoundOnWin, ignorePlayLimit, allowUseBonusLost, isAlreadyProcessed TINYINT(1) DEFAULT 0;
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE extendSessionExpiry TINYINT(1) DEFAULT 0;
  DECLARE sessionStatusCode INT DEFAULT 0;
  DECLARE currencyCode, cwExchangeCurrency VARCHAR(3) DEFAULT NULL;
  DECLARE gameSessionKey, playerHandle VARCHAR(80) DEFAULT NULL;
  DECLARE exchangeRate, originalAmount, currentRealBalance DECIMAL(18,5) DEFAULT NULL;
  DECLARE cwAllowConcurrentGames BIT;
    
  SELECT 	client_stat_id, client_id, currency_id, 
			current_real_balance - (current_ring_fenced_amount + current_ring_fenced_sb + current_ring_fenced_casino + current_ring_fenced_poker)
  INTO 		clientStatIDCheck, clientID, currencyID, currentRealBalance 
  FROM 		gaming_client_stats 
  WHERE 	client_stat_id=clientStatID FOR UPDATE; 
  
  IF (realBalance IS NOT NULL AND realBalance != currentRealBalance) THEN
	CALL TransactionAdjustRealMoney(0, clientStatID, realBalance - currentRealBalance, 'Correction', 'Correction', UUID(), 0, 0, NULL, @s);
  END IF;
  
  IF (clientStatIDCheck=-1) THEN SET statusCode=1; LEAVE root; END IF;

  IF (gameSessionID IS NULL) THEN

  	IF (gameManufacturerName='ThirdPartyClient') THEN
  		SELECT ggm.name 
  		INTO gameManufacturerName
  		FROM gaming_games AS gg
  		JOIN gaming_game_manufacturers AS ggm ON gg.game_manufacturer_id=ggm.game_manufacturer_id
  		WHERE gg.manufacturer_game_idf=gameRef
  		LIMIT 1;
    END IF;

    CALL CommonWalletGeneralGetGameSession(clientStatID, gameManufacturerName, gameRef, gameSessionID);
	
  END IF;
  
  IF (gameSessionID IS NOT NULL) THEN
    SET ignoreSessionExpiry=ignoreSessionExpiry OR manualUpdate; SET extendSessionExpiry=1; 
    CALL CommonWalletCheckGameSessionByID(gameSessionID, ignoreSessionExpiry, extendSessionExpiry, canCommit, sessionStatusCode);
	
    IF (sessionStatusCode!=0) THEN SET statusCode=7; LEAVE root; END IF;  
  END IF;
  
  SELECT client_stat_id, client_id, currency_id INTO clientStatIDCheck, clientID, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=1; LEAVE root; END IF;
  
  SET @transactionType='Bet'; 
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, @transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;

  IF (gameSessionID IS NULL) THEN 
	CALL GameSessionStartFromProc(clientStatID, gameManufacturerName, gameRef, gameSessionID);
  END IF;

  SELECT  gaming_game_sessions.session_id, gaming_game_sessions.client_stat_id, gaming_game_sessions.game_manufacturer_id, cw_exchange_currency, gaming_game_sessions.operator_game_id, gaming_game_sessions.game_id 
  INTO  sessionID, clientStatID, gameManufacturerID, cwExchangeCurrency, operatorGameID, gameID
  FROM gaming_game_sessions 
  JOIN gaming_game_manufacturers ON gaming_game_sessions.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  WHERE gaming_game_sessions.game_session_id=gameSessionID;

  IF (gameSessionID IS NULL) THEN SET statusCode=11; LEAVE root; END IF;
 
  IF (gameManufacturerID!=-1 AND cwExchangeCurrency IS NOT NULL) THEN
    SELECT pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate INTO exchangeRate
    FROM gaming_operators
    JOIN gaming_currency ON gaming_currency.currency_code=cwExchangeCurrency
    JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gaming_currency.currency_id=gm_exchange_rate.currency_id 
    JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=currencyID 
    WHERE gaming_operators.is_main_operator=1;
  
    SET originalAmount=betAmount;
    SET betAmount=CEILING(betAmount*exchangeRate);
    SET currencyCode=cwExchangeCurrency;
  ELSE
    SET originalAmount=betAmount;
  END IF;
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID AND is_round_finished=0  
  ORDER BY game_round_id DESC LIMIT 1;
 
  
  SET ignorePlayLimit=manualUpdate; 
  SET allowUseBonusLost=0; 
  SET @gamePlayKey=NULL;
  SET @roundType='Normal';

  SET @wagerType='Type1';
  SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
  
 
  
  IF (@wagerType='Type2') THEN
    CALL PlaceBetTypeTwo(operatorGameID, NULL, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, NULL, 
		gameRoundID, ignorePlayLimit, ignoreSessionExpiry, @allowUseBonusLost, @roundType, transactionRef, roundRef, realMoneyOnly, 
        platformType, minimalData, gamePlayIDReturned, statusCode);
  ELSE
	CALL PlaceBet(operatorGameID, NULL, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, NULL, 
		gameRoundID, ignorePlayLimit, ignoreSessionExpiry, allowUseBonusLost, @roundType, transactionRef, roundRef, realMoneyOnly, 
        platformType, minimalData, gamePlayIDReturned, statusCode);
  END IF;

  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code, manual_update, currency_code, exchange_rate)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, originalAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), NULL, statusCode=0, statusCode, manualUpdate, currencyCode, exchangeRate 
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name='Bet';
  
    SET cwTransactionID=LAST_INSERT_ID(); 
  END IF;
  
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
END root$$

DELIMITER ;

