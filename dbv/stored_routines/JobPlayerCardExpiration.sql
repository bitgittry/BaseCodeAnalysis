
DROP procedure IF EXISTS `JobPlayerCardExpiration`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `JobPlayerCardExpiration`(jobRunID BIGINT, sessionID BIGINT)
root: BEGIN
	
    -- CPREQ-43 Daily job to set card status to expired
      
	DECLARE v_jobName VARCHAR(50) DEFAULT 'JobPlayerCardExpiration';
	DECLARE v_notificationEnabled TINYINT(1) DEFAULT 0;
    DECLARE v_daysBeforeExpireNotification, v_monthsBeforeExpiration INT DEFAULT 0;
    DECLARE v_clientId BIGINT DEFAULT 0;
    DECLARE v_playerCard BIGINT UNSIGNED;
    DECLARE v_cardFee DECIMAL(18,5);
	DECLARE v_finished,v_autoissueVirtualCard,v_numofcards INT DEFAULT 0;
    DECLARE v_dateNow, v_dateAboutToExpire DATETIME DEFAULT NOW();
    
     -- declare cursor for employee email
	DECLARE v_expiredCardsCursor CURSOR FOR 
		SELECT playercard_cards_id, client_id  
        FROM gaming_playercard_cards FORCE INDEX (expiry_status_date)
		WHERE is_expiration_unlimited = 0 AND card_status = 0 AND expiration_date <= v_dateNow;
	
    -- declare NOT FOUND handler
	DECLARE CONTINUE HANDLER 
        FOR NOT FOUND SET v_finished = 1;
        
    SELECT gs1.value_bool INTO v_notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';
      
   	-- get default values
    SELECT 
		MAX(IF(name = 'fee_default', value_dec,NULL)), 
		MAX(IF(name = 'notification_days_before_expiration', value_int, NULL)), 
        MAX(IF(name = 'autoissue_virtual_card', value_int, NULL)), 
        MAX(IF(name = 'months_before_expiration', value_int, NULL)) 
    INTO v_cardFee, v_daysBeforeExpireNotification, v_autoissueVirtualCard, v_monthsBeforeExpiration
		FROM gaming_playercard_settings;
    
    IF (v_notificationEnabled = 1) THEN 
    
		-- add notifications for card expired
        INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing, is_portal)
		SELECT 606, playercard_cards_id, client_id, 0, 0
        FROM gaming_playercard_cards FORCE INDEX (expiry_status_date)
		WHERE is_expiration_unlimited = 0 AND card_status = 0 AND expiration_date <= v_dateNow
		ON DUPLICATE KEY UPDATE event2_id = VALUES(event2_id), is_processing=VALUES(is_processing);
        
        SET v_dateAboutToExpire = DATE_ADD(v_dateNow, INTERVAL v_daysBeforeExpireNotification DAY);
        
   		-- add notifications for card about to expire
        INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing, is_portal)
		SELECT 607, playercard_cards_id, client_id, 0, 0 
        FROM gaming_playercard_cards FORCE INDEX (expiry_status_date)
		WHERE is_expiration_unlimited = 0 AND card_status = 0 AND expiration_date < v_dateAboutToExpire
		ON DUPLICATE KEY UPDATE event2_id = VALUES(event2_id), is_processing=VALUES(is_processing);
        
    END IF;
      
	-- cursor to cicle all expired cards
	OPEN v_expiredCardsCursor;
		get_cards: LOOP
	 
		SET v_finished = 0;
		FETCH v_expiredCardsCursor INTO v_playerCard, v_clientId;
		
		IF v_finished = 1 THEN 
			LEAVE get_cards;
		END IF;
        
    	-- set cards to status expired
		UPDATE gaming_playercard_cards 
        SET card_status = 1
		WHERE v_playerCard = playercard_cards_id;
	
	    
	END LOOP get_cards;
	CLOSE v_expiredCardsCursor;
    
    
END root$$

DELIMITER ;

