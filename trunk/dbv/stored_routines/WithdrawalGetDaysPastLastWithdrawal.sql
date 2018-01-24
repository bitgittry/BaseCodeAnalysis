DROP function IF EXISTS `WithdrawalGetDaysPastLastWithdrawal`;

DELIMITER $$
CREATE DEFINER=`root`@`%` FUNCTION `WithdrawalGetDaysPastLastWithdrawal`(withdrawalRequestId BIGINT) RETURNS BIGINT
BEGIN

	DECLARE daysPastLastWithdrawal BIGINT DEFAULT NULL;
	DECLARE lastWithdrawnDate DATETIME DEFAULT NULL;

	SELECT gcs.last_withdrawn_date FROM gaming_client_stats AS gcs 
    JOIN gaming_balance_history AS gbh ON gcs.client_stat_id = gbh.client_stat_id 
    JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.balance_history_id = gbh.balance_history_id 
    WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId 
    INTO lastWithdrawnDate;
	
	IF lastWithdrawnDate IS NOT NULL THEN 
		SET daysPastLastWithdrawal = DATEDIFF(NOW(), lastWithdrawnDate);
    ELSE 
		SET daysPastLastWithdrawal = 999999;
    END IF;
    
    RETURN daysPastLastWithdrawal;

END$$

DELIMITER ;
