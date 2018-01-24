-- -------------------------------------
-- PlaceSBBet.sql
-- -------------------------------------

DROP procedure IF EXISTS `PlaceSBBet`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceSBBet`(sbBetID BIGINT, ignorePlayLimit TINYINT(1), ignoreSessionExpiry TINYINT(1), OUT statusCode INT)
root:BEGIN  
 
  DECLARE betAmount, totalPlayerBalance, betReal, betFreeBet, betFreeBetWinLocked, betBonus, betBonusWinLocked DECIMAL(18, 5) DEFAULT 0;
  DECLARE balanceReal, balanceFreeBet, balaneFreeBetWinLocked, balanceBonus, balanceWinLocked, betRemain, exchangeRate, betTotalBase, sbOdd DECIMAL(18, 5) DEFAULT 0;
  DECLARE sessionID, clientStatID, clientStatIDStat, clientStatIDCheck, clientID, gamePlayID, currencyID, gameManufacturerID, fraudClientEventID, gameRoundID, gameSessionID BIGINT DEFAULT -1;
  DECLARE playLimitEnabled, isLimitExceeded, bonusEnabledFlag, disableBonusMoney, isAccountClosed, fraudEnabled, disallowPlay, isPlayAllowed TINYINT(1) DEFAULT 0;
  DECLARE bonusReqContributeRealOnly, bonusMismatch, isSessionOpen, noMoreRecords TINYINT(1) DEFAULT 0;
  DECLARE roundType, licenseType VARCHAR(20) DEFAULT NULL;
  DECLARE clientWagerTypeID, sessionStatusCode INT DEFAULT -1;
  DECLARE sbBetSingleID, sbSelectionID BIGINT DEFAULT -1;
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
   
  DECLARE betSinglesCursor CURSOR FOR 
    SELECT sb_bet_single_id, sb_selection_id, bet_amount, odd
    FROM gaming_sb_bet_singles WHERE sb_bet_id=sbBetID;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
    
  SET roundType='Sports';
  SET licenseType='sportsbook';
  SET gameSessionID = NULL;
  
  SELECT client_stat_id, bet_total, gaming_sb_bets.game_manufacturer_id, cw_disable_bonus_money 
  INTO clientStatID, betAmount, gameManufacturerID, disableBonusMoney
  FROM gaming_sb_bets 
  JOIN gaming_game_manufacturers ON gaming_sb_bets.game_manufacturer_id = gaming_game_manufacturers.game_manufacturer_id
  WHERE sb_bet_id=sbBetID;    
  
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, gs4.value_bool as vb4
    INTO playLimitEnabled, bonusEnabledFlag, fraudEnabled, bonusReqContributeRealOnly
    FROM gaming_settings gs1 
    JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
    JOIN gaming_settings gs3 ON (gs3.name='FRAUD_ENABLED')
    JOIN gaming_settings gs4 ON (gs4.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
  SELECT client_stat_id, gaming_client_stats.client_id, currency_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance
  INTO clientStatIDCheck, clientID, currencyID, balanceReal, balanceBonus, balanceWinLocked   
  FROM gaming_client_stats
  WHERE gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1 
  FOR UPDATE;
  
  SELECT gaming_clients.is_account_closed OR gaming_fraud_rule_client_settings.block_account, gaming_clients.is_play_allowed AND !gaming_fraud_rule_client_settings.block_gameplay, sessions_main.session_id, sessions_main.status_code 
  INTO isAccountClosed, isPlayAllowed, sessionID, sessionStatusCode
  FROM gaming_clients
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
  JOIN sessions_main ON sessions_main.extra_id=gaming_clients.client_id AND sessions_main.is_latest
  WHERE gaming_clients.client_id=clientID;
    
  SELECT client_wager_type_id INTO clientWagerTypeID
  FROM gaming_client_wager_types
  WHERE name='sb'; 
  
  if (clientStatIDCheck=-1 OR isAccountClosed=1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (isPlayAllowed=0 AND ignorePlayLimit=0) THEN 
    SET statusCode=6; 
    LEAVE root;
  END IF;  
  
  SET balanceWinLocked=balanceWinLocked+balaneFreeBetWinLocked; 
  SET balaneFreeBetWinLocked=0;
  IF (disableBonusMoney OR bonusEnabledFlag=0) THEN
    SET balanceBonus=0;
    SET balanceWinLocked=0; 
    SET balanceFreeBet=0; 
    SET balaneFreeBetWinLocked=0;
  END IF;
  
  IF (ignoreSessionExpiry=0 AND sessionStatusCode!=1) THEN
    SET statusCode=7;
    LEAVE root;
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
  IF (roundType='Sports') THEN
    
    SET totalPlayerBalance = IF(disableBonusMoney=1, balanceReal, balanceReal+(balanceBonus+balanceWinLocked)+(balanceFreeBet+balaneFreeBetWinLocked));
    
    IF (totalPlayerBalance < betAmount) THEN 
      SET statusCode=4;
      LEAVE root;
    END IF;
     
    IF (playLimitEnabled AND ignorePlayLimit=0) THEN 
      SET isLimitExceeded=PlayLimitCheckExceeded(betAmount, sessionID, clientStatID, licenseType);
      IF (isLimitExceeded>0) THEN
        SET statusCode=5;
        LEAVE root;
      END IF;
    END IF;
    
  END IF;
   
  IF (roundType='Sports') THEN
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
    
    IF (betRemain > 0) THEN
      SET statusCode=4;
      LEAVE root;
    END IF;
    
    SET betBonus=betBonus+betFreeBet;
    SET betBonusWinLocked=betBonusWinLocked+betFreeBetWinLocked;
     
    SELECT exchange_rate into exchangeRate 
    FROM gaming_client_stats
    JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
    WHERE gaming_client_stats.client_stat_id=clientStatID;
    
    SET betTotalBase=ROUND(betAmount/exchangeRate,5);  
    
    UPDATE gaming_client_stats AS gcs
    LEFT JOIN gaming_game_sessions AS ggs ON ggs.game_session_id=gameSessionID
    LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
    LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
    SET total_real_played=total_real_played+betReal, current_real_balance=current_real_balance-betReal,
        total_bonus_played=total_bonus_played+betBonus, current_bonus_balance=current_bonus_balance-betBonus, 
        total_bonus_win_locked_played=total_bonus_win_locked_played+betBonusWinLocked, current_bonus_win_locked_balance=current_bonus_win_locked_balance-betBonusWinLocked, 
        gcs.total_real_played_base=gcs.total_real_played_base+(betReal/exchangeRate), gcs.total_bonus_played_base=gcs.total_bonus_played_base+((betBonus+betBonusWinLocked)/exchangeRate),
        last_played_date=NOW(), 
        
        ggs.total_bet=ggs.total_bet+betAmount, ggs.total_bet_base=ggs.total_bet_base+betTotalBase, ggs.bets=ggs.bets+1, ggs.total_bet_real=ggs.total_bet_real+betReal, ggs.total_bet_bonus=ggs.total_bet_bonus+betBonus+betBonusWinLocked,
        
        gcss.total_bet=gcss.total_bet+betAmount,gcss.total_bet_base=gcss.total_bet_base+betTotalBase, gcss.bets=gcss.bets+1, gcss.total_bet_real=gcss.total_bet_real+betReal, gcss.total_bet_bonus=gcss.total_bet_bonus+betBonus+betBonusWinLocked,
        
        gcws.num_bets=gcws.num_bets+1, gcws.total_real_wagered=gcws.total_real_wagered+betReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered+betBonus+betBonusWinLocked,
        gcws.first_wagered_date=IFNULL(gcws.first_wagered_date, NOW()), gcws.last_wagered_date=NOW()
    WHERE gcs.client_stat_id = clientStatID;
  
  ELSE 
    
    SET statusCode=4;
    LEAVE root;
    
  END IF;
  
  OPEN betSinglesCursor;
  betSinglesLabel: LOOP 
    
    FETCH betSinglesCursor INTO sbBetSingleID, sbSelectionID, betAmount, sbOdd;
    IF (noMoreRecords) THEN
      LEAVE betSinglesLabel;
    END IF;                  
  
  INSERT INTO gaming_game_rounds
  (bet_total, bet_total_base, bet_real, bet_bonus, bet_bonus_win_locked, num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, sb_selection_id, sb_bet_id) 
  SELECT betAmount, betTotalBase, betReal, betBonus, betBonusWinLocked, 1, 1, NOW(), gameManufacturerID, clientID, clientStatID, 0, gaming_game_round_types.game_round_type_id, currencyID, sbSelectionID, sbBetID 
  FROM gaming_game_round_types
  WHERE gaming_game_round_types.name=roundType;
  
  SET gameRoundID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, is_win_placed, is_processed, currency_id, round_transaction_no, game_play_message_type_id, transaction_ref, sign_mult, sb_selection_id, sb_bet_id, license_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT betAmount, betTotalBase, exchangeRate, betReal, betBonus, betBonusWinLocked, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, 0, 0, currencyID, gaming_game_rounds.num_transactions, game_play_message_type_id, NULL, -1, sbSelectionID, sbBetID, licenseTypeID, 0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`) 
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='Bet' AND gaming_client_stats.client_stat_id=clientStatID
  JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id=gameRoundID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=('SportsBet' COLLATE utf8_general_ci); 

  SET gamePlayID=LAST_INSERT_ID();

  CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);
  
  SET @sbSelectionID=sbSelectionID;
  SET @sbPlayOdd=sbOdd;
  
  IF (bonusEnabledFlag) THEN 
    IF (betAmount > 0 AND roundType='Normal') THEN 
      SET @transferBonusMoneyFlag=1;
      
      SET @betBonusDeduct=betBonus;
      SET @betBonusDeductWinLocked=betBonusWinLocked;
      SET @betBonusDeductWagerRequirement=betAmount; 
      SET @wager_requirement_non_weighted=0;
      SET @wager_requirement_contribution=0;
      SET @betBonus=0;
      SET @betBonusWinLocked=0;
      SET @nowWagerReqMet=0;
      SET @hasReleaseBonus=0;
      
      INSERT INTO gaming_game_plays_bonus_instances (game_play_id, bonus_instance_id, client_stat_id, bet_bonus, bet_bonus_win_locked,
        bonus_deduct, bonus_deduct_win_locked, wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_deduct_wager_requirement, bonus_wager_requirement_remain_after)
      SELECT gamePlayID, bonus_instance_id, clientStatID,
        @betBonus:=IF(@betBonusDeduct>=bonus_amount_remaining, bonus_amount_remaining, @betBonusDeduct) AS bet_bonus,
        @betBonusWinLocked:=IF(@betBonusDeductWinLocked>=current_win_locked_amount,current_win_locked_amount,@betBonusDeductWinLocked) AS bet_bonus_win_locked,
        @betBonusDeduct:=GREATEST(0, @betBonusDeduct-bonus_amount_remaining) AS bonusDeductRemain, 
        @betBonusDeductWinLocked:=GREATEST(0, @betBonusDeductWinLocked-current_win_locked_amount) AS bonusWinLockedRemain, 
        @wager_requirement_non_weighted:=IF(ROUND(@betBonusDeductWagerRequirement*IFNULL(sb_weights.weight, 0), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, @betBonusDeductWagerRequirement) AS wager_requirement_non_weighted, 
        @wager_requirement_contribution:=IF(ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,1000000*100),@betBonusDeductWagerRequirement)*IFNULL(sb_weights.weight, 0), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,1000000*100),@betBonusDeductWagerRequirement)*IFNULL(sb_weights.weight, 0), 5)) AS wager_requirement_contribution,
        @wager_requirement_contribution:=LEAST(IFNULL(wgr_restrictions.max_wager_contibution,1000000*100), IF(wager_req_real_only OR bonusReqContributeRealOnly, ROUND(GREATEST(@wager_requirement_contribution-((@betBonus+@betBonusWinLocked)*IFNULL(sb_weights.weight,0)),0), 5), @wager_requirement_contribution)), 
        @nowWagerReqMet:=IF (bonus_wager_requirement_remain-@wager_requirement_contribution=0,1,0) AS now_wager_requirement_met,
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
        WHERE 
          client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 
        ORDER BY gaming_bonus_types_awarding ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date DESC
      ) AS gaming_bonus_instances  
      JOIN gaming_sb_selections ON gaming_sb_selections.sb_selection_id=@sbSelectionID
	  JOIN gaming_bonus_rules_wgr_sb_eligibility_criterias AS criterias ON gaming_bonus_instances.bonus_rule_id = criterias.bonus_rule_id
      JOIN gaming_bonus_rules_wgr_sb_profile_selections AS profile_selection ON criterias.eligibility_criterias_id = profile_selection.eligibility_criterias_id
		AND (
			   (profile_selection.sb_entity_id=gaming_sb_selections.sb_sport_id  AND profile_selection.sb_entity_type_id = 1 )OR 
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_region_id AND profile_selection.sb_entity_type_id = 2 )OR 
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_group_id  AND profile_selection.sb_entity_type_id = 3 )OR
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_event_id  AND profile_selection.sb_entity_type_id = 4 )OR 
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_market_id AND profile_selection.sb_entity_type_id = 5 )
			) 
	  JOIN gaming_bonus_rules_wgr_sb_weights AS sb_weights  ON criterias.eligibility_criterias_id = sb_weights.eligibility_criterias_id
		AND (@sbPlayOdd>=sb_weights.min_odd AND (sb_weights.max_odd IS NULL OR @sbPlayOdd<sb_weights.max_odd))
      LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_instances.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID
      HAVING wager_requirement_contribution > 0 OR bet_bonus > 0 OR bet_bonus_win_locked > 0;
      
      IF (ROW_COUNT() > 0) THEN
        
        UPDATE gaming_bonus_instances 
        JOIN gaming_game_plays_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
        SET bonus_amount_remaining=bonus_amount_remaining-bet_bonus, current_win_locked_amount=current_win_locked_amount-bet_bonus_win_locked,
            bonus_wager_requirement_remain=bonus_wager_requirement_remain-wager_requirement_contribution,
            
            is_secured=IF(now_wager_requirement_met=1,1,is_secured), secured_date=IF(now_wager_requirement_met=1,NOW(),NULL),
            gaming_bonus_instances.is_active=IF(is_active=0,0,IF(now_used_all=1 OR (now_wager_requirement_met=1 AND @transferBonusMoneyFlag=1),0,1))
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;           
         
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
        
        SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0)   ,
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
        INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
        FROM gaming_game_plays_bonus_instances
		LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id	
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;

        SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
        IF (@requireTransfer=1 AND @bonusTransferedTotal>0) THEN
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
        
        SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0) ,
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
        INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
        FROM gaming_game_plays_bonus_instances
		LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id	
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

        SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
        IF (@requireTransfer=1 AND @bonusTransferedTotal>0) THEN
          CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
        END IF; 
      
      END IF; 
      
    END IF; 
  END IF; 
  
  END LOOP betSinglesLabel;
  CLOSE betSinglesCursor;
  
  IF (playLimitEnabled AND roundType='Normal') THEN 
    CALL PlayLimitsUpdate(clientStatID, licenseType, betAmount, 1);
  END IF;
   
  SET statusCode=0;
  
END root$$

DELIMITER ;

