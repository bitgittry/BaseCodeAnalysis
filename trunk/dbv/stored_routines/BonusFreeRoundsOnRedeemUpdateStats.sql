DROP procedure IF EXISTS `BonusFreeRoundsOnRedeemUpdateStats`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusFreeRoundsOnRedeemUpdateStats`(bonusInstanceID BIGINT, paramGamePlayID BIGINT)
BEGIN

	DECLARE isFreeBonus TINYINT(1);
	DECLARE exchangeRate, ringFencedAmount DECIMAL(18,5);
	DECLARE awardingType VARCHAR(80);
	DECLARE cwFreeRoundID, transactionID, gamePlayID, bonusRuleID BIGINT;

	SELECT gaming_operator_currency.exchange_rate, gaming_bonus_types_awarding.name,cw_free_round_id, gaming_bonus_rules.bonus_rule_id, gaming_bonus_instances.current_ring_fenced_amount
	INTO exchangeRate, awardingType, cwFreeRoundID, bonusRuleID, ringFencedAmount
	FROM gaming_bonus_instances
	JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
	JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
	JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
	JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
	JOIN gaming_operators ON gaming_operators.is_main_operator=1 AND gaming_operator_currency.operator_id=gaming_operators.operator_id
	WHERE gaming_bonus_instances.bonus_instance_id=bonusInstanceID;

	UPDATE gaming_cw_free_rounds
	JOIN gaming_bonus_instances ON gaming_cw_free_rounds.cw_free_round_id = gaming_bonus_instances.cw_free_round_id
	JOIN gaming_cw_free_round_statuses ON (gaming_cw_free_rounds.win_total > 0 AND gaming_cw_free_round_statuses.name = 'FinishedAndTransfered') 
		OR (gaming_cw_free_rounds.win_total = 0 AND gaming_cw_free_round_statuses.name = 'UsedAll')
	JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id =gaming_client_stats.client_stat_id
	JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
	JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
	JOIN gaming_operators ON gaming_operators.is_main_operator=1 AND gaming_operator_currency.operator_id=gaming_operators.operator_id
	LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
    LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
	LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
	SET gaming_cw_free_rounds.cw_free_round_status_id = gaming_cw_free_round_statuses.cw_free_round_status_id,
		date_transfered = NOW(),
		bonus_amount_given = win_total,
		bonus_amount_remaining = win_total,
		bonus_wager_requirement = win_total * gaming_cw_free_rounds.wager_requirement_multiplier,
		bonus_wager_requirement_remain = win_total * gaming_cw_free_rounds.wager_requirement_multiplier,
		current_free_rounds_win_locked = current_free_rounds_win_locked - win_total,
        gaming_client_stats.current_ring_fenced_casino = current_ring_fenced_casino-IF(win_total=0 AND ring_fenced_by_license_type = 1, gaming_bonus_instances.current_ring_fenced_amount,0),
		gaming_client_stats.current_ring_fenced_amount = gaming_client_stats.current_ring_fenced_amount-IF(win_total=0 AND ring_fenced_by_bonus_rules = 1, gaming_bonus_instances.current_ring_fenced_amount,0),
		is_free_rounds_mode = 0,
		gaming_cw_free_rounds.is_active=0,
		gaming_bonus_instances.is_active = IF(win_total=0,0,1),
		is_used_all = IF(win_total=0,1,0),
		used_all_date = IF(win_total=0,NOW(),NULL),
		gaming_client_stats.current_bonus_balance=current_bonus_balance+win_total,
		gaming_client_stats.total_bonus_awarded=gaming_client_stats.total_bonus_awarded+win_total,
		gaming_client_stats.total_bonus_awarded_base=gaming_client_stats.total_bonus_awarded_base+ROUND(win_total/exchange_rate, 5),
		transfer_every_x = IF (gaming_bonus_types_release.name = 'EveryReleaseAmount',ROUND(gaming_cw_free_rounds.wager_requirement_multiplier/(win_total/wager_restrictions.release_every_amount),2),transfer_every_x),
		transfer_every_amount = IF(gaming_bonus_types_release.name = 'EveryXWager',ROUND(win_total/(gaming_cw_free_rounds.wager_requirement_multiplier/transfer_every_x_wager), 0),transfer_every_amount),
		gaming_client_stats.total_free_rounds_win_transferred = total_free_rounds_win_transferred + win_total
	WHERE bonus_instance_id = bonusInstanceID;


	INSERT INTO gaming_transactions
	(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, extra2_id, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus,amount_free_round,amount_free_round_win, balance_free_round_after, balance_free_round_win_after) 
	SELECT gaming_payment_transaction_type.payment_transaction_type_id, bonus_amount_given, ROUND(bonus_amount_given/exchangeRate, 5), gaming_client_stats.currency_id, exchangeRate, 0, bonus_amount_given, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, pending_bets_real, pending_bets_bonus,
	withdrawal_pending_amount,0,(gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus),0,-bonus_amount_given, gaming_client_stats.current_free_rounds_amount, gaming_client_stats.current_free_rounds_win_locked
	FROM gaming_bonus_instances  
	JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='BonusAwarded'
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=gaming_bonus_instances.client_stat_id 
	WHERE gaming_bonus_instances.bonus_instance_id=bonusInstanceID; 

	SET transactionID=LAST_INSERT_ID();

	INSERT INTO gaming_game_plays 
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_bonus ,timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
	FROM gaming_transactions
	WHERE transaction_id=transactionID;

	SET gamePlayID = LAST_INSERT_ID();
    
    INSERT INTO gaming_game_plays_bonus_instances (game_play_id, bonus_instance_id, bonus_rule_id, client_stat_id, timestamp, exchange_rate, bet_real,bet_ring_fenced, bet_bonus, bet_bonus_win_locked,
        wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_wager_requirement_remain_after,bonus_order,ring_fence_only, bonus_transfered_total,
        win_bonus, win_bonus_win_locked,  win_real, win_ring_fenced, lost_win_bonus, lost_win_bonus_win_locked,ring_fenced_transfered)
	SELECT paramGamePlayID, bonusInstanceID, bonusRuleID, client_stat_id, timestamp, exchange_rate, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, amount_bonus, 0, 0, 0, 0, 0, IF (amount_bonus = 0,ringFencedAmount,0)
    FROM gaming_game_plays
    WHERE game_play_id = gamePlayID;

	INSERT INTO 	gaming_game_play_ring_fenced 
				(game_play_id,ring_fenced_sb_after,ring_fenced_casino_after,ring_fenced_poker_after,ring_fenced_pb_after)
	SELECT 		game_play_id, current_ring_fenced_sb, current_ring_fenced_casino, current_ring_fenced_poker, 0
	FROM			gaming_client_stats
				JOIN gaming_game_plays ON gaming_client_stats.client_stat_id = gaming_game_plays.client_stat_id
					AND game_play_id = gamePlayID
	ON DUPLICATE KEY UPDATE   
		`ring_fenced_sb_after`=values(`ring_fenced_sb_after`), 
		`ring_fenced_casino_after`=values(`ring_fenced_casino_after`),  
		`ring_fenced_poker_after`=values(`ring_fenced_poker_after`), 
		`ring_fenced_pb_after`=values(`ring_fenced_pb_after`);

	INSERT INTO gaming_game_plays_cw_free_rounds (game_play_id,amount_free_round,amount_free_round_win,balance_free_round_after,balance_free_round_win_after,cw_free_round_id)
	SELECT gamePlayID,amount_free_round,amount_free_round_win,balance_free_round_after,balance_free_round_win_after,cwFreeRoundID
	FROM gaming_transactions
	WHERE transaction_id=transactionID;

	COMMIT AND CHAIN;

	UPDATE gaming_bonus_rules 
	JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=bonusInstanceID AND gaming_bonus_rules.bonus_rule_id=gaming_bonus_instances.bonus_rule_id
	SET gaming_bonus_rules.awarded_total=gaming_bonus_rules.awarded_total+(gaming_bonus_instances.bonus_amount_given/exchangeRate);

	COMMIT AND CHAIN;
    
END$$

DELIMITER ;

