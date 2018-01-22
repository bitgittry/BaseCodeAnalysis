DROP procedure IF EXISTS `PlayerBalanceThresholdUpdate`;

DELIMITER $$
 
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerBalanceThresholdUpdate`( clientStatID BIGINT, maxPlayerBalanceThreshold DECIMAL(18,5))
BEGIN

 UPDATE gaming_client_stats SET max_player_balance_threshold = maxPlayerBalanceThreshold WHERE client_stat_id = clientStatID;

 CALL NotificationEventCreate(540,clientStatID,NULL,0);
 
END$$

DELIMITER ;