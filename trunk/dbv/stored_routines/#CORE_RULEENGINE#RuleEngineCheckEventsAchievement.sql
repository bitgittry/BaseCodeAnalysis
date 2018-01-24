DROP procedure IF EXISTS `RuleEngineCheckEventsAchievement`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleEngineCheckEventsAchievement`(ruleInstanceId BIGINT)
root: BEGIN
  
  DECLARE ruleId BIGINT; 
  DECLARE clientId BIGINT;   


         SELECT client_stat_id, rule_id INTO clientId, ruleId FROM gaming_rules_instances WHERE rule_instance_id=ruleInstanceId;
         

         -- when the number of "counting" criteria matches with the number of verified "counting" criteria the whole event is verified
         -- we have to check all the events, even the ones not directly related to the transaction that called the function, because they could be true for default
         UPDATE gaming_events_instances
         INNER JOIN (

          SELECT event_id, CASE WHEN count(res) = sum(res) THEN 1 ELSE 0 END AS res
          FROM (
          
          
          SELECT gaming_events.event_id, 

          case when 
            (criteria_name='DepositSum' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
            
          case when 
            (criteria_name='DepositCount' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 

          case when 
            (criteria_name='WithdrawalSum' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
            
          case when 
            (criteria_name='WithdrawalCount' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
          
          case when 
            (criteria_name='StakeSum' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
           
          case when 
            (criteria_name='StakeNumPlays' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
          
          
          case when 
            (criteria_name='StakeNumRounds' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
          
          
          case when 
            (criteria_name='PlayerRegisterDummy' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
          
         case when 
            (criteria_name='ReturnSum' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
           
          case when 
            (criteria_name='ReturnNumPlays' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
          
          
          case when 
            (criteria_name='ReturnNumRounds' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
          
          case when 
            (criteria_name='LoginCount' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
          
          
          case when 
            (criteria_name='LoginDuration' and 
              (
                (operator='equal' and gaming_re_event_criteria_instances.incr_result = lower_bound)
                OR (operator='greater' and gaming_re_event_criteria_instances.incr_result > lower_bound)
                OR (operator='greater_or_equal' and gaming_re_event_criteria_instances.incr_result >= lower_bound)
                OR (operator='less' and gaming_re_event_criteria_instances.incr_result < lower_bound)
                OR (operator='less_or_equal' and gaming_re_event_criteria_instances.incr_result <= lower_bound)
                OR (operator='between' and gaming_re_event_criteria_instances.incr_result between lower_bound and upper_bound)
              )
            )
          then 1 else 
          
          0 END END END END END END END END END END END END END as res
          from         
          (SELECT * FROM gaming_rules_instances WHERE rule_instance_id=ruleInstanceId AND client_stat_id=clientId) gaming_rules_instances
          JOIN gaming_rules on gaming_rules.rule_id=gaming_rules_instances.rule_id and gaming_rules.is_active=1 and gaming_rules.is_hidden=0 AND gaming_rules.rule_id=ruleId
          JOIN gaming_events on gaming_events.rule_id=gaming_rules.rule_id AND gaming_events.is_deleted=0
          JOIN gaming_re_event_criteria_config on gaming_re_event_criteria_config.event_id=gaming_events.event_id
          JOIN gaming_re_event_criteria on gaming_re_event_criteria.re_event_criteria_id=gaming_re_event_criteria_config.re_event_criteria_id
            AND gaming_re_event_criteria.is_filter=0
          LEFT JOIN (SELECT * FROM gaming_re_event_criteria_instances where rule_instance_id=ruleInstanceId) gaming_re_event_criteria_instances
                  ON gaming_re_event_criteria_instances.re_event_criteria_config_id=gaming_re_event_criteria_config.re_event_criteria_config_id
                  
                  
            ) dvtbl
            group by dvtbl.event_id) dvtbl2
             ON
                  gaming_events_instances.event_id=dvtbl2.event_id AND gaming_events_instances.rule_instance_id=ruleInstanceId AND client_stat_id=clientId 
          SET is_achieved=dvtbl2.res;



END root$$

DELIMITER ;

