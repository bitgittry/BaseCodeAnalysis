DROP procedure IF EXISTS `PlayerGetVipDetails`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetVipDetails`(clientStatID BIGINT, OUT statusCode INT)
root:BEGIN
-- Status Code 1: Invalid Client Stat Id

DECLARE existingClientStatID BIGINT DEFAULT 0;

SET statusCode = 0;

SELECT client_stat_id INTO existingClientStatID FROM gaming_client_stats WHERE client_stat_id = clientStatID;
  IF (existingClientStatID = 0) THEN
    SET statusCode = 1;
    LEAVE root;
  END IF;

SELECT gc.vip_level_id, gc.vip_level, gvl.`name`, gcs.loyalty_points_running_total, gcs.loyalty_points_reset_date, gcs.total_loyalty_points_given, gvl.min_loyalty_points, gvl.max_loyalty_points
FROM gaming_client_stats gcs
JOIN gaming_clients gc
ON gcs.client_id = gc.client_id
JOIN gaming_vip_levels gvl
ON gvl.vip_level_id = gc.vip_level_id
WHERE gcs.client_stat_id = clientStatID;

END root$$

DELIMITER ;
;
