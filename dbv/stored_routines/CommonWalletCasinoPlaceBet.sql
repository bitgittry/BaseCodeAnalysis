DROP procedure IF EXISTS `CommonWalletCasinoPlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCasinoPlaceBet`(
  externalGameSessionId VARCHAR(80), clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80),
  roundRef VARCHAR(50), gameRef VARCHAR(80), betAmount DECIMAL(18, 5), jackpotContribution DECIMAL(18, 5),
  amountCurrency CHAR(3), roundType VARCHAR(20), ignoreSessionExpiry TINYINT(1), extendSessionExpiry TINYINT(1), canCommit TINYINT(1), isManualUpdate TINYINT(1),
  realMoneyOnly TINYINT(1), platformType VARCHAR(20), transactionComment TEXT, minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN
 
  -- Parameter: minimalData
 
  DECLARE operatorGameID, sessionID, gameManufacturerID, clientStatIDCheck, plCurrencyID, gameID BIGINT DEFAULT -1;
  DECLARE gameRoundID,numericRoundRef, operatorGameIDMinigame BIGINT DEFAULT NULL;
  DECLARE isSubGame, cwHasSubGames, ignorePlayLimit, allowUseBonusLost, isAlreadyProcessed,hasAlphanumericRoundRefs TINYINT(1) DEFAULT 0;
  DECLARE gamePlayIDReturned, cwTransactionID, gameSessionID BIGINT DEFAULT NULL;
  DECLARE sessionStatusCode INT DEFAULT 0;
  DECLARE originalAmount, exchangeRate DECIMAL(18,5) DEFAULT NULL;
  DECLARE plCurrencyCode CHAR(3) DEFAULT NULL;

  IF (externalGameSessionId IS NULL) THEN
    CALL CommonWalletGeneralGetGameSession(clientStatID, gameManufacturerName, gameRef, gameSessionID);
  END IF;
  
  SELECT client_stat_id, currency_id INTO clientStatIDCheck, plCurrencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN 
	SET statusCode=101; 
	LEAVE root;
  END IF;
  
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, 'Bet', cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;

  IF (gameSessionID IS NOT NULL AND extendSessionExpiry = 1) THEN
		SET ignoreSessionExpiry=ignoreSessionExpiry OR isManualUpdate; 
		SET extendSessionExpiry=1; 
		CALL CommonWalletCheckGameSessionByID(gameSessionID, ignoreSessionExpiry, extendSessionExpiry, 0, sessionStatusCode);
	ELSE
		SET statusCode=11;
		LEAVE root;
  END IF;
  
  IF (sessionStatusCode!=0) THEN 
	SET statusCode=7;
	LEAVE root;
  END IF;  
    
  SELECT operator_game_id, game_id, gaming_game_sessions.session_id, gaming_game_sessions.client_stat_id, gaming_game_sessions.game_manufacturer_id, gaming_game_manufacturers.has_alphanumeric_round_refs
  INTO operatorGameID, gameID, sessionID, clientStatID, gameManufacturerID,hasAlphanumericRoundRefs
  FROM gaming_game_sessions 
  JOIN gaming_game_manufacturers ON gaming_game_sessions.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  WHERE gaming_game_sessions.game_session_id=gameSessionID;
  
 IF (amountCurrency IS NOT NULL) THEN
    
	SELECT currency_code INTO plCurrencyCode
	FROM gaming_currency
	WHERE currency_id = plCurrencyID;
	
	SET originalAmount=betAmount;
	CALL CurrencyExchangeAmt(originalAmount, amountCurrency, plCurrencyCode, betAmount, exchangeRate);

	IF(betAmount IS NULL) THEN 
		SET statusCode=660;
		LEAVE root;
	END IF;
	SET betAmount = CEILING(betAmount); 
  ELSE
    
    SET originalAmount=betAmount;
  END IF;
  

  IF (hasAlphanumericRoundRefs) THEN
	  -- Check if RoundRef has already been stored in gaming_cw_rounds
	  SELECT cw_round_id INTO numericRoundRef FROM gaming_cw_rounds WHERE client_stat_id=clientStatID AND game_manufacturer_id=gameManufacturerID AND manuf_round_ref=roundRef;
  
	  SELECT game_round_id INTO gameRoundID
      FROM gaming_game_rounds  FORCE INDEX (client_game_round_ref)
	  WHERE round_ref=numericRoundRef AND client_stat_id=clientStatID AND game_id=gameID AND is_round_finished=0  
      ORDER BY game_round_id DESC LIMIT 1;
  
	  IF (numericRoundRef IS NULL) AND (gameRoundID IS NULL) THEN
		-- round has not yet been stored
		INSERT INTO gaming_cw_rounds (game_manufacturer_id, client_stat_id, game_id, timestamp, cw_latest, manuf_round_ref)
			VALUES (gameManufacturerID, clientStatID, gameID, NOW(), 0, roundRef);
		SET numericRoundRef=LAST_INSERT_ID();
	  END IF;
	ELSE
		SELECT game_round_id INTO gameRoundID
		FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
		WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID AND is_round_finished=0  
		ORDER BY game_round_id DESC LIMIT 1;

	  SET numericRoundRef=CONVERT(roundRef,UNSIGNED INTEGER);
	END IF;
  
  SET ignorePlayLimit=isManualUpdate; 
  SET allowUseBonusLost=0; 

  SET @wagerType='Type1';
  SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
  IF (@wagerType='Type2') THEN
    CALL PlaceBetTypeTwo(operatorGameID, NULL, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, NULL, 
		gameRoundID, ignorePlayLimit, ignoreSessionExpiry, allowUseBonusLost, roundType, transactionRef, numericRoundRef, realMoneyOnly, 
        platformType, minimalData, gamePlayIDReturned, statusCode);
  ELSE
	CALL PlaceBet(operatorGameID, NULL, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, NULL, 
		gameRoundID, ignorePlayLimit, ignoreSessionExpiry, allowUseBonusLost, roundType, transactionRef, numericRoundRef, realMoneyOnly, 
        platformType, minimalData, gamePlayIDReturned, statusCode);
  END IF;


  INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, `timestamp`, other_data, is_success, status_code, manual_update, currency_code, exchange_rate)
  SELECT gameManufacturerID, transaction_type.payment_transaction_type_id, originalAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), transactionComment, statusCode=0, statusCode, isManualUpdate, amountCurrency, exchangeRate 
  FROM gaming_payment_transaction_type AS transaction_type 
  WHERE transaction_type.name='Bet';
  
  SET cwTransactionID=LAST_INSERT_ID(); 
  
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
END root$$

DELIMITER ;

