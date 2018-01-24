DROP procedure IF EXISTS `BonusGiveBulkCashBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGiveBulkCashBonus`(bonusBulkCounterID BIGINT, sessionID BIGINT, OUT statusCode INT)
root: BEGIN
  
	DECLARE bonusEnabledFlag,bonusBulkAuthorization TINYINT(1) DEFAULT 0;
	DECLARE bonusRuleIDCheck, clientStatIDCheck, CounterID, playerSelectionID,bonusRuleAwardCounterID,transactionCounterID BIGINT DEFAULT -1;
	DECLARE minAmount, maxAmount DECIMAL(18,5) DEFAULT 0;
	DECLARE playerInSelection, validWagerReq, validDaysFromAwarding, validDateFixed, validAmount, bonusPreAuth,isFreeBonus TINYINT(1) DEFAULT 0;
	DECLARE numToAward, awardedTimes INT DEFAULT 0;
	DECLARE awardedTimesThreshold INT DEFAULT NULL;

	SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
	SELECT value_bool INTO bonusBulkAuthorization FROM gaming_settings WHERE name='BONUS_BULK_GIVE_AUTHORIZATION';
	SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';


	IF NOT (bonusEnabledFlag) THEN
		SET statusCode=1;
		LEAVE root;
	END IF;

	SELECT gaming_bonus_rules.bonus_rule_id,player_selection_id,is_free_bonus INTO bonusRuleIDCheck,playerSelectionID, isFreeBonus
	FROM gaming_bonus_bulk_counter
	JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id= gaming_bonus_bulk_counter.bonus_rule_id
	JOIN gaming_bonus_rules_manuals ON gaming_bonus_rules_manuals.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	WHERE bonus_bulk_counter_id = bonusBulkCounterID;

	IF (bonusRuleIDCheck = -1) THEN
		SET statusCode=2;
		LEAVE root;
	END IF;

	SELECT gaming_bonus_rules.awarded_times, gaming_bonus_rules.awarded_times_threshold 
	INTO awardedTimes, awardedTimesThreshold
	FROM gaming_bonus_rules 
	WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleIDCheck;
 
	IF (awardedTimesThreshold IS NOT NULL) THEN

		SELECT COUNT(*) INTO numToAward FROM gaming_bonus_bulk_players WHERE bonus_bulk_counter_id = bonusBulkCounterID;
		IF (numToAward > (awardedTimesThreshold - awardedTimes)) THEN
			SET statusCode = 3;
			LEAVE root;
		END IF;

	END IF;

	UPDATE gaming_bonus_bulk_players
	SET is_invalid =1
	WHERE bonus_bulk_counter_id = bonusBulkCounterID AND is_given=0;

	UPDATE gaming_bonus_bulk_players
	LEFT JOIN gaming_client_stats ON gaming_bonus_bulk_players.client_stat_id = gaming_client_stats.client_stat_id
	LEFT JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = bonusRuleIDCheck
	LEFT JOIN gaming_bonus_rules_manuals ON gaming_bonus_rules_manuals.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	LEFT JOIN gaming_bonus_rules_manuals_amounts ON gaming_bonus_rules_manuals.bonus_rule_id = gaming_bonus_rules_manuals_amounts.bonus_rule_id AND gaming_client_stats.currency_id = gaming_bonus_rules_manuals_amounts.currency_id
	LEFT JOIN gaming_player_selections_player_cache AS CS ON CS.player_selection_id=gaming_bonus_rules.player_selection_id AND CS.player_in_selection=1 AND CS.client_stat_id = gaming_client_stats.client_stat_id
		SET 
		invalid_wager = IF (gaming_bonus_bulk_players.wagering_requirment_multiplier BETWEEN gaming_bonus_rules_manuals.min_wager_requirement_multiplier AND gaming_bonus_rules_manuals.max_wager_requirement_multiplier,0,1),
		invalid_amount = IF (gaming_bonus_bulk_players.amount BETWEEN gaming_bonus_rules_manuals_amounts.min_amount AND gaming_bonus_rules_manuals_amounts.max_amount,0,1),
		invalid_expiry = IF (
				(
					(
						gaming_bonus_bulk_players.expirey_days_from_awarding IS NOT NULL AND 
						 IF(gaming_bonus_rules_manuals.min_expiry_days_from_awarding IS NOT NULL,
								gaming_bonus_bulk_players.expirey_days_from_awarding BETWEEN gaming_bonus_rules_manuals.min_expiry_days_from_awarding AND gaming_bonus_rules_manuals.max_expiry_days_from_awarding,
								DATE_ADD(NOW(), INTERVAL gaming_bonus_bulk_players.expirey_days_from_awarding DAY) BETWEEN gaming_bonus_rules_manuals.min_expiry_date_fixed AND gaming_bonus_rules_manuals.max_expiry_date_fixed
							)
					) 
					OR 
					(
						gaming_bonus_bulk_players.expirey_date IS NOT NULL AND
						IF(gaming_bonus_rules_manuals.min_expiry_date_fixed IS NOT NULL,
							gaming_bonus_bulk_players.expirey_date BETWEEN gaming_bonus_rules_manuals.min_expiry_date_fixed AND gaming_bonus_rules_manuals.max_expiry_date_fixed,
							DATEDIFF(gaming_bonus_bulk_players.expirey_date ,NOW()) BETWEEN gaming_bonus_rules_manuals.min_expiry_days_from_awarding AND gaming_bonus_rules_manuals.max_expiry_days_from_awarding
						   )
					)
				) ,0,1),
		invalid_client = IF (gaming_client_stats.client_stat_id IS NULL,1,0),
		not_in_bonus_selection = IF (CS.client_stat_id IS NULL,1,0)
	WHERE bonus_bulk_counter_id = bonusBulkCounterID AND is_given=0;

	UPDATE gaming_bonus_bulk_players
	SET is_invalid =0
	WHERE bonus_bulk_counter_id = bonusBulkCounterID AND not_in_bonus_selection=0 AND invalid_client=0 AND invalid_expiry=0 AND invalid_amount = 0 AND invalid_wager =0;

	INSERT INTO gaming_bonus_rule_award_counter(bonus_rule_id, date_created)
	SELECT bonusRuleIDCheck, NOW();

	SET bonusRuleAwardCounterID=LAST_INSERT_ID();
  
	INSERT INTO gaming_bonus_instances 
		(priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, extra_id, reason, transfer_every_x, transfer_every_amount,bonus_rule_award_counter_id)
	SELECT 
		priority, gbbp.amount, gbbp.amount, IF(isFreeBonus,0,gbbp.amount*gbbp.wagering_requirment_multiplier),IF(isFreeBonus,0, gbbp.amount*gbbp.wagering_requirment_multiplier), NOW(),
		IFNULL(gbbp.expirey_date, DATE_ADD(NOW(), INTERVAL gbbp.expirey_days_from_awarding DAY)) AS expiry_date, gaming_bonus_rules.bonus_rule_id, gbbp.client_stat_id , sessionID, gbbp.reason,
		CASE gaming_bonus_types_release.name
			WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
			WHEN 'EveryReleaseAmount' THEN ROUND(gbbp.wagering_requirment_multiplier/(gbbp.amount/wager_restrictions.release_every_amount),2)
			ELSE NULL
		END,
		CASE gaming_bonus_types_release.name
			WHEN 'EveryXWager' THEN ROUND(gbbp.amount/(gbbp.wagering_requirment_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
			WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
			ELSE NULL
		END,
		bonusRuleAwardCounterID
	FROM gaming_bonus_rules 
	LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
	LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
	JOIN gaming_bonus_bulk_players AS gbbp ON gbbp.bonus_bulk_counter_id = bonusBulkCounterID AND is_invalid =0 AND (is_authorized || bonusBulkAuthorization =0) AND is_given =0
	JOIN gaming_client_stats ON gbbp.client_stat_id = gaming_client_stats.client_stat_id
	LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
	WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleIDCheck;
	 
	UPDATE gaming_bonus_bulk_players
	SET is_given=1  
	WHERE bonus_bulk_counter_id = bonusBulkCounterID AND is_invalid =0  AND (is_authorized || bonusBulkAuthorization =0) AND is_given=0;

	
	IF (ROW_COUNT() > 0) THEN

		INSERT INTO gaming_bonus_rule_award_counter_client_stats(bonus_rule_award_counter_id, bonus_instance_id, client_stat_id)
		SELECT bonusRuleAwardCounterID, gaming_bonus_instances.bonus_instance_id, gaming_client_stats.client_stat_id
		FROM gaming_client_stats 
		JOIN gaming_bonus_instances ON 
		gaming_bonus_instances.bonus_rule_award_counter_id=bonusRuleAwardCounterID AND 
		gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
		FOR UPDATE;

		CALL BonusOnAwardedUpdateStatsMultipleBonuses(bonusRuleAwardCounterID, 1);

		UPDATE gaming_client_stats   
		JOIN gaming_bonus_instances ON bonus_rule_award_counter_id=bonusRuleAwardCounterID AND gaming_bonus_instances.client_stat_id = gaming_client_stats.client_stat_id
		JOIN gaming_operators ON gaming_operators.is_main_operator=1
		JOIN gaming_operator_currency ON gaming_operators.operator_id=gaming_operator_currency.operator_id AND gaming_operator_currency.currency_id =gaming_client_stats.currency_id
		SET
		current_real_balance=current_real_balance+bonus_amount_remaining  + current_win_locked_amount, 
		total_bonus_transferred=total_bonus_transferred+bonus_amount_remaining  + current_win_locked_amount,
		current_bonus_balance=current_bonus_balance-bonus_amount_remaining, 
		total_bonus_win_locked_transferred=total_bonus_win_locked_transferred+current_win_locked_amount,
		current_bonus_win_locked_balance=current_bonus_win_locked_balance-current_win_locked_amount,
		total_bonus_transferred_base=total_bonus_transferred_base+ROUND(bonus_amount_remaining/exchange_rate, 5),
		gaming_client_stats.bet_from_real = 0;

		INSERT INTO gaming_transaction_counter (date_created,transaction_ref) VALUES (NOW(),'BulkCashBonus');

		SET transactionCounterID=LAST_INSERT_ID();

		INSERT INTO gaming_transactions
		(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, session_id, pending_bet_real, pending_bet_bonus,transaction_counter_id,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
		SELECT gaming_payment_transaction_type.payment_transaction_type_id, bonus_amount_remaining  + current_win_locked_amount, ROUND(bonus_amount_remaining  + current_win_locked_amount/exchange_rate, 5), gaming_client_stats.currency_id, exchange_rate, bonus_amount_remaining  + current_win_locked_amount, bonus_amount_remaining*-1, current_win_locked_amount*-1, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, NULL, 0, gaming_client_stats.pending_bets_real, gaming_client_stats.pending_bets_bonus,transactionCounterID,withdrawal_pending_amount,0, (gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`) 
		FROM gaming_client_stats  
		JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='CashBonus'
		JOIN gaming_bonus_instances ON bonus_rule_award_counter_id=bonusRuleAwardCounterID AND gaming_bonus_instances.client_stat_id = gaming_client_stats.client_stat_id
		JOIN gaming_operators ON gaming_operators.is_main_operator=1
		JOIN gaming_operator_currency ON gaming_operators.operator_id=gaming_operator_currency.operator_id AND gaming_operator_currency.currency_id =gaming_client_stats.currency_id;

		SET @BeforeInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays); 

		INSERT INTO gaming_game_plays 
		(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, bonus_lost, bonus_win_locked_lost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
		SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, 0, 0, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
		FROM gaming_transactions
		WHERE transaction_counter_id=transactionCounterID;
		
		SET @AfterInsert = (SELECT MAX(game_play_id) FROM gaming_game_plays);

		INSERT INTO 	gaming_game_play_ring_fenced 
						(game_play_id,ring_fenced_sb_after,ring_fenced_casino_after,ring_fenced_poker_after,ring_fenced_pb_after)
		SELECT 			game_play_id, current_ring_fenced_sb, current_ring_fenced_casino, current_ring_fenced_poker, 0
		FROM			gaming_client_stats
						JOIN gaming_game_plays ON gaming_client_stats.client_stat_id = gaming_game_plays.client_stat_id
							AND game_play_id BETWEEN @BeforeInsert AND @AfterInsert
		ON DUPLICATE KEY UPDATE   
		`ring_fenced_sb_after`=values(`ring_fenced_sb_after`), 
		`ring_fenced_casino_after`=values(`ring_fenced_casino_after`),  
		`ring_fenced_poker_after`=values(`ring_fenced_poker_after`), 
		`ring_fenced_pb_after`=values(`ring_fenced_pb_after`);
  
		INSERT INTO gaming_bonus_rules_rec_met (bonus_rule_id,bonus_transfered)
		SELECT bonus_rule_id,SUM(IFNULL(ROUND(bonus_amount_remaining  + current_win_locked_amount/exchange_rate, 0),0)) 
		FROM gaming_client_stats
		JOIN gaming_bonus_instances ON bonus_rule_award_counter_id=bonusRuleAwardCounterID AND gaming_bonus_instances.client_stat_id = gaming_client_stats.client_stat_id
		JOIN gaming_operators ON gaming_operators.is_main_operator=1
		JOIN gaming_operator_currency ON gaming_operators.operator_id=gaming_operator_currency.operator_id AND gaming_operator_currency.currency_id =gaming_client_stats.currency_id;
		
		UPDATE gaming_bonus_instances AS gbi
		JOIN gaming_bonus_rules ON gbi.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
		SET gbi.bonus_amount_remaining=0, gbi.current_win_locked_amount=0, gbi.is_active=0, gbi.is_secured=1, gbi.secured_date=now(), gbi.redeem_reason='Cash Bonus', gbi.redeem_session_id=0, gbi.redeem_user_id=0, 
			gbi.bonus_transfered_total = gbi.bonus_transfered_total + bonus_amount_remaining  + current_win_locked_amount
		WHERE bonus_rule_award_counter_id=bonusRuleAwardCounterID;

		DELETE FROM gaming_bonus_rule_award_counter_client_stats
		WHERE bonus_rule_award_counter_id=bonusRuleAwardCounterID;

		COMMIT;

	END IF;
	

  COMMIT;
  SET statusCode=0;
END root$$

DELIMITER ;

