DROP function IF EXISTS `WithdrawalGetKycChecked`;

DELIMITER $$
CREATE DEFINER=`root`@`%` FUNCTION `WithdrawalGetKycChecked`(withdrawalRequestId BIGINT) RETURNS BIGINT
BEGIN
	-- Alternative KYC status Ids
	DECLARE yesId BIGINT DEFAULT -1;
	DECLARE noId BIGINT DEFAULT -2;

	DECLARE kycCheckedStatusId BIGINT DEFAULT NULL;
    DECLARE enhancedKycEnabled TINYINT DEFAULT 0;
    DECLARE isKycChecked TINYINT DEFAULT 0;
    
    SELECT value_bool FROM gaming_settings 
    WHERE name = 'ENHANCED_KYC_CHECKED_STATUSES' 
    INTO enhancedKycEnabled;

	IF enhancedKycEnabled = 1 THEN
		SELECT gc.kyc_checked_status_id FROM gaming_clients AS gc 
		JOIN gaming_balance_history AS gbh ON gc.client_id = gbh.client_id 
		JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.balance_history_id = gbh.balance_history_id 
		WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId 
		INTO kycCheckedStatusId;
	END IF;
    
    IF kycCheckedStatusId IS NULL THEN
        SELECT gc.is_kyc_checked FROM gaming_clients AS gc 
		JOIN gaming_balance_history AS gbh ON gc.client_id = gbh.client_id 
		JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.balance_history_id = gbh.balance_history_id 
		WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId 
		INTO isKycChecked;
        
        SET kycCheckedStatusId = IF(isKycChecked, yesId, noId);
    END IF;
    
    RETURN kycCheckedStatusId;

END$$

DELIMITER ;