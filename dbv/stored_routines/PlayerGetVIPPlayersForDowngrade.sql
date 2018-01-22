DROP procedure IF EXISTS `PlayerGetVIPPlayersForDowngrade`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetVIPPlayersForDowngrade`()
proc:BEGIN

	DECLARE downgradeIsEnabled, ruleIsEnabled TINYINT(1) DEFAULT 0;

	SELECT gs1.value_bool INTO downgradeIsEnabled FROM gaming_settings AS gs1 WHERE name='VIP_LOYALTY_POINTS_DOWNGRADE_ENABLED';
	SELECT gs1.value_bool INTO ruleIsEnabled FROM gaming_settings AS gs1 WHERE name='VIP_LOYALTY_POINTS_DOWNGRADE_RULES_ENABLED';

	IF (downgradeIsEnabled=0) THEN
		LEAVE proc;
	END IF;

	-- Players that must be checked
	SELECT gc.client_id, gcs.client_stat_id, gc.vip_level, vl.min_loyalty_points, gcs.loyalty_points_running_total
	FROM gaming_clients gc
	JOIN gaming_client_stats gcs ON gcs.client_id=gc.client_id
	JOIN gaming_vip_levels vl ON vl.vip_level_id=gc.vip_level_id AND vl.set_type='LoyaltyPointsPeriod' -- AND vl.min_loyalty_points > gcs.loyalty_points_running_total
	WHERE gc.vip_downgrade_disabled=0 AND gcs.loyalty_points_reset_date < NOW();

	IF (ruleIsEnabled=1) THEN
		SELECT 1;
	END IF;
END$$

DELIMITER ;