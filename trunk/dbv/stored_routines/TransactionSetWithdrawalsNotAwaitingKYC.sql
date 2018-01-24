DROP procedure IF EXISTS `TransactionSetWithdrawalsNotAwaitingKYC`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionSetWithdrawalsNotAwaitingKYC`(clientStatID BIGINT, userID BIGINT)
BEGIN

  DECLARE clientID, balanceWithdrawalRequestID, auditLogGroupId BIGINT DEFAULT NULL;
  DECLARE noMoreRecords TINYINT(1) DEFAULT 0;
  
  DECLARE withdrawalsCursor CURSOR FOR 
    SELECT balance_withdrawal_request_id FROM gaming_balance_withdrawal_requests WHERE client_stat_id=clientStatID AND is_processed=0 AND is_waiting_kyc=1;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1; 
  
  SELECT client_id INTO clientID FROM gaming_client_stats WHERE client_stat_id=clientStatID;
  
  OPEN withdrawalsCursor;
  allTxnLabel: LOOP 
    
    SET noMoreRecords=0;
    FETCH withdrawalsCursor INTO balanceWithdrawalRequestID;
    IF (noMoreRecords) THEN
      LEAVE allTxnLabel;
    END IF;
  
	UPDATE gaming_balance_withdrawal_requests SET is_waiting_kyc=0 WHERE balance_withdrawal_request_id=balanceWithdrawalRequestID;
    
    -- Done by Trigger
    /*
    SET auditLogGroupId = AuditLogNewGroup(userID, NULL, balanceWithdrawalRequestID, 6, IF(userID=0, 'System', 'User'), NULL, NULL, clientID);
	CALL AuditLogAttributeChange('Is Waiting KYC', clientID, auditLogGroupId, 0, 1, NOW());
    */
  END LOOP allTxnLabel;
  CLOSE withdrawalsCursor;

END$$

DELIMITER ;

