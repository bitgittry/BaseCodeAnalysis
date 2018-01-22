DROP procedure IF EXISTS `PlaceBetCancelSingleTransaction`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceBetCancelSingleTransaction`(
  gamePlayID BIGINT, sessionID BIGINT, gameSessionID BIGINT, betToCancelAmount DECIMAL(18, 5), transactionRef VARCHAR(80), 
  OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN

  -- Optimized + passing 0 as minimalData to PlayReturnData

  DECLARE cancelAmount, cancelTotalBase, cancelReal, cancelBonus, cancelBonusWinLocked, cancelRemain, cancelOther, cancelLoyaltyPoints, cancelLoyaltyPointsBonus DECIMAL(18, 5) DEFAULT 0;
  DECLARE betAmount, betTotalBase, betReal, betBonus, betBonusWinLocked DECIMAL(18, 5) DEFAULT 0;
  DECLARE exchangeRate, roundRemainingValue, winAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE gamePlayIDCheck, gameID, gameManufacturerID, operatorGameID, clientStatID, clientStatIDCheck, clientID, currencyID, gameRoundID, gamePlayExtraID BIGINT DEFAULT -1;
  DECLARE dateTimeWin DATETIME DEFAULT NULL;
  DECLARE bonusEnabledFlag, playLimitEnabled, disableBonusMoney, isAlreadyProcessed TINYINT(1) DEFAULT 0;
  DECLARE numBets, numTransactions INT DEFAULT 0;
  DECLARE licenseType, roundType VARCHAR(20) DEFAULT NULL;
  DECLARE clientWagerTypeID INT DEFAULT -1;
  
  SET gamePlayIDReturned=NULL;
  
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2
    INTO playLimitEnabled, bonusEnabledFlag
    FROM gaming_settings gs1 
    JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
    
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  
  
  SELECT gaming_game_plays.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.is_win_placed, gaming_game_plays.amount_total, gaming_game_plays.amount_total_base, 
	gaming_game_plays.game_id, gaming_game_plays.game_manufacturer_id, gaming_game_plays.operator_game_id, 
	gaming_game_plays.client_stat_id, gaming_game_plays.client_id, gaming_game_rounds.num_bets, gaming_game_rounds.num_transactions, gaming_game_plays.extra_id, 
    IFNULL(gaming_game_plays.loyalty_points,0), IFNULL(gaming_game_plays.loyalty_points_bonus,0), COALESCE(gp_win.amount_total, 0)
  INTO   gamePlayIDCheck, gameRoundID, isAlreadyProcessed, betAmount, betTotalBase, gameID, gameManufacturerID, 
         operatorGameID, clientStatID, clientID, numBets, numTransactions, gamePlayExtraID, cancelLoyaltyPoints, cancelLoyaltyPointsBonus, winAmount
  FROM gaming_game_plays
  JOIN gaming_game_rounds ON gaming_game_plays.game_play_id=gamePlayID AND gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
  LEFT JOIN gaming_game_plays gp_win ON gp_win.game_play_id = gaming_game_plays.game_play_id_win;
  
  SET isAlreadyProcessed = isAlreadyProcessed AND winAmount > 0;
  
  SELECT client_stat_id, client_id, gaming_client_stats.currency_id, exchange_rate 
  INTO clientStatIDCheck, clientID, currencyID, exchangeRate
  FROM gaming_client_stats 
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
  WHERE client_stat_id=clientStatID
  FOR UPDATE;
  
  SELECT disable_bonus_money, gaming_license_type.name, gaming_games.client_wager_type_id, gaming_game_round_types.name 
  INTO disableBonusMoney, licenseType, clientWagerTypeID, roundType
  FROM gaming_operator_games 
  STRAIGHT_JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id
  STRAIGHT_JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_games.license_type_id
  STRAIGHT_JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id=gameRoundID
  STRAIGHT_JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
  WHERE gaming_operator_games.operator_game_id=operatorGameID;

  SELECT SUM(gaming_game_plays.amount_total*gaming_game_plays.sign_mult*-1),
	SUM(gaming_game_plays.amount_real*gaming_game_plays.sign_mult*-1),
	SUM(gaming_game_plays.amount_bonus*gaming_game_plays.sign_mult*-1),
	SUM(gaming_game_plays.amount_bonus_win_locked*gaming_game_plays.sign_mult*-1)
  INTO roundRemainingValue,betReal,betBonus,betBonusWinLocked
  FROM gaming_game_rounds FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_game_plays ON 
	gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
  STRAIGHT_JOIN gaming_payment_transaction_type ON 
	gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND 
	gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
  STRAIGHT_JOIN gaming_cw_transactions FORCE INDEX (game_play_id) ON 
	gaming_cw_transactions.game_play_id=gaming_game_plays.game_play_id 
    AND gaming_cw_transactions.transaction_ref=transactionRef   
  WHERE gaming_game_rounds.game_round_id=gameRoundID;
   
  IF (gamePlayIDCheck=-1 OR clientStatIDCheck=-1) THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;

  IF (roundType='Normal') THEN
  
    -- IF (isAlreadyProcessed OR betToCancelAmount>roundRemainingValue) THEN
    --   SET statusCode=2;
    --   LEAVE root;
    -- END IF;
    
    IF (betToCancelAmount=betAmount) THEN
      SET cancelReal=betReal; 
      SET cancelBonus=betBonus; 
      SET cancelBonusWinLocked=betBonusWinLocked;
    ELSE  
      
      SET cancelRemain=betToCancelAmount;
      
      
      IF (cancelRemain > 0) THEN
        IF (cancelRemain > betBonusWinLocked) THEN
          SET cancelBonusWinLocked=ROUND(betBonusWinLocked,5);
          SET cancelRemain=ROUND(cancelRemain-betBonusWinLocked,0);
        ELSE
          SET cancelBonusWinLocked=ROUND(cancelRemain,5);
          SET cancelRemain=0;
        END IF;
      END IF;
      
      
      IF (cancelRemain > 0) THEN
        IF (cancelRemain > betBonus) THEN
          SET cancelBonus=ROUND(betBonus,5);
          SET cancelRemain=ROUND(cancelRemain-betBonus,0);
        ELSE
          SET cancelBonus=ROUND(cancelRemain,5);
          SET cancelRemain=0;
        END IF;
      END IF;
      
      
      IF (cancelRemain > 0) THEN
        IF (cancelRemain > betReal) THEN
          SET cancelReal=ROUND(betReal,5);
          SET cancelRemain=ROUND(cancelRemain-betReal,0);
        ELSE
          SET cancelReal=ROUND(cancelRemain,5);
          SET cancelRemain=0;
        END IF;
      END IF;
    END IF;
    
    SET @bonusLost=0;
    SET @bonusWinLockedLost=0;
    
    IF (bonusEnabledFlag) THEN 
      
      SET @numPlayBonusInstances=0;
      SELECT COUNT(*) INTO @numPlayBonusInstances
      FROM gaming_game_plays_bonus_instances 
      WHERE game_play_id=gamePlayID;
      
      IF (@numPlayBonusInstances>0) THEN
     
        
        UPDATE gaming_game_plays_bonus_instances
        STRAIGHT_JOIN gaming_bonus_instances ON gaming_game_plays_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
        SET
          gaming_game_plays_bonus_instances.wager_requirement_contribution_cancelled=IF(gaming_bonus_instances.is_active=1 AND gaming_bonus_instances.is_secured=0, gaming_game_plays_bonus_instances.wager_requirement_contribution, 0),
          gaming_game_plays_bonus_instances.win_bonus=IF(gaming_bonus_instances.is_active=1, gaming_game_plays_bonus_instances.bet_bonus, 0), 
          gaming_game_plays_bonus_instances.win_bonus_win_locked=IF(gaming_bonus_instances.is_active=1, gaming_game_plays_bonus_instances.bet_bonus_win_locked, 0), 
          gaming_game_plays_bonus_instances.win_real=0,
          gaming_game_plays_bonus_instances.lost_win_bonus=IF(gaming_bonus_instances.is_active=0, gaming_game_plays_bonus_instances.bet_bonus, 0), 
          gaming_game_plays_bonus_instances.lost_win_bonus_win_locked=IF(gaming_bonus_instances.is_active=0, gaming_game_plays_bonus_instances.bet_bonus_win_locked, 0)
        WHERE 
          gaming_game_plays_bonus_instances.game_play_id=gamePlayID;
          
        SELECT SUM(lost_win_bonus), SUM(lost_win_bonus_win_locked) 
        INTO @bonusLost, @bonusWinLockedLost
        FROM gaming_game_plays_bonus_instances
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID; 
          
        SET cancelBonus=ABS(ROUND(cancelBonus-@bonusLost,0));
        SET cancelBonusWinLocked=ABS(ROUND(cancelBonusWinLocked-@bonusWinLockedLost,0));
            
        UPDATE gaming_game_plays_bonus_instances
        STRAIGHT_JOIN gaming_bonus_instances ON 
          gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND
          gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
        SET 
          bonus_amount_remaining=bonus_amount_remaining+win_bonus,
          current_win_locked_amount=current_win_locked_amount+win_bonus_win_locked,
          bonus_wager_requirement_remain=bonus_wager_requirement_remain+wager_requirement_contribution_cancelled,
       
          is_used_all=IF(is_active=1 AND gaming_bonus_instances.open_rounds<=0 AND is_used_all=0 AND is_secured=0 AND is_lost=0 
			AND bonus_amount_remaining=0 AND current_win_locked_amount=0, 1, 0),
          used_all_date=IF(is_used_all=1 AND used_all_date IS NULL, NOW(), used_all_date),
          gaming_bonus_instances.is_active=IF(is_used_all,0,gaming_bonus_instances.is_active);
        
        INSERT INTO gaming_bonus_losts (bonus_instance_id, client_stat_id, bonus_lost_type_id, 
			bonus_amount, bonus_win_locked_amount, extra_id, date_time_lost, session_id)
        SELECT bonus_instance_id, client_stat_id, gaming_bonus_lost_types.bonus_lost_type_id, 
			IFNULL(SUM(lost_win_bonus),0), IFNULL(SUM(lost_win_bonus_win_locked),0), NULL, NOW(), sessionID
        FROM gaming_game_plays_bonus_instances  
        JOIN gaming_bonus_lost_types ON gaming_bonus_lost_types.name='BetCancelledAfterLostOrSecured'
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND 
			(gaming_game_plays_bonus_instances.lost_win_bonus!=0 OR gaming_game_plays_bonus_instances.lost_win_bonus_win_locked!=0) 
        GROUP BY gaming_game_plays_bonus_instances.bonus_instance_id;   
      END IF; 
           
    END IF; 
    
  ELSEIF (roundType='FreeRound') THEN
    SET cancelOther=betAmount;
    SET cancelReal=0; 
    SET cancelBonus=0; 
    SET cancelBonusWinLocked=0; 
    SET @bonusLost=0;
    SET @bonusWinLockedLost=0;
    
    IF ((numBets-1) = 0 AND betAmount=betToCancelAmount) THEN
      UPDATE gaming_bonus_free_rounds
      SET num_rounds_remaining=num_rounds_remaining+1, is_active=num_rounds_remaining>0
      WHERE bonus_free_round_id=gamePlayExtraID;
    END IF;
  END IF;
  
  UPDATE gaming_client_stats 
  SET total_real_played=total_real_played-cancelReal, current_real_balance=current_real_balance+cancelReal,
      total_bonus_played=total_bonus_played-(cancelBonus + @bonusLost), current_bonus_balance=current_bonus_balance+cancelBonus, 
      total_bonus_win_locked_played=total_bonus_win_locked_played-(cancelBonusWinLocked + @bonusWinLockedLost), 
      current_bonus_win_locked_balance=current_bonus_win_locked_balance+cancelBonusWinLocked,
      total_real_played_base=total_real_played_base-(cancelReal/exchangeRate), 
      total_bonus_played_base=total_bonus_played_base-((cancelBonus+cancelBonusWinLocked + @bonusLost + @bonusWinLockedLost)/exchangeRate), 
      total_loyalty_points_given = total_loyalty_points_given - cancelLoyaltyPoints, 
      current_loyalty_points = current_loyalty_points - cancelLoyaltyPoints, 
      total_loyalty_points_given_bonus = total_loyalty_points_given_bonus - cancelLoyaltyPointsBonus,
      loyalty_points_running_total = loyalty_points_running_total-cancelLoyaltyPoints
  WHERE client_stat_id=clientStatID;  
      
  SET cancelAmount=ROUND(cancelReal+cancelBonus+cancelBonusWinLocked+cancelOther+@bonusLost+@bonusWinLockedLost,0); 
  SET cancelTotalBase=ROUND(cancelAmount/exchangeRate,5);
  
  UPDATE gaming_game_plays
  SET is_processed=1, is_win_placed=1 
  WHERE game_play_id=gamePlayID;
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, is_win_placed, is_processed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, pending_bet_real, pending_bet_bonus, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus) 
  SELECT cancelAmount, cancelTotalBase, exchangeRate, cancelReal, cancelBonus, cancelBonusWinLocked, cancelOther, @bonusLost, @bonusWinLockedLost, 0, NOW(), gameID, gameManufacturerID, operatorGameID, clientID, clientStatID, sessionID, gameSessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 1, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, currencyID, numTransactions+1, game_play_message_type_id, pending_bets_real, pending_bets_bonus, cancelLoyaltyPoints * -1, gaming_client_stats.current_loyalty_points, cancelLoyaltyPointsBonus * -1, gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='BetCancelled' AND gaming_client_stats.client_stat_id=clientStatID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name='BetCancelled';
  
  SET gamePlayID=LAST_INSERT_ID();

  CALL GameUpdateRingFencedBalances(@clientStatID,LAST_INSERT_ID());   
  
  IF (playLimitEnabled) THEN 
    CALL PlayLimitsUpdateWithGame(sessionID, clientStatID, licenseType, cancelAmount*-1, 1, gameID);
  END IF;
  
  UPDATE gaming_game_rounds AS ggr
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET 
    ggr.bet_total=bet_total-cancelAmount, bet_total_base=ROUND(bet_total_base-cancelTotalBase,5), bet_real=bet_real-cancelReal, bet_bonus=bet_bonus-(cancelBonus + @bonusLost), 
    bet_bonus_win_locked=bet_bonus_win_locked-(cancelBonusWinLocked + @bonusWinLockedLost), win_bet_diffence_base=win_total_base-bet_total_base,
    bonus_lost=bonus_lost+@bonusLost, bonus_win_locked_lost=bonus_win_locked_lost+@bonusWinLockedLost, 
    ggr.num_bets=GREATEST(0, ggr.num_bets-1), ggr.num_transactions=ggr.num_transactions+1, 
    balance_real_after=current_real_balance, balance_bonus_after=ROUND(current_bonus_balance+current_bonus_win_locked_balance,0),
	loyalty_points=loyalty_points-cancelLoyaltyPoints,
	loyalty_points_bonus=loyalty_points_bonus-cancelLoyaltyPointsBonus 
  WHERE game_round_id=gameRoundID;
  
  UPDATE gaming_client_wager_stats AS gcws 
  SET gcws.num_bets=gcws.num_bets-1, gcws.total_real_wagered=gcws.total_real_wagered-cancelReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered-(cancelBonus+cancelBonusWinLocked),
	  gcws.loyalty_points=gcws.loyalty_points-IFNULL(cancelLoyaltyPoints,0), gcws.loyalty_points_bonus=gcws.loyalty_points_bonus-IFNULL(cancelLoyaltyPointsBonus,0)
  WHERE gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID;
  
  UPDATE gaming_game_sessions
  SET total_bet=total_bet-cancelAmount,total_bet_base=total_bet_base-cancelTotalBase, bets=GREATEST(0, bets-1), total_bet_real=total_bet_real-cancelReal, total_bet_bonus=total_bet_bonus-(cancelBonus+cancelBonusWinLocked),
      loyalty_points=loyalty_points-IFNULL(cancelLoyaltyPoints,0), loyalty_points_bonus=loyalty_points_bonus-IFNULL(cancelLoyaltyPointsBonus,0)
  WHERE game_session_id=gameSessionID;
  
  UPDATE gaming_client_sessions 
  SET total_bet=total_bet-cancelAmount,total_bet_base=total_bet_base-cancelTotalBase, bets=GREATEST(0, bets-1), total_bet_real=total_bet_real-cancelReal, total_bet_bonus=total_bet_bonus-(cancelBonus+cancelBonusWinLocked),
	  loyalty_points=loyalty_points-IFNULL(cancelLoyaltyPoints,0), loyalty_points_bonus=loyalty_points_bonus-IFNULL(cancelLoyaltyPointsBonus,0)
  WHERE session_id=sessionID;
  
  
  IF ((numBets-1) <= 0) THEN
    SET @checkWinZero=0; SET @checkRoundFinishMessage=0; SET @returnData=0;
    CALL PlayCloseRound(gameRoundID, @checkWinZero, @checkRoundFinishMessage, @returnData);
  END IF;
  
  CALL PlayReturnData(gamePlayID, gameRoundID, clientStatID , operatorGameID, 0);
  
  SET gamePlayIDReturned = gamePlayID;
  SET statusCode=0;
    
END root$$

DELIMITER ;

