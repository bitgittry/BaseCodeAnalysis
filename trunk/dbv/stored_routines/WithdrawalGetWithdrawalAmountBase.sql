DROP function IF EXISTS `WithdrawalGetWithdrawalAmountBase`;

DELIMITER $$
CREATE DEFINER=`root`@`%` FUNCTION `WithdrawalGetWithdrawalAmountBase`(withdrawalRequestId BIGINT) RETURNS DECIMAL(18, 5)
BEGIN

	DECLARE withdrawalAmountBase DECIMAL(18, 5) DEFAULT NULL;

	SELECT gbh.amount_base FROM gaming_balance_history AS gbh 
    JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.balance_history_id = gbh.balance_history_id 
    WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId 
    INTO withdrawalAmountBase;
    
    RETURN withdrawalAmountBase;

END$$

DELIMITER ;
