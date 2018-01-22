DROP procedure IF EXISTS `CommonWalletBSFPlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletBSFPlaceBet`(
  clientStatID BIGINT, transactionRef VARCHAR(80), roundRef BIGINT, gameRef VARCHAR(80), betAmount DECIMAL(18, 5), jackpotContribution DECIMAL(18, 5), 
  ignoreSessionExpiry TINYINT(1), extGameSessionID VARCHAR(40), canCommit TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN

  -- Parameter: minimalData
  -- Game Session refactoring with proc
 
  DECLARE operatorGameID, sessionID, clientStatIDCheck, clientID, currencyID, gameID BIGINT DEFAULT -1;
  DECLARE gameSessionID, gameRoundID, parentGameID BIGINT DEFAULT NULL;
  DECLARE ignorePlayLimit, isAlreadyProcessed TINYINT(1) DEFAULT 0;
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE extendSessionExpiry, gameSessionOpen, cwAllowZeroBet, cwNoRound, cwExchangeCurrency TINYINT(1) DEFAULT 0;
  DECLARE sessionStatusCode INT DEFAULT 0;
  DECLARE gameManufacturerID BIGINT DEFAULT 13;
  DECLARE gameManufacturerName VARCHAR(80) DEFAULT 'BetSoft';
  
  SET @wagerType='Type1';
  SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
  
  CALL CommonWalletGeneralGetGameSession(clientStatID, gameManufacturerName, gameRef, gameSessionID);
  
  IF (gameSessionID IS NULL) THEN
	CALL GameSessionStartFromProc(clientStatID, gameManufacturerName, gameRef, gameSessionID);
  END IF;
  
  IF (gameSessionID IS NOT NULL) THEN
    SET ignoreSessionExpiry=ignoreSessionExpiry; SET extendSessionExpiry=1; 
    CALL CommonWalletCheckGameSessionByID(gameSessionID, ignoreSessionExpiry, extendSessionExpiry, canCommit, sessionStatusCode);
  END IF;
  
  SELECT client_stat_id, client_id, currency_id INTO clientStatIDCheck, clientID, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=1; LEAVE root; END IF;
	
  SET @transactionType='Bet'; 
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, @transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  IF (gameSessionID IS NULL) THEN SET statusCode=11; LEAVE root; END IF;
  IF (sessionStatusCode!=0) THEN SET statusCode=7; LEAVE root; END IF; 
  
  SELECT operator_game_id, game_id, gaming_game_sessions.session_id, gaming_game_sessions.client_stat_id, gaming_game_sessions.game_manufacturer_id, cw_exchange_currency, cw_allow_zero_bet, cw_no_round 
  INTO operatorGameID, gameID, sessionID, clientStatID, gameManufacturerID, cwExchangeCurrency, cwAllowZeroBet, cwNoRound 
  FROM gaming_game_sessions 
  JOIN gaming_game_manufacturers ON gaming_game_sessions.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  WHERE gaming_game_sessions.game_session_id=gameSessionID;
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID AND is_round_finished=0  
  ORDER BY game_round_id DESC LIMIT 1;
  
  SET ignorePlayLimit=0; 
  SET @allowUseBonusLost=0; 
  SET @roundType='Normal';
  
  IF (@wagerType='Type2') THEN
    CALL PlaceBetTypeTwo(operatorGameID, NULL, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, NULL, 
		gameRoundID, ignorePlayLimit, ignoreSessionExpiry, @allowUseBonusLost, @roundType, transactionRef, roundRef, 0, NULL, 
        minimalData, gamePlayIDReturned, statusCode);
  ELSE
    CALL PlaceBet(operatorGameID, NULL, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, NULL, 
		gameRoundID, ignorePlayLimit, ignoreSessionExpiry, @allowUseBonusLost, @roundType, transactionRef, roundRef, 0, NULL, 
        minimalData, gamePlayIDReturned, statusCode);
  END IF;
  
  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code, manual_update)
    SELECT gameManufacturerID, 12, betAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), extGameSessionID, 1, statusCode, 0; 
  
    SET cwTransactionID=LAST_INSERT_ID(); 
  END IF;
  
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
  
END root$$

DELIMITER ;

