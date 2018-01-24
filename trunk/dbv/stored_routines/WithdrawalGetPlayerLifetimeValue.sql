DROP function IF EXISTS `WithdrawalGetPlayerLifetimeValue`;

DELIMITER $$
CREATE DEFINER=`root`@`%` FUNCTION `WithdrawalGetPlayerLifetimeValue`(withdrawalRequestId BIGINT) RETURNS DECIMAL(18, 5)
BEGIN

	DECLARE playerLifetimeValue DECIMAL(18, 5) DEFAULT NULL;

	SELECT gcs.total_real_played - gcs.total_real_won - gcs.total_bonus_transferred - gcs.total_bonus_win_locked_transferred - gcs.total_adjustments FROM gaming_client_stats AS gcs 
    JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.client_stat_id = gcs.client_stat_id 
    WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId 
    INTO playerLifetimeValue;
    
    RETURN playerLifetimeValue;

END$$

DELIMITER ;
