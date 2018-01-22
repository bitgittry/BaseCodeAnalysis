DROP procedure IF EXISTS `CommonWalletCommonRollback`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCommonRollback`(
  gameSessionKey VARCHAR(40), clientStatID BIGINT, gameManufacturerName VARCHAR(80), cancelTransactionRef VARCHAR(80), transactionRef VARCHAR(80), 
  roundRef BIGINT, gameRef VARCHAR(80), refundAmount DECIMAL(18, 5), canCommit TINYINT(1), 
  minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  DECLARE sessionID, gameManufacturerID, gameRoundID, gamePlayID, operatorGameID, betCwTransactionID, clientStatIDCheck BIGINT DEFAULT -1;
  DECLARE betTotal DECIMAL(18, 5) DEFAULT 0;
  DECLARE gamePlayIDReturned, cwTransactionID, gameID, gameSessionID BIGINT DEFAULT NULL;
  DECLARE isAlreadyProcessed, betIsSuccess, isMultiTransaction TINYINT(1) DEFAULT 0;
  DECLARE ignoreSessionExpiry, extendSessionExpiry TINYINT(1) DEFAULT 0;
  DECLARE sessionStatusCode INT DEFAULT 0;
  DECLARE currencyCode, cwExchangeCurrency VARCHAR(3) DEFAULT NULL;
  DECLARE exchangeRate, originalAmount DECIMAL(18,5) DEFAULT NULL;
  DECLARE transactionType VARCHAR(20);
  
  
  IF (gameSessionKey IS NOT NULL) THEN
    SELECT game_session_id, client_stat_id INTO gameSessionID, clientStatID FROM gaming_game_sessions WHERE game_session_key=gameSessionKey AND (clientStatID=0 OR client_stat_id=clientStatID);
  END IF;
  
  
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=1; LEAVE root; END IF;
  
  
  SET @transactionType='BetCancelled';
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, @transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  
  IF (gameSessionID IS NULL) THEN
    CALL CommonWalletGeneralGetGameSession(clientStatID, gameManufacturerName, gameRef, gameSessionID);
    IF (gameSessionID IS NULL) THEN SET statusCode=11; LEAVE root; END IF;
  END IF;
  
  SELECT gaming_game_sessions.session_id, gaming_game_sessions.game_manufacturer_id, client_stat_id, operator_game_id, cw_exchange_currency, game_id
  INTO sessionID, gameManufacturerID, clientStatID, operatorGameID, cwExchangeCurrency, gameID
  FROM gaming_game_sessions 
  JOIN gaming_game_manufacturers ON gaming_game_sessions.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  WHERE gaming_game_sessions.game_session_id=gameSessionID;
  
  SELECT gaming_game_plays.game_round_id, gaming_game_plays.game_play_id, gaming_game_plays.amount_total, IFNULL(refundAmount, gaming_cw_transactions.amount), gaming_cw_transactions.exchange_rate 
  INTO gameRoundID, gamePlayID, betTotal, refundAmount, exchangeRate 
  FROM gaming_cw_transactions
  JOIN gaming_game_plays ON gaming_cw_transactions.game_play_id=gaming_game_plays.game_play_id
  JOIN gaming_payment_transaction_type AS transaction_type ON transaction_type.name='Bet' AND gaming_cw_transactions.payment_transaction_type_id=transaction_type.payment_transaction_type_id 
  WHERE gaming_cw_transactions.transaction_ref=cancelTransactionRef AND gaming_cw_transactions.client_stat_id=clientStatID AND gaming_cw_transactions.game_manufacturer_id=gameManufacturerID 
  ORDER BY gaming_cw_transactions.timestamp DESC
  LIMIT 1;
  
  
  IF (gamePlayID=-1 AND roundRef IS NOT NULL) THEN
	SELECT gaming_game_plays.game_round_id, gaming_game_plays.game_play_id, gaming_game_plays.amount_total, IFNULL(refundAmount, gaming_cw_transactions.amount), gaming_cw_transactions.exchange_rate 
    INTO gameRoundID, gamePlayID, betTotal, refundAmount, exchangeRate
    FROM gaming_game_rounds 
    JOIN gaming_game_plays ON gaming_game_rounds.round_ref=roundRef AND gaming_game_rounds.client_stat_id=clientStatID AND gaming_game_rounds.game_id=gameID AND 
       gaming_game_rounds.game_round_id=gaming_game_plays.game_round_id AND
      gaming_game_plays.payment_transaction_type_id=12 AND gaming_game_plays.is_win_placed=0  
    JOIN gaming_cw_transactions ON gaming_game_plays.game_play_id=gaming_cw_transactions.game_play_id
    ORDER BY gaming_game_plays.timestamp DESC
    LIMIT 1;
  END IF;

  SET originalAmount=refundAmount;
  SET refundAmount=CEILING(refundAmount/IFNULL(exchangeRate, 1.0));
  SET refundAmount=IF(refundAmount<>0.0,refundAmount,betTotal);  
  
  IF (gamePlayID=-1) THEN
    
    SELECT gaming_cw_transactions.cw_transaction_id, gaming_cw_transactions.is_success INTO betCwTransactionID, betIsSuccess
    FROM gaming_cw_transactions WHERE transaction_ref=cancelTransactionRef AND game_manufacturer_id=gameManufacturerID AND client_stat_id=clientStatID;
  
    IF (betCwTransactionID!=-1 AND betIsSuccess=1) THEN
      SET statusCode=50; 
      
      SELECT IF (gaming_operator_games.disable_bonus_money=1, current_real_balance, ROUND(current_real_balance+IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance,0),0)) AS current_balance, current_real_balance, 
        IF(gaming_operator_games.disable_bonus_money=1, 0, ROUND(IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance,0),0)) AS current_bonus_balance, gaming_currency.currency_code, ROUND(pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate,5) AS exchange_rate  
      FROM gaming_client_stats  
      JOIN gaming_currency ON client_stat_id=clientStatID AND gaming_client_stats.currency_id=gaming_currency.currency_id
      LEFT JOIN gaming_operator_games ON gaming_operator_games.operator_game_id=operatorGameID
      LEFT JOIN
      (
        SELECT SUM(gbi.bonus_amount_remaining) AS current_bonus_balance, SUM(gbi.current_win_locked_amount) AS current_bonus_win_locked_balance
        FROM gaming_bonus_instances AS gbi
        JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbi.client_stat_id=clientStatID AND gbi.is_active) AND
          (gbi.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
      ) AS Bonuses ON 1=1
      JOIN gaming_operators ON gaming_operators.is_main_operator=1
      JOIN gaming_game_manufacturers ON gaming_game_manufacturers.game_manufacturer_id=gameManufacturerID
      LEFT JOIN gaming_currency AS gm_currency ON gm_currency.currency_code=gaming_game_manufacturers.cw_exchange_currency
      LEFT JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gm_currency.currency_id=gm_exchange_rate.currency_id 
      LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=gaming_currency.currency_id; 
    ELSE
      SET statusCode=1;      
    END IF;
    
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, originalAmount, transactionRef, roundRef, gameRef, clientStatID, NULL, NOW(), NULL, IF(statusCode=50,1,0), statusCode 
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name='BetCancelled';
    
    SET cwTransactionID=LAST_INSERT_ID(); SET isAlreadyProcessed=0;
    SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
    
    LEAVE root;
  END IF;

  SET @wagerType='Type1';
  SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
  IF (@wagerType='Type2') THEN
    CALL PlaceBetCancelTypeTwo(gamePlayID, sessionID, gameSessionID, refundAmount, transactionRef, 
		minimalData, gamePlayIDReturned, statusCode);
  ELSE
    CALL PlaceBetCancel(gamePlayID, sessionID, gameSessionID, refundAmount, transactionRef, 
		minimalData, gamePlayIDReturned, statusCode);
  END IF;  

  INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code, manual_update, currency_code, exchange_rate)
  SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, originalAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), NULL, IF(statusCode=0,1,0), statusCode, 0, currencyCode, exchangeRate
  FROM gaming_game_manufacturers
  JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name='BetCancelled';
  
  SET cwTransactionID=LAST_INSERT_ID(); SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
END root$$

DELIMITER ;

