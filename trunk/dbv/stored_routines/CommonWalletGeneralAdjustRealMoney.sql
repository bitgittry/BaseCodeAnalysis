DROP procedure IF EXISTS `CommonWalletGeneralAdjustRealMoney`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletGeneralAdjustRealMoney`(
  clientStatID BIGINT, gameManufacturerName VARCHAR(80), transactionRef VARCHAR(40), varAmount DECIMAL(18, 5), 
  transactionType VARCHAR(80), roundRef VARCHAR(40), gameRef VARCHAR(40), canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN
  -- round ref in this proc can be alpha numeric becuase we are only storing in gaming_cw_transactions
  DECLARE isAlreadyProcessed, isValidTransactionType TINYINT(1) DEFAULT 0;
  DECLARE clientStatIDCheck, gamePlayIDReturned, transactionID, cwTransactionID, currencyID BIGINT DEFAULT -1;
  DECLARE currentRealBalance DECIMAL(18, 5) DEFAULT 0;
  DECLARE sessionID, operatorGameID, gameManufacturerID BIGINT DEFAULT NULL; 
  DECLARE disableBonusMoney TINYINT(1) DEFAULT 1;
  DECLARE currencyCode, cwExchangeCurrency VARCHAR(3) DEFAULT NULL;
  DECLARE exchangeRate, originalAmount DECIMAL(18,5) DEFAULT NULL;
  IF (transactionType IN ('ExternalBonusLost') AND varAmount>0)  THEN
    SET varAmount=varAmount*-1;
  END IF;
  
  SELECT client_stat_id, current_real_balance, currency_id INTO clientStatIDCheck, currentRealBalance, currencyID
  FROM gaming_client_stats
  WHERE client_stat_id=clientStatID and is_active=1 
  FOR UPDATE; 
  
  
  CALL CommonWalletGeneralCheckTransactionProcessed(transactionRef, gameManufacturerName, transactionType, cwTransactionID, isAlreadyProcessed, statusCode);
  IF (isAlreadyProcessed) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF; 
    LEAVE root;
  END IF;
  
  
  IF (clientStatIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  SELECT 1 INTO isValidTransactionType 
  FROM gaming_payment_transaction_type
  WHERE name=transactionType AND is_common_wallet_adjustment_type=1;
  IF (isValidTransactionType!=1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF varAmount<0 AND transactionType NOT IN ('Correction','ExternalBonusLost','Tip','TransferIn','WinCancelled', 'TournamentTicketPurchase', 'TransferOut') THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  
  SELECT gaming_game_manufacturers.game_manufacturer_id, gaming_operator_games.operator_game_id, gaming_operator_games.disable_bonus_money, cw_exchange_currency
  INTO gameManufacturerID, operatorGameID, disableBonusMoney, cwExchangeCurrency
  FROM gaming_game_manufacturers 
  JOIN gaming_operators ON gaming_game_manufacturers.name=gameManufacturerName AND gaming_operators.is_main_operator
  LEFT JOIN gaming_games ON BINARY gaming_games.manufacturer_game_idf=gameRef AND gaming_game_manufacturers.game_manufacturer_id=gaming_games.game_manufacturer_id
  LEFT JOIN gaming_operator_games ON gaming_games.game_id=gaming_operator_games.game_id AND gaming_operators.operator_id=gaming_operator_games.operator_id;
  
  IF (gameManufacturerID!=-1 AND cwExchangeCurrency IS NOT NULL) THEN
    SELECT pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate INTO exchangeRate
    FROM gaming_operators
    JOIN gaming_currency ON gaming_currency.currency_code=cwExchangeCurrency
    JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gaming_currency.currency_id=gm_exchange_rate.currency_id 
    JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=currencyID 
    WHERE gaming_operators.is_main_operator=1;
  
    SET originalAmount=varAmount;
    SET varAmount=FLOOR(varAmount*exchangeRate);    
    SET currencyCode=cwExchangeCurrency;
  ELSE
    SET originalAmount=varAmount;
  END IF;
  
  IF (varAmount<0 AND currentRealBalance+varAmount < 0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;  
  
  UPDATE gaming_client_stats  
  SET current_real_balance=current_real_balance+varAmount, total_adjustments=total_adjustments+varAmount
  WHERE client_stat_id=clientStatID;
  
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, reason, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, varAmount, ROUND(varAmount/gaming_operator_currency.exchange_rate,5), gaming_client_stats.currency_id, gaming_operator_currency.exchange_rate, varAmount, 0, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, sessionID, NULL, pending_bets_real, pending_bets_bonus ,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_client_stats 
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=transactionType
  WHERE gaming_client_stats.client_stat_id=clientStatID;  
  
  IF (ROW_COUNT()=0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;
  SET transactionID=LAST_INSERT_ID();
  
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, game_manufacturer_id, game_id, operator_game_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, gaming_transactions.client_id, gaming_transactions.client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, gaming_transactions.currency_id, gaming_transactions.session_id, gaming_transactions.transaction_id, gameManufacturerID, gaming_operator_games.game_id, gaming_operator_games.operator_game_id, pending_bet_real, pending_bet_bonus,gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
  FROM gaming_transactions
  LEFT JOIN gaming_operator_games ON gaming_operator_games.operator_game_id=operatorGameID
  WHERE gaming_transactions.transaction_id=transactionID;
  
  SET gamePlayIDReturned=LAST_INSERT_ID();

  CALL GameUpdateRingFencedBalances(clientStatID,gamePlayIDReturned);  
  
  IF (operatorGameID IS NOT NULL) THEN
    CALL PlayReturnData(gamePlayIDReturned, NULL, clientStatID, operatorGameID, 0);
  ELSE
    CALL PlayReturnDataWithoutGame(gamePlayIDReturned, NULL, clientStatID, gameManufacturerID, 0);
  END IF;
  
  SET statusCode=0;
  
  IF (cwTransactionID IS NULL) THEN
    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code, currency_code, exchange_rate)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, originalAmount, transactionRef, roundRef, gameRef, clientStatID, gamePlayIDReturned, NOW(), NULL, 1, statusCode, currencyCode, exchangeRate 
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.name=gameManufacturerName AND transaction_type.name=transactionType;
  
    SET cwTransactionID=LAST_INSERT_ID(); 
  END IF;
  SET isAlreadyProcessed=0;
  SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessed AS already_processed;
    
END root$$

DELIMITER ;

