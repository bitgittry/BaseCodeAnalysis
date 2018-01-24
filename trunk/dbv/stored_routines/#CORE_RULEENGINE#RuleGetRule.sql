DROP procedure IF EXISTS `RuleGetRule`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleGetRule`(ruleId BIGINT)
BEGIN
    -- Added chaining rule    
 
    -- rule
    SELECT rule_id,gaming_rules.name AS name,friendly_name,reoccuring,player_selection_id,has_prerequisite,
     interval_multiplier,max_occurrences,is_active,rule_query,start_date,
      end_date,days_to_achieve,player_max_occurrences,  gaming_query_date_interval_types.name AS 'achievement_interval_type'
    FROM gaming_rules
    LEFT JOIN gaming_query_date_interval_types ON gaming_query_date_interval_types.query_date_interval_type_id = gaming_rules.achievement_interval_type_id
    WHERE rule_id=ruleId;
       
    -- actions
    SELECT name, description,rule_action_id,gaming_rule_action_types.rule_action_type_id 
    FROM gaming_rule_actions 
    JOIN gaming_rule_action_types ON gaming_rule_action_types.rule_action_type_id = gaming_rule_actions.rule_action_type_id
    WHERE rule_id = ruleId;
    
    -- action values
    SELECT gaming_rule_actions.rule_action_id, rule_action_var_id, name, enum_values, value
    FROM gaming_rule_actions
    JOIN gaming_rule_action_vars ON gaming_rule_action_vars.rule_action_id = gaming_rule_actions.rule_action_id
    JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id=gaming_rule_action_vars.rule_action_type_var_id
    WHERE rule_id=ruleId;
    
    -- events
  	SELECT gaming_events.rule_id, gaming_events.event_id, gaming_event_types.name AS 'event_type', gaming_events.name AS 'event_name',
      description, priority, gaming_events.priority, is_continous, gaming_events.event_type_id, gaming_events.json
    FROM gaming_events
    JOIN gaming_event_types ON gaming_events.event_type_id = gaming_event_types.event_type_id
    WHERE gaming_events.is_deleted = 0 AND gaming_events.rule_id=ruleId ORDER BY gaming_events.event_id;

    -- criteria
    SELECT ce.re_event_criteria_id, ce.event_id, ce.operator, ce.lower_bound, ce.upper_bound, ce.is_active, ce.filter_date_from, ce.filter_date_to, ce.filter_csv, ce.is_dummy
    FROM gaming_re_event_criteria_config ce JOIN gaming_events ge ON ce.event_id = ge.event_id
    WHERE ge.rule_id = ruleId AND ge.is_deleted = 0 AND  ce.is_dummy = 0;
    

	-- Bonus Actions
    SELECT bonus_rule_id, name, description FROM gaming_bonus_rules 
    WHERE bonus_rule_id IN (
      SELECT value
      FROM gaming_rule_actions
      JOIN gaming_rule_action_vars ON gaming_rule_action_vars.rule_action_id = gaming_rule_actions.rule_action_id
      JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id=gaming_rule_action_vars.rule_action_type_var_id
      WHERE gaming_rule_actions.rule_id=ruleId AND gaming_rule_action_types_var_types.name = 'BonusRuleID'
    );
    
    -- Promotion Actions
    SELECT promotion_id, name, description FROM gaming_promotions
    WHERE promotion_id IN (
      SELECT value
      FROM gaming_rule_actions
      JOIN gaming_rule_action_vars ON gaming_rule_action_vars.rule_action_id = gaming_rule_actions.rule_action_id
      JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id=gaming_rule_action_vars.rule_action_type_var_id
      WHERE gaming_rule_actions.rule_id=ruleId AND gaming_rule_action_types_var_types.name = 'PromotionID'
    );
    
    -- Badges Actions
    SELECT loyalty_badge_id, name, description FROM gaming_loyalty_badges
    WHERE loyalty_badge_id IN (
      SELECT value
      FROM gaming_rule_actions
      JOIN gaming_rule_action_vars ON gaming_rule_action_vars.rule_action_id = gaming_rule_actions.rule_action_id
      JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id=gaming_rule_action_vars.rule_action_type_var_id
      WHERE gaming_rule_actions.rule_id=ruleId AND gaming_rule_action_types_var_types.name = 'BadgeID'
    );

    -- Notification Actions
    SELECT notification_subscription_id, description, url FROM notifications_subscriptions
    WHERE notification_subscription_id IN (
      SELECT value
      FROM gaming_rule_actions
      JOIN gaming_rule_action_vars ON gaming_rule_action_vars.rule_action_id = gaming_rule_actions.rule_action_id
      JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id=gaming_rule_action_vars.rule_action_type_var_id
      WHERE gaming_rule_actions.rule_id=ruleId AND gaming_rule_action_types_var_types.name = 'NotificationID'
    );
    
    SELECT license_type_id, name FROM gaming_license_type
    WHERE license_type_id IN (
      SELECT value
      FROM gaming_rule_actions
      JOIN gaming_rule_action_vars ON gaming_rule_action_vars.rule_action_id = gaming_rule_actions.rule_action_id
      JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id=gaming_rule_action_vars.rule_action_type_var_id
      WHERE gaming_rule_actions.rule_id=ruleId AND gaming_rule_action_types_var_types.name = 'LicenseType'
    );
    
    -- Action currency amounts (mainly for bonuses)
    SELECT gaming_rule_action_vars.rule_action_var_id, currency_value.currency_id, currency_value.value, gaming_currency.currency_code
    FROM gaming_rule_actions
    JOIN gaming_rule_action_vars ON gaming_rule_action_vars.rule_action_id = gaming_rule_actions.rule_action_id
    JOIN gaming_rule_action_var_currency_value AS currency_value ON gaming_rule_action_vars.rule_action_var_id = currency_value.rule_action_var_id
    JOIN gaming_currency ON currency_value.currency_id=gaming_currency.currency_id
	WHERE gaming_rule_actions.rule_id=ruleId;
    
	-- Chaining rules
	SELECT next_rule_id, continue_from_last_event 
	FROM gaming_rules_relations
	WHERE current_rule_id=ruleId;

    -- base currency
    SELECT currency_id FROM gaming_operators WHERE is_main_operator=1;
      
END$$

DELIMITER ;

