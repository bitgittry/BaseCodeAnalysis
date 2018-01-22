DROP procedure IF EXISTS `FraudReassignClassificationType`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudReassignClassificationType`(sessionID BIGINT)
BEGIN
	
  UPDATE gaming_fraud_client_events AS client_event
  JOIN gaming_clients ON client_event.client_id=gaming_clients.client_id 
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = client_event.client_id 
  JOIN gaming_fraud_classification_types AS cls_types ON cls_types.is_active=1 AND
    client_event.override_points >= cls_types.points_min_range AND client_event.override_points < IFNULL(cls_types.points_max_range,2147483647)
  SET 
    client_event.fraud_classification_type_id=cls_types.fraud_classification_type_id,
    client_event.session_id=sessionID
  WHERE client_event.is_current=1 AND (gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL));
    
END$$

DELIMITER ;

