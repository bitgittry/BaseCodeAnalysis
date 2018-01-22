DROP procedure IF EXISTS `RuleGetActiveEvent`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleGetActiveEvent`(ruleEventId BIGINT)
BEGIN
	    SELECT rule_event_id,gaming_events.event_id,gaming_event_types.name AS 'event_type',gaming_events.name AS 'event_name',
      description,priority
      FROM gaming_events
      JOIN gaming_event_types ON gaming_events.event_type_id = gaming_event_types.event_type_id
      JOIN gaming_rules_events ON gaming_events.event_id = gaming_rules_events.event_id
      WHERE rule_event_id=ruleEventId;
      
      SELECT gaming_events_vars.event_var_id,var_reference,name,default_value,rule_events_var_id,is_currency,non_editable,enum_values, enum_values, is_currency, non_editable,rule_events_var_id FROM gaming_events_vars
      JOIN gaming_events_var_types ON gaming_events_var_types.event_var_type_id=gaming_events_vars.event_var_type_id
      LEFT JOIN gaming_rule_events_vars ON gaming_events_vars.event_var_id = gaming_rule_events_vars.event_var_id
      WHERE rule_event_id=ruleEventId;
      
      SELECT gaming_rule_events_vars.rule_events_var_id,gaming_currency.currency_id,gaming_rule_events_vars_currency_value.value, currency_code FROM gaming_events_vars
      JOIN gaming_events_var_types ON gaming_events_var_types.event_var_type_id=gaming_events_vars.event_var_type_id
      LEFT JOIN gaming_rule_events_vars ON gaming_events_vars.event_var_id = gaming_rule_events_vars.event_var_id
      JOIN gaming_rule_events_vars_currency_value ON gaming_rule_events_vars_currency_value.rule_events_var_id = gaming_rule_events_vars.rule_events_var_id
      JOIN gaming_currency ON gaming_currency.currency_id = gaming_rule_events_vars_currency_value.currency_id 
      WHERE rule_event_id=ruleEventId;
      
END$$

DELIMITER ;