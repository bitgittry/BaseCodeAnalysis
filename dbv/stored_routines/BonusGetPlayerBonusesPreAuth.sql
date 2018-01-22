DROP procedure IF EXISTS `BonusGetPlayerBonusesPreAuth`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetPlayerBonusesPreAuth`(bonusInstancePreID BIGINT, clientStatID BIGINT)
BEGIN

  SELECT bonus_instance_pre_id, gbip.bonus_rule_id, gbr.name AS bonus_name, gbip.client_stat_id, gbip.priority, gbip.bonus_amount, gbip.wager_requirement_multiplier, gbip.wager_requirement, gbip.expiry_date_fixed, gbip.expiry_days_from_awarding,
   gbip.extra_id, gbip.award_selector, gbip.session_id, gbip.date_created, gbip.status AS status_code, IF(gbip.status=1,'Active',IF(gbip.status=2,'Accepted','Rejected')) AS status, um.username AS auth_user, gbip.reason, gbip.auth_reason, gbip.pre_expiry_date,
   gbip.cw_free_round_id	
  FROM gaming_bonus_instances_pre AS gbip
  JOIN gaming_bonus_rules AS gbr ON gbip.bonus_rule_id=gbr.bonus_rule_id
  LEFT JOIN users_main AS um ON gbip.auth_user_id=um.user_id
  WHERE gbip.client_stat_id=clientStatID AND ((bonusInstancePreID=0 AND gbip.status=1) OR bonus_instance_pre_id=bonusInstancePreID);

END$$

DELIMITER ;

