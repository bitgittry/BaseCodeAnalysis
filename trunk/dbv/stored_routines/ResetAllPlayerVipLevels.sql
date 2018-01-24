DROP procedure IF EXISTS `ResetAllPlayerVipLevels`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `ResetAllPlayerVipLevels`(OUT statusCode INT)
root:BEGIN

    -- Improved Looping  

	DECLARE batchSize INT DEFAULT NULL;
	DECLARE maxVIPLevelID, minVIPLevelID, maxVIPLevelMaxVIP, minVIPLevelMinVIP, maxVIPLevelIDMinLevel, minVIPLevelMinLP, maxVIPLevelMinLP INT DEFAULT NULL;
    DECLARE clientIDMax, currentBatch BIGINT DEFAULT 0;
    DECLARE loyaltyType VARCHAR(80);
    
    SET batchSize = 10000;
    
	UPDATE gaming_locks SET in_use = 1 WHERE name = 'vip_level_update';
    
    SELECT 
       MIN(min_vip_level), 
	   MAX(max_vip_level), 
	   set_type,
	   (SELECT vip_level_id FROM gaming_vip_levels ORDER BY `order` LIMIT 1) as min_level_id,
	   (SELECT vip_level_id FROM gaming_vip_levels ORDER BY `order` DESC LIMIT 1) as max_level_id,
	   (SELECT min_vip_level FROM gaming_vip_levels ORDER BY `order` DESC LIMIT 1) as max_level_id_min_vip,
		MIN(min_loyalty_points),
		(SELECT max_loyalty_points FROM gaming_vip_levels ORDER BY `order` DESC LIMIT 1) as max_level_id_min_lp
	INTO minVIPLevelMinVIP, maxVIPLevelMaxVIP, loyaltyType, minVIPLevelID, maxVIPLevelID, maxVIPLevelIDMinLevel, minVIPLevelMinLP, maxVIPLevelMinLP
	FROM gaming_vip_levels
	WHERE set_type!='Manual';
    
    SET loyaltyType=IF(loyaltyType IS NULL OR loyaltyType='', 'LoyaltyPointsPeriod', loyaltyType);
    
    UPDATE gaming_locks SET in_use = 0 WHERE name = 'vip_level_update';
    
    playerLoop: LOOP
    
		SELECT in_use INTO statusCode FROM gaming_locks WHERE name = 'vip_level_update' FOR UPDATE;
        
        IF (statusCode = 1) THEN 
			LEAVE root;
        END IF;
        
		UPDATE gaming_locks SET in_use = 1 WHERE name = 'vip_level_update';
        
        SET currentBatch=(SELECT MIN(client_id) FROM gaming_clients WHERE client_id>currentBatch AND is_account_closed=0);
        
        IF (currentBatch IS NULL) THEN
			LEAVE playerLoop;
        END IF;

		IF (loyaltyType = 'LoyaltyPointsPeriod') THEN
			UPDATE gaming_clients gc FORCE INDEX (PRIMARY)
			LEFT JOIN gaming_vip_levels lvl ON gc.vip_level BETWEEN lvl.min_vip_level AND lvl.max_vip_level
			SET
				gc.vip_level = CASE 
								WHEN lvl.vip_level_id IS NULL AND gc.vip_level < minVIPLevelMinVIP THEN 0
								WHEN lvl.vip_level_id IS NULL AND gc.vip_level >= maxVIPLevelIDMinLevel THEN maxVIPLevelIDMinLevel
								ELSE IFNULL(lvl.min_vip_level,0)
							END,
				gc.vip_level_id = CASE 
								WHEN lvl.vip_level_id IS NULL AND gc.vip_level < minVIPLevelMinVIP THEN NULL
								WHEN lvl.vip_level_id IS NULL AND gc.vip_level >= maxVIPLevelIDMinLevel THEN maxVIPLevelID
								ELSE lvl.vip_level_id
							END
			WHERE gc.client_id BETWEEN currentBatch AND currentBatch + batchSize AND gc.is_account_closed=0;

			IF (loyaltyType = 'LoyaltyPointsPeriod') THEN
				UPDATE gaming_clients gc
				STRAIGHT_JOIN gaming_client_stats gcs FORCE INDEX (client_id) ON gcs.client_id = gc.client_id AND gcs.is_active = 1
				LEFT JOIN gaming_vip_levels lvl ON gc.vip_level_id=lvl.vip_level_id
				SET 
					gcs.loyalty_points_running_total = 0,
					gcs.loyalty_points_reset_date = IF(lvl.period_in_days IS NULL, NULL, DATE_FORMAT(DATE(DATE_ADD(NOW(), INTERVAL lvl.period_in_days DAY)), "%Y-%m-%d 23:59:59"))
				WHERE gc.client_id BETWEEN currentBatch AND currentBatch + batchSize AND gc.is_account_closed=0;
			END IF;

        ELSEIF (loyaltyType = 'LoyaltyPointsLifeTime') THEN           
			UPDATE gaming_clients gc FORCE INDEX (PRIMARY)
			STRAIGHT_JOIN gaming_client_stats gcs FORCE INDEX (client_id) ON gcs.client_id = gc.client_id AND gcs.is_active = 1
			LEFT JOIN gaming_vip_levels lvl ON gcs.total_loyalty_points_given BETWEEN lvl.min_loyalty_points AND IFNULL(lvl.max_loyalty_points, 99999999999)
			SET
				gc.vip_level = CASE 
								WHEN lvl.vip_level_id IS NULL AND gcs.total_loyalty_points_given < minVIPLevelMinLP  THEN 0
								WHEN lvl.vip_level_id IS NULL AND gcs.total_loyalty_points_given >= maxVIPLevelMinLP THEN maxVIPLevelIDMinLevel
								ELSE IFNULL(lvl.min_vip_level,0)
							END,
				gc.vip_level_id = CASE 
								WHEN lvl.vip_level_id IS NULL AND gcs.total_loyalty_points_given < minVIPLevelMinLP THEN NULL
								WHEN lvl.vip_level_id IS NULL AND gcs.total_loyalty_points_given >= maxVIPLevelMinLP THEN maxVIPLevelID
								ELSE lvl.vip_level_id
							END
			WHERE gc.client_id BETWEEN currentBatch AND currentBatch + batchSize AND gc.is_account_closed=0;

        END IF;
        
        -- Prepare for next batch
        SET currentBatch = currentBatch + batchSize;
		UPDATE gaming_locks SET in_use = 0 WHERE name = 'vip_level_update';
		
		COMMIT AND CHAIN;
        
	END LOOP playerLoop;
    
    UPDATE gaming_locks SET in_use = 0 WHERE name = 'vip_level_update';
    
END root$$

DELIMITER ;

