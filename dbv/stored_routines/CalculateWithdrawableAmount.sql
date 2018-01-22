DROP function IF EXISTS `CalculateWithdrawableAmount`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CalculateWithdrawableAmount`(varClientStatID BIGINT(20)) RETURNS decimal(18,5)
BEGIN

	DECLARE limitWitdrawalToWinnings,limitWithdrawalToNonLockedFunds TINYINT(1) DEFAULT 0;
	DECLARE returnValue, LockedFunds, depositedAmount, totalRealWon, totalBonusTransferred, totalBonusWinLockedTransferred, withdrawnAmount, withdrawalPendingAmount, deferredTax, currentRealBalance DECIMAL(18,5) DEFAULT 0;

	SELECT value_bool INTO limitWitdrawalToWinnings FROM gaming_settings WHERE `name`='PLAYER_RESTRICT_WITHDRAWALS_TO_ONLY_WINNINGS';
  SELECT value_bool INTO limitWithdrawalToNonLockedFunds FROM gaming_settings WHERE `name`='PLAYER_RESTRICT_WITHDRAWALS_TO_NON_LOCKED_FUNDS';

	SELECT IFNULL(total_real_won,0), IFNULL(total_bonus_transferred,0), IFNULL(total_bonus_win_locked_transferred,0), IFNULL(withdrawn_amount,0), IFNULL(withdrawal_pending_amount,0), IFNULL(deferred_tax,0), IFNULL(current_real_balance,0),  IFNULL(locked_real_funds,0)
	INTO totalRealWon, totalBonusTransferred, totalBonusWinLockedTransferred, withdrawnAmount, withdrawalPendingAmount, deferredTax, currentRealBalance, LockedFunds
	FROM gaming_client_stats
	WHERE client_stat_id = varClientStatID;

	IF (limitWitdrawalToWinnings = 1 AND limitWithdrawalToNonLockedFunds = 0) THEN

			SELECT IFNULL(SUM(b.deposited_amount),0) 
        INTO depositedAmount
			FROM gaming_balance_accounts b, gaming_payment_method p 
			WHERE 
        p.payment_method_id = b.payment_method_id 
				AND p.wager_before_withdrawal = 0 
        AND b.client_stat_id = varClientStatID;

			SET returnValue = depositedAmount + totalRealWon + totalBonusTransferred + totalBonusWinLockedTransferred - (withdrawnAmount + withdrawalPendingAmount) - deferredTax;

	ELSEIF (limitWitdrawalToWinnings = 1 AND limitWithdrawalToNonLockedFunds = 1) THEN
			SET returnValue = currentRealBalance - LockedFunds - deferredTax;
	ELSE
		SET returnValue = currentRealBalance - deferredTax;
	END IF;

RETURN returnValue;
END$$

DELIMITER ;

