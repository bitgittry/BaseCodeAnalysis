DROP procedure IF EXISTS `RuleEngineCheckRuleAchievement`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleEngineCheckRuleAchievement`(ruleInstanceId BIGINT, OUT Result TINYINT(1), OUT outLog varchar(2500))
root: BEGIN
  
  DECLARE ruleId BIGINT; 
  DECLARE clientId BIGINT;   
  DECLARE ruleQuery VARCHAR(2000);
  DECLARE eventId BIGINT;   
  DECLARE isAchieved TINYINT(1);
  DECLARE done INT DEFAULT FALSE;  
  DECLARE cur1 CURSOR FOR 
    SELECT event_id, is_achieved FROM gaming_events_instances WHERE rule_instance_id=ruleInstanceId order by length(event_id) desc;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;  

  SELECT client_stat_id, rule_id INTO clientId, ruleId FROM gaming_rules_instances WHERE rule_instance_id=ruleInstanceId;
  SELECT rule_query INTO ruleQuery FROM gaming_rules where rule_id=ruleId;

  SET outLog = ruleQuery;
  OPEN cur1;
  read_loop: LOOP
    FETCH cur1 INTO eventId, isAchieved;
    IF done THEN 
      LEAVE read_loop;
    END IF;
    SET ruleQuery=replace(ruleQuery, CAST(eventId AS CHAR), CAST(isAchieved AS CHAR));
    
  END LOOP;
  CLOSE cur1;

  SET outLog = CONCAT(outLog, '=', ruleQuery);
  
  SET @res=0;
  SET @convFormula=CONCAT('select case when ', replace(replace(ruleQuery,'|',' or '), '&',' and '),' then 1 else 0 end INTO @res;' );
  
  PREPARE stmt FROM @convFormula;
  EXECUTE stmt;
  DEALLOCATE PREPARE stmt; 
  SET Result=@res;


END root$$

DELIMITER ;

