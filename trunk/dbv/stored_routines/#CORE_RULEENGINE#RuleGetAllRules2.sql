DROP procedure IF EXISTS `RuleGetAllRules2`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleGetAllRules2`(evenHidden TINYINT(1))
BEGIN
    
    SELECT rule_id, gaming_rules.name AS name, friendly_name, reoccuring, player_selection_id, has_prerequisite,
      gaming_query_date_interval_types.name AS 'query_interval_type', interval_multiplier, max_occurrences
    FROM gaming_rules
    LEFT JOIN gaming_query_date_interval_types ON gaming_query_date_interval_types.query_date_interval_type_id = gaming_rules.query_interval_type_id
    WHERE (evenHidden=1 OR gaming_rules.is_hidden=0);
    
    
    SELECT name, description, rule_action_id, rule_id AS ruleID FROM gaming_rule_actions 
    JOIN gaming_rule_action_types ON gaming_rule_action_types.rule_action_type_id = gaming_rule_actions.rule_action_type_id;
    
    
    SELECT gaming_rule_actions.rule_action_id, rule_action_var_id, name, enum_values,value FROM gaming_rule_actions
    JOIN gaming_rule_action_vars ON gaming_rule_action_vars.rule_action_id = gaming_rule_actions.rule_action_id
    JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id=gaming_rule_action_vars.rule_action_type_var_id;
      
    
  	SELECT gaming_rules_events.rule_id, gaming_events.event_id, gaming_event_types.name AS 'event_type', gaming_events.name AS 'event_name',
     gaming_events.description, gaming_events.priority
    FROM gaming_events
    JOIN gaming_event_types ON gaming_events.event_type_id = gaming_event_types.event_type_id
    JOIN gaming_rules_events ON gaming_rules_events.event_id = gaming_events.event_id
    JOIN gaming_rules ON gaming_rules_events.rule_id=gaming_rules.rule_id 
    WHERE (evenHidden=1 OR gaming_rules.is_hidden=0);
    
    
    SELECT gaming_events_vars.event_var_id, gaming_events_vars.var_reference, gaming_events_var_types.name, gaming_events_vars.default_value, gaming_events_vars.event_id, gaming_rule_events_vars.value 
    FROM gaming_events_vars
    JOIN gaming_events_var_types ON gaming_events_var_types.event_var_type_id=gaming_events_vars.event_var_type_id
    JOIN gaming_rules_events ON gaming_rules_events.event_id = gaming_events_vars.event_id
    LEFT JOIN gaming_rule_events_vars ON gaming_events_vars.event_var_id = gaming_rule_events_vars.event_var_id
    JOIN gaming_rules ON gaming_rules_events.rule_id=gaming_rules.rule_id
    WHERE (evenHidden=1 OR gaming_rules.is_hidden=0);
    
END$$

DELIMITER ;