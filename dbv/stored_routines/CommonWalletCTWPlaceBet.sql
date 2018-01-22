DROP procedure IF EXISTS `CommonWalletCTWPlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCTWPlaceBet`(
  playerHandle VARCHAR(80), clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80), 
  roundRef BIGINT, gameRef VARCHAR(80), betAmount DECIMAL(18, 5), jackpotContribution DECIMAL(18, 5), isMultiTransaction TINYINT(1), 
  canCommit TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN
 
  DECLARE clientStatIDCheck, gameSessionID, operatorGameID, sessionID, gameManufacturerID BIGINT DEFAULT -1;
  DECLARE gameRoundID, operatorGameIDMinigame,gameID BIGINT DEFAULT NULL;
  DECLARE isSubGame, ignorePlayLimit, allowUseBonusLost, isAlreadyProcessed, ignoreSessionExpiry TINYINT(1) DEFAULT 0;
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE sessionStatusCode INT DEFAULT 0;
  
  SET @wagerType='Type1';
  SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
  
  SET canCommit=IF(isMultiTransaction, 0, canCommit);
  
  CALL CommonWalletCTWGetGameSession(playerHandle, clientStatID, gameManufacturerName, gameRef, 1, gameSessionID);
  
  IF (gameSessionID IS NOT NULL) THEN
    CALL CommonWalletCheckGameSessionByID(gameSessionID, ignoreSessionExpiry, 1, NOT isMultiTransaction, sessionStatusCode); 
  END IF;
  
  
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=10; LEAVE root; END IF;
  
  
  SET @transactionType=NULL; 
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, @transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  IF (gameSessionID IS NULL) THEN SET statusCode=11; LEAVE root; END IF;
  IF (gameSessionID IS NULL OR (sessionStatusCode!=0 AND isMultiTransaction=0)) THEN 
    SET statusCode=7;
    LEAVE root;
  END IF; 
  
  SELECT operator_game_id, session_id, game_manufacturer_id , game_id
  INTO operatorGameID, sessionID, gameManufacturerID , gameID
  FROM gaming_game_sessions
  WHERE game_session_id=gameSessionID;
  
  SET @cwHasSubGames=1;
  IF (@cwHasSubGames) THEN 
    SELECT gaming_operator_games.operator_game_id, gaming_games.is_sub_game INTO operatorGameIDMinigame, isSubGame
    FROM gaming_games
    JOIN gaming_game_manufacturers ON gaming_games.manufacturer_game_idf=gameRef AND 
		gaming_game_manufacturers.game_manufacturer_id=gameManufacturerID AND gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
    JOIN gaming_operators ON gaming_operators.is_main_operator=1 
    JOIN gaming_operator_games ON gaming_games.game_id=gaming_operator_games.game_id AND gaming_operator_games.operator_id=gaming_operators.operator_id;
    
    SET operatorGameIDMinigame = IF(isSubGame=0, NULL, operatorGameIDMinigame);
  END IF;
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
  WHERE gaming_game_rounds.round_ref=roundRef AND gaming_game_rounds.client_stat_id=clientStatID AND game_id=gameID
  ORDER BY game_round_id DESC LIMIT 1;
  
  SET ignorePlayLimit=isMultiTransaction; 
  SET ignoreSessionExpiry=isMultiTransaction;
  SET allowUseBonusLost=isMultiTransaction; 
  SET @roundType='Normal';
  
  IF (@wagerType='Type2') THEN
    CALL PlaceBetTypeTwo(operatorGameID, operatorGameIDMinigame, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, NULL, 
		gameRoundID, ignorePlayLimit, ignoreSessionExpiry, allowUseBonusLost, @roundType, transactionRef, roundRef, 0, null, 
        minimalData, gamePlayIDReturned, statusCode);
  ELSE
    CALL PlaceBet(operatorGameID, operatorGameIDMinigame, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, NULL, 
		gameRoundID, ignorePlayLimit, ignoreSessionExpiry, allowUseBonusLost, @roundType, transactionRef, roundRef, 0, null, 
        minimalData, gamePlayIDReturned, statusCode);
  END IF;
  
  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, betAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), NULL, 1, statusCode 
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name='Bet';
    SET cwTransactionID=LAST_INSERT_ID(); 
  END IF;
  
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
  IF (canCommit) THEN COMMIT AND CHAIN; END IF;
END root$$

DELIMITER ;

