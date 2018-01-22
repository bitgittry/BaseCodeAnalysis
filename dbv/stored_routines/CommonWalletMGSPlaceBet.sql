DROP procedure IF EXISTS `CommonWalletMGSPlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletMGSPlaceBet`(
  gameSessionID BIGINT, clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80), roundRef BIGINT, gameRef VARCHAR(80), 
  betAmount DECIMAL(18, 5), jackpotContribution DECIMAL(18, 5), ignoreSessionExpiry TINYINT(1), canCommit TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN
 
  DECLARE clientStatIDCheck, operatorGameID, sessionID, gameManufacturerID, gameSessionIDNew, gameID BIGINT DEFAULT -1;
  DECLARE gameRoundID, operatorGameIDMinigame BIGINT DEFAULT NULL;
  DECLARE isSubGame, cwHasSubGames, cwCloseRoundOnWin, ignorePlayLimit, allowUseBonusLost, isAlreadyProcessed, gameSessionOpen TINYINT(1) DEFAULT 0;
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE sessionStatusCode INT DEFAULT 0;
  DECLARE transactionType VARCHAR(20) DEFAULT 'Bet';
  DECLARE gameRefMatch VARCHAR(80) DEFAULT NULL;
  
  SELECT gaming_game_sessions.session_id, gaming_game_sessions.game_manufacturer_id, gaming_games.manufacturer_game_idf, gaming_game_sessions.client_stat_id, gaming_game_sessions.operator_game_id, gaming_game_sessions.game_id
  INTO sessionID, gameManufacturerID, gameRefMatch, clientStatID, operatorGameID, gameID  
  FROM gaming_game_sessions JOIN gaming_games ON gaming_game_sessions.game_id=gaming_games.game_id
  WHERE gaming_game_sessions.game_session_id=gameSessionID;
    
  
  CALL CommonWalletCheckGameSessionByID(gameSessionID, ignoreSessionExpiry, 1, canCommit, sessionStatusCode); 
  
  
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=1; LEAVE root; END IF;
  
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  IF (sessionStatusCode!=0) THEN SET statusCode=7; LEAVE root; END IF;
  
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID AND is_round_finished=0  
  ORDER BY date_time_start DESC, game_round_id DESC LIMIT 1;
  
  SET ignorePlayLimit=0; 
  
  SET allowUseBonusLost=0; 
  SET @gamePlayKey=NULL;
  SET @roundType='Normal';
 
  SET @wagerType='Type1';
  SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
  IF (@wagerType='Type2') THEN
    CALL PlaceBetTypeTwo(operatorGameID, NULL, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, 
		NULL, gameRoundID, ignorePlayLimit, ignoreSessionExpiry, @allowUseBonusLost, @roundType, transactionRef, roundRef, 0, 
        NULL, minimalData, gamePlayIDReturned, statusCode);
  ELSE
    CALL PlaceBet(operatorGameID, NULL, sessionID, gameSessionID, clientStatID, betAmount, jackpotContribution, 
		NULL, gameRoundID, ignorePlayLimit, ignoreSessionExpiry, allowUseBonusLost, @roundType, transactionRef, roundRef, 0, 
        NULL, minimalData, gamePlayIDReturned, statusCode);
  END IF;

  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, betAmount, transactionRef, roundRef, SUBSTRING(gameRef,1,40), clientStatID, gamePlayIDReturned, NOW(), NULL, 1, statusCode 
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name='Bet';
  
    SET cwTransactionID=LAST_INSERT_ID(); 
  END IF;
  
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
  IF (canCommit) THEN COMMIT AND CHAIN; END IF;
END root$$

DELIMITER ;

