DROP procedure IF EXISTS `PlaceTransactionOffsetNegativeBalancePreComputred`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceTransactionOffsetNegativeBalancePreComputred`(clientStatID BIGINT, badDebtRealAmount DECIMAL(18,5), exchangeRate DECIMAL(18,5), gamePlayID BIGINT, betSBExtraID BIGINT, sbBetID BIGINT, licenseTypeID TINYINT(4), OUT badDeptGamePlayID BIGINT)
BEGIN

	DECLARE badDeptTransactionID BIGINT DEFAULT -1;   

	UPDATE gaming_client_stats AS gcs
	SET 
    gcs.current_real_balance=gcs.current_real_balance + badDebtRealAmount, 
    gcs.total_bad_debt=gcs.total_bad_debt+badDebtRealAmount
	WHERE 
    gcs.client_stat_id=clientStatID;  

	INSERT INTO gaming_transactions
    (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, 
	 timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, 
	 extra_id, pending_bet_real, pending_bet_bonus, withdrawal_pending_after, loyalty_points_bonus, loyalty_points_after_bonus) 
    SELECT gaming_payment_transaction_type.payment_transaction_type_id, badDebtRealAmount, ROUND(badDebtRealAmount/exchangeRate,5), gaming_client_stats.currency_id, exchangeRate, badDebtRealAmount, 0, 0, 0, 
	  NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, 
	  gamePlayID, pending_bets_real, pending_bets_bonus, withdrawal_pending_amount, 0, (gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
    FROM gaming_client_stats 
    JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
    JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='BadDebt'
    WHERE gaming_client_stats.client_stat_id=clientStatID;  
    
    SET badDeptTransactionID=LAST_INSERT_ID();
  
    INSERT INTO gaming_game_plays 
    (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, 
     payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, 
     platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, extra_id, sb_extra_id, sb_bet_id, license_type_id) 
    SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, 
	 payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, 
     platform_type_id, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, gamePlayID, betSBExtraID, sbBetID, licenseTypeID
    FROM gaming_transactions
    WHERE transaction_id=badDeptTransactionID;
	
    SET badDeptGamePlayID=LAST_INSERT_ID();

	CALL GameUpdateRingFencedBalances(clientStatID, badDeptGamePlayID);

END$$

DELIMITER ;

