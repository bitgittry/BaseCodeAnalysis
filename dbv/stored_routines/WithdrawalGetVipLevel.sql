DROP function IF EXISTS `WithdrawalGetVipLevel`;

DELIMITER $$
CREATE DEFINER=`root`@`%` FUNCTION `WithdrawalGetVipLevel`(withdrawalRequestId BIGINT) RETURNS BIGINT
BEGIN

  DECLARE clientVipLevelId BIGINT DEFAULT 0;

  SELECT IFNULL(gc.vip_level_id,0) INTO clientVipLevelId
  FROM gaming_clients AS gc 
  JOIN gaming_balance_history AS gbh ON gc.client_id = gbh.client_id 
  JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.balance_history_id = gbh.balance_history_id 
  WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId;
    
  RETURN clientVipLevelId;

END$$

DELIMITER ;