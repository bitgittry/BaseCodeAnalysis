DROP procedure IF EXISTS `BonusGetBonusLostRingFencedAmount`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetBonusLostRingFencedAmount`(bonusLostCounterID BIGINT)
BEGIN

	SELECT gaming_client_stats.client_stat_id,ext_client_id, SUM(gaming_bonus_losts.bonus_amount) AS bonus_amount,
	SUM(gaming_bonus_losts.bonus_win_locked_amount) AS bonus_win_locked_amount, SUM(IF(ring_fenced_by_bonus_rules,gaming_bonus_losts.ring_fenced_amount,0)) AS bon_ring_fenced_amount,
	IFNULL(SUM(IF(ring_fenced_by_license_type=3,gaming_bonus_losts.ring_fenced_amount,0)),0) AS ring_fenced_sb,IFNULL(SUM(IF(ring_fenced_by_license_type=1,gaming_bonus_losts.ring_fenced_amount,0)),0) AS ring_fenced_casino,
	IFNULL(SUM(IF(ring_fenced_by_license_type=2,gaming_bonus_losts.ring_fenced_amount,0)),0) AS ring_fenced_poker
	FROM gaming_bonus_lost_counter_bonus_instances
	JOIN gaming_bonus_losts ON gaming_bonus_losts.bonus_instance_id = gaming_bonus_lost_counter_bonus_instances.bonus_instance_id
	JOIN gaming_bonus_instances ON gaming_bonus_lost_counter_bonus_instances.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
	LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
	JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id = gaming_client_stats.client_stat_id
	JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id
	WHERE gaming_bonus_lost_counter_bonus_instances.bonus_lost_counter_id = bonusLostCounterID
	GROUP BY client_stat_id;

	SELECT gaming_client_stats.client_stat_id,gaming_bonus_instances.bonus_instance_id,gaming_bonus_instances.bonus_rule_id, gaming_bonus_losts.bonus_amount AS bonus_amount,
	gaming_bonus_losts.bonus_win_locked_amount AS bonus_win_locked_amount, IF(ring_fenced_by_bonus_rules,gaming_bonus_losts.ring_fenced_amount,0) AS bon_ring_fenced_amount,
	IFNULL(IF(ring_fenced_by_license_type=3,gaming_bonus_losts.ring_fenced_amount,0),0) AS ring_fenced_sb,IFNULL(IF(ring_fenced_by_license_type=1,gaming_bonus_losts.ring_fenced_amount,0),0) AS ring_fenced_casino,
	IFNULL(IF(ring_fenced_by_license_type=2,gaming_bonus_losts.ring_fenced_amount,0),0) AS ring_fenced_poker,
	gaming_bonus_instances.cw_free_round_id
	FROM gaming_bonus_lost_counter_bonus_instances
	JOIN gaming_bonus_losts ON gaming_bonus_losts.bonus_instance_id = gaming_bonus_lost_counter_bonus_instances.bonus_instance_id
	JOIN gaming_bonus_instances ON gaming_bonus_lost_counter_bonus_instances.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
	LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
	JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id = gaming_client_stats.client_stat_id
	JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id
	WHERE gaming_bonus_lost_counter_bonus_instances.bonus_lost_counter_id = bonusLostCounterID;

END$$

DELIMITER ;

