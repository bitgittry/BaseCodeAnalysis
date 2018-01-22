DROP procedure IF EXISTS `LoyaltyPointsRedemptionForPlayer`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LoyaltyPointsRedemptionForPlayer`(clientStatId bigint)
BEGIN

    INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date)
	SELECT gaming_loyalty_redemption.player_selection_id, clientStatId, IFNULL(cache.player_in_selection, PlayerSelectionIsPlayerInSelection(gaming_loyalty_redemption.player_selection_id,clientStatId)) AS cache_new_value,
			IF(player_in_selection=1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = gaming_loyalty_redemption.player_selection_id)  MINUTE), expiry_date)
	FROM gaming_loyalty_redemption
    LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_loyalty_redemption.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatId
	WHERE gaming_loyalty_redemption.is_active=1 AND gaming_loyalty_redemption.player_selection_id IS NOT NULL AND cache.player_in_selection IS NULL 
	GROUP BY gaming_loyalty_redemption.player_selection_id	
    ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND gaming_player_selections_player_cache.expiry_date IS NULL, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
						    gaming_player_selections_player_cache.player_in_selection=IF(VALUES(player_in_selection), IF(gaming_player_selections_player_cache.expiry_date<NOW(),0,1), 0),
						    gaming_player_selections_player_cache.last_updated=NOW();

	SELECT lr.loyalty_redemption_id, lr.name, lr.description, lr.loyalty_redemption_prize_type_id, lrpt.prize_type, lr.extra_id, lr.loyalty_redemption_prize_id, lr.date_start, lr.date_end, lr.is_active, lr.is_current, lr.minimum_loyalty_points,
	lr.minimum_enrolment_age_days, lr.minimum_vip_level,  lr.is_open_to_all, lr.player_selection_id, lr.limited_offer_placings_balance, lr.free_rounds 
	FROM gaming_loyalty_redemption AS lr
	JOIN gaming_loyalty_redemption_prize_types AS lrpt ON lr.loyalty_redemption_prize_type_id=lrpt.loyalty_redemption_prize_type_id
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatId
	JOIN gaming_clients ON gaming_clients.client_id=gaming_client_stats.client_id AND 
		(lr.minimum_vip_level IS NULL OR lr.minimum_vip_level <= gaming_clients.vip_level) AND
		(lr.minimum_enrolment_age_days IS NULL OR gaming_clients.sign_up_date<=DATE_SUB(NOW(), INTERVAL lr.minimum_enrolment_age_days DAY))
	LEFT JOIN gaming_player_selections_player_cache AS pspc ON (pspc.player_selection_id=lr.player_selection_id AND pspc.client_stat_id=clientStatId AND pspc.player_in_selection=1) 
	WHERE lr.is_active=1 AND (IFNULL(pspc.client_stat_id,0)=clientStatId OR lr.is_open_to_all) AND (lr.limited_offer_placings_balance IS NULL OR lr.limited_offer_placings_balance>0)
		AND NOW() BETWEEN lr.date_start AND lr.date_end;
	
	SELECT c.loyalty_redemption_id, c.currency_id, c.amount, gc.currency_code 
    FROM gaming_loyalty_redemption AS lr	
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatId
	JOIN gaming_clients ON gaming_clients.client_id=gaming_client_stats.client_id AND 
		(lr.minimum_vip_level IS NULL OR lr.minimum_vip_level <= gaming_clients.vip_level) AND
		(lr.minimum_enrolment_age_days IS NULL OR gaming_clients.sign_up_date<=DATE_SUB(NOW(), INTERVAL lr.minimum_enrolment_age_days DAY))
	JOIN gaming_loyalty_redemption_currency_amounts AS c ON c.loyalty_redemption_id=lr.loyalty_redemption_id AND c.currency_id=gaming_client_stats.currency_id 
	JOIN gaming_currency AS gc ON c.currency_id=gc.currency_id
    LEFT JOIN gaming_player_selections_player_cache AS pspc ON (pspc.player_selection_id=lr.player_selection_id AND pspc.client_stat_id=clientStatId AND pspc.player_in_selection=1) 
	WHERE lr.is_active=1 AND (IFNULL(pspc.client_stat_id,0)=clientStatId OR lr.is_open_to_all) AND (lr.limited_offer_placings_balance IS NULL OR lr.limited_offer_placings_balance>0);



	SELECT b.loyalty_redemption_id, b.loyalty_badge_id 
    FROM gaming_loyalty_redemption AS lr
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatId
	JOIN gaming_clients ON gaming_clients.client_id=gaming_client_stats.client_id AND lr.minimum_vip_level <= gaming_clients.vip_level
	JOIN gaming_loyalty_redemption_badges_requirement AS b ON b.loyalty_redemption_id=lr.loyalty_redemption_id 
	LEFT JOIN gaming_player_selections_player_cache AS pspc ON (pspc.player_selection_id=lr.player_selection_id AND pspc.client_stat_id=clientStatId AND pspc.player_in_selection=1) 
	WHERE lr.is_active=1 AND (IFNULL(pspc.client_stat_id,0)=clientStatId OR lr.is_open_to_all) AND (lr.limited_offer_placings_balance IS NULL OR lr.limited_offer_placings_balance>0);

END$$

DELIMITER ;

