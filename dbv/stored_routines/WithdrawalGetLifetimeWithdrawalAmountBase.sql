DROP function IF EXISTS `WithdrawalGetLifetimeWithdrawalAmountBase`;

DELIMITER $$
CREATE DEFINER=`root`@`%` FUNCTION `WithdrawalGetLifetimeWithdrawalAmountBase`(withdrawalRequestId BIGINT) RETURNS DECIMAL(18, 5)
BEGIN

	DECLARE lifetimeWithdrawalAmountBase DECIMAL(18, 5) DEFAULT NULL;

	SELECT gcs.withdrawn_amount_base FROM gaming_client_stats AS gcs 
    JOIN gaming_balance_history AS gbh ON gcs.client_stat_id = gbh.client_stat_id 
	JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.balance_history_id = gbh.balance_history_id 
    WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId 
    INTO lifetimeWithdrawalAmountBase;
    
    RETURN lifetimeWithdrawalAmountBase;

END$$

DELIMITER ;