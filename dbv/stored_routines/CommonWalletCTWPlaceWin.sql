DROP procedure IF EXISTS `CommonWalletCTWPlaceWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCTWPlaceWin`(
  playerHandle VARCHAR(80), clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80), roundRef BIGINT, 
  gameRef VARCHAR(80), winAmount DECIMAL(18, 5), isJackpotWin TINYINT(1), isMultiTransaction TINYINT(1), 
  canCommit TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN
 

  DECLARE clientStatIDCheck, gameSessionID, sessionID, gameManufacturerID, gameRoundID BIGINT DEFAULT -1;
  DECLARE clearBonusLost, isAlreadyProcessed, jackpotWinMoneyFlowAsNormalWin TINYINT(1) DEFAULT 0; 
  DECLARE gamePlayIDReturned, cwTransactionID,gameID BIGINT DEFAULT NULL;
  DECLARE transactionType VARCHAR(40) DEFAULT NULL;
  DECLARE sessionStatusCode INT DEFAULT 0;
  
  SET canCommit=IF(isMultiTransaction, 0, canCommit);
  
  
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=10; LEAVE root; END IF;
  
  SET @transactionType=NULL; 
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, @transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  CALL CommonWalletCTWGetGameSession(playerHandle, clientStatID, gameManufacturerName, gameRef, 0, gameSessionID);
  IF (gameSessionID IS NULL) THEN SET statusCode=11; LEAVE root; END IF;
  
  SELECT session_id, game_manufacturer_id,game_id INTO sessionID, gameManufacturerID, gameID
  FROM gaming_game_sessions WHERE game_session_id=gameSessionID;
  
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds  FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID 
  ORDER BY date_time_start DESC, game_round_id DESC LIMIT 1;
  
  
  IF (gameRoundID=-1) THEN
    INSERT INTO gaming_game_rounds
    (bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked, bet_bonus_lost, jackpot_contribution, num_bets, num_transactions, date_time_start, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, round_ref) 
    SELECT 0, 0, gaming_operator_currency.exchange_rate, 0, 0, 0, 0, 0, 0, 0, NOW(), gaming_game_sessions.game_id, gaming_game_sessions.game_manufacturer_id, gaming_game_sessions.operator_game_id, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, 0, gaming_game_round_types.game_round_type_id, gaming_client_stats.currency_id, roundRef 
    FROM gaming_game_round_types
    JOIN gaming_game_sessions ON gaming_game_round_types.name='Normal' AND gaming_game_sessions.game_session_id=gameSessionID
    JOIN gaming_client_stats ON gaming_game_sessions.client_stat_id=gaming_client_stats.client_stat_id
    JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
    JOIN gaming_operators ON gaming_operators.is_main_operator AND gaming_operator_currency.operator_id=gaming_operators.operator_id; 
    
    SET gameRoundID=LAST_INSERT_ID();
  END IF;
    
	SET transactionType='Win';
    SET clearBonusLost = NOT isMultiTransaction;
    SET @closeRound=1; 
    SET @returnData=1;

  SELECT value_bool INTO jackpotWinMoneyFlowAsNormalWin FROM gaming_settings WHERE name='JACKPOT_WIN_MONEY_FLOW_AS_NORMAL_WIN';
    
  IF(isJackpotWin=1 AND jackpotWinMoneyFlowAsNormalWin=0) THEN
    SET transactionType='PJWin';
    CALL PlaceJackpotWin(gameRoundID, sessionID, gameSessionID, winAmount, transactionRef, @returnData, gamePlayIDReturned, statusCode);
  ELSE
    
	SET @wagerType='Type1';
	SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
    IF (@wagerType='Type2') THEN
      CALL PlaceWinTypeTwo(gameRoundID, sessionID, gameSessionID, winAmount, clearBonusLost, transactionRef, @closeRound, isJackpotWin, 
		@returnData, minimalData, gamePlayIDReturned, statusCode);   
    ELSE
      CALL PlaceWin(gameRoundID, sessionID, gameSessionID, winAmount, clearBonusLost, transactionRef, @closeRound, isJackpotWin, 
		@returnData, minimalData, gamePlayIDReturned, statusCode); 
    END IF;

  END IF;
  
  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, winAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), NULL, IF(statusCode=0,1,0), statusCode
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name=transactionType;
  
    SET cwTransactionID=LAST_INSERT_ID();
  END IF;
 
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
 
  IF (canCommit) THEN COMMIT AND CHAIN; END IF;
END root$$

DELIMITER ;

