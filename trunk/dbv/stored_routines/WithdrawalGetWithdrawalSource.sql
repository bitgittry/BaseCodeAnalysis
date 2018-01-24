DROP function IF EXISTS `WithdrawalGetWithdrawalSource`;

DELIMITER $$
CREATE DEFINER=`root`@`%` FUNCTION `WithdrawalGetWithdrawalSource`(withdrawalRequestId BIGINT) RETURNS BIGINT
BEGIN

	DECLARE withdrawalSourceId BIGINT DEFAULT NULL;

	SELECT gbh.issue_withdrawal_type_id FROM gaming_balance_history AS gbh 
    JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.balance_history_id = gbh.balance_history_id 
    WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId 
    INTO withdrawalSourceId;
    
    RETURN withdrawalSourceId;

END$$

DELIMITER ;
