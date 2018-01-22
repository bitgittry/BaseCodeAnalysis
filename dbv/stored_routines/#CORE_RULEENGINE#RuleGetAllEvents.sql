DROP procedure IF EXISTS `RuleGetAllEvents`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleGetAllEvents`()
BEGIN
	    SELECT gaming_rules_events.rule_id,gaming_rules_events.rule_event_id,gaming_events.event_id,gaming_event_types.name AS 'event_type',gaming_events.name AS 'event_name',
      description,priority, is_continous
      FROM gaming_events
      LEFT JOIN gaming_event_types ON gaming_events.event_type_id = gaming_event_types.event_type_id
      LEFT JOIN gaming_rules_events ON gaming_rules_events.event_id = gaming_events.event_id
      LEFT JOIN gaming_rules ON gaming_rules.rule_id = gaming_rules_events.rule_id;
     
      SELECT gaming_rules_events.rule_id,gaming_events_vars.event_var_id,var_reference,gaming_events_var_types.name,default_value,
      value,gaming_events_vars.event_id,enum_values,is_currency,non_editable,rule_events_var_id FROM gaming_events_vars
      JOIN gaming_events_var_types ON gaming_events_var_types.event_var_type_id=gaming_events_vars.event_var_type_id
      LEFT JOIN gaming_rule_events_vars ON gaming_events_vars.event_var_id = gaming_rule_events_vars.event_var_id
      LEFT JOIN gaming_rules_events ON gaming_rules_events.rule_event_id = gaming_rule_events_vars.rule_event_id
      LEFT JOIN gaming_rules ON gaming_rules.rule_id = gaming_rules_events.rule_id;
      
END$$

DELIMITER ;