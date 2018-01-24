DROP function IF EXISTS `WithdrawalGetWithdrawalCount`;

DELIMITER $$
CREATE DEFINER=`root`@`%` FUNCTION `WithdrawalGetWithdrawalCount`(withdrawalRequestId BIGINT) RETURNS BIGINT
BEGIN

	DECLARE withdrawalsCount BIGINT DEFAULT NULL;

	SELECT gcs.num_withdrawals FROM gaming_client_stats AS gcs 
    JOIN gaming_balance_history AS gbh ON gcs.client_stat_id = gbh.client_stat_id 
    JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.balance_history_id = gbh.balance_history_id 
    WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId 
    INTO withdrawalsCount;
    
    RETURN withdrawalsCount;

END$$

DELIMITER ;