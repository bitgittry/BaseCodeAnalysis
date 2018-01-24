DROP procedure IF EXISTS `PlaceBetCancel`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceBetCancel`(
  gamePlayID BIGINT, sessionID BIGINT, gameSessionID BIGINT, betToCancelAmount DECIMAL(18, 5), transactionRef VARCHAR(80), 
  minimalData TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN

  -- gamePlayID BIGINT, clientStatID BIGINT,
  -- gamePlayIDVar, 
  -- ,betAmount,betAmountBase,betReal,betBonus,betBonusWinLocked
  -- PlayLimitUpdate - gameID

  /* Status Codes
  0 : Success
  1 : gamePlayID or clientStatID not found
  2 : gamePlayID is already processed or amount to refund is bigger than bet
  */ 
  
  DECLARE cancelAmount, cancelTotalBase, cancelReal, cancelBonus, cancelBonusWinLocked, cancelRemain, 
	cancelOther, cancelLoyaltyPoints, cancelLoyaltyPointsBonus DECIMAL(18, 5) DEFAULT 0;
  DECLARE betAmount, betTotalBase, betReal, betBonus, betBonusWinLocked DECIMAL(18, 5) DEFAULT 0;
  DECLARE exchangeRate, roundRemainingValue, winAmount, releasedLockedFunds DECIMAL(18, 5) DEFAULT 0;
  DECLARE gamePlayIDCheck, gameID, gameManufacturerID, operatorGameID, clientStatID, clientStatIDCheck, clientID, 
	currencyID, gameRoundID, gamePlayExtraID BIGINT DEFAULT -1;
  DECLARE dateTimeWin DATETIME DEFAULT NULL;
  DECLARE bonusEnabledFlag, playLimitEnabled, disableBonusMoney, isAlreadyProcessed,
	ringFencedEnabled, taxEnabled, ruleEngineEnabled TINYINT(1) DEFAULT 0;
  DECLARE numBets, numTransactions INT DEFAULT 0;
  DECLARE licenseType, roundType VARCHAR(20) DEFAULT NULL;
  DECLARE licenseTypeID TINYINT(4) DEFAULT 1;
  DECLARE clientWagerTypeID INT DEFAULT -1;
  
  SET gamePlayIDReturned=NULL;
  
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, gs4.value_bool as vb4, gs5.value_bool as vb5
    INTO playLimitEnabled, bonusEnabledFlag, ringFencedEnabled, taxEnabled, ruleEngineEnabled
    FROM gaming_settings gs1 
    STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
    STRAIGHT_JOIN gaming_settings gs3 ON (gs3.name='RING_FENCED_ENABLED')
    STRAIGHT_JOIN gaming_settings gs4 ON (gs4.name='TAX_ON_GAMEPLAY_ENABLED')
    STRAIGHT_JOIN gaming_settings gs5 ON (gs5.name='RULE_ENGINE_ENABLED')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
    
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  
  -- don't remove the order because we are setting the ClientStatID in here
  SELECT gaming_game_plays.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.is_win_placed, gaming_game_plays.amount_total, gaming_game_plays.amount_total_base, 
	gaming_game_plays.game_id, gaming_game_plays.game_manufacturer_id, gaming_game_plays.operator_game_id, 
	gaming_game_plays.client_stat_id, gaming_game_plays.client_id, gaming_game_rounds.num_bets, gaming_game_rounds.num_transactions, gaming_game_plays.extra_id, 
    IFNULL(gaming_game_plays.loyalty_points,0), IFNULL(gaming_game_plays.loyalty_points_bonus,0), gaming_game_plays.released_locked_funds
  INTO   gamePlayIDCheck, gameRoundID, isAlreadyProcessed, betAmount, betTotalBase, gameID, gameManufacturerID, 
         operatorGameID, clientStatID, clientID, numBets, numTransactions, gamePlayExtraID, cancelLoyaltyPoints, cancelLoyaltyPointsBonus, releasedLockedFunds
  FROM gaming_game_plays
  STRAIGHT_JOIN gaming_game_rounds ON 
	gaming_game_rounds.game_round_id=gaming_game_plays.game_round_id
  WHERE gaming_game_plays.game_play_id=gamePlayID;
  
  SELECT COALESCE(SUM(if(payment_transaction_type_id = 13, amount_total, -amount_total)), 0)
  INTO winAmount
  FROM gaming_game_plays 
  WHERE payment_transaction_type_id in (13, 30) AND game_round_id = gameRoundID;
  
  SET isAlreadyProcessed = isAlreadyProcessed AND winAmount > 0;
  
  SELECT client_stat_id, client_id, gaming_client_stats.currency_id 
  INTO clientStatIDCheck, clientID, currencyID
  FROM gaming_client_stats 
  WHERE client_stat_id=clientStatID;
  
  SELECT exchange_rate INTO exchangeRate FROM gaming_operator_currency WHERE gaming_operator_currency.currency_id=currencyID;
  
  SELECT disable_bonus_money, gaming_license_type.name, gaming_license_type.license_type_id, gaming_games.client_wager_type_id, gaming_game_round_types.name 
  INTO disableBonusMoney, licenseType, licenseTypeID, clientWagerTypeID, roundType
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
  FROM gaming_game_rounds
  STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND 
	gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
  WHERE gaming_game_rounds.game_round_id=gameRoundID;
    
  IF (gamePlayIDCheck=-1 OR clientStatIDCheck=-1) THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (roundType='Normal') THEN
  
    IF (isAlreadyProcessed OR betToCancelAmount>roundRemainingValue) THEN
      SET statusCode=2;
      LEAVE root;
    END IF;
    
    -- if amount to refund is the same as the bet value then there is no need to select from real or bonus but refund as played 
    IF (betToCancelAmount=betAmount) THEN
      SET cancelReal=betReal; 
      SET cancelBonus=betBonus; 
      SET cancelBonusWinLocked=betBonusWinLocked;
    ELSE  
      
      SET cancelRemain=betToCancelAmount;
      
      -- Cancel BonusWinLocked  
      IF (cancelRemain > 0) THEN
        IF (cancelRemain > betBonusWinLocked) THEN
          SET cancelBonusWinLocked=ROUND(betBonusWinLocked,5);
          SET cancelRemain=ROUND(cancelRemain-betBonusWinLocked,0);
        ELSE
          SET cancelBonusWinLocked=ROUND(cancelRemain,5);
          SET cancelRemain=0;
        END IF;
      END IF;
      
      -- Cancel Bonus
      IF (cancelRemain > 0) THEN
        IF (cancelRemain > betBonus) THEN
          SET cancelBonus=ROUND(betBonus,5);
          SET cancelRemain=ROUND(cancelRemain-betBonus,0);
        ELSE
          SET cancelBonus=ROUND(cancelRemain,5);
          SET cancelRemain=0;
        END IF;
      END IF;
      
      -- Cancel Real
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
     
        -- 1. update gaming_bonus_instances in-order to partition winnings 
        UPDATE gaming_game_plays_bonus_instances
        STRAIGHT_JOIN gaming_bonus_instances ON 
			gaming_game_plays_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
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
            
        -- 2. update gaming_bonus_instances in-oder to add bonus_amount_remaining, current_win_locked_amount, bonus_wager_requirement_remain
        -- check wether all the bonus has been used
        UPDATE gaming_game_plays_bonus_instances
        STRAIGHT_JOIN gaming_bonus_instances ON
          gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
        SET 
          bonus_amount_remaining=bonus_amount_remaining+win_bonus,
          current_win_locked_amount=current_win_locked_amount+win_bonus_win_locked,
          bonus_wager_requirement_remain=bonus_wager_requirement_remain+wager_requirement_contribution_cancelled,
       --   gaming_bonus_instances.open_rounds=gaming_bonus_instances.open_rounds-1,
          is_used_all=IF(is_active=1 AND gaming_bonus_instances.open_rounds<=0 AND is_used_all=0 AND is_secured=0 AND is_lost=0 AND bonus_amount_remaining=0 AND current_win_locked_amount=0, 1, 0),
          used_all_date=IF(is_used_all=1 AND used_all_date IS NULL, NOW(), used_all_date),
          gaming_bonus_instances.is_active=IF(is_used_all,0,gaming_bonus_instances.is_active)
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;  
        
        -- 2.1 If any of the bonuses had been lost between the bet and the win then need to transfer to gaming_bonus_losts
        INSERT INTO gaming_bonus_losts (bonus_instance_id, client_stat_id, bonus_lost_type_id, 
			bonus_amount, bonus_win_locked_amount, extra_id, date_time_lost, session_id)
        SELECT bonus_instance_id, client_stat_id, gaming_bonus_lost_types.bonus_lost_type_id, 
			IFNULL(SUM(lost_win_bonus),0), IFNULL(SUM(lost_win_bonus_win_locked),0), NULL, NOW(), sessionID
        FROM gaming_game_plays_bonus_instances  
        STRAIGHT_JOIN gaming_bonus_lost_types ON gaming_bonus_lost_types.name='BetCancelledAfterLostOrSecured'
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND (gaming_game_plays_bonus_instances.lost_win_bonus!=0 OR gaming_game_plays_bonus_instances.lost_win_bonus_win_locked!=0) -- Condition
        GROUP BY gaming_game_plays_bonus_instances.bonus_instance_id;   
        
      END IF; -- @numPlayBonusInstances>0
           
    END IF; -- bonus section 
    
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
  
  -- addd player account
  UPDATE gaming_client_stats 
  SET total_real_played=total_real_played-cancelReal, current_real_balance=current_real_balance+cancelReal,
      total_bonus_played=total_bonus_played-(cancelBonus + @bonusLost),  current_bonus_balance=current_bonus_balance+cancelBonus, 
      total_bonus_win_locked_played=total_bonus_win_locked_played-(cancelBonusWinLocked + @bonusWinLockedLost), current_bonus_win_locked_balance=current_bonus_win_locked_balance+cancelBonusWinLocked,
      total_real_played_base=total_real_played_base-(cancelReal/exchangeRate),
      total_bonus_played_base=total_bonus_played_base-((cancelBonus+  @bonusLost + cancelBonusWinLocked + @bonusWinLockedLost)/exchangeRate), 
      total_loyalty_points_given = total_loyalty_points_given - cancelLoyaltyPoints, current_loyalty_points = current_loyalty_points - cancelLoyaltyPoints, total_loyalty_points_given_bonus = total_loyalty_points_given_bonus - cancelLoyaltyPointsBonus,
      loyalty_points_running_total = loyalty_points_running_total-cancelLoyaltyPoints,
	  locked_real_funds = locked_real_funds + releasedLockedFunds
  WHERE client_stat_id=clientStatID;  
   
   
  SET cancelAmount=ROUND(cancelReal+cancelBonus+cancelBonusWinLocked+cancelOther+@bonusLost+@bonusWinLockedLost,0); -- check cancelAmount matches
  SET cancelTotalBase=ROUND(cancelAmount/exchangeRate,5);
  
  -- 3. update is_win_placed flag (set flags are already processed)
  UPDATE gaming_game_plays
  SET is_processed=1, is_win_placed=1 -- , game_play_id_win=NULL
  WHERE game_play_id=gamePlayID;
  
  -- 3. Insert into gaming_game_plays 
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, is_win_placed, is_processed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, pending_bet_real, pending_bet_bonus, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, license_type_id) 
  SELECT cancelAmount, cancelTotalBase, exchangeRate, cancelReal, cancelBonus, cancelBonusWinLocked, cancelOther, @bonusLost, @bonusWinLockedLost, 0, NOW(), gameID, gameManufacturerID, operatorGameID, clientID, clientStatID, sessionID, gameSessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 1, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, currencyID, numTransactions+1, game_play_message_type_id, pending_bets_real, pending_bets_bonus, cancelLoyaltyPoints * -1, gaming_client_stats.current_loyalty_points, cancelLoyaltyPointsBonus * -1, gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus, licenseTypeID
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='BetCancelled' AND gaming_client_stats.client_stat_id=clientStatID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name='BetCancelled';
  
  SET gamePlayID=LAST_INSERT_ID();

  IF (ringFencedEnabled) THEN
	CALL GameUpdateRingFencedBalances(@clientStatID,LAST_INSERT_ID());   
  END IF;
  
  -- 2.4 Update Play Limits Current Value
  IF (playLimitEnabled) THEN 
    CALL PlayLimitsUpdateWithGame(sessionID, clientStatID, licenseType, cancelAmount*-1, 1, gameID);
  END IF;
  
  -- 4. update tables
  -- update gaming_game_rounds with win amount
  UPDATE gaming_client_stats
  STRAIGHT_JOIN gaming_game_rounds AS ggr ON ggr.game_round_id=gameRoundID
  SET 
    ggr.bet_total=bet_total-cancelAmount, bet_total_base=ROUND(bet_total_base-cancelTotalBase,5), bet_real=bet_real-cancelReal, bet_bonus=bet_bonus-(cancelBonus + @bonusLost), 
    bet_bonus_win_locked=bet_bonus_win_locked-(cancelBonusWinLocked + @bonusWinLockedLost), win_bet_diffence_base=win_total_base-ROUND(bet_total_base-cancelTotalBase,5),
    bonus_lost=bonus_lost+@bonusLost, bonus_win_locked_lost=bonus_win_locked_lost+@bonusWinLockedLost, 
    ggr.num_bets=GREATEST(0, ggr.num_bets-1), ggr.num_transactions=ggr.num_transactions+1, 
    balance_real_after=current_real_balance, balance_bonus_after=ROUND(current_bonus_balance+current_bonus_win_locked_balance,0),
	loyalty_points=loyalty_points-cancelLoyaltyPoints,
	loyalty_points_bonus=loyalty_points_bonus-cancelLoyaltyPointsBonus 
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
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
  
  -- close the round
  IF ((numBets-1) <= 0) THEN
    SET @checkWinZero=0; SET @checkRoundFinishMessage=0; SET @returnData=0;
    CALL PlayCloseRound(gameRoundID, @checkWinZero, @checkRoundFinishMessage, @returnData);
  END IF;
  
  -- 5. Return Data  
  -- return data
  CALL PlayReturnData(gamePlayID, gameRoundID, clientStatID , operatorGameID, minimalData);
  
  /* Needed for Keith !!!
  -- return data: gaming_game_session
  SELECT game_session_id,game_session_key,player_handle,total_bet,total_win 
  FROM gaming_game_sessions 
  WHERE game_session_id=gameSessionID; -- client_stat_id=clientStatID and is_open=1
  */
  SET gamePlayIDReturned = gamePlayID;
  SET statusCode=0;
    

END root$$

DELIMITER ;

