DROP procedure IF EXISTS `CommonWalletMGSPlaceWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletMGSPlaceWin`(
  gameSessionID BIGINT, clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80), roundRef BIGINT, gameRef VARCHAR(80), 
  winAmount DECIMAL(18,5), isJackpotWin TINYINT(1), canCommit TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN
  -- jackpot flow
  DECLARE clientStatIDCheck, sessionID, gameManufacturerID, gameRoundID, gameID BIGINT DEFAULT -1;
  DECLARE isAlreadyProcessed, jackpotWinMoneyFlowAsNormalWin TINYINT(1) DEFAULT 0; 
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE sessionStatusCode INT DEFAULT 0;
  DECLARE gameRefMatch VARCHAR(80) DEFAULT NULL;
  
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=10; LEAVE root; END IF;
  
  SET @transactionType='Win'; 
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, @transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  SELECT gaming_game_sessions.session_id, gaming_game_sessions.game_manufacturer_id, gaming_games.manufacturer_game_idf, gaming_game_sessions.game_id
  INTO sessionID, gameManufacturerID, gameRefMatch, gameID
  FROM gaming_game_sessions JOIN gaming_games ON gaming_game_sessions.game_id=gaming_games.game_id WHERE gaming_game_sessions.game_session_id=gameSessionID;
  
  
  IF (gameRef!=gameRefMatch) THEN
    SELECT gaming_game_sessions.game_session_id, gaming_game_sessions.session_id, gaming_game_sessions.game_id
    INTO gameSessionID, sessionID, gameID
    FROM gaming_games 
    JOIN gaming_game_sessions ON (manufacturer_game_idf=gameRef AND gaming_games.game_manufacturer_id=gameManufacturerID) AND
      (gaming_game_sessions.client_stat_id=clientStatID AND gaming_game_sessions.game_id=gaming_games.game_id AND gaming_game_sessions.cw_game_latest);  
  END IF;
  
  
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id = gameID 
  ORDER BY date_time_start DESC, game_round_id DESC LIMIT 1;
  
  IF (gameRoundID=-1) THEN
    SELECT game_round_id INTO gameRoundID
    FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
    WHERE round_ref=roundRef AND client_stat_id=clientStatID AND is_round_finished = 0
    ORDER BY date_time_start DESC, game_round_id DESC LIMIT 1;
    
    IF (gameRoundID=-1) THEN
      SET statusCode = 1;
      LEAVE root;
    ELSE
      UPDATE gaming_game_rounds SET game_id = gameID WHERE game_round_id = gameRoundID;
    END IF;
  END IF;
  
  SET @clearBonusLost=1; SET @closeRound=0; SET @returnData=1; 

  SELECT value_bool INTO jackpotWinMoneyFlowAsNormalWin FROM gaming_settings WHERE name='JACKPOT_WIN_MONEY_FLOW_AS_NORMAL_WIN';
    
  IF(isJackpotWin=1 AND jackpotWinMoneyFlowAsNormalWin=0) THEN
	CALL PlaceJackpotWin(gameRoundID, sessionID, gameSessionID, winAmount, transactionRef, @returnData, gamePlayIDReturned, statusCode);
  ELSE
	  SET @wagerType='Type1';
	  SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
	  IF (@wagerType='Type2') THEN
		CALL PlaceWinTypeTwo(gameRoundID, sessionID, gameSessionID, winAmount, @clearBonusLost, transactionRef, 
			@closeRound, isJackpotWin, @returnData, minimalData, gamePlayIDReturned, statusCode);  
	  ELSE
		CALL PlaceWin(gameRoundID, sessionID, gameSessionID, winAmount, @clearBonusLost, transactionRef, 
			@closeRound, isJackpotWin, @returnData, minimalData, gamePlayIDReturned, statusCode);  
	  END IF; 
  END IF;
  
  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, winAmount, transactionRef, roundRef, SUBSTRING(gameRef,1,40), clientStatID, gamePlayIDReturned, NOW(), NULL, IF(statusCode=0,1,0), statusCode
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name='Win';
  
    SET cwTransactionID=LAST_INSERT_ID();
  END IF;
 
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
  IF (canCommit) THEN COMMIT AND CHAIN; END IF;
END root$$

DELIMITER ;

