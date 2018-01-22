DROP procedure IF EXISTS `PlayerGetBalance`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetBalance`(clientStatID BIGINT, balanceAccountActiveOnly TINYINT(1), minimalData TINYINT(1))
BEGIN 
  -- Removed Reference to gaming_bonus_free_rounds 
  --  balance account attributes with left join 
  

  DECLARE bonusEnabledFlag, promotionEnabled, tournamentEnabled TINYINT(1) DEFAULT 0;
  DECLARE currencyID BIGINT DEFAULT NULL;
  

  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool
  INTO bonusEnabledFlag, promotionEnabled, tournamentEnabled
  FROM gaming_settings gs1 
  JOIN gaming_settings gs2 ON (gs2.name='IS_PROMOTION_ENABLED')
  JOIN gaming_settings gs3 ON (gs3.name='IS_TOURNAMENTS_ENABLED')
  WHERE gs1.name='IS_BONUS_ENABLED';
  SELECT currency_id INTO currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID;
  
  
  SET @client_stat_id=clientStatID;
  SELECT gaming_client_stats.client_stat_id, gaming_client_stats.client_id, gaming_clients.ext_client_id, total_real_played, gaming_client_stats.total_wallet_real_played, gaming_client_stats.total_wallet_real_played_online, gaming_client_stats.total_wallet_real_played_retail, gaming_client_stats.total_wallet_real_played_self_service,
	total_bonus_played, total_bonus_win_locked_played, total_real_won, gaming_client_stats.total_wallet_real_won, gaming_client_stats.total_wallet_real_won_online, gaming_client_stats.total_wallet_real_won_retail, gaming_client_stats.total_wallet_real_won_self_service, gaming_client_stats.total_cash_played, 
	gaming_client_stats.total_cash_played_retail, gaming_client_stats.total_cash_played_self_service, 
	gaming_client_stats.total_cash_win, gaming_client_stats.total_cash_win_paid_retail, gaming_client_stats.total_cash_win_paid_self_service, total_bonus_won, total_bonus_win_locked_won, 
    gaming_client_stats.total_loyalty_points_given, gaming_client_stats.total_loyalty_points_used, gaming_client_stats.current_loyalty_points, 
	gaming_client_stats.loyalty_points_running_total, gaming_clients.vip_level,
    gaming_client_stats.total_loyalty_points_given_bonus, gaming_client_stats.total_loyalty_points_used_bonus,
    total_bonus_transferred, total_bonus_win_locked_transferred, total_adjustments, total_jackpot_contributions, 
    current_real_balance - gaming_client_stats.current_ring_fenced_amount- gaming_client_stats.current_ring_fenced_sb- gaming_client_stats.current_ring_fenced_casino- gaming_client_stats.current_ring_fenced_poker AS current_real_balance,
	current_bonus_balance AS current_bonus_balance, current_bonus_win_locked_balance, IFNULL(FreeBets.free_bet_balance,0) AS free_bet_balance,
    deposited_amount, withdrawn_amount, withdrawal_pending_amount, total_bonus_awarded, gaming_currency.currency_id, currency_code, 
    last_played_date, num_deposits, first_deposited_date, last_deposited_date, balanceHist.processed_datetime as last_deposited_processed_date, num_withdrawals, first_withdrawn_date, last_withdrawn_date, last_withdrawal_processed_date,
    gaming_client_stats.pending_bets_real, gaming_client_stats.pending_bets_bonus, gaming_client_stats.bet_from_real, gaming_client_stats.total_tax_paid, gaming_client_stats.total_tax_paid_bonus,
    CS.session_id, CS.total_bet AS session_bet, CS.total_win AS session_win, CS.bets AS session_bets,  
    GS.game_session_id, GS.total_bet AS game_session_bet, GS.total_win AS game_session_win, GS.bets AS game_session_bets,
	gaming_client_stats.current_ring_fenced_amount, gaming_client_stats.current_ring_fenced_sb, gaming_client_stats.current_ring_fenced_casino, gaming_client_stats.current_ring_fenced_poker,
	gaming_client_stats.chargeback_amount, gaming_client_stats.chargeback_amount_base, gaming_client_stats.chargeback_count, gaming_client_stats.chargeback_reversal_amount,
	gaming_client_stats.chargeback_reversal_amount_base, gaming_client_stats.chargeback_reversal_count, gaming_client_stats.current_free_rounds_amount, gaming_client_stats.total_free_rounds_played_amount, 
	gaming_client_stats.total_free_rounds_win_transferred, gaming_client_stats.total_free_rounds_played_num, gaming_client_stats.current_free_rounds_num, gaming_client_stats.current_free_rounds_win_locked,
	gaming_client_stats.pending_winning_real, gaming_client_stats.total_bad_debt,gaming_client_stats.max_player_balance_threshold,gaming_countries.max_player_balance_threshold AS country_max_balance_threshold,
    CWFreeRounds.cw_free_rounds_balance,
	gaming_client_stats.deferred_tax,gaming_client_stats.locked_real_funds,
	TAX.total_deferred_tax,
	deposited_charge_amount,
	withdrawn_charge_amount
  FROM gaming_client_stats 
  JOIN gaming_currency ON gaming_client_stats.client_stat_id=@client_stat_id AND gaming_client_stats.is_active=1 AND gaming_client_stats.currency_id=gaming_currency.currency_id
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  LEFT JOIN clients_locations ON clients_locations.client_id = gaming_clients.client_id
  LEFT JOIN gaming_countries ON gaming_countries.country_id = clients_locations.country_id
  LEFT JOIN 
  (
    SELECT gaming_client_sessions.session_id, total_bet, total_win, bets
    FROM gaming_client_sessions FORCE INDEX(client_open_sessions)
    WHERE gaming_client_sessions.client_stat_id=@client_stat_id AND gaming_client_sessions.is_open=0 
    ORDER BY gaming_client_sessions.session_id DESC
    LIMIT 1
  ) AS CS ON 1=1
  LEFT JOIN 
  (
    SELECT game_session_id, total_bet, total_win, bets
    FROM gaming_game_sessions FORCE INDEX(client_open_sessions)
    WHERE gaming_game_sessions.client_stat_id=@client_stat_id AND gaming_game_sessions.is_open=0
    ORDER BY gaming_game_sessions.game_session_id DESC
    LIMIT 1
  ) AS GS ON 1=1
  LEFT JOIN
  (
    SELECT SUM(gaming_bonus_instances.bonus_amount_remaining) AS free_bet_balance 
    FROM gaming_bonus_instances  FORCE INDEX (client_active_bonuses) 
    JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id 
    JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id=gaming_bonus_rules.bonus_type_awarding_id AND gaming_bonus_types_awarding.name='FreeBet'
    WHERE gaming_bonus_instances.client_stat_id=@client_stat_id AND gaming_bonus_instances.is_active
  ) AS FreeBets ON 1=1
  LEFT JOIN
  (
	SELECT SUM(IFNULL(gcwfr.free_rounds_remaining * gcwfr.cost_per_round,0)) AS cw_free_rounds_balance 
    FROM gaming_cw_free_rounds AS gcwfr FORCE INDEX (player_with_status)
	JOIN gaming_cw_free_round_statuses gcwfrs ON gcwfrs.name NOT IN ('FinishedAndTransfered','Forfeited','Expired')
		AND gcwfr.client_stat_id = @client_stat_id AND gcwfr.cw_free_round_status_id = gcwfrs.cw_free_round_status_id
   ) AS CWFreeRounds ON 1=1
  LEFT JOIN
  (
	SELECT IFNULL(SUM(deferred_tax_amount),0) AS total_deferred_tax 
    FROM gaming_tax_cycles FORCE INDEX (client_stat_id)
    WHERE client_stat_id = @client_stat_id AND is_active = 0
   ) as TAX ON 1=1
   LEFT JOIN 
  (
    SELECT processed_datetime 
    FROM gaming_balance_history
	WHERE  gaming_balance_history.client_stat_id= @client_stat_id AND payment_transaction_type_id=1 
	ORDER BY processed_datetime DESC limit 1
  ) as balanceHist on 1=1;
  

  IF (bonusEnabledFlag) THEN
    IF (minimalData) THEN
      SELECT bonus.bonus_instance_id, bonus.priority, bonus_amount_given, bonus_amount_remaining, total_amount_won, current_win_locked_amount, 
        bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, secured_date, lost_date, used_all_date, 
        bonus.is_secured, bonus.is_lost, bonus.is_used_all, bonus.is_active, 
        bonus.bonus_rule_id, gaming_bonus_rules.name AS bonus_name, gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_types.name AS bonus_type, bonus.client_stat_id, bonus.extra_id,
        bonus_transfered_total, transfer_every_x, transfer_every_amount, transfer_every_x_last,
        NULL AS reason,current_ring_fenced_amount, gaming_bonus_rules.is_generic,bonus.is_free_rounds,bonus.is_free_rounds_mode,bonus.cw_free_round_id
      FROM gaming_bonus_instances AS bonus
      JOIN gaming_bonus_rules ON bonus.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	  JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id = gaming_bonus_types.bonus_type_id
      WHERE bonus.client_stat_id=@client_stat_id AND bonus.is_active=1
      ORDER BY bonus.bonus_instance_id ASC;
      -- ORDER BY given_date, bonus_rule_id;
    ELSE
      SELECT bonus.bonus_instance_id, bonus.priority, bonus_amount_given, bonus_amount_remaining, total_amount_won, current_win_locked_amount, 
        bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, secured_date, lost_date, used_all_date, 
        bonus.is_secured, bonus.is_lost, bonus.is_used_all, bonus.is_active, 
		bonus.bonus_rule_id, gaming_bonus_rules.name AS bonus_name, gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_types.name AS bonus_type, bonus.client_stat_id, bonus.extra_id,
        bonus_transfered_total, transfer_every_x, transfer_every_amount, transfer_every_x_last,current_ring_fenced_amount,
      CASE gaming_bonus_types.name 
        WHEN 'Manual' THEN CONCAT('User: ', manual_user.username, ', Reason: ', bonus.reason)
        WHEN 'Login' THEN CONCAT('Logged In On: ', login_session.date_open)
        WHEN 'Deposit' THEN CONCAT('Deposited On: ', deposit_transaction.timestamp, ' , Amount: ', ROUND(deposit_transaction.amount/100, 2)) 
        WHEN 'DirectGive' THEN CONCAT('')
        WHEN 'FreeRound' THEN CONCAT('')
        WHEN 'Reward' THEN CONCAT('')
        WHEN 'BonusForPromotion' THEN CONCAT('Promotion Prize: ',gaming_promotions.description)
      END AS reason, gaming_bonus_rules.is_generic,bonus.is_free_rounds,bonus.is_free_rounds_mode,bonus.cw_free_round_id
      FROM gaming_bonus_instances AS bonus FORCE INDEX (client_active_bonuses) 
      JOIN gaming_bonus_rules ON bonus.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
      JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id = gaming_bonus_types.bonus_type_id
      LEFT JOIN sessions_main AS manual_session ON gaming_bonus_types.name='Manual' AND bonus.extra_id=manual_session.session_id
      LEFT JOIN users_main AS manual_user ON manual_session.user_id=manual_user.user_id
      LEFT JOIN sessions_main AS login_session ON gaming_bonus_types.name='Login' AND bonus.extra_id=login_session.session_id   
      LEFT JOIN gaming_balance_history AS deposit_transaction ON gaming_bonus_types.name='Deposit' AND bonus.extra_id=deposit_transaction.balance_history_id
      LEFT JOIN gaming_promotions ON gaming_bonus_types.name='BonusForPromotion' AND bonus.extra_id=gaming_promotions.promotion_id  
      WHERE bonus.client_stat_id=@client_stat_id AND bonus.is_active=1
      ORDER BY bonus.bonus_instance_id ASC;
      -- Type 2: ORDER BY bonus.bonus_instance_id ASC;
      -- Type 1: ORDER BY gaming_bonus_types_awarding.`order` ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date ASC, gaming_bonus_instances.bonus_instance_id ASC;
    END IF;
    
    SELECT NUll;
  ELSE
    SELECT NULL;
    SELECT NULL;
  END IF;
  
  
  IF (promotionEnabled) THEN
    CALL PromotionGetAllPlayerPromotionStatusFilterByDateType('CURRENT+FUTURE', @client_stat_id, currencyID, 1, 0, NULL);
  ELSE
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
	SELECT NULL;
    SELECT NULL;
  END IF;
  
  IF (tournamentEnabled) THEN
    SELECT tournament_player_status_id, gaming_tournaments.tournament_id, gaming_tournaments.name AS tournament_name, player_statuses.total_bet, player_statuses.total_win, player_statuses.rounds, player_statuses.score, player_statuses.rank, opted_in_date, player_statuses.is_active, player_statuses.priority,
        gaming_tournaments.tournament_date_start AS tournament_start_date,  gaming_tournaments.tournament_date_end AS tournament_end_date, gaming_tournaments.tournament_date_end<NOW() AS has_expired
		, player_statuses.last_updated_date, player_statuses.previous_rank, gaming_tournaments.last_temp_rank_update_date
    FROM gaming_tournament_player_statuses AS player_statuses  
    JOIN gaming_tournaments ON player_statuses.tournament_id=gaming_tournaments.tournament_id AND gaming_tournaments.tournament_date_end>NOW()
    WHERE player_statuses.client_stat_id=@client_stat_id AND player_statuses.is_active;
  ELSE
    SELECT NULL;
  END IF;
  
  
  SET @nonInternalOnly=1;
  SELECT gaming_balance_accounts.balance_account_id, IFNULL(gaming_payment_method_sub.payment_method_id, gaming_payment_method.payment_method_id) AS payment_method_id, gaming_payment_method.name AS payment_method_name, gaming_payment_method_sub.name AS payment_method_sub_name,
		IFNULL(gaming_payment_method_sub.display_name, gaming_payment_method.display_name) AS payment_method, account_reference, 
		date_created, date_last_used, kyc_checked, gaming_balance_accounts.is_active, unique_transaction_id_last, deposited_amount, withdrawn_amount, withdrawal_pending_amount, cc_holder_name, expiry_date, fraud_checkable, 
		gaming_balance_accounts.can_withdraw, gaming_payment_method.can_withdraw AS method_can_withdraw, gaming_balance_accounts.is_default, gaming_balance_accounts.is_internal, gaming_balance_accounts.player_token, 
		gaming_payment_gateways.payment_gateway_id, gaming_payment_gateways.name AS payment_gateway,
    gaming_balance_accounts.is_default_withdrawal, gbaa.attr_value AS customer_reference_number
  FROM gaming_balance_accounts
  LEFT JOIN gaming_balance_account_attributes gbaa ON gbaa.balance_account_id = gaming_balance_accounts.balance_account_id AND gbaa.attr_name = 'crn'
  JOIN gaming_payment_method ON gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id 
  LEFT JOIN gaming_payment_method AS gaming_payment_method_sub ON gaming_balance_accounts.sub_payment_method_id=gaming_payment_method_sub.payment_method_id  
  LEFT JOIN gaming_payment_gateways ON gaming_payment_gateways.payment_gateway_id=gaming_balance_accounts.payment_gateway_id
  WHERE gaming_balance_accounts.client_stat_id=@client_stat_id AND (balanceAccountActiveOnly=0 OR gaming_balance_accounts.is_active=1) AND (@nonInternalOnly=0 OR gaming_balance_accounts.is_internal=0);

	SELECT gba.balance_account_id, IFNULL(pgma2.attr_name, gbaa.attr_name) AS attr_name, IFNULL(gbaa.attr_value, pgma.attr_default_value) AS attr_value
	FROM gaming_balance_accounts AS gba FORCE INDEX (client_stat_id)
	STRAIGHT_JOIN gaming_payment_method AS gpm ON gba.sub_payment_method_id=gpm.payment_method_id
	STRAIGHT_JOIN payment_methods AS pm ON pm.name=gpm.payment_gateway_method_name AND 
		((gpm.sub_name IS NULL AND pm.sub_name IS NULL) OR pm.sub_name=gpm.payment_gateway_method_sub_name)
	STRAIGHT_JOIN payment_profiles AS pp ON pm.payment_profile_id=pp.payment_profile_id
	LEFT JOIN gaming_payment_gateways ON gba.payment_gateway_id=gaming_payment_gateways.payment_gateway_id
	LEFT JOIN payment_gateways AS pg ON pg.payment_gateway_id=IFNULL(gaming_payment_gateways.payment_gateway_ref, pp.payment_gateway_id)
	LEFT JOIN payment_gateway_methods AS pgm ON pgm.payment_gateway_id=pg.payment_gateway_id AND pgm.payment_method_id=pm.payment_method_id	
	LEFT JOIN payment_gateway_methods_attributes AS pgma ON pgm.payment_gateway_method_id=pgma.payment_gateway_method_id
	LEFT JOIN payment_gateway_method_attributes AS pgma2 ON pgma2.attr_name = pgma.attr_name
	LEFT JOIN gaming_balance_account_attributes AS gbaa ON gba.balance_account_id=gbaa.balance_account_id AND gbaa.attr_name=pgma2.attr_name
    WHERE gba.client_stat_id=@client_stat_id AND (balanceAccountActiveOnly=0 OR gba.is_active=1) AND (@nonInternalOnly=0 OR gba.is_internal=0) 
		AND IFNULL(pgma2.attr_name, gbaa.attr_name) IS NOT NULL;


	SELECT sum(b.deposited_amount) as depositedamount from  gaming_balance_accounts b, gaming_payment_method p WHERE p.payment_method_id = b.payment_method_id  
		AND p.wager_before_withdrawal = 0  AND b.client_stat_id = clientStatID;

END$$

DELIMITER ;

