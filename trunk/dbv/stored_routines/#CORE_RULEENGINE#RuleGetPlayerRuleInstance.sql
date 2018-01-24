-- --------------------------------------------------------------------------------
-- Routine DDL
-- Note: comments before and after the routine body will not be stored by the server
-- --------------------------------------------------------------------------------
DROP procedure IF EXISTS `RuleGetPlayerRuleInstance`;
DELIMITER $$

CREATE PROCEDURE `RuleGetPlayerRuleInstance`(ruleInstanceID BIGINT)
BEGIN
  
  SELECT gaming_rules_instances.rule_instance_id, client_stat_id, date_created, gaming_rules_instances.rule_id, gaming_rules_instances.is_current, is_achieved,
    gaming_rules.name AS rule_name, gaming_rules.friendly_name AS rule_display_name
  FROM gaming_rules_instances
  JOIN gaming_rules ON gaming_rules_instances.rule_id=gaming_rules.rule_id
  WHERE gaming_rules_instances.rule_instance_id=ruleInstanceID;
  
  SELECT event_instance_id, gaming_events_instances.client_stat_id, gaming_events_instances.rule_event_id, gaming_rules_events.event_id, attr_value, gaming_events_instances.rule_instance_id, 
    gaming_events_instances.is_achieved, gaming_events_instances.has_failed,
    gaming_events.name AS event_name, gaming_events.description AS event_description
  FROM gaming_events_instances
  JOIN gaming_rules_instances ON gaming_events_instances.rule_instance_id=gaming_rules_instances.rule_instance_id
  JOIN gaming_rules_events ON gaming_events_instances.rule_event_id=gaming_rules_events.rule_event_id
  JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id
  WHERE gaming_rules_instances.rule_instance_id=ruleInstanceID;

END $$
DELIMITER ;