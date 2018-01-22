DROP procedure IF EXISTS `CommonWalletFinSoftBetAdjustmentByBetRef`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletFinSoftBetAdjustmentByBetRef`(clientStatID BIGINT, transactionRef VARCHAR(50), betRef VARCHAR(40), adjustAmount DECIMAL(18,5), canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  
  DECLARE gameManufacturerName VARCHAR(20) DEFAULT 'FinSoft';
  DECLARE gameManufacturerID BIGINT DEFAULT 7; 
  DECLARE sbBetWinID, gamePlayID, sbBetID, sbExtraID, clientStatIDCheck, clientID, currencyID, sbBetIDCheck, gamePlayMessageTypeID  BIGINT DEFAULT -1; 
  DECLARE gamePlayIDReturned, gameRoundID, gamePlayWinCounterID BIGINT DEFAULT NULL;
  DECLARE balanceReal, balanceBonus, adjustReal, adjustBonus, adjustBonusWinLocked, exchangeRate, betTotal, originalAdjustAmount, adjustAmountBase, remainAmountTotal DECIMAL(18,5) DEFAULT 0; 
  DECLARE playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly TINYINT(1) DEFAULT 0;
  DECLARE signMult, numTransactions INT DEFAULT 1;
  DECLARE clientWagerTypeID BIGINT DEFAULT 3; 
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
  DECLARE deviceType TINYINT(4) DEFAULT 1;
  
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3
  INTO playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly
  FROM gaming_settings gs1 
  JOIN gaming_settings gs2 ON gs2.name='IS_BONUS_ENABLED'
  JOIN gaming_settings gs3 ON gs3.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY'
  WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
  SELECT client_stat_id, client_id, currency_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance
  INTO clientStatIDCheck, clientID, currencyID, balanceReal, balanceBonus 
  FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  
  IF (clientStatIDCheck=-1) THEN
    SET statusCode=1;
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    LEAVE root;
  END IF;
  
  
  SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions 
  INTO sbBetID, gamePlayID, gameRoundID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions
  FROM gaming_sb_bet_singles 
  JOIN gaming_sb_bets ON gaming_sb_bet_singles.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_singles.sb_bet_id
    AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1
  JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_singles.sb_selection_id=gaming_game_plays.sb_extra_id AND 
    gaming_game_plays.game_play_message_type_id=8 AND gaming_game_plays.payment_transaction_type_id=12
  JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
  ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
    
  
  IF (gamePlayID=-1) THEN
    SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions 
    INTO sbBetID, gamePlayID, gameRoundID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions
    FROM gaming_sb_bet_multiples 
    JOIN gaming_sb_bets ON gaming_sb_bet_multiples.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_multiples.sb_bet_id
      AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1 
    JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_multiples.sb_multiple_type_id=gaming_game_plays.sb_extra_id AND 
      gaming_game_plays.game_play_message_type_id=10 AND gaming_game_plays.payment_transaction_type_id=12
    JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
    ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
  END IF;
  
  IF (gamePlayID=-1) THEN
    SET statusCode=2;
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    LEAVE root;
  END IF;
  
  
  SELECT sb_bet_id, game_play_id INTO sbBetIDCheck, gamePlayIDReturned FROM gaming_sb_bet_history WHERE transaction_ref=transactionRef AND sb_bet_transaction_type_id=6; 
  
  IF (sbBetIDCheck!=-1) THEN 
    SET statusCode=0;
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    CALL CommonWalletSBReturnTransactionData(gamePlayIDReturned, sbBetID, sbExtraID, 'Bet', clientStatID); 
    LEAVE root;
  END IF;
  
  
  SELECT exchange_rate into exchangeRate FROM gaming_client_stats
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
  WHERE gaming_client_stats.client_stat_id=clientStatID
  LIMIT 1;
  
  SET @winBonusLost=0;
  SET @winBonusWinLockedLost=0;
  SET adjustAmountBase=ROUND(adjustAmount/exchangeRate,5);
  SET originalAdjustAmount=adjustAmount;
  
  IF (adjustAmount>0) THEN
    
    SET signMult=-1;
    SET adjustBonus=0;
    SET adjustBonusWinLocked=0;      
    SET adjustReal=adjustAmount;
    
    SET adjustBonus=adjustBonus*-1;
    SET adjustBonusWinLocked=adjustBonusWinLocked*-1;      
    SET adjustReal=adjustReal*-1;
  ELSE
    
    SET signMult=1;
    SET adjustAmount=ABS(adjustAmount);
    
    
    SELECT SUM(amount_total*sign_mult*-1) AS amount_total INTO remainAmountTotal
    FROM gaming_game_plays 
    WHERE sb_bet_id=sbBetID AND sb_extra_id=sbExtraID AND payment_transaction_type_id IN (12,20,45);
    
    IF (remainAmountTotal<adjustAmount) THEN
      SET statusCode=3;
      IF (canCommit) THEN COMMIT AND CHAIN; END IF;
      LEAVE root;
    END IF;
    
    
    INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameRoundID);
    SET gamePlayWinCounterID=LAST_INSERT_ID();
    
    SELECT COUNT(*) INTO @numPlayBonusInstances
    FROM gaming_game_plays_bonus_instances  
    WHERE game_play_id=gamePlayID;  
    
    IF (@numPlayBonusInstances>0) THEN
   
      SET @winRealDeduct=0;    
      SET @winBonusAllTemp=0; 
      SET @winBonusTemp=0;
      SET @winBonusWinLockedTemp=0;
      
      SET @winBonusCurrent=0;
      SET @winBonusWinLockedCurrent=0;
      SET @winBonus=0;
      SET @winBonusWinLocked=0;
      
      SET @winBonusLostCurrent=0;
      SET @winBonusWinLockedLostCurrent=0;
      SET @winBonusLost=0;
      SET @winBonusWinLockedLost=0;
      SET @winRealBonusCurrent=0;
      
      SET @isBonusSecured=0;
      
      
      
      INSERT INTO gaming_game_plays_bonus_instances_wins (game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, timestamp, exchange_rate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution)
      SELECT gamePlayWinCounterID, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, NOW(), exchangeRate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, clientStatID, NULL, add_wager_contribution
      FROM
      (
        SELECT 
          play_bonus_instances.game_play_bonus_instance_id, play_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id,
          
          @isBonusSecured:=IF(gaming_bonus_instances.is_secured, 1, @isBonusSecured),
          @winBonusAllTemp:=ROUND(((bet_bonus+bet_bonus_win_locked)/betTotal)*adjustAmount,0), 
          @winBonusTemp:=ROUND((bet_bonus/betTotal)*adjustAmount,0),
          @winBonusWinLockedTemp:=@winBonusAllTemp-@winBonusTemp,
          
          @winBonusCurrent:=ROUND(IF(gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=0, @winBonusTemp, 0.0), 0) AS win_bonus,
          @winBonusWinLockedCurrent:=ROUND(IF(gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=0, @winBonusWinLockedTemp, 0.0), 0) AS win_bonus_win_locked,  
          @winRealBonusCurrent:=IF(gaming_bonus_instances.is_secured=1, 
            (CASE transfer_type.name
              WHEN 'All' THEN @winBonusAllTemp
              WHEN 'Bonus' THEN @winBonusTemp
              WHEN 'BonusWinLocked' THEN @winBonusWinLockedTemp
              WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
              WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((bonus_amount_given*transfer_upto_percentage)-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
              WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, @winBonusAllTemp))
              WHEN 'ReleaseAllBonus' THEN @winBonusAllTemp
              ELSE 0
            END), 0.0) AS win_real,
          
          @winBonusLostCurrent:=ROUND(IF(gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=1, @winBonusTemp, 0), 0) AS lost_win_bonus,
          @winBonusWinLockedLostCurrent:=ROUND(IF(gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=1, 
            IF(bet_returns_type.name='BonusWinLocked', @winBonusAllTemp, @winBonusWinLockedTemp),  
            IF(gaming_bonus_instances.is_secured=1, @winBonusAllTemp-@winRealBonusCurrent, 0)), 0) AS lost_win_bonus_win_locked,
          -
          @winBonus:=@winBonus+@winBonusCurrent,
          @winBonusWinLocked:=@winBonusWinLocked+@winBonusWinLockedCurrent,
          
          @winBonusLost:=@winBonusLost+@winBonusLostCurrent,
          @winBonusWinLockedLost:=@winBonusWinLockedLost+@winBonusWinLockedLostCurrent,
          
          IF (gaming_bonus_instances.is_active=0, 0, 
            ROUND(((play_bonus_instances.wager_requirement_contribution-IFNULL(play_bonus_instances.wager_requirement_contribution_cancelled,0))/betTotal)*adjustAmount,0)
            ) AS add_wager_contribution,           
          gaming_bonus_instances.bonus_amount_remaining, gaming_bonus_instances.current_win_locked_amount
        FROM gaming_game_plays_bonus_instances AS play_bonus_instances FORCE INDEX (game_play_id)
        JOIN gaming_bonus_instances ON play_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
        JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        JOIN gaming_bonus_types_bet_returns AS bet_returns_type ON gaming_bonus_rules.bonus_type_bet_return_id=bet_returns_type.bonus_type_bet_return_id
        JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
        LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON gaming_bonus_rules.bonus_rule_id=wager_restrictions.bonus_rule_id AND wager_restrictions.currency_id=currencyID
        WHERE play_bonus_instances.game_play_id=gamePlayID
      ) AS XX
      ON DUPLICATE KEY UPDATE bonus_instance_id=VALUES(bonus_instance_id), win_real=VALUES(win_real), win_bonus=VALUES(win_bonus), win_bonus_win_locked=VALUES(win_bonus_win_locked), lost_win_bonus=VALUES(lost_win_bonus), lost_win_bonus_win_locked=VALUES(lost_win_bonus_win_locked), client_stat_id=VALUES(client_stat_id);
            
      
      UPDATE gaming_game_plays_bonus_instances AS pbi_update
      JOIN gaming_game_plays_bonus_instances_wins AS PIU ON PIU.game_play_win_counter_id=gamePlayWinCounterID AND pbi_update.game_play_bonus_instance_id=PIU.game_play_bonus_instance_id 
      JOIN gaming_bonus_instances ON pbi_update.bonus_instance_id=gaming_bonus_instances.bonus_instance_id AND PIU.game_play_bonus_instance_id=pbi_update.game_play_bonus_instance_id 
      SET
        pbi_update.wager_requirement_contribution_cancelled=IFNULL(pbi_update.wager_requirement_contribution_cancelled,0)+PIU.add_wager_contribution,
        pbi_update.win_bonus=IFNULL(pbi_update.win_bonus,0)+PIU.win_bonus, 
        pbi_update.win_bonus_win_locked=IFNULL(pbi_update.win_bonus_win_locked,0)+PIU.win_bonus_win_locked, 
        pbi_update.win_real=IFNULL(pbi_update.win_real,0)+PIU.win_real,
        pbi_update.lost_win_bonus=IFNULL(pbi_update.lost_win_bonus,0)+PIU.lost_win_bonus,
        pbi_update.lost_win_bonus_win_locked=IFNULL(pbi_update.lost_win_bonus_win_locked,0)+PIU.lost_win_bonus_win_locked;
     
      
      SET adjustBonus=@winBonus;
      SET adjustBonusWinLocked=@winBonusWinLocked;      
      SET adjustReal=adjustAmount-(adjustBonus+adjustBonusWinLocked)-(@winBonusLost+@winBonusWinLockedLost);
      
      
      
      UPDATE gaming_bonus_instances
      JOIN 
      (
        SELECT play_bonus.bonus_instance_id, SUM(play_bonus_wins.win_real) AS win_real, SUM(play_bonus_wins.win_bonus) AS win_bonus, 
          SUM(play_bonus_wins.win_bonus_win_locked) AS win_bonus_win_locked, SUM(IFNULL(play_bonus_wins.add_wager_contribution, 0)) AS add_wager_contribution, MIN(play_bonus.now_used_all) AS now_used_all
        FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins
        JOIN gaming_game_plays_bonus_instances AS play_bonus ON play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND play_bonus_wins.game_play_bonus_instance_id=play_bonus.game_play_bonus_instance_id 
        
        GROUP BY play_bonus.bonus_instance_id
      ) AS PB ON gaming_bonus_instances.bonus_instance_id=PB.bonus_instance_id  
      SET 
        bonus_amount_remaining=bonus_amount_remaining+PB.win_bonus,
        current_win_locked_amount=current_win_locked_amount+PB.win_bonus_win_locked,
        bonus_transfered_total=bonus_transfered_total+PB.win_real,
        
        bonus_wager_requirement_remain=IF(gaming_bonus_instances.is_active, bonus_wager_requirement_remain+PB.add_wager_contribution, bonus_wager_requirement_remain);
      
      IF (@winBonusLost+@winBonusWinLockedLost>0) THEN
        
        INSERT INTO gaming_bonus_losts (bonus_instance_id, client_stat_id, bonus_lost_type_id, bonus_amount, bonus_win_locked_amount, extra_id, date_time_lost, session_id)
        SELECT bonus_instance_id, client_stat_id, gaming_bonus_lost_types.bonus_lost_type_id, IFNULL(SUM(lost_win_bonus),0), IFNULL(SUM(lost_win_bonus_win_locked),0), gamePlayWinCounterID, NOW(), sessionID
        FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins  
        JOIN gaming_bonus_lost_types ON 
           play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND
          (play_bonus_wins.lost_win_bonus!=0 OR play_bonus_wins.lost_win_bonus_win_locked!=0) 
        WHERE gaming_bonus_lost_types.name='BetAdjustmentAfterLost'
        GROUP BY play_bonus_wins.bonus_instance_id;  
      END IF;
    ELSE
      SET adjustBonus=0;
      SET adjustBonusWinLocked=0;      
      SET adjustReal=adjustAmount;
    END IF; 
  END IF; 
  
  UPDATE gaming_client_stats AS gcs
  SET 
    total_real_played=total_real_played-adjustReal, current_real_balance=current_real_balance+adjustReal,
    total_bonus_played=total_bonus_played-adjustBonus, current_bonus_balance=current_bonus_balance+adjustBonus, 
    total_bonus_win_locked_played=total_bonus_win_locked_played-adjustBonusWinLocked, current_bonus_win_locked_balance=current_bonus_win_locked_balance+adjustBonusWinLocked, 
    gcs.total_real_played_base=gcs.total_real_played_base+IFNULL((adjustReal/exchangeRate),0), gcs.total_bonus_played_base=gcs.total_bonus_played_base-((adjustBonus+adjustBonusWinLocked)/exchangeRate)
  WHERE gcs.client_stat_id=clientStatID;  
  
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, game_round_id, payment_transaction_type_id, is_win_placed, is_processed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, sb_extra_id, sb_bet_id, license_type_id, device_type, sign_mult,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT ABS(adjustAmount), ABS(adjustAmountBase), exchangeRate, ABS(adjustReal), ABS(adjustBonus), ABS(adjustBonusWinLocked), 0, @winBonusLost, @winBonusWinLockedLost, 0, NOW(), gameManufacturerID, clientID, clientStatID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 1, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, currencyID, numTransactions+1, gamePlayMessageTypeID, sbExtraID, sbBetID, licenseTypeID, deviceType, signMult,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='BetAdjustment' AND gaming_client_stats.client_stat_id=clientStatID;
  
  SET gamePlayIDReturned=LAST_INSERT_ID();

  CALL GameUpdateRingFencedBalances(clientStatID,gamePlayIDReturned);  
  
  
  INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units)
  SELECT gamePlayIDReturned, 12, adjustAmount*-1, adjustAmountBase*-1, adjustReal*-1, adjustReal/exchangeRate*-1, (adjustBonus+adjustBonusWinLocked)*-1, (adjustBonus+adjustBonusWinLocked)/exchangeRate*-1, NOW(), exchangeRate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, 0
  FROM gaming_game_plays_sb
  WHERE game_play_id=gamePlayID;
  
  
  IF (playLimitEnabled AND adjustAmount!=0) THEN 
    CALL PlayLimitsUpdate(clientStatID, 'sportsbook', originalAdjustAmount, 0);
  END IF;
  
  
  
  UPDATE gaming_game_rounds AS ggr
  SET 
    ggr.bet_total=bet_total-adjustAmount, bet_total_base=ROUND(bet_total_base-adjustAmountBase,5), bet_real=bet_real-adjustReal, bet_bonus=bet_bonus-adjustBonus, bet_bonus_win_locked=bet_bonus_win_locked-adjustBonusWinLocked, 
    win_bet_diffence_base=win_total_base-bet_total_base, ggr.num_transactions=ggr.num_transactions+1
  WHERE game_round_id=gameRoundID;
  
  UPDATE gaming_client_wager_stats AS gcws 
  SET gcws.total_real_wagered=gcws.total_real_wagered-adjustReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered-(adjustBonus+adjustBonusWinLocked)
  WHERE gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID;
  
  INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount, transaction_ref, game_play_id) 
  SELECT sbBetID, sb_bet_transaction_type_id, NOW(), originalAdjustAmount, transactionRef, gamePlayIDReturned
  FROM gaming_sb_bet_transaction_types WHERE name='BetAdjustment';
  
  SET statusCode=0;
  IF (canCommit) THEN COMMIT AND CHAIN; END IF;
  CALL CommonWalletSBReturnTransactionData(gamePlayIDReturned, sbBetID, sbExtraID, 'Bet', clientStatID); 
  
END root$$

DELIMITER ;

