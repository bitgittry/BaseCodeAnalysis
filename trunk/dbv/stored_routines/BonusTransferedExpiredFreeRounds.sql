DROP procedure IF EXISTS `BonusTransferedExpiredFreeRounds`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusTransferedExpiredFreeRounds`(CWFreeRoundCounterID BIGINT)
BEGIN
	-- Updating client stats correctly

	UPDATE gaming_cw_free_rounds FORCE INDEX (cw_free_round_counter_id)
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_cw_free_rounds.cw_free_round_id = gaming_bonus_instances.cw_free_round_id
	STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_bonus_instances.client_stat_id
	STRAIGHT_JOIN gaming_operators ON is_main_operator=1
	STRAIGHT_JOIN gaming_operator_currency ON gaming_operators.operator_id = gaming_operator_currency.operator_id AND gaming_operator_currency.currency_id = gaming_client_stats.currency_id 
	STRAIGHT_JOIN gaming_cw_free_round_statuses ON gaming_cw_free_round_statuses.name = 'FinishedAndTransfered' 
	LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
	LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
	SET 
		gaming_cw_free_rounds.cw_free_round_status_id = gaming_cw_free_round_statuses.cw_free_round_status_id,
		gaming_cw_free_rounds.free_rounds_remaining=LEAST(@free_rounds_remaining:=gaming_cw_free_rounds.free_rounds_remaining, 0),
        
		gaming_client_stats.current_free_rounds_num=gaming_client_stats.current_free_rounds_num-@free_rounds_remaining,
		gaming_client_stats.current_free_rounds_win_locked=gaming_client_stats.current_free_rounds_win_locked-gaming_cw_free_rounds.win_total,
        gaming_client_stats.current_free_rounds_amount=gaming_client_stats.current_free_rounds_amount-(@free_rounds_remaining*gaming_cw_free_rounds.cost_per_round),
	
		date_transfered = NOW(),
		bonus_amount_given = win_total,
		bonus_amount_remaining = win_total,
		bonus_wager_requirement = win_total * gaming_cw_free_rounds.wager_requirement_multiplier,
		bonus_wager_requirement_remain = win_total * gaming_cw_free_rounds.wager_requirement_multiplier,
		is_free_rounds_mode = 0,
		gaming_cw_free_rounds.is_active=0,
		gaming_client_stats.current_bonus_balance=current_bonus_balance+win_total,
		gaming_client_stats.total_bonus_awarded=gaming_client_stats.total_bonus_awarded+win_total,
		gaming_client_stats.total_bonus_awarded_base=gaming_client_stats.total_bonus_awarded_base+ROUND(win_total/exchange_rate, 5),
		gaming_client_stats.current_free_rounds_num = 0,
		gaming_client_stats.current_free_rounds_amount = 0,
		gaming_bonus_instances.is_active = IF(win_total=0,0,1),
		transfer_every_x = IF (gaming_bonus_types_release.name = 'EveryReleaseAmount',ROUND(gaming_cw_free_rounds.wager_requirement_multiplier/(win_total/wager_restrictions.release_every_amount),2),transfer_every_x),
		transfer_every_amount = IF(gaming_bonus_types_release.name = 'EveryXWager',ROUND(win_total/(gaming_cw_free_rounds.wager_requirement_multiplier/transfer_every_x_wager), 0),transfer_every_amount)
	WHERE gaming_cw_free_rounds.cw_free_round_counter_id = CWFreeRoundCounterID;

	UPDATE gaming_cw_free_rounds FORCE INDEX (cw_free_round_counter_id)
	STRAIGHT_JOIN gaming_bonus_instances FORCE INDEX (cw_free_round_id) ON gaming_cw_free_rounds.cw_free_round_id = gaming_bonus_instances.cw_free_round_id AND
		gaming_bonus_instances.bonus_amount_remaining=0
    SET gaming_bonus_instances.is_active=0
    WHERE gaming_cw_free_rounds.cw_free_round_counter_id = CWFreeRoundCounterID;

	INSERT INTO gaming_transactions
	(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, extra2_id, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus,amount_free_round,amount_free_round_win, balance_free_round_after, balance_free_round_win_after) 
	SELECT gaming_payment_transaction_type.payment_transaction_type_id, bonus_amount_given, ROUND(bonus_amount_given/exchange_rate, 5), gaming_client_stats.currency_id, exchange_rate, 0, bonus_amount_given, 0, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, pending_bets_real, pending_bets_bonus,
	withdrawal_pending_amount,0,(gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus),0,-bonus_amount_given, gaming_client_stats.current_free_rounds_amount, gaming_client_stats.current_free_rounds_win_locked
	FROM gaming_cw_free_rounds  
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.cw_free_round_id = gaming_cw_free_rounds.cw_free_round_id AND gaming_bonus_instances.bonus_amount_given>0
	STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='BonusAwarded'
	STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=gaming_bonus_instances.client_stat_id 
	STRAIGHT_JOIN gaming_operators ON is_main_operator=1
	STRAIGHT_JOIN gaming_operator_currency ON gaming_operators.operator_id = gaming_operator_currency.operator_id AND gaming_operator_currency.currency_id = gaming_client_stats.currency_id 
	WHERE gaming_cw_free_rounds.cw_free_round_counter_id=CWFreeRoundCounterID;

	SET @BeforeInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays); 

	INSERT INTO gaming_game_plays 
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,IF(@IsFreeBonus OR @awardingType = 'FreeBet',amount_bonus,0) ,timestamp, gaming_transactions.client_id, gaming_transactions.client_stat_id, gaming_transactions.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, gaming_transactions.session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
	FROM gaming_cw_free_rounds FORCE INDEX (cw_free_round_counter_id)
    STRAIGHT_JOIN gaming_bonus_instances FORCE INDEX (cw_free_round_id) ON gaming_bonus_instances.cw_free_round_id = gaming_cw_free_rounds.cw_free_round_id
	STRAIGHT_JOIN gaming_transactions FORCE INDEX (extra_id) ON gaming_transactions.extra_id = gaming_bonus_instances.bonus_instance_id 
    STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_transactions.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id AND gaming_payment_transaction_type.name='BonusAwarded'
    WHERE gaming_cw_free_rounds.cw_free_round_counter_id=CWFreeRoundCounterID;

	SET @AfterInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays);


	INSERT INTO 	gaming_game_play_ring_fenced 
				(game_play_id,ring_fenced_sb_after,ring_fenced_casino_after,ring_fenced_poker_after,ring_fenced_pb_after)
	SELECT 		game_play_id, current_ring_fenced_sb, current_ring_fenced_casino, current_ring_fenced_poker, 0
	FROM			gaming_client_stats
				JOIN gaming_game_plays ON gaming_client_stats.client_stat_id = gaming_game_plays.client_stat_id
					AND game_play_id BETWEEN @BeforeInsert AND @AfterInsert
	ON DUPLICATE KEY UPDATE   
		`ring_fenced_sb_after`=values(`ring_fenced_sb_after`), 
		`ring_fenced_casino_after`=values(`ring_fenced_casino_after`),  
		`ring_fenced_poker_after`=values(`ring_fenced_poker_after`), 
		`ring_fenced_pb_after`=values(`ring_fenced_pb_after`);

	UPDATE gaming_bonus_rules
	JOIN (
		SELECT gaming_bonus_instances.bonus_rule_id, SUM(bonus_amount_given/gaming_operator_currency.exchange_rate) AS bonus_amount_given  
		FROM gaming_bonus_instances 
		JOIN gaming_cw_free_rounds ON gaming_bonus_instances.cw_free_round_id = gaming_cw_free_rounds.cw_free_round_id
		JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=gaming_bonus_instances.client_stat_id 
		JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
		JOIN gaming_operators ON gaming_operators.is_main_operator=1 AND gaming_operator_currency.operator_id=gaming_operators.operator_id
		WHERE cw_free_round_counter_id=CWFreeRoundCounterID
		GROUP BY bonus_rule_id
	) AS bonus_rule_sums ON gaming_bonus_rules.bonus_rule_id=bonus_rule_sums.bonus_rule_id
	SET gaming_bonus_rules.awarded_total=gaming_bonus_rules.awarded_total+bonus_rule_sums.bonus_amount_given;


END$$

DELIMITER ;

