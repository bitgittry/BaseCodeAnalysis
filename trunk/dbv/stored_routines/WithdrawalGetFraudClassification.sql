DROP function IF EXISTS `WithdrawalGetFraudClassification`;

DELIMITER $$
CREATE DEFINER=`root`@`%` FUNCTION `WithdrawalGetFraudClassification`(withdrawalRequestId BIGINT) RETURNS BIGINT
BEGIN

	DECLARE fraudClassificationTypeId BIGINT DEFAULT NULL;

	SELECT gfce.fraud_classification_type_id FROM gaming_fraud_client_events AS gfce 
    JOIN gaming_balance_withdrawal_requests AS gbwr ON gbwr.client_stat_id = gfce.client_stat_id 
    WHERE gbwr.balance_withdrawal_request_id = withdrawalRequestId 
    ORDER BY gfce.fraud_client_event_id DESC LIMIT 1 
    INTO fraudClassificationTypeId;
	
	IF fraudClassificationTypeId IS NULL THEN 
		SELECT fraud_classification_type_id FROM gaming_fraud_classification_types 
        WHERE is_active = 1 
        ORDER BY safety_level ASC LIMIT 1 
		INTO fraudClassificationTypeId;
    END IF;
    
    RETURN fraudClassificationTypeId;

END$$

DELIMITER ;
