DROP procedure IF EXISTS `BonusAdjustBalance`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusAdjustBalance`(clientStatID BIGINT, sessionID BIGINT, transactionType VARCHAR(20), exchangeRate DECIMAL(18,5),bonusInstanceID BIGINT, bonusAmount DECIMAL(18,5), bonusWinLockedAmount DECIMAL(18,5), 
  RingFencedAmount DECIMAL(18,5),RingFencedAmountSB DECIMAL(18,5),RingFencedAmountCasino DECIMAL(18,5),RingFencedAmountPoker DECIMAL(18,5))
root:BEGIN  
	-- This stored procedure is meant to perform an adjustment on the bonus balances for a player by the amount specifieds 
	DECLARE totalAdjustmentAmount, totalAdjustmentAmountBase, totalRingFenced, totalBonusAdjustmentAmount, totalBonusAdjustmentAmountBase, totalAdjustmentAmountAbs DECIMAL(18,5) DEFAULT 0.0;
	DECLARE currentBonusBalance, currentBonusWinLockedBalance DECIMAL(18,5) DEFAULT 0.0;
	DECLARE transactionID BIGINT;
	
	SET totalAdjustmentAmount = IFNULL(bonusAmount,0) + IFNULL(bonusWinLockedAmount,0) + IFNULL(RingFencedAmount,0) + IFNULL(RingFencedAmountSB,0) + IFNULL(RingFencedAmountCasino,0) + IFNULL(RingFencedAmountPoker,0);
	SET totalAdjustmentAmountAbs = ABS(IFNULL(bonusAmount,0)) + ABS(IFNULL(bonusWinLockedAmount,0)) + ABS(IFNULL(RingFencedAmount,0)) + ABS(IFNULL(RingFencedAmountSB,0)) + ABS(IFNULL(RingFencedAmountCasino,0)) + ABS(IFNULL(RingFencedAmountPoker,0));
    SET totalRingFenced = IFNULL(RingFencedAmount,0) + IFNULL(RingFencedAmountSB,0) + IFNULL(RingFencedAmountCasino,0) + IFNULL(RingFencedAmountPoker,0);
	SET totalBonusAdjustmentAmount = IFNULL(bonusAmount,0) + IFNULL(RingFencedAmount,0) + IFNULL(RingFencedAmountSB,0) + IFNULL(RingFencedAmountCasino,0) + IFNULL(RingFencedAmountPoker,0);
	
	IF(totalAdjustmentAmountAbs = 0) THEN
		LEAVE root;
	END IF;

	-- 1. Update balances in bonus_instance
	UPDATE gaming_bonus_instances AS gbi
		JOIN gaming_bonus_rules ON gbi.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
		SET gbi.bonus_amount_given=bonus_amount_given + IFNULL(bonusAmount,0),
		gbi.bonus_amount_remaining=bonus_amount_remaining + IFNULL(bonusAmount,0), 
		-- Not sure that we should allow adjustment
		gbi.current_win_locked_amount=current_win_locked_amount + IFNULL(bonusWinLockedAmount,0), 
		gbi.ring_fenced_amount_given=ring_fenced_amount_given + totalRingFenced,
		gbi.current_ring_fenced_amount=current_ring_fenced_amount + totalRingFenced
	WHERE bonus_instance_id=bonusInstanceID and gbi.is_active=true;
	
	-- Load ExchangeRate for player
	SELECT exchange_rate INTO exchangeRate
		FROM gaming_operators 
		JOIN gaming_operator_currency ON gaming_operators.operator_id=gaming_operator_currency.operator_id
		JOIN gaming_client_stats AS gcs ON gcs.client_stat_id=clientStatID AND gcs.currency_id=gaming_operator_currency.currency_id
	WHERE gaming_operators.is_main_operator=1;
	
	SET totalAdjustmentAmountBase = totalAdjustmentAmount / exchangeRate;
	SET totalBonusAdjustmentAmountBase = totalBonusAdjustmentAmount/ exchangeRate;
	
	SELECT current_bonus_balance, current_bonus_win_locked_balance INTO currentBonusBalance, currentBonusWinLockedBalance FROM gaming_client_stats WHERE gaming_client_stats.client_stat_id = clientStatID;
	SET currentBonusBalance= IFNULL(currentBonusBalance,0);
	SET currentBonusWinLockedBalance=IFNULL(currentBonusWinLockedBalance,0);


	-- Update gaming_client_stats
	UPDATE gaming_client_stats
        LEFT JOIN
			gaming_bonus_instances ON bonus_instance_id = bonusInstanceID
        LEFT JOIN
		(SELECT 
			COUNT(1) AS numBonuses
		FROM
			gaming_bonus_instances
		WHERE
			gaming_bonus_instances.client_stat_id = clientStatID
				AND is_active
				AND is_freebet_phase = 0
		GROUP BY client_stat_id) AS activeBonuses ON 1 = 1 
	SET 
		current_bonus_balance = current_bonus_balance + IFNULL(bonusAmount,0),
		current_bonus_win_locked_balance = current_bonus_win_locked_balance + IFNULL(bonusWinLockedAmount,0),
		gaming_client_stats.current_ring_fenced_sb = current_ring_fenced_sb - IFNULL(RingFencedAmountSB,0),
		gaming_client_stats.current_ring_fenced_casino = current_ring_fenced_casino - IFNULL(RingFencedAmountCasino,0),
		gaming_client_stats.current_ring_fenced_poker = current_ring_fenced_poker - IFNULL(RingFencedAmountPoker,0),
		gaming_client_stats.current_ring_fenced_amount = gaming_client_stats.current_ring_fenced_amount - IFNULL(RingFencedAmount,0),
		-- to review this with kieth or brian.
		gaming_client_stats.total_bonus_awarded = total_bonus_awarded + totalBonusAdjustmentAmount,
		gaming_client_stats.total_bonus_awarded_base = total_bonus_awarded_base + totalBonusAdjustmentAmountBase
	WHERE
		gaming_client_stats.client_stat_id = clientStatID;



	-- Insert entry in gaming_transactions
	
	INSERT INTO gaming_transactions	(payment_transaction_type_id, 
		amount_total,  
		amount_total_base, 
		currency_id, 
		exchange_rate, 
		amount_real, 
		amount_bonus, 
		amount_bonus_win_locked, 
		loyalty_points, 
		timestamp, 
		client_id, 
		client_stat_id, 
		balance_real_after, 
		balance_bonus_after, 
		balance_bonus_win_locked_after, 
		loyalty_points_after, 
		extra_id, 
		extra2_id, 
		session_id, 
		pending_bet_real, 
		pending_bet_bonus,
		withdrawal_pending_after, 
		loyalty_points_bonus,	
		loyalty_points_after_bonus) 
	SELECT gaming_payment_transaction_type.payment_transaction_type_id,  
		totalAdjustmentAmount, 
		ROUND(totalAdjustmentAmountBase, 5), 
		gaming_client_stats.currency_id, 
		exchangeRate, 
		0,
		totalBonusAdjustmentAmount, 
		IFNULL(bonusWinLockedAmount,0), 
		0, 
		NOW(), 
		gaming_client_stats.client_id, 
		gaming_client_stats.client_stat_id, 
		current_real_balance, 
		currentBonusBalance+totalBonusAdjustmentAmount, 
		currentBonusWinLockedBalance+bonusWinLockedAmount,
		current_loyalty_points, 
		NULL, 
		bonusInstanceID, 
		sessionID, 
		gaming_client_stats.pending_bets_real, 
		gaming_client_stats.pending_bets_bonus,	
		withdrawal_pending_amount, 
		0,
		(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
	FROM gaming_client_stats  
	JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=transactionType
	WHERE client_stat_id=clientStatID; 

	SET transactionID=LAST_INSERT_ID();
	
	-- Insert entry in gaming_game_plays

	INSERT INTO gaming_game_plays (amount_total, 
		amount_total_base, 
		exchange_rate, 
		amount_real, 
		amount_bonus, 
		amount_bonus_win_locked,
		amount_free_bet, 
		bonus_lost, 
		bonus_win_locked_lost, 
		timestamp, 
		client_id, 
		client_stat_id, 
		payment_transaction_type_id, 
		balance_real_after, 
		balance_bonus_after, 
		balance_bonus_win_locked_after, 
		currency_id, 
		session_id, 
		transaction_id, 
		pending_bet_real, 
		pending_bet_bonus, 
		loyalty_points, 
		loyalty_points_after, 
		loyalty_points_bonus, 
		loyalty_points_after_bonus) 
	SELECT amount_total, 
			amount_total_base, 
			exchange_rate, 
			amount_real, 
			amount_bonus, 
			amount_bonus_win_locked,
			0, 
			0, 
			0,  
			timestamp, 
			client_id, 
			client_stat_id, 
			payment_transaction_type_id, 
			balance_real_after, 
			balance_bonus_after+balance_bonus_win_locked_after, 
			balance_bonus_win_locked_after, 
			currency_id, 
			session_id, 
			gaming_transactions.transaction_id, 
			pending_bet_real, 
			pending_bet_bonus, 
			gaming_transactions.loyalty_points, 
			gaming_transactions.loyalty_points_after, 
			gaming_transactions.loyalty_points_bonus, 
			gaming_transactions.loyalty_points_after_bonus
	FROM gaming_transactions
	WHERE transaction_id=transactionID;
		
	CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());  


END root$$

DELIMITER ;

