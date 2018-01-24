DROP procedure IF EXISTS `RuleUpdateRuleInstanceNCheckForChainingRule`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleUpdateRuleInstanceNCheckForChainingRule`(idArray TEXT)
root:BEGIN
  -- Optimized
  -- Removing counter entry to mimimize table
  -- Added the next interval in SP
  -- Fully optimized 
  
  DECLARE nowDate DATETIME;
  DECLARE counterID, counterIDInterval, counterIDChaining BIGINT DEFAULT 0;
  DECLARE numRulesInstancesToCreate, numRulesInstancesToCreateWithRelations BIGINT DEFAULT 0;
  
  SET nowDate = NOW();
  
  CALL RulesQueueAwards(idArray,',');
  
  SELECT COUNT(*), COUNT(gaming_rules_relations.current_rule_id)
  INTO numRulesInstancesToCreate, numRulesInstancesToCreateWithRelations
  FROM gaming_rules_to_award FORCE INDEX (awarded_state)
  STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_to_award.awarded_state=0 
	AND gaming_rules_instances.rule_instance_id=gaming_rules_to_award.rule_instance_id   
  LEFT JOIN gaming_rules_relations ON gaming_rules_relations.current_rule_id=gaming_rules_instances.rule_id;

  UPDATE gaming_rules_to_award FORCE INDEX (awarded_state)
  STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_to_award.awarded_state=0 
	AND gaming_rules_instances.rule_instance_id=gaming_rules_to_award.rule_instance_id
  SET gaming_rules_instances.is_achieved=1, gaming_rules_instances.is_current=0;	

  UPDATE gaming_rules_to_award FORCE INDEX (awarded_state)
  STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_to_award.awarded_state=0 
	AND gaming_rules_instances.rule_instance_id=gaming_rules_to_award.rule_instance_id
  STRAIGHT_JOIN gaming_events_instances ON
	gaming_events_instances.rule_instance_id=gaming_rules_instances.rule_instance_id
  SET gaming_events_instances.is_current=0;		

  -- Next Interval
  IF (numRulesInstancesToCreate > 0) THEN

	-- Update how many times the rule was achieved
	UPDATE 
    (
		SELECT gaming_rules_instances.rule_id, COUNT(*) AS num_achieved_now
		FROM gaming_rules_to_award FORCE INDEX (awarded_state)
		STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_to_award.awarded_state=0 AND 
			gaming_rules_instances.rule_instance_id=gaming_rules_to_award.rule_instance_id  
		GROUP BY gaming_rules_instances.rule_id
    ) AS XX
    STRAIGHT_JOIN gaming_rules ON gaming_rules.rule_id=XX.rule_id
	SET gaming_rules.amount_achieved = gaming_rules.amount_achieved + XX.num_achieved_now;
  

	INSERT INTO gaming_rules_instances_counter (date_created) VALUES (NOW());
	SET counterIDInterval=LAST_INSERT_ID();    

	INSERT INTO gaming_rules_instances (client_stat_id, rule_id, is_current, date_created, end_date, rule_instance_counter_id, start_date)
	SELECT gri.client_stat_id, gri.rule_id , 1, NOW(),
		IF(days_to_achieve IS NOT NULL, DATE_ADD(NOW(), INTERVAL gr.days_to_achieve DAY), NULL), counterIDInterval,
        DateGetNextIntervalStart(gaming_query_date_interval_types.name)
	FROM gaming_rules_to_award FORCE INDEX (awarded_state)
    STRAIGHT_JOIN gaming_rules_instances AS gri ON 
		gaming_rules_to_award.awarded_state=0 AND 
        gri.rule_instance_id=gaming_rules_to_award.rule_instance_id
	STRAIGHT_JOIN gaming_rules AS gr ON gr.rule_id = gri.rule_id
	STRAIGHT_JOIN (
		-- Can by optimized by having gaming_rules_players (rule_id, client_stat_id, num_times_achieved)
        SELECT COUNT(*) AS player_achieved 
        FROM gaming_rules_to_award
		STRAIGHT_JOIN gaming_rules_instances AS gri ON 
			gaming_rules_to_award.awarded_state=0 AND 
			gri.rule_instance_id=gaming_rules_to_award.rule_instance_id
		STRAIGHT_JOIN gaming_rules_instances AS gri_achieved ON
			gri_achieved.rule_id=gri.rule_id AND gri_achieved.client_stat_id=gri.client_stat_id AND gri_achieved.is_achieved=1
	) AS achieveCount ON 1=1
	LEFT JOIN gaming_query_date_interval_types ON gaming_query_date_interval_types.query_date_interval_type_id=gr.query_interval_type_id
	WHERE
		gr.is_active AND (gr.end_date IS NULL OR gr.end_date>NOW()) AND
        IFNULL(gaming_query_date_interval_types.name, 'OneTime')!='OneTime' AND
		(gr.max_occurrences IS NULL OR (gr.amount_achieved < gr.max_occurrences)) AND 
        (gr.player_max_occurrences IS NULL OR (achieveCount.player_achieved < gr.player_max_occurrences));

	INSERT INTO gaming_events_instances (client_stat_id, rule_event_id, attr_value, rule_instance_id, is_achieved, has_failed)
	SELECT gri.client_stat_id, gaming_rules_events.rule_event_id, CONCAT('{"LastDateStr":"', gri.start_date, '"}'), 
		   gri.rule_instance_id, 0, 0
	FROM gaming_rules_instances AS gri FORCE INDEX (rule_instance_counter_id)
    STRAIGHT_JOIN gaming_rules_events ON gaming_rules_events.rule_id=gri.rule_id
    STRAIGHT_JOIN gaming_rules AS gr ON gr.rule_id = gri.rule_id
	WHERE gri.rule_instance_counter_id=counterIDInterval;

  END IF;

  -- Chaining of Rules with the Chaining Feature
  IF (numRulesInstancesToCreateWithRelations>0) THEN

	  INSERT INTO gaming_rules_instances_counter (date_created) VALUES (NOW());
	  SET counterIDChaining=LAST_INSERT_ID();    

	  INSERT INTO gaming_rules_instances (client_stat_id, rule_id, is_current, date_created, end_date, rule_instance_counter_id)
	  SELECT gaming_rules_instances.client_stat_id, gaming_rules_relations.next_rule_id, 1, nowDate, 
		IF (gaming_rules.days_to_achieve IS NULL OR gaming_rules.days_to_achieve<=0, NULL, DATE_ADD(nowDate, INTERVAL gaming_rules.days_to_achieve DAY)), counterIDChaining  
	  FROM gaming_rules_to_award FORCE INDEX (awarded_state)
	  STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_to_award.awarded_state=0 
		AND gaming_rules_instances.rule_instance_id=gaming_rules_to_award.rule_instance_id
	  STRAIGHT_JOIN gaming_rules ON gaming_rules_instances.rule_id=gaming_rules.rule_id
	  STRAIGHT_JOIN gaming_rules_relations ON gaming_rules.rule_id = gaming_rules_relations.current_rule_id;
	  
      INSERT INTO gaming_events_instances (client_stat_id, rule_event_id, attr_value, rule_instance_id, is_continous) 		 
	  SELECT gaming_rules_instances.client_stat_id, gaming_rules_events.rule_event_id
		, IF (gaming_rules_relations.continue_from_last_event AND pre_event_instance.attr_value IS NOT NULL, pre_event_instance.attr_value, '0'), 
        gaming_rules_instances.rule_instance_id, gaming_events.is_continous 
	  FROM gaming_rules_instances FORCE INDEX (rule_instance_counter_id)
	  STRAIGHT_JOIN gaming_rules_events ON gaming_rules_events.rule_id=gaming_rules_instances.rule_id 
	  STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id
      STRAIGHT_JOIN gaming_rules_to_award ON gaming_rules_to_award.awarded_state=0 		
		-- previous rule: to get gaming_rules_relations.continue_from_last_event and pre_event_instance.attr_value
	  STRAIGHT_JOIN gaming_rules_instances AS prev_rule_instance ON 
		prev_rule_instance.rule_instance_id=gaming_rules_to_award.rule_instance_id AND
		gaming_rules_instances.client_stat_id=prev_rule_instance.client_stat_id
	  STRAIGHT_JOIN gaming_rules_relations ON 
		prev_rule_instance.rule_id=gaming_rules_relations.current_rule_id AND 
		gaming_rules_instances.rule_id=gaming_rules_relations.next_rule_id
	  LEFT JOIN gaming_rules_events AS prev_rule_events ON 
		prev_rule_events.rule_id=prev_rule_instance.rule_id AND
		gaming_events.event_id=prev_rule_events.event_id
	  LEFT JOIN gaming_events_instances AS pre_event_instance ON 
		pre_event_instance.rule_instance_id=prev_rule_instance.rule_instance_id AND
		pre_event_instance.rule_event_id=prev_rule_events.rule_event_id 
	  WHERE gaming_rules_instances.rule_instance_counter_id=counterIDChaining AND gaming_rules_instances.is_current=1
	  GROUP BY gaming_rules_instances.client_stat_id, gaming_rules_events.rule_event_id; -- just as a precaution not to have duplicates
      
  END IF;

  UPDATE gaming_rules_to_award SET awarded_state=1 WHERE awarded_state=0;

END root$$

DELIMITER ;

