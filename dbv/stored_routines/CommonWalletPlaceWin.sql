DROP procedure IF EXISTS `CommonWalletPlaceWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletPlaceWin`(
  gameSessionID BIGINT, clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80), roundRef VARCHAR(80), 
  gameRef VARCHAR(80), cwRequestType VARCHAR(80), winAmount DECIMAL(18, 5), isJackpotWin TINYINT(1), isMultiTransaction TINYINT(1), 
  closeRound TINYINT(1), usePrevious TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN
 
  DECLARE sessionID, clientStatID, gameManufacturerID, gameRoundID, gameID BIGINT DEFAULT -1;
  DECLARE clearBonusLost, cwCloseRoundOnWin, isAlreadyProcessed TINYINT(1) DEFAULT 0; 
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE transactionType VARCHAR(40) DEFAULT NULL;
  DECLARE ignoreSessionExpiry, extendSessionExpiry TINYINT(1) DEFAULT 0;
  DECLARE sessionStatusCode INT DEFAULT 0;
  
  
  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  
  CALL CommonWalletCheckTransactionProcessed(transactionRef, gameManufacturerName, cwRequestType, usePrevious, cwTransactionID, isAlreadyProcessed);
  IF (isAlreadyProcessed) THEN
    SET statusCode=IF(cwTransactionID IS NULL, 100, 0);
    LEAVE root;
  END IF;
  
  
  SET ignoreSessionExpiry=1; SET extendSessionExpiry=1; 
  CALL CommonWalletCheckGameSessionByID(gameSessionID, ignoreSessionExpiry, extendSessionExpiry, 0, sessionStatusCode);
  
  SELECT session_id, client_stat_id, game_manufacturer_id, game_id INTO sessionID, clientStatID, gameManufacturerID, gameID
  FROM gaming_game_sessions WHERE game_session_id=gameSessionID;
  
  SELECT cw_close_round_onwin INTO cwCloseRoundOnWin
  FROM gaming_game_manufacturers WHERE game_manufacturer_id=gameManufacturerID;
  
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID 
  ORDER BY date_time_start DESC, game_round_id DESC LIMIT 1;
  
  IF (gameRoundID=-1 AND isJackpotWin=0) THEN
    SET statusCode = 1;
    LEAVE root;
  END IF;
  
  IF (isJackpotWin=0) THEN
    SET transactionType='Win';
    SET clearBonusLost = NOT isMultiTransaction;
    SET closeRound = IF(cwCloseRoundOnWin, 1, closeRound); 
      
    SET @returnData=1;
    CALL PlaceWin(gameRoundID, sessionID, gameSessionID, winAmount, clearBonusLost, transactionRef, closeRound, @returnData, minimalData, gamePlayIDReturned, statusCode);   
  ELSE
    SET transactionType='PJWin';
    
    IF (gameRoundID=-1) THEN
      INSERT INTO gaming_game_rounds
      (bet_total, bet_total_base, bet_real, bet_bonus, bet_bonus_win_locked, bet_bonus_lost, jackpot_contribution, num_bets, num_transactions, date_time_start, game_id, game_manufacturer_id, operator_game_id, operator_game_id_minigame, client_id, client_stat_id, game_play_key, is_processed, game_round_type_id, currency_id, round_ref) 
      SELECT 0, 0, 0, 0, 0, 0, 0, 0, 0, NOW(), gaming_game_sessions.game_id, gaming_game_sessions.game_manufacturer_id, gaming_game_sessions.operator_game_id, NULL, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, NULL, 0, gaming_game_round_types.game_round_type_id, gaming_client_stats.currency_id, roundRef 
      FROM gaming_game_round_types
      JOIN gaming_game_sessions ON gaming_game_round_types.name='Normal' AND gaming_game_sessions.game_session_id=gameSessionID
      JOIN gaming_client_stats ON gaming_game_sessions.client_stat_id=gaming_client_stats.client_stat_id; 
      
      SET gameRoundID=LAST_INSERT_ID();
    END IF;
    
    CALL PlaceJackpotWin(gameRoundID, sessionID, gameSessionID, winAmount, transactionRef, gamePlayIDReturned, statusCode);
  END IF;
  
  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, cw_request_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, request_type.cw_request_type_id, winAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), NULL, IF(statusCode=0,1,0), statusCode
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name=transactionType
    LEFT JOIN gaming_cw_request_types AS request_type ON request_type.name=cwRequestType AND request_type.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id;
  
    SET cwTransactionID=LAST_INSERT_ID();
  END IF;
 
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
END root$$

DELIMITER ;

