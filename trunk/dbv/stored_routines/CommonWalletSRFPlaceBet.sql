DROP procedure IF EXISTS `CommonWalletSRFPlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSRFPlaceBet`(
  gameSessionKey VARCHAR(40), clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80), roundRef BIGINT, gameRef VARCHAR(80), betAmount DECIMAL(18, 5), jackpotContribution DECIMAL(18, 5), ignoreSessionExpiry TINYINT(1), canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN
 
  DECLARE operatorGameID, sessionID, gameManufacturerID, clientStatIDCheck, currencyID, gameID BIGINT DEFAULT -1;
  DECLARE gameSessionID, gameRoundID, operatorGameIDMinigame BIGINT DEFAULT NULL;
  DECLARE ignorePlayLimit, isAlreadyProcessed TINYINT(1) DEFAULT 0;
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE extendSessionExpiry TINYINT(1) DEFAULT 0;
  DECLARE sessionStatusCode INT DEFAULT 0;
  DECLARE currencyCode, cwExchangeCurrency VARCHAR(3) DEFAULT NULL;
  DECLARE exchangeRate, originalAmount DECIMAL(18,5) DEFAULT NULL;
  
  IF (gameSessionKey IS NOT NULL) THEN
    SELECT game_session_id INTO gameSessionID FROM gaming_game_sessions WHERE game_session_key=gameSessionKey AND client_stat_id=clientStatID;
  END IF;
   
  
  IF (gameSessionID IS NULL) THEN
    CALL CommonWalletGeneralGetGameSession(clientStatID, gameManufacturerName, gameRef, gameSessionID);
  END IF;
  
  IF (gameSessionID IS NOT NULL) THEN
    
    SET ignoreSessionExpiry=ignoreSessionExpiry; SET extendSessionExpiry=1; 
    CALL CommonWalletCheckGameSessionByID(gameSessionID, ignoreSessionExpiry, extendSessionExpiry, canCommit, sessionStatusCode);
  END IF;
  
  
  SELECT client_stat_id, currency_id INTO clientStatIDCheck, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=1; LEAVE root; END IF;
  
  
  SET @transactionType='Bet'; 
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, @transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  IF (gameSessionID IS NULL) THEN SET statusCode=11; LEAVE root; END IF;
  IF (sessionStatusCode!=0) THEN SET statusCode=7; LEAVE root; END IF; 
   
  
  SELECT operator_game_id, gaming_game_sessions.session_id, gaming_game_sessions.client_stat_id, gaming_game_sessions.game_manufacturer_id, cw_exchange_currency, game_id
  INTO operatorGameID, sessionID, clientStatID, gameManufacturerID, cwExchangeCurrency, gameID
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
  
    SET originalAmount=betAmount;
    SET betAmount=CEILING(betAmount/exchangeRate);
    SET currencyCode=cwExchangeCurrency;
  ELSE
    SET originalAmount=betAmount;
  END IF;
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID AND is_round_finished=0  
  ORDER BY date_time_start DESC, game_round_id DESC LIMIT 1;
  
  SET ignorePlayLimit=0; 
  SET @allowUseBonusLost=0; 
  SET @gamePlayKey=NULL;
  SET @roundType='Normal';

  SET @wagerType='Type1';
  SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
  IF (@wagerType='Type2') THEN
    CALL PlaceBetTypeTwo(operatorGameID, NULL, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, NULL, gameRoundID, ignorePlayLimit, ignoreSessionExpiry, @allowUseBonusLost, @roundType, transactionRef, roundRef, 0, null, gamePlayIDReturned, statusCode);
  ELSE
	CALL PlaceBet(operatorGameID, NULL, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, NULL, gameRoundID, ignorePlayLimit, ignoreSessionExpiry, @allowUseBonusLost, @roundType, transactionRef, roundRef, null, gamePlayIDReturned, 0, statusCode);
  END IF;

  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code, manual_update, currency_code, exchange_rate)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, originalAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), NULL, 1, statusCode, 0, currencyCode, exchangeRate 
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name='Bet';
  
    SET cwTransactionID=LAST_INSERT_ID(); 
  END IF;
  
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
END root$$

DELIMITER ;

