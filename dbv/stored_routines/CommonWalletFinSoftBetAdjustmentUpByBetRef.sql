DROP procedure IF EXISTS `CommonWalletFinSoftBetAdjustmentUpByBetRef`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletFinSoftBetAdjustmentUpByBetRef`(clientStatID BIGINT, transactionRef VARCHAR(50), betRef VARCHAR(40), adjustAmount DECIMAL(18,5), canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN

  

  

  DECLARE gameManufacturerName VARCHAR(20) DEFAULT 'FinSoft';

  DECLARE gameManufacturerID BIGINT DEFAULT 7; 
  DECLARE sbBetWinID, gamePlayID, sbBetID, sbExtraID, clientStatIDCheck, clientID, currencyID, sessionID, sbBetIDCheck, gamePlayMessageTypeID, gamePlayBetCounterID, countryID, countryTaxID BIGINT DEFAULT -1; 
  DECLARE gamePlayIDReturned, gameRoundID, gamePlayWinCounterID BIGINT DEFAULT NULL;
  DECLARE balanceReal, balanceBonus, adjustReal, adjustBonus, adjustBonusWinLocked, exchangeRate, betTotal, originalAdjustAmount, adjustAmountBase, remainAmountTotal, betRemain, taxBet, taxWin, roundBetTotal, roundWinTotal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal,  amountTaxPlayer, amountTaxOperator, taxModificationOperator, taxModificationPlayer, roundWinTotalFull, roundBetTotalFull DECIMAL(18,5) DEFAULT 0; 

  DECLARE playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, applyNetDeduction, winTaxPaidByOperator, taxEnabled, sportsTaxCountryEnabled TINYINT(1) DEFAULT 0;

  DECLARE signMult, numTransactions INT DEFAULT 1;

  DECLARE numApplicableBonuses, numBonuses INT DEFAULT 0;

  DECLARE clientWagerTypeID BIGINT DEFAULT 3; 
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
  DECLARE deviceType TINYINT(4) DEFAULT 1;
  DECLARE NumSingles INT DEFAULT 1;

  

  IF (adjustAmount<0) THEN

    SET statusCode=4;

  END IF;

  

  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, IFNULL(gs4.value_bool,0) AS vb4

  INTO playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, taxEnabled

  FROM gaming_settings gs1 

  JOIN gaming_settings gs2 ON gs2.name='IS_BONUS_ENABLED'

  JOIN gaming_settings gs3 ON gs3.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY'
  LEFT JOIN gaming_settings gs4 ON (gs4.name='TAX_ON_GAMEPLAY_ENABLED')

  WHERE gs1.name='PLAY_LIMIT_ENABLED';

  

  SELECT client_stat_id, client_id, currency_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance

  INTO clientStatIDCheck, clientID, currencyID, balanceReal, balanceBonus 

  FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;

  

  IF (clientStatIDCheck=-1) THEN

    SET statusCode=1;

    IF (canCommit) THEN COMMIT AND CHAIN; END IF;

    LEAVE root;

  END IF;

  

  
  SELECT sb_bet_id, game_play_id, sb_extra_id INTO sbBetIDCheck, gamePlayIDReturned, sbExtraID FROM gaming_sb_bet_history WHERE transaction_ref=transactionRef AND sb_bet_transaction_type_id=6; 
  

  IF (sbBetIDCheck!=-1) THEN 
    SET statusCode=0;

    IF (canCommit) THEN COMMIT AND CHAIN; END IF;

    CALL CommonWalletSBReturnTransactionData(gamePlayIDReturned, sbBetIDCheck, sbExtraID, 'Bet', clientStatID); 

    LEAVE root;

  END IF;

  

  
  SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.session_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions 

  INTO sbBetID, gamePlayID, gameRoundID, sessionID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions

  FROM gaming_sb_bet_singles 

  JOIN gaming_sb_bets ON gaming_sb_bet_singles.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_singles.sb_bet_id

    AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1

  JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_singles.sb_selection_id=gaming_game_plays.sb_extra_id AND 

    gaming_game_plays.game_play_message_type_id=8 AND gaming_game_plays.payment_transaction_type_id=12

  JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id

  ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
    

  
  IF (gamePlayID=-1) THEN

    SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.session_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions , gaming_sb_bet_multiples.num_singles

    INTO sbBetID, gamePlayID, gameRoundID, sessionID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions,NumSingles

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

  

  
  SELECT exchange_rate into exchangeRate FROM gaming_client_stats

  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 

  WHERE gaming_client_stats.client_stat_id=clientStatID

  LIMIT 1;

  

  SET @winBonusLost=0;

  SET @winBonusWinLockedLost=0;

  SET adjustAmountBase=ROUND(adjustAmount/exchangeRate,5);

  SET originalAdjustAmount=adjustAmount;

  
  SET signMult=-1;

  

  SELECT COUNT(*) AS num_applicable_bonuses INTO numApplicableBonuses 
  FROM gaming_bonus_instances AS gbi

  JOIN gaming_sb_bets_bonus_rules AS gsbbr ON (gbi.client_stat_id=clientStatID AND gbi.is_active) 

    AND gsbbr.sb_bet_id=sbBetID AND gbi.bonus_rule_id=gsbbr.bonus_rule_id;

  

  IF (numApplicableBonuses AND bonusEnabledFlag) THEN

  

    SET @betRemain=adjustAmount;

    SET @bonusCounter=0;

    SET @betReal=0;

    SET @betBonus=0;

    SET @betBonusWinLocked=0;

    SET @freeBetBonus=0;

  

    INSERT INTO gaming_game_plays_bet_counter (date_created, client_stat_id) VALUES (NOW(), clientStatID);

    SET gamePlayBetCounterID=LAST_INSERT_ID();

    

    INSERT INTO gaming_game_plays_bonus_instances_pre (game_play_bet_counter_id, bonus_instance_id, bet_total, bet_real, bet_bonus, bet_bonus_win_locked)

    SELECT gamePlayBetCounterID, bonus_instance_id, bet_real+free_bet_bonus+bet_bonus+bet_bonus_win_locked AS bet_total, bet_real, bet_bonus+free_bet_bonus, bet_bonus_win_locked

    FROM

    (

      SELECT

        bonus_instance_id AS bonus_instance_id, 

        @freeBetBonus:=IF(awarding_type='FreeBet', IF(bonus_amount_remaining>@betRemain, @betRemain, bonus_amount_remaining), 0) AS free_bet_bonus, @betRemain:=@betRemain-@freeBetBonus,   

        @betReal:=IF(@bonusCounter=0, IF(balanceReal>@betRemain, @betRemain, balanceReal), 0) AS bet_real, @betRemain:=@betRemain-@betReal,  

        @betBonusWinLocked:=IF(current_win_locked_amount>@betRemain, @betRemain, current_win_locked_amount) AS bet_bonus_win_locked, @betRemain:=@betRemain-@betBonusWinLocked,

        @betBonus:=IF(bonus_amount_remaining>@betRemain, @betRemain, bonus_amount_remaining) AS bet_bonus, @betRemain:=@betRemain-@betBonus, @bonusCounter:=@bonusCounter+1

      FROM

      (

        SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_types_awarding.name AS awarding_type, bonus_amount_remaining, current_win_locked_amount

        FROM gaming_bonus_instances

        JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id

        JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id

        JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id

        JOIN gaming_sb_bets_bonus_rules AS gsbbr ON (gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active) 

          AND gsbbr.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=gsbbr.bonus_rule_id

        WHERE client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 

        ORDER BY gaming_bonus_types_awarding.order ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date DESC

      ) AS XX

      HAVING free_bet_bonus!=0 OR bet_real!=0 OR bet_bonus!=0 OR bet_bonus_win_locked!=0

    ) AS XY;

    

    SELECT COUNT(*), SUM(bet_real), SUM(bet_bonus), SUM(bet_bonus_win_locked)  

    INTO numBonuses, adjustReal, adjustBonus, adjustBonusWinLocked 

    FROM gaming_game_plays_bonus_instances_pre

    WHERE game_play_bet_counter_id=gamePlayBetCounterID;

      

    SET betRemain=adjustAmount-(adjustReal+adjustBonus+adjustBonusWinLocked);

    SET adjustReal=adjustReal+betRemain; SET betRemain=0; 
  ELSE

    SET adjustReal=adjustAmount;

    SET adjustBonus=0;

    SET adjustBonusWinLocked=0;  

    SET betRemain=0;

  END IF;

  IF (taxEnabled) THEN
	SELECT bet_total, win_total, amount_tax_operator, amount_tax_player, bet_real, win_real
	INTO roundBetTotal, roundWinTotal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal
	FROM gaming_game_rounds
	WHERE game_round_id=gameRoundID;

    
    IF (roundWinTotal != 0.0 OR taxAlreadyChargedOperator != 0.0 OR taxAlreadyChargedPlayer != 0.0) THEN
	    SELECT clients_locations.country_id, gaming_countries.sports_tax INTO countryID, sportsTaxCountryEnabled  
		FROM clients_locations
		JOIN gaming_countries ON gaming_countries.country_id = clients_locations.country_id
		WHERE clients_locations.client_id = clientID AND clients_locations.is_primary = 1;
	  
		SET amountTaxPlayer = 0.0;
		SET amountTaxOperator = 0.0;
		SET taxModificationOperator = 0.0;
		SET taxModificationPlayer = 0.0;

		IF (countryID > 0 AND sportsTaxCountryEnabled = 1) THEN
		  
		  SELECT country_tax_id, bet_tax, win_tax, apply_net_deduction, tax_paid_by_operator_win INTO countryTaxID, taxBet, taxWin, applyNetDeduction, winTaxPaidByOperator
		  FROM gaming_country_tax AS gct
		  WHERE gct.country_id = countryID AND gct.is_current =  1 AND gct.licence_type_id = licenseTypeID AND gct.is_active = 1 LIMIT 1;
		
		  SET roundBetTotalReal = roundBetTotalReal + adjustReal;
		  SET roundWinTotalFull = roundWinTotalReal; 

			
		  IF(countryTaxID > 0) THEN	
			  IF(roundWinTotalFull > 0) THEN
				 IF(applyNetDeduction = 1) THEN
					IF(winTaxPaidByOperator = 0) THEN
						SET amountTaxPlayer = ABS(roundWinTotalFull - roundBetTotalReal) * taxWin; 
						SET amountTaxOperator = 0.0;
					ELSE 
						SET amountTaxPlayer = 0.0;
						SET amountTaxOperator = ABS(roundWinTotalFull - roundBetTotalReal) * taxWin; 
					END IF;
				ELSE 
					IF(winTaxPaidByOperator = 0) THEN
						SET amountTaxPlayer = ABS(roundWinTotalFull) * taxWin; 
						SET amountTaxOperator = 0.0;
					ELSE 
						SET amountTaxPlayer = 0.0;
						SET amountTaxOperator = ABS(roundWinTotalFull) * taxWin; 
					END IF;
				 END IF;
			ELSE
				SET amountTaxPlayer = 0.0;
				SET amountTaxOperator = roundBetTotalReal * taxWin;
			END IF;
	     END IF; -- country Tax ID
      END IF; -- country ID

    END IF; 
  END IF; -- tax enabled


  SET taxModificationOperator = amountTaxOperator - taxAlreadyChargedOperator;
  SET taxModificationPlayer = amountTaxPlayer - taxAlreadyChargedPlayer;

  UPDATE gaming_client_stats AS gcs

  LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID

  SET 

    total_real_played=total_real_played+adjustReal, current_real_balance=current_real_balance-adjustReal - taxModificationPlayer,

    total_bonus_played=total_bonus_played+adjustBonus, current_bonus_balance=current_bonus_balance-adjustBonus, 

    total_bonus_win_locked_played=total_bonus_win_locked_played+adjustBonusWinLocked, current_bonus_win_locked_balance=current_bonus_win_locked_balance-adjustBonusWinLocked, 

    gcs.total_real_played_base=gcs.total_real_played_base+IFNULL((adjustReal/exchangeRate),0), gcs.total_bonus_played_base=gcs.total_bonus_played_base+((adjustBonus+adjustBonusWinLocked)/exchangeRate), gcs.total_tax_paid = gcs.total_tax_paid + taxModificationPlayer,

    
    gcss.total_bet=gcss.total_bet+adjustAmount, gcss.total_bet_base=gcss.total_bet_base+adjustAmountBase, gcss.total_bet_real=gcss.total_bet_real+adjustReal, gcss.total_bet_bonus=gcss.total_bet_bonus+adjustBonus+adjustBonusWinLocked

  WHERE gcs.client_stat_id=clientStatID;  

  

  
  INSERT INTO gaming_game_plays 

  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, game_round_id, payment_transaction_type_id, is_win_placed, is_processed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, sb_extra_id, sb_bet_id, license_type_id, device_type, sign_mult, pending_bet_real, pending_bet_bonus, amount_tax_operator, amount_tax_player,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 

  SELECT adjustAmount, adjustAmountBase, exchangeRate, adjustReal, adjustBonus, adjustBonusWinLocked, 0, 0, 0, 0, NOW(), gameManufacturerID, clientID, clientStatID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 1, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, currencyID, numTransactions+1, gamePlayMessageTypeID, sbExtraID, sbBetID, licenseTypeID, deviceType, signMult, pending_bets_real, pending_bets_bonus, taxModificationOperator, taxModificationPlayer,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)

  FROM gaming_payment_transaction_type

  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='BetAdjustment' AND gaming_client_stats.client_stat_id=clientStatID;

  

  SET gamePlayIDReturned=LAST_INSERT_ID();
  
  CALL GameUpdateRingFencedBalances(clientStatID,gamePlayIDReturned);  
  

  
  INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units)

  SELECT gamePlayIDReturned, 12, adjustAmount/NumSingles, adjustAmountBase/NumSingles, adjustReal/NumSingles, adjustReal/NumSingles/exchangeRate, (adjustBonus+adjustBonusWinLocked)/NumSingles, (adjustBonus+adjustBonusWinLocked)/NumSingles/exchangeRate, NOW(), exchangeRate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, 0

  FROM gaming_game_plays_sb

  WHERE game_play_id=gamePlayID
  GROUP BY sb_selection_id;

  

  
  IF (playLimitEnabled AND adjustAmount!=0) THEN 

    CALL PlayLimitsUpdate(clientStatID, 'sportsbook', originalAdjustAmount, 0);

  END IF;

  

  
  
  UPDATE gaming_game_rounds AS ggr

  SET 

    ggr.bet_total=bet_total+adjustAmount, bet_total_base=ROUND(bet_total_base+adjustAmountBase,5), bet_real=bet_real+adjustReal, bet_bonus=bet_bonus+adjustBonus, bet_bonus_win_locked=bet_bonus_win_locked+adjustBonusWinLocked, 

    win_bet_diffence_base=win_total_base-bet_total_base, ggr.num_transactions=ggr.num_transactions+1, ggr.amount_tax_operator = amountTaxOperator, ggr.amount_tax_player = amountTaxPlayer

  WHERE game_round_id=gameRoundID;

  

  UPDATE gaming_client_wager_stats AS gcws 

  SET gcws.total_real_wagered=gcws.total_real_wagered+adjustReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered+(adjustBonus+adjustBonusWinLocked)

  WHERE gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID;

  

  IF (bonusEnabledFlag AND numBonuses>0) THEN 

    SET @transferBonusMoneyFlag=1;

    SET @betBonusDeductWagerRequirement=adjustAmount; 
    SET @wager_requirement_non_weighted=0;

    SET @wager_requirement_contribution=0;

    SET @betBonus=0;

    SET @betBonusWinLocked=0;

    SET @nowWagerReqMet=0;

    SET @hasReleaseBonus=0;

    


    
    INSERT INTO gaming_game_plays_bonus_instances (game_play_id,game_play_id_bet, bonus_instance_id, bonus_rule_id, client_stat_id, timestamp, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,

      wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_wager_requirement_remain_after)

    SELECT gamePlayIDReturned,gamePlayID, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, clientStatID, NOW(), exchangeRate,

      
      
      
          
      gaming_bonus_instances.bet_real, gaming_bonus_instances.bet_bonus, gaming_bonus_instances.bet_bonus_win_locked,

      

      @wager_requirement_non_weighted:=IF(ROUND(gaming_bonus_instances.bet_total*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain/IFNULL(sb_bonus_rules.weight, 1)/IFNULL(license_weight_mod, 1), gaming_bonus_instances.bet_total) AS wager_requirement_non_weighted, 

      @wager_requirement_contribution:=IF(ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,100000000*100),gaming_bonus_instances.bet_total)*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,1000000*100),gaming_bonus_instances.bet_total)*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)) AS wager_requirement_contribution_pre,

      @wager_requirement_contribution:=LEAST(IFNULL(wgr_restrictions.max_wager_contibution,100000000*100), IF(wager_req_real_only OR bonusReqContributeRealOnly, ROUND(GREATEST(@wager_requirement_contribution-((gaming_bonus_instances.bet_bonus+gaming_bonus_instances.bet_bonus_win_locked)*IFNULL(sb_bonus_rules.weight,0)*IFNULL(license_weight_mod, 1)),0), 5), @wager_requirement_contribution)) AS wager_requirement_contribution, 
      

      @nowWagerReqMet:=IF (bonus_wager_requirement_remain-@wager_requirement_contribution=0,1,0) AS now_wager_requirement_met,

      

      IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wager_requirement_contribution)>=

        ((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,

      bonus_wager_requirement_remain-@wager_requirement_contribution AS bonus_wager_requirement_remain_after

    FROM 

    (

      SELECT bonus_transaction.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, bonus_transaction.bet_total, bonus_transaction.bet_real, bonus_transaction.bet_bonus, bonus_transaction.bet_bonus_win_locked, bonus_wager_requirement_remain, IF(licenseTypeID=1,gaming_bonus_rules.casino_weight_mod, IF(licenseTypeID=2,gaming_bonus_rules.poker_weight_mod,IF(licenseTypeID=3, sportsbook_weight_mod ,1))) AS license_weight_mod,

        bonus_amount_given, bonus_wager_requirement, gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus

      FROM gaming_game_plays_bonus_instances_pre AS bonus_transaction

      JOIN gaming_bonus_instances ON bonus_transaction.bonus_instance_id=gaming_bonus_instances.bonus_instance_id

      JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id

      JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id

      WHERE bonus_transaction.game_play_bet_counter_id=gamePlayBetCounterID 
    ) AS gaming_bonus_instances  

    JOIN gaming_sb_bets_bonus_rules AS sb_bonus_rules ON sb_bonus_rules.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=sb_bonus_rules.bonus_rule_id  

    LEFT JOIN gaming_sb_bets_bonuses ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_sb_bets_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id

    LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_instances.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID

    ; 


    IF (ROW_COUNT() > 0) THEN

      
      
      UPDATE gaming_bonus_instances 

      JOIN gaming_game_plays_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id

      SET bonus_amount_remaining=bonus_amount_remaining-bet_bonus, current_win_locked_amount=current_win_locked_amount-bet_bonus_win_locked,

          bonus_wager_requirement_remain=bonus_wager_requirement_remain-wager_requirement_contribution,

          
          is_secured=IF(now_wager_requirement_met=1,1,is_secured), secured_date=IF(now_wager_requirement_met=1,NOW(),NULL)

          
          
      WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayIDReturned;           

  

      
      
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

      WHERE ggpbi.game_play_id=gamePlayIDReturned AND now_wager_requirement_met=1 AND now_used_all=0;

    

      
      SET @requireTransfer=0;

      SET @bonusTransfered=0;

      SET @bonusWinLockedTransfered=0;

      SET @bonusTransferedLost=0;

      SET @bonusWinLockedTransferedLost=0;

	  SET @ringFencedAmount=0;

	  SET @ringFencedAmountSB=0;

	  SET @ringFencedAmountCasino=0;

	  SET @ringFencedAmountPoker=0;

      

      SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0),

	  ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),

	  ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
				
      INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,

	  @ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker

      FROM gaming_game_plays_bonus_instances

	  LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id

      WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayIDReturned AND now_wager_requirement_met=1 AND now_used_all=0;

      

      SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);

      SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;

      IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN

        CALL PlaceBetBonusCashExchange(clientStatID, gamePlayIDReturned, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);

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

      WHERE ggpbi.game_play_id=gamePlayIDReturned AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

      

      SET @requireTransfer=0;

      SET @bonusTransfered=0;

      SET @bonusWinLockedTransfered=0;

      SET @bonusTransferedLost=0;

      SET @bonusWinLockedTransferedLost=0;

	  SET @ringFencedAmount=0;

	  SET @ringFencedAmountSB=0;

	  SET @ringFencedAmountCasino=0;

	  SET @ringFencedAmountPoker=0;


      

      SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0),
	  
	  ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),

	  ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)

      INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,

	  @ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker

      FROM gaming_game_plays_bonus_instances

	  LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id

      WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayIDReturned AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

      

      SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);

      SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;

      IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN

        CALL PlaceBetBonusCashExchange(clientStatID, gamePlayIDReturned, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);

      END IF; 
    

    END IF; 
  END IF; 
  

  INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount, transaction_ref, game_play_id, sb_extra_id) 

  SELECT sbBetID, sb_bet_transaction_type_id, NOW(), originalAdjustAmount, transactionRef, gamePlayIDReturned, sbExtraID

  FROM gaming_sb_bet_transaction_types WHERE name='BetAdjustment';

  

  SET statusCode=0;

  IF (canCommit) THEN COMMIT AND CHAIN; END IF;

  CALL CommonWalletSBReturnTransactionData(gamePlayIDReturned, sbBetID, sbExtraID, 'Bet', clientStatID); 

  

END root$$

DELIMITER ;

