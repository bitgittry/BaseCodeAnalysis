DROP procedure IF EXISTS `CommonWalletMGSRefundBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletMGSRefundBet`(
  gameSessionID BIGINT, clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80), betTransactionRef VARCHAR(80), roundRef BIGINT, 
  gameRef VARCHAR(80), refundAmount DECIMAL(18, 5), canCommit TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  DECLARE clientStatIDCheck, sessionID, gameManufacturerID, gameRoundID, gamePlayID, operatorGameID, betCwTransactionID BIGINT DEFAULT -1;
  DECLARE betTotal DECIMAL(18, 5) DEFAULT 0;
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE isAlreadyProcessed, betIsSuccess TINYINT(1) DEFAULT 0;
  DECLARE transactionType VARCHAR(20) DEFAULT 'BetCancelled';
  SET gameManufacturerID=3;
  
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=10; LEAVE root; END IF;
    
  
  
  CALL CommonWalletGeneralCheckTransactionProcessed(betTransactionRef, gameManufacturerName, transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  
  SELECT session_id, game_manufacturer_id, operator_game_id INTO sessionID, gameManufacturerID, operatorGameID 
  FROM gaming_game_sessions WHERE game_session_id=gameSessionID;
    
  SET gamePlayID=NULL;
  SELECT gaming_game_plays.game_play_id, gaming_cw_transactions.cw_transaction_id, gaming_cw_transactions.is_success 
  INTO gamePlayID, betCwTransactionID, betIsSuccess
  FROM gaming_cw_transactions   
  JOIN gaming_payment_transaction_type AS transaction_type ON 
    (transaction_ref=betTransactionRef AND game_manufacturer_id=gameManufacturerID AND client_stat_id=clientStatID) AND
    (transaction_type.name='Bet' AND gaming_cw_transactions.payment_transaction_type_id=transaction_type.payment_transaction_type_id) 
  LEFT JOIN gaming_game_plays ON gaming_cw_transactions.game_play_id=gaming_game_plays.game_play_id
  ORDER BY gaming_cw_transactions.`timestamp` DESC, gaming_cw_transactions.cw_transaction_id DESC
  LIMIT 1;
  
  
  IF (gamePlayID IS NULL) THEN
    IF (betCwTransactionID!=-1 AND betIsSuccess=1) THEN
      SET statusCode=50; 
      
      SELECT IF (IFNULL(gaming_operator_games.disable_bonus_money,1)=1, current_real_balance, ROUND(current_real_balance+current_bonus_balance+current_bonus_win_locked_balance,0)) AS current_balance, gaming_currency.currency_code  
      FROM gaming_client_stats  
      JOIN gaming_currency ON gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.currency_id=gaming_currency.currency_id 
      LEFT JOIN gaming_operator_games ON gaming_operator_games.operator_game_id=operatorGameID; 
    ELSE
      SET statusCode=1;      
    END IF;
    
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, refundAmount, transactionRef, roundRef, SUBSTRING(gameRef,1,40), clientStatID, NULL, NOW(), NULL, IF(statusCode=50,1,0), statusCode 
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name='BetCancelled';
    
    SET cwTransactionID=LAST_INSERT_ID(); SET isAlreadyProcessed=0;
    SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
    
    LEAVE root;
  END IF;
  
  CALL PlaceBetCancel(gamePlayID, sessionID, gameSessionID, refundAmount, transactionRef, minimalData, gamePlayIDReturned, statusCode);
  
  INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code)
  SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, refundAmount, transactionRef, roundRef, SUBSTRING(gameRef,1,40), clientStatID, gamePlayIDReturned, NOW(), NULL, IF(statusCode=0,1,0), statusCode
  FROM gaming_game_manufacturers
  JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name='BetCancelled';
  SET cwTransactionID=LAST_INSERT_ID(); SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  IF (canCommit) THEN COMMIT AND CHAIN; END IF;
END root$$

DELIMITER ;

