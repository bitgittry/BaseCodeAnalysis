DROP procedure IF EXISTS `FraudRunAsync`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRunAsync`()
BEGIN
    -- Limited at 50 at a time
	DECLARE varDone, fraudStatus INT DEFAULT 0;
	DECLARE clientID, sessionID, extraID, operatorID BIGINT DEFAULT 0;
	DECLARE fraudEventType VARCHAR(40);
	DECLARE clientCursor CURSOR FOR SELECT DISTINCT client_id, event_type, extra_id, session_id FROM gaming_fraud_registration_pending WHERE is_processing = 1;
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET varDone = 1;

	SELECT operator_id INTO operatorID FROM gaming_operators WHERE is_main_operator = 1 LIMIT 1;
	UPDATE gaming_fraud_registration_pending SET is_processing = 1 WHERE process_date <= NOW() LIMIT 50;

    START TRANSACTION;
	OPEN clientCursor;
	allClientsLabel: LOOP 
		SET varDone=0;
		FETCH clientCursor INTO clientID, fraudEventType, extraID, sessionID;
		IF (varDone) THEN
		  LEAVE allClientsLabel;
		END IF;
	  
		SET fraudStatus=0;
		CALL FraudEventRun(operatorID, clientID, fraudEventType, extraID, sessionID, NULL, 0, 0, fraudStatus);
		DELETE FROM gaming_fraud_registration_pending WHERE client_id = clientID AND event_type = fraudEventType;
		COMMIT AND CHAIN;
	END LOOP allClientsLabel;
	CLOSE clientCursor;
	COMMIT;
	

END$$

DELIMITER ;

