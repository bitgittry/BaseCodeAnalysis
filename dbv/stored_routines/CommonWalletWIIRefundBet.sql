

DROP procedure IF EXISTS `CommonWalletWIIRefundBet`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletWIIRefundBet`(clientStatID BIGINT, cancelTransactionRef VARCHAR(80), transactionRef VARCHAR(80), canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN

  DECLARE gameSessionID, sessionID, gameRoundID, gamePlayID, operatorGameID, gameID, betCwTransactionID, clientStatIDCheck BIGINT DEFAULT -1;
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE isAlreadyProcessed, betIsSuccess, isMultiTransaction TINYINT(1) DEFAULT 0;
  DECLARE ignoreSessionExpiry, extendSessionExpiry TINYINT(1) DEFAULT 0;
  DECLARE sessionStatusCode INT DEFAULT 0;
  DECLARE transactionType VARCHAR(20);
  DECLARE refundAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE gameManufacturerID BIGINT DEFAULT 25;
  DECLARE gameManufacturerName VARCHAR(80) DEFAULT 'WilliamsInteractive';
  
  SET @wagerType='Type1';
  SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
  
  
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=101; LEAVE root; END IF;
  
  
  SET @transactionType='BetCancelled'; 
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, @transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  
  SELECT gaming_game_plays.game_round_id, gaming_game_plays.game_play_id, gaming_game_plays.amount_total, gaming_game_plays.game_session_id 
  INTO gameRoundID, gamePlayID, refundAmount, gameSessionID 
  FROM gaming_cw_transactions
  JOIN gaming_game_plays ON gaming_cw_transactions.game_play_id=gaming_game_plays.game_play_id
  JOIN gaming_payment_transaction_type AS transaction_type ON transaction_type.name='Bet' AND gaming_cw_transactions.payment_transaction_type_id=transaction_type.payment_transaction_type_id 
  WHERE gaming_cw_transactions.transaction_ref=cancelTransactionRef AND gaming_cw_transactions.client_stat_id=clientStatID AND gaming_cw_transactions.game_manufacturer_id=gameManufacturerID 
  ORDER BY gaming_cw_transactions.timestamp DESC
  LIMIT 1;
    
  
  IF (gamePlayID=-1) THEN
    SET statusCode=1; 
    LEAVE root;
  END IF;
  
  SELECT gaming_game_sessions.game_session_id, gaming_game_sessions.session_id, gaming_game_sessions.game_id, gaming_game_sessions.operator_game_id 
  INTO gameSessionID, sessionID, gameID, operatorGameID
  FROM gaming_game_sessions
  WHERE game_session_id=gameSessionID;
  
  IF (@wagerType='Type2') THEN
    CALL PlaceBetCancelTypeTwo(gamePlayID, sessionID, gameSessionID, refundAmount, transactionRef, gamePlayIDReturned, statusCode);
  ELSE
    CALL PlaceBetCancel(gamePlayID, sessionID, gameSessionID, refundAmount, transactionRef, gamePlayIDReturned, statusCode);
  END IF;
  
  INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code, manual_update)
  SELECT gameManufacturerID, 20, refundAmount, transactionRef, NULL, NULL, clientStatID, gamePlayIDReturned, NOW(), NULL, IF(statusCode=0,1,0), statusCode, 0;
  
  SET cwTransactionID=LAST_INSERT_ID(); SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
END root$$

DELIMITER ;

