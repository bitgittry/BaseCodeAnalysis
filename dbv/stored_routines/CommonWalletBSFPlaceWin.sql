DROP procedure IF EXISTS `CommonWalletBSFPlaceWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletBSFPlaceWin`(
  clientStatID BIGINT, transactionRef VARCHAR(80), roundRef BIGINT, gameRef VARCHAR(80), winAmount DECIMAL(18, 5), 
  closeRound TINYINT(1), extGameSessionID VARCHAR(40), JPWinAmount DECIMAL(18, 5), 
  canCommit TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN
   
  -- Parameter: minimalData

  DECLARE gameSessionID, sessionID, gameRoundID, clientStatIDCheck, currencyID, gameID, operatorGameID BIGINT DEFAULT -1;
  DECLARE isAlreadyProcessed, jackpotWinMoneyFlowAsNormalWin, isJackpotWin TINYINT(1) DEFAULT 0; 
  DECLARE gamePlayIDReturned, cwTransactionID BIGINT DEFAULT NULL;
  DECLARE roundExchangeRate DECIMAL(18,5) DEFAULT NULL;
  DECLARE gameManufacturerID BIGINT DEFAULT 13;
  DECLARE gameManufacturerName VARCHAR(80) DEFAULT 'BetSoft';
  DECLARE transactionType VARCHAR(80) DEFAULT 'Win';
  
  SET @wagerType='Type1';
  SELECT value_string INTO @wagerType FROM gaming_settings WHERE name='PLAY_WAGER_TYPE';
  
  SELECT client_stat_id, currency_id INTO clientStatIDCheck, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE; 
  IF (clientStatIDCheck=-1) THEN SET statusCode=101; LEAVE root; END IF;
  
  SET JPWinAmount=IFNULL(JPWinAmount, 0);
  IF(JPWinAmount > 0) THEN
	SET transactionType = 'PJWin';
	SET isJackpotWin=1;
	IF(winAmount>JPWinAmount) then
		SET winAmount = winAmount - JPWinAmount;
	END IF;
  END IF;

  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  SELECT gaming_game_sessions.game_session_id, gaming_game_sessions.session_id, gaming_games.game_id, gaming_game_sessions.operator_game_id 
  INTO gameSessionID, sessionID, gameID, operatorGameID
  FROM gaming_games 
  JOIN gaming_game_sessions ON (manufacturer_game_idf=gameRef AND gaming_games.game_manufacturer_id=gameManufacturerID) AND
    (gaming_game_sessions.client_stat_id=clientStatID AND gaming_game_sessions.game_id=gaming_games.game_id AND gaming_game_sessions.cw_game_latest);
    
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID 
  ORDER BY game_round_id DESC LIMIT 1;
  
  IF (gameSessionID=-1 AND gameRoundID!=-1) THEN
	SELECT gaming_game_sessions.game_session_id, gaming_game_sessions.session_id, gaming_game_sessions.game_id, gaming_game_sessions.operator_game_id 
    INTO gameSessionID, sessionID, gameID, operatorGameID
	FROM gaming_game_sessions 
	JOIN gaming_game_plays ON gaming_game_plays.game_round_id=gameRoundID AND gaming_game_sessions.game_session_id=gaming_game_plays.game_session_id
	ORDER BY gaming_game_plays.game_play_id DESC
    LIMIT 1;
  END IF;

  IF (gameRoundID=-1) THEN
      
    SELECT exchange_rate into roundExchangeRate 
    FROM gaming_client_stats
    JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
    WHERE gaming_client_stats.client_stat_id=clientStatID
    LIMIT 1;
    
    INSERT INTO gaming_game_rounds
    (bet_total, bet_total_base, bet_real, bet_bonus, bet_bonus_win_locked, bet_bonus_lost, jackpot_contribution, num_bets, num_transactions, date_time_start, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, round_ref, exchange_rate) 
    SELECT 0, 0, 0, 0, 0, 0, 0, 0, 0, NOW(), gaming_game_sessions.game_id, gaming_game_sessions.game_manufacturer_id, gaming_game_sessions.operator_game_id, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, 0, gaming_game_round_types.game_round_type_id, gaming_client_stats.currency_id, roundRef, roundExchangeRate 
    FROM gaming_game_round_types
    JOIN gaming_game_sessions ON gaming_game_round_types.name='Normal' AND gaming_game_sessions.game_session_id=gameSessionID
    JOIN gaming_client_stats ON gaming_game_sessions.client_stat_id=gaming_client_stats.client_stat_id; 
    
    SET gameRoundID=LAST_INSERT_ID();
  END IF;
  
  SET @clearBonusLost = 1;
  SET @returnData=1;
  
  SELECT value_bool INTO jackpotWinMoneyFlowAsNormalWin FROM gaming_settings WHERE name='JACKPOT_WIN_MONEY_FLOW_AS_NORMAL_WIN';
    
  SET winAmount=winAmount+JPWinAmount;

  IF(isJackpotWin=1 AND jackpotWinMoneyFlowAsNormalWin=0) THEN
    SET @JPgamePlayIDReturned = NULL;
    CALL PlaceJackpotWin(gameRoundID, sessionID, gameSessionID, winAmount, transactionRef, @returnData, gamePlayIDReturned, statusCode);
  ELSE
	  IF (@wagerType='Type2') THEN
		CALL PlaceWinTypeTwo(gameRoundID, sessionID, gameSessionID, winAmount, @clearBonusLost, transactionRef, closeRound, isJackpotWin, 
			@returnData, minimalData, gamePlayIDReturned, statusCode);  
	  ELSE
		CALL PlaceWin(gameRoundID, sessionID, gameSessionID, winAmount, @clearBonusLost, transactionRef, closeRound, isJackpotWin, 
			@returnData, minimalData, gamePlayIDReturned, statusCode);
	  END IF;
  END IF; 
  
  SELECT CONCAT_WS(',',extGameSessionID,@JPgamePlayIDReturned) INTO @extra;
  SELECT payment_transaction_type_id FROM gaming_payment_transaction_type WHERE `name` = transactionType INTO @transTypeID;

  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code, manual_update)
    SELECT gameManufacturerID, @transTypeID, winAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), @extra, IF(statusCode=0,1,0), statusCode, 0;
    SET cwTransactionID=LAST_INSERT_ID();
  END IF;
 
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  
END root$$

DELIMITER ;

