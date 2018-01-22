DROP procedure IF EXISTS `RuleGetAllActiveEvents`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleGetAllActiveEvents`()
BEGIN
	    SELECT gaming_rules_events.rule_event_id,gaming_events.event_id,gaming_event_types.name AS 'event_type',gaming_events.name AS 'event_name',description,priority,
      is_continous
      FROM gaming_events
      JOIN gaming_event_types ON gaming_events.event_type_id = gaming_event_types.event_type_id
      JOIN gaming_rules_events ON gaming_rules_events.event_id = gaming_events.event_id
      JOIN gaming_rules ON gaming_rules.rule_id = gaming_rules_events.rule_id
      WHERE is_active=1;
      
      SELECT gaming_rules_events.rule_event_id,gaming_events_vars.event_var_id,var_reference,gaming_events_var_types.name,default_value,value,gaming_events_vars.event_id,rule_events_var_id,is_currency,non_editable,enum_values
      FROM gaming_events_vars
      JOIN gaming_events_var_types ON gaming_events_var_types.event_var_type_id=gaming_events_vars.event_var_type_id
      JOIN gaming_rule_events_vars ON gaming_events_vars.event_var_id = gaming_rule_events_vars.event_var_id
      JOIN gaming_rules_events ON gaming_rules_events.rule_event_id = gaming_rule_events_vars.rule_event_id
      JOIN gaming_rules ON gaming_rules.rule_id = gaming_rules_events.rule_id AND gaming_rules.is_active=1 AND gaming_rules.is_hidden =0;
      
      SELECT gaming_rule_events_vars.rule_events_var_id,gaming_currency.currency_id,gaming_rule_events_vars_currency_value.value, currency_code
      FROM gaming_events_vars
      JOIN gaming_events_var_types ON gaming_events_var_types.event_var_type_id=gaming_events_vars.event_var_type_id
      JOIN gaming_rule_events_vars ON gaming_events_vars.event_var_id = gaming_rule_events_vars.event_var_id
      JOIN gaming_rules_events ON gaming_rules_events.rule_event_id = gaming_rule_events_vars.rule_event_id
      JOIN gaming_rule_events_vars_currency_value ON gaming_rule_events_vars_currency_value.rule_events_var_id = gaming_rule_events_vars.rule_events_var_id
      JOIN gaming_currency ON gaming_currency.currency_id = gaming_rule_events_vars_currency_value.currency_id
      JOIN gaming_rules ON gaming_rules.rule_id = gaming_rules_events.rule_id AND gaming_rules.is_active=1 AND gaming_rules.is_hidden =0 
      WHERE is_currency=1;
      
END$$

DELIMITER ;