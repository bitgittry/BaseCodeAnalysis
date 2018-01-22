DROP procedure IF EXISTS `CommonWalletBSFBonusWin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletBSFBonusWin`(clientStatID BIGINT, transactionRef VARCHAR(40), bonusID BIGINT, bonusAmount DECIMAL(18, 5), canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN
  -- parameter isJackpotWin=0

  DECLARE gameSessionID, sessionID, gameRoundID, clientStatIDCheck, currencyID, gameID, operatorGameID BIGINT DEFAULT -1;
  DECLARE isAlreadyProcessed TINYINT(1) DEFAULT 0; 
  DECLARE gamePlayIDReturned, cwTransactionID, roundRef BIGINT DEFAULT NULL;
  DECLARE roundExchangeRate DECIMAL(18,5) DEFAULT NULL;
  DECLARE gameManufacturerID BIGINT DEFAULT 13;
  DECLARE gameManufacturerName VARCHAR(80) DEFAULT 'BetSoft';
  
  SET @transactionType='Win'; 
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, @transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  
  SELECT gaming_game_sessions.game_session_id, gaming_game_sessions.session_id, gaming_game_sessions.game_id, gaming_game_sessions.operator_game_id 
  INTO gameSessionID, sessionID, gameID, operatorGameID
  FROM gaming_game_sessions 
  WHERE gaming_game_sessions.client_stat_id=clientStatID AND gaming_game_sessions.cw_game_latest 
  ORDER BY game_session_id DESC LIMIT 1; 

  
  SELECT cw_round_id INTO roundRef FROM gaming_cw_rounds WHERE client_stat_id=clientStatID AND ext_bonus_id=bonusID;
  IF (roundRef IS NULL) THEN
    INSERT INTO gaming_cw_rounds (game_manufacturer_id, client_stat_id, game_id, cw_latest, timestamp, ext_bonus_id)
    VALUES (gameManufacturerID, clientStatID, 0, 0, NOW(), bonusID);
    
    SET roundRef=LAST_INSERT_ID();
  END IF;
  
  
  
  SELECT game_round_id INTO gameRoundID
  FROM gaming_game_rounds  FORCE INDEX (client_game_round_ref)
  WHERE round_ref=roundRef AND client_stat_id=clientStatID AND game_id=gameID AND is_round_finished=0 
  ORDER BY game_round_id DESC LIMIT 1;
  
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
  SET @closeRound=0;
  SET @returnData=1;
  CALL PlaceWin(gameRoundID, sessionID, gameSessionID, bonusAmount, @clearBonusLost, transactionRef, @closeRound, 0, @returnData, gamePlayIDReturned, statusCode);  

  IF (cwTransactionID IS NULL OR statusCode=0) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code, manual_update)
    SELECT gameManufacturerID, 13, bonusAmount, transactionRef, roundRef, NULL, clientStatID, gamePlayIDReturned, NOW(), NULL, IF(statusCode=0,1,0), statusCode, 0;
    SET cwTransactionID=LAST_INSERT_ID();
  END IF;

  IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
  
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
  

END root$$

DELIMITER ;

