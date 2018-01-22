DROP procedure IF EXISTS `RuleEngineProcessNewTransactions`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleEngineProcessNewTransactions`()
root: BEGIN
  
  DECLARE res int; 
  DECLARE EventTypeId int;
  DECLARE done INT DEFAULT FALSE;
  DECLARE transactionTypeId INT; 
  DECLARE transactionId BIGINT;
  DECLARE transactionStatus INT;
  DECLARE ruleId BIGINT; 
  DECLARE ruleInstanceId BIGINT; 
  DECLARE clientId BIGINT;   
  DECLARE isLogActive, isReActive TINYINT(1);
  DECLARE hasError INT;

  
  DECLARE cur2 CURSOR FOR SELECT event_table_id, elem_id FROM gaming_event_rows where rule_engine_state=0 order by gaming_event_row_id limit 100;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET hasError = 1;
  

  call RuleEngine_TimingStart ('RuleEngineProcessNewTransactions');
  -- select value_bool INTO isReActive from gaming_settings where name='RULE_ENGINE_ENABLED';
  select value_bool INTO isLogActive from gaming_settings where name='RULE_ENGINE_LOG_ENABLED';
  
  IF (isLogActive=1)  THEN
    -- insert in gaming_event_rows all the player sessions closed still not processed
    INSERT INTO gaming_event_rows (event_table_id, elem_id)
      SELECT 4, session_id FROM sessions_main WHERE rule_engine_processed=0 AND date_closed IS NOT NULL AND user_id=1;
  END IF;
  UPDATE sessions_main SET rule_engine_processed=1 WHERE rule_engine_processed=0 AND date_closed IS NOT NULL AND user_id=1;
  
  -- reset rule istances of all the players that didn't achieve it within (x) days
  UPDATE gaming_rules_instances 
  INNER JOIN
  (SELECT gaming_rules_instances.rule_instance_id
          FROM gaming_rules_instances
          JOIN gaming_rules on gaming_rules.rule_id=gaming_rules_instances.rule_id and gaming_rules.is_active=1 and gaming_rules.is_hidden=0 AND gaming_rules_instances.is_current=1
          AND gaming_rules.days_to_achieve IS NOT NULL AND gaming_rules_instances.start_date IS NOT NULL
      WHERE DATEDIFF(NOW(), gaming_rules_instances.start_date)> gaming_rules.days_to_achieve) dvtbl
   ON dvtbl.rule_instance_id=gaming_rules_instances.rule_instance_id
      SET gaming_rules_instances.is_achieved=0, gaming_rules_instances.is_current=0;

  -- loop for all new unprocessed transactions
  OPEN cur2;
  read_loop2: LOOP
    FETCH cur2 INTO transactionTypeId, transactionId; 
    IF done THEN
      LEAVE read_loop2;
    END IF;
  
      --  select transactionTypeId, transactionId;
    
    -- 1	gaming_game_plays
    -- 2	gaming_balance_history
    -- 4	sessions_main
    -- 5	gaming_clients
    
    -- gaming_game_plays, affects bet and win criteria ------------------------------------------------------------------------------------
    IF (transactionTypeId=1) THEN
        SET res=1;
           CALL RuleEngineProcessTransactionStake (transactionId, isLogActive);
           CALL RuleEngineProcessTransactionStakeSB (transactionId, isLogActive);
           CALL RuleEngineProcessTransactionReturn (transactionId, isLogActive);
           CALL RuleEngineProcessTransactionReturnSB (transactionId, isLogActive);

    -- gaming_balance_history, affects deposit and withdrawal criteria   ------------------------------------------------------------------------------------
    ELSEIF (transactionTypeId=2) THEN
         SET res=2;
         CALL RuleEngineProcessTransactionDeposit (transactionId, isLogActive);
         CALL RuleEngineProcessTransactionWithdrawal (transactionId, isLogActive);
        
    ELSEIF (transactionTypeId=4) THEN
          SET res=4;
          CALL RuleEngineProcessTransactionLogin (transactionId, isLogActive);  
          
    ELSEIF (transactionTypeId=5) THEN
          SET res=5;
          CALL RuleEngineProcessTransactionPlayerRegistration (transactionId, isLogActive);  

    END IF;
    
    IF (isLogActive=1)  THEN
      UPDATE gaming_event_rows SET rule_engine_state=1, log=case when IFNULL(trim(log),'')='' then '(No active rule has a criteria affected by this transaction)' else log end where event_table_id=transactionTypeId AND elem_id=transactionId;
    ELSE
      DELETE FROM gaming_event_rows where event_table_id=transactionTypeId AND elem_id=transactionId;
    END IF;
    -- loop for each rule instance of the player to see if it has been achieved
    
    IF (hasError=1) THEN
      UPDATE gaming_event_rows SET `log`= CONCAT('SQL ERROR:', ERROR_MESSAGE(), ' ' , `log`) WHERE event_table_id=transactionTypeId AND elem_id=transactionId;
    END IF;
  END LOOP;
  CLOSE cur2;
  
  -- insert into the queue table for awarding
 INSERT INTO gaming_rules_to_award(rule_instance_id, awarded_state)
 SELECT rule_instance_id, 2
 FROM gaming_rules_instances 
 WHERE is_achieved = 1 AND is_processed = 0;
 
  -- update the is_proccesed to 1 which means the instance is added to be awarded
 UPDATE gaming_rules_instances SET is_processed = 1 WHERE is_achieved = 1 AND is_processed = 0;

  
  call RuleEngine_TimingStop ('RuleEngineProcessNewTransactions');
END root$$

DELIMITER ;

