DROP procedure IF EXISTS `CommonWalletFinSoftCancelBetByBetRef`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletFinSoftCancelBetByBetRef`(clientStatID BIGINT, transactionRef VARCHAR(100), betRef VARCHAR(40), canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  
  
  DECLARE gameManufacturerName VARCHAR(20) DEFAULT 'FinSoft';
  DECLARE gameManufacturerID BIGINT DEFAULT 7; 
  DECLARE sbBetWinID, gamePlayID, gamePlayIDReturned, sbBetID, clientStatIDCheck,gameRoundID BIGINT DEFAULT -1; 
  DECLARE cancelAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE liveBetType TINYINT(4) DEFAULT 2;
  DECLARE deviceType TINYINT(4) DEFAULT 1;
  DECLARE betType VARCHAR(20) DEFAULT NULL;

  
  SET statusCode=0;
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;

 
  IF (sbBetWinID!=-1) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
  
  
  END IF;
  
  IF (clientStatIDCheck=-1) THEN SET statusCode=1; END IF;
  
  
  SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_sb_bets.sb_bet_type_id, gaming_sb_bets.device_type, 'Single',gaming_game_plays.game_round_id 
  INTO sbBetID, gamePlayID, liveBetType, deviceType, betType, gameRoundID
  FROM gaming_sb_bet_singles 
  JOIN gaming_sb_bets ON gaming_sb_bet_singles.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_singles.sb_bet_id
    AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1
  JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_singles.sb_selection_id=gaming_game_plays.sb_extra_id 
    AND gaming_game_plays.game_play_message_type_id=8 AND gaming_game_plays.payment_transaction_type_id=12
  ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
    
  
  IF (gamePlayID=-1) THEN
    SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_sb_bets.sb_bet_type_id, gaming_sb_bets.device_type, 'Multiple' ,gaming_game_plays.game_round_id 
    INTO sbBetID, gamePlayID, liveBetType, deviceType, betType, gameRoundID
    FROM gaming_sb_bet_multiples 
    JOIN gaming_sb_bets ON gaming_sb_bet_multiples.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_multiples.sb_bet_id
      AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1 
    JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_multiples.sb_multiple_type_id=gaming_game_plays.sb_extra_id 
      AND gaming_game_plays.game_play_message_type_id=10 AND gaming_game_plays.payment_transaction_type_id=12
    ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
  END IF;

   SELECT SUM(amount_total*sign_mult)
  INTO cancelAmount FROM gaming_game_plays
  JOIN gaming_payment_transaction_type ON gaming_game_plays.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id
   WHERE game_round_id=gameRoundID  AND (gaming_game_plays.payment_Transaction_type_id IN (45,12,20) OR name = 'PartialCancel');

  
  IF (statusCode=0 AND (sbBetID=-1 OR gamePlayID=-1)) THEN
    SET statusCode=2;
  END IF;
  
  IF (statusCode=0 AND (sbBetID=-1 OR gamePlayID=-1)) THEN
    SET statusCode=2;
  END IF;
  
  
  IF (statusCode=0) THEN
    CALL PlaceSBBetCancel(clientStatID, gamePlayID, gameRoundID,cancelAmount, liveBetType, deviceType, gamePlayIDReturned, statusCode);
  END IF;
  
  INSERT INTO gaming_sb_bet_wins (sb_bet_id, game_play_id, transaction_ref, status_code, timestamp, client_stat_id)
  SELECT sbBetID, gamePlayID, transactionRef, statusCode, NOW(), clientStatID;
  
  INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount, game_play_id) 
  SELECT sbBetID, sb_bet_transaction_type_id, NOW(), cancelAmount, gamePlayIDReturned
  FROM gaming_sb_bet_transaction_types WHERE name='CancelBet';
  
  IF (canCommit) THEN COMMIT AND CHAIN; END IF;
  
  CALL CommonWalletSBReturnDataOnCancelBet(clientStatID, sbBetID);
  

END root$$

DELIMITER ;
