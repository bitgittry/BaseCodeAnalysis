DROP procedure IF EXISTS `CommonWalletFinSoftUndoCancelBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletFinSoftUndoCancelBet`(clientStatID BIGINT, transactionRef VARCHAR(64),betRef VARCHAR(40), canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  DECLARE gameManufacturerName VARCHAR(80) DEFAULT 'FinSoft';
  DECLARE gameManufacturerID BIGINT DEFAULT 7;
  DECLARE gamePlayID, sbBetID, clientID, gameRoundID, currencyID, clientWagerTypeID, countryID,newGamePlayID,sessionID,sbExtraID,cancelGamePlayerID,sbBetIDCheck,gamePlayIDReturned BIGINT DEFAULT -1;
  DECLARE isAlreadyProcessed, playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly,disableBonusMoney,useFreeBet TINYINT(1) DEFAULT 0;
  DECLARE numSingles, numMultiples, sbBetStatusCode, noMoreRecords,RoundTypeID,gamePlayMessageTypeID,numTransactions INT DEFAULT 0;
  DECLARE betAmount, betReal, betBonus, betBonusWinLocked, betRealRemain, betBonusRemain, betBonusWinLockedRemain,betTotal,totalPlayerBalance,betFreeBet,betFreeBetWinLocked,cancelAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE balanceReal, balanceBonus, balanceWinLocked,  balanceFreeBet,  balaneFreeBetWinLocked, betRemain, exchangeRate, betAmountBase, sbOdd, pendingBetsReal, pendingBetsBonus DECIMAL(18, 5) DEFAULT 0;
  DECLARE roundType, licenseType VARCHAR(20) DEFAULT NULL;
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
  DECLARE liveBetType TINYINT(4) DEFAULT 2; 
  DECLARE deviceType TINYINT(4) DEFAULT 1;
  DECLARE defaultSBSelectionID, defaultSBMultipleTypeID BIGINT DEFAULT NULL;

  SELECT sb_bet_id, game_play_id, sb_extra_id INTO sbBetIDCheck, gamePlayIDReturned ,sbExtraID
  FROM gaming_sb_bet_history
  JOIN gaming_sb_bet_transaction_types ON gaming_sb_bet_transaction_types.sb_bet_transaction_type_id = gaming_sb_bet_history.sb_bet_transaction_type_id
  WHERE transaction_ref=transactionRef AND gaming_sb_bet_transaction_types.name = 'UndoCancelBet';

  IF (sbBetIDCheck!=-1) THEN 
    SET statusCode=0;
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    CALL CommonWalletSBReturnTransactionData(gamePlayIDReturned, sbBetIDCheck, sbExtraID, 'Bet', clientStatID);
    LEAVE root;
  END IF;
  
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, gs4.value_long as vb4, gs5.value_long AS vb5
  INTO playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, defaultSBSelectionID, defaultSBMultipleTypeID
  FROM gaming_settings gs1 
  JOIN gaming_settings gs2 ON gs2.name='IS_BONUS_ENABLED'
  JOIN gaming_settings gs3 ON gs3.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY'
  LEFT JOIN gaming_settings gs4 ON gs4.name='SPORTS_WAGER_DEFAULT_SELECTION_ID'
  LEFT JOIN gaming_settings gs5 ON gs5.name='SPORTS_WAGER_DEFAULT_MULTIPLE_TYPE_ID'
  WHERE gs1.name='PLAY_LIMIT_ENABLED';

  
  SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.session_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, 
    gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions,4,ggpCancel.amount_total,ggpCancel.game_play_id
  INTO sbBetID, gamePlayID, gameRoundID, sessionID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions,RoundTypeID,cancelAmount, cancelGamePlayerID
  FROM gaming_sb_bet_singles 
  JOIN gaming_sb_bets ON gaming_sb_bet_singles.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_singles.sb_bet_id
    AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1
  JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_singles.sb_selection_id=gaming_game_plays.sb_extra_id AND 
    gaming_game_plays.game_play_message_type_id=8 AND gaming_game_plays.payment_transaction_type_id=12
  JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
  JOIN gaming_game_plays AS ggpCancel ON ggpCancel.payment_transaction_type_id=20 AND ggpCancel.sb_bet_id = gaming_game_plays.sb_bet_id
  ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
  
  
  IF (gamePlayID=-1) THEN
    SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.session_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, 
      gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions,5,ggpCancel.amount_total,ggpCancel.game_play_id
    INTO sbBetID, gamePlayID, gameRoundID, sessionID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions,RoundTypeID,cancelAmount, cancelGamePlayerID
    FROM gaming_sb_bet_multiples 
    JOIN gaming_sb_bets ON gaming_sb_bet_multiples.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_multiples.sb_bet_id
      AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1 
    JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_multiples.sb_multiple_type_id=gaming_game_plays.sb_extra_id AND 
      gaming_game_plays.game_play_message_type_id=10 AND gaming_game_plays.payment_transaction_type_id=12
    JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
    JOIN gaming_game_plays AS ggpCancel ON ggpCancel.payment_transaction_type_id=20 AND ggpCancel.sb_bet_id = gaming_game_plays.sb_bet_id
    ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
  END IF;

  IF (gamePlayID=-1 OR cancelGamePlayerID = -1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SET betAmount = betTotal;
  SET statusCode=0;
  SET licenseType='sportsbook';

  SELECT gaming_sb_bets.game_manufacturer_id, cw_disable_bonus_money,use_free_bet
  INTO gameManufacturerID, disableBonusMoney,useFreeBet
  FROM gaming_sb_bets 
  JOIN gaming_game_manufacturers ON gaming_sb_bets.game_manufacturer_id = gaming_game_manufacturers.game_manufacturer_id
  WHERE sb_bet_id=sbBetID; 
  
  
  SELECT client_stat_id, client_id, currency_id, current_real_balance, current_bonus_balance,current_bonus_win_locked_balance, pending_bets_real, pending_bets_bonus
  INTO clientStatID, clientID, currencyID, balanceReal, balanceBonus,balanceWinLocked, pendingBetsReal, pendingBetsBonus 
  FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  
  SELECT country_id INTO countryID
  FROM clients_locations 
  WHERE clients_locations.client_id=clientID AND clients_locations.is_primary=1; 
  


 
  
  SET balaneFreeBetWinLocked=0;
  
  IF (disableBonusMoney OR bonusEnabledFlag=0) THEN
    SET balanceBonus=0;
    SET balanceWinLocked=0; 
    SET balanceFreeBet=0; 
    SET balaneFreeBetWinLocked=0;
  END IF;
  
  IF (useFreeBet) THEN
    SET balanceReal=0;
    SET balanceBonus=0;
    SET balanceWinLocked=0;
    SET balaneFreeBetWinLocked=0;
  ELSE
    SET balanceFreeBet=0;
  END IF;
  
  SET totalPlayerBalance = IF(disableBonusMoney=1, balanceReal, balanceReal+(balanceBonus+balanceWinLocked)+(balanceFreeBet+balaneFreeBetWinLocked));
  
 
 
 
      
  IF (statusCode!=0) THEN
    UPDATE gaming_sb_bets SET status_code=2, detailed_status_code=statusCode WHERE sb_bet_id=sbBetID;
    SELECT sb_bet_id, transaction_ref, gaming_sb_bets.status_code, gaming_sb_bets_statuses.status, timestamp, bet_total AS amount_total, amount_real, amount_bonus+amount_bonus_win_locked AS amount_bonus FROM gaming_sb_bets JOIN gaming_sb_bets_statuses ON gaming_sb_bets.status_code=gaming_sb_bets_statuses.status_code WHERE sb_bet_id=sbBetID;
    LEAVE root;
  END IF;    
      
  
  
  
  SET betRemain=betAmount;
    
  
  IF (disableBonusMoney=0) THEN
    IF (betRemain > 0) THEN
      IF (balanceFreeBet >= betRemain) THEN
        SET betFreeBet=ROUND(betRemain, 5);
        SET betRemain=0;
      ELSE
        SET betFreeBet=ROUND(balanceFreeBet, 5);
        SET betRemain=ROUND(betRemain-betFreeBet,0);
      END IF;
    END IF;
  END IF; 
  
  
  IF (betRemain > 0) THEN
    IF (balanceReal >= betRemain) THEN
      SET betReal=ROUND(betRemain, 5);
      SET betRemain=0;
    ELSE
      SET betReal=ROUND(balanceReal, 5);
      SET betRemain=ROUND(betRemain-betReal,0);
    END IF;
  END IF;
  IF (disableBonusMoney=0) THEN
    
    IF (betRemain > 0) THEN
      IF (balanceWinLocked >= betRemain) THEN
        SET betBonusWinLocked=ROUND(betRemain,5);
        SET betRemain=0;
      ELSE
        SET betBonusWinLocked=ROUND(balanceWinLocked,5);
        SET betRemain=ROUND(betRemain-betBonusWinLocked,0);
      END IF;
      
    END IF;
    
    IF (betRemain > 0) THEN
      IF (balanceBonus >= betRemain) THEN
        SET betBonus=ROUND(betRemain,5);
        SET betRemain=0;
      ELSE
        SET betBonus=ROUND(balanceBonus,5);
        SET betRemain=ROUND(betRemain-betBonus,0);
      END IF;
      
    END IF;
  END IF;
  
  
 
  
 

	SET betReal =betReal + betRemain;
  
  SET betBonus=betBonus+betFreeBet;
  SET betBonusWinLocked=betBonusWinLocked+betFreeBetWinLocked;
  IF (betBonus+betBonusWinLocked > 0) THEN
    SET @betBonusDeduct=betBonus;
    SET @betBonusDeductWinLocked=betBonusWinLocked;

	DELETE FROM gaming_sb_bets_bonuses WHERE sb_bet_id=sbBetID;

    INSERT INTO gaming_sb_bets_bonuses (sb_bet_id, bonus_instance_id, amount_bonus, amount_bonus_win_locked, amount_bonus_deduct, amount_bonus_win_locked_deduct)
    SELECT sbBetID, bonus_instance_id, 
      
      
      
     
      @betBonus:=IF(@betBonusDeduct>=bonus_amount_remaining, bonus_amount_remaining, @betBonusDeduct) AS bet_bonus,
      @betBonusWinLocked:=IF(@betBonusDeductWinLocked>=current_win_locked_amount,current_win_locked_amount,@betBonusDeductWinLocked) AS bet_bonus_win_locked,
      @betBonusDeduct:=GREATEST(0, @betBonusDeduct-bonus_amount_remaining) AS bonusDeductRemain, 
      @betBonusDeductWinLocked:=GREATEST(0, @betBonusDeductWinLocked-current_win_locked_amount) AS bonusWinLockedRemain
    FROM 
    (
      SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, IF(useFreeBet, 0, current_win_locked_amount) AS current_win_locked_amount, IF(useFreeBet, IF(gaming_bonus_types_awarding.name='FreeBet', bonus_amount_remaining, 0), IF(gaming_bonus_types_awarding.name='FreeBet', 0, bonus_amount_remaining)) AS bonus_amount_remaining
      FROM gaming_bonus_instances
      JOIN gaming_sb_bets_bonus_rules ON gaming_sb_bets_bonus_rules.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=gaming_sb_bets_bonus_rules.bonus_rule_id
      JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
      JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
      WHERE client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 
      ORDER BY gaming_bonus_types_awarding.order ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date DESC
    ) AS gaming_bonus_instances  
    HAVING bet_bonus > 0 OR bet_bonus_win_locked > 0;
    
    UPDATE gaming_bonus_instances 
    JOIN gaming_sb_bets_bonuses ON gaming_bonus_instances.bonus_instance_id=gaming_sb_bets_bonuses.bonus_instance_id
    SET bonus_amount_remaining=bonus_amount_remaining-amount_bonus, current_win_locked_amount=current_win_locked_amount-amount_bonus_win_locked
        
    WHERE gaming_sb_bets_bonuses.sb_bet_id=sbBetID;   
  END IF;

  
  IF (sbBetID=-1 OR clientStatID=-1) THEN
    SET statusCode=1;
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    LEAVE root;
  END IF;
  
  SELECT exchange_rate into exchangeRate FROM gaming_client_stats
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SET betAmountBase=ROUND(betAmount/exchangeRate, 5);
  SELECT client_wager_type_id INTO clientWagerTypeID FROM gaming_client_wager_types WHERE name='sb'; 


  
  
  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET total_real_played=total_real_played+betReal, 
      total_bonus_played=total_bonus_played+betBonus, 
      total_bonus_win_locked_played=total_bonus_win_locked_played+betBonusWinLocked, 
      gcs.total_real_played_base=gcs.total_real_played_base+(betReal/exchangeRate), gcs.total_bonus_played_base=gcs.total_bonus_played_base+((betBonus+betBonusWinLocked)/exchangeRate),
      last_played_date=NOW(), current_real_balance=current_real_balance-betReal, current_bonus_balance=current_bonus_balance-betBonus, current_bonus_win_locked_balance=current_bonus_win_locked_balance-betBonusWinLocked,
      
      gcss.total_bet=gcss.total_bet+betAmount,gcss.total_bet_base=gcss.total_bet_base+betAmountBase, gcss.bets=gcss.bets+numSingles+numMultiples, gcss.total_bet_real=gcss.total_bet_real+betReal, gcss.total_bet_bonus=gcss.total_bet_bonus+betBonus+betBonusWinLocked,
      
      gcws.num_bets=gcws.num_bets+numSingles+numMultiples, gcws.total_real_wagered=gcws.total_real_wagered+betReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered+betBonus+betBonusWinLocked,
      gcws.first_wagered_date=IFNULL(gcws.first_wagered_date, NOW()), gcws.last_wagered_date=NOW()
  WHERE gcs.client_stat_id = clientStatID;
  
  
  SET @betRealRemain=betReal;
  SET @betBonusRemain=betBonus;
  SET @betBonusWinLockedRemain=betBonusWinLocked;
  SET @paymentTransactionTypeID=12; 
  SET @betAmount=NULL;
  SET @transactionNum=0;
  
  INSERT INTO gaming_game_plays 
  (game_round_id, amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, pending_bet_real, pending_bet_bonus, currency_id, sign_mult, sb_bet_id,sb_extra_id, license_type_id,round_transaction_no,game_play_message_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gameRoundID,(betReal+betBonus+betBonusWinLocked), (betReal+betBonus+betBonusWinLocked)/exchangeRate, exchangeRate, betReal, betBonus, betBonusWinLocked, 0, 0, 0, NOW(), gameManufacturerID, clientID, clientStatID, gaming_payment_transaction_type.payment_transaction_type_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, pending_bets_real, pending_bets_bonus, currencyID, -1, sbBetID,sbExtraID, 3,cancelGGP.round_transaction_no+1,BetGGP.game_play_message_type_id,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_payment_transaction_type
  JOIN gaming_game_plays AS cancelGGP ON cancelGGP.game_play_id = cancelGamePlayerID
  JOIN gaming_game_plays AS BetGGP ON BetGGP.game_play_id = gamePlayID
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='UndoCancelBet' AND gaming_client_stats.client_stat_id=clientStatID;

  SET newGamePlayID = LAST_INSERT_ID();

  CALL GameUpdateRingFencedBalances(clientStatID,newGamePlayID);  
  
  INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount,transaction_ref,game_play_id,sb_extra_id) 
  SELECT sbBetID, sb_bet_transaction_type_id, NOW(), betAmount,transactionRef,newGamePlayID,sbExtraID
  FROM gaming_sb_bet_transaction_types WHERE name='UndoCancelBet';
  
  

    INSERT INTO gaming_game_rounds
   (bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked, num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, sb_bet_id, sb_extra_id, license_type_id) 
    SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, 1, 1, NOW(), gameManufacturerID, clientID, clientStatID, 1, RoundTypeID, currencyID, sb_bet_id, IFNULL(sbExtraID, defaultSBSelectionID), licenseTypeID 
    FROM gaming_game_plays WHERE game_play_id = newGamePlayID;

 
  
  
  
  IF (RoundTypeID=4) THEN
    
    
    SELECT sb_multiple_type_id INTO @singleMultTypeID FROM gaming_sb_multiple_types WHERE name='Single' AND game_manufacturer_id=gameManufacturerID; 
    
    INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units)
    SELECT gaming_game_plays.game_play_id, gaming_game_plays.payment_transaction_type_id, gaming_game_plays.amount_total, gaming_game_plays.amount_total_base, gaming_game_plays.amount_real, gaming_game_plays.amount_real/exchange_rate, gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/exchange_rate, gaming_game_plays.timestamp, gaming_game_plays.exchange_rate, gaming_game_plays.game_manufacturer_id, clientID, clientStatID, currencyID, countryID,
      gaming_game_plays.round_transaction_no, gaming_sb_sports.sb_sport_id, gaming_sb_regions.sb_region_id, gaming_sb_groups.sb_group_id, gaming_sb_events.sb_event_id, gaming_sb_markets.sb_market_id, gaming_sb_selections.sb_selection_id, gaming_game_plays.sb_bet_id, @singleMultTypeID, liveBetType, deviceType, 1
    FROM gaming_game_plays
    JOIN gaming_sb_selections ON gaming_game_plays.sb_extra_id=gaming_sb_selections.sb_selection_id
    JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    JOIN gaming_sb_events ON gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_groups ON gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    JOIN gaming_sb_regions ON gaming_sb_groups.sb_region_id=gaming_sb_regions.sb_region_id
    JOIN gaming_sb_sports ON gaming_sb_regions.sb_sport_id=gaming_sb_sports.sb_sport_id
    WHERE gaming_game_plays.game_play_id=newGamePlayID;
 
  END IF;
  
  IF (RoundTypeID=5) THEN
  
    INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, units)
    SELECT gaming_game_plays.game_play_id, gaming_game_plays.payment_transaction_type_id, gaming_game_plays.amount_total/bet_multiple.num_singles, gaming_game_plays.amount_total_base/bet_multiple.num_singles, gaming_game_plays.amount_real/bet_multiple.num_singles, (gaming_game_plays.amount_real/exchange_rate)/bet_multiple.num_singles, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/bet_multiple.num_singles, ((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/exchange_rate)/bet_multiple.num_singles, 
      gaming_game_plays.timestamp, gaming_game_plays.exchange_rate, gaming_game_plays.game_manufacturer_id, clientID, clientStatID, currencyID, countryID, 
      gaming_game_plays.round_transaction_no, gaming_sb_sports.sb_sport_id, gaming_sb_regions.sb_region_id, gaming_sb_groups.sb_group_id, gaming_sb_events.sb_event_id, gaming_sb_markets.sb_market_id, gaming_sb_selections.sb_selection_id, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, liveBetType, 1/bet_multiple.num_singles
    FROM gaming_game_plays
    JOIN gaming_sb_bet_multiples AS bet_multiple ON gaming_game_plays.sb_bet_id=bet_multiple.sb_bet_id AND gaming_game_plays.sb_extra_id=bet_multiple.sb_multiple_type_id
    JOIN gaming_sb_bet_multiples_singles AS mult_singles ON bet_multiple.sb_bet_multiple_id=mult_singles.sb_bet_multiple_id
    JOIN gaming_sb_selections ON IFNULL(mult_singles.sb_selection_id,defaultSBSelectionID)=gaming_sb_selections.sb_selection_id
    JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    JOIN gaming_sb_events ON gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_groups ON gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    JOIN gaming_sb_regions ON gaming_sb_groups.sb_region_id=gaming_sb_regions.sb_region_id
    JOIN gaming_sb_sports ON gaming_sb_regions.sb_sport_id=gaming_sb_sports.sb_sport_id
    WHERE gaming_game_plays.game_play_id=newGamePlayID;
    
  END IF;
  
  IF (bonusEnabledFlag AND betAmount>0) THEN

    
      SET @transferBonusMoneyFlag=1;
    
      
      
      SET @betBonusDeductWagerRequirement=betAmount; 
      SET @wager_requirement_non_weighted=0;
      SET @wager_requirement_contribution=0;
      
      SET @betRealDeduct=betReal*2;
      SET @betBonusDeduct=0;
      SET @betBonusDeductWinLocked=0; 
      
      SET @betBonus=0;
      SET @betBonusWinLocked=0;
      SET @nowWagerReqMet=0;
      SET @hasReleaseBonus=0;
      
      
      INSERT INTO gaming_game_plays_bonus_instances (sb_bet_id, game_play_id, bonus_instance_id, client_stat_id, timestamp, bonus_rule_id, exchange_rate, 
        bet_real, bet_bonus, bet_bonus_win_locked, bonus_deduct, bonus_deduct_win_locked, wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_deduct_wager_requirement, bonus_wager_requirement_remain_after)
      SELECT sbBetID, newGamePlayID, gaming_bonus_instances.bonus_instance_id, clientStatID, NOW(), gaming_bonus_instances.bonus_rule_id, exchangeRate,
        @betRealDeduct:=GREATEST(0, @betRealDeduct-betReal) AS bet_real,
        @betBonus:=IFNULL(gaming_sb_bets_bonuses.amount_bonus,0) AS bet_bonus,
        @betBonusWinLocked:=IFNULL(gaming_sb_bets_bonuses.amount_bonus_win_locked,0) AS bet_bonus_win_locked,
        @betBonusDeduct:=0 AS bonusDeductRemain, 
        @betBonusDeductWinLocked:=0 AS bonusWinLockedRemain,
        
        
        @wager_requirement_non_weighted:=IF(ROUND(@betBonusDeductWagerRequirement*IFNULL(sb_bonus_rules.weight, 0), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, @betBonusDeductWagerRequirement) AS wager_requirement_non_weighted, 
        @wager_requirement_contribution:=IF(ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,100000000*100),@betBonusDeductWagerRequirement)*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,1000000*100),@betBonusDeductWagerRequirement)*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)) AS wager_requirement_contribution,
        @wager_requirement_contribution:=LEAST(IFNULL(wgr_restrictions.max_wager_contibution,100000000*100), IF(wager_req_real_only OR bonusReqContributeRealOnly, ROUND(GREATEST(@wager_requirement_contribution-(IFNULL(IFNULL(gaming_sb_bets_bonuses.amount_bonus,0)+IFNULL(gaming_sb_bets_bonuses.amount_bonus_win_locked,0),0)*IFNULL(sb_bonus_rules.weight,0)*IFNULL(license_weight_mod, 1)),0), 5), @wager_requirement_contribution)), 
        
        @nowWagerReqMet:=IF (bonus_wager_requirement_remain-@wager_requirement_contribution<=0,1,0) AS now_wager_requirement_met,
        IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wager_requirement_contribution)>=
          ((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,
        
        @betBonusDeductWagerRequirement:=GREATEST(0, ROUND(@betBonusDeductWagerRequirement-@wager_requirement_non_weighted, 5)) AS wagerRequirementRemain 
        , bonus_wager_requirement_remain-@wager_requirement_contribution AS bonus_wager_requirement_remain_after
      FROM 
      (
        SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, current_win_locked_amount, bonus_amount_remaining, bonus_wager_requirement_remain, IFNULL(gaming_bonus_rules.sportsbook_weight_mod, 1) AS license_weight_mod,
          bonus_amount_given, bonus_wager_requirement, gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus
        FROM gaming_bonus_instances
        JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
        JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
        LEFT JOIN gaming_sb_bets_bonuses ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_sb_bets_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
        WHERE gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 
        ORDER BY gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date DESC, gaming_bonus_instances.bonus_instance_id DESC
      ) AS gaming_bonus_instances  
      JOIN gaming_sb_bets_bonus_rules AS sb_bonus_rules ON sb_bonus_rules.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=sb_bonus_rules.bonus_rule_id  
      LEFT JOIN gaming_sb_bets_bonuses ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_sb_bets_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
      LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_instances.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID
      HAVING wager_requirement_contribution > 0 OR bet_bonus > 0 OR bet_bonus_win_locked > 0;
      

        UPDATE gaming_bonus_instances 
        JOIN gaming_game_plays_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
        SET
            
            bonus_wager_requirement_remain=bonus_wager_requirement_remain-wager_requirement_contribution,
            
            is_secured=IF(now_wager_requirement_met=1,1,is_secured), secured_date=IF(now_wager_requirement_met=1,NOW(),NULL),
            gaming_bonus_instances.is_active=IF(is_active=0,0,IF(0 OR (now_wager_requirement_met=1 AND @transferBonusMoneyFlag=1),0,1)) 
        WHERE gaming_game_plays_bonus_instances.game_play_id=newGamePlayID;           
    
        
        
        UPDATE gaming_game_plays_bonus_instances AS ggpbi  
        JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
        JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
        SET 
            ggpbi.bonus_transfered_total=(CASE transfer_type.name
              WHEN 'All' THEN bonus_amount_remaining+current_win_locked_amount
              WHEN 'Bonus' THEN bonus_amount_remaining
              WHEN 'BonusWinLocked' THEN current_win_locked_amount
              WHEN 'UpToBonusAmount' THEN LEAST(bonus_amount_given, bonus_amount_remaining+current_win_locked_amount)
              WHEN 'UpToPercentage' THEN LEAST(bonus_amount_given*transfer_upto_percentage, bonus_amount_remaining+current_win_locked_amount)
              WHEN 'ReleaseBonus' THEN LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, bonus_amount_remaining+current_win_locked_amount)
              WHEN 'ReleaseAllBonus' THEN bonus_amount_remaining+current_win_locked_amount
              ELSE 0
            END),
            ggpbi.bonus_transfered=IF(transfer_type.name='BonusWinLocked', 0, LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining)),
            ggpbi.bonus_win_locked_transfered=IF(transfer_type.name='Bonus', 0, ggpbi.bonus_transfered_total-ggpbi.bonus_transfered),
            ggpbi.bonus_transfered_lost=bonus_amount_remaining-ggpbi.bonus_transfered,
            ggpbi.bonus_win_locked_transfered_lost=current_win_locked_amount-bonus_win_locked_transfered,
            bonus_amount_remaining=0,current_win_locked_amount=0,  current_ring_fenced_amount=0,  
            gaming_bonus_instances.bonus_transfered_total=gaming_bonus_instances.bonus_transfered_total+ggpbi.bonus_transfered_total,
            gaming_bonus_instances.session_id=sessionID
        WHERE ggpbi.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;
      
        
        SET @requireTransfer=0;
        SET @bonusTransfered=0;
        SET @bonusWinLockedTransfered=0;
        SET @bonusTransferedLost=0;
        SET @bonusWinLockedTransferedLost=0;

		SET @ringFencedAmount=0;
		SET @ringFencedAmountSB=0;
		SET @ringFencedAmountCasino=0;
		SET @ringFencedAmountPoker=0;
        
        SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0)  ,
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
        INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
        FROM gaming_game_plays_bonus_instances
		LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id	
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;
        
        SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
        SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
        IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
          CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
        END IF; 
        
        
        UPDATE gaming_game_plays_bonus_instances AS ggpbi 
        JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id
        JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        JOIN gaming_bonus_types_transfers AS transfer_type ON 
          gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id AND transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus')
        SET 
            ggpbi.bonus_transfered_total=LEAST(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))* 
              gaming_bonus_instances.transfer_every_amount, 
              bonus_amount_remaining+current_win_locked_amount), 
            ggpbi.bonus_transfered=LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining),
            ggpbi.bonus_win_locked_transfered=ggpbi.bonus_transfered_total-ggpbi.bonus_transfered,
            bonus_amount_remaining=bonus_amount_remaining-bonus_transfered, current_win_locked_amount=current_win_locked_amount-bonus_win_locked_transfered,  
            gaming_bonus_instances.transfer_every_x_last=gaming_bonus_instances.transfer_every_x_last+(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))*gaming_bonus_instances.transfer_every_x),
            gaming_bonus_instances.bonus_transfered_total=IFNULL(gaming_bonus_instances.bonus_transfered_total,0)+ggpbi.bonus_transfered_total,
            gaming_bonus_instances.session_id=sessionID
        WHERE ggpbi.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;
        
        SET @requireTransfer=0;
        SET @bonusTransfered=0;
        SET @bonusWinLockedTransfered=0;
        SET @bonusTransferedLost=0;
        SET @bonusWinLockedTransferedLost=0;

		SET @ringFencedAmount=0;
		SET @ringFencedAmountSB=0;
		SET @ringFencedAmountCasino=0;
		SET @ringFencedAmountPoker=0;
        
        SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0)  ,
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
        INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
        FROM gaming_game_plays_bonus_instances
		LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id	
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

        SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
        SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
        IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
          CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
        END IF; 
      END IF; 
      
  
  
  IF (playLimitEnabled) THEN 
    CALL PlayLimitsUpdate(clientStatID, licenseType, betAmount, 1);
  END IF;

  IF (canCommit) THEN COMMIT AND CHAIN; END IF;
  
  CALL CommonWalletSBReturnTransactionData(newGamePlayID, sbBetID, sbExtraID, 'Bet', clientStatID);
  SET statusCode=0;
  
END root$$

DELIMITER ;

