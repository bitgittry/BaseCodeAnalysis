DROP procedure IF EXISTS `BonusCheckLossOnWithdraw`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusCheckLossOnWithdraw`(balanceHistoryID BIGINT, clientStatID BIGINT)
root: BEGIN

   -- Added: TransactionWithdrawByUser which is need by push notification 

  DECLARE bonusEnabledFlag, isManualTransaction TINYINT(1) DEFAULT 0;
  DECLARE bonusLostCounterID, sessionID, clientStatIDCheck LONG DEFAULT -1;
  
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  SET sessionID=0;
  
  IF NOT (bonusEnabledFlag) THEN
    LEAVE root;
  END IF;
  
  SELECT client_stat_id INTO clientStatIDCheck
  FROM gaming_client_stats
  WHERE client_stat_id=clientStatID
  FOR UPDATE;
  
  SELECT IFNULL(is_manual_transaction, 0) INTO isManualTransaction
  FROM gaming_balance_history 
  WHERE balance_history_id=balanceHistoryID;
  
  INSERT INTO gaming_bonus_lost_counter (date_created)
  VALUES (NOW());
  
  SET bonusLostCounterID=LAST_INSERT_ID();
  
  INSERT INTO gaming_bonus_lost_counter_bonus_instances(bonus_lost_counter_id, bonus_instance_id)
  SELECT bonusLostCounterID, gaming_bonus_instances.bonus_instance_id
  FROM gaming_bonus_instances 
  STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_instances.bonus_rule_id
  WHERE (gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1) 
	AND (gaming_bonus_rules.forfeit_on_withdraw=1); 
  
  IF (ROW_COUNT() > 0) THEN 
    CALL BonusOnLostUpdateStats(bonusLostCounterID, IF(isManualTransaction, 'TransactionWithdrawByUser', 'TransactionWithdraw'), 
		balanceHistoryID, sessionID, 'Withdrawal',0, NULL);
  END IF;
  
END root$$

DELIMITER ;

