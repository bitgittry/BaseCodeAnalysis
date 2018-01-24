DROP procedure IF EXISTS `CheckForPendingFutureDepositLimitsAndSendNotifications`;
DROP procedure IF EXISTS `TransferLimitChecksForFutureDepositLimitsAndSendNotifications`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransferLimitChecksForFutureDepositLimitsAndSendNotifications`()
BEGIN
  -- Added Notification accessible 
  
  DECLARE notificationEnabled TINYINT DEFAULT 0;
  
  SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';
  
  IF (notificationEnabled=1) THEN
	  INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
	  SELECT 54, gtlc.transfer_limit_client_id, gcs.client_id, 0
	  FROM gaming_transfer_limit_clients gtlc
      JOIN gaming_client_stats gcs ON gcs.client_stat_id = gtlc.client_stat_id
      WHERE gtlc.is_active = 1 AND gtlc.is_confirmed = 0 AND gtlc.end_date is NULL AND gtlc.start_date <= NOW() AND gtlc.notification_processed_release = 0
      ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
  END IF;
  
  # Mark pending future deposit limits, with start date passed as pushed for sending notification
  UPDATE gaming_transfer_limit_clients gtlc
  SET gtlc.notification_processed_release = 1
  WHERE is_active = 1 AND is_confirmed = 0 AND end_date IS NULL AND start_date<=NOW() AND notification_processed_release = 0;
	
END$$

DELIMITER ;

