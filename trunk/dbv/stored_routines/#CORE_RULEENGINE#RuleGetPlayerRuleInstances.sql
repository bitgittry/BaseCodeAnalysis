DROP procedure IF EXISTS `RuleGetPlayerRuleInstances`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleGetPlayerRuleInstances`(clientStatID BIGINT, currentOnly TINYINT(1))
root:BEGIN


  -- rule instances
  SELECT gaming_rules_instances.rule_instance_id, client_stat_id, date_created, gaming_rules_instances.rule_id, gaming_rules_instances.is_current, is_achieved,
    gaming_rules.name AS rule_name, gaming_rules.friendly_name AS rule_display_name, gaming_rules_instances.rule_id as rule_id
  FROM gaming_rules_instances
  JOIN gaming_rules ON gaming_rules_instances.rule_id=gaming_rules.rule_id
  WHERE client_stat_id=clientStatID AND gaming_rules_instances.is_current=CASE WHEN currentOnly=1 THEN 1 ELSE gaming_rules_instances.is_current END;
  
  -- event instances
  SELECT event_instance_id, gaming_events_instances.client_stat_id, gaming_events_instances.rule_event_id, gaming_events_instances.event_id, attr_value, 
    gaming_events_instances.rule_instance_id, 
    gaming_events_instances.is_achieved, gaming_events_instances.has_failed,
    gaming_events.name AS event_name, gaming_events.description AS event_description
  FROM gaming_events_instances
  JOIN gaming_rules_instances ON gaming_events_instances.rule_instance_id=gaming_rules_instances.rule_instance_id 
    AND gaming_rules_instances.is_current=CASE WHEN currentOnly=1 THEN 1 ELSE gaming_rules_instances.is_current END
    AND gaming_rules_instances.client_stat_id=clientStatID AND gaming_rules_instances.is_current=CASE WHEN currentOnly=1 THEN 1 ELSE gaming_rules_instances.is_current END
  JOIN gaming_events ON gaming_events_instances.event_id=gaming_events.event_id;
  
  
END root$$

DELIMITER ;