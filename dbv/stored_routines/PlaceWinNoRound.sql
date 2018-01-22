DROP procedure IF EXISTS `PlaceWinNoRound`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceWinNoRound`(sessionID BIGINT, gameSessionID BIGINT, winAmount DECIMAL(18, 5), transactionRef VARCHAR(80), returnData TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN
  
  
  
  
  
  DECLARE winTotalBase, winReal, betReal DECIMAL(18, 5) DEFAULT 0;
  DECLARE exchangeRate DECIMAL(18, 5) DEFAULT 0;
  DECLARE gameID, gameManufacturerID, operatorGameID, clientStatID, clientStatIDCheck, clientID, currencyID, gamePlayID, prevWinGamePlayID, gamePlayExtraID, bonusFreeRoundID, bonusFreeRoundRuleID, gamePlayWinCounterID BIGINT DEFAULT -1;
  DECLARE playLimitEnabled TINYINT(1) DEFAULT 0;
  
  SET gamePlayIDReturned=NULL;
  
  SELECT gs1.value_bool as vb1 INTO playLimitEnabled
  FROM gaming_settings gs1 WHERE gs1.name='PLAY_LIMIT_ENABLED';
  SELECT game_id, game_manufacturer_id, operator_game_id, client_stat_id
  INTO gameID, gameManufacturerID, operatorGameID, clientStatID
  FROM gaming_game_sessions
  WHERE game_session_id=gameSessionID;
  SELECT client_stat_id, client_id, gaming_client_stats.currency_id INTO clientStatIDCheck, clientID, currencyID
  FROM gaming_client_stats WHERE client_stat_id=clientStatID
  FOR UPDATE;
  
  SELECT exchange_rate INTO exchangeRate
  FROM gaming_operator_currency WHERE gaming_operator_currency.currency_id=currencyID;
    
  IF (clientStatIDCheck=-1) THEN 
    SET statusCode = 1;
    LEAVE root;
  END IF;
  
  
  SET winReal=winAmount;  
  
  
  SET winTotalBase=ROUND(winAmount/exchangeRate,5);
  
  UPDATE gaming_client_stats 
  LEFT JOIN gaming_game_sessions AS ggs ON ggs.game_session_id=gameSessionID
  LEFT JOIN gaming_client_sessions AS gcs ON gcs.session_id=sessionID   
  SET 
    total_real_won=total_real_won+winReal, total_real_won_base=total_real_won_base+ROUND(winReal/exchangeRate, 5), current_real_balance=current_real_balance+winReal, 
    current_bonus_lost=0,
    
    ggs.total_win=ggs.total_win+winAmount, ggs.total_win_base=ggs.total_win_base+winTotalBase, 
    
    gcs.total_win=gcs.total_win+winAmount, gcs.total_win_base=gcs.total_win_base+winTotalBase
  WHERE gaming_client_stats.client_stat_id=clientStatID;  
  
  
  SET @messageType='Win';
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_id, game_manufacturer_id, operator_game_id, operator_game_id_minigame, client_id, client_stat_id, session_id, game_session_id, game_play_key, game_round_id, payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, currency_id, round_transaction_no, game_play_message_type_id, transaction_ref, timestamp_hourly,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT winAmount, winTotalBase, exchangeRate, winReal, 0, 0, 0, 0, 0, NOW(), gameID, gameManufacturerID, operatorGameID, NULL, clientID, clientStatID, sessionID, gameSessionID, NULL, NULL, gaming_payment_transaction_type.payment_transaction_type_id, 1, current_real_balance, ROUND(current_bonus_balance+current_bonus_win_locked_balance,0), currencyID, 1, game_play_message_type_id, transactionRef, DATE_FORMAT(NOW(), '%Y-%m-%d %H:00'),0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='Win' AND gaming_client_stats.client_stat_id=clientStatID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=@messageType;
  
  SET gamePlayID=LAST_INSERT_ID();

  CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);
  
  
  IF (winAmount > 0 AND playLimitEnabled) THEN
    CALL PlayLimitsUpdate(clientStatID, 'Casino', winAmount, 0);
  END IF;
    
  IF (returnData) THEN
    
    CALL PlayReturnData(gamePlayID, NULL, clientStatID , operatorGameID);
  END IF;
  SET gamePlayIDReturned=gamePlayID;
  SET statusCode=0;
    
END root$$

DELIMITER ;

