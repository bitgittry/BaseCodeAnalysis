DROP function IF EXISTS `WithdrawalGetPaymentProvider`;

DELIMITER $$
CREATE DEFINER=`root`@`%` FUNCTION `WithdrawalGetPaymentProvider`(withdrawalRequestId BIGINT) RETURNS BIGINT
BEGIN

  DECLARE paymentProviderId BIGINT DEFAULT 0;

  SELECT IFNULL(gba.payment_gateway_id, 0) INTO paymentProviderId 
  FROM gaming_balance_accounts AS gba 
  JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.balance_account_id = gba.balance_account_id 
  WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId;
    
  RETURN paymentProviderId;

END$$

DELIMITER ;
