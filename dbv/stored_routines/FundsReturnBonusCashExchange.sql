DROP procedure IF EXISTS `FundsReturnBonusCashExchange`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FundsReturnBonusCashExchange`(clientStatID BIGINT, gamePlayID BIGINT, sessionID BIGINT, transactionType VARCHAR(20), exchangeRate DECIMAL(18,5), bonusTransferedTotal DECIMAL(18,5),
		bonusTransfered DECIMAL(18,5), bonusWinLockedTransfered DECIMAL(18,5),sbBetID BIGINT)
root:BEGIN  

  -- 1. update client stats added real_money as the amount transferred 
	UPDATE gaming_client_stats
	SET 
		current_real_balance = current_real_balance + bonusTransferedTotal,
		total_bonus_transferred = total_bonus_transferred + bonusTransfered,
		current_bonus_balance = current_bonus_balance - bonusTransfered,
		total_bonus_win_locked_transferred = total_bonus_win_locked_transferred + bonusWinLockedTransfered,
		current_bonus_win_locked_balance = current_bonus_win_locked_balance - bonusWinLockedTransfered,
		total_bonus_transferred_base = total_bonus_transferred_base + ROUND(bonusTransferedTotal / exchangeRate, 5)
	WHERE gaming_client_stats.client_stat_id = clientStatID;
  
	INSERT INTO gaming_transactions
	(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, 
	 amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, 
	 client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, 
	 loyalty_points_after, extra_id,extra2_id, session_id, pending_bet_real, 
	 pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT  gaming_payment_transaction_type.payment_transaction_type_id, SUM(ROUND(gsbb.turned_real_bonus+gsbb.turned_real_bonus_win_locked)), SUM(ROUND(gsbb.turned_real_bonus+gsbb.turned_real_bonus_win_locked/exchangeRate, 5)), gaming_client_stats.currency_id, exchangeRate,
			SUM(ROUND(gsbb.turned_real_bonus+gsbb.turned_real_bonus_win_locked)) ,SUM(ROUND(gsbb.turned_real_bonus)*-1), SUM(ROUND(gsbb.turned_real_bonus_win_locked)*-1), 0, NOW(), 
			gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, 
			current_loyalty_points,gamePlayID,gbi.bonus_instance_id, sessionID, gaming_client_stats.pending_bets_real, 
			gaming_client_stats.pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)		 
	FROM gaming_sb_bets_bonuses AS gsbb 
	JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id = gsbb.bonus_instance_id 
	JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gbi.bonus_rule_id
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gbi.client_stat_id
	JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=transactionType
	WHERE gsbb.sb_bet_id=sbBetID AND (gbi.is_secured OR is_free_bonus OR gbi.is_freebet_phase)
	GROUP BY gbi.bonus_instance_id;

	INSERT INTO gaming_game_plays 
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, bonus_lost, bonus_win_locked_lost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,bet_from_real,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,0, 0, 0, timestamp, gaming_transactions.client_id, gaming_transactions.client_stat_id, gaming_payment_transaction_type.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, gaming_transactions.currency_id, gaming_transactions.session_id, gaming_transactions.transaction_id, gaming_transactions.pending_bet_real, gaming_transactions.pending_bet_bonus,bet_from_real,gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
	FROM gaming_transactions
	JOIN gaming_payment_transaction_type ON gaming_transactions.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id AND gaming_payment_transaction_type.name=transactionType
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_transactions.client_stat_id
	WHERE extra_id=gamePlayID;
	
	CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());  


	INSERT INTO gaming_bonus_rules_rec_met (bonus_rule_id,bonus_transfered)
	SELECT gbi.bonus_rule_id,IFNULL(ROUND((turned_real_bonus_win_locked + turned_real_bonus)/exchangeRate, 0),0) 
	FROM gaming_sb_bets_bonuses  gsbb
	JOIN gaming_bonus_instances gbi ON gbi.bonus_instance_id =  gsbb.bonus_instance_id 
	WHERE gsbb.sb_bet_id=sbBetID;

END root$$

DELIMITER ;

