DROP procedure IF EXISTS `FraudAddExternalViolation`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudAddExternalViolation`(clientID BIGINT, sessionID BIGINT, extraID BIGINT, fraudRule VARCHAR(255))
BEGIN
    
	SELECT operator_id INTO @operatorID FROM gaming_operators WHERE is_main_operator;
	SET @client_id=clientID;
    SET @session_id=sessionID;
    SET @fraud_rule=fraudRule; 

	INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)  
	SELECT gaming_fraud_client_events.fraud_client_event_id, gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, 1, 
      segment_points.points AS rule_points, client_overrides.points AS override_points, NOW()
	FROM gaming_clients
	JOIN gaming_client_stats ON gaming_clients.client_id=@client_id 
	  AND gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
	JOIN gaming_fraud_client_events ON gaming_fraud_client_events.client_id=gaming_clients.client_id AND gaming_fraud_client_events.is_current
	JOIN gaming_fraud_rules ON gaming_fraud_rules.name=@fraud_rule AND gaming_fraud_rules.is_active
	JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
	  gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
	  gaming_clients.client_segment_id=segment_points.client_segment_id
	LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
	  gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
	  gaming_clients.client_id=client_overrides.client_id
	LEFT JOIN
	(
		SELECT COUNT(*) AS num_triggered 
		FROM gaming_fraud_client_events_violations AS gfcev 
		JOIN gaming_fraud_rules AS gfr ON gfcev.fraud_rule_id=gfr.fraud_rule_id 
		WHERE gfr.name=@fraud_rule AND gfcev.client_id=@client_id AND gfcev.cascade_points
	) AS NumTriggered ON 1=1
	WHERE IFNULL(NumTriggered.num_triggered,0)<IFNULL(gaming_fraud_rules.max_trigger_num, 1);

	IF (ROW_COUNT()>0) THEN
		CALL FraudEventRun(@operatorID, clientID, 'ExternalViolation', extraID, sessionID, NULL, 0, 1, @fraudStatus);
	END IF;

END$$

DELIMITER ;

