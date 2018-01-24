DROP procedure IF EXISTS `BonusRulesUpdateBonusTransfered`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusRulesUpdateBonusTransfered`()
BEGIN
    -- Do not set allow_awarding_bonuses if it is off  
    DECLARE awardedDateLast, awardedDateTo DATETIME DEFAULT NULL;
 
  UPDATE gaming_bonus_rules
  JOIN
  (
  select sum(bonus_transfered_total) AS bonus_transfered , bonus_rule_id from gaming_bonus_instances where IFNULL(bonus_transfered_total_recorded,0)=0 group by bonus_rule_id
  ) AS changes
  ON gaming_bonus_rules.bonus_rule_id = changes.bonus_rule_id
  SET added_to_real_money_total=IFNULL(added_to_real_money_total,0) + IFNULL(changes.bonus_transfered,0),
	   allow_awarding_bonuses=IF(program_cost_threshold=0 OR allow_awarding_bonuses=0,allow_awarding_bonuses,added_to_real_money_total + changes.bonus_transfered<program_cost_threshold);  
  UPDATE gaming_bonus_instances SET bonus_transfered_total_recorded=1;
 


    -- update bonuses awarded

    SELECT gaming_settings.value_date INTO awardedDateLast FROM gaming_settings WHERE gaming_settings.name = 'BONUS_AWARD_CHECK_DATE'; 
    SET awardedDateTo=DATE_SUB(NOW(), INTERVAL 1 SECOND);

    IF (awardedDateLast IS NOT NULL) THEN

		UPDATE gaming_bonus_rules
		JOIN (
		   SELECT gaming_bonus_instances.bonus_rule_id, COUNT(gaming_bonus_instances.bonus_instance_id) as awarded_times
		   FROM gaming_bonus_instances
		   WHERE gaming_bonus_instances.given_date BETWEEN awardedDateLast AND awardedDateTo 
		   GROUP BY gaming_bonus_instances.bonus_rule_id
		) AS bonus_instances on bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
		SET gaming_bonus_rules.awarded_times = gaming_bonus_rules.awarded_times + bonus_instances.awarded_times,
			allow_awarding_bonuses=IF(awarded_times_threshold IS NULL OR allow_awarding_bonuses=0, allow_awarding_bonuses, (gaming_bonus_rules.awarded_times + bonus_instances.awarded_times) < awarded_times_threshold); 

	   UPDATE gaming_settings
	   SET gaming_settings.value_date = DATE_ADD(awardedDateTo, INTERVAL 1 SECOND)
	  WHERE gaming_settings.name = 'BONUS_AWARD_CHECK_DATE';

   END IF;


END$$

DELIMITER ;

