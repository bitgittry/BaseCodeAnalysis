DROP procedure IF EXISTS `RuleActivateRulesForPlayer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleActivateRulesForPlayer`(clientStatID BIGINT)
BEGIN
	-- Removed Cursor 
    
	DECLARE	dateTimeNow DATETIME;	
	SET dateTimeNow = NOW();
	
	INSERT INTO gaming_rules_instances_counter (date_created) VALUES (NOW());
	SET @counterID=LAST_INSERT_ID();    

	INSERT INTO gaming_rules_instances (client_stat_id, rule_id, is_current, date_created, end_date, rule_instance_counter_id) 
	SELECT clientStatID, gaming_rules.rule_id, 1, dateTimeNow, 
		   IF (gaming_rules.days_to_achieve IS NULL OR gaming_rules.days_to_achieve<=0, 
				NULL, DATE_ADD(dateTimeNow, INTERVAL gaming_rules.days_to_achieve DAY)), @counterID 
	FROM gaming_rules FORCE INDEX (is_active)
    LEFT JOIN gaming_rules_instances AS gri FORCE INDEX (client_stat_rule) ON 
		gri.client_stat_id=clientStatID AND gri.rule_id=gaming_rules.rule_id AND gri.is_current
	WHERE gaming_rules.is_active AND gaming_rules.has_prerequisite=0 AND 
		(gaming_rules.start_date IS NULL OR gaming_rules.start_date<=NOW()) AND (gaming_rules.end_date IS NULL OR gaming_rules.end_date>NOW()) 
	   AND gri.client_stat_id IS NULL
       AND PlayerSelectionIsPlayerInSelectionCached(gaming_rules.player_selection_id, clientStatID);
	
	IF (ROW_COUNT()>0) THEN
		INSERT INTO gaming_events_instances (client_stat_id, rule_event_id, attr_value, rule_instance_id, is_continous) 
		SELECT client_stat_id, rule_event_id, '0', rule_instance_id, is_continous 
		FROM gaming_rules_instances FORCE INDEX (rule_instance_counter_id)
		STRAIGHT_JOIN gaming_rules_events ON gaming_rules_events.rule_id=gaming_rules_instances.rule_id 
		STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id
		WHERE gaming_rules_instances.rule_instance_counter_id=@counterID AND gaming_rules_instances.client_stat_id=clientStatID;
	ELSE
		DELETE FROM gaming_rules_instances_counter WHERE rule_instance_counter_id=@counterID;
	END IF;

END$$

DELIMITER ;

