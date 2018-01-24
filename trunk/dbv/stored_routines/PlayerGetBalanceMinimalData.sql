DROP procedure IF EXISTS `PlayerGetBalanceMinimalData`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetBalanceMinimalData`(clientStatID BIGINT)
BEGIN
-- Committing to DBV
  SELECT gaming_client_stats.client_stat_id, gaming_client_stats.client_id, gaming_clients.ext_client_id, total_real_played, gaming_client_stats.total_wallet_real_played, gaming_client_stats.total_wallet_real_played_online, gaming_client_stats.total_wallet_real_played_retail, gaming_client_stats.total_wallet_real_played_self_service, total_bonus_played, total_bonus_win_locked_played, total_real_won, 
	gaming_client_stats.total_wallet_real_won, gaming_client_stats.total_wallet_real_won_online, gaming_client_stats.total_wallet_real_won_retail, gaming_client_stats.total_wallet_real_won_self_service, gaming_client_stats.total_cash_played, gaming_client_stats.total_cash_played_retail, gaming_client_stats.total_cash_played_self_service, 
	gaming_client_stats.total_cash_win, gaming_client_stats.total_cash_win_paid_retail, gaming_client_stats.total_cash_win_paid_self_service, 
	total_bonus_won, total_bonus_win_locked_won, gaming_client_stats.total_loyalty_points_given, gaming_client_stats.total_loyalty_points_used, gaming_client_stats.current_loyalty_points, gaming_client_stats.loyalty_points_running_total, gaming_client_stats.total_loyalty_points_given_bonus, gaming_client_stats.total_loyalty_points_used_bonus,
    total_bonus_transferred, total_bonus_win_locked_transferred, total_adjustments, total_jackpot_contributions, 
    current_real_balance - gaming_client_stats.current_ring_fenced_amount- gaming_client_stats.current_ring_fenced_sb- gaming_client_stats.current_ring_fenced_casino- gaming_client_stats.current_ring_fenced_poker AS current_real_balance,
    current_bonus_balance AS current_bonus_balance, current_bonus_win_locked_balance, IFNULL(FreeBets.free_bet_balance,0) AS free_bet_balance,
    deposited_amount, withdrawn_amount, withdrawal_pending_amount, total_bonus_awarded, gaming_currency.currency_id, currency_code, 
    last_played_date, num_deposits, first_deposited_date, last_deposited_date, num_withdrawals, first_withdrawn_date, last_withdrawn_date, last_withdrawal_processed_date,
    gaming_client_stats.pending_bets_real, gaming_client_stats.pending_bets_bonus,gaming_client_stats.bet_from_real, gaming_client_stats.total_tax_paid, gaming_client_stats.total_tax_paid_bonus,
	gaming_client_stats.current_ring_fenced_amount, gaming_client_stats.current_ring_fenced_sb, gaming_client_stats.current_ring_fenced_casino, gaming_client_stats.current_ring_fenced_poker,
	CWFreeRounds.cw_free_rounds_balance, gaming_client_stats.pending_winning_real, gaming_client_stats.total_bad_debt,
	gaming_client_stats.total_free_rounds_played_amount, gaming_client_stats.total_free_rounds_win_transferred, gaming_client_stats.total_free_rounds_played_num, gaming_client_stats.current_free_rounds_num, 
	gaming_client_stats.current_free_rounds_win_locked, gaming_client_stats.current_free_rounds_amount,
	gaming_client_stats.max_player_balance_threshold, gaming_countries.max_player_balance_threshold AS country_max_balance_threshold,
	gaming_client_stats.deferred_tax, gaming_client_stats.locked_real_funds,
	deposited_charge_amount,
	withdrawn_charge_amount
  FROM gaming_client_stats FORCE INDEX (PRIMARY)
  JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  LEFT JOIN clients_locations ON clients_locations.client_id = gaming_clients.client_id
  LEFT JOIN gaming_countries ON gaming_countries.country_id = clients_locations.country_id
  LEFT JOIN
  (
    SELECT SUM(gaming_bonus_instances.bonus_amount_remaining) AS free_bet_balance 
    FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses) 
    JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id 
    JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id=gaming_bonus_rules.bonus_type_awarding_id AND gaming_bonus_types_awarding.name='FreeBet'
    WHERE gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active
  ) AS FreeBets ON 1=1
  LEFT JOIN
  (
	SELECT SUM(IFNULL(gcwfr.free_rounds_remaining * gcwfr.cost_per_round,0)) AS cw_free_rounds_balance 
    FROM gaming_cw_free_rounds AS gcwfr FORCE INDEX (player_with_status)
	JOIN gaming_cw_free_round_statuses gcwfrs ON gcwfrs.name NOT IN ('FinishedAndTransfered','Forfeited','Expired')
		AND gcwfr.client_stat_id = clientStatID AND gcwfr.cw_free_round_status_id = gcwfrs.cw_free_round_status_id
   ) AS CWFreeRounds ON 1=1
  WHERE gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1;
  
END$$

DELIMITER ;

