DROP function IF EXISTS `WithdrawalGetPaymentMethod`;

DELIMITER $$
CREATE DEFINER=`root`@`%` FUNCTION `WithdrawalGetPaymentMethod`(withdrawalRequestId BIGINT) RETURNS BIGINT
BEGIN

	DECLARE paymentMethodId BIGINT DEFAULT NULL;

	SELECT gbh.sub_payment_method_id FROM gaming_balance_history AS gbh 
    JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.balance_history_id = gbh.balance_history_id 
    WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId 
    INTO paymentMethodId;
    
    RETURN paymentMethodId;

END$$

DELIMITER ;
