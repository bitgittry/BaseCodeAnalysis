DROP procedure IF EXISTS `PlaceSBBetCancel`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceSBBetCancel`(clientStatID BIGINT, gamePlayID BIGINT,gameRoundID BIGINT, betToCancelAmount DECIMAL(18, 5), liveBetType TINYINT(4), deviceType TINYINT(4), selectionID BIGINT, refundMultiples TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN

  /* Status Codes
  0 : Success
  1 : gamePlayID or clientStatID not found
  2 : gamePlayID is already processed or amount to refund is bigger than bet
  */
 
 
	DECLARE cancelAmount, cancelTotalBase, cancelReal, cancelBonus, cancelBonusWinLocked, cancelRemain, cancelOther DECIMAL(18, 5) DEFAULT 0;
	DECLARE betAmount, betTotalBase, betReal, betBonus, betBonusWinLocked, cancelRatio,adjustAmount,numBonuses,
			taxBet, taxWin, roundBetTotal, roundWinTotal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal,  amountTaxPlayer, amountTaxOperator, taxModificationOperator, taxModificationPlayer, roundWinTotalFull, roundBetTotalFull DECIMAL(18, 5) DEFAULT 0;
	DECLARE exchangeRate, playRemainingValue, totalLoyaltyPoints, totalLoyaltyPointsBonus DECIMAL(18, 5) DEFAULT 0;
	DECLARE gamePlayIDCheck, gameID, gameManufacturerID, clientStatIDCheck, clientID, currencyID, sbExtraID, sbBetID, gamePlayMessageTypeID,gamePlayBetCounterID, countryID, countryTaxID, vipLevelID, sessionID  BIGINT DEFAULT -1;
	DECLARE dateTimeWin DATETIME DEFAULT NULL;
	DECLARE bonusEnabledFlag, playLimitEnabled, disableBonusMoney, isAlreadyProcessed, applyNetDeduction, winTaxPaidByOperator, taxEnabled, sportsTaxCountryEnabled TINYINT(1) DEFAULT 0;
	DECLARE numBets, numTransactions INT DEFAULT 0;
	DECLARE licenseType, roundType VARCHAR(20) DEFAULT NULL;
	DECLARE clientWagerTypeID INT DEFAULT -1;
	DECLARE licenseTypeID,bonusReqContributeRealOnly TINYINT(4) DEFAULT 3; -- SportsBook
	DECLARE numOfBets, countMult INT DEFAULT -1;
	DECLARE currentVipType VARCHAR(100) DEFAULT '';
    -- DECLARE sign_mult INT DEFAULT 1;
	
	SET gamePlayIDReturned=NULL;
	SET clientWagerTypeID=3;
	SET licenseType=3;

	
	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, IFNULL(gs4.value_bool,0) AS vb4
	INTO playLimitEnabled, bonusEnabledFlag,bonusReqContributeRealOnly, taxEnabled
	FROM gaming_settings gs1 
	JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
    JOIN gaming_settings gs3 ON gs3.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY'
    LEFT JOIN gaming_settings gs4 ON (gs4.name='TAX_ON_GAMEPLAY_ENABLED')
	WHERE gs1.name='PLAY_LIMIT_ENABLED';

	SELECT client_stat_id, client_id, gaming_client_stats.currency_id INTO clientStatIDCheck, clientID, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
	
	SELECT gaming_operator_currency.exchange_rate, gaming_clients.vip_level_id, gaming_vip_levels.set_type, sessions_main.session_id
	INTO exchangeRate, vipLevelID, currentVipType, sessionID
	FROM gaming_clients
	STRAIGHT_JOIN sessions_main FORCE INDEX (client_latest_session) ON sessions_main.extra_id=gaming_clients.client_id AND sessions_main.is_latest
	JOIN gaming_operator_currency ON gaming_operator_currency.currency_id = currencyID
	LEFT JOIN gaming_vip_levels ON gaming_vip_levels.vip_level_id = gaming_clients.vip_level_id 
	WHERE gaming_clients.client_id=clientID;

	-- don't remove the order because we are setting the ClientStatID in here
	SELECT gaming_game_plays.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.is_win_placed, (amount_total*sign_mult), (amount_total_base*sign_mult), (amount_real*sign_mult), (amount_bonus*sign_mult), (amount_bonus_win_locked*sign_mult), game_manufacturer_id, sb_extra_id, sb_bet_id, game_play_message_type_id
	INTO gamePlayIDCheck, gameRoundID, isAlreadyProcessed, betAmount, betTotalBase, betReal, betBonus, betBonusWinLocked, gameManufacturerID, sbExtraID, sbBetID, gamePlayMessageTypeID 
	FROM gaming_game_plays 
	JOIN gaming_payment_transaction_type ON gaming_game_plays.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id
	WHERE game_round_id=gameRoundID AND (gaming_game_plays.payment_Transaction_type_id IN (45,12,20,247) OR name = 'PartialCancel')
	LIMIT 1;
	
	SELECT loyalty_points, loyalty_points_bonus
	INTO totalLoyaltyPoints, totalLoyaltyPointsBonus
	FROM gaming_game_plays
	WHERE game_play_id = gamePlayID;

	SELECT num_transactions INTO numTransactions FROM gaming_game_rounds WHERE game_round_id=gameRoundID;

	IF (gamePlayIDCheck=-1 OR clientStatIDCheck=-1) THEN 
		SET statusCode=1;
		LEAVE root;
	END IF;

	IF (betToCancelAmount>(betAmount*-1)) THEN
		SET statusCode= 6;
		LEAVE root;
	END IF;

	SET cancelRatio=IFNULL(betToCancelAmount/betAmount*-1,0); -- negate ratio since values need to be passed as negative

	-- if amount to refund is the same as the bet value then there is no need to select from real or bonus but refund as played 
	IF (betToCancelAmount=betAmount) THEN
		SET cancelReal=betReal; 
		SET cancelBonus=betBonus; 
		SET cancelBonusWinLocked=betBonusWinLocked; 
		SET adjustAmount=(betReal+betBonus+betBonusWinLocked) * -1;
	ELSE  
		SET adjustAmount=betToCancelAmount;
	END IF;
	
	SET @bonusLost=0;
	SET @bonusWinLockedLost=0;

	IF (bonusEnabledFlag) THEN 

		SET @numPlayBonusInstances=0;
		SELECT COUNT(*) INTO @numPlayBonusInstances
		FROM gaming_game_plays_bonus_instances 
		WHERE game_play_id=gamePlayID;

		INSERT INTO gaming_game_plays_bet_counter (date_created, client_stat_id) VALUES (NOW(), clientStatID);
		SET gamePlayBetCounterID=LAST_INSERT_ID();

		IF (@numPlayBonusInstances>0) THEN

		  -- 1. update gaming_bonus_instances in-order to partition winnings 
			INSERT INTO gaming_game_plays_bonus_instances_pre (game_play_bet_counter_id, bonus_instance_id, bet_total, bet_real, bet_bonus, bet_bonus_win_locked)
			SELECT gamePlayBetCounterID, bonus_instance_id, bet_real+bet_bonus+bet_bonus_win_locked AS bet_total, bet_real, bet_bonus, bet_bonus_win_locked   
			FROM
			(
			SELECT 
				play_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id,play_bonus_instances.client_stat_id,
				IFNULL(ROUND(IF(gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=0, ROUND((SUM(bet_bonus)/betAmount)*adjustAmount, 0), 0),0),0) AS bet_bonus,
				IFNULL(ROUND(IF(gaming_bonus_instances.is_secured=0 AND gaming_bonus_instances.is_lost=0, ROUND(SUM(bet_bonus_win_locked)/betAmount*adjustAmount, 0), 0),0),0) AS bet_bonus_win_locked,  
				IFNULL(ROUND((SUM(bet_real)/betAmount)*adjustAmount,0) + ROUND(IF(gaming_bonus_instances.is_secured=0,0,(SUM(bet_bonus+bet_bonus_win_locked)/betAmount)*adjustAmount),0),0) AS bet_real
			FROM gaming_game_plays_bonus_instances AS play_bonus_instances FORCE INDEX (game_play_id, game_play_id_bet)
			JOIN gaming_bonus_instances ON play_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON gaming_bonus_rules.bonus_rule_id=wager_restrictions.bonus_rule_id AND wager_restrictions.currency_id=currencyID
			WHERE play_bonus_instances.game_play_id = gamePlayID OR play_bonus_instances.game_play_id_bet=gamePlayID  
			GROUP BY play_bonus_instances.bonus_instance_id
			) AS XX;

			SELECT COUNT(*), SUM(bet_real), SUM(bet_bonus), SUM(bet_bonus_win_locked)  
			INTO numBonuses, cancelReal, cancelBonus, cancelBonusWinLocked 
			FROM gaming_game_plays_bonus_instances_pre
			WHERE game_play_bet_counter_id=gamePlayBetCounterID;

			-- SET cancelBonus=ABS(ROUND(cancelBonus-@bonusLost,0));
			-- SET cancelBonusWinLocked=ABS(ROUND(cancelBonusWinLocked-@bonusWinLockedLost,0));
		ELSE
			SET cancelReal = adjustAmount*-1;
			SET cancelBonus = 0;
			SET cancelBonusWinLocked = 0;
		END IF;
	ELSE
		SET cancelReal = adjustAmount*-1;
		SET cancelBonus = 0;
		SET cancelBonusWinLocked = 0;
	END IF;

 -- Add Tax Adjustment Calculations
   -- Retrieve Tax Flags
   
   IF (taxEnabled) THEN
	SELECT bet_total, win_total, amount_tax_operator, amount_tax_player, bet_real, win_real
	INTO roundBetTotal, roundWinTotal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal
	FROM gaming_game_rounds
	WHERE game_round_id=gameRoundID;

	SELECT clients_locations.country_id, gaming_countries.sports_tax INTO countryID, sportsTaxCountryEnabled  
	FROM clients_locations
	JOIN gaming_countries ON gaming_countries.country_id = clients_locations.country_id
	WHERE clients_locations.client_id = clientID AND clients_locations.is_primary = 1;
	  
	SET amountTaxPlayer = 0.0;
	SET amountTaxOperator = 0.0;
	SET taxModificationOperator = 0.0;
	SET taxModificationPlayer = 0.0;

	-- Bet cancel will cancel out all tax calculations which have previously occured.
	IF (countryID > 0 AND sportsTaxCountryEnabled = 1) THEN
	  SET taxModificationOperator = taxAlreadyChargedOperator;
	  SET taxModificationPlayer = taxAlreadyChargedPlayer;
	END IF;
END IF; -- taxEnabled

	
	UPDATE gaming_client_stats AS gcs
    JOIN gaming_client_wager_types ON gaming_client_wager_types.client_wager_type_id = clientWagerTypeID
	LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=gaming_client_wager_types.client_wager_type_id
	SET gcs.total_real_played=gcs.total_real_played+cancelReal, gcs.current_real_balance=gcs.current_real_balance-cancelReal - taxModificationPlayer,
		gcs.total_bonus_played=gcs.total_bonus_played+cancelBonus, gcs.current_bonus_balance=gcs.current_bonus_balance-cancelBonus, 
		gcs.total_bonus_win_locked_played=gcs.total_bonus_win_locked_played+cancelBonusWinLocked, gcs.current_bonus_win_locked_balance=gcs.current_bonus_win_locked_balance-cancelBonusWinLocked,
		gcs.total_real_played_base=gcs.total_real_played_base+(cancelReal/exchangeRate), gcs.total_bonus_played_base=gcs.total_bonus_played_base+((cancelBonus+cancelBonusWinLocked)/exchangeRate), gcs.total_tax_paid = gcs.total_tax_paid - taxModificationPlayer,
		-- loyalty points
		gcs.total_loyalty_points_given = gcs.total_loyalty_points_given - IFNULL(totalLoyaltyPoints,0),
		gcs.current_loyalty_points = gcs.current_loyalty_points - IFNULL(totalLoyaltyPoints,0),
		gcs.total_loyalty_points_given_bonus = gcs.total_loyalty_points_given_bonus - IFNULL(totalLoyaltyPointsBonus,0),
		gcs.loyalty_points_running_total = IF(currentVipType = 'LoyaltyPointsPeriod', gcs.loyalty_points_running_total - IFNULL(totalLoyaltyPoints,0), gcs.loyalty_points_running_total),
		
		-- gaming_client_sessions
		gcss.bets = gcss.bets - 1,
		gcss.total_bet_real = gcss.total_bet_real + cancelReal,
		gcss.total_bet_bonus = gcss.total_bet_bonus + cancelBonus + cancelBonusWinLocked,
		gcss.loyalty_points = gcss.loyalty_points - IFNULL(totalLoyaltyPoints,0), 
		gcss.loyalty_points_bonus = gcss.loyalty_points_bonus - IFNULL(totalLoyaltyPointsBonus,0),
		
		-- gaming_client_wager_types
		gcws.num_bets = gcws.num_bets - 1,
		gcws.total_real_wagered = gcws.total_real_wagered + cancelReal,
		gcws.total_bonus_wagered = gcws.total_bonus_wagered + (cancelBonus + cancelBonusWinLocked),
		gcws.loyalty_points = gcws.loyalty_points - IFNULL(totalLoyaltyPoints,0),
		gcws.loyalty_points_bonus = gcws.loyalty_points_bonus - IFNULL(totalLoyaltyPointsBonus,0)
	WHERE gcs.client_stat_id=clientStatID;  
	
	-- Update vip level of the client
	IF (vipLevelID IS NOT NULL AND vipLevelID > 0) THEN
		CALL PlayerUpdateVIPLevel(clientStatID,0);
	END IF;
	  
	SET cancelAmount=ROUND(cancelReal+cancelBonus+cancelBonusWinLocked+cancelOther+@bonusLost+@bonusWinLockedLost,0); -- check cancelAmount matches
	SET cancelTotalBase=ROUND(cancelAmount/exchangeRate,5);

	-- 3. update is_win_placed flag (set flags are already processed)
	UPDATE gaming_game_plays SET is_processed=1, is_win_placed=1 WHERE game_play_id=gamePlayID;

	-- 3. Insert into gaming_game_plays 
	INSERT INTO gaming_game_plays
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, bonus_win_locked_lost, 
     jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, game_round_id, payment_transaction_type_id, is_win_placed, 
     is_processed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, 
     sb_extra_id, sb_bet_id, license_type_id, device_type, pending_bet_real, pending_bet_bonus, amount_tax_operator, amount_tax_player, 
     loyalty_points, loyalty_points_bonus, loyalty_points_after, loyalty_points_after_bonus) 
	SELECT cancelAmount*-1, cancelTotalBase*-1, exchangeRate, cancelReal*-1, cancelBonus*-1, cancelBonusWinLocked*-1, cancelOther*-1, @bonusLost, @bonusWinLockedLost, 
		0, NOW(), gameManufacturerID, clientID, clientStatID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 
        1, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, currencyID, numTransactions+1, gaming_game_play_message_types.game_play_message_type_id,
		sbExtraID, sbBetID, licenseTypeID, deviceType, pending_bets_real, pending_bets_bonus, taxModificationOperator*-1, taxModificationPlayer*-1,
		-loyalty_points, -loyalty_points_bonus, gaming_client_stats.current_loyalty_points-loyalty_points, IFNULL(gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus - loyalty_points_bonus, 0)
	FROM gaming_game_plays FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='BetCancelled'
	JOIN gaming_client_stats  ON gaming_client_stats.client_stat_id=clientStatID
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.game_play_message_type_id=IF(gamePlayMessageTypeID=8,12,13)
	WHERE gaming_game_plays.game_play_id=gamePlayID;

	SET gamePlayIDReturned=LAST_INSERT_ID();

	INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units, game_round_id, sb_bet_entry_id, sign_mult)
	SELECT gamePlayIDReturned, payment_transaction_type_id, amount_total*-1, amount_total_base*-1, amount_real*-1, amount_real_base*-1, amount_bonus*-1, amount_bonus_base*-1, NOW(), exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, liveBetType, deviceType, units*cancelRatio, game_round_id, sb_bet_entry_id, -1
	FROM gaming_game_plays_sb
	WHERE game_play_id=gamePlayID AND sb_selection_id = IF(refundMultiples = 0, selectionID, sb_selection_id);

	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayIDReturned);
          
	IF (bonusEnabledFlag && @numPlayBonusInstances>0) THEN 

		-- 2. update gaming_bonus_instances in-oder to add bonus_amount_remaining, current_win_locked_amount, bonus_wager_requirement_remain
		-- check wether all the bonus has been used
		INSERT INTO gaming_game_plays_bonus_instances (game_play_id,game_play_id_bet, bonus_instance_id, bonus_rule_id, client_stat_id, timestamp, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,
		  wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_wager_requirement_remain_after)
		SELECT gamePlayIDReturned,gamePlayID, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, clientStatID, NOW(), exchangeRate,

		  gaming_bonus_instances.bet_real, gaming_bonus_instances.bet_bonus, gaming_bonus_instances.bet_bonus_win_locked,
		  
		  @wager_requirement_non_weighted:=IF(ROUND(gaming_bonus_instances.bet_total*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, gaming_bonus_instances.bet_total) AS wager_requirement_non_weighted, 
		  @wager_requirement_contribution:=IF(ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,100000000*100),gaming_bonus_instances.bet_total)*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,1000000*100),gaming_bonus_instances.bet_total)*IFNULL(sb_bonus_rules.weight, 0)*IFNULL(license_weight_mod, 1), 5)) AS wager_requirement_contribution_pre,
		  @wager_requirement_contribution:=LEAST(IFNULL(wgr_restrictions.max_wager_contibution,100000000*100), IF(wager_req_real_only OR bonusReqContributeRealOnly, ROUND(GREATEST(@wager_requirement_contribution-((gaming_bonus_instances.bet_bonus+gaming_bonus_instances.bet_bonus_win_locked)*IFNULL(sb_bonus_rules.weight,0)*IFNULL(license_weight_mod, 1)),0), 5), @wager_requirement_contribution)) AS wager_requirement_contribution, -- need test: *IFNULL(sb_bonus_rules.weight,0)*IFNULL(license_weight_mod, 1)
		  
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
		  WHERE bonus_transaction.game_play_bet_counter_id=gamePlayBetCounterID -- AND gaming_bonus_instances.expiry_date > NOW() 
		) AS gaming_bonus_instances  
		JOIN gaming_sb_bets_bonus_rules AS sb_bonus_rules ON sb_bonus_rules.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=sb_bonus_rules.bonus_rule_id  
		LEFT JOIN gaming_sb_bets_bonuses ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_sb_bets_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
		LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_instances.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID;

		UPDATE gaming_bonus_instances 
		JOIN gaming_game_plays_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
		SET bonus_amount_remaining=bonus_amount_remaining-bet_bonus, current_win_locked_amount=current_win_locked_amount-bet_bonus_win_locked,
		  bonus_wager_requirement_remain=bonus_wager_requirement_remain-wager_requirement_contribution,
	      is_active = IF (is_used_all=1 AND NOW() < expiry_date AND is_lost =0 ,1 , is_active),
		  is_used_all = IF (is_used_all=1 AND NOW() < expiry_date AND is_lost =0 ,0 , is_used_all)
		WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayIDReturned; 

-- update bonus and - 1 open rounds

		-- 2.1 If any of the bonuses had been lost between the bet and the win then need to transfer to gaming_bonus_losts
		IF (@bonusLost+@bonusWinLockedLost>0) THEN
			INSERT INTO gaming_bonus_losts (bonus_instance_id, client_stat_id, bonus_lost_type_id, bonus_amount, bonus_win_locked_amount, extra_id, date_time_lost, session_id)
			SELECT bonus_instance_id, client_stat_id, gaming_bonus_lost_types.bonus_lost_type_id, IFNULL(SUM(lost_win_bonus),0), IFNULL(SUM(lost_win_bonus_win_locked),0), NULL, NOW(), NULL
			FROM gaming_game_plays_bonus_instances  
			JOIN gaming_bonus_lost_types ON gaming_bonus_lost_types.name='BetCancelledAfterLostOrSecured'
			WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND (gaming_game_plays_bonus_instances.lost_win_bonus!=0 OR gaming_game_plays_bonus_instances.lost_win_bonus_win_locked!=0) -- Condition
			GROUP BY gaming_game_plays_bonus_instances.bonus_instance_id;
		END IF;

	END IF;

  -- 2.4 Update Play Limits Current Value
  IF (playLimitEnabled) THEN 
    CALL PlayLimitsUpdate(clientStatID, 'sportsbook', cancelAmount, 1); -- no need to *-1 because cancelAmount already negative
  END IF;

  -- 4. update tables
  -- update gaming_game_rounds with win amount   [TAX - Set tax operator and tax player to 0]
  UPDATE gaming_game_rounds AS ggr
  SET 
  ggr.bet_total=bet_total+cancelAmount, 
  bet_total_base=ROUND(bet_total_base+cancelTotalBase,5),
	bet_real=bet_real+cancelReal,
	bet_bonus=bet_bonus+cancelBonus,
	bet_bonus_win_locked=bet_bonus_win_locked+cancelBonusWinLocked, 
	win_bet_diffence_base=win_total_base+bet_total_base,
    ggr.num_bets=GREATEST(0, ggr.num_bets-1), -- dedict from master record
	ggr.num_transactions=ggr.num_transactions+1, 
	ggr.amount_tax_operator = 0.0,
	ggr.amount_tax_player = 0.0,
	ggr.loyalty_points = ggr.loyalty_points - totalLoyaltyPoints,
	ggr.loyalty_points_bonus = ggr.loyalty_points_bonus - totalLoyaltyPointsBonus
  WHERE game_round_id=gameRoundID;

 /* UPDATE gaming_game_plays_sb AS ggps FORCE INDEX (game_play_id)
  STRAIGHT_JOIN gaming_game_rounds AS ggr ON ggr.game_round_id=ggps.game_round_id
  STRAIGHT_JOIN gaming_game_plays_sb AS bets ON bets.game_round_id=ggr.game_round_id AND bets.game_play_id=gamePlayID
  SET 
	ggr.bet_total=0,
	ggr.bet_total_base=0,
	ggr.bet_real=0,
	ggr.bet_bonus=0,
	ggr.bet_bonus_win_locked=0, 
	ggr.win_bet_diffence_base=0,
    ggr.num_bets=0, -- dedict from master record
	ggr.num_transactions=ggr.num_transactions+1, 
	ggr.amount_tax_operator = 0.0,
	ggr.amount_tax_player = 0.0,
    ggr.date_time_end = NOW(),
	ggr.is_round_finished = 1,
	ggr.is_processed = 1,
	ggr.is_cancelled = 1,
    -- original wager
    bets.confirmation_status=1,
	ggr.loyalty_points = 0,
	ggr.loyalty_points_bonus = 0
  WHERE ggps.game_play_id=gamePlayIDReturned;*/
/*
  -- set num_bets = 0, if there are multiples in the bet (cancel the whole bet if yes)
  IF(refundMultiples = 1) THEN
  
	-- update master record's fields
	UPDATE gaming_game_rounds
		SET num_bets = 0,
			date_time_end = NOW(),
			is_round_finished = 1,
			is_processed = 1,
			is_cancelled = 1
		WHERE gaming_game_rounds.game_round_id=gameRoundID;
    
	-- update gaming_game_plays.is_cancelled = true if master record from gaming_game_rounds is cancelled
	UPDATE gaming_game_plays SET is_cancelled = 1 WHERE game_play_id = gamePlayID;
	-- set confirmation_status to 1 (cancelled)
	UPDATE gaming_game_plays_sb SET confirmation_status = 1 WHERE game_play_id = gamePlayID;

	-- insert negative amount for multiple
	INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units, game_round_id, sb_bet_entry_id, sign_mult)
	SELECT gamePlayIDReturned, payment_transaction_type_id, amount_total*-1, amount_total_base*-1, amount_real*-1, amount_real_base*-1, amount_bonus*-1, amount_bonus_base*-1, NOW(), exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, liveBetType, deviceType, units*cancelRatio, game_round_id, sb_bet_entry_id, -1
	FROM gaming_game_plays_sb
	WHERE game_play_id=gamePlayID AND sb_selection_id IS NULL;

  ELSE
	UPDATE gaming_game_plays_sb
	JOIN gaming_game_rounds ON gaming_game_plays_sb.game_round_id = gaming_game_rounds.game_round_id
	SET	gaming_game_rounds.date_time_end = NOW(),
		gaming_game_rounds.is_cancelled = 1
	WHERE gaming_game_plays_sb.sb_selection_id = selectionID;
  END IF;
*/

  SELECT num_bets INTO numOfBets
  FROM gaming_game_rounds WHERE gaming_game_rounds.game_round_id=gameRoundID;

  IF(numOfBets = 0) THEN

	UPDATE gaming_game_rounds 
	SET gaming_game_rounds.is_cancelled = 1
	WHERE gaming_game_rounds.game_round_id=gameRoundID;

	-- update gaming_game_plays.is_cancelled = true if master record from gaming_game_rounds is cancelled
	UPDATE gaming_game_plays 
	SET is_cancelled = 1 
	WHERE game_play_id = gamePlayID;
    
  END IF;

  CALL PromotionSBCancelBetContribution(sbBetID);

  SET statusCode=0;

END root$$

DELIMITER ;

