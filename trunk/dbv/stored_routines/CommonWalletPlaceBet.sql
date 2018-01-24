DROP procedure IF EXISTS `CommonWalletPlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletPlaceBet`(
  gameSessionID BIGINT, clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80), roundRef VARCHAR(80), gameRef VARCHAR(80), cwRequestType VARCHAR(80), betAmount DECIMAL(18, 5), jackpotContribution DECIMAL(18, 5), gamePlayKey VARCHAR(80), isMultiTransaction TINYINT(1), usePrevious TINYINT(1), OUT statusCode INT)
root: BEGIN
  -- Removed 
  DECLARE operatorGameID, sessionID, clientStatID, gameManufacturerID,gameID BIGINT DEFAULT -1;
  DECLARE gameRoundID, operatorGameIDMinigame BIGINT DEFAULT NULL;
  DECLARE isSubGame, cwHasSubGames, cwCloseRoundOnWin, ignorePlayLimit, allowUseBonusLost, isAlreadyProcessed TINYINT(1) DEFAULT 0;
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE ignoreSessionExpiry, extendSessionExpiry TINYINT(1) DEFAULT 0;
  DECLARE sessionStatusCode INT DEFAULT 0;
  
  
  SET ignoreSessionExpiry=0; SET extendSessionExpiry=1; 
  CALL CommonWalletCheckGameSessionByID(gameSessionID, ignoreSessionExpiry, extendSessionExpiry, NOT isMultiTransaction, sessionStatusCode);
  
  
  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  
  CALL CommonWalletCheckTransactionProcessed(transactionRef, gameManufacturerName, cwRequestType, usePrevious, cwTransactionID, isAlreadyProcessed);
  IF (isAlreadyProcessed) THEN
    SET statusCode=IF(cwTransactionID IS NULL, 100, 0); 
    LEAVE root;
  END IF;
  
  IF (sessionStatusCode!=0) THEN SET statusCode=7; LEAVE root; END IF; 
   
  
  SELECT operator_game_id, session_id, client_stat_id, game_manufacturer_id, game_id
  INTO operatorGameID, sessionID, clientStatID, gameManufacturerID,  gameID
  FROM gaming_game_sessions
  WHERE game_session_id=gameSessionID;
  
  SELECT cw_has_subgames INTO cwHasSubGames
  FROM gaming_game_manufacturers WHERE game_manufacturer_id=gameManufacturerID;
  
  
  IF (cwHasSubGames) THEN 
    SELECT gaming_operator_games.operator_game_id, gaming_games.is_sub_game INTO operatorGameIDMinigame, isSubGame
    FROM gaming_games
    JOIN gaming_game_manufacturers ON gaming_game_manufacturers.game_manufacturer_id=gameManufacturerID AND gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
    JOIN gaming_operators ON gaming_operators.is_main_operator=1 
    JOIN gaming_operator_games ON gaming_games.game_id=gaming_operator_games.game_id AND gaming_operator_games.operator_id=gaming_operators.operator_id
    WHERE gaming_games.manufacturer_game_idf=gameRef;
    
    SET operatorGameIDMinigame = IF(isSubGame=0, NULL, operatorGameIDMinigame);
  END IF;
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID AND is_round_finished=0  
  ORDER BY date_time_start DESC, game_round_id DESC LIMIT 1;
  
  SET ignorePlayLimit=isMultiTransaction; 
  SET allowUseBonusLost=isMultiTransaction; 
  CALL PlaceBet(operatorGameID, operatorGameIDMinigame, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, gamePlayKey, gameRoundID, ignorePlayLimit, allowUseBonusLost, transactionRef, roundRef, gamePlayIDReturned, statusCode);
  
  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, cw_request_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, request_type.cw_request_type_id, betAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), NULL, 1, statusCode 
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name='Bet'
    LEFT JOIN gaming_cw_request_types AS request_type ON request_type.name=cwRequestType AND request_type.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id;
  
    SET cwTransactionID=LAST_INSERT_ID(); 
  END IF;
  
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
END root$$

DELIMITER ;

