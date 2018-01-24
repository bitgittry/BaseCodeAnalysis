DROP procedure IF EXISTS `PlaceBetNoRound`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceBetNoRound`(operatorGameID BIGINT, sessionID BIGINT, gameSessionID BIGINT, clientStatID BIGINT, betAmount DECIMAL(18, 5), jackpotContribution DECIMAL(18, 5), ignorePlayLimit TINYINT(1), ignoreSessionExpiry TINYINT(1), transactionRef VARCHAR(80), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN  
  
 
  DECLARE totalPlayerBalance, betOther, betReal, balanceReal, exchangeRate, betTotalBase DECIMAL(18, 5) DEFAULT 0;
  DECLARE clientStatIDStat, clientStatIDCheck, clientID, gamePlayID, currencyID, gameID, gameManufacturerID, operatorGameIDCheck, fraudClientEventID, bonusFreeRoundID, gamePlayExtraID BIGINT DEFAULT -1;
  DECLARE playLimitEnabled, isLimitExceeded, isGameBlocked, isAccountClosed, fraudEnabled, disallowPlay, isPlayAllowed TINYINT(1) DEFAULT 0;
  DECLARE isSessionOpen TINYINT(1) DEFAULT 0;
  DECLARE licenseType VARCHAR(20) DEFAULT NULL;  
    
  SET gamePlayIDReturned=NULL;
  SET gamePlayExtraID=NULL;
  
  SELECT gs1.value_bool 
  INTO playLimitEnabled
  FROM gaming_settings gs1 
  WHERE gs1.name='PLAY_LIMIT_ENABLED';
   
  
  SELECT client_stat_id, gaming_clients.client_id, currency_id, current_real_balance, IF(gaming_clients.is_account_closed OR gaming_fraud_rule_client_settings.block_account,1,0), gaming_clients.is_play_allowed AND !gaming_fraud_rule_client_settings.block_gameplay
  INTO clientStatIDCheck, clientID, currencyID, balanceReal, isAccountClosed, isPlayAllowed   
  FROM gaming_client_stats
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id
  JOIN gaming_clients ON 
    gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1 AND
    gaming_client_stats.client_id=gaming_clients.client_id
  FOR UPDATE;
  
  if (clientStatIDCheck=-1 OR isAccountClosed=1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (isPlayAllowed=0 AND ignorePlayLimit=0) THEN 
    SET statusCode=6; 
    LEAVE root;
  END IF;
  
  
  SELECT gaming_operator_games.operator_game_id, gaming_operator_games.is_game_blocked,  gaming_games.game_id, gaming_games.game_manufacturer_id, gaming_license_type.name
  INTO operatorGameIDCheck, isGameBlocked, gameID, gameManufacturerID, licenseType
  FROM gaming_operator_games
  JOIN gaming_games ON gaming_operator_games.operator_game_id=operatorGameID AND gaming_operator_games.game_id=gaming_games.game_id
  JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_games.license_type_id;
  IF (operatorGameIDCheck<>operatorGameID OR (isGameBlocked=1 AND ignorePlayLimit=0)) THEN 
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  IF (ignoreSessionExpiry=0) THEN
    SELECT gaming_game_sessions.game_session_id, gaming_game_sessions.is_open, operator_game_id 
    INTO gameSessionID, isSessionOpen, operatorGameID 
    FROM gaming_game_sessions
    WHERE gaming_game_sessions.game_session_id=gameSessionID;
    
    IF (isSessionOpen=0) THEN
      SET statusCode=7;
      LEAVE root;
    END IF;
  END IF;
  
  IF (fraudEnabled AND ignorePlayLimit=0) THEN
    SELECT fraud_client_event_id, disallow_play 
    INTO fraudClientEventID, disallowPlay
    FROM gaming_fraud_client_events 
    JOIN gaming_fraud_classification_types ON gaming_fraud_client_events.client_stat_id=clientStatID AND gaming_fraud_client_events.is_current=1
      AND gaming_fraud_client_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id;
  
    IF (fraudClientEventID<>-1 AND disallowPlay=1) THEN
      SET statusCode=3;
      LEAVE root;
    END IF;
  END IF;
  
  
  
  
  IF (betAmount <= balanceReal) THEN
    SET betReal=betAmount;
  ELSE
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  
  SELECT exchange_rate into exchangeRate 
  FROM gaming_client_stats
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SET betTotalBase=ROUND(betAmount/exchangeRate,5);  
  
  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_game_sessions AS ggs ON ggs.game_session_id=gameSessionID
  LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
  SET total_real_played=total_real_played+betReal, total_real_played_base=total_real_played_base+ROUND(betReal/exchangeRate, 5), current_real_balance=current_real_balance-betReal, current_bonus_lost=0,
      last_played_date=NOW(),
      
      ggs.total_bet=ggs.total_bet+betAmount, ggs.total_bet_base=ggs.total_bet_base+betTotalBase, ggs.bets=ggs.bets+1, 
      
      gcss.total_bet=gcss.total_bet+betAmount,gcss.total_bet_base=gcss.total_bet_base+betTotalBase, gcss.bets=gcss.bets+1 
  WHERE gcs.client_stat_id = clientStatID;
                    
  
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, jackpot_contribution, timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, is_win_placed, is_processed, currency_id, round_transaction_no, game_play_message_type_id, transaction_ref, sign_mult, extra_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT betAmount, betTotalBase, exchangeRate, betReal, 0, 0, 0, 0, jackpotContribution, NOW(), gameID, gameManufacturerID, operatorGameID, clientID, clientStatID, sessionID, gameSessionID, NULL, gaming_payment_transaction_type.payment_transaction_type_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, 1, 0, currencyID, 1, game_play_message_type_id, transactionRef, -1, gamePlayExtraID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='Bet' AND gaming_client_stats.client_stat_id=clientStatID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=('InitialBet' COLLATE utf8_general_ci); 

  SET gamePlayID=LAST_INSERT_ID();  

  CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);  
  
  
  IF (playLimitEnabled) THEN 
    CALL PlayLimitsUpdate(clientStatID, licenseType, betAmount, 1);
  END IF;
  
  CALL PlayReturnData(gamePlayID, NULL, clientStatID , operatorGameID);
  
  SET gamePlayIDReturned = gamePlayID;
  SET statusCode=0;
  
  
END root$$

DELIMITER ;

