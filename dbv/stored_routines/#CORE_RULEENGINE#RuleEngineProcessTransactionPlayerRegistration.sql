DROP procedure IF EXISTS `RuleEngineProcessTransactionPlayerRegistration`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleEngineProcessTransactionPlayerRegistration`(transactionId BIGINT, isLogActive TINYINT(1))
root: BEGIN


  -- ============================================================================================================================================================
  -- Player Registration
  -- ============================================================================================================================================================  
  -- First scope of this sp is to update the incremental status of criteria for all the players.
  -- Second scope is to prevent the creation of new rule instances for those player that are not eligible
  -- the input transaction (Registration) is checked against all the criteria that could be affected by it.
  -- when all criteria of an event are verified, the amount (and count) of the transaction is added and saved to table [gaming_re_event_criteria_instances]
  -- this table contains the incremental status of all the criteria for all the players.
  
  DECLARE done INT DEFAULT FALSE;
  DECLARE ruleId BIGINT; 
  DECLARE ruleInstanceId BIGINT; 
  DECLARE clientId BIGINT; 
  DECLARE varAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE achievementIntervalTypeId INT;
  DECLARE intervalDiff INT;
  DECLARE ruleInstanceEndDate Date;
  DECLARE amountAchieved INT;
  DECLARE maxoccurrences INT;
  DECLARE amountAchievedPlayer INT;
  DECLARE maxoccurrencesPlayer INT;
  DECLARE isAchieved TINYINT(1);
  DECLARE transactionDate Date;
  DECLARE dateCheck TINYINT(1);
  DECLARE playerSelectionCheck TINYINT(1);
  DECLARE logTxt varchar(2500) DEFAULT '';


  -- loop for all the active rules that have rule conditions verified for this transaction
  DECLARE cur1 CURSOR FOR 
    SELECT gaming_rules.rule_id, gcs.client_stat_id, gaming_rules_instances.rule_instance_id, gaming_rules.achievement_interval_type_id,
            gaming_rules.amount_achieved, gaming_rules.max_occurrences, gaming_rules_instances.achieve_counter, gaming_rules.player_max_occurrences, gc.sign_up_date,
          CASE WHEN (gc.sign_up_date between IFNULL(gaming_rules.start_date,'2001-01-01') and IFNULL(gaming_rules.end_date,'2399-01-01')) THEN 1 ELSE 0 END as date_check,
            CASE WHEN ((IFNULL(gaming_rules.player_selection_id,0)=0) OR EXISTS (SELECT player_selection_id FROM gaming_player_selections_player_cache 
                    WHERE client_stat_id=gc.client_id AND player_selection_id =IFNULL(gaming_rules.player_selection_id, 0) AND player_in_selection=1)) THEN 1 ELSE 0 END as player_selection_check            
        FROM 
          (SELECT gaming_rules.rule_id, gaming_rules.achievement_interval_type_id, gaming_rules.amount_achieved, gaming_rules.max_occurrences, gaming_rules.player_max_occurrences, 
            gaming_rules.start_date, gaming_rules.end_date, gaming_rules.player_selection_id FROM gaming_rules INNER JOIN gaming_events ON gaming_events.rule_id=gaming_rules.rule_id 
            WHERE gaming_events.event_type_id=8 AND is_active=1 AND is_hidden=0 GROUP BY gaming_rules.rule_id, gaming_rules.achievement_interval_type_id, gaming_rules.amount_achieved, 
            gaming_rules.max_occurrences, gaming_rules.player_max_occurrences, gaming_rules.start_date, gaming_rules.end_date, gaming_rules.player_selection_id) gaming_rules
          CROSS JOIN (SELECT * FROM gaming_clients WHERE client_id = transactionId AND is_active = 1 AND is_dormant_account = 0 AND is_account_closed = 0) as gc
          JOIN gaming_client_stats gcs ON gcs.client_id = gc.client_id
          LEFT JOIN gaming_rules_instances on gaming_rules.rule_id = gaming_rules_instances.rule_id 
              AND gaming_rules_instances.is_current = 1 
              AND gaming_rules_instances.is_achieved = 0 
              AND gaming_rules_instances.client_stat_id = gcs.client_stat_id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
  

  OPEN cur1;
  read_loop: LOOP
    FETCH cur1 INTO ruleId, clientId, ruleInstanceId, achievementIntervalTypeId, amountAchieved, maxoccurrences, amountAchievedPlayer, maxoccurrencesPlayer, transactionDate, dateCheck, playerSelectionCheck;
    IF done THEN 
      LEAVE read_loop;
    END IF;
    -- select ruleId, clientId, ruleInstanceId, achievementIntervalTypeId, amountAchieved, maxoccurrences, amountAchievedPlayer, maxoccurrencesPlayer, transactionDate, dateCheck, playerSelectionCheck;
    
    SET logTxt=CONCAT(logTxt, '//[REGISTRATION] RULE_', ruleId);
    IF dateCheck=0 THEN
      IF (isLogActive=1) THEN SET logTxt=CONCAT(logTxt,' (NOT_ACHIEVED) [outside rule date bounds]'); END IF;
    ELSE
      IF playerSelectionCheck=0 THEN
        IF (isLogActive=1) THEN SET logTxt=CONCAT(logTxt,' (NOT_ACHIEVED) [player not in selection]'); END IF;
      ELSE
        SELECT COUNT(rule_instance_id) INTO amountAchievedPlayer FROM gaming_rules_instances WHERE client_stat_id=clientId AND rule_id=ruleId AND is_achieved=1;
        -- creates a new instance only if the total number awarded till now is less than the max_occurrences available 
        IF (IFNULL(amountAchieved,0) >= IFNULL(maxoccurrences,9999999)) THEN
          IF (isLogActive=1) THEN SET logTxt=CONCAT(logTxt,' (NOT_ACHIEVED) [exceeded total max occurences ',amountAchieved,'/',maxoccurrences,']'); END IF;
          SET ruleInstanceId=null;
        ELSE        
          -- creates missing record in gaming_rules_instances for this player for this rule
          IF ruleInstanceId IS NULL THEN
          -- creates a new istance only if the option "Enable One Award Achievement per Interval" is satisfied
            SELECT end_date INTO ruleInstanceEndDate FROM gaming_rules_instances WHERE client_stat_id=clientId AND rule_id=ruleId AND is_achieved=1 ORDER BY end_date DESC LIMIT 1;
              -- the total number awarded to the player till now is less than the max_occurrences available for each player
              IF (IFNULL(amountAchievedPlayer,0) < IFNULL(maxoccurrencesPlayer,99999999)) THEN
                IF (ruleInstanceEndDate IS NULL)
                  OR (achievementIntervalTypeId IN (12,13))
                  OR (achievementIntervalTypeId=3 AND timestampdiff(day,ruleInstanceEndDate,transactionDate) > 0)
                  OR (achievementIntervalTypeId=4 AND timestampdiff(week,ruleInstanceEndDate,transactionDate) > 0)
                  OR (achievementIntervalTypeId=5 AND timestampdiff(month,ruleInstanceEndDate,transactionDate) > 0)
                  OR (achievementIntervalTypeId=6 AND timestampdiff(quarter,ruleInstanceEndDate,transactionDate) > 0)
                  OR (achievementIntervalTypeId=7 AND timestampdiff(year,ruleInstanceEndDate,transactionDate) > 0)
                THEN
                  INSERT INTO gaming_rules_instances (client_stat_id, rule_id, is_current, is_achieved, date_created)
                    SELECT clientId, ruleId, 1, 0, NOW();
                  SET ruleInstanceId=LAST_INSERT_ID();  
                ELSE
                  IF (isLogActive=1) THEN SET logTxt=CONCAT(logTxt,' (NOT_ACHIEVED) [achievement interval still not elapsed]'); END IF;
                END IF;                        
              ELSE
                IF (isLogActive=1) THEN SET logTxt=CONCAT(logTxt,' (NOT_ACHIEVED) [exceeded player max occurences ',amountAchievedPlayer,'/',maxoccurrencesPlayer,']'); END IF;
              END IF;
          END IF;
        END IF;
          
        -- ruleInstanceId is null when the player is not allowed to achieve another rule in the same period
        IF ruleInstanceId IS NOT NULL THEN
          SET logTxt=CONCAT(logTxt, ' INSTANCE_', ruleInstanceId);
          -- creates missing records in gaming_re_event_criteria_instances for this player, used to keep track of sums and counts criteria
          -- creates missing records  for all the event_types, because they could be in the rule configuration but without a transaction that allows to check them.
          -- for this reason all the events istances are created for all the event types         
          INSERT INTO gaming_re_event_criteria_instances (re_event_criteria_config_id, rule_instance_id, client_stat_id, event_id, State, incr_result)
          SELECT re_event_criteria_config_id, ruleInstanceId, clientId, event_id, 0, 0 FROM (
            SELECT gaming_re_event_criteria_config.re_event_criteria_config_id, clientId, re_event_criteria_instance_id, gaming_events.event_id
            from (select * from gaming_rules where rule_id=ruleId) gaming_rules
            join gaming_events on gaming_events.rule_id=gaming_rules.rule_id AND gaming_rules.is_active=1 AND gaming_rules.is_hidden=0 AND gaming_events.is_deleted=0
            join gaming_re_event_criteria_config on gaming_re_event_criteria_config.event_id=gaming_events.event_id
            join gaming_re_event_criteria on gaming_re_event_criteria.re_event_criteria_id=gaming_re_event_criteria_config.re_event_criteria_id AND gaming_re_event_criteria.is_filter=0
            LEFT JOIN (SELECT * FROM gaming_re_event_criteria_instances WHERE rule_instance_id=ruleInstanceId AND client_stat_id=clientId) gaming_re_event_criteria_instances
              ON gaming_re_event_criteria_instances.re_event_criteria_config_id=gaming_re_event_criteria_config.re_event_criteria_config_id
              ) dvtbl
          WHERE re_event_criteria_instance_id IS NULL;

          -- creates missing records in gaming_events_instances for this player, used to keep track of achieved events
          INSERT INTO gaming_events_instances (rule_instance_id, event_id, client_stat_id, is_achieved)
          SELECT ruleInstanceId, event_id, clientId, 0 FROM (
            SELECT gaming_events.event_id, gaming_events_instances.client_stat_id
            FROM (SELECT * FROM gaming_rules WHERE rule_id=ruleId AND is_active=1 AND is_hidden=0) gaming_rules 
            JOIN gaming_events 
              on gaming_events.rule_id=gaming_rules.rule_id AND gaming_events.is_deleted=0
            LEFT JOIN (SELECT event_id, client_stat_id FROM gaming_events_instances WHERE rule_instance_id=ruleInstanceId AND client_stat_id=clientId) gaming_events_instances
              ON gaming_events_instances.event_id=gaming_events.event_id
              ) dvtbl
          WHERE dvtbl.client_stat_id IS NULL;
 
          SET @logTxt='';
          SET @logTxt2='';
          
          -- updates totals and sums (statuses) when all the filter conditions are verified
          UPDATE gaming_re_event_criteria_instances
          
          INNER JOIN (
           SELECT gaming_re_event_criteria_instances.re_event_criteria_instance_id, gaming_re_event_criteria.criteria_name,
                   @logTxt2:=CONCAT(@logTxt2,' EV_', dvtbl2.event_id, '_', criteria_name,'+', case when criteria_name='PlayerRegisterDummy' THEN 1 END) FROM (
           
           -- when the number of criteria matches with the number of verified criteria the ev 
           SELECT event_id, @logTxt:=CONCAT(@logTxt, GROUP_CONCAT(CASE WHEN res=1 THEN '' ELSE CONCAT(' EV_', event_id, '_', criteria_name,'=FAILED') END SEPARATOR '')),
            CASE WHEN count(res) = sum(res) THEN 1 ELSE 0 END AS res FROM (
           -- check of every single criteria
          SELECT gaming_events.event_id, criteria_name,
            -- the criteria of type "function" are always true and they are needed to return the event_id even when the event has no filter criteria to check
            case when gaming_re_event_criteria.is_filter=0 then 1 else

            case when 
              (criteria_name='PlayerRegisterDate' and 
                (
                  (operator='on' and datediff(gaming_clients.sign_up_date, filter_date_from)=0)
                  OR (operator='between' and gaming_clients.sign_up_date between filter_date_from and filter_date_to)
                  OR (operator='until' and datediff(gaming_clients.sign_up_date, filter_date_from)<=0)
                )
              )
            then 1 else 

            0 END END  AS res
            FROM      
            gaming_clients 
            JOIN gaming_rules_instances ON gaming_clients.client_id=transactionId  AND rule_instance_id=ruleInstanceId
            JOIN gaming_rules ON gaming_rules.rule_id=gaming_rules_instances.rule_id and gaming_rules.is_active=1 and gaming_rules.is_hidden=0 AND gaming_rules.rule_id=ruleId
            JOIN gaming_events ON gaming_events.rule_id=gaming_rules.rule_id AND gaming_events.is_deleted=0
            JOIN gaming_re_event_criteria_config ON gaming_re_event_criteria_config.event_id=gaming_events.event_id
            JOIN gaming_re_event_criteria ON gaming_re_event_criteria.re_event_criteria_id=gaming_re_event_criteria_config.re_event_criteria_id
              AND gaming_re_event_criteria.event_type_id=8
              ) dvtbl
             group by dvtbl.event_id

             ) dvtbl2 -- this returns event_id and result of the validation for each event_id
             
             
            -- join the events with all verified criteria ON the criteria of type "function" of the same event to update them accordingly
            LEFT JOIN gaming_re_event_criteria_config ON gaming_re_event_criteria_config.event_id=dvtbl2.event_id
            JOIN gaming_re_event_criteria ON gaming_re_event_criteria.re_event_criteria_id=gaming_re_event_criteria_config.re_event_criteria_id
             AND dvtbl2.res=1 AND gaming_re_event_criteria.criteria_name in ('PlayerRegisterDummy')
            JOIN gaming_re_event_criteria_instances ON gaming_re_event_criteria_instances.re_event_criteria_config_id=gaming_re_event_criteria_config.re_event_criteria_config_id
             AND gaming_re_event_criteria_instances.client_stat_id=clientId) dvtbl3
                   ON
                      dvtbl3.re_event_criteria_instance_id= gaming_re_event_criteria_instances.re_event_criteria_instance_id
            SET incr_result=IFNULL(incr_result,0) + 1;

          -- Checks all the events of the rule and marks the validated ones
          CALL RuleEngineCheckEventsAchievement(ruleInstanceId);
          CALL RuleEngineCheckRuleAchievement(ruleInstanceId, isAchieved, @out);
          IF CONCAT( @logTxt,  @logTxt2)='' THEN
            SET @logTxt='No criteria';
          END IF;
          SET logTxt=CONCAT(logTxt, CASE WHEN isAchieved=1 THEN ' (ACHIEVED) ' ELSE ' (NOT_ACHIEVED) ' END, @out, ' {', @logTxt, ' ', @logTxt2, '}');
          IF (isAchieved=1) THEN
            UPDATE gaming_rules_instances SET is_achieved=1, end_date=NOW(), is_current=0 WHERE is_achieved=0 AND rule_instance_id=ruleInstanceId;
            UPDATE gaming_rules SET amount_achieved=amount_achieved+1 WHERE rule_id=ruleId;
          END IF;
          
        
        END IF; -- ruleInstanceId exists
      END IF;  -- playerSelectionCheck 
    END IF;  -- rule dateCheck
  END LOOP; -- end of the rules loop
  CLOSE cur1;
      
  IF (isLogActive=1) AND (clientId IS NOT NULL) THEN 
    UPDATE gaming_event_rows SET client_id=clientId, `log`=CONCAT(`log`,' ',logTxt) WHERE event_table_id=5 AND elem_id=transactionId; 
  END IF;      
END root$$

DELIMITER ;