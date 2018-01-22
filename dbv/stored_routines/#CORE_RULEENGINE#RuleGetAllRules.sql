DROP procedure IF EXISTS `RuleGetAllRules`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleGetAllRules`(evenHidden TINYINT(1))
BEGIN
 
    -- rules 
    SELECT rule_id, gaming_rules.name AS name, friendly_name, reoccuring, player_selection_id, has_prerequisite,
       interval_multiplier, max_occurrences,is_active, rule_query,
      end_date, start_date, days_to_achieve,player_max_occurrences, gaming_query_date_interval_types.name AS 'achievement_interval_type'
    FROM gaming_rules
    LEFT JOIN gaming_query_date_interval_types ON gaming_query_date_interval_types.query_date_interval_type_id = gaming_rules. achievement_interval_type_id
    WHERE (evenHidden=1 OR gaming_rules.is_hidden=0);
    
    -- linked events
  	SELECT gaming_rules_events.rule_event_id,gaming_rules_events.rule_id, gaming_events.event_id, gaming_event_types.name AS 'event_type', gaming_events.name AS 'event_name',
     gaming_events.description, gaming_events.priority, is_continous
    FROM gaming_events
    JOIN gaming_event_types ON gaming_events.event_type_id = gaming_event_types.event_type_id
    JOIN gaming_rules_events ON gaming_rules_events.event_id = gaming_events.event_id
    JOIN gaming_rules ON gaming_rules_events.rule_id=gaming_rules.rule_id 
    WHERE (evenHidden=1 OR gaming_rules.is_hidden=0);
    
    -- event variables
    SELECT gaming_rule_events_vars.rule_events_var_id, gaming_rules_events.rule_event_id, gaming_events_vars.event_var_id, gaming_events_vars.var_reference, gaming_events_var_types.name, gaming_events_vars.default_value, gaming_events_vars.event_id, gaming_rule_events_vars.value, enum_values, is_currency, non_editable
    FROM gaming_events_vars
    JOIN gaming_events_var_types ON gaming_events_var_types.event_var_type_id=gaming_events_vars.event_var_type_id
    JOIN gaming_rules_events ON gaming_rules_events.event_id = gaming_events_vars.event_id
    JOIN gaming_rule_events_vars ON gaming_events_vars.event_var_id = gaming_rule_events_vars.event_var_id
    JOIN gaming_rules ON gaming_rules_events.rule_id=gaming_rules.rule_id
    WHERE (evenHidden=1 OR gaming_rules.is_hidden=0);
    
    -- event variables currency amounts
    SELECT gaming_rule_events_vars.rule_events_var_id, gaming_currency.currency_id, gaming_rule_events_vars_currency_value.value, gaming_currency.currency_code
    FROM gaming_events_vars
    JOIN gaming_events_var_types ON gaming_events_var_types.event_var_type_id=gaming_events_vars.event_var_type_id
    JOIN gaming_rules_events ON gaming_rules_events.event_id = gaming_events_vars.event_id
    LEFT JOIN gaming_rule_events_vars ON gaming_events_vars.event_var_id = gaming_rule_events_vars.event_var_id
    JOIN gaming_rules ON gaming_rules_events.rule_id=gaming_rules.rule_id
    JOIN gaming_rule_events_vars_currency_value ON gaming_rule_events_vars_currency_value.rule_events_var_id = gaming_rule_events_vars.rule_events_var_id
    JOIN gaming_currency ON gaming_currency.currency_id = gaming_rule_events_vars_currency_value.currency_id 
    WHERE (evenHidden=1 OR gaming_rules.is_hidden=0);
    
END$$

DELIMITER ;

