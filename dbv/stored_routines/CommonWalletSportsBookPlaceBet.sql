DROP procedure IF EXISTS `CommonWalletSportsBookPlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsBookPlaceBet`(gameManufacturerName VARCHAR(20), transactionRef VARCHAR(40), sessionID BIGINT, clientStatID BIGINT, canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  DECLARE gameManufacturerID BIGINT DEFAULT -1;
  DECLARE gamePlayID, sbBetID, clientID, gameRoundID, currencyID, clientWagerTypeID, countryID BIGINT DEFAULT -1;
  DECLARE isAlreadyProcessed, playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly TINYINT(1) DEFAULT 0;
  DECLARE numSingles, numMultiplies, sbBetStatusCode INT DEFAULT 0;
  DECLARE betAmount, betReal, betBonus, betBonusWinLocked DECIMAL(18,5) DEFAULT 0;
  DECLARE balanceReal, balanceBonus, balanceWinLocked, betRemain, exchangeRate, betAmountBase, sbOdd DECIMAL(18, 5) DEFAULT 0;
  DECLARE roundType, licenseType VARCHAR(20) DEFAULT NULL;
  SET statusCode=0;
  SET roundType='Sports';
  SET licenseType='sportsbook';
  SELECT game_manufacturer_id INTO gameManufacturerID FROM gaming_game_manufacturers WHERE name=gameManufacturerName;
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3
  INTO playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly
  FROM gaming_settings gs1 
  JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
  JOIN gaming_settings gs3 ON (gs3.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY')
  WHERE gs1.name='PLAY_LIMIT_ENABLED';
  SELECT client_stat_id, client_id, currency_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance 
  INTO clientStatID, clientID, currencyID, balanceReal, balanceBonus 
  FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  SELECT country_id INTO countryID
  FROM clients_locations 
  WHERE clients_locations.client_id=clientID AND clients_locations.is_primary=1; 
  SELECT sb_bet_id, client_stat_id, transaction_ref, bet_total, num_singles, num_multiplies, status_code, amount_real, amount_bonus, amount_bonus_win_locked
  INTO sbBetID, clientStatID, transactionRef, betAmount, numSingles, numMultiplies, sbBetStatusCode, betReal, betBonus, betBonusWinlocked
  FROM gaming_sb_bets WHERE transaction_ref=transactionRef AND game_manufacturer_id=gameManufacturerID;
  
  IF (sbBetID=-1 OR clientStatID=-1) THEN
    SET statusCode=1;
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    LEAVE root;
  END IF;
  
  IF (sbBetStatusCode NOT IN (3,6)) THEN 
    SET statusCode=2;
    CALL CommonWalletSBReturnData(sbBetID, clientStatID); 
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
      last_played_date=NOW(), 
      
      gcss.total_bet=gcss.total_bet+betAmount,gcss.total_bet_base=gcss.total_bet_base+betAmountBase, gcss.bets=gcss.bets+numSingles+numMultiplies, gcss.total_bet_real=gcss.total_bet_real+betReal, gcss.total_bet_bonus=gcss.total_bet_bonus+betBonus+betBonusWinLocked,
      
      gcws.num_bets=gcws.num_bets+numSingles+numMultiplies, gcws.total_real_wagered=gcws.total_real_wagered+betReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered+betBonus+betBonusWinLocked,
      gcws.first_wagered_date=IFNULL(gcws.first_wagered_date, NOW()), gcws.last_wagered_date=NOW()
  WHERE gcs.client_stat_id = clientStatID;
  
  
  INSERT INTO gaming_game_rounds
  (bet_total, bet_total_base, bet_real, bet_bonus, bet_bonus_win_locked, num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, sb_bet_id) 
  SELECT betAmount, betAmountBase, betReal, betBonus, betBonusWinLocked, numSingles+numMultiplies, numSingles+numMultiplies, NOW(), gameManufacturerID, clientID, clientStatID, 0, gaming_game_round_types.game_round_type_id, currencyID, sbBetID 
  FROM gaming_game_round_types
  WHERE gaming_game_round_types.name=roundType;
  
  SET gameRoundID=LAST_INSERT_ID();
  
  SET @betRealRemain=betReal;
  SET @betBonusRemain=betBonus;
  SET @betBonusWinLockedRemain=betBonusWinLocked;
  SET @paymentTransactionTypeID=12; 
  SET @betAmount=NULL;
  SET gamePlayID=NULL;
  IF (numSingles>0) THEN
    SELECT sb_multiple_type_id INTO @singleMultTypeID FROM gaming_sb_multiple_types WHERE name='Single' AND game_manufacturer_id=gameManufacturerID; 
  
    INSERT INTO gaming_game_plays 
    (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, is_win_placed, is_processed, currency_id, game_play_message_type_id, sign_mult, timestamp_hourly, sb_extra_id, sb_bet_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
    SELECT bet_amount, ROUND(bet_amount/exchangeRate,5), exchangeRate, bet_real, bet_bonus, bet_bonus_win_locked, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gameRoundID, @paymentTransactionTypeID, balanceReal, balanceBonus, 0, 0, currencyID, game_play_message_type_id, -1, DATE_FORMAT(NOW(), '%Y-%m-%d %H:00'), sb_selection_id, sbBetID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`) 
    FROM
    (
      SELECT gaming_sb_bet_singles.sb_selection_id,client_stat_id, @betAmountRemain:=bet_amount AS bet_amount, 
        @betReal:=LEAST(@betRealRemain, @betAmountRemain) AS bet_real, @betAmountRemain:=@betAmountRemain-@betReal,
        @betBonus:=LEAST(@betBonusRemain, @betAmountRemain) AS bet_bonus, @betAmountRemain:=@betAmountRemain-@betBonus,
        @betBonusWinLocked:=LEAST(@betBonusWinLockedRemain, @betAmountRemain) AS bet_bonus_win_locked, @betAmountRemain:=@betAmountRemain-@betBonusWinLocked,
        @betRealRemain:=@betRealRemain-@betReal, @betBonusRemain:=@betBonusRemain-@betBonus, @betBonusWinLockedRemain:=@betBonusWinLockedRemain-@betBonusWinLocked
      FROM gaming_sb_bet_singles
      WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID
    ) AS XX
    LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=('SportsBet' COLLATE utf8_general_ci)
	JOIN gaming_client_stats ON XX.client_stat_id = gaming_client_stats.client_stat_id;

    SET gamePlayID=LAST_INSERT_ID();

	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);  
    
    INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, units)
    SELECT gaming_game_plays.game_play_id, gaming_game_plays.payment_transaction_type_id, gaming_game_plays.amount_total, gaming_game_plays.amount_total_base, gaming_game_plays.amount_real, gaming_game_plays.amount_real*exchange_rate, gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*exchange_rate, gaming_game_plays.timestamp, gaming_game_plays.exchange_rate, gaming_game_plays.game_manufacturer_id, clientID, clientStatID, currencyID, countryID,
      gaming_game_plays.round_transaction_no, gaming_sb_sports.sb_sport_id, gaming_sb_regions.sb_region_id, gaming_sb_groups.sb_group_id, gaming_sb_events.sb_event_id, gaming_sb_markets.sb_market_id, gaming_sb_selections.sb_selection_id, gaming_game_plays.sb_bet_id, @singleMultTypeID, 1
    FROM gaming_game_plays
    JOIN gaming_sb_selections ON gaming_game_plays.sb_extra_id=gaming_sb_selections.sb_selection_id
    JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    JOIN gaming_sb_events ON gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_groups ON gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    JOIN gaming_sb_regions ON gaming_sb_groups.sb_region_id=gaming_sb_regions.sb_region_id
    JOIN gaming_sb_sports ON gaming_sb_regions.sb_sport_id=gaming_sb_sports.sb_sport_id
    WHERE gaming_game_plays.sb_bet_id=sbBetID AND gaming_game_plays.game_play_message_type_id=8; 
 
  END IF;
  
  IF (numMultiplies>0) THEN
    INSERT INTO gaming_game_plays 
    (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, is_win_placed, is_processed, currency_id, game_play_message_type_id, sign_mult, timestamp_hourly, sb_extra_id, sb_bet_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
    SELECT bet_amount, ROUND(bet_amount/exchangeRate,5), exchangeRate, bet_real, bet_bonus, bet_bonus_win_locked, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gameRoundID, @paymentTransactionTypeID, balanceReal, balanceBonus, 0, 0, currencyID, game_play_message_type_id, -1, DATE_FORMAT(NOW(), '%Y-%m-%d %H:00'), sb_multiple_type_id, sbBetID,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`) 
    FROM
    (
      SELECT gaming_sb_bet_multiples.sb_multiple_type_id, client_stat_id, @betAmountRemain:=bet_amount AS bet_amount, 
        @betReal:=LEAST(@betRealRemain, @betAmountRemain) AS bet_real, @betAmountRemain:=@betAmountRemain-@betReal,
        @betBonus:=LEAST(@betBonusRemain, @betAmountRemain) AS bet_bonus, @betAmountRemain:=@betAmountRemain-@betBonus,
        @betBonusWinLocked:=LEAST(@betBonusWinLockedRemain, @betAmountRemain) AS bet_bonus_win_locked, @betAmountRemain:=@betAmountRemain-@betBonusWinLocked,
        @betRealRemain:=@betRealRemain-@betReal, @betBonusRemain:=@betBonusRemain-@betBonus, @betBonusWinLockedRemain:=@betBonusWinLockedRemain-@betBonusWinLocked
      FROM gaming_sb_bet_multiples
      LEFT JOIN gaming_sb_multiple_types ON gaming_sb_bet_multiples.sb_multiple_type_id=gaming_sb_multiple_types.sb_multiple_type_id
      WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID
    ) AS XX
    LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=('SportsBetMult' COLLATE utf8_general_ci)
	JOIN gaming_client_stats ON XX.client_stat_id = gaming_client_stats.client_stat_id;

    SET gamePlayID=LAST_INSERT_ID();
	
	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);  
    
    INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, units)
    SELECT gaming_game_plays.game_play_id, gaming_game_plays.payment_transaction_type_id, gaming_game_plays.amount_total/bet_multiple.num_singles, gaming_game_plays.amount_total_base/bet_multiple.num_singles, gaming_game_plays.amount_real/bet_multiple.num_singles, gaming_game_plays.amount_real*exchange_rate/bet_multiple.num_singles, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/bet_multiple.num_singles, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*exchange_rate/bet_multiple.num_singles, 
      gaming_game_plays.timestamp, gaming_game_plays.exchange_rate, gaming_game_plays.game_manufacturer_id, clientID, clientStatID, currencyID, countryID, 
      gaming_game_plays.round_transaction_no, gaming_sb_sports.sb_sport_id, gaming_sb_regions.sb_region_id, gaming_sb_groups.sb_group_id, gaming_sb_events.sb_event_id, gaming_sb_markets.sb_market_id, gaming_sb_selections.sb_selection_id, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, 1/bet_multiple.num_singles
    FROM gaming_game_plays
    JOIN gaming_sb_bet_multiples AS bet_multiple ON gaming_game_plays.sb_bet_id=bet_multiple.sb_bet_id AND gaming_game_plays.sb_extra_id=bet_multiple.sb_multiple_type_id
    JOIN gaming_sb_bet_multiples_singles AS mult_singles ON bet_multiple.sb_bet_multiple_id=mult_singles.sb_bet_multiple_id
    JOIN gaming_sb_selections ON mult_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
    JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    JOIN gaming_sb_events ON gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_groups ON gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    JOIN gaming_sb_regions ON gaming_sb_groups.sb_region_id=gaming_sb_regions.sb_region_id
    JOIN gaming_sb_sports ON gaming_sb_regions.sb_sport_id=gaming_sb_sports.sb_sport_id
    WHERE gaming_game_plays.sb_bet_id=sbBetID AND gaming_game_plays.game_play_message_type_id=10; 
  END IF;
  
  IF (bonusEnabledFlag AND betAmount>0) THEN
    SET @transferBonusMoneyFlag=1;
    
    
    
    SET @betBonusDeductWagerRequirement=betAmount; 
    SET @wager_requirement_non_weighted=0;
    SET @wager_requirement_contribution=0;
    SET @betBonus=0;
    SET @betBonusWinLocked=0;
    SET @nowWagerReqMet=0;
    SET @hasReleaseBonus=0;
    
    
    
    INSERT INTO gaming_game_plays_bonus_instances (sb_bet_id, game_play_id, bonus_instance_id, client_stat_id, bet_bonus, bet_bonus_win_locked,
      bonus_deduct, bonus_deduct_win_locked, wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_deduct_wager_requirement, bonus_wager_requirement_remain_after)
    SELECT sbBetID, gamePlayID, gaming_bonus_instances.bonus_instance_id, clientStatID,
      
      
      
      
      IFNULL(gaming_sb_bets_bonuses.amount_bonus, 0) AS bet_bonus, IFNULL(gaming_sb_bets_bonuses.amount_bonus_win_locked, 0) AS bet_bonus_win_locked, 
      0, 0,
      
      @wager_requirement_non_weighted:=IF(ROUND(@betBonusDeductWagerRequirement*IFNULL(sb_bonus_rules.weight, 0), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, @betBonusDeductWagerRequirement) AS wager_requirement_non_weighted, 
      @wager_requirement_contribution:=IF(ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,100000000*100),@betBonusDeductWagerRequirement)*IFNULL(sb_bonus_rules.weight, 0), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,1000000*100),@betBonusDeductWagerRequirement)*IFNULL(sb_bonus_rules.weight, 0), 5)) AS wager_requirement_contribution,
      @wager_requirement_contribution:=LEAST(IFNULL(wgr_restrictions.max_wager_contibution,100000000*100), IF(wager_req_real_only OR bonusReqContributeRealOnly, ROUND(GREATEST(@wager_requirement_contribution-(IFNULL(gaming_sb_bets_bonuses.amount_bonus+gaming_sb_bets_bonuses.amount_bonus_win_locked,0)*IFNULL(sb_bonus_rules.weight,0)),0), 5), @wager_requirement_contribution)), 
      
      @nowWagerReqMet:=IF (bonus_wager_requirement_remain-@wager_requirement_contribution<=0,1,0) AS now_wager_requirement_met,
      IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wager_requirement_contribution)>=
        ((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,
      
      @betBonusDeductWagerRequirement:=GREATEST(0, ROUND(@betBonusDeductWagerRequirement-@wager_requirement_non_weighted, 5)) AS wagerRequirementRemain 
      , bonus_wager_requirement_remain-@wager_requirement_contribution AS bonus_wager_requirement_remain_after
    FROM 
    (
      SELECT bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, current_win_locked_amount,  bonus_amount_remaining, bonus_wager_requirement_remain, 
        bonus_amount_given, bonus_wager_requirement, gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus
      FROM gaming_bonus_instances
      JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
      JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
      JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
      WHERE client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 
      ORDER BY gaming_bonus_types_awarding.order ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date DESC
    ) AS gaming_bonus_instances  
    JOIN gaming_sb_bets_bonus_rules AS sb_bonus_rules ON sb_bonus_rules.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=sb_bonus_rules.bonus_rule_id  
    LEFT JOIN gaming_sb_bets_bonuses ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_sb_bets_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
    LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_instances.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID
    HAVING wager_requirement_contribution > 0 OR bet_bonus > 0 OR bet_bonus_win_locked > 0;
    
    IF (ROW_COUNT() > 0) THEN
      
      
      UPDATE gaming_bonus_instances 
      JOIN gaming_game_plays_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
      SET 
          bonus_wager_requirement_remain=bonus_wager_requirement_remain-wager_requirement_contribution,
          
          is_secured=IF(now_wager_requirement_met=1,1,is_secured), secured_date=IF(now_wager_requirement_met=1,NOW(),NULL),
          gaming_bonus_instances.is_active=IF(is_active=0,0,IF(now_used_all=1 OR (now_wager_requirement_met=1 AND @transferBonusMoneyFlag=1),0,1))
      WHERE gaming_game_plays_bonus_instances.sb_bet_id=sbBetID;           
  
      
      
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
          bonus_transfered_lost=bonus_amount_remaining-bonus_transfered,
          bonus_win_locked_transfered_lost=current_win_locked_amount-bonus_win_locked_transfered,
          bonus_amount_remaining=0,current_win_locked_amount=0,  
          gaming_bonus_instances.bonus_transfered_total=gaming_bonus_instances.bonus_transfered_total+ggpbi.bonus_transfered_total,
          gaming_bonus_instances.session_id=sessionID
      WHERE ggpbi.sb_bet_id=sbBetID AND now_wager_requirement_met=1 AND now_used_all=0;
    
      
      SET @requireTransfer=0;
      SET @bonusTransfered=0;
      SET @bonusWinLockedTransfered=0;
      SET @bonusTransferedLost=0;
      SET @bonusWinLockedTransferedLost=0;
      
      SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0)  
      INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost
      FROM gaming_game_plays_bonus_instances
      WHERE gaming_game_plays_bonus_instances.sb_bet_id=sbBetID AND now_wager_requirement_met=1 AND now_used_all=0;
      SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
      IF (@requireTransfer=1 AND @bonusTransferedTotal>0) THEN
        CALL PlaceBetBonusCashExchangeSB(clientStatID, sbBetID, gamePlayID, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost);
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
      WHERE ggpbi.sb_bet_id=sbBetID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;
      
      SET @requireTransfer=0;
      SET @bonusTransfered=0;
      SET @bonusWinLockedTransfered=0;
      SET @bonusTransferedLost=0;
      SET @bonusWinLockedTransferedLost=0;
      
      SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0)  
      INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost
      FROM gaming_game_plays_bonus_instances
      WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;
      SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
      IF (@requireTransfer=1 AND @bonusTransferedTotal>0) THEN
        CALL PlaceBetBonusCashExchangeSB(clientStatID, sbBetID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost);
      END IF; 
    
    END IF; 
  END IF;
 
  
  UPDATE gaming_sb_bets SET is_processed=1, status_code=5 WHERE sb_bet_id=sbBetID;
  
  
  IF (playLimitEnabled) THEN 
    CALL PlayLimitsUpdate(clientStatID, licenseType, betAmount, 1);
  END IF;
  
  CALL CommonWalletSBReturnData(sbBetID, clientStatID);
  IF (canCommit) THEN COMMIT AND CHAIN; END IF;
END root$$

DELIMITER ;

