DROP procedure IF EXISTS `RuleUpdateExpiredRulesNEvents`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleUpdateExpiredRulesNEvents`()
BEGIN
  -- Optimized
  -- Checking if rule or rule instance have expired 
  
  DECLARE defaultDate DATETIME DEFAULT '3000-01-01 00:00:00';

  -- Fail expire events	
  UPDATE gaming_events_instances FORCE INDEX (current_events)
	  STRAIGHT_JOIN gaming_rules_instances ON gaming_events_instances.rule_instance_id=gaming_rules_instances.rule_instance_id
	  STRAIGHT_JOIN gaming_rules ON gaming_rules_instances.rule_id=gaming_rules.rule_id
	  STRAIGHT_JOIN gaming_rules_events ON gaming_rules_events.rule_event_id = gaming_events_instances.rule_event_id
	  STRAIGHT_JOIN gaming_rule_events_vars ON gaming_rules_events.rule_event_id = gaming_rule_events_vars.rule_event_id
	  STRAIGHT_JOIN gaming_events_vars ON gaming_rule_events_vars.event_var_id = gaming_events_vars.event_var_id
	  STRAIGHT_JOIN gaming_events_var_types ON gaming_events_var_types.name='DateTo' AND gaming_events_vars.event_var_type_id = gaming_events_var_types.event_var_type_id
  SET gaming_events_instances.has_failed=1
  WHERE (gaming_events_instances.is_current=1 AND gaming_events_instances.is_achieved=0 AND gaming_events_instances.has_failed=0) AND (
	(gaming_rules.end_date IS NOT NULL AND gaming_rules.end_date < NOW()) OR 
	(gaming_rules_instances.end_date IS NOT NULL AND gaming_rules_instances.end_date < NOW()) OR 
	(IF(gaming_events_var_types.name='DateTo', IFNULL(CAST(gaming_rule_events_vars.value AS DATETIME), defaultDate), defaultDate) < NOW())
   );

  -- Mark as achieved events with NotEndDate (typically withdrawal events)
  UPDATE gaming_events_instances FORCE INDEX (current_events)
	  STRAIGHT_JOIN gaming_rules_instances ON gaming_events_instances.rule_instance_id=gaming_rules_instances.rule_instance_id
	  STRAIGHT_JOIN gaming_rules ON gaming_rules_instances.rule_id=gaming_rules.rule_id
	  STRAIGHT_JOIN gaming_rules_events ON gaming_rules_events.rule_event_id = gaming_events_instances.rule_event_id
	  STRAIGHT_JOIN gaming_rule_events_vars ON gaming_rules_events.rule_event_id = gaming_rule_events_vars.rule_event_id
	  STRAIGHT_JOIN gaming_events_vars ON gaming_rule_events_vars.event_var_id = gaming_events_vars.event_var_id
	  STRAIGHT_JOIN gaming_events_var_types ON gaming_events_var_types.name='NotEndDate' AND gaming_events_vars.event_var_type_id = gaming_events_var_types.event_var_type_id
  SET gaming_events_instances.is_achieved=1
  WHERE (gaming_events_instances.is_current=1 AND gaming_events_instances.is_achieved=0 AND gaming_events_instances.has_failed=0) AND (
	(IF(gaming_events_var_types.name='NotEndDate', IFNULL(CAST(gaming_rule_events_vars.value AS DATETIME), defaultDate), defaultDate) < NOW())
   );
  
  UPDATE gaming_rules_instances SET is_current=0 WHERE is_current=1 AND end_date < NOW();
  UPDATE gaming_rules SET is_active=0 WHERE is_active =1 AND end_date<NOW();
	
END$$

DELIMITER ;

